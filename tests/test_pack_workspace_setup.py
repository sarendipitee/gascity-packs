"""Tests for packer/assets/scripts/pack-workspace-setup.sh import handling."""

import os
import subprocess
import sys
import tempfile
import unittest


class TestListImportPatterns(unittest.TestCase):
    """Exercise list-import-patterns.py against synthetic pack.toml files."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.rig_root = os.path.join(self.tmp.name, "rig")
        os.makedirs(self.rig_root)
        self.script = os.path.join(
            os.path.dirname(__file__),
            "..",
            "packer",
            "assets",
            "scripts",
            "list-import-patterns.py",
        )

    def tearDown(self):
        self.tmp.cleanup()

    def _make_pack(self, pack_name, toml_content):
        pack_dir = os.path.join(self.rig_root, pack_name)
        os.makedirs(pack_dir, exist_ok=True)
        pack_toml = os.path.join(pack_dir, "pack.toml")
        with open(pack_toml, "w", encoding="utf-8") as f:
            f.write(toml_content)
        return pack_dir, pack_toml

    def _run(self, pack_pattern, pack_toml):
        result = subprocess.run(
            [sys.executable, self.script, self.rig_root, pack_pattern, pack_toml],
            capture_output=True,
            text=True,
        )
        return result

    def test_local_relative_import(self):
        self._make_pack("jjw", "")
        _, pack_toml = self._make_pack(
            "packer",
            '[imports.jjw]\nsource = "../jjw"\n',
        )
        result = self._run("packer", pack_toml)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), "jjw/")
        self.assertEqual(result.stderr, "")

    def test_local_relative_import_in_subdirectory(self):
        os.makedirs(os.path.join(self.rig_root, "packs", "jjw"))
        os.makedirs(os.path.join(self.rig_root, "packs", "packer"))
        pack_toml = os.path.join(self.rig_root, "packs", "packer", "pack.toml")
        with open(pack_toml, "w", encoding="utf-8") as f:
            f.write('[imports.jjw]\nsource = "../jjw"\n')
        result = self._run("packs/packer", pack_toml)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), "packs/jjw/")
        self.assertEqual(result.stderr, "")

    def test_url_imports_are_skipped(self):
        _, pack_toml = self._make_pack(
            "packer",
            """
[imports.http]
source = "https://example.com/pack"
[imports.git]
source = "git@github.com:gastownhall/gascity-packs.git//bmad"
[imports.ssh]
source = "ssh://git@example.com/pack"
""",
        )
        result = self._run("packer", pack_toml)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), "")
        self.assertIn("skipping remote/URL import 'http'", result.stderr)
        self.assertIn("skipping remote/URL import 'git'", result.stderr)
        self.assertIn("skipping remote/URL import 'ssh'", result.stderr)

    def test_missing_source_is_skipped(self):
        _, pack_toml = self._make_pack(
            "packer",
            """
[imports.empty]
source = ""
[imports.none]

[imports.bad]
source = "   "
""",
        )
        result = self._run("packer", pack_toml)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), "")
        self.assertIn("missing source", result.stderr)

    def test_malformed_source_is_skipped(self):
        _, pack_toml = self._make_pack(
            "packer",
            """
[imports.list]
source = ["not", "a", "string"]

[imports.int]
source = 42
""",
        )
        result = self._run("packer", pack_toml)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), "")
        self.assertIn("malformed source", result.stderr)

    def test_import_outside_rig_root_is_skipped(self):
        _, pack_toml = self._make_pack(
            "packer",
            '[imports.escape]\nsource = "../../outside"\n',
        )
        result = self._run("packer", pack_toml)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), "")
        self.assertIn("resolves outside rig root", result.stderr)

    def test_absolute_import_outside_rig_root_is_skipped(self):
        _, pack_toml = self._make_pack(
            "packer",
            f'[imports.abs]\nsource = "{self.tmp.name}/outside"\n',
        )
        result = self._run("packer", pack_toml)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), "")
        self.assertIn("resolves outside rig root", result.stderr)

    def test_import_resolving_to_rig_root_is_skipped(self):
        _, pack_toml = self._make_pack(
            "packer",
            '[imports.root]\nsource = ".."\n',
        )
        result = self._run("packer", pack_toml)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), "")
        self.assertIn("resolves outside rig root", result.stderr)

    def test_nonexistent_local_import_is_skipped(self):
        _, pack_toml = self._make_pack(
            "packer",
            '[imports.missing]\nsource = "../missing"\n',
        )
        result = self._run("packer", pack_toml)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), "")
        self.assertIn("does not resolve to a directory", result.stderr)

    def test_file_import_is_skipped(self):
        jjw_dir = os.path.join(self.rig_root, "jjw")
        os.makedirs(jjw_dir)
        # Replace the directory with a file.
        os.rmdir(jjw_dir)
        with open(jjw_dir, "w", encoding="utf-8") as f:
            f.write("not a directory")
        _, pack_toml = self._make_pack(
            "packer",
            '[imports.jjw]\nsource = "../jjw"\n',
        )
        result = self._run("packer", pack_toml)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), "")
        self.assertIn("does not resolve to a directory", result.stderr)

    def test_symlink_escape_is_skipped(self):
        outside = os.path.join(self.tmp.name, "outside")
        os.makedirs(outside)
        link_target = os.path.join(self.rig_root, "escape")
        os.symlink(outside, link_target)
        _, pack_toml = self._make_pack(
            "packer",
            '[imports.escape]\nsource = "../escape"\n',
        )
        result = self._run("packer", pack_toml)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), "")
        self.assertIn("resolves outside rig root", result.stderr)

    def test_valid_and_invalid_imports_mixed(self):
        self._make_pack("jjw", "")
        _, pack_toml = self._make_pack(
            "packer",
            """
[imports.jjw]
source = "../jjw"

[imports.remote]
source = "https://example.com/pack"

[imports.missing]
source = "../missing"
""",
        )
        result = self._run("packer", pack_toml)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), "jjw/")
        self.assertIn("skipping remote/URL import 'remote'", result.stderr)
        self.assertIn("does not resolve to a directory", result.stderr)


if __name__ == "__main__":
    unittest.main()
