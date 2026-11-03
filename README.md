# Model Lab

Version 0.2.0 · see [CHANGELOG.md](CHANGELOG.md)

A Jaide plugin for formal verification with Bend: explore a project's state
machines, check their laws one proof at a time, and replay any counterexample
in both the state machine and the project's architecture.

The plugin carries no models. Each project describes its own cases in
`.model-lab/cases/<id>/case.mjs` (see [docs/CASES.md](docs/CASES.md)), next to
the code they verify.

## Install

In a Jaide project, install from the published repository (Cmd+K, or ask the
agent to run `install_plugin` with the repository's https URL), then open
**Model Lab**. The first time it runs Bun, allow it in the pane.

Requires Jaide plugin SDK 13, [Bun](https://bun.sh) and Bend **2.0.5**. The
runner uses `~/.bend/current` directly; `MODEL_LAB_BEND` can point at another
installation of that exact version. It never installs or updates a checker.

## Using it

- **Tabs** are the project's cases; **Rescan** reads `.model-lab/cases` again.
  A tab marked ⚠ has problems, listed under the tabs with their file and field.
- **Design** and **scenario** pick the two choices the case offers. Changing
  either reloads the model.
- **Verify** freezes the loaded revision and runs each proof as its own step.
  The panel collapses to one line; **Show steps** lists each proof.
- **Explore the model**: Back, Forward, the walkthrough, Step and Reset sit at
  the top; the events possible from the current state, the metrics and a
  clickable history sit below the diagrams. A failed law offers
  **Show how it fails**, which replays its shortest counterexample.
- **Architecture** (when the case describes one) animates each step's route
  through the real components, marks side effects such as queued work, and
  turns a component red where a rule breaks.

Every load and check keeps its exact sources, generated inputs, checker
version, results and a Markdown `report.md` under `.jaide/model-lab/runs/<id>/`.
These are local evidence files, not signed attestations.

## For agents

Another conversation can use Model Lab without the pane, through
`operations`/`perform` on `local/model-lab.<name>` with the instance id
(`operations` lists it):

| Operation | What it does |
|---|---|
| `status` | Cases with their designs and scenarios, the loaded model, `pending`, laws and verification steps |
| `configure` `{case, design, scenario}`, `reload`, `rescan` | Load; poll `status` until `pending` is null |
| `explain` | The current state as text and fields: rows, metrics, possible events, the last step |
| `step` `{event}`, `back`, `forward`, `seek` `{step}`, `reset` | Move; each answers like `explain` |
| `replay` `{law, step?}` | Replay a broken law's counterexample |
| `counterexamples` | Each broken law: failure text, trace as event names, each step's change and state |
| `verify`, then `report` | Verify the loaded revision; a Markdown summary for a PR or plan |

From the terminal, in the project root, no pane is needed at all:

```sh
bun .jaide/plugins/model-lab/runner.mjs list
bun .jaide/plugins/model-lab/runner.mjs report <case> <design> <scenario> [--fresh]
bun .jaide/plugins/model-lab/runner.mjs check-case <case> [<design> <scenario>]
```

`report` prints the latest verification of the current revision, verifying
first when there is none (or with `--fresh`). `check-case` prints every
problem in a case, one line each, and exits 1 if there are any.

## Limits

Exploration stops at 3000 states and 90000 transitions. The closure proof
costs about 0.1 ms per (state, event): 496 states × 30 events check in about
2 s, and 3000 states × 30 events would take about 10 s, inside the default
30 s per proof (`timeout` in a case raises it to 110 s). Each law check takes
well under a second at these sizes.

## Development

```sh
scripts/install-dev.sh <project folder> [plugin folder id]   # sync into a project
bun test ./tests                                             # runner tests (needs Bend 2.0.5)
```

`install-dev.sh` syncs files into the existing plugin folder. Never replace a
live plugin folder: Jaide's registration is tied to the folder itself.

The parts: `plugin.luau` wires `state.luau` (sessions and moving through the
graph), `load.luau` (the runner task), `graph.luau` (reading the graph,
explanations), `operations.luau` (agent operations) and `views/`. The runner
is `runner.mjs` with `lab.mjs` (helpers passed to cases), `closure.mjs`
(certificates), `check.mjs` (case problems), `report.mjs` and `wire.mjs`
(how graphs travel: repeated views are sent once, edges as
`[from, to, event, view]`, and a graph over 40 KB in pages read once per
revision, because Jaide reads at most 48 KiB from each process call).

### Smoke test

`scripts/smoke.luau` drives one open instance through its whole lifecycle with
public operations: rescan, load every case, step its walkthrough, back,
forward, seek, an impossible event, replay a counterexample, verify and
report. Set `PLUGIN` (the manifest id, such as `model-lab-pnp` for a
development install) and, with several instances open, `INSTANCE` at the top,
then pass the file's text to `run_luau`. It returns
`{pass, checks, failures, captures}`; in the conversation developing the
plugin it also takes two captures with `check_plugin`.

## Licence

Apache License 2.0; see [LICENSE](LICENSE).
