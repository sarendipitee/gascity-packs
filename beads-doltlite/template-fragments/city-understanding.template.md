{{ define "city-understanding" }}
## City: doltlite-gascity

### Purpose

This city exists to develop, test, and maintain the **doltlite backend** for Gas Town and beads. It runs Gas Town's full machinery (mayor, polecats, witnesses, refinery, dogs) on a doltlite storage backend — an embedded prolly-tree SQLite engine with zero server process.

The city is the **primary development and testing ground** for running Gas Town cities without a Dolt MySQL-compatible server.

### The Ship-It Principle

A fix is only real when another user on another machine gets the same result by running the same commands — no manual steps, no ad-hoc edits, no "we already fixed that on this machine." Every change must be in code or config that ships:

- **gascity source** — patches to `cmd/gc/`, `internal/`, or `examples/*/pack/` that compile into the `gc` binary.
- **beads-doltlite source** — patches to `internal/storage/doltlite/` or `cmd/bd/` that compile into the `bd` binary.
- **doltlite C source** — patches to the prolly-tree engine that produce `libdoltlite.so`.
- **city.toml** — declarative config (`backend = "doltlite"`, pack includes, order overrides) that any `gc init` can reproduce.

Manual edits to runtime files (`.gc/system/packs/`, wrapper scripts, installed binaries) are scaffolding. They prove the fix works but are not the fix. Before declaring done, port every manual edit into its upstream source and rebuild.

### Codebases

| Repo | Location | Purpose |
|------|----------|---------|
| `gastownhall/gascity` | `./gascity/` | Gas Town controller, CLI, packs, molecules |
| `dolthub/doltlite` | `./doltlite/` | C library: prolly-tree SQLite fork (libdoltlite.so) |
| `duncan4123/beads-doltlite` | `./beads-doltlite/` | `bd` CLI: beads issue tracker with doltlite storage backend |

### Build Pipeline

```
doltlite release lib          bd release binary              gascity release archive
  doltlite-lib-<os>-<arch>       bd-doltlite-linux-amd64       gascity-doltlite_<version>_linux_amd64.tar.gz
  from GitHub releases           checksums.txt verified        Gas City checksums verified
  → libdoltlite.a/.so ───────→  installed bd wrapper           → installed gc
          └────────────────────────────────────────────────────→  libdoltlite-linked binaries
```

1. Use the pinned DoltLite release library, or pass `--lib` for an explicit development build
2. Install the released `bd-doltlite` binary with `gc beads-doltlite build bd`
3. Install the latest released DoltLite-linked Gas City archive with `gc beads-doltlite build gc`; pass `--build-gc-from-source` only for local source changes
4. `bd` binary provides beads CLI; Gas Town's `gc bd` commands shell out to it
5. Gas Town's `gc` binary embeds pack definitions (including the bd pack with `gc-beads-bd.sh` wrapper)

The `gc beads-doltlite build` command is pack-managed. It still requires an existing `gc` binary to run the city and dispatch pack commands, then it installs libdoltlite-linked replacements from release artifacts by default. Local source checkouts are used only when explicit source paths or `--build-gc-from-source`/`--build-bd-from-source` are provided. Use `gc beads-doltlite build bd --install --no-restart` and `gc beads-doltlite build gc --install --no-restart` for required init binaries; reserve `gc beads-doltlite build all` for coordinated rebuilds that include the optional diagnostic client. Add `--install` to copy verified `gc` binaries to every distinct home-owned entrypoint the city may use: the running supervisor's `gc` binary path, the existing supervisor unit's `gc` path, and the active controller `gc` path. Symlink install paths are resolved before writing so the script updates the real binary instead of replacing the link. Use `--install-dir`, `--bd-install`, and `--gc-install` to choose exact install paths.

Installing a rebuilt `bd` affects new `gc bd` calls as soon as that `bd` path is first on `PATH`. Installing a rebuilt `gc` affects new `gc` invocations immediately, but a running controller still uses the old in-memory binary until it is reloaded or restarted.

### Backend Architecture

- **Storage**: `libdoltlite.a`/`libdoltlite.so` — embedded prolly-tree engine. Single `.db` file per database, no server process.
- **Pack layering**: `beads-doltlite` owns the DoltLite beads provider script directly, so DoltLite cities do not import the managed `bd` pack or the `dolt` pack.
- **Beads CLI**: `gc beads-doltlite build bd` installs the released `bd-doltlite` binary by default; source builds use `CGO_ENABLED=1`, `GOFLAGS=-tags=libsqlite3`, and DoltLite CGO include/link flags.
- **Gas City binary**: `gc beads-doltlite build gc` installs the released DoltLite-linked `gc` archive by default; source builds use `CGO_ENABLED=1`, `GOFLAGS=-tags=gascity_doltlite_lib,libsqlite3`, and DoltLite CGO include/link flags.
- **Gas Town integration**: `gc bd` commands delegate to `bd` via `gc-beads-bd.sh` wrapper script. The wrapper detects `BEADS_BACKEND=doltlite` and routes init/operations through doltlite-specific code paths. The libdoltlite read fast path can bypass the CLI for selected hot reads, but writes and general `gc bd` behavior still go through `bd`.
- **No Dolt server**: No MySQL protocol, no port, no `dolt sql-server` process. The dolt pack is conditionally skipped when backend is doltlite (see `embed_builtin_packs.go`).

### Key Differences from Dolt-Backed Cities

| Aspect | Dolt (default) | Doltlite |
|--------|---------------|----------|
| Storage | Dolt SQL server (port 37282) | Embedded prolly-tree `.db` file |
| Beads init | `DOLT_COMMIT()` via MySQL | `dolt_commit()` via SQLite built-in |
| Pack auto-install | `dolt` pack included | `dolt` pack skipped |
| Formulas | `mol-dolt-health`, `mol-dolt-remotes-patrol` | `mol-doltlite-maintenance` |
| `--dolt-auto-commit` | Controls VCS commit timing | Same flag passed but doltlite ignores VCS semantics |

### Database Layout

```
.beads/
  metadata.json        → {"backend":"doltlite","database":"doltlite","dolt_database":"hq"}
  doltlite/
    hq.db              → Single-file prolly-tree database (city-level beads)
    .lock              → flock() sentinel for exclusive write access
  routes.jsonl         → Rig prefix routing

gascity/.beads/        → Rig-level beads store (same layout, database: gc.db)
beads-doltlite/.beads/ → Rig-level beads store
```

### Rig Status

| Rig | Prefix | Repo | Role |
|-----|--------|------|------|
| gascity | `gc-` | `gastownhall/gascity` | Gas Town source, packs, CLI |
| beads-doltlite | `bd-` | `duncan4123/beads-doltlite` | Beads CLI with doltlite backend |
{{ end }}
