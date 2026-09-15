"""Generate package and license evidence reports from Bazel targets.

Load `report` from `@rules_supply_chain//:defs.bzl`.
The module supplies its own collector, jq filters, and digest script.
Reports check evidence structure and consistency.
They do not approve licenses or establish legal permissions.
"""

load("@jq.bzl//jq:jq.bzl", "jq")
load("//private:collect.bzl", "inventory")
load("//private:legal_scope.bzl", _legal_scope = "legal_scope")

legal_scope = _legal_scope

def report(
        name,
        roots,
        expected_packages = [],
        evidence = [],
        overlay_evidence = {},
        required_overlay_packages = [],
        package_evidence = [],
        schema_defs = [],
        testonly = False):
    """Create metadata, coverage, notices, and a structural check.

    The target is a filegroup with five outputs under `<name>/`.
    Identical inputs produce identical output bytes.
    JSON reports refer to the local JSON Schema bundle.

    | Output | Contents |
    | --- | --- |
    | `metadata.json` | Package identities, graph relationships, digests, and evidence text |
    | `coverage.json` | Missing evidence, unresolved terms, and conflicts |
    | `notices.txt` | Package index and exact license and notice text |
    | `check.json` | Structural check result |
    | `schema.json` | JSON Schema bundle for reports and audit inputs |

    The macro declares `<name>_inventory`, `<name>_metadata`, `<name>_coverage`, `<name>_notices`, `<name>_check`, and `<name>_schema` targets.
    Use the combined target to build all outputs and run the structural check.
    A failed structural check fails the build of the combined target.
    Missing legal evidence remains a coverage gap unless a structural requirement fails.
    The report does not assign the module MIT license to consumer inputs.

    Evidence labels can identify files or filegroups.
    Overlay associations use exact package URLs (PURLs).
    Different packages can share evidence files.
    Repository names, filenames, and report scope names do not determine overlay associations.

    Example:

    ```starlark
    load("@rules_supply_chain//:defs.bzl", "report")

    report(
        name = "dependencies",
        roots = ["//app:binary"],
        expected_packages = ["pkg:generic/example@1.0.0"],
        overlay_evidence = {
            "pkg:generic/example@1.0.0": ["origin.txt"],
        },
        required_overlay_packages = ["pkg:generic/example@1.0.0"],
    )
    ```

    The example requires the root graph to supply the expected package identity.

    Args:
        schema_defs: JSON Schema files with additional definitions. Duplicate definition names fail the build.
        testonly: Allow test targets as report inputs.
        package_evidence: Adapter targets that supply PackageEvidenceInfo records and evidence files.
            Records must identify targets reachable from this report.
        name: A string that sets the report scope, target name, and output directory.
        roots: A label list that selects the dependency graph roots.
            The collector reads their source dependencies and package providers.
            An empty list produces an empty report unless explicit evidence supplies files.
        expected_packages: A list of PURL strings that the structural check requires.
            The check fails if the report lacks an expected identity.
            This argument does not create package metadata.
        evidence: A label list of additional source, manifest, license, or notice files to digest.
            This argument does not associate files with specific package identities.
        overlay_evidence: A dictionary from PURL strings to lists of evidence labels.
            The collector digests the files and records each explicit package association.
            This argument does not create package metadata or approve legal terms.
        required_overlay_packages: A list of PURL strings that must have overlay evidence.
            The check fails if a package is absent or its overlay association has no files.
    """
    jq(
        name = name + "_schema",
        testonly = testonly,
        srcs = [Label("//:schema")] + schema_defs,
        filter_file = Label("//private:schema.jq"),
        args = ["--slurp", "--sort-keys"],
        out = name + "/schema.json",
    )
    bindings = {}
    for purl, labels in overlay_evidence.items():
        for label in labels:
            bindings.setdefault(label, []).append(purl)
    inventory(
        name = name + "_inventory",
        testonly = testonly,
        roots = roots,
        scope = name,
        evidence = evidence,
        package_evidence = package_evidence,
        expected_packages = expected_packages,
        overlay_bindings = {label: json.encode(purls) for label, purls in bindings.items()},
    )
    jq(
        name = name + "_metadata",
        testonly = testonly,
        srcs = [":" + name + "_inventory"],
        data = [":" + name + "_schema"],
        expand_args = True,
        filter_file = Label("//private:metadata.jq"),
        args = ["--sort-keys", "--slurpfile", "schema", "$(location :" + name + "_schema)"],
        out = name + "/metadata.json",
    )
    jq(
        name = name + "_coverage",
        testonly = testonly,
        srcs = [":" + name + "_metadata"],
        filter_file = Label("//private:coverage.jq"),
        args = ["--sort-keys"],
        out = name + "/coverage.json",
    )
    jq(
        name = name + "_notices",
        testonly = testonly,
        srcs = [":" + name + "_metadata"],
        filter_file = Label("//private:notices.jq"),
        args = ["--join-output"],
        out = name + "/notices.txt",
    )
    jq(
        name = name + "_check",
        testonly = testonly,
        srcs = [":" + name + "_metadata", ":" + name + "_coverage"],
        filter_file = Label("//private:check.jq"),
        args = ["--slurp", "--exit-status", "--sort-keys", "--argjson", "required_overlay_packages", "'" + json.encode(required_overlay_packages).replace("'", "'\"'\"'") + "'"],
        out = name + "/check.json",
    )
    native.filegroup(
        name = name,
        testonly = testonly,
        srcs = [":" + name + "_metadata", ":" + name + "_coverage", ":" + name + "_notices", ":" + name + "_check", ":" + name + "_schema"],
    )
