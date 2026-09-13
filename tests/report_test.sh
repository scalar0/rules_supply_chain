#!/usr/bin/env bash
set -euo pipefail
trap 'echo "The report test failed at line $LINENO." >&2' ERR
jq_bin=$1
filters=$(dirname "$2")
base=$(cd -- "$(dirname -- "$0")" && pwd)
work=$TEST_TMPDIR
report="$base/fixture_report/metadata.json"

check() {
    "$jq_bin" -f "$filters/coverage.jq" "$1" > "$work/coverage.json"
    "$jq_bin" -es --argjson required_overlay_packages '["pkg:generic/fixture-override"]' -f "$filters/check.jq" "$1" "$work/coverage.json" > /dev/null
}

reject() {
    if check "$1" 2> "$work/error"; then
        echo "The structural check accepted invalid metadata." >&2
        exit 1
    fi
}

check "$report"
"$jq_bin" -e 'any(.packages[]; .purl == "pkg:github/scalar0/rules_supply_chain@0.1.0" and .declared_licenses == ["MIT"]) and any(.packages[]; .provider == "PackageInfo") and any(.targets[]; .kind == "genrule") and any(.targets[].dependencies[]; .attribute == "sources")' "$report" > /dev/null
"$jq_bin" -e 'any(.packages[]; .purl == "pkg:generic/fixture-override" and .declared_licenses == [] and (.overlay_evidence | length) == 1) and (.unassigned_license_evidence | length) == 1' "$report" > /dev/null
"$jq_bin" -e '(.missing_identities | length) > 0 and (.missing_license_text | length) > 0' "$base/fixture_report/coverage.json" > /dev/null
"$jq_bin" -e '.packages == [] and .evidence == [] and .roots == []' "$base/empty_report/metadata.json" > /dev/null

for filter in \
    '.packages[0].purl = "invalid"' \
    '.packages[0].purl = "pkg:generic/invalid name"' \
    '.expected_packages += ["pkg:generic/absent"]' \
    '.targets[0].dependencies += [{attribute: "deps", target: "//absent:target"}]' \
    '.packages[0].declared_versions = ["1", "2"]' \
    '.schema_version = 99' \
    '(.packages[] | select(.purl == "pkg:github/scalar0/rules_supply_chain@0.1.0") | .declared_licenses) = ["Apache-2.0"]' \
    '(.packages[] | .overlay_evidence) = []' \
    '(.packages[] | .overlay_evidence[] | .sha256) = "invalid"'; do
    "$jq_bin" "$filter" "$report" > "$work/bad.json"
    reject "$work/bad.json"
done

# Required evidence does not depend on the report scope name.
"$jq_bin" '.scope = "arbitrary-consumer"' "$report" > "$work/renamed.json"
check "$work/renamed.json"
"$jq_bin" '.missing_license_text = []' "$base/fixture_report/coverage.json" > "$work/wrong-coverage.json"
if "$jq_bin" -es -f "$filters/check.jq" "$report" "$work/wrong-coverage.json" > /dev/null 2>&1; then
    echo "The structural check accepted inconsistent coverage." >&2
    exit 1
fi

"$jq_bin" -j -f "$filters/notices.jq" "$report" > "$work/notices.txt"
cmp "$work/notices.txt" "$base/fixture_report/notices.txt"
"$jq_bin" -e --rawfile notices "$work/notices.txt" '. as $m | all(([.packages[] | (.license_evidence + .notice_evidence)[]] + .unassigned_license_evidence)[]; .file as $f | first($m.evidence[] | select(.logical == $f)).content as $text | $notices | contains($text))' "$report" > /dev/null

printf 'first\n' > "$work/input"
"$jq_bin" -n --arg path "$work/input" '{schema_version: 1, files: [{path: $path, logical: "input", kind: "text"}]}' > "$work/manifest.json"
bash "$filters/digest.sh" "$jq_bin" "$work/manifest.json" "$work/first.json"
bash "$filters/digest.sh" "$jq_bin" "$work/manifest.json" "$work/repeated.json"
cmp "$work/first.json" "$work/repeated.json"
printf 'second\n' > "$work/input"
bash "$filters/digest.sh" "$jq_bin" "$work/manifest.json" "$work/second.json"
"$jq_bin" -es '.[0].files[0].sha256 != .[1].files[0].sha256 and .[1].files[0].content == "second\n"' "$work/first.json" "$work/second.json" > /dev/null
