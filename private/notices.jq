. as $report
| "Package index\n",
  (.packages[] | "\(.purl)\(if .revision then "@" + .revision else "" end)\n"),
  (.unassigned[] | "Unknown package identity: \(.label)\n"),
  "\n",
  ([.packages[] | (.licenses.texts + .licenses.notices)[]] + .unassigned | unique_by(.sha256) | sort_by([.file, .sha256])[] |
    . as $evidence | "\n--- \(.file) [sha256:\(.sha256)] ---\n",
    (first($report.files[] | select(.path == $evidence.file)).content // error("Missing notice text"))),
  (if any(.packages[]; (.licenses.candidates // [] | length) > 0) then
    "\nFile-scoped legal candidates: applicability unresolved\n",
    (.packages[] | .purl as $purl | .licenses.candidates[]? |
      . as $candidate | "\n--- \($purl): \(.path) [sha256:\(.sha256)] ---\n",
      (first($report.files[] | select(.path == $candidate.file)).content // error("Missing candidate text")))
    else empty end)
