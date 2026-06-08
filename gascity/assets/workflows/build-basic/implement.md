Use the built-in Gas City `build-run` helper for the implementation back half.

Launch or reuse `build-run` with the artifact root, context path, drain policy, iteration limit, push flag, and open PR flag inherited from this workflow. Store the build-run workflow id and summary path on the workflow root bead.

Close this step only after build-run reports a clean implementation result or an explicit failure artifact.
