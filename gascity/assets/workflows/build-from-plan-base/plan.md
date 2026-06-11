This is the `build-from-plan-base` plan stage.

Produce or reuse the implementation plan using approved requirements from
`{{requirements_path}}`. Write the plan to `{{plan_path}}` when provided;
otherwise write the default implementation-plan artifact under
`{{artifact_root}}`.

The plan must preserve requirement traceability, upstream hashes, assumptions,
risks, out-of-scope work, and verification strategy. Close only after the plan
path and content hash are recorded for the inherited decompose suffix.
