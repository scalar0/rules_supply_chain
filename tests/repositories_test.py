"""Test source selection and explicit refresh against a local Git repository."""

import json
from pathlib import Path
import subprocess
import tempfile
import unittest

MODULE = Path(__file__).resolve().parent.parent


def run(args, cwd):
    result = subprocess.run(args, cwd=cwd, capture_output=True, text=True)
    if result.returncode:
        raise AssertionError(result.stdout + result.stderr)
    return result.stdout.strip()


class RepositoryTests(unittest.TestCase):
    def test_sources(self):
        with tempfile.TemporaryDirectory(prefix="source-test-") as location:
            root = Path(location)
            remote = root / "upstream"
            remote.mkdir()
            run(["git", "init", "-b", "main"], remote)
            run(["git", "config", "commit.gpgsign", "false"], remote)
            run(["git", "config", "core.hooksPath", "/dev/null"], remote)
            run(["git", "config", "user.name", "Source fixture"], remote)
            run(["git", "config", "user.email", "fixture@example.invalid"], remote)

            def commit(value):
                (remote / "value.txt").write_text(value)
                run(["git", "add", "value.txt"], remote)
                run(["git", "commit", "-m", "Update fixture"], remote)
                return run(["git", "rev-parse", "HEAD"], remote)

            first = commit("first")
            consumer = root / "consumer"
            consumer.mkdir()
            (consumer / ".bazelversion").write_text((MODULE / ".bazelversion").read_text())
            (consumer / "overlay.bazel").write_text('exports_files(["value.txt"])\nalias(name="owner", actual="@{owner}//:local.txt", visibility=["//visibility:public"])\n')
            (consumer / "local.txt").write_text("owner")
            (consumer / "BUILD.bazel").write_text(
                'exports_files(["overlay.bazel", "local.txt"])\n'
                'filegroup(name="inputs", srcs=["@sample//:value.txt", "@sample//:owner", "@source_repositories//:sample"])\n'
            )
            prefix = [
                "bazel", f"--output_base={root / 'output'}",
                "--host_jvm_args=-Xmx512m",
            ]

            def configure(selector, duplicate=False):
                declaration = (
                    'sources.git(name="sample", remote=' + json.dumps(str(remote))
                    + ', build_file="//:overlay.bazel", ' + selector + ')\n'
                )
                (consumer / "MODULE.bazel").write_text(
                    'module(name="source_fixture")\n'
                    'bazel_dep(name="rules_supply_chain", version="0.1.0")\n'
                    'local_path_override(module_name="rules_supply_chain", path=' + json.dumps(str(MODULE)) + ')\n'
                    'sources=use_extension("@rules_supply_chain//:repositories.bzl", "sources")\n'
                    'use_repo(sources, "sample", "source_repositories")\n'
                    + declaration * (2 if duplicate else 1)
                )

            def build():
                run(prefix + ["build", "//:inputs"], consumer)
                paths = run(prefix + ["cquery", "//:inputs", "--output=files"], consumer).splitlines()
                execution_root = Path(run(prefix + ["info", "execution_root"], consumer))
                files = {Path(path).name: execution_root / path for path in paths}
                return files["value.txt"].read_text(), json.loads(files["sample.json"].read_text())

            try:
                configure('branch="main"')
                value, source = build()
                self.assertEqual(value, "first")
                self.assertIsNone(source["revision"])
                self.assertEqual(source["branch"], "main")
                commit("second")
                self.assertEqual(build()[0], "first")
                run(prefix + ["fetch", "--force", "--repo=@sample"], consumer)
                self.assertEqual(build()[0], "second")
                configure('commit=' + json.dumps(first))
                value, source = build()
                self.assertEqual(value, "first")
                self.assertEqual(source["revision"], first)
                for selector, duplicate, message in [
                    ('branch="main", commit="' + first + '"', False, "exactly one"),
                    ('branch=""', False, "exactly one"),
                    ('commit="short"', False, "full lowercase commit"),
                    ('branch="main"', True, "Duplicate source name"),
                ]:
                    configure(selector, duplicate)
                    with self.assertRaisesRegex(AssertionError, message):
                        build()
            finally:
                subprocess.run(prefix + ["shutdown"], cwd=consumer, capture_output=True)


if __name__ == "__main__":
    unittest.main()
