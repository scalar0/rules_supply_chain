"""Attach declared legal evidence without a separate catalog."""

load("@package_metadata//providers:package_metadata_info.bzl", "PackageMetadataInfo")
load("//:providers.bzl", "LegalScopeInfo")

def _impl(ctx):
    return [LegalScopeInfo(
        package = ctx.attr.package[PackageMetadataInfo],
        artifacts = ctx.files.artifacts,
        texts = ctx.files.texts,
        gaps = ctx.attr.gaps,
    )]

_legal_scope = rule(
    implementation = _impl,
    attrs = {
        "artifacts": attr.label_list(allow_files = True),
        "gaps": attr.string_list(),
        "package": attr.label(mandatory = True, providers = [PackageMetadataInfo]),
        "texts": attr.label_list(allow_files = True),
    },
)

def legal_scope(name, package, artifacts = [], texts = [], gaps = [], **kwargs):
    """Attach evidence to an existing package identity.

    Texts remain candidates. Use license targets for verified license associations.
    The report validates gap codes against its schema.

    Args:
        name: The metadata helper target name.
        package: The package metadata target that owns this evidence.
        artifacts: Files or filegroups to hash.
        texts: Evidence text files or filegroups with unresolved applicability.
        gaps: Unresolved gap codes defined in the report schema.
        **kwargs: Common target attributes.
    """
    _legal_scope(
        name = name,
        package = package,
        artifacts = artifacts,
        texts = texts,
        gaps = gaps,
        package_metadata = [],
        **kwargs
    )
