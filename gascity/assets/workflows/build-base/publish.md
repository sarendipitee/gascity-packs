This is the `build-base` publish stage. Treat it as a virtual contract that concrete formulas may override.

If `push` or `open_pr` is enabled, publish the finalized build result according to the workflow metadata. If publishing is disabled, record the exact reason and leave the artifacts ready for a later publisher.

Close this step only after the publish action or explicit no-op is recorded.
