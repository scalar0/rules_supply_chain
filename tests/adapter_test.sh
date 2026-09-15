#!/usr/bin/env bash
set -euo pipefail
jq_bin=$1
filters=$(dirname "$2")
base=$(cd -- "$(dirname -- "$0")" && pwd)
work=$TEST_TMPDIR

"$jq_bin" '
  (first(.files[] | select(.content | type == "string"))) as $text
  | .roots[0] as $target
  | {target: $target, purl: "pkg:generic/adapter@1.0", version: "1.0",
      source: {kind: "fixture", revision: null, url: null},
      declarations: [{expression: "MIT OR Apache-2.0", terms: ["Apache-2.0", "MIT"], file: $text.logical, sha256: $text.sha256}],
      license_evidence: [{file: $text.logical, sha256: $text.sha256, terms: [], association: "filename_candidate"}],
      notice_evidence: [], gaps: [],
      texts: [{file: $text.logical, sha256: $text.sha256, content: $text.content}]
    } as $record
  | .package_evidence = ["adapter.json"]
  | .files += [{logical: "adapter.json", kind: "metadata", sha256: ("0" * 64), content: {"$schema": "urn:rules-supply-chain:schema:2#adapter", packages: [$record]}}]
' "$base/fixture_report_inventory.json" > "$work/raw.json"

"$jq_bin" --slurpfile schema "$base/../schema.json" -f "$filters/metadata.jq" "$work/raw.json" > "$work/metadata.json"
"$jq_bin" -f "$filters/coverage.jq" "$work/metadata.json" > "$work/coverage.json"
"$jq_bin" -es -f "$filters/check.jq" "$work/metadata.json" "$work/coverage.json" > /dev/null
"$jq_bin" -e '.["$schema"] == "schema.json#metadata" and any(.packages[]; .purl == "pkg:generic/adapter@1.0" and .licenses.declarations[0].expression == "MIT OR Apache-2.0" and .licenses.terms == ["Apache-2.0", "MIT"])' "$work/metadata.json" > /dev/null

for mutation in \
    '.files[-1].content["$schema"] = "urn:rules-supply-chain:schema:2#unknown"' \
    '.files[-1].content.packages[0] |= del(.version)' \
    '.files[-1].content.packages[0].target = "//absent:target"' \
    '.files[-1].content.packages[0].texts[0].sha256 = ("0" * 64)' \
    '.files[-1].content.packages[0].texts[0].content = "Forged text"' \
    '.files[-1].content.packages += [(.files[-1].content.packages[0] | .purl = "pkg:generic/other@1.0")]'; do
    "$jq_bin" "$mutation" "$work/raw.json" > "$work/bad.json"
    if "$jq_bin" --slurpfile schema "$base/../schema.json" -f "$filters/metadata.jq" "$work/bad.json" > /dev/null 2>&1; then
        echo "The adapter accepted invalid evidence." >&2
        exit 1
    fi
done

"$jq_bin" '(.packages[] | select(.purl == "pkg:generic/adapter@1.0") | .licenses.declarations[0].sha256) = ("0" * 64)' "$work/metadata.json" > "$work/bad.json"
if "$jq_bin" -es -f "$filters/check.jq" "$work/bad.json" "$work/coverage.json" > /dev/null 2>&1; then
    echo "The check accepted an invalid declaration reference." >&2
    exit 1
fi

"$jq_bin" '
  .files[-1].content.packages[0] |= (
    .legal_file_candidates = [.license_evidence[0] + {relative_path:"nested/LICENCE",association:"unresolved_scope"}]
    | .source.publisher_vcs = (.license_evidence[0] + {revision:("a"*40),path_in_vcs:"crate",trust:"publisher_supplied"})
  )
