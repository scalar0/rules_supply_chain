#!/usr/bin/env -S just --justfile

# Check Starlark and shell syntax without changing files.
lint:
    rg --files --hidden -g '*.bzl' -g '*.bazel' -g '!bazel-*' | xargs buildifier -lint=warn -mode=check
    bash -n private/digest.sh tests/report_test.sh

# Run the standalone module tests.
test *args:
    bazel test //... {{args}}

# Build the independent consumer example.
[working-directory: 'examples/basic']
example *args:
    bazel build //:audit {{args}}

# Check the module, consumer, and their dependency lockfiles.
check: lint
    bazel mod deps --lockfile_mode=error
    just test --lockfile_mode=error
    cd examples/basic && bazel mod deps --lockfile_mode=error
    just example --lockfile_mode=error
