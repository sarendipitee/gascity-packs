#!/usr/bin/env python3
"""Generate SQL reports that track graph.v2 formula progress.

The generator reads formula TOML files, emits a formula_steps CTE, and joins
that static definition against bead rows using Gas City formula metadata.
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import sys
import tomllib


SKIP_DIRS = {
    ".cache",
    ".git",
    ".gc",
    ".jj",
    "__pycache__",
    "build",
    "dist",
    "node_modules",
    "sqlitebrowser-build",
    "sqlitebrowser-src",
    "vendor",
}


def sql_quote(value: object) -> str:
    if value is None:
        return "NULL"
    text = str(value)
    return "'" + text.replace("'", "''") + "'"


def sql_ident(value: str) -> str:
    return '"' + value.replace('"', '""') + '"'


def safe_alias(value: str, used: set[str]) -> str:
    base = re.sub(r"[^A-Za-z0-9_]+", "_", value.strip().lower()).strip("_")
    if not base:
        base = "db"
    if base[0].isdigit():
        base = "db_" + base
    alias = base
    i = 2
    while alias in used:
        alias = f"{base}_{i}"
        i += 1
    used.add(alias)
    return alias


def walk_formula_files(root: Path) -> list[Path]:
    if not root.exists():
        return []
    if root.is_file() and root.suffix == ".toml":
        return [root]
    out: list[Path] = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for filename in filenames:
            if filename.endswith(".toml"):
                out.append(Path(dirpath) / filename)
    return sorted(out)


def as_list(value: object) -> list[str]:
    if value is None:
        return []
    if isinstance(value, list):
        return [str(v) for v in value]
    return [str(value)]


def metadata_value(step: dict, key: str) -> str:
    metadata = step.get("metadata")
    if not isinstance(metadata, dict):
        return ""
    value = metadata.get(key)
    if value is None:
        return ""
    return str(value)


def record_step(
    rows: list[dict[str, object]],
    source: Path,
    formula_name: str,
    kind: str,
    ordinal: int,
    step: dict,
    parent_template: str = "",
) -> None:
    step_id = str(step.get("id") or "").strip()
    if not step_id:
        return
    rows.append(
        {
            "source_path": str(source),
            "formula": formula_name,
            "step_kind": kind,
            "ordinal": ordinal,
            "step_id": step_id,
            "step_ref": f"{formula_name}.{step_id}",
            "title": str(step.get("title") or step_id),
            "needs": ",".join(as_list(step.get("needs"))),
            "run_target": metadata_value(step, "gc.run_target"),
            "child_formula": str(step.get("formula") or ""),
            "expand_formula": str(step.get("expand") or ""),
            "condition": str(step.get("condition") or ""),
            "parent_template": parent_template,
        }
    )


def formula_name_from_path(path: Path) -> str:
    name = path.name
    for suffix in (".formula.toml", ".toml"):
        if name.endswith(suffix):
            return name[: -len(suffix)]
    return path.stem


def load_formula_steps(paths: list[Path]) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    seen: set[tuple[str, str, str, str]] = set()
    raw_rows: list[dict[str, object]] = []
    for path in paths:
        try:
            with path.open("rb") as handle:
                data = tomllib.load(handle)
        except Exception as exc:
            print(f"warning: skipping {path}: {exc}", file=sys.stderr)
            continue
        formula_name = str(data.get("formula") or formula_name_from_path(path))
        for i, step in enumerate(data.get("steps") or [], start=1):
            if isinstance(step, dict):
                record_step(raw_rows, path, formula_name, "step", i, step)
        for i, template in enumerate(data.get("template") or [], start=1):
            if not isinstance(template, dict):
                continue
            record_step(raw_rows, path, formula_name, "template", i, template)
            parent_id = str(template.get("id") or "")
            for j, child in enumerate(template.get("children") or [], start=1):
                if isinstance(child, dict):
                    record_step(raw_rows, path, formula_name, "template.child", (i * 1000) + j, child, parent_id)

    # Materialized formula dirs often carry both name.toml and name.formula.toml.
    # Keep the first row for each formula/step/kind/source stem.
    for row in raw_rows:
        source = Path(str(row["source_path"]))
        source_key = formula_name_from_path(source)
        key = (str(row["formula"]), str(row["step_id"]), str(row["step_kind"]), source_key)
        if key in seen:
            continue
        seen.add(key)
        rows.append(row)
    rows.sort(key=lambda r: (str(r["formula"]), int(r["ordinal"]), str(r["step_kind"]), str(r["step_id"])))
    return rows


def discover_databases(city: Path) -> list[tuple[str, str, Path, bool]]:
    db_root = city / ".beads" / "doltlite"
    out: list[tuple[str, str, Path, bool]] = []
    used = {"main"}
    if db_root.exists():
        for db in sorted(db_root.glob("*.db")):
            label = db.stem
            out.append((label, "main", db, True))
            break
    found: list[Path] = []
    for dirpath, dirnames, filenames in os.walk(city):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        current = Path(dirpath)
        if current.name != "doltlite" or current.parent.name != ".beads":
            continue
        for filename in filenames:
            if filename.endswith(".db"):
                found.append(current / filename)
    for path in sorted(found):
        if path.parent == db_root:
            continue
        label = path.stem
        alias = safe_alias(f"rig_{label}", used)
        out.append((label, alias, path, False))
    return out


def parse_database_arg(value: str, used: set[str]) -> tuple[str, str, Path | None, bool]:
    # label=alias[:/absolute/path]
    if "=" not in value:
        raise argparse.ArgumentTypeError("database must be label=alias or label=alias:/path/db.db")
    label, rest = value.split("=", 1)
    if ":" in rest:
        alias, raw_path = rest.split(":", 1)
        path = Path(raw_path)
        main = alias == "main"
    else:
        alias, path, main = rest, None, rest == "main"
    alias = safe_alias(alias, used) if alias != "main" else "main"
    return label, alias, path, main


def cte_formula_steps(rows: list[dict[str, object]]) -> str:
    cols = [
        "source_path",
        "formula",
        "step_kind",
        "ordinal",
        "step_id",
        "step_ref",
        "title",
        "needs",
        "run_target",
        "child_formula",
        "expand_formula",
        "condition",
        "parent_template",
    ]
    if not rows:
        nulls = ", ".join("NULL" for _ in cols)
        return "formula_steps(" + ", ".join(cols) + f") AS (SELECT {nulls} WHERE 0)"
    values = []
    for row in rows:
        values.append("(" + ", ".join(sql_quote(row.get(col)) for col in cols) + ")")
    return "formula_steps(" + ", ".join(cols) + ") AS (\n  VALUES\n  " + ",\n  ".join(values) + "\n)"


def cte_issue_rows(databases: list[tuple[str, str, Path | None, bool]], table: str, cte_name: str) -> str:
    selects = []
    for label, alias, _path, _main in databases:
        prefix = sql_ident(alias)
        selects.append(
            f"""SELECT {sql_quote(label)} AS db_name,
       id, title, status, issue_type, priority, assignee, owner, rig,
       updated_at, closed_at, defer_until, started_at, is_blocked,
       hook_bead, role_bead, agent_state, role_type, last_activity,
       await_type, await_id, metadata,
       json_extract(metadata, '$."gc.kind"') AS gc_kind,
       json_extract(metadata, '$."gc.formula_contract"') AS formula_contract,
       json_extract(metadata, '$."gc.root_bead_id"') AS root_bead_id,
       json_extract(metadata, '$."gc.step_ref"') AS step_ref,
       json_extract(metadata, '$."gc.step_id"') AS step_id,
       json_extract(metadata, '$."gc.ralph_step_id"') AS ralph_step_id,
       json_extract(metadata, '$."gc.spec_for"') AS spec_for,
       json_extract(metadata, '$."gc.spec_for_ref"') AS spec_for_ref,
       json_extract(metadata, '$."gc.routed_to"') AS routed_to,
       json_extract(metadata, '$."gc.run_target"') AS run_target,
       json_extract(metadata, '$."gc.session_name"') AS gc_session_name,
       json_extract(metadata, '$."gc.work_dir"') AS gc_work_dir,
       json_extract(metadata, '$.session_name') AS session_name_meta,
       json_extract(metadata, '$.template') AS template_meta,
       json_extract(metadata, '$.state') AS state_meta,
       json_extract(metadata, '$.sleep_reason') AS sleep_reason,
       json_extract(metadata, '$.pending_create_claim') AS pending_create_claim,
       json_extract(metadata, '$.alias') AS alias_meta,
       json_extract(metadata, '$.configured_named_identity') AS configured_named_identity,
       json_extract(metadata, '$.configured_named_session') AS configured_named_session,
       json_extract(metadata, '$.dependency_only') AS dependency_only,
       json_extract(metadata, '$.explicit_wake') AS explicit_wake,
       json_extract(metadata, '$.current_run_id') AS current_run_id,
       json_extract(metadata, '$.work_dir') AS session_work_dir
  FROM {prefix}.{table}"""
        )
    return cte_name + " AS (\n" + "\nUNION ALL\n".join(selects) + "\n)"


def cte_all_issues(databases: list[tuple[str, str, Path | None, bool]]) -> str:
    return cte_issue_rows(databases, "issues", "all_issues")


def cte_all_ready_issues(databases: list[tuple[str, str, Path | None, bool]]) -> str:
    return cte_issue_rows(databases, "ready_issues", "all_ready_issues")


def cte_all_labels(databases: list[tuple[str, str, Path | None, bool]]) -> str:
    selects = []
    for label, alias, _path, _main in databases:
        prefix = sql_ident(alias)
        selects.append(
            f"""SELECT {sql_quote(label)} AS db_name, issue_id, label
  FROM {prefix}.labels"""
        )
    return "all_labels AS (\n" + "\nUNION ALL\n".join(selects) + "\n)"


def common_ctes(step_rows: list[dict[str, object]], databases: list[tuple[str, str, Path | None, bool]]) -> str:
    return f"""{cte_formula_steps(step_rows)},
{cte_all_issues(databases)},
step_beads AS (
  SELECT db_name, id, title, status, issue_type, priority, assignee, owner, rig,
         updated_at, closed_at, metadata, gc_kind, formula_contract,
         COALESCE(root_bead_id, CASE WHEN gc_kind = 'workflow' THEN id END) AS root_id,
         step_ref,
         COALESCE(step_id, ralph_step_id, spec_for) AS logical_step_id,
         CASE
           WHEN step_ref IS NOT NULL AND instr(step_ref, '.') > 0
           THEN substr(step_ref, 1, instr(step_ref, '.') - 1)
         END AS formula_hint
    FROM all_issues
   WHERE step_ref IS NOT NULL
      OR root_bead_id IS NOT NULL
      OR gc_kind = 'workflow'
),
root_formulas AS (
  SELECT DISTINCT sb.db_name, sb.root_id, fs.formula
    FROM step_beads sb
    JOIN (SELECT DISTINCT formula FROM formula_steps) fs
      ON sb.formula_hint = fs.formula
   WHERE sb.root_id IS NOT NULL
),
workflow_roots AS (
  SELECT ai.db_name, ai.id AS root_id, ai.title, ai.status, ai.priority,
         ai.assignee, ai.owner, ai.rig, ai.updated_at, ai.closed_at, rf.formula
    FROM all_issues ai
    JOIN root_formulas rf
      ON rf.db_name = ai.db_name
     AND rf.root_id = ai.id
),
expected_steps AS (
  SELECT wr.db_name, wr.root_id, wr.title AS workflow_title, wr.status AS workflow_status,
         wr.priority AS workflow_priority, wr.assignee AS workflow_assignee,
         wr.owner AS workflow_owner, wr.rig AS workflow_rig, wr.updated_at AS workflow_updated_at,
         wr.formula, fs.step_kind, fs.ordinal, fs.step_id, fs.step_ref, fs.title AS expected_title,
         fs.needs, fs.run_target, fs.child_formula, fs.expand_formula, fs.condition, fs.parent_template
    FROM workflow_roots wr
    JOIN formula_steps fs ON fs.formula = wr.formula
),
actual_steps AS (
  SELECT sb.*
    FROM step_beads sb
   WHERE sb.root_id IS NOT NULL
     AND sb.step_ref IS NOT NULL
),
matched_steps AS (
  SELECT es.*,
         ast.id AS bead_id,
         ast.title AS bead_title,
         ast.status AS bead_status,
         ast.issue_type AS bead_type,
         ast.priority AS bead_priority,
         ast.assignee AS bead_assignee,
         ast.owner AS bead_owner,
         ast.updated_at AS bead_updated_at,
         ast.closed_at AS bead_closed_at
    FROM expected_steps es
    LEFT JOIN actual_steps ast
      ON ast.db_name = es.db_name
     AND ast.root_id = es.root_id
     AND (
          ast.step_ref = es.step_ref
       OR (ast.formula_hint = es.formula AND ast.logical_step_id = es.step_id)
     )
)"""


def session_beads_view_sql(databases: list[tuple[str, str, Path | None, bool]]) -> str:
    return f"""DROP VIEW IF EXISTS temp.session_demand_debug;
