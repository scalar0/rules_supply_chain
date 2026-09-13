"""Compose deterministic reports with jq.bzl."""

load("@jq.bzl", "jq")
load("//private:collect.bzl", "inventory")

def report(name, roots, expected_packages = [], evidence = [], overlay_evidence = {}, required_overlay_packages = []):
    """Create metadata, coverage, notices, and a structural check.

    The target is a filegroup with four outputs under `<name>/`:
    `metadata.json`, `coverage.json`, `notices.txt`, and `check.json`.
    The macro also declares `<name>_inventory` and one target per report suffix.
    A failed structural check fails the build of the combined target.
    The module supplies the filters and scripts through repository labels.

    Args:
        name: The report scope, target name, and output directory name.
        roots: Targets whose source dependencies and package providers define the report.
        expected_packages: Required package identities for the structural check.
        evidence: Additional source, manifest, license, or notice files to digest.
        overlay_evidence: Package identities mapped to lists of evidence labels.
        required_overlay_packages: Package identities that must have overlay evidence.
    """
    bindings = {}
    for purl, labels in overlay_evidence.items():
        for label in labels:
            bindings.setdefault(label, []).append(purl)
    inventory(
        name = name + "_inventory",
        roots = roots,
        scope = name,
        evidence = evidence,
        expected_packages = expected_packages,
        overlay_bindings = {label: json.encode(purls) for label, purls in bindings.items()},
    )
    jq(
        name = name + "_metadata",
        srcs = [":" + name + "_inventory"],
        filter_file = Label("//private:metadata.jq"),
        args = ["--sort-keys"],
        out = name + "/metadata.json",
    )
    jq(
        name = name + "_coverage",
        srcs = [":" + name + "_metadata"],
        filter_file = Label("//private:coverage.jq"),
        args = ["--sort-keys"],
        out = name + "/coverage.json",
    )
    jq(
        name = name + "_notices",
        srcs = [":" + name + "_metadata"],
        filter_file = Label("//private:notices.jq"),
        args = ["--join-output"],
        out = name + "/notices.txt",
    )
    jq(
        name = name + "_check",
        srcs = [":" + name + "_metadata", ":" + name + "_coverage"],
        filter_file = Label("//private:check.jq"),
        args = ["--slurp", "--exit-status", "--sort-keys", "--argjson", "required_overlay_packages", "'" + json.encode(required_overlay_packages).replace("'", "'\"'\"'") + "'"],
        out = name + "/check.json",
    )
    native.filegroup(
        name = name,
        srcs = [":" + name + "_metadata", ":" + name + "_coverage", ":" + name + "_notices", ":" + name + "_check"],
    )
