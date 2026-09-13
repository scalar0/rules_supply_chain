"""Collect package providers and source relationships."""

load("@jq.bzl//jq/toolchain:toolchain.bzl", "TOOLCHAIN_TYPE")
load("@package_metadata//providers:package_metadata_info.bzl", "PackageMetadataInfo")
load("@rules_license//rules:providers.bzl", "LicenseInfo", "PackageInfo")

CollectionInfo = provider(
    doc = "Transitive source and package evidence collected from a Bazel target graph.",
    fields = {
        "files": "A depset of source Files and generated grammar Files to digest.",
        "metadata": "A depset of package metadata Files supplied by PackageMetadataInfo providers.",
        "nodes": "A depset of JSON strings that describe target dependencies, files, packages, and licenses.",
        "root": "The canonical label string for the collection root.",
        "texts": "A depset of license text Files to retain as evidence.",
    },
)

# These attributes carry product inputs or grammar conversion inputs.
_EDGES = ["srcs", "deps", "data", "sources", "actual", "compile_data", "grammars", "ir", "_emit", "_importer", "_importer_source", "_lock", "_tool"]
_METADATA = ["package_metadata"]

def _targets(value):
    if type(value) == "Target":
        return [value]
    if type(value) == "list":
        return [v for v in value if type(v) == "Target"]
    if type(value) == "dict":
        return [v for v in value.keys() if type(v) == "Target"]
    return []

def _collect_impl(target, ctx):
    files = []
    texts = []
    metadata = []
    packages = []
    licenses = []
    children = []
    edges = []
    helpers = []
    if ctx.rule:
        for attribute in _METADATA:
            helpers.extend(_targets(getattr(ctx.rule.attr, attribute, [])))

    # Explicit metadata roots must also appear in the module inventory.
    candidates = helpers + [target]
    for helper in candidates:
        if PackageMetadataInfo in helper:
            info = helper[PackageMetadataInfo]
            metadata.extend(info.files.to_list())
            packages.append({"file": info.metadata.short_path, "provider": "PackageMetadataInfo"})
        if PackageInfo in helper:
            info = helper[PackageInfo]
            packages.append({
                "declared_version": info.package_version or None,
                "name": info.package_name or None,
                "provider": "PackageInfo",
                "purl": info.purl or None,
                "repository_url": info.package_url or None,
            })
        if LicenseInfo in helper:
            info = helper[LicenseInfo]
            licenses.append({
                "declared_version": info.package_version or None,
                "file": info.license_text.short_path if info.license_text else None,
                "label": str(info.label),
                "name": info.package_name or None,
                "repository_url": info.package_url or None,
                "terms": [k.name for k in info.license_kinds],
            })
            if info.license_text:
                texts.append(info.license_text)
    is_helper = PackageMetadataInfo in target or PackageInfo in target or LicenseInfo in target
    if ctx.rule and not is_helper:
        for attribute in _EDGES:
            for dep in _targets(getattr(ctx.rule.attr, attribute, [])):
                if CollectionInfo in dep:
                    children.append(dep[CollectionInfo])
                    edges.append({"attribute": attribute, "target": dep[CollectionInfo].root})
    if DefaultInfo in target and not is_helper:
        # Reports digest source files and generated grammar inputs, but not executables.
        files.extend([f for f in target[DefaultInfo].files.to_list() if f.is_source or f.extension in ["ebnf", "xtext", "ungram"]])

    # buildifier: disable=attr-licenses
    node = json.encode({
        "dependencies": edges,
        "files": [f.short_path for f in files],
        "helper": is_helper,
        "kind": ctx.rule.kind if ctx.rule else "source_file",
        "label": str(target.label),
        # buildifier: disable=attr-licenses
        "licenses": licenses,
        "packages": packages,
    })
    return [CollectionInfo(
        root = str(target.label),
        nodes = depset([node], transitive = [c.nodes for c in children]),
        files = depset(files, transitive = [c.files for c in children]),
        texts = depset(texts, transitive = [c.texts for c in children]),
        metadata = depset(metadata, transitive = [c.metadata for c in children]),
    )]

