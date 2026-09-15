def require($condition; $message): if $condition then . else error($message) end;
.[0] as $m | .[1] as $c
| require($m["$schema"] == "schema.json#metadata" and $c["$schema"] == "schema.json#coverage"; "Invalid report schema")
| require($m.scope == $c.scope; "Report scopes differ")
| require(all($m.packages[]; all(.licenses.declarations[]?; . as $d | any($m.files[]; .path == $d.file and .sha256 == $d.sha256 and (.content | type) == "string"))); "Invalid license declaration evidence")
| require(all($m.packages[]; .licenses.terms == ([.licenses.texts[].terms[], .licenses.declarations[]?.terms[]] | unique)); "License declaration summary differs")
| require(($m.gaps // []) == ($c.gaps // []); "Adapter gap coverage differs")
| require(all($m.packages[]; (.purl | type) == "string" and (.purl | test("^pkg:[a-z][a-z0-9.+-]*/[^/?#[:space:]]+(/[^/?#[:space:]]+)*(\\?[^#[:space:]]+)?(#[^[:space:]]+)?$"))); "Invalid package identity")
| require(($m.expected - [$m.packages[].purl] | length) == 0; "A configured package is absent")
| require(all($m.packages[]; .revision == null or (.revision | test("^[0-9a-f]{40}$|^[0-9a-f]{64}$"))); "Invalid checkout revision")
| require(all($m.packages[]; all(.overlays[]; . as $e | any($m.files[]; .path == $e.file and .sha256 == $e.sha256))); "Invalid overlay evidence")
| require(all($m.targets[]; all(.deps[]; .target as $t | any($m.targets[]; .label == $t))); "Invalid dependency reference")
| require(all($m.targets[]; all(.packages[]; . as $p | any($m.packages[]; .purl == $p))); "Invalid package reference")
| require(all($m.roots[]; . as $root | any($m.targets[]; .label == $root)); "Invalid root reference")
| require(all($m.files[]; (.sha256 | test("^[0-9a-f]{64}$")) and (.path | startswith("/") | not)); "Invalid evidence record")
| require(all($m.packages[]; all((.licenses.texts + .licenses.notices)[]; . as $e | any($m.files[]; .path == $e.file and .sha256 == $e.sha256 and (.content | type) == "string"))); "Invalid license evidence")
| require(all($m.packages[]; all(.licenses.candidates[]?; . as $e |
    .association == "unresolved_scope" and (.path | type) == "string"
    and (.path | test("(^/|(^|/)\\.\\.(/|$))") | not)
    and any($m.files[]; .path == $e.file and .sha256 == $e.sha256 and (.content | type) == "string"))); "Invalid legal candidate evidence")
| require(all($m.packages[]; all(.sources[]?.publisher_vcs | select(. != null); . as $v |
    (.path_in_vcs == null or (.path_in_vcs | type) == "string") and
    .trust == "publisher_supplied" and (.revision | test("^[0-9a-fA-F]{40}$|^[0-9a-fA-F]{64}$"))
    and any($m.files[]; .path == $v.file and .sha256 == $v.sha256 and (.content | type) == "string"))); "Invalid publisher VCS evidence")
| require(all($m.packages[]; all(.licenses.declarations[]? | select(has("parsing"));
    (.parsing == "valid" and .normalized == .expression and .normalization == null)
    or (.parsing == "normalized" and (.normalized | type) == "string" and .normalization == "cargo_slash_to_or")
    or ((.parsing == "invalid" or .parsing == "missing") and .normalized == null and .normalization == null))); "Invalid declaration parsing state")
| require(($c.assessment // null) == null or $c.assessment == {inputs:"declared_bazel_inputs",completeness:"not_established",policy:"not_evaluated"}; "Invalid assessment scope")
| require(all($m.unassigned[]; . as $e | any($m.files[]; .path == $e.file and .sha256 == $e.sha256 and (.content | type) == "string")); "Invalid unassigned license evidence")
| require(all($m.packages[]; all(.artifacts[]?; . as $e | any($m.files[]; .path == $e.file and .sha256 == $e.sha256))); "Invalid artifact evidence")
| require(all(($ARGS.named.required_overlay_packages // [])[]; . as $p | any($m.packages[]; .purl == $p and (.overlays | length) > 0)); "Missing overlay evidence")
| require(($c.conflicts // [] | length) == 0; "Conflicting declarations")
| require(($c.missing.texts // [] | sort) == ([$m.packages[] | select((.licenses.texts | length) == 0) | .purl] | unique); "License coverage differs")
| require(($c.missing.identities // []) == ([$m.targets[] | select(.helper == false and .kind != "source_file" and (.packages | length) == 0) | .label] | unique); "Identity coverage differs")
| require(($c.missing.terms // []) == ([$m.packages[] | select((.licenses.terms | length) == 0) | .purl] | unique); "Terms coverage differs")
| {"$schema": "schema.json#check", scope: $m.scope, valid: true}
