Finalize the `build-basic` workflow.

Summarize requirements, implementation-plan, design-review, create-beads,
implementation, and review artifacts. Record the final outcome, artifact paths,
and remaining follow-up beads on the workflow root bead.

Write `factory-run.md` under the build artifact root. Keep it short and useful
for a first-time factory user:

- methodology: build-basic starter factory
- requirements, plan, decomposition, implementation, and review artifact paths
- implementation convoy id
- review lanes that ran
- proof commands or test summaries that were recorded
- publish outcome
- next human action

Record the `factory-run.md` path on the workflow root bead as
`gc.build.factory_run_path=<path>`.

Do not publish from this step.