DROP VIEW IF EXISTS temp.session_beads_debug;
CREATE TEMP VIEW session_beads_debug AS
WITH {cte_all_issues(databases)},
{cte_all_labels(databases)},
session_label_flags AS (
  SELECT db_name, issue_id, MAX(CASE WHEN label = 'gc:session' THEN 1 ELSE 0 END) AS has_session_label
    FROM all_labels
   GROUP BY db_name, issue_id
)
SELECT ai.db_name,
       ai.id AS session_bead_id,
       ai.title AS session_title,
       ai.status AS session_status,
       ai.issue_type AS session_type,
       COALESCE(NULLIF(ai.session_name_meta, ''), NULLIF(ai.alias_meta, ''), NULLIF(ai.configured_named_identity, '')) AS session_key,
       NULLIF(ai.session_name_meta, '') AS session_name,
       NULLIF(ai.alias_meta, '') AS alias,
       NULLIF(ai.configured_named_identity, '') AS configured_named_identity,
       NULLIF(ai.template_meta, '') AS template,
       COALESCE(NULLIF(ai.state_meta, ''), NULLIF(ai.agent_state, ''), ai.status) AS session_state,
       NULLIF(ai.sleep_reason, '') AS sleep_reason,
       NULLIF(ai.pending_create_claim, '') AS pending_create_claim,
       NULLIF(ai.configured_named_session, '') AS configured_named_session,
       NULLIF(ai.dependency_only, '') AS dependency_only,
       NULLIF(ai.explicit_wake, '') AS explicit_wake,
       COALESCE(NULLIF(ai.session_work_dir, ''), NULLIF(ai.gc_work_dir, '')) AS work_dir,
       NULLIF(ai.current_run_id, '') AS current_run_id,
       ai.hook_bead, ai.role_bead, ai.role_type, ai.agent_state,
       ai.last_activity, ai.updated_at, ai.metadata
  FROM all_issues ai
  LEFT JOIN session_label_flags sl
    ON sl.db_name = ai.db_name
   AND sl.issue_id = ai.id
 WHERE ai.issue_type = 'session'
    OR COALESCE(sl.has_session_label, 0) = 1
    OR NULLIF(ai.session_name_meta, '') IS NOT NULL
    OR NULLIF(ai.template_meta, '') IS NOT NULL
    OR NULLIF(ai.configured_named_identity, '') IS NOT NULL;"""


def session_demand_view_sql(databases: list[tuple[str, str, Path | None, bool]]) -> str:
    return f"""DROP VIEW IF EXISTS temp.session_demand_debug;
