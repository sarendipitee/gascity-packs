Use the built-in Gas City guided starter factory requirements flow.

Create the requirements artifact with the same expectations as the
`generate-requirements` stage in the GitHub issue fix workflow: preserve the
input target, normalize the artifact path, and make the acceptance criteria
specific enough for plan review.

Keep the artifact approachable for a first factory run. Include these sections:

- goal
- constraints
- acceptance criteria
- non-goals
- open questions

If `interaction_mode` is interactive or the user is present, ask only the
minimum question needed to unblock the artifact. If the workflow is autonomous
or headless, record unresolved ambiguity in open questions instead of blocking
without a clear need.

Record the requirements path on the workflow root bead before closing.
