# Task Workspace

```mermaid
flowchart TD
  subgraph creation["Bead creation"]
    request["Pack work request that needs isolation"]
    mode{"Workspace mode"}
    named["--workspace name:<br/>bd create includes gc.pack_workspace = name"]
    task["--task-workspace:<br/>bd create child bead first"]
    compute["Compute workspace from child id and title"]
    update["bd update child:<br/>gc.pack_workspace = child-id-title-slug"]
    metadata["child bead metadata:<br/>gc.pack = pack<br/>gc.pack_root = pack_root<br/>gc.pack_workspace = workspace"]
    sling["gc sling rig/packer.packsmith child --on mol-packer-work"]

    request --> mode
    mode --> named --> metadata
    mode --> task --> compute --> update --> metadata
    metadata --> sling
  end

  subgraph desired["GC desired state"]
    demand["Pool demand for shared packsmith template"]
    bind["Bind trigger bead to idle or new pool worker"]
    workdir["Derive work_dir:<br/>.gc/workspaces/rig/packs/pack/workspace"]
    session["Write named session metadata:<br/>trigger bead id<br/>pack<br/>pack root<br/>workspace<br/>work_dir"]

    sling --> demand --> bind --> workdir --> session
  end

  subgraph start["Worker start or resume"]
    start_session["Start or adopt named pool session"]
    prestart["pre_start reads GC_TRIGGER_BEAD_ID"]
    jjw["jjw creates or reuses the explicit workspace"]
    sparse["Sparse checkout contains target pack plus shared files"]
    agent["packsmith works this isolated routed bead"]
    resume["Later resume reads session metadata and returns to this task workspace"]

    session --> start_session --> prestart --> jjw --> sparse --> agent
    session --> resume --> prestart
  end
```
