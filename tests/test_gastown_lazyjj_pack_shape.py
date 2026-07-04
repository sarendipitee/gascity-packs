from __future__ import annotations

import json
import stat
import tomllib
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
PACK_ROOT = REPO_ROOT / "gastown-lazyjj"


TUTORIAL_SLUGS = {
    "create-pr",
    "create-stack",
    "edit-mid-stack",
    "navigate-stack",
    "resolve-conflicts",
    "sync-remote",
}

EXPECTED_FORMULAS = {
    "mol-lazyjj-create-pr.toml",
    "mol-lazyjj-create-stack.toml",
    "mol-lazyjj-cross-workspace-sync.toml",
    "mol-lazyjj-edit-mid-stack.toml",
    "mol-lazyjj-navigate-stack.toml",
    "mol-lazyjj-publish.toml",
    "mol-lazyjj-resolve-conflicts.toml",
    "mol-lazyjj-runtime-verify.toml",
    "mol-lazyjj-sync-remote.toml",
    "mol-polecat-lazyjj-work.toml",
}

EXPECTED_FRAGMENTS = {
    "doltlite-gascity-city-basics.template.md",
    "gc-role-worker.template.md",
    "lazyjj-common-mistakes.template.md",
    "lazyjj-config-reference.template.md",
    "lazyjj-create-pr.template.md",
    "lazyjj-create-stack.template.md",
    "lazyjj-edit-mid-stack.template.md",
    "lazyjj-git-differences.template.md",
    "lazyjj-introduction.template.md",
    "lazyjj-mental-model.template.md",
    "lazyjj-navigate-stack.template.md",
    "lazyjj-operation-log.template.md",
    "lazyjj-pr-workflow.template.md",
    "lazyjj-quickstart.template.md",
    "lazyjj-resolve-conflicts.template.md",
    "lazyjj-revsets-advanced.template.md",
    "lazyjj-stack-workflow.template.md",
    "lazyjj-sync-remote.template.md",
    "lazyjj-workspace-refresh.template.md",
    "test-policy.template.md",
}


def read_pack_text(relative_path: str) -> str:
    return (PACK_ROOT / relative_path).read_text(encoding="utf-8")


def load_pack_toml(relative_path: str) -> dict:
    return tomllib.loads(read_pack_text(relative_path))


def test_pack_manifest_and_readme_keep_entrypoints_workspace_relative() -> None:
    manifest = load_pack_toml("pack.toml")

    assert manifest["pack"]["name"] == "gastown-lazyjj"
    assert manifest["pack"]["schema"] == 2
    assert (
        "{{.ConfigDir}}/assets/scripts/tmux-scroll.sh {{.Session}}"
        in manifest["global"]["session_live"]
    )

    readme = read_pack_text("README.md")
    assert "## Pack entry points" in readme
    for entrypoint in [
        "pack.toml",
        "agents/jedi/prompt.template.md",
        "agents/tasksmith/prompt.template.md",
        "formulas/mol-polecat-lazyjj-work.toml",
        "formulas/mol-lazyjj-publish.toml",
    ]:
        assert f"]({ './' + entrypoint })" in readme

    # Regression for the earlier workspace mismatch: tests must resolve the
    # pack from the repository root and never embed a routed workspace path.
    assert PACK_ROOT == REPO_ROOT / "gastown-lazyjj"
    source_text = Path(__file__).read_text(encoding="utf-8")
    assert "gp-qmh" + ".4" not in source_text


