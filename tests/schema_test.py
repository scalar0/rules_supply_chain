"""Validate audit documents with the local schema bundle."""

import argparse
import copy
import json
from pathlib import Path
import tempfile
import unittest

from jsonschema import Draft202012Validator, ValidationError
from referencing import Registry, Resource

BASE = Path(__file__).resolve().parent.parent
SCHEMA_ID = "urn:rules-supply-chain:schema:2"


def load(path):
    return json.loads(Path(path).read_text())


def validator(bundle, document):
    Draft202012Validator.check_schema(bundle)
    reference = document["$schema"]
    if reference.startswith("schema.json#"):
        reference = SCHEMA_ID + reference[len("schema.json"):]
    registry = Registry().with_resource(SCHEMA_ID, Resource.from_contents(bundle))
    return Draft202012Validator({"$ref": reference}, registry=registry)


def validate(bundle, document):
    validator(bundle, document).validate(document)


class SchemaTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = BASE / "bazel-bin/tests/fixture_report"
        cls.bundle = load(cls.directory / "schema.json")
        cls.metadata = load(cls.directory / "metadata.json")

    def test_reports(self):
        for name in ("fixture_report", "empty_report"):
            directory = BASE / "bazel-bin/tests" / name
            bundle = load(directory / "schema.json")
            for report in ("metadata", "coverage", "check"):
                with self.subTest(name=name, report=report):
                    document = load(directory / f"{report}.json")
                    validate(bundle, document)
                    self.assertNotIn("schema_version", document)
        empty = load(BASE / "bazel-bin/tests/empty_report/coverage.json")
        self.assertNotIn("missing", empty)
        self.assertNotIn("gaps", empty)
        self.assertNotIn("conflicts", empty)

    def test_invalid_reports(self):
        for change in (
            lambda d: d.update(schema_version=1),
            lambda d: d.pop("roots"),
            lambda d: d.update(packages="invalid"),
            lambda d: d["files"][0].update(sha256="invalid"),
            lambda d: d["files"][0].update(path="/absolute"),
            lambda d: d["packages"][0].update(declared_licenses=[]),
            lambda d: d["packages"][0]["licenses"].update(license_evidence=[]),
            lambda d: d["packages"][0]["licenses"].update(declarations=[{
                "expression": "MIT", "terms": ["MIT"], "file": "LICENSE", "sha256": "a" * 64,
                "normalized_expression": "MIT",
            }]),
        ):
            document = copy.deepcopy(self.metadata)
            change(document)
            with self.assertRaises(ValidationError):
                validate(self.bundle, document)

    def test_relocated_bundle(self):
        with tempfile.TemporaryDirectory() as location:
            directory = Path(location)
            for name in ("metadata.json", "coverage.json", "check.json", "schema.json"):
                (directory / name).write_bytes((self.directory / name).read_bytes())
            for name in ("metadata.json", "coverage.json", "check.json"):
                validate(load(directory / "schema.json"), load(directory / name))

    def test_inventory(self):
        path = BASE / "bazel-bin/tests/fixture_report_inventory"
        validate(self.bundle, load(str(path) + ".json"))
        validate(self.bundle, load(str(path) + ".manifest.json"))

    def test_adapter(self):
        adapter = {
            "$schema": SCHEMA_ID + "#adapter",
            "packages": [{"target": "//:missing", "purl": None, "gaps": [
                {"code": "missing_manifest"}
            ]}]
        }
        validate(self.bundle, adapter)
        adapter["packages"][0]["purl"] = "invalid"
        with self.assertRaises(ValidationError):
            validate(self.bundle, adapter)

    def test_gap_codes(self):
        document = {
            "$schema": SCHEMA_ID + "#adapter",
            "packages": [{"target": "//:missing", "purl": None, "gaps": []}]
        }
        for entry in self.bundle["$defs"]["gap_code"]["oneOf"]:
            self.assertTrue(entry["description"])
            document["packages"][0]["gaps"] = [{"code": entry["const"], "file": "Cargo.toml", "field": "license"}]
            validate(self.bundle, document)
        for gap in (
            {"code": "unknown"},
            {"code": ""},
            {"kind": "missing_manifest", "message": "The manifest is absent."},
            {"code": "missing_manifest", "message": "The manifest is absent."},
            {"code": "missing_manifest", "file": None},
        ):
            document["packages"][0]["gaps"] = [gap]
            with self.subTest(gap=gap), self.assertRaises(ValidationError):
                validate(self.bundle, document)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--schema", type=Path)
    parser.add_argument("documents", nargs="*", type=Path)
    args = parser.parse_args()
    if args.schema:
        bundle = load(args.schema)
        for path in args.documents:
            validate(bundle, load(path))
        print(f"Validated {len(args.documents)} audit documents.")
    else:
        unittest.main(argv=[__file__])
