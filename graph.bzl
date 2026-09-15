"""Shared dependency edges for audit collectors."""

# These attributes carry source inputs and declared dependencies.
DEPENDENCY_ATTRIBUTES = [
    "srcs",
    "deps",
    "data",
    "sources",
    "actual",
    "compile_data",
    "proc_macro_deps",
    "crate",
    "link_deps",
    "script",
    "tests",
    "grammars",
    "ir",
    "_emit",
    "_importer",
    "_importer_source",
    "_lock",
    "_tool",
]

def targets(value):
    """Return targets from a rule attribute value.

    Args:
        value: A target, list, dictionary, or other attribute value.

    Returns:
        Target values, or target keys for a dictionary.
    """
    if type(value) == "Target":
        return [value]
    if type(value) == "list":
        return [v for v in value if type(v) == "Target"]
    if type(value) == "dict":
        return [v for v in value.keys() if type(v) == "Target"]
    return []
