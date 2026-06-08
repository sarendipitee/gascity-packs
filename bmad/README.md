# BMAD Pack

This pack implements the Gas City `build-base` workflow contract with vendored
[BMAD Method](https://github.com/bmad-code-org/BMAD-METHOD) skills.

## What It Provides

- Formula: `bmad-build`
- Vendored skills: `bmad-prd`, `bmad-create-architecture`,
  `bmad-check-implementation-readiness`, `bmad-create-epics-and-stories`,
  `bmad-quick-dev`, `bmad-dev-story`, `bmad-code-review`,
  `bmad-brainstorming`, and `bmad-spec`
- Provenance: `vendor/bmad-method/upstream.toml`

BMAD maps naturally onto the full lifecycle base: PRD, architecture, readiness,
epics/stories, implementation, review, finalize, and publish.

## Import It

Import this pack alongside the Gas City pack that provides `build-base`:

```toml
[imports.gc]
source = "../gascity-packs/gascity"

[imports.bmad]
source = "../gascity-packs/bmad"
```

Then launch `bmad-build` from the target rig context.
