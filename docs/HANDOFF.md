# Handoff: make Model Lab easier for agents to build on and use

Model Lab is a standalone Jaide plugin for formal verification with Bend 2.0.5.
It works today (see "Current state"), but it was grown in one long session and
several things make the next agent slower than it needs to be. This document
lists them as tasks, most valuable first, each with what "done" means.

## Status (2026-11-03)

Tasks 1–9 are implemented; see CHANGELOG.md 0.2.0. `bun test ./tests` passes
(12 tests). All 26 PnP design × scenario runs explore to the same graphs and
laws as before, and each verifies in at most 4 s. What is still open:

- **No pane check yet.** The new Luau (split modules, operations, wire
  format, state version 9) ran in a headless harness: real Luau, stubbed
  `jaide`/`ui`, the real runner. It has not been loaded in Jaide.
  `scripts/smoke.luau` passed 72 of 72 checks there. To finish:
  `scripts/install-dev.sh /Users/danfel/dev/ip model-lab-pnp`, press
  **Allow**, `check_plugin`, run `scripts/smoke.luau` (PLUGIN =
  'model-lab-pnp') with `run_luau`, and compare two captures with the previous
  version at the same state. Until then the installed `model-lab-pnp` is the
  old version.
- **Bend progress proofs** need a `bend` test per progress property. Only
  `pnp-po-flow` has one so far (`Finishes`).
- **Conformance** (`compare`) is wired, but no case uses it yet. `PnpErp.Worker`
  does not exist yet.

## Read first

- `README.md`: what the plugin does, install, development.
- `docs/CASES.md`: the case format (`.model-lab/cases/<id>/case.mjs` in a project).
- `skills/model-lab-case/SKILL.md`: modelling a flow in Bend and writing a case.
- The `jaide-plugins` skill (`ip/.claude/skills/jaide-plugins/SKILL.md` in the
  space this was built in): plugin rules that each cost real time. Most
  important: never delete and recreate a live plugin folder, `run_process`
  reads at most 48 KiB of stdout, every new revision needs the person's
  **Allow**, operations and events cannot share a name, and controls must never
  move between steps.

## Current state

- Repository: `/Users/danfel/dev/ip/model-lab` (may move to
  `~/dev/personal/model-lab`). Git initialised; **nothing committed yet**, no
  remote, no licence.
- Files: `plugin.luau` (739 lines: state, handlers, operations and the whole
  view), `render.luau` (state rows and architecture SVG from case data),
  `motion.luau`, `runner.mjs` (discovery, explore, per-proof verify, paging),
  `checker.mjs`, `plugin.css`, `scripts/install-dev.sh`, `tests/` (5 Bun tests
  against a fixture case).
- Real cases to test against: `integration-platform/.model-lab/` (next to the
  repo in the same space): `pnp-po-flow` (184–496 states, 30 events,
  architecture with 9 components) and `pnp-po-worker`.
- Development install: `scripts/install-dev.sh /Users/danfel/dev/ip model-lab-pnp`
  syncs into `ip/.jaide/plugins/model-lab-pnp`, the folder the open tab uses.
- Checks: `bun test ./tests` (5 pass); from `/Users/danfel/dev/ip`:
  `bun .jaide/plugins/model-lab-pnp/runner.mjs verify pnp-po-flow plan contract`
  must report `proof.status: proved`.
- The person wants: a static layout (nothing clickable moves on Step, autoplay
  or label changes), work kept inside the space's folders, and no AI
  attribution lines in PRs.

## Tasks

### 1. Let agents use Model Lab through operations, not only the pane

Today an agent can `configure`, `reload`, `verify`, `rescan` and read `status`,
but exploring needs `send_plugin_event`, which only the conversation that
develops the plugin may use. `status` returns event ids and counterexamples as
raw ids.

Add operations (observe or keep effect) that make the plugin a tool:
- `explain`: the current state as text: each row's value label, the metrics,
  the possible events with their names, and the last step's caption.
- `step` (`event`), `back`, `forward`, `seek` (`step`): move, returning `explain`.
- `counterexamples`: each failed law with its failure text and its trace as
  event *names*, plus the state after each step.
- `report`: a Markdown summary of the latest verification (laws, proof results,
  counterexamples) that an agent can paste into a PR or plan.

Also add `bun runner.mjs report <case> <policy> <scenario>` printing the same
Markdown from the terminal, so agents need not open the plugin at all.

Done when: another conversation can load a case, replay a counterexample and
produce the report using only `operations`/`perform` and the runner CLI.

### 2. Split `plugin.luau`

The view function is ~300 lines building every panel inline; state, handlers,
operations and view live in one 739-line file. Split into modules with one job
each, for example `state.luau` (sessions, catalogue, history: back, forward,
seek), `load.luau` (`read_model`, paging, validation), `views/verification.luau`,
`views/explorer.luau`, `views/history.luau`, `views/evidence.luau`, and a short
`plugin.luau` wiring them. Behaviour must not change.

