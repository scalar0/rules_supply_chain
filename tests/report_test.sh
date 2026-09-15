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
"$jq_bin" -e 'any(.packages[]; .purl == "pkg:github/scalar0/rules_supply_chain@0.1.0" and .licenses.terms == ["MIT"]) and any(.packages[]; .provider == "PackageInfo") and any(.targets[]; .kind == "genrule") and any(.targets[].deps[]; .attribute == "sources")' "$report" > /dev/null
"$jq_bin" -e 'any(.packages[]; .purl == "pkg:generic/fixture-override" and .licenses.terms == [] and (.overlays | length) == 1) and (.unassigned | length) == 1' "$report" > /dev/null
"$jq_bin" -e '(.missing.identities | length) > 0 and (.missing.texts | length) > 0' "$base/fixture_report/coverage.json" > /dev/null
"$jq_bin" -e '.packages == [] and .files == [] and .roots == []' "$base/empty_report/metadata.json" > /dev/null

for filter in \
    '.packages[0].purl = "invalid"' \
    '.packages[0].purl = "pkg:generic/invalid name"' \
    '.expected += ["pkg:generic/absent"]' \
    '.targets[0].deps += [{attribute: "deps", target: "//absent:target"}]' \
    '.packages[0].versions = ["1", "2"]' \
    '.["$schema"] = "schema.json#unknown"' \
    '(.packages[] | select(.purl == "pkg:github/scalar0/rules_supply_chain@0.1.0") | .licenses.terms) = ["Apache-2.0"]' \
    '(.packages[] | .overlays) = []' \
    '(.packages[] | .overlays[] | .sha256) = "invalid"'; do
    "$jq_bin" "$filter" "$report" > "$work/bad.json"
    reject "$work/bad.json"
done

# Required evidence does not depend on the report scope name.
"$jq_bin" '.scope = "arbitrary-consumer"' "$report" > "$work/renamed.json"
check "$work/renamed.json"
"$jq_bin" '.missing.texts = []' "$base/fixture_report/coverage.json" > "$work/wrong-coverage.json"
if "$jq_bin" -es -f "$filters/check.jq" "$report" "$work/wrong-coverage.json" > /dev/null 2>&1; then
    echo "The structural check accepted inconsistent coverage." >&2
    exit 1
fi

# Duplicate definitions must fail schema assembly.
"$jq_bin" -n '{"$defs": {metadata: {type:"object"}}}' > "$work/duplicate-schema.json"
if "$jq_bin" -s -f "$filters/schema.jq" "$base/fixture_report/schema.json" "$work/duplicate-schema.json" > /dev/null 2>&1; then
    echo "The schema merger accepted a duplicate definition." >&2
    exit 1
fi

"$jq_bin" -j -f "$filters/notices.jq" "$report" > "$work/notices.txt"
cmp "$work/notices.txt" "$base/fixture_report/notices.txt"
"$jq_bin" -e --rawfile notices "$work/notices.txt" '. as $m | all(([.packages[] | (.licenses.texts + .licenses.notices)[]] + .unassigned)[]; .file as $f | first($m.files[] | select(.path == $f)).content as $text | $notices | contains($text))' "$report" > /dev/null

printf 'first\n' > "$work/input"
"$jq_bin" -n --arg path "$work/input" '{"$schema": "urn:rules-supply-chain:schema:2#manifest", files: [{path: $path, logical: "input", kind: "text"}]}' > "$work/manifest.json"
bash "$filters/digest.sh" "$jq_bin" "$work/manifest.json" "$work/first.json"
bash "$filters/digest.sh" "$jq_bin" "$work/manifest.json" "$work/repeated.json"
cmp "$work/first.json" "$work/repeated.json"
printf 'second\n' > "$work/input"
bash "$filters/digest.sh" "$jq_bin" "$work/manifest.json" "$work/second.json"
"$jq_bin" -es '.[0].files[0].sha256 != .[1].files[0].sha256 and .[1].files[0].content == "second\n"' "$work/first.json" "$work/second.json" > /dev/null

# Cross batch boundaries with exact text and unusual filenames.
for count in 0 1 63 64 65 129; do
    : > "$work/batch-inputs"
    for ((i = 0; i < count; i++)); do
        path="$work/"$'odd\tname\n'"$i"
        if ((i % 3 == 0)); then
            : > "$path"
        else
            printf 'Text %s\n\n' "$i" > "$path"
        fi
        "$jq_bin" -cn --arg path "$path" --arg logical "text-$i" --rawfile text "$path" \
            '{path:$path,logical:$logical,kind:"text",expected:$text}' >> "$work/batch-inputs"
    done
    "$jq_bin" -s '{"$schema": "urn:rules-supply-chain:schema:2#manifest",files:.}' "$work/batch-inputs" > "$work/batch-manifest.json"
    bash "$filters/digest.sh" "$jq_bin" "$work/batch-manifest.json" "$work/batch-result.json"
    "$jq_bin" -e --argjson count "$count" \
        '(.files|length)==$count and all(.files[]; .content==.expected and (.sha256|test("^[0-9a-f]{64}$")))' \
        "$work/batch-result.json" > /dev/null
done

# Invalid JSON must fail even when it occurs after a full batch.
printf '{invalid' > "$work/zz-invalid"
"$jq_bin" --arg path "$work/zz-invalid" \
    '.files += [{path:$path,logical:"invalid",kind:"metadata"}]' \
    "$work/batch-manifest.json" > "$work/bad-manifest.json"
if bash "$filters/digest.sh" "$jq_bin" "$work/bad-manifest.json" "$work/bad-result.json" 2>/dev/null; then
    echo "The digest action accepted invalid JSON." >&2
    exit 1
fi
