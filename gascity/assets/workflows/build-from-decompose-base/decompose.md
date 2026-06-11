This is the `build-from-decompose-base` decomposition stage.

Read the approved requirements from `{{requirements_path}}`, the approved implementation plan from `{{plan_path}}`, and the plan-review verdict from `{{plan_review_path}}`. Use the selected decomposition methodology `{{decomposition_formula}}` when translating the plan into durable work items.

Create or adopt an implementation convoy for the work units. The convoy must contain only runnable implementation beads for this continuation; do not reuse any original request, planning, or workflow-control convoy.

Write the decomposition artifact to `{{decomposition_path}}` when supplied; otherwise write it under `{{artifact_root}}` as the default decomposition artifact. The decomposition must include work item IDs, requirement and plan traceability, expected files or formula assets, verification expectations, dependencies, skipped work, and blocked work with rationale.

Record the implementation convoy ID on the workflow root bead as both:

- `gc.input_convoy_id=<implementation-convoy-id>` for the drain contract.
- `gc.build.implementation_convoy_id=<implementation-convoy-id>` for continuation reporting.

Close this step only after the decomposition artifact is recorded and both convoy metadata fields are set. Verify the recorded implementation convoy is not the original launch or workflow-control convoy.