Done when: no module over ~250 lines, the pane looks identical in two captures
(before/after) at the same state, and task 3's smoke test passes.

### 3. A repeatable smoke test for the pane

Upstream Jaide tested the Luau through its own Rust harness, which this repo
does not have. Add `scripts/smoke.luau`, a script for `run_luau` that drives a
named plugin instance through: reload → select each case → step the
walkthrough → back → forward → seek → replay the first counterexample →
verify, asserting no handler error and the expected `current`/`trail` after
each, and returning two captures. Document how to run it in `README.md`.

Done when: one `run_luau` call with the instance id reports pass/fail for the
whole lifecycle.

### 4. A helper library for cases

`explore` (breadth-first walk with shortest counterexamples), proof module
generation (`<id>.bend` + `CHECK-<id>.bend`), Bend list decoding, BigInt-safe
encoding and walkthrough filtering are copied into every case
(`integration-platform/.model-lab/pnp.mjs`, the test fixture). Cases cannot
import the plugin by path (its folder id varies). Pass the helpers in instead:
`explore(model, policy, scenario, lab)` and `sources(policy, scenario, lab)`,
where `lab` exposes `explore`, `proofModules`, `list`, `encode`, `walk`, and the
certificate pattern (closed reachable set). Keep the current signatures working.

Done when: the fixture and both PnP cases use `lab` and lose their copies, and
`docs/CASES.md` shows a minimal case of ~40 lines.

### 5. `check-case`: validate a case with clear errors

A malformed case fails late (a row value out of range, a hop to an unknown
component, a missing CHECK module, a law id without a failure text). Add
`bun runner.mjs check-case <id>` that loads the case, explores the first
policy × scenario, and reports every problem with the file and field: rows
labels and node values, `describe` component ids, `transition` hops and side
ids, `names` covering every event, `failures` covering every law, proofs having
CHECK modules. Show the same problems in the pane next to the case's tab.

Done when: each kind of mistake above produces one readable line.

### 6. Make large graphs cheap

Per-edge `view` objects repeat the same notes and routes thousands of times:
`pnp-po-flow notidem500` (256 states, 4154 edges) needs 17 pages of 40 KB, and
each verification step re-reads every page because the task replaces bulk
data wholesale. Options, in order of payoff:
- Intern edge views: send a table of distinct views and an index per edge.
- `advance` returns only `steps` and `proof`; keep the graph from the first
  load (for example cache it under the run directory and have the plugin
  request pages only when the revision changes).
- Drop `edges[].view` for events whose description is the default.

Done when: `notidem500` loads in ≤ 4 pages and a full verify reads the graph once.

### 7. Scale the checker beyond a few hundred states

The closure proof uses a list `contains`, so it is quadratic: ~450 states take
~16 s and each proof times out at 30 s. Replace it with an encoding the checker
can look up cheaply (states numbered by their field values, or a sorted list
with a binary search), and allow a per-case timeout. Measure before and after
on `pnp-po-flow` (`personearly realistic`, 496 states).

Done when: the 496-state run verifies in well under the timeout, and the
README states the practical limit.

### 8. Progress properties and implementation conformance

Laws today are state invariants. Two gaps people will ask about next:
- **Progress:** "every PO eventually reaches Ordered or Rejected" (from every
  reachable state some terminal state is reachable, possibly through a person).
  Compute it in JS over the graph, report the states that cannot finish, and
  add a Bend proof over the certificate.
- **Conformance:** the upstream checkout example compared a C# implementation
  with the model state by state; that hook was dropped. Bring it back as an
  optional case member (`compare(graph, policy, scenario)`) shown as its own
  verification step, so a project can replay every model edge against its
  real code (for PnP ERP: `PnpErp.Worker` once it exists).

### 9. Naming and release hygiene

- State and operations still say `example` and `policy` from the first version;
  agents see `example: 'pnp-po-flow'`. Rename to `case`/`design` in state
  (bump the state version with a migration) and in operation arguments.
- Before publishing: choose and add a licence, add `CHANGELOG.md` and a version
  line, add `AGENTS.md` pointing at the two skills, make the first commit, and
  leave pushing to the person.

## Constraints for whoever picks this up

- Stay inside this repository (and, for testing, the PnP cases in
  `integration-platform/.model-lab`). Do not edit the Jaide repository.
- Never replace `ip/.jaide/plugins/model-lab-pnp`; use `scripts/install-dev.sh`.
- After each change: `bun test ./tests`, sync, `check_plugin`, then two captures
  at different states to confirm nothing clickable moved. Tell the person when a
  new revision needs **Allow**.
