#!/usr/bin/env -S just --justfile

# Check Starlark and shell syntax without changing files.
lint:
    rg --files --hidden -g '*.bzl' -g '*.bazel' -g '!bazel-*' | xargs buildifier -lint=warn -mode=check
    bash -n private/digest.sh tests/report_test.sh tests/adapter_test.sh

# Run the module tests and build the API references.
test *args:
    bazel test //... {{args}}

# Build the API references under bazel-bin/docs/generated.
docs-build *args:
    bazel build //docs:reference {{args}}

# Build the independent consumer example.
[working-directory: 'examples/basic']
example *args:
    bazel build //:audit {{args}}

# Validate the exported schemas and fixtures without network schema resolution.
schema-check:
    bazel build //tests:fixture_report //tests:empty_report --lockfile_mode=error
    uv run --project tests --locked tests/schema_test.py

# Test branch refresh and commit selection against a local Git repository.
source-check:
    uv run --project tests --locked tests/repositories_test.py

# Check the module, API reference, consumer, and dependency lockfiles.
check: lint
    bazel mod deps --lockfile_mode=error
    just test --lockfile_mode=error
    just schema-check
    just source-check
    cd examples/basic && bazel mod deps --lockfile_mode=error
    just example --lockfile_mode=error
