---
name: doltlite
description: Use when working with DoltLite-backed Gas City or Beads storage, the beads-doltlite pack, doltlite-client diagnostics, libdoltlite-linked builds, DoltLite SQL operations such as dolt_gc/hash functions/remotes, or debugging DoltLite locks, maintenance, flatten, gc, and native read fast path behavior.
---

# DoltLite

Use this skill for Gas City work involving the `beads-doltlite` backend or the
local `doltlite` checkout.

## Source Of Truth

Read the local DoltLite README before changing DoltLite semantics:

- `<city-root>/doltlite/README.md`
- `../../../../../doltlite/README.md`
- `../../../../tools/doltlite-client/README.md`

The README documents DoltLite's SQLite-compatible API and Dolt SQL functions.
Prefer that contract over assumptions from Dolt-server commands.

## Gas City Rules

- DoltLite cities use `[beads] backend = "doltlite"` and bead scopes under
  `.beads/doltlite/*.db`.
- Plugin-backed DoltLite scopes must also have `.beads/metadata.json` fields
  for both Beads and Gas City plugin entry points:
  `backend_plugin_command`, `backend_plugin_args`,
  `gascity_backend_command`, and `gascity_backend_args`. Keep the local ops
  attachment as `attached_databases: [{alias:"ops", path:"<scope>/.gc/ops.sqlite"}]`.
- Do not require a Dolt SQL server, runtime port, or
  `.gc/runtime/packs/dolt/dolt-state.json`.
- For fresh init and normal Gas City install paths, install only `gc` with
  `gc beads-doltlite build gc --install --no-restart`; it defaults to the
  latest released DoltLite-linked Gas City archive unless
  `GC_DOLTLITE_GC_RELEASE_VERSION` pins one. Pass `--build-gc-from-source`
  only for local Gas City source, native read fastpath, or build-tag changes.
- Fresh DoltLite init builds the required binaries with
  `gc beads-doltlite build bd --install --no-restart` and
  `gc beads-doltlite build gc --install --no-restart`. It should not require
  `doltlite-client`, sqlitebrowser, or a local DoltLite source build.
- Use `gc beads-doltlite build all --install --no-restart` only for coordinated
  rebuilds that include the optional diagnostic client. The build command may
  download pinned DoltLite and latest Gas City release artifacts into pack
  runtime state; pass `--lib` or `--build-gc-from-source` only for an explicit
  development build.
- Use `doltlite-client` for direct test reads and writes. It supports `info`,
  `query`, `exec`, `show`, `set-metadata`, and `close`.
- Use `gc beads-doltlite sqlitebrowser build/open` for optional GUI inspection;
  stock SQLite Browser builds cannot open DoltLite-format databases. Plain
  `open --city <city>` generates a DB Browser project with HQ, rig attachments,
  and a formula-progress SQL tab.
- Use DoltLite SQL for native maintenance checks, including
  `SELECT dolt_gc();` for GC.
- Do not assume configurable SQLite checkpoint modes. DoltLite rejects
  `PRAGMA wal_checkpoint(TRUNCATE)` on DoltLite-format databases; use the
  default checkpoint form when probing.
- Treat `bd flatten` and `bd gc` as Beads CLI behavior, not the canonical
  DoltLite client oracle.
- Do not run heavyweight flatten or GC synchronously inside city startup.
  Keep non-critical maintenance bounded and non-fatal.
- Before debugging lock issues, check for active `bd`, `doltlite-client`,
  `gc session list`, and `gc-beads-bd` processes. Kill only probes you started
  or processes the user has approved.

## Backend Plugin Layout

The DoltLite plugin work spans four repositories/workspaces. Check all of them
before declaring the city healthy:

- Beads core plugin branch:
  `/data/projects/doltlite-gascity/workspaces/beads-plugin-architecture`.
  This owns the Beads backend plugin client, protocol, `bd backend` command,
  `bd sql` raw-SQL forwarding, schema v54 lease compatibility, and Beads
  database discovery for `.beads/doltlite/`.
- DoltLite backend plugin repo:
  `/data/projects/doltlite-gascity/rigs/beads-backend-doltlite-plugin`.
  This owns `bd-backend-doltlite` and `gc-doltlite-fastpath` server binaries.
- Gas City repo:
  `/data/projects/doltlite-gascity/gascity`.
  This owns Gas City metadata preservation and the Gas City backend abstraction
  that launches `gc-doltlite-fastpath`.
- Gas City packs repo:
  `/data/projects/doltlite-gascity/gascity-packs`.
  The full pack is `beads-doltlite`; the bootstrap pack is
  `beads-doltlite-init`. Both must write plugin metadata during init, and the
  full pack should repair existing DoltLite scope metadata during
  `ensure-ready`.

The runtime binaries normally live under the city root:

```bash
.gc/runtime/packs/beads-doltlite/bin/bd-backend-doltlite
.gc/runtime/packs/dolt/bin/gc-doltlite-fastpath
```

Use these trace files to prove calls are going through the plugin:

```bash
.gc/backend-plugin-trace.jsonl
.gc/gascity-backend-plugin-trace.jsonl
```

If logs show `embeddeddolt: init schema` or
`cannot resolve default branch head ... main`, the current `bd` process is not
opening through the backend plugin. First inspect the scope's
`.beads/metadata.json`; missing `backend_plugin_command` is the usual cause.
If a pure DoltLite scope says `no beads database found`, confirm the installed
Beads build recognizes `.beads/doltlite/` as a valid database root.

Fast sanity checks from a rig root:

```bash
BEADS_DIR="$PWD/.beads" bd list --json --limit 1
BEADS_DIR="$PWD/.beads" bd sql 'select version from schema_migrations order by version desc limit 1' --json
tail -20 "$GC_CITY_PATH/.gc/backend-plugin-trace.jsonl"
```

Expected current schema for the plugin work is v54. Identity mismatches mean
`metadata.json project_id` does not match the database `_project_id`; reconcile
that before debugging backend behavior.

## Pack Troubleshooting

When a Gas City pack formula appears stuck under the DoltLite backend, treat
each live query and write as a test case. Do not stop at checking whether a
bead exists.

For every controller, worker, formula, or helper operation involved:

1. Capture the exact operation the system runs: the `bd` command, shell
   pipeline, jq filter, Go store call, or metadata write.
2. Run the equivalent `bd` command from the rig root against the live
   DoltLite-backed store.
3. Run an equivalent direct read with `doltlite-client -db
   <rig>/.beads/doltlite/<prefix>.db query '<SQL>'`.
4. Compare the result of the direct DoltLite query with the `bd` result and the
   next controller lifecycle decision, such as pool demand, session
   materialization, hook claim, continuation assignment, drain acknowledgement,
   or finalization.

For ready-work bugs, verify the fully qualified route and blocking state with
both surfaces. The controller scale/query path should agree with a `bd ready`
probe such as:

```bash
bd ready \
  --metadata-field 'gc.routed_to=<rig>/<agent>' \
  --unassigned \
  --exclude-type=epic \
  --json \
  --sort oldest \
  --limit=20
```

Then check the same predicate directly in DoltLite, including `status`,
`assignee`, `issue_type`, `is_blocked`, and metadata such as `gc.routed_to`,
`gc.run_target`, `gc.kind`, `gc.session_affinity`, `gc.root_bead_id`,
`gc.root_store_ref`, and `gc.continuation_group`.

If `bd` and `doltlite-client` agree that work is ready but no session starts,
the bug is in route qualification, pool demand, desired-state construction, or
session materialization. If they diverge, debug the Beads/DoltLite fast path or
metadata/index translation before changing formula logic.
