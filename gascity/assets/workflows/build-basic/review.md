Use the built-in Gas City starter factory post-implementation review loop.

The `build-basic-review` expansion has already created three review lanes:
acceptance/correctness, test evidence, and simplicity/maintainability. Record
that this starter factory review fanout is active, then let the expansion own
review synthesis, required fixes, and the final `code_review.verdict`.

Record the synthesized review report path and pass/fail outcome on the workflow
root bead.