' "$work/raw.json" > "$work/candidates.json"
"$jq_bin" --slurpfile schema "$base/../schema.json" -f "$filters/metadata.jq" "$work/candidates.json" > "$work/candidate-metadata.json"
"$jq_bin" -f "$filters/coverage.jq" "$work/candidate-metadata.json" > "$work/candidate-coverage.json"
"$jq_bin" -es -f "$filters/check.jq" "$work/candidate-metadata.json" "$work/candidate-coverage.json" > /dev/null
"$jq_bin" -e '.assessment.completeness == "not_established" and (has("package_coverage") | not)' "$work/candidate-coverage.json" > /dev/null
for mutation in \
  '(.packages[] | select(.licenses.candidates | length > 0) | .licenses.candidates[0].sha256) = ("0"*64)' \
  '(.packages[] | select(.licenses.candidates | length > 0) | .licenses.candidates[0].path) = "../escape"' \
  '(.packages[] | select(.licenses.candidates | length > 0) | .licenses.candidates[0].file) = "undeclared"' \
  '(.packages[] | select(.sources != null) | .sources[0].publisher_vcs.trust) = "verified"'; do
  "$jq_bin" "$mutation" "$work/candidate-metadata.json" > "$work/bad.json"
  if "$jq_bin" -es -f "$filters/check.jq" "$work/bad.json" "$work/candidate-coverage.json" > /dev/null 2>&1; then
    echo "The check accepted invalid candidate evidence." >&2
    exit 1
  fi
done

"$jq_bin" '
  first(.files[] | select(.kind == "text")) as $text
  | .files += [{logical:"package.json",kind:"metadata",sha256:("1"*64),content:{purl:"pkg:generic/adapter@1.0"}}]
  | .nodes[0].legal_scopes = [{
      package:"package.json",texts:[$text.logical],artifacts:[$text.logical],
      gaps:["unresolved_applicability"]
  }]
' "$work/raw.json" > "$work/scope.json"
"$jq_bin" --slurpfile schema "$base/../schema.json" -f "$filters/metadata.jq" "$work/scope.json" > "$work/scope-metadata.json"
"$jq_bin" -f "$filters/coverage.jq" "$work/scope-metadata.json" > "$work/scope-coverage.json"
"$jq_bin" -es -f "$filters/check.jq" "$work/scope-metadata.json" "$work/scope-coverage.json" > /dev/null
for mutation in \
  '.files[-1].content.purl = "pkg:generic/absent"' \
  '.nodes[0].legal_scopes[0].texts = ["undeclared"]' \
  '.nodes[0].legal_scopes[0].artifacts = ["undeclared"]' \
  '.nodes[0].legal_scopes[0].gaps = ["unknown"]' \
  '.nodes[0].legal_scopes[0].gaps = [null]'; do
  "$jq_bin" "$mutation" "$work/scope.json" > "$work/bad.json"
  if "$jq_bin" --slurpfile schema "$base/../schema.json" -f "$filters/metadata.jq" "$work/bad.json" > /dev/null 2>&1; then
    echo "The adapter accepted an invalid legal scope." >&2
    exit 1
  fi
done

"$jq_bin" '(.packages[] | select(.artifacts != null) | .artifacts[0].sha256) = ("0"*64)' "$work/scope-metadata.json" > "$work/bad.json"
if "$jq_bin" -es -f "$filters/check.jq" "$work/bad.json" "$work/scope-coverage.json" > /dev/null 2>&1; then
  echo "The check accepted an invalid artifact digest." >&2
  exit 1
fi
"$jq_bin" '.assessment.completeness = "complete"' "$work/scope-coverage.json" > "$work/bad-coverage.json"
if "$jq_bin" -es -f "$filters/check.jq" "$work/scope-metadata.json" "$work/bad-coverage.json" > /dev/null 2>&1; then
  echo "The check accepted invalid coverage." >&2
  exit 1
fi

"$jq_bin" '
  .roots[0] as $target
  | .files += [{
      logical:"source.json",kind:"metadata",sha256:("1"*64),
      content:{kind:"git",url:"https://example.invalid/source",branch:"main",revision:null}
    }]
  | (.nodes[] | select(.label == $target)).source_records = ["source.json"]
' "$work/raw.json" > "$work/source.json"
"$jq_bin" --slurpfile schema "$base/../schema.json" -f "$filters/metadata.jq" "$work/source.json" > "$work/source-metadata.json"
"$jq_bin" -e 'any(.packages[]; any(.sources[]?; .branch == "main" and .revision == null))' "$work/source-metadata.json" > /dev/null
"$jq_bin" '.files[-1].content.url = null' "$work/source.json" > "$work/bad.json"
if "$jq_bin" --slurpfile schema "$base/../schema.json" -f "$filters/metadata.jq" "$work/bad.json" > /dev/null 2>&1; then
  echo "The report accepted an invalid source declaration." >&2
  exit 1
fi
