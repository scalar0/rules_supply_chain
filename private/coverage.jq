{
  schema_version: .schema_version,
  scope: .scope,
  missing_identities: ([.targets[] | select(.helper == false and .kind != "source_file" and (.packages | length) == 0) | .label] | unique),
  missing_license_text: ([.packages[] | select((.license_evidence | length) == 0) | .purl] | unique),
  unresolved_terms: ([.packages[] | select((.declared_licenses | length) == 0) | .purl] | unique),
  conflicting_declarations: ([.packages[] | select((.declared_versions | length) > 1 or
    (.declared_licenses != ([.license_evidence[].terms[]] | unique))) | .purl] | unique)
}