collect = aspect(
    doc = """Collect package evidence along declared source and dependency attributes.

The aspect returns `CollectionInfo` for each visited target.
It reads package metadata and license providers without treating metadata helpers as product dependencies.
It includes source files and generated grammar inputs, and omits executable outputs from file evidence.
""",
    apply_to_generating_rules = True,
    implementation = _collect_impl,
    attr_aspects = _EDGES,
)

def _inventory_impl(ctx):
    collections = [target[CollectionInfo] for target in ctx.attr.roots]
    overlays = {}
    overlay_files = []
    for target, encoded_purls in ctx.attr.overlay_bindings.items():
        inputs = target[DefaultInfo].files.to_list()
        overlay_files.extend(inputs)
        for purl in json.decode(encoded_purls):
            overlays.setdefault(purl, []).extend([f.short_path for f in inputs])
    files = depset(ctx.files.evidence + overlay_files, transitive = [c.files for c in collections]).to_list()
    texts = depset(transitive = [c.texts for c in collections]).to_list()
    texts.extend([f for f in ctx.files.evidence if f.basename in ["Cargo.toml", "MODULE.bazel"] or f.basename.startswith("NOTICE") or "/LICENSES/" in f.short_path])
    text_paths = {f.path: True for f in texts}
    files = [f for f in files if f.path not in text_paths]
    metadata = depset(transitive = [c.metadata for c in collections]).to_list()
    nodes = depset(transitive = [c.nodes for c in collections]).to_list()
    manifest = ctx.actions.declare_file(ctx.label.name + ".manifest.json")
    ctx.actions.write(manifest, json.encode({
        "expected_packages": ctx.attr.expected_packages,
        "files": [{"kind": kind, "logical": f.short_path, "path": f.path} for kind, inputs in [("source", files), ("text", texts), ("metadata", metadata)] for f in inputs],
        "nodes": [json.decode(n) for n in nodes],
        "overlay_evidence": overlays,
        "roots": [str(t.label) for t in ctx.attr.roots],
        "schema_version": 1,
        "scope": ctx.attr.scope,
    }))
    output = ctx.actions.declare_file(ctx.label.name + ".json")
    jq = ctx.toolchains[TOOLCHAIN_TYPE].jqinfo.bin
    ctx.actions.run_shell(
        inputs = depset([manifest, ctx.file._digest] + files + texts + metadata),
        tools = [jq],
        outputs = [output],
        arguments = [ctx.file._digest.path, jq.path, manifest.path, output.path],
        command = 'bash "$1" "$2" "$3" "$4"',
        mnemonic = "SupplyChainEvidence",
    )
    return [DefaultInfo(files = depset([output]))]

inventory = rule(
    implementation = _inventory_impl,
    doc = """Collect and digest source evidence for a report scope.

The collect aspect supplies target relationships and package metadata from each root.
The action combines this data with explicit evidence and file digests.
`DefaultInfo` exposes `<name>.json`, a version 1 evidence inventory.
""",
    attrs = {
        "evidence": attr.label_list(allow_files = True, doc = "Additional source, manifest, license, or notice files to digest and retain as evidence."),
        "expected_packages": attr.string_list(doc = "Required package identities to record for later report checks."),
        "overlay_bindings": attr.label_keyed_string_dict(allow_files = True, doc = "Evidence labels mapped to JSON lists of package identities."),
        "roots": attr.label_list(aspects = [collect], doc = "Targets whose source dependencies and package providers define the inventory."),
        "scope": attr.string(mandatory = True, doc = "The report scope identifier stored in the inventory."),
        "_digest": attr.label(default = Label("//private:digest.sh"), allow_single_file = True),
    },
    toolchains = [TOOLCHAIN_TYPE],
)