CREATE TEMP VIEW session_demand_debug AS
WITH {cte_all_ready_issues(databases)},
ready_work AS (
  SELECT db_name,
         id AS work_bead_id,
         title AS work_title,
         status AS work_status,
         issue_type AS work_type,
         priority, assignee, owner, rig,
         updated_at, defer_until, started_at, is_blocked,
         gc_kind, formula_contract, root_bead_id, step_ref, step_id,
         routed_to, run_target, gc_session_name, gc_work_dir,
         COALESCE(NULLIF(gc_session_name, ''), NULLIF(assignee, '')) AS expected_session_name,
         COALESCE(NULLIF(routed_to, ''), NULLIF(run_target, ''), NULLIF(assignee, '')) AS expected_route,
         metadata
    FROM all_ready_issues
   WHERE status IN ('open', 'in_progress')
     AND COALESCE(issue_type, '') <> 'session'
)
SELECT rw.db_name,
       rw.work_bead_id,
       rw.work_title,
       rw.work_status,
       rw.work_type,
       rw.priority,
       rw.assignee,
       rw.owner,
       rw.rig,
       rw.gc_kind,
       rw.formula_contract,
       rw.root_bead_id,
       rw.step_ref,
       rw.step_id,
       rw.routed_to,
       rw.run_target,
       rw.expected_route,
       rw.expected_session_name,
       rw.gc_work_dir AS expected_work_dir,
       sb.session_bead_id,
       sb.session_name,
       sb.alias AS session_alias,
       sb.configured_named_identity,
       sb.template AS session_template,
       sb.session_status,
       sb.session_state,
       sb.sleep_reason,
       sb.pending_create_claim,
       sb.dependency_only,
       sb.explicit_wake,
       sb.work_dir AS session_work_dir,
       CASE
         WHEN NULLIF(rw.assignee, '') IS NOT NULL AND sb.session_bead_id IS NULL THEN 'assigned-work-session-missing'
         WHEN NULLIF(rw.gc_session_name, '') IS NOT NULL AND sb.session_bead_id IS NULL THEN 'stamped-session-missing'
         WHEN NULLIF(rw.expected_route, '') IS NULL THEN 'ready-work-unrouted'
         WHEN sb.session_bead_id IS NULL THEN 'ready-routed-no-session-bead'
         WHEN sb.session_status = 'closed' THEN 'session-bead-closed'
         WHEN sb.session_state IN ('drained', 'draining') OR sb.sleep_reason = 'drained' THEN 'session-drained'
         WHEN sb.dependency_only IN ('1', 'true', 'yes') THEN 'session-dependency-only'
         WHEN NULLIF(sb.pending_create_claim, '') IS NOT NULL THEN 'session-pending-create'
         WHEN sb.session_state IN ('creating', 'start_pending') THEN 'session-create-pending'
         WHEN sb.session_state IN ('asleep', 'suspended', 'quarantined') THEN 'session-not-awake'
         ELSE 'session-present-check-claim'
       END AS session_gap,
       rw.updated_at
  FROM ready_work rw
  LEFT JOIN session_beads_debug sb
    ON sb.db_name = rw.db_name
   AND (
        (NULLIF(rw.expected_session_name, '') IS NOT NULL
         AND rw.expected_session_name IN (sb.session_name, sb.alias, sb.configured_named_identity, sb.session_key))
     OR (NULLIF(rw.expected_route, '') IS NOT NULL
         AND rw.expected_route IN (sb.template, sb.alias, sb.configured_named_identity, sb.session_name, sb.session_key))
   );"""


def attach_sql(databases: list[tuple[str, str, Path | None, bool]]) -> str:
    lines = []
    for _label, alias, path, main in databases:
        if main or path is None:
            continue
        lines.append(f"ATTACH DATABASE {sql_quote(path)} AS {sql_ident(alias)};")
    return "\n".join(lines)


def generate_sql(
    step_rows: list[dict[str, object]],
    databases: list[tuple[str, str, Path | None, bool]],
    city: Path,
    attach_mode: str,
) -> str:
    ctes = common_ctes(step_rows, databases)
    attach_block = attach_sql(databases) if attach_mode == "attach" else ""
    attach_note = (
        "This file attaches rig databases for a fresh DB Browser connection."
        if attach_mode == "attach"
        else "This file assumes rig databases are already attached in the current connection."
    )
    return f"""-- Generated formula progress SQL.
