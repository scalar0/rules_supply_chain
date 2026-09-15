def valid_gap:
  . as $gap
  | ($gap | type) == "object"
    and ($gap | has("kind") or has("message") | not)
    and any($schema[0]["$defs"].gap_code.oneOf[]; .const == $gap.code);

def file($raw; $name):
  first($raw.files[] | select(.logical == $name)) // error("Invalid evidence reference: " + $name);
def package_records($raw; $node):
  ($node.label | ltrimstr("@@") | split("//")[0]) as $repository
  | (if $repository == "" then "" else "../" + $repository + "/" end) as $prefix
  | [$node.packages[] |
      if .provider == "PackageMetadataInfo" then
        file($raw; .file).content | {purl, provider: "PackageMetadataInfo", provider_attributes: .attributes}
      else . end]
  | group_by(.purl)[]
  | reduce .[] as $p ({}; . * $p)
  | .purl as $purl
  | . + {
      declared_version: (.declared_version // (try (.purl | split("#")[0] | split("?")[0] | capture("@(?<version>[^@]+)$").version) catch null) // null),
      release_version: null,
      resolved_revision: null,
      fetched_remote: null,
      declared_licenses: ([$node.licenses[].terms[]] | unique),
      license_evidence: [$node.licenses[] | select(.file != null) | . + {sha256: file($raw; .file).sha256}],
      notice_evidence: [$raw.files[] | select(if $prefix == "" then (.logical | startswith("../") | not) else (.logical | startswith($prefix)) end) | select(.kind == "text" and ((.logical | split("/")[-1] | startswith("NOTICE")) or (.logical | contains("/LICENSES/")))) | {file: .logical, sha256}],
      overlay_evidence: [($raw.overlay_evidence[$purl] // [])[] as $name | file($raw; $name) | {file: .logical, sha256}] | unique,
      targets: [$node.label]
    };
def adapter_records($raw):
  [($raw.package_evidence // [])[] as $path
   | file($raw; $path).content
   | if .["$schema"] != "urn:rules-supply-chain:schema:2#adapter" or (.packages | type) != "array" then error("Invalid package evidence schema") else .packages[] end
   | if (has("legal_file_candidates") and ((.legal_file_candidates | type) != "array"
         or any(.legal_file_candidates[]; (.file | type) != "string" or (.sha256 | type) != "string"
           or (.relative_path | type) != "string" or .association != "unresolved_scope")))
       or (.target | type) != "string" or (.gaps | type) != "array"
       or any(.gaps[]; valid_gap | not)
       or (.purl != null and ((.purl | type) != "string" or (.version | type) != "string"
         or (.source | type) != "object" or (.declarations | type) != "array"
         or (.texts | type) != "array" or (.license_evidence | type) != "array" or (.notice_evidence | type) != "array"
         or any(.declarations[]; (.terms | type) != "array" or any(.terms[]; type != "string")
           or (.expression != null and (.expression | type) != "string"))))
     then error("Invalid package evidence record") else . end];

def enrich($raw):
  if (($raw.package_evidence // []) | length) == 0 then . else
    adapter_records($raw) as $records
    | . as $report
    | if any($records[]; .target as $target | ($report.targets | any(.label == $target) | not))
      then error("Package evidence target is outside the report") else . end
    | if any($records | group_by(.target)[]; (unique | length) > 1)
      then error("Conflicting package evidence adapters") else . end
    | ([$records[] | .texts[]?] | unique) as $texts
    | if any($texts[]; (file($raw; .file).sha256 != .sha256) or (file($raw; .file).content != .content) or (.content | type) != "string")
      then error("Invalid adapter evidence digest") else . end
    | .evidence |= map(. as $input | (first($texts[] | select(.file == $input.logical)) // null) as $text
        | if $text == null then . else . + {kind: "text", content: $text.content} end)
    | .package_evidence_gaps = ([$records[] | .target as $target | .gaps[]? | . + {target: $target}] | unique)
    | reduce ($records | unique | .[] | select(.purl != null)) as $record (.;
        .packages += [{
          purl: $record.purl, provider: "PackageEvidenceInfo", provider_attributes: {},
          declared_version: $record.version, declared_versions: [$record.version], release_version: null,
          resolved_revision: $record.source.revision, fetched_remote: $record.source.url,
          targets: [$record.target], declared_licenses: ([$record.declarations[].terms[]] | unique),
          license_declarations: $record.declarations, package_sources: [$record.source],
          license_metadata_gaps: $record.gaps,
          legal_file_candidates: ($record.legal_file_candidates // []),
          license_evidence: $record.license_evidence, notice_evidence: $record.notice_evidence, overlay_evidence: []
        }])
    | .packages |= (group_by(.purl) | map(.[0] + {
        targets: ([.[].targets[]] | unique),
        declared_licenses: ([.[].declared_licenses[]] | unique),
        declared_versions: ([.[].declared_versions[]] | unique),
        license_evidence: ([.[].license_evidence[]] | unique),
        notice_evidence: ([.[].notice_evidence[]] | unique),
        overlay_evidence: ([.[].overlay_evidence[]] | unique)
      } + (if any(.[]; has("license_declarations")) then {
        license_declarations: ([.[].license_declarations[]?] | unique),
        package_sources: ([.[].package_sources[]?] | unique),
        license_metadata_gaps: ([.[].license_metadata_gaps[]?] | unique),
        legal_file_candidates: ([.[].legal_file_candidates[]?] | unique)
      } else {} end)) | sort_by(.purl))
    | .packages |= map(. as $package | .targets |= map(. as $target
        | if ($package.purl | startswith("pkg:cargo/")) and any($records[]; .target == $target and .purl != null and .purl != $package.purl)
          then empty else . end))
    | .packages |= map(select((.targets | length) > 0))
    | .packages as $packages
    | .targets |= map(. as $target | .packages = [$packages[] | select(.targets | index($target.label)) | .purl])
  end;

def enrich_scopes($raw):
  ([$raw.nodes[].legal_scopes[]?] | unique) as $scopes
  | reduce $scopes[] as $scope (.;
      file($raw; $scope.package).content.purl as $purl
      | if ($scope.artifacts | type) != "array" or ($scope.texts | type) != "array"
          or ($scope.gaps | type) != "array" or any($scope.gaps[]; {code: .} | valid_gap | not)
        then error("Invalid legal scope") else . end
      | if any(.packages[]; .purl == $purl) | not then error("Legal scope package is absent") else . end
      | .packages |= map(if .purl != $purl then . else
          . + {
            legal_file_candidates: (((.legal_file_candidates // []) + [$scope.texts[] |
              file($raw; .) as $input
              | if $input.kind != "text" or ($input.content | type) != "string" then error("Legal candidate is not declared text") else
                  {file: $input.logical, relative_path: ($input.logical | ltrimstr("../")), sha256: $input.sha256, association: "unresolved_scope"} end]) | unique),
            artifact_sources: (((.artifact_sources // []) + [$scope.artifacts[] |
              file($raw; .) | {file: .logical, sha256}]) | unique),
            license_metadata_gaps: (((.license_metadata_gaps // []) + [$scope.gaps[] | {code: .}]) | unique)
          } end));

def enrich_sources($raw):
  reduce ($raw.nodes[] | select(has("source_records"))) as $node (.;
    reduce $node.source_records[] as $path (.;
      file($raw; $path).content as $source
      | if ($source.url | type) != "string" then error("Invalid source declaration") else . end
      | .packages |= map(if (.targets | index($node.label)) == null then . else
          .package_sources = (((.package_sources // []) + [$source]) | unique)
        end)));


. as $raw
| if .["$schema"] != "urn:rules-supply-chain:schema:2#inventory" then error("Invalid inventory schema") else . end
| if any(.nodes[]; has("legal_catalogs")) then error("Legal catalogs are no longer supported") else . end
| [.nodes[] as $node | package_records($raw; $node)]
| group_by([.purl, .resolved_revision])
| map(.[0] + {
    declared_licenses: ([.[].declared_licenses[]] | unique),
    license_evidence: ([.[].license_evidence[]] | unique_by([.file, .sha256])),
    notice_evidence: ([.[].notice_evidence[]] | unique_by([.file, .sha256])),
    overlay_evidence: ([.[].overlay_evidence[]] | unique_by([.file, .sha256])),
    targets: ([.[].targets[]] | unique),
    declared_versions: ([.[].declared_version | select(. != null)] | unique)
  })
| sort_by([.purl, .resolved_revision])
| . as $packages
| {
    "$schema": "schema.json#metadata",
    scope: $raw.scope,
    roots: ($raw.roots | unique),
    expected_packages: ($raw.expected_packages | unique),
    packages: $packages,
    targets: [$raw.nodes[] as $node | $node | .packages = [$packages[] | select(.targets | index($node.label)) | .purl]],
    evidence: ($raw.files | sort_by(.logical))
  }
| .targets |= (group_by(.label) | map(.[0] + {
    dependencies: ([.[].dependencies[]] | unique),
    files: ([.[].files[]] | unique),
    packages: ([.[].packages[]] | unique),
    licenses: ([.[].licenses[]] | unique)
  }) | sort_by(.label))
| .unassigned_license_evidence = ([.targets[] | select((.packages | length) == 0) | .licenses[] | select(.file != null) | . + {sha256: file($raw; .file).sha256}] | unique)
| enrich($raw)
| enrich_scopes($raw)
| enrich_sources($raw)
| .expected = .expected_packages
| .gaps = (.package_evidence_gaps // [])
| .unassigned = .unassigned_license_evidence
| .files = (.evidence | map(.path = .logical | del(.logical)))
| .targets |= map(.deps = .dependencies | del(.dependencies))
| .packages |= map(
    .version = .declared_version | .versions = .declared_versions | .release = .release_version
    | .revision = .resolved_revision | .remote = .fetched_remote
    | if has("provider_attributes") then .attributes = .provider_attributes else . end
    | if has("package_sources") then .sources = .package_sources else . end
    | if has("artifact_sources") then .artifacts = .artifact_sources else . end
    | .overlays = .overlay_evidence
    | .gaps = (.license_metadata_gaps // [])
    | .licenses = {
        terms: .declared_licenses,
        declarations: [ .license_declarations[]? | if has("normalized_expression") then .normalized = .normalized_expression | del(.normalized_expression) else . end ],
        texts: .license_evidence,
        notices: .notice_evidence,
        candidates: [.legal_file_candidates[]? | .path = .relative_path | del(.relative_path)]
      }
    | del(.declared_version, .declared_versions, .release_version, .resolved_revision,
          .fetched_remote, .provider_attributes, .package_sources, .artifact_sources,
          .overlay_evidence, .license_metadata_gaps, .declared_licenses,
          .license_declarations, .license_evidence, .notice_evidence, .legal_file_candidates)
    | if .gaps == [] then del(.gaps) else . end)
| del(.expected_packages, .package_evidence_gaps, .unassigned_license_evidence, .evidence)
| if .gaps == [] then del(.gaps) else . end
