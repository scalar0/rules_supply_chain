"""Supply source provenance through Bazel package metadata."""

SourceRepositoryInfo = provider(
    doc = "Source provenance that identifies imported cases through package metadata.",
    fields = {"metadata": "A JSON File with the source URL, branch, and available revision. A null revision means no resolved commit is available."},
)

def _source_repository_impl(ctx):
    return [
        SourceRepositoryInfo(metadata = ctx.file.src),
        DefaultInfo(files = depset([ctx.file.src])),
    ]

_source_repository = rule(
    implementation = _source_repository_impl,
    doc = """Expose an existing source metadata file through `SourceRepositoryInfo`.

Add this target to a package's `default_package_metadata` list.
Case rules then inherit source provenance and apply imported-case classification.
`DefaultInfo` exposes the original file without copying or changing its contents.
The `sources` module extension creates these targets in `@source_repositories`.
""",
    attrs = {
        "src": attr.label(mandatory = True, allow_single_file = [".json"], doc = "A source declaration."),
    },
)

def source_repository(name, src, **kwargs):
    """Expose a source declaration.

    Args:
        name: The metadata target name.
        src: The JSON source declaration.
        **kwargs: Common target attributes.
    """
    _source_repository(name = name, src = src, package_metadata = [], **kwargs)