-- City: {city}
-- Open the HQ database first, then run this script with the DoltLite-linked DB Browser.
-- {attach_note}

{attach_block}

-- 1. Formula catalog from pack/materialized formula TOML.
WITH {cte_formula_steps(step_rows)}
SELECT formula, step_kind, ordinal, step_id, title, needs, run_target,
       child_formula, expand_formula, condition, source_path
  FROM formula_steps
 ORDER BY formula, ordinal, step_kind, step_id;

-- 2. Workflow progress rollup by formula and root bead.
WITH {ctes}
SELECT db_name, formula, root_id, workflow_title, workflow_status,
       COUNT(*) AS expected_steps,
       SUM(CASE WHEN bead_id IS NOT NULL THEN 1 ELSE 0 END) AS materialized_steps,
       SUM(CASE WHEN bead_status = 'closed' THEN 1 ELSE 0 END) AS closed_steps,
       SUM(CASE WHEN bead_status = 'in_progress' THEN 1 ELSE 0 END) AS in_progress_steps,
       SUM(CASE WHEN bead_status = 'open' THEN 1 ELSE 0 END) AS open_steps,
       SUM(CASE WHEN bead_id IS NULL THEN 1 ELSE 0 END) AS missing_steps,
       ROUND(100.0 * SUM(CASE WHEN bead_status = 'closed' THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 1) AS pct_closed,
       workflow_updated_at
  FROM matched_steps
 GROUP BY db_name, formula, root_id, workflow_title, workflow_status, workflow_updated_at
 ORDER BY workflow_updated_at DESC, db_name, formula;

-- 3. Per-step formula progress.
WITH {ctes}
SELECT db_name, formula, root_id, workflow_title, ordinal, step_kind,
       step_id, expected_title, needs, run_target,
       COALESCE(bead_status, 'not_materialized') AS status,
       bead_id, bead_title, bead_assignee, bead_owner, bead_updated_at
  FROM matched_steps
 ORDER BY db_name, root_id, formula, ordinal, step_kind, step_id;

-- 4. Missing expected formula steps.
WITH {ctes}
SELECT db_name, formula, root_id, workflow_title, ordinal, step_kind,
       step_id, expected_title, needs, run_target
  FROM matched_steps
 WHERE bead_id IS NULL
 ORDER BY db_name, root_id, formula, ordinal;

-- 5. Runtime-generated or expansion steps not present in static formula TOML.
WITH {ctes}
SELECT ast.db_name, ast.root_id, wr.formula, ast.id AS bead_id, ast.title,
       ast.status, ast.issue_type, ast.step_ref, ast.logical_step_id,
       ast.assignee, ast.owner, ast.updated_at
  FROM actual_steps ast
  LEFT JOIN workflow_roots wr
    ON wr.db_name = ast.db_name
   AND wr.root_id = ast.root_id
  LEFT JOIN formula_steps fs
    ON fs.formula = wr.formula
   AND (
        ast.step_ref = fs.step_ref
     OR (ast.formula_hint = fs.formula AND ast.logical_step_id = fs.step_id)
   )
 WHERE fs.step_id IS NULL
 ORDER BY ast.updated_at DESC;

-- 6. Temporary debugging views for session-bead demand.
-- These views live only in the current DB Browser connection.
{session_beads_view_sql(databases)}

{session_demand_view_sql(databases)}

-- 7. Session demand gap summary: why ready work may not have a worker.
SELECT session_gap, COUNT(*) AS ready_work_count
  FROM session_demand_debug
 GROUP BY session_gap
 ORDER BY ready_work_count DESC, session_gap;

-- 8. Ready work and its matching session bead, if one exists.
SELECT db_name, work_bead_id, work_title, work_status, work_type, priority,
       assignee, expected_route, expected_session_name, session_gap,
       session_bead_id, session_name, session_alias, configured_named_identity,
       session_template, session_status, session_state, sleep_reason,
       pending_create_claim, dependency_only, expected_work_dir, session_work_dir,
       updated_at
  FROM session_demand_debug
 ORDER BY
       CASE
         WHEN session_gap IN ('assigned-work-session-missing', 'stamped-session-missing', 'ready-routed-no-session-bead') THEN 0
         WHEN session_gap = 'ready-work-unrouted' THEN 1
         ELSE 2
       END,
       priority ASC,
       updated_at DESC;
"""


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--city", default="/data/projects/doltlite-gascity", help="city root used for defaults")
    parser.add_argument(
        "--formula-root",
        action="append",
        default=[],
        help="formula file or directory; default: <city>/.beads/formulas",
    )
    parser.add_argument(
        "--database",
        action="append",
        default=[],
        help="database mapping label=alias or label=alias:/absolute/path. Default discovers <city>/.beads/doltlite/*.db and sibling rig DBs.",
    )
    parser.add_argument(
        "--attach-mode",
        choices=("attach", "none"),
        default="attach",
        help="emit ATTACH DATABASE statements, or assume aliases are already attached",
    )
    parser.add_argument("--output", default="-", help="output SQL path, or '-' for stdout")
    args = parser.parse_args()

    city = Path(args.city).resolve()
    formula_roots = [Path(p).resolve() for p in args.formula_root]
    if not formula_roots:
        formula_roots = [city / ".beads" / "formulas"]

    formula_files: list[Path] = []
    for root in formula_roots:
        formula_files.extend(walk_formula_files(root))
    step_rows = load_formula_steps(formula_files)

    if args.database:
        used = {"main"}
        databases = [parse_database_arg(v, used) for v in args.database]
        if not any(main for _label, _alias, _path, main in databases):
            parser.error("at least one --database must use alias main")
    else:
        databases = discover_databases(city)
    if not databases:
        parser.error("no DoltLite databases found; pass --database")

    sql = generate_sql(step_rows, databases, city, args.attach_mode)
    if args.output == "-":
        print(sql)
    else:
        output = Path(args.output)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(sql, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
