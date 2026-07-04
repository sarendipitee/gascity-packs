# Validate JJ Review Context

Validate that the review has stable source and document inputs.

Required behavior:

- Confirm `{{manifest_path}}` exists or can be derived from workflow root
  metadata.
- Confirm all manifest document paths needed for the review are readable.
- Confirm `{{source_change_id}}` or `{{subject_path}}` identifies the source or
  artifact state to review.
- Report any missing path, hash, schema, or change ID as a blocking context
  issue.

Do not start a review from prompt-only context when the manifest or source
identity is missing.