def test_agent_configs_and_prompts_pin_lazyjj_workspace_contract() -> None:
    jedi_agent = load_pack_toml("agents/jedi/agent.toml")
    runner_agent = load_pack_toml("agents/runner/agent.toml")
    tasksmith_agent = load_pack_toml("agents/tasksmith/agent.toml")

    assert jedi_agent["provider"] == "codex-mini"
    assert jedi_agent["work_dir"] == ".gc/workspaces/{{.Rig}}/jedi/{{.AgentBase}}"
    assert any(
        "assets/scripts/workspace-setup.sh" in command and "--sync" in command
        for command in jedi_agent["pre_start"]
    )
    assert runner_agent["provider"] == "codex-runner"
    assert tasksmith_agent["provider"] == "codex-gpt-5-5"

    jedi_prompt = read_pack_text("agents/jedi/prompt.template.md")
    for required in [
        "metadata.lazyjj_workspace",
        "metadata.lazyjj_workspace_dir",
        "GC_SESSION_NAME",
        "mol-polecat-lazyjj-work",
        '{{ template "lazyjj-workspace-refresh" . }}',
    ]:
        assert required in jedi_prompt

    runner_prompt = read_pack_text("agents/runner/prompt.template.md")
    for required in [
        "default@",
        "jj workspace list",
        "Do not implement feature work here",
        '{{ template "lazyjj-workspace-refresh" . }}',
    ]:
        assert required in runner_prompt

    tasksmith_prompt = read_pack_text("agents/tasksmith/prompt.template.md")
    for required in [
        "mol-polecat-lazyjj-work",
        "LazyJJ Workspace Seed",
        "LAZYJJ_WORK_BEAD_ID",
    ]:
        assert required in tasksmith_prompt

    example_beads = read_pack_text("agents/tasksmith/lazyjj-pack-beads.yaml")
    assert "formula: mol-polecat-lazyjj-work" in example_beads

    role_worker_fragment = read_pack_text("agents/jedi/gc-role-worker.template.md")
    for required in ["GC_CLAIM", "gc hook --claim --json", "gc runtime drain-ack"]:
        assert required in role_worker_fragment


def test_lazyjj_formula_skill_and_template_fragment_surfaces_are_complete() -> None:
    formula_dir = PACK_ROOT / "formulas"
    actual_formulas = {path.name for path in formula_dir.glob("*.toml")}
    assert EXPECTED_FORMULAS <= actual_formulas

    for formula_file in EXPECTED_FORMULAS:
        formula = load_pack_toml(f"formulas/{formula_file}")
        assert formula["formula"] == formula_file.removesuffix(".toml")
        assert formula.get("steps"), f"{formula_file} should define workflow steps"

    skill_dir = PACK_ROOT / "skills"
    for slug in TUTORIAL_SLUGS:
        skill = skill_dir / f"lazyjj-{slug}" / "SKILL.md"
        assert skill.is_file()
        skill_text = skill.read_text(encoding="utf-8")
        assert f"lazyjj-{slug}" in skill_text

    workspace_skill = skill_dir / "lazyjj-workspace" / "SKILL.md"
    assert workspace_skill.is_file()
    workspace_skill_text = workspace_skill.read_text(encoding="utf-8")
    assert "workspace" in workspace_skill_text
    assert "handoff" in workspace_skill_text

    fragment_dir = PACK_ROOT / "template-fragments"
    actual_fragments = {path.name for path in fragment_dir.glob("*.template.md")}
    assert EXPECTED_FRAGMENTS <= actual_fragments

    runner_prompt = read_pack_text("agents/runner/prompt.template.md")
    tasksmith_prompt = read_pack_text("agents/tasksmith/prompt.template.md")
    for slug in TUTORIAL_SLUGS:
        template_call = f'{{{{ template "lazyjj-{slug}" . }}}}'
        assert template_call in runner_prompt
        assert template_call in tasksmith_prompt


def test_overlay_orders_and_assets_wire_runtime_surfaces() -> None:
    order = load_pack_toml("orders/runtime-verify.toml")
    assert order["order"]["formula"] == "mol-lazyjj-runtime-verify"

    runtime_formula = load_pack_toml("formulas/mol-lazyjj-runtime-verify.toml")
    assert runtime_formula["vars"]["formula_name"]["default"] == "mol-polecat-lazyjj-work"
    assert runtime_formula["vars"]["agent"]["default"] == "runner"

    hooks_path = PACK_ROOT / "overlay/per-provider/codex/.codex/hooks.json"
    hooks = json.loads(hooks_path.read_text(encoding="utf-8"))
    assert "SessionStart" in hooks["hooks"]
    assert "UserPromptSubmit" in hooks["hooks"]
    assert "PreCompact" in hooks["hooks"]
    assert "gc prime --hook --hook-format codex" in hooks_path.read_text(encoding="utf-8")

    for script in [
        PACK_ROOT / "assets/scripts/workspace-setup.sh",
        PACK_ROOT / "assets/scripts/tmux-scroll.sh",
    ]:
        text = script.read_text(encoding="utf-8")
        mode = script.stat().st_mode
        assert text.startswith("#!/bin/sh")
        assert mode & stat.S_IXUSR, f"{script} must remain executable"
