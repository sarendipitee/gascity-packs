# gascity-jj-base Sling Review

Schema: `gc.build.review.v1`
Source change: `tynmlvxmoqkw` (`a8e075e1dc58`)
Review change: `xylxutzm`

## Findings

1. **P2 - Fix-loop document describe steps cannot identify the document workspace**

   `gascity-jj-base/formulas/jj-fix-loop.formula.toml:47` and `gascity-jj-base/formulas/jj-fix-loop.formula.toml:75` add document-scoped describe steps, but their metadata omits `gc.docs.workspace_key` and `gc.docs.workspace_path_key`. The shared describe instructions require agents to work in "the jj workspace selected by step metadata"; without these keys, the fix-plan and re-review describe steps do not carry enough information to select the default@ document workspace before running `jj describe`.

   Other document-scoped describe steps in this change include the document workspace metadata, so fix-loop is the inconsistent path. Add the two document workspace metadata keys to both `describe-fix-plan-change` and `describe-re-review-change`, and extend the regression test to assert that document-scoped describe steps declare document workspace metadata.

## Verification

- `pytest -q gascity-jj-base/tests/test_gascity_jj_base_pack.py` - 12 passed.
- Checked all formula describe steps for workspace metadata; only the two `jj-fix-loop` document-scoped describe steps were missing it.
