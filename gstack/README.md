# gstack Gas City Pack

This pack adapts the [garrytan/gstack](https://github.com/garrytan/gstack)
methodology into Gas City formulas. It keeps the recognizable garrytan/gstack sprint:

Think -> Plan -> Build -> Review -> Test -> Ship -> Reflect

The upstream project is a Claude Code skills pack with roles such as YC Office
Hours, CEO/founder review, engineering review, design review, staff review, QA,
CSO security, documentation, and release engineering. In this pack those roles
are providerless Gas City agents, and their multi-agent handoffs are Gas City
fanouts.

The pack-local compatibility ledger lives at
[`gstack/REQUIREMENTS.md`](./REQUIREMENTS.md) and records the build-base
contract proofs, including the inherited `gc` import, the preserved anchor
order, and the qa/release-readiness insertion between review and finalize.

## Usage

Run `gstack-build` for a full product sprint:

```bash
gc formula run gstack-build --var artifact_root=.gc/artifacts/gstack-demo
```

The default flow is interactive because raw gstack is intentionally
conversation-heavy:

- `requirements` uses the office-hours posture to force demand, status quo,
  user specificity, narrow wedge, observation, and future-fit into the
  requirements artifact.
- `plan-review` runs CEO, design, engineering, and developer-experience lanes
  through the `gstack-plan-review` fanout.
- `review` runs staff, QA-evidence, security, and gap-analysis lanes through
  `gstack-code-review`.
- `qa` runs browser-oriented QA and regression-test evidence through
  `gstack-qa-review`.
- `release-readiness` runs document-release, ship, and deploy readiness lanes
  through `gstack-release-readiness`.

Set `interaction_mode=autonomous` when an adapter must avoid human gates. Set
`review_mode=report` when the run should write findings without applying fixes
or opening release paths. The key mode variables are `interaction_mode` and
`review_mode`.

## Supported Modes and Drain Policies

Supported modes and drain policies, as declared in
`[metadata.gc.methodology]` of `gstack-build`:

- `interaction_modes`: `interactive`, `autonomous`, `headless` (inherited
  `interaction_mode` var; the pack pins the default to `interactive` because
  raw gstack is conversation-heavy)
- `review_modes`: `report`, `agent`, `interactive` (inherited `review_mode`
  var; the pack pins the default to `interactive` to match the office-hours
  posture)
- `implementation_strategy`: `drain` with `allowed_drain_policies` of
  `separate` (drains `gstack-work` item formulas with exclusive member
  access) and `same-session` (drains `gstack-work-item` in one shared
  single-lane session with `on_item_failure = "skip_remaining"`)

The review/fix loop is graph structure: the `review` anchor expands
`gstack-code-review`, which records the review context, fans out sibling
staff, QA-evidence, CSO-security, and gap-analysis lanes, fans in at
`synthesize-code-review`, and loops an `apply-review-findings` lane (routed
to the caller-selected implementation target) through a bounded graph check
until the `code_review.verdict=done` approval lands on the workflow root. The
`qa` and `release-readiness` anchors apply the same check-gated loop shape,
and `gstack-fix-loop` carries the review-fix contract for standalone adapter
use.

## Adapter Selectors

Use these values when launching shared Gas City adapters:

```text
planning_formula=gstack-planning
decomposition_formula=gstack-decomposition
implementation_formula=gstack-implementation
implementation_item_formula=gstack-work-item
code_review_formula=gstack-review
review_fix_formula=gstack-fix-loop
implementation_target=gstack.implementer
```

Raw-framework subagents become Gas City fanouts. Do not preserve upstream
subagent behavior as provider-native subagents; model that work as formulas or
expansion children.

## Pack Shape

The vendored upstream files under `vendor/gstack` are reference material. The
installed files under `skills/` expose the same vocabulary for agents. Runtime
execution is owned by formulas, beads, and Gas City graph lanes.

This keeps the first-time gstack experience approachable while making the
automation factory durable: work is persistent, fanout is observable, retries
are graph-level, and adapters can select the same methodology without knowing
about Claude slash commands.
