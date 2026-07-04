from __future__ import annotations

import os
import pathlib
import subprocess
import tomllib


PACK_DIR = pathlib.Path(__file__).resolve().parent.parent
REPO_ROOT = PACK_DIR.parent


def read_toml(relative_path: str) -> dict:
    return tomllib.loads((PACK_DIR / relative_path).read_text(encoding="utf-8"))


def assert_shell_script(relative_path: str) -> None:
    script = PACK_DIR / relative_path
    assert script.is_file(), f"missing script: {relative_path}"
    assert script.read_text(encoding="utf-8").startswith("#!/bin/sh\n")
    assert os.access(script, os.X_OK), f"script must be executable: {relative_path}"
    subprocess.run(["sh", "-n", str(script)], check=True)


def test_pack_manifest_declares_jjw_identity() -> None:
    manifest = read_toml("pack.toml")

    assert manifest["pack"]["name"] == "jjw"
    assert manifest["pack"]["schema"] == 2
    assert manifest["pack"]["version"] == "0.1.0"
    assert "Jujutsu workspace setup helpers" in manifest["pack"]["description"]


def test_workspace_report_formula_contract() -> None:
    formula = read_toml("formulas/mol-jjw-workspace-report.toml")

    assert formula["formula"] == "mol-jjw-workspace-report"
    assert formula["phase"] == "vapor"
    assert formula["pool"] == "dog"
    assert formula["steps"][0]["id"] == "report"

    text = "\n".join(
        [
            formula["description"],
            formula["steps"][0]["title"],
            formula["steps"][0]["description"],
        ]
    )
    for fragment in (
        "gc bd formula show mol-jjw-workspace-report --json",
        "jjw version",
        "jjw list --verbose",
        'bd update "$WORK_BEAD" --append-notes',
        "gc runtime drain-ack",
    ):
        assert fragment in text


def test_commands_doctor_orders_and_assets_are_wired() -> None:
    assert "Install aranw/jjw" in read_toml("commands/install/command.toml")[
        "description"
    ]
    assert "workspace health report" in read_toml(
        "commands/workspace-report/command.toml"
    )["description"]
    assert "jjw is available" in read_toml("doctor/check-jjw/doctor.toml")[
        "description"
    ]

    direct_order = read_toml("orders/workspace-report.toml")["order"]
    assert direct_order["trigger"] == "cooldown"
    assert direct_order["interval"] == "5m"
    assert "jjw list --verbose" in direct_order["exec"]

    formula_order = read_toml("orders/jjw-workspace-report.toml")["order"]
    assert formula_order["formula"] == "mol-jjw-workspace-report"
    assert formula_order["pool"] == "dog"

    for script in (
        "assets/scripts/install-jjw.sh",
        "assets/scripts/workspace-setup.sh",
        "assets/scripts/workspace-report.sh",
        "commands/install/run.sh",
        "commands/workspace-report/run.sh",
        "doctor/check-jjw/run.sh",
    ):
        assert_shell_script(script)

    assert "../../assets/scripts/install-jjw.sh" in (
        PACK_DIR / "commands/install/run.sh"
    ).read_text(encoding="utf-8")
    assert "../../assets/scripts/workspace-report.sh" in (
        PACK_DIR / "commands/workspace-report/run.sh"
    ).read_text(encoding="utf-8")


def test_workspace_setup_script_contract_is_explicit() -> None:
    script = (PACK_DIR / "assets/scripts/workspace-setup.sh").read_text(
        encoding="utf-8"
    )

    for expected in (
        'usage: workspace-setup.sh <rig-root> <target-dir> <agent-name> [--sync]',
        'REQUESTED_WT="${2:?missing target-dir}"',
        'AGENT="${3:?missing agent-name}"',
        'SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)',
        '"$SCRIPT_DIR/install-jjw.sh"',
        "GC_JJW_WORKSPACE_DIR",
        "GC_JJW_BASE_REVSET",
        "GC_JJW_BOOKMARK_PATTERN",
        "GC_JJW_MANAGE_CONFIG",
        "refusing to create workspace outside jjw config",
        "update agent work_dir or GC_JJW_WORKSPACE_DIR so they match",
        'echo "$RIG_ROOT/.beads" > "$WT/.beads/redirect"',
        'jj -R "$WT" bookmark set -B "$BOOKMARK" -r @',
    ):
        assert expected in script


def test_command_and_doctor_surfaces_preserve_script_relative_resolution() -> None:
    install = (PACK_DIR / "commands/install/run.sh").read_text(encoding="utf-8")
    report = (PACK_DIR / "commands/workspace-report/run.sh").read_text(
        encoding="utf-8"
    )
    doctor = (PACK_DIR / "doctor/check-jjw/run.sh").read_text(encoding="utf-8")

    for command_script in (install, report):
        assert 'SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)' in command_script

    assert '"$SCRIPT_DIR/../../assets/scripts/install-jjw.sh"' in install
    assert '"$SCRIPT_DIR/../../assets/scripts/workspace-report.sh" "$@"' in report
    assert "command -v jjw" in doctor
    assert "jjw version >/dev/null" in doctor


