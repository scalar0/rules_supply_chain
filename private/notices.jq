. as $report
| "Package index\n",
  (.packages[] | "\(.purl)\(if .resolved_revision then "@" + .resolved_revision else "" end)\n"),
  (.unassigned_license_evidence[] | "Unknown package identity: \(.label)\n"),
  "\n",
  ([.packages[] | (.license_evidence + .notice_evidence)[]] + .unassigned_license_evidence | unique_by(.sha256) | sort_by([.file, .sha256])[] |
    . as $evidence | "\n--- \(.file) [sha256:\(.sha256)] ---\n",
    (first($report.evidence[] | select(.logical == $evidence.file)).content // error("Missing notice text")))
