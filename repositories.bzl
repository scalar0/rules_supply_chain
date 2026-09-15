"""Fetch sources and generate metadata from the same module declarations."""

load("@bazel_tools//tools/build_defs/repo:git.bzl", "git_repository")
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_file")

def _metadata_impl(ctx):
    declarations = [
        'load("@rules_supply_chain//:source_metadata.bzl", "source_repository")',
        'package(default_visibility = ["//visibility:public"])',
        'exports_files(glob(["*.json"]))',
    ]
    for name, value in ctx.attr.sources.items():
        ctx.file(name + ".json", value + "\n")
        declarations.append("source_repository(name = %r, src = %r)" % (name, name + ".json"))
    ctx.file("BUILD.bazel", "\n".join(declarations) + "\n")

_metadata = repository_rule(
    implementation = _metadata_impl,
    attrs = {"sources": attr.string_dict()},
)

def _sources_impl(ctx):
    metadata = {}
    for module in ctx.modules:
        for source in module.tags.git:
            if source.name in metadata:
                fail("Duplicate source name: " + source.name)
            if bool(source.branch) == bool(source.commit):
                fail("Supply exactly one branch or commit for " + source.name)
            if source.commit and (len(source.commit) not in [40, 64] or any([c not in "0123456789abcdef" for c in source.commit.elems()])):
                fail("Supply a full lowercase commit ID for " + source.name)
            selector = {"commit": source.commit} if source.commit else {"branch": source.branch}
            git_repository(
                name = source.name,
                remote = source.remote,
                # Resolve the overlay owner without a dependency on the consumer module.
                # buildifier: disable=canonical-repository
                build_file_content = ctx.read(source.build_file).replace("@{owner}//", "@@%s//" % source.build_file.repo_name),
                sparse_checkout_patterns = source.sparse_checkout_patterns,
                **selector
            )
            metadata[source.name] = json.encode({
                "branch": source.branch or None,
                "kind": "git",
                "revision": source.commit or None,
                "url": source.remote,
            })
        for source in module.tags.http_file:
            if not source.urls or len(source.sha256) != 64 or any([c not in "0123456789abcdef" for c in source.sha256.elems()]):
                fail("Supply URLs and a SHA-256 checksum for " + source.name)
            if source.name in metadata:
                fail("Duplicate source name: " + source.name)
            http_file(
                name = source.name,
                urls = source.urls,
                sha256 = source.sha256,
                downloaded_file_path = source.downloaded_file_path,
            )
            metadata[source.name] = json.encode({
                "branch": None,
                "checksum": source.sha256,
                "kind": "http",
                "revision": None,
                "url": source.urls[0],
                "urls": source.urls,
            })
    _metadata(name = "source_repositories", sources = metadata)

sources = module_extension(
    implementation = _sources_impl,
    doc = """Fetch declared Git sources and expose their provenance as package metadata.

Each git tag creates a source repository with the supplied BUILD overlay.
Use @{owner}// in an overlay to reference the module that supplies the overlay.
The extension also creates `source_repositories` with one metadata target and JSON file per source name.
Import source repositories and `source_repositories` with `use_repo`.
Add `@source_repositories//:<name>` to each overlay's `default_package_metadata` list.
Source names must be unique across all tags processed by the extension.

Supply a branch for development or a commit for a fixed checkout.
Branch sources record a null revision.
HTTP sources record their declared URLs and checksum.
Metadata comes from the same declarations as retrieval.
""",
    tag_classes = {
        "git": tag_class(
            doc = "Declare one upstream source, its BUILD overlay, and its checkout scope.",
            attrs = {
                "branch": attr.string(doc = "The upstream branch. Supply either branch or commit."),
                "build_file": attr.label(mandatory = True, doc = "The BUILD overlay. Use @{owner}// for labels in its owning module."),
                "commit": attr.string(doc = "An optional full commit ID. An empty value leaves the revision unknown."),
                "name": attr.string(mandatory = True, doc = "The generated repository name and corresponding source metadata target name."),
                "remote": attr.string(mandatory = True, doc = "The Git repository URL to fetch and record in source metadata."),
                "sparse_checkout_patterns": attr.string_list(doc = "Patterns passed to git_repository for sparse checkout. An empty list keeps the complete checkout."),
            },
        ),
        "http_file": tag_class(
            doc = "Fetch one checksum-verified file and expose its source metadata.",
            attrs = {
                "downloaded_file_path": attr.string(mandatory = True),
                "name": attr.string(mandatory = True),
                "sha256": attr.string(mandatory = True),
                "urls": attr.string_list(mandatory = True),
            },
        ),
    },
)