def test_template_fragments_cover_workspace_setup_and_reporting() -> None:
    fragments = {
        "template-fragments/jjw-workspace-setup.template.md": (
            '{{ define "jjw-workspace-setup" -}}',
            "[imports.jjw]",
            "assets/scripts/workspace-setup.sh",
            "JJW_NAME",
            "GC_JJW_WORKSPACE_DIR",
            "path disagree",
        ),
        "template-fragments/jjw-workspace-reporting.template.md": (
            '{{ define "jjw-workspace-reporting" -}}',
            "gc jjw workspace-report",
            "mol-jjw-workspace-report",
            "jjw list --verbose",
        ),
    }

    for relative_path, expected_fragments in fragments.items():
        text = (PACK_DIR / relative_path).read_text(encoding="utf-8")
        for expected in expected_fragments:
            assert expected in text


def test_readmes_list_jjw_entrypoints() -> None:
    pack_readme = (PACK_DIR / "README.md").read_text(encoding="utf-8")
    for fragment in (
        "assets/scripts/install-jjw.sh",
        "assets/scripts/workspace-setup.sh",
        "assets/scripts/workspace-report.sh",
        "gc jjw install",
        "gc jjw workspace-report",
        "formulas/mol-jjw-workspace-report.toml",
        "orders/workspace-report.toml",
        "orders/jjw-workspace-report.toml",
        "doctor/check-jjw",
        "template-fragments/jjw-workspace-setup.template.md",
        "template-fragments/jjw-workspace-reporting.template.md",
    ):
        assert fragment in pack_readme

    root_readme = (REPO_ROOT / "README.md").read_text(encoding="utf-8")
    assert "[jjw](./jjw)" in root_readme
    assert "workspace setup/reporting" in root_readme


def test_readme_documents_workspace_setup_contract_and_consumers() -> None:
    readme = (PACK_DIR / "README.md").read_text(encoding="utf-8")

    for expected in (
        "## Workspace setup contract",
        "[imports.jjw]",
        "source = \"../jjw\"",
        "`assets/scripts/workspace-setup.sh` is the public setup entry point",
        "`{{.RigRoot}}`",
        "`{{.WorkDir}}`",
        "`{{.AgentBase}}`",
        "agent process working directory",
        "`GC_JJW_WORKSPACE_DIR`",
        "`GC_JJW_BASE_REVSET`",
        "`GC_JJW_BOOKMARK_PATTERN`",
        "`packer/assets/scripts/pack-workspace-setup.sh`",
        "`jj-hunk/agents/surgeon/agent.toml`",
    ):
        assert expected in readme


def test_packer_and_jj_hunk_consumers_pin_jjw_workspace_setup_contract() -> None:
    packer_manifest = tomllib.loads(
        (REPO_ROOT / "packer/pack.toml").read_text(encoding="utf-8")
    )
    hunk_manifest = tomllib.loads(
        (REPO_ROOT / "jj-hunk/pack.toml").read_text(encoding="utf-8")
    )
    packer_setup = (REPO_ROOT / "packer/assets/scripts/pack-workspace-setup.sh").read_text(
        encoding="utf-8"
    )
    hunk_agent_path = REPO_ROOT / "jj-hunk/agents/surgeon/agent.toml"
    hunk_agent_text = hunk_agent_path.read_text(encoding="utf-8")
    hunk_agent = tomllib.loads(hunk_agent_text)

    assert packer_manifest["imports"]["jjw"]["source"] == "../jjw"
    assert hunk_manifest["imports"]["jjw"]["source"] == "../jjw"

    assert "packer imports jjw in pack.toml" in packer_setup
    assert 'workspace_setup="$SCRIPT_DIR/../../../jjw/assets/scripts/workspace-setup.sh"' in packer_setup
    assert '"$workspace_setup" "$RIG_ROOT" "$PACK_WORKSPACE_DIR" "$PACK_WORKSPACE_NAME"' in packer_setup
    assert 'GC_JJW_WORKSPACE_DIR="$PACK_WORKSPACE_PARENT"' in packer_setup
    assert 'GC_JJW_BOOKMARK_PATTERN="gc/$PACK_NAME.{name}"' in packer_setup
    assert 'GC_JJW_BASE_REVSET="$PACK_INTEGRATION_BOOKMARK"' in packer_setup
    assert '"$SCRIPT_DIR/list-import-patterns.py"' in packer_setup
    assert 'jj -R "$PACK_WORKSPACE_DIR" sparse set "$@"' in packer_setup

    assert "jj-hunk imports jjw in pack.toml" in hunk_agent_text
    assert hunk_agent["pre_start"] == [
        '{{.ConfigDir}}/../jjw/assets/scripts/workspace-setup.sh {{.RigRoot}} {{.WorkDir}} {{.AgentBase}} --sync${JJ_HUNK_WORK_BEAD_ID:+ --bead "$JJ_HUNK_WORK_BEAD_ID"}'
    ]
    pre_start = hunk_agent["pre_start"][0]
    for expected in ("{{.ConfigDir}}/../jjw", "{{.RigRoot}}", "{{.WorkDir}}", "{{.AgentBase}}", "--sync"):
        assert expected in pre_start
