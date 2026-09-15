#!/usr/bin/env bash
set -euo pipefail
jq_bin=$1
manifest=$2
output=$3
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Read selected adapter evidence from its declared source files.
"$jq_bin" -j '. as $m | .files[] | select(.logical as $p | ($m.package_evidence // []) | index($p)) | .path, "\u0000"' "$manifest" > "$work/adapters"
: > "$work/adapter-texts"
while IFS= read -r -d '' adapter; do
    "$jq_bin" -c '.packages[] | .texts[]?.file' "$adapter" >> "$work/adapter-texts"
done < "$work/adapters"
"$jq_bin" --slurpfile texts "$work/adapter-texts" '.files |= map(if (.logical as $p | $texts | index($p)) then .kind = "text" else . end)' "$manifest" > "$work/manifest.json"
manifest="$work/manifest.json"

# Hash all inputs in one process. NUL records preserve spaces and newlines.
"$jq_bin" -j '.files | unique_by(.path)[] | .path, "\u0000"' "$manifest" > "$work/paths"
xargs -0 -r sha256sum --zero -- < "$work/paths" > "$work/hashes"
"$jq_bin" -Rs '[split("\u0000")[] | select(length > 0) | {key: .[66:], value: .[:64]}] | from_entries' "$work/hashes" > "$work/digests"

# Read at most 64 files per jq process. NUL records preserve filenames.
"$jq_bin" -j '.files | unique_by(.path)[] | select(.kind != "source") | .path, "\u0000", .kind, "\u0000"' "$manifest" > "$work/texts"
contents_filter=$(dirname -- "$0")/contents.jq
batch_args=()
batch_count=0
: > "$work/contents"
while IFS= read -r -d '' path && IFS= read -r -d '' kind; do
    batch_args+=(--arg "path_$batch_count" "$path" --arg "kind_$batch_count" "$kind" --rawfile "text_$batch_count" "$path")
    batch_count=$((batch_count + 1))
    if ((batch_count == 64)); then
        "$jq_bin" -cn "${batch_args[@]}" -f "$contents_filter" >> "$work/contents"
        batch_args=()
        batch_count=0
    fi
done < "$work/texts"
if ((batch_count > 0)); then
    "$jq_bin" -cn "${batch_args[@]}" -f "$contents_filter" >> "$work/contents"
fi
"$jq_bin" -s 'from_entries' "$work/contents" > "$work/content-map"
"$jq_bin" --slurpfile digests "$work/digests" --slurpfile contents "$work/content-map" \
    '.["$schema"] = "urn:rules-supply-chain:schema:2#inventory" | .files |= (map(. + {sha256: $digests[0][.path], content: $contents[0][.path]} | del(.path)) | unique_by(.logical) | sort_by(.logical))' \
    "$manifest" > "$output"
