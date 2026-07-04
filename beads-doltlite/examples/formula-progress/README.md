# Formula Progress SQL Generator

This example generates DB Browser SQL from the formula TOML available to a
DoltLite-backed city.

The generated SQL:

- attaches the HQ database and discovered rig databases,
- builds a `formula_steps` CTE from pack/materialized formula definitions,
- correlates formula steps with beads using `gc.root_bead_id`, `gc.step_ref`,
  and `gc.step_id` metadata,
- reports workflow rollups, per-step progress, and runtime-generated steps that
  are not present in the static formula TOML,
- creates temporary `session_beads_debug` and `session_demand_debug` views that
  show ready work, route/session metadata, matching session beads, and why ready
  work does not have a usable session.

Generate SQL for this workspace:

```bash
python3 /data/projects/doltlite-gascity/gascity/examples/beads-doltlite/examples/formula-progress/generate-formula-progress-sql.py \
  --city /data/projects/doltlite-gascity \
  --output /data/projects/doltlite-gascity/gascity/examples/beads-doltlite/examples/formula-progress/doltlite-gascity-formula-progress.sql
```

Open HQ plus the rig DBs with the DoltLite-linked browser:

```bash
gc beads-doltlite sqlitebrowser open --city /data/projects/doltlite-gascity
```

The command generates a DB Browser project, attaches the rig databases, and
loads the generated no-attach formula-progress SQL in the `Execute SQL` tab.
Run the SQL tab to create the temporary debug views, then inspect
`session_demand_debug` for rows such as `ready-routed-no-session-bead`,
`assigned-work-session-missing`, and `stamped-session-missing`.

The default generated file emits `ATTACH DATABASE` statements and is intended
for a fresh DB Browser connection. If the connection already has aliases such as
`rig_bd` attached, generate or run the no-attach variant instead:

```bash
python3 /data/projects/doltlite-gascity/gascity/examples/beads-doltlite/examples/formula-progress/generate-formula-progress-sql.py \
  --city /data/projects/doltlite-gascity \
  --attach-mode none \
  --output /data/projects/doltlite-gascity/gascity/examples/beads-doltlite/examples/formula-progress/doltlite-gascity-formula-progress-no-attach.sql
```

Use `doltlite-gascity-formula-progress-no-attach.sql` after running
`../hq-rig-browser/doltlite-gascity-attach.sql` or after running the default
formula-progress SQL once in the same DB Browser connection.
