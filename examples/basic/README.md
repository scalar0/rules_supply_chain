# Consumer example

This directory is an independent Bazel module.
It uses the public `report` API through a local module override.
It supplies no copies of the reporting scripts or filters.

Run `bazel build //:audit` from this directory.
Inspect the four report outputs under `bazel-bin/audit/`.
The input has an MIT license and explicit evidence from `origin.txt`.
The report requires that evidence without using a special scope name.
