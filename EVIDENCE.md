# Package evidence adapters

Adapters expose [PackageEvidenceInfo](providers.bzl) and pass their targets to the report's package_evidence argument.
The provider supplies one JSON records file and a depset of declared input files.
The report does not depend on Cargo or any Rust adapter.

The records file uses "$schema": "urn:rules-supply-chain:schema:2#adapter" and a packages array.
Each package record identifies one canonical Bazel target.

| Field            | Content                                                                |
| ---------------- | ---------------------------------------------------------------------- |
| target           | A target reachable from the report roots                               |
| purl             | A package identity, or null when identity discovery fails              |
| version          | The declared package version                                           |
| source           | Source kind, manifest path, URL, checksum, and revision when available |
| declarations     | SPDX expressions, atomic requirements, declaration paths, and digests  |
| license_evidence | License file references with digests and association methods           |
| notice_evidence  | Notice file references with digests                                    |
| texts            | Exact UTF-8 text, logical file paths, and SHA-256 digests              |
| gaps             | Discovery codes with optional context                                  |

A record without an identity contains only target, purl, and gaps.
File paths use the short paths of declared Bazel Files.
The report reads the referenced files independently and checks both their text and digests.
Unknown targets, inconsistent duplicate records, invalid references, and forged evidence fail the build.

Exported reports use shorter names than adapter records.
Packages group license evidence under licenses and retain sources and nonempty gaps.
Metadata and coverage expose nonempty adapter gaps as gaps.
Gap records use codes from the [schema](schema.json), with optional context fields.
For example, {"code":"missing_license_file","file":"legal/LICENSE"} identifies a missing declared input.
Gap records do not contain kind or message fields.

The licenses.terms array summarizes atomic requirements.
Use licenses.declarations[].expression when OR, AND, grouping, or WITH matters.
The report does not infer expression coverage from filename candidates.
Missing upstream declarations remain gaps rather than report schema errors.

Adapters can add crate identities alongside repository identities.
When a crate source has a more precise identity, it replaces the previous Cargo identity for that target.
It does not replace repository metadata.

## File scope and coverage

Adapters can supply legal_file_candidates with file, sha256, relative_path, and association fields.
The association must be unresolved_scope.
The report retains candidate text without assigning its terms to a package.
Equal text at different paths retains each path association.

Declarations can add parsing, normalized_expression, and normalization fields.
Parsing states are valid, normalized, invalid, and missing.
The Rust adapter uses cargo_slash_to_or for deprecated Cargo license lists.
Raw expressions remain unchanged.

Sources can add publisher_vcs with revision, path_in_vcs, file, sha256, and trust fields.
The trust value publisher_supplied distinguishes packaged claims from verified checkout evidence.

Coverage lists detected gaps without a per-package success record.
Package metadata retains detailed gaps and licenses.candidates.
No gap entry means that the audit found no gaps in the declared inputs for that package.
Text presence does not establish expression coverage or complete copyright notices.
The assessment records declared_bazel_inputs, not_established completeness, and not_evaluated policy.
The structural check does not reject unresolved discovery gaps.

## Declared legal evidence

Attach [legal_scope](defs.bzl) through package_metadata or package defaults.
Reference an existing package metadata target with package.
Declare artifact and text labels directly.
Texts remain candidates until a license target establishes an explicit association.
The collector hashes these files independently.
The rule clears inherited metadata on its private target to prevent a dependency cycle.

Declare unresolved gap codes with gaps.
The [schema](schema.json) defines each code.
The report rejects unknown codes.
Consumers must use codes for decisions.
The interface does not accept a catalog.

## Source provenance

The [sources extension](repositories.bzl) fetches Git sources and checksum-verified HTTP files.
The same declarations generate metadata in source_repositories.
A branch source records a null revision.
A commit source records the supplied full commit ID.
A null revision does not establish a reproducible checkout.

The [source_repository rule](source_metadata.bzl) attaches generated source declarations through package_metadata.
The report records these declarations and hashes the current local files independently.
A branch declaration does not prove that a local file matches the current upstream checkout.
Use a source comparison to check that relationship.

## Exported schema

Each report exports schema.json beside metadata.json, coverage.json, and check.json.
These reports use relative references such as "$schema": "schema.json#metadata".
The bundle uses JSON Schema Draft 2020-12 and the identifier urn:rules-supply-chain:schema:2.
Internal documents use this identifier with manifest, inventory, adapter, or cargo-inputs anchors.
Upstream evidence content remains unchanged.

The public schema target exports the generic definitions.
The report schema_defs argument accepts additional definitions.
Duplicate definition names fail bundle assembly.
crate_report includes the Cargo definitions automatically.
Copy the complete report directory to preserve relative references.

| Report   | Main fields                                                        |
| -------- | ------------------------------------------------------------------ |
| Metadata | scope, roots, expected, packages, targets, files, unassigned, gaps |
| Coverage | scope, missing, conflicts, gaps, assessment                        |
| Check    | scope, valid                                                       |

Packages use version, versions, release, revision, remote, attributes, sources, artifacts, overlays, and gaps.
Their licenses object contains terms, declarations, texts, notices, and candidates.
Targets use deps for dependency edges.
Evidence files and candidates use path for locations.
References retain file and sha256.
Declarations use normalized for a normalized expression.

Coverage groups missing identities, texts, and terms under missing.
Empty gap arrays and an empty missing object are absent.
No per-package success records exist.

Development tests validate schemas and documents without network resolution.
Report builds retain jq checks for references, digests, and consistency.
JSON Schema describes structure and does not establish license permissions.
