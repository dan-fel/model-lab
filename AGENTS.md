# Model Lab: notes for agents

Model Lab is a Jaide plugin (Luau pane + a Bun runner) that explores and proves
Bend 2.0.5 models a project describes in `.model-lab/cases/<id>/case.mjs`.

Read first:
- `README.md`: what it does, agent operations, the terminal commands, limits.
- `docs/CASES.md`: the case format and the `lab` helpers.
- `skills/model-lab-case/SKILL.md`: modelling a flow in Bend and writing a case.
- The `jaide-plugins` skill, if the space has one (`.claude/skills/jaide-plugins`):
  plugin rules that each cost real time (never replace a live plugin folder,
  48 KiB per process answer, every revision needs the person's **Allow**,
  operations and events cannot share a name, controls must not move).

Using it without the pane: `bun <plugin>/runner.mjs report|check-case …` from
the project root, or the `local/model-lab.*` operations (README, "For agents").

Changing it:
- `bun test ./tests` (needs Bend 2.0.5 at `~/.bend/current`).
- Sync into a project with `scripts/install-dev.sh <project> [id]`, never by
  replacing the plugin folder; then `check_plugin`, run `scripts/smoke.luau`
  with `run_luau`, and compare two captures at different states to see that
  nothing clickable moved. Tell the person when a new revision needs **Allow**.
- Keep modules short and single-purpose (see "Development" in the README).
