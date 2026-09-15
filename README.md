# rules_supply_chain

Collect package and license evidence from Bazel targets.
Generate deterministic metadata, coverage reports, notice bundles, and structural checks.

## Setup

Use Bazel 9.2.0 and a Linux execution environment.
The execution environment must provide Bash, GNU `sha256sum`, `xargs`, `mktemp`, and standard shell utilities.
The module registers a pinned jq toolchain through `jq.bzl`.
It does not require Python, Rust, or Cargo.

The module is not published in the Bazel Central Registry.
Use a Git submodule or local checkout with a Bzlmod override:

```starlark
bazel_dep(name = "rules_supply_chain", version = "0.1.0")
local_path_override(
    module_name = "rules_supply_chain",
    path = "rules_supply_chain",
)
```

Load the public API from [defs.bzl](defs.bzl):

```starlark
load("@rules_supply_chain//:defs.bzl", "report")

report(
    name = "dependencies",
    roots = ["//app:binary"],
    expected_packages = ["pkg:generic/example@1.0.0"],
)
```

The module supplies its own filters and scripts.
The [consumer example](examples/basic/README.md) is an independent Bazel module.

## Interface

The [adapter contract](EVIDENCE.md) describes optional package evidence inputs and schema-version-1 additions.

The [API docstrings](defs.bzl) describe all arguments, defaults, outputs, and structural requirements.
Stardoc generates Markdown from these docstrings under bazel-bin/docs/generated.
The [consumer example](examples/basic/BUILD.bazel) supplies package metadata and explicit overlay evidence.

## Collection limits

The collector reads `PackageMetadataInfo`, `LicenseInfo`, `LegalScopeInfo`, and legacy `PackageInfo` providers.
It preserves repository defaults and package overrides.
Missing legal evidence remains a coverage gap.
The module does not assign its own MIT license to consumer inputs.

The supported dependency attributes are `srcs`, `deps`, `data`, `sources`, `actual`, `compile_data`, `grammars`, and `ir`.
The collector also follows `_emit`, `_importer`, `_importer_source`, `_lock`, and `_tool` for existing generator rules.
It follows aliases and records source files plus generated `ebnf`, `xtext`, and `ungram` files.
It excludes executable outputs and metadata helper dependencies from source collection.
Explicit evidence can include other file types.

License providers supply license text.
Explicit `NOTICE*` files and files below `LICENSES/` supply notice text.
Notice associations follow repository boundaries.
Versions come from providers or versioned PURLs.
Unresolved revisions and fetched remotes remain `null`.

The reports validate evidence structure and consistency.
They do not approve licenses, establish legal permissions, or certify license compatibility.
Cargo scanning, release policy, SBOM export, signing, and complete compiler toolchain inventories are outside this release.

## Development

See the [Justfile](Justfile) for development commands.

### API documentation

Use the [Stardoc docstring format](https://github.com/bazelbuild/stardoc/blob/master/docs/writing_stardoc.md) for the public API.
Keep parameter descriptions in the `Args:` section of [defs.bzl](defs.bzl).
Keep setup and collection limits in this README.
The [documentation targets](docs/BUILD.bazel) select the public rules, macro, and providers.
Documentation tools are development dependencies.
The module registers a pinned LLVM development toolchain to build Stardoc dependencies.
Consumer modules do not need these tools.

Update the public docstring when you change an argument, output, or structural requirement.
Generated references do not belong in source control.
The module test command also builds the documentation targets.
