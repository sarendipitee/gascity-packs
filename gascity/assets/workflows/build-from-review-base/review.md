This is the `build-from-review-base` review stage.

Review the implementation against:

- requirements_path: {{requirements_path}}
- plan_path: {{plan_path}}
- plan_review_path: {{plan_review_path}}
- decomposition_path: {{decomposition_path}}
- implementation_summary_path: {{implementation_summary_path}}
- code_review_formula: {{code_review_formula}}
- review_fix_formula: {{review_fix_formula}}
- implementation_formula: {{implementation_formula}}
- implementation_item_formula: {{implementation_item_formula}}
- review_mode: {{review_mode}}
- interaction_mode: {{interaction_mode}}
- max_iterations: {{max_iterations}}

Use the selected code review methodology to produce a review verdict and
findings. This stage records the review result; the following `repair-review`
stage owns any selected review-fix loop, restart handoff, or blocked repair
state.

For `review_mode=report`, write findings and verdicts without mutating code.
For `review_mode=agent`, write a structured fix handoff for the caller or
selected fix loop. For `review_mode=interactive`, safe fixes may be negotiated
or applied, but every change and reason must be recorded.

Close this step only when the implementation has a concrete review verdict:
`approved`, `changes_required`, or `blocked`. Record the review report path,
verdict, unresolved findings, drift observations, and any existing fix-attempt
count on the workflow root metadata.
