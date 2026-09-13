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

| Argument | Value | Purpose |
| --- | --- | --- |
| `name` | Target name | Set the report scope and output directory |
| `roots` | Label list | Select the dependency graph roots |
| `expected_packages` | PURL list | Require these package identities |
| `evidence` | Label list | Include additional source and legal evidence |
| `overlay_evidence` | PURL to label-list map | Associate files with exact package identities |
| `required_overlay_packages` | PURL list | Require a nonempty overlay association for each identity |

Only `name` and `roots` are required.
The other arguments default to empty collections.
Evidence labels can identify files or filegroups.
Different packages can share evidence files.
Overlay associations do not depend on repository names, filenames, or report scope names.
The check fails if a required overlay package is absent or has no associated files.

Each report produces schema-version-1 outputs under `<name>/`:

| Output | Contents |
| --- | --- |
| `metadata.json` | Packages, graph relationships, source digests, and exact evidence text |
| `coverage.json` | Missing identities, missing license text, unresolved terms, and conflicts |
| `notices.txt` | Package index and exact license and notice text |
| `check.json` | The structural check result |

The macro also creates `<name>_inventory`, `<name>_metadata`, `<name>_coverage`, `<name>_notices`, and `<name>_check` targets.
A failed structural check fails the combined report target.
Identical inputs produce identical output bytes.

## Collection limits

The collector reads `PackageMetadataInfo`, `LicenseInfo`, and legacy `PackageInfo` providers.
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

| Command | Purpose |
| --- | --- |
| `just lint` | Check Starlark formatting and shell syntax |
| `just test` | Run standalone module tests |
| `just example` | Build the independent consumer report |
| `just check` | Check the module, example, and both lockfiles |

## License and origin

The module code and documentation use the [MIT license](LICENSE).
Collected artifacts and dependency licenses retain their original terms.

The initial source came from `tools/supply_chain` in `scalar0/kertc`.
The source commit was `cbd9ba4779fff672238aee00093082e80421857e`.
The extraction separates repository configuration from the reporting engine.
