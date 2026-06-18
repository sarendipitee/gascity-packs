from __future__ import annotations

import os
import pathlib
import subprocess
import tempfile
import textwrap
import unittest


SCRIPT = pathlib.Path(__file__).resolve().parents[2] / "maintenance" / "assets" / "scripts" / "prune-branches.sh"


class PruneBranchesScriptTests(unittest.TestCase):
    def _run(self, script: str, workdir: pathlib.Path, env: dict[str, str]) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["/usr/bin/env", "bash", "-lc", script],
            cwd=workdir,
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )

    def _make_repo(self, root: pathlib.Path) -> pathlib.Path:
        remote = root / "origin.git"
        subprocess.run(["git", "init", "--bare", remote.as_posix()], check=True, capture_output=True, text=True)
        repo = root / "rig"
        repo.mkdir()
        subprocess.run(["git", "init", "-b", "live"], cwd=repo, check=True, capture_output=True, text=True)
        subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=repo, check=True)
        subprocess.run(["git", "config", "user.name", "Test User"], cwd=repo, check=True)
        (repo / "README.md").write_text("base\n", encoding="utf-8")
        subprocess.run(["git", "add", "README.md"], cwd=repo, check=True)
        subprocess.run(["git", "commit", "-m", "base"], cwd=repo, check=True, capture_output=True, text=True)
        subprocess.run(["git", "remote", "add", "origin", remote.as_posix()], cwd=repo, check=True, capture_output=True, text=True)
        subprocess.run(["git", "push", "-u", "origin", "live"], cwd=repo, check=True, capture_output=True, text=True)
        subprocess.run(["git", "branch", "polecat/gc-pack-xm3"], cwd=repo, check=True, capture_output=True, text=True)
        subprocess.run(["git", "checkout", "live"], cwd=repo, check=True, capture_output=True, text=True)
        return repo

    def test_prunes_closed_polecat_branch(self) -> None:
        script_text = SCRIPT.read_text(encoding="utf-8")
        self.assertIn("branch --list 'polecat/*'", script_text)
        self.assertIn("Only prune branches for closed beads", script_text)

    def test_preserves_rejected_polecat_branch(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            root = pathlib.Path(tmpdir)
            repo = self._make_repo(root)
            fakebin = root / "bin"
            fakebin.mkdir()
            gc = fakebin / "gc"
            gc.write_text(
                textwrap.dedent(
                    f"""\
                    #!/usr/bin/env bash
                    set -euo pipefail
                    if [ "$1" = "rig" ] && [ "$2" = "list" ]; then
                      cat <<'JSON'
                    {{"rigs":[{{"path":"{repo}"}}]}}
                    JSON
                      exit 0
                    fi
                    if [ "$1" = "bd" ] && [ "$2" = "list" ]; then
                      cat <<'JSON'
                    [{{"id":"gc-pack-xm3","status":"open","metadata":{{"branch":"polecat/gc-pack-xm3","rejection_reason":"conflict"}}}}]
                    JSON
                      exit 0
                    fi
                    if [ "$1" = "bd" ] && [ "$2" = "show" ]; then
                      cat <<'JSON'
                    [{{"id":"gc-pack-xm3","status":"open","metadata":{{"branch":"polecat/gc-pack-xm3","rejection_reason":"conflict"}}}}]
                    JSON
                      exit 0
                    fi
                    exit 1
                    """
                ),
                encoding="utf-8",
            )
            gc.chmod(0o755)

            env = os.environ.copy()
            env["PATH"] = f"{fakebin}:{env['PATH']}"

            result = self._run(f"bash {SCRIPT}", root, env)

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                subprocess.run(
                    ["git", "show-ref", "--verify", "--quiet", "refs/heads/polecat/gc-pack-xm3"],
                    cwd=repo,
                    check=False,
                ).returncode,
                0,
                result.stdout,
            )
