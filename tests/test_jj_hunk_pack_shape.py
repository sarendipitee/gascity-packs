from __future__ import annotations

import stat
import tomllib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PACK = ROOT / "jj-hunk"
MATURE_TMUX_HELPERS = {
    "gastown/assets/scripts/agent-menu.sh",
    "gastown/assets/scripts/bind-key.sh",
    "gastown/assets/scripts/cycle.sh",
    "gastown/assets/scripts/status-line.sh",
    "gastown/assets/scripts/tmux-keybindings.sh",
    "gastown/assets/scripts/tmux-theme.sh",
    "gastown-lazyjj/assets/scripts/tmux-scroll.sh",
}


def load_toml(path: Path) -> dict:
    with path.open("rb") as handle:
        return tomllib.load(handle)


def is_executable(path: Path) -> bool:
    return bool(path.stat().st_mode & stat.S_IXUSR)


def test_pack_imports_jjw_and_declares_tasksmith_named_session() -> None:
    manifest = load_toml(PACK / "pack.toml")

    assert manifest["pack"]["name"] == "jj-hunk"
    assert manifest["pack"]["schema"] == 2
    assert manifest["imports"]["jjw"]["source"] == "../jjw"
    assert set(manifest["providers"]) == {"omp-tasksmith", "omp-surgeon"}

    named_sessions = manifest["named_session"]
    assert {"template": "tasksmith", "scope": "rig", "mode": "always"} in named_sessions
    assert all(session["template"] != "surgeon" for session in named_sessions)


def test_tasksmith_is_named_session_and_surgeon_is_pool_agent() -> None:
    manifest = load_toml(PACK / "pack.toml")
    tasksmith = load_toml(PACK / "agents" / "tasksmith" / "agent.toml")

    assert tasksmith["scope"] == "rig"
    assert tasksmith["provider"] == "omp-tasksmith"
    assert tasksmith["formula"] == "mol-jj-hunk-subagent-task"
    assert tasksmith["work_dir"] == "{{.RigRoot}}"
    assert "min_active_sessions" not in tasksmith
    assert "max_active_sessions" not in tasksmith
    assert not (PACK / "agents" / "tasksmith" / "namepool.txt").exists()

    surgeon = load_toml(PACK / "agents" / "surgeon" / "agent.toml")

    assert surgeon["scope"] == "rig"
    assert surgeon["provider"] == "omp-surgeon"
    assert surgeon["formula"] == "mol-jj-hunk-work"
    assert surgeon["work_dir"] == ".gc/workspaces/{{.Rig}}/jedi/{{.AgentBase}}"
    assert surgeon["min_active_sessions"] == 0
    assert surgeon["max_active_sessions"] >= 1
    assert (PACK / "agents" / "surgeon" / "namepool.txt").is_file()

    assert len(surgeon["pre_start"]) == 1
    pre_start = surgeon["pre_start"][0]
    jjw_workspace_setup = (
        f"{{{{.ConfigDir}}}}/{manifest['imports']['jjw']['source']}/"
        "assets/scripts/workspace-setup.sh"
    )
    assert pre_start.startswith(jjw_workspace_setup)
    assert "{{.RigRoot}}" in pre_start
    assert "{{.WorkDir}}" in pre_start
    assert "{{.AgentBase}}" in pre_start
    assert "--sync" in pre_start
    assert "JJ_HUNK_WORK_BEAD_ID" in pre_start
    assert not (PACK / "assets" / "scripts" / "workspace-setup.sh").exists()


def test_command_and_doctor_entry_points_are_present_and_executable() -> None:
    commands = {
        "commit",
        "lightjj-annotate",
        "list",
        "spec",
        "split",
        "squash",
    }
    doctors = {"check-jj-hunk", "check-jj-repo"}

    assert {path.name for path in (PACK / "commands").iterdir() if path.is_dir()} == commands
    for command in commands:
        command_dir = PACK / "commands" / command
        command_toml = load_toml(command_dir / "command.toml")

        assert command_toml["description"]
        assert (command_dir / "run.sh").is_file()
        assert is_executable(command_dir / "run.sh")

    assert {path.name for path in (PACK / "doctor").iterdir() if path.is_dir()} == doctors
    for doctor in doctors:
        doctor_dir = PACK / "doctor" / doctor
        doctor_toml = load_toml(doctor_dir / "doctor.toml")

        assert doctor_toml["description"]
        assert (doctor_dir / "run.sh").is_file()
        assert is_executable(doctor_dir / "run.sh")


