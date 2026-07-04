# HQ and Rig Database Browser Example

Open the DoltLite-linked DB Browser for this city:

```bash
gc beads-doltlite sqlitebrowser open --city /data/projects/doltlite-gascity
```

The command generates a DB Browser project under
`.gc/runtime/packs/beads-doltlite/sqlitebrowser`, opens the HQ database
read-only, attaches the rig databases as `rig_bd`, `rig_gc`, `rig_gp`,
`rig_gd`, and `rig_lj`, and loads a formula-progress SQL tab. Run that SQL tab
to create temporary `session_beads_debug` and `session_demand_debug` views for
debugging why ready beads do not have matching sessions.

To generate the project without launching the GUI:

```bash
gc beads-doltlite sqlitebrowser project --city /data/projects/doltlite-gascity
```

Alternatively, open the city HQ database first:

```bash
gc beads-doltlite sqlitebrowser open --city /data/projects/doltlite-gascity
```

That opens:

```text
/data/projects/doltlite-gascity/.beads/doltlite/hq.db
```

Then use DB Browser's `Execute SQL` tab to run
`doltlite-gascity-attach.sql`. The script attaches the configured rig bead
databases for this city.

Do not edit rows or click "Write Changes" while Gas City is running. SELECT-only
inspection normally holds read locks only while statements are active, but a
long-running query or browse operation can still overlap with writer activity.
Close the browser when not inspecting live data.

Configured databases in this workspace:

| Scope | Alias | Path |
| --- | --- | --- |
| HQ city | `main` | `/data/projects/doltlite-gascity/.beads/doltlite/hq.db` |
| `beads-doltlite` rig | `rig_bd` | `/data/projects/doltlite-gascity/beads-doltlite/.beads/doltlite/bd.db` |
| `gascity` rig | `rig_gc` | `/data/projects/doltlite-gascity/gascity/.beads/doltlite/gc.db` |
| `gascity-packs` rig | `rig_gp` | `/data/projects/doltlite-gascity/gascity-packs/.beads/doltlite/gp.db` |
| `gascity-dashboard` rig | `rig_gd` | `/data/projects/doltlite-gascity/gascity/gascity-dashboard/.beads/doltlite/gd.db` |
| `lightjj` rig | `rig_lj` | `/data/projects/doltlite-gascity/lightjj/.beads/doltlite/lj.db` |

These are DoltLite-format databases. Stock SQLite Browser cannot open them;
use the DoltLite-linked browser built by `gc beads-doltlite sqlitebrowser build`.
