# Changelog

## 0.2.0

- Agents can use Model Lab through operations: `explain`, `step`, `back`,
  `forward`, `seek`, `reset`, `replay`, `counterexamples` and `report`, besides
  `status`, `configure`, `reload`, `rescan` and `verify`.
- `runner.mjs report <case> <design> <scenario>` prints a Markdown summary of
  the latest verification; every run also keeps it as `report.md`.
- `runner.mjs check-case <case>` lists every problem in a case, one line each
  with its file and field; the pane marks a case with problems and lists them.
  A load with a broken graph now fails with those reasons.
- Cases receive the helpers as `lab` (`explore`, `walk`, `list`, `encode`,
  `proofs`, `proofModules`, `closure`), so they no longer copy them.
- The closure proof uses a tree of states with a witness path per event: 496
  states × 30 events prove in about 2 s instead of timing out after 30 s.
  Cases may set `timeout` (seconds per proof).
- Progress properties (`progress`): states that can no longer finish, the
  shortest way into one, and a Bend proof over the closed set.
- Optional `compare(graph, design, scenario)` runs as the last verification
  step, to replay the model against the real implementation.
- Graphs travel with each distinct view once and compact edges: the 256-state,
  4154-edge `notidem500` graph takes 3 pages instead of 17, and a verification
  reads its pages once rather than at every step.
- Apache License 2.0.
- Names: `case` and `design` replace `example` and `policy` in state (version
  9, migrated), operation arguments and runner output (format 4). Cases may
  still say `policies` and `policyLabel`.
- `plugin.luau` is split into `state`, `load`, `graph`, `operations` and
  `views/`; `scripts/smoke.luau` tests the whole lifecycle through `run_luau`.

## 0.1.0

- First version: project cases, exploration, per-proof verification, replay of
  counterexamples in the state machine and the architecture.
