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
. as $raw
| if .schema_version != 1 then error("Invalid schema version") else . end
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
    schema_version: 1,
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
