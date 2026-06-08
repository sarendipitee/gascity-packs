# Compound Engineering Pack

This pack implements the Gas City `build-base` workflow contract with vendored
[Compound Engineering Plugin](https://github.com/EveryInc/compound-engineering-plugin)
skills.

## What It Provides

- Formula: `compound-build`
- Vendored skills: `ce-brainstorm`, `ce-plan`, `ce-work`, `ce-code-review`,
  and `ce-compound`
- Provenance: `vendor/compound-engineering-plugin/upstream.toml`

`ce-compound` is used during the `finalize` stage. The base workflow does not
add a separate compound stage.

## Import It

Import this pack alongside the Gas City pack that provides `build-base`:

```toml
[imports.gc]
source = "../gascity-packs/gascity"

[imports.compound-engineering]
source = "../gascity-packs/compound-engineering"
```

Then launch `compound-build` from the target rig context.
