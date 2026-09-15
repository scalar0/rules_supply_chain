{
  "$schema": "schema.json#coverage",
  scope,
  missing: {
    identities: ([.targets[] | select(.helper == false and .kind != "source_file" and (.packages | length) == 0) | .label] | unique),
    texts: ([.packages[] | select((.licenses.texts | length) == 0) | .purl] | unique),
    terms: ([.packages[] | select((.licenses.terms | length) == 0) | .purl] | unique)
  },
  conflicts: ([.packages[] | select(
    (.versions | length) > 1
    or (.licenses.terms != ([.licenses.texts[].terms[], .licenses.declarations[].terms[]] | unique))
    or ([.licenses.declarations[].expression | select(. != null)] | unique | length) > 1
  ) | .purl] | unique),
  gaps: (.gaps // []),
  assessment: {inputs:"declared_bazel_inputs",completeness:"not_established",policy:"not_evaluated"}
}
| .missing |= with_entries(select(.value | length > 0))
| if .missing == {} then del(.missing) else . end
| if .conflicts == [] then del(.conflicts) else . end
| if .gaps == [] then del(.gaps) else . end
