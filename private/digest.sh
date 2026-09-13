#!/usr/bin/env bash
set -euo pipefail
jq_bin=$1
manifest=$2
output=$3
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Hash all inputs in one process. NUL records preserve spaces and newlines.
"$jq_bin" -j '.files | unique_by(.path)[] | .path, "\u0000"' "$manifest" > "$work/paths"
xargs -0 -r sha256sum --zero -- < "$work/paths" > "$work/hashes"
"$jq_bin" -Rs '[split("\u0000")[] | select(length > 0) | {key: .[66:], value: .[:64]}] | from_entries' "$work/hashes" > "$work/digests"

# jq reads structured data and exact license text.
"$jq_bin" -r '.files | unique_by(.path)[] | select(.kind != "source") | [.path, .kind] | @tsv' "$manifest" > "$work/texts"
while IFS=$'\t' read -r path kind; do
    "$jq_bin" -cn --arg path "$path" --arg kind "$kind" --rawfile text "$path" \
        '{key: $path, value: (if $kind == "metadata" then ($text | fromjson) else $text end)}'
done < "$work/texts" > "$work/contents"
"$jq_bin" -s 'from_entries' "$work/contents" > "$work/content-map"
"$jq_bin" --slurpfile digests "$work/digests" --slurpfile contents "$work/content-map" \
    '.files |= (map(. + {sha256: $digests[0][.path], content: $contents[0][.path]} | del(.path)) | unique_by(.logical) | sort_by(.logical))' \
    "$manifest" > "$output"
