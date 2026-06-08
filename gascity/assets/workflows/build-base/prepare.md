This is the `build-base` prepare stage. Treat it as a virtual contract that concrete formulas may override.

Validate the target, artifact root, and optional context inputs. Record the normalized artifact paths on the workflow root bead so later stages can reuse them without inventing new locations.

Do not edit source files. Close this step only after the required paths and input assumptions are explicit.
