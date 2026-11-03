---
name: model-lab-case
description: Model a system flow in Bend 2 and add it to Model Lab as a verification case (.model-lab/cases/<id>/case.mjs). Use when asked to formally model, verify or find counterexamples in a flow (retries, idempotency, outboxes, status updates), or to add or change a Model Lab case.
---

# Writing a Model Lab case

The case format is in the plugin's `docs/CASES.md`; read it first. Working
examples: the plugin's `tests/fixture/.model-lab/cases/toggle` (smallest), and
integration-platform's `.model-lab/cases/pnp-po-flow` (a full system: every
answer code, lost replies, outbox, architecture).

## Modelling the flow

- Enumerate events from the real system, not from the happy path: every answer
  code of every call, each paired with what *really* happened downstream
  ("500 after the supplier accepted"), lost replies, crashes between a write and
  its reply, failed writes when recording, timeouts with requests still in
  flight, retries, people acting, and what the caller does with each answer.
- Make each design question a **design** (what we choose) and each environment
  assumption a **scenario** (what we cannot control). Keep variants that fail:
  their counterexamples are the reasons for the design.
- Laws are about states ("never two orders", "told 04 only when nothing is
  ordered"), so checking every reachable state covers every step.
- Keep state small: counts that saturate at 2, flags as 0/1. Plain `Nat`
  fields make equality and certificates trivial. The closure proof costs
  about 0.1 ms per (state, event), so 500 states × 30 events take ~2 s; the
  explorer stops at 3000 states.
- "Something eventually happens" (every PO finishes) is a **progress**
  property, not a law: give `progress` with `done(node)` and a Bend `bend` test.

## Bend 2 (2.0.5) traps

- Variables are affine: mark a parameter or pattern variable `+` when it is
  used more than once (`case State{+p, +r, …}`, `+x = v`).
- `match` scrutinees in parameter order, or "reorder the match". Match the
  first parameter first; swap parameters if needed.
- Define a function before using it.
- `Event` already exists in `Base`; pick another name (`Act`).
- No `if`: write a `pick(c: Bool, a, b)` helper with `match c`. `case x:` is a
  catch-all. Nat literals are `0n`; `(n + 1n)` is Nat arithmetic; `Nat.min`,
  `Nat.sub` (saturating), `Nat.is_eq`, `Nat.is_le`, `Bool.and/or/not`.
- From JS (after `await import(bend2/main.ts)`, import the `.bend` file):
  definitions are functions, constructors are `{ $: 'Name', …fields }` (the
  name may carry a module prefix: use `.split('.').pop()`), Nat is BigInt,
  `Bool` is a JS boolean, lists are `Con{head, tail}` / `Nil`.

## The proof pattern

The runner passes `lab` to `sources` and `explore`; use it rather than copying
helpers (docs/CASES.md shows a 40-line case).

1. `lab.explore` walks the graph breadth-first from the start: every event
   from every state. The first path that breaks a law is its shortest
   counterexample.
2. `lab.closure.modules` writes `CLOSURE.bend`: the reachable states in a tree,
   each with the path to its successor under every event of `events()`.
3. `lab.closure.claim()` proves the tree contains the start and is closed under
   every event: the JS enumeration cannot have missed a state.
4. One proof per law checks the law in every state of `lab.closure.states()`
   (the model's `check`).
5. `lab.proofModules` gives each claim a `CHECK-<id>.bend` that restates it and
   calls the proof module, so an empty or weakened proof cannot pass.

The model itself needs `initial`, `step`, `events`, `equal`, `holds`,
`holds_in` and `check`; no `contains` or `complete`.

## Loop

```sh
# from the project root, with Model Lab installed at .jaide/plugins/model-lab
bun .jaide/plugins/model-lab/runner.mjs check-case <case>            # every problem, one line each
bun .jaide/plugins/model-lab/runner.mjs report <case> <design> <scenario>   # verify, as Markdown
```

Check every design × scenario from the terminal before opening the plugin;
confirm the intended design proves and each rejected design fails with a
counterexample you can explain. Then describe `view` (rows, architecture),
`describe` and `transition`, press **Rescan** in Model Lab, and step through a
counterexample to see that each step's route matches the real system.
