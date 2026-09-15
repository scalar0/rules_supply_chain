"""Provider contract for package evidence adapters."""

LegalScopeInfo = provider(
    doc = "Declared artifacts, candidate texts, and unresolved gaps for one package.",
    fields = {
        "artifacts": "Files to digest independently.",
        "gaps": "Gap codes from the schema.",
        "package": "The package metadata provider.",
        "texts": "Text Files with unresolved applicability.",
    },
)

PackageEvidenceInfo = provider(
    doc = "Package declarations and the files that support them.",
    fields = {
        "files": "A depset of declared evidence Files referenced by logical short paths.",
        "records": "A JSON File with the adapter schema reference and a packages array.",
    },
)