def test_formula_skill_and_template_fragment_entry_points_are_present() -> None:
    formulas = {"mol-jj-hunk-subagent-task", "mol-jj-hunk-work"}
    skills = {"jj-subagent-workspaces", "jj-surgeon"}
    template_fragments = {
        "jj-hunk-agent-safety.template.md",
        "jj-hunk-reference.template.md",
    }

    assert {path.stem for path in (PACK / "formulas").glob("*.toml")} == formulas
    for formula in formulas:
        formula_toml = load_toml(PACK / "formulas" / f"{formula}.toml")

        assert formula_toml["formula"] == formula
        assert formula_toml["version"] == 1
        assert formula_toml["steps"]

    assert {path.name for path in (PACK / "skills").iterdir() if path.is_dir()} == skills
    for skill in skills:
        skill_text = (PACK / "skills" / skill / "SKILL.md").read_text(encoding="utf-8")

        assert f"name: {skill}" in skill_text

    assert {path.name for path in (PACK / "template-fragments").iterdir()} == template_fragments
    for fragment in template_fragments:
        assert (PACK / "template-fragments" / fragment).read_text(encoding="utf-8").strip()


def test_docs_diagrams_cover_formula_entry_points() -> None:
    formulas = {path.stem for path in (PACK / "formulas").glob("*.toml")}
    diagrams_dir = PACK / "docs" / "diagrams"
    index = (diagrams_dir / "README.md").read_text(encoding="utf-8")

    for formula in formulas:
        diagram = diagrams_dir / f"{formula}.md"

        assert diagram.is_file()
        assert formula in diagram.read_text(encoding="utf-8")
        assert f"[{formula}.md]" in index


def test_workspace_setup_and_tmux_reuse_contract_is_documented() -> None:
    readme = (PACK / "README.md").read_text(encoding="utf-8")
    local_script_names = {
        path.name
        for path in PACK.rglob("*")
        if path.is_file() and ("tmux" in path.name or path.name == "workspace-setup.sh")
    }

    assert "jjw/assets/scripts/workspace-setup.sh" in readme
    assert "does not ship local tmux or workspace lifecycle scripts" in readme
    assert local_script_names == set()

    for helper in MATURE_TMUX_HELPERS:
        assert (ROOT / helper).is_file()
        assert helper in readme


def test_readme_documents_jj_hunk_entry_points() -> None:
    readme = (PACK / "README.md").read_text(encoding="utf-8")

    for expected in [
        "`jjw/assets/scripts/workspace-setup.sh`",
        "`gastown-lazyjj/assets/scripts/tmux-scroll.sh`",
        "`docs/diagrams/mol-jj-hunk-work.md`",
        "`docs/diagrams/mol-jj-hunk-subagent-task.md`",
        "`jj-subagent-workspaces`",
        "`jj-surgeon`",
        "`tasksmith`",
        "`surgeon`",
        "`gc jj-hunk list`",
        "`gc jj-hunk spec`",
        "`gc jj-hunk split`",
        "`gc jj-hunk commit`",
        "`gc jj-hunk squash`",
        "`gc jj-hunk lightjj-annotate`",
        "`mol-jj-hunk-work`",
        "`mol-jj-hunk-subagent-task`",
        "gc lint jj-hunk",
        "python3 -m pytest tests/test_jj_hunk_pack_shape.py -q",
        "gc doctor --json",
        "gc formula show mol-jj-hunk-work",
        "gc formula show mol-jj-hunk-subagent-task",
        "gc prime gascity-packs/jj-hunk.tasksmith --strict",
        "gc prime surgeon --strict",
    ]:
        assert expected in readme
