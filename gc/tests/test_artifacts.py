from __future__ import annotations

import importlib.util
import os
import pathlib
import tempfile
import unittest


SCRIPT_PATH = pathlib.Path(__file__).resolve().parents[1] / "assets" / "scripts" / "artifacts.py"


def load_artifacts_module():
    spec = importlib.util.spec_from_file_location("gc_artifacts", SCRIPT_PATH)
    if spec is None or spec.loader is None:
        raise AssertionError("could not load artifacts.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ArtifactHelperTests(unittest.TestCase):
    def setUp(self) -> None:
        self._old_env = os.environ.copy()

    def tearDown(self) -> None:
        os.environ.clear()
        os.environ.update(self._old_env)

    def test_helper_is_executable(self) -> None:
        self.assertTrue(os.access(SCRIPT_PATH, os.X_OK))

    def test_empty_override_defaults_to_rig_plans_directory(self) -> None:
        module = load_artifacts_module()
        with tempfile.TemporaryDirectory() as temp_dir:
            os.environ["GC_RIG_ROOT"] = temp_dir
            self.assertEqual(
                module.resolve_artifact_root(""),
                pathlib.Path(temp_dir).resolve() / "plans",
            )

    def test_explicit_override_wins_over_default_root(self) -> None:
        module = load_artifacts_module()
        with tempfile.TemporaryDirectory() as temp_dir:
            override = pathlib.Path(temp_dir) / "custom" / "artifact-root"

            self.assertEqual(module.resolve_artifact_root(str(override)), override.resolve())

    def test_foreign_plans_directory_falls_back_to_gc_plans(self) -> None:
        module = load_artifacts_module()
        with tempfile.TemporaryDirectory() as temp_dir:
            rig_root = pathlib.Path(temp_dir)
            plans = rig_root / "plans"
            plans.mkdir()
            (plans / "team-roadmap.md").write_text("# Roadmap\n", encoding="utf-8")

            self.assertEqual(
                module.resolve_artifact_root("", rig_root=str(rig_root)),
                rig_root.resolve() / "gc-plans",
            )

    def test_gc_owned_plans_directory_is_stable_across_runs(self) -> None:
        module = load_artifacts_module()
        with tempfile.TemporaryDirectory() as temp_dir:
            rig_root = pathlib.Path(temp_dir)
            plans = rig_root / "plans"
            plans.mkdir()
            (plans / ".gc-plans").write_text("", encoding="utf-8")

            self.assertEqual(
                module.resolve_artifact_root("", rig_root=str(rig_root)),
                plans.resolve(),
            )

    def test_leading_slash_paths_are_artifact_root_relative(self) -> None:
        module = load_artifacts_module()
        with tempfile.TemporaryDirectory() as temp_dir:
            target = module.resolve_artifact_path(
                temp_dir,
                "/github/issues/gastownhall/gascity/11/source.json",
            )
            self.assertEqual(
                target,
                pathlib.Path(temp_dir).resolve()
                / "github"
                / "issues"
                / "gastownhall"
                / "gascity"
                / "11"
                / "source.json",
            )

    def test_artifact_path_rejects_root_escape(self) -> None:
        module = load_artifacts_module()
        with tempfile.TemporaryDirectory() as temp_dir:
            with self.assertRaises(ValueError):
                module.resolve_artifact_path(temp_dir, "../outside")


if __name__ == "__main__":
    unittest.main()
