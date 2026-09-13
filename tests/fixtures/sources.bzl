"""Exercise the custom corpus dependency attribute."""

def _corpus_impl(ctx):
    return [DefaultInfo(files = depset(transitive = [t[DefaultInfo].files for t in ctx.attr.sources]))]

corpus = rule(
    implementation = _corpus_impl,
    doc = """Expose source files through a custom dependency attribute for aspect tests.

`DefaultInfo` contains the union of the source targets' default files.
The string values identify fixture sources but do not change file collection.
""",
    attrs = {"sources": attr.label_keyed_string_dict(doc = "Source targets mapped to fixture identifiers for dependency traversal tests.")},
)
