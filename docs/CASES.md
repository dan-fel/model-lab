# Writing a Model Lab case

A case is one Bend model that Model Lab can explore, verify and replay, with
the description it needs to draw it. Cases belong to the project they verify,
not to the plugin.

```
<project>/.model-lab/cases/<id>/case.mjs
<project>/<folder>/.model-lab/cases/<id>/case.mjs   # a space with several repositories
```

The folder name is the case's id. Model Lab finds every `case.mjs` there when
it opens and when you press **Rescan**. A case that fails to load is listed
with its error and the others still work. Run
`bun <plugin>/runner.mjs check-case <id>` to list every problem in a case,
one per line with its file and field; the pane marks such a case's tab with ⚠.

## A minimal case

The runner passes its helper library to the case as `lab`, so a case holds only
what is its own. This is the plugin's test fixture (`tests/fixture`), a switch
whose Broken design lets a jam leave it neither on nor off:

```js
import fs from 'node:fs';
import path from 'node:path';

const designs = { safe: 'Safe', broken: 'Broken' };
const obligations = { OnIsBinary: 'The switch is on or off' };
const imports = 'import Base\nimport ./Toggle.bend as T\nimport ./Config.bend as Config\nimport ./CLOSURE.bend as Closure\n';

export default {
    label: 'Toggle', title: 'A switch', intro: 'Can a jam leave the switch neither on nor off?',
    designs: [['safe', 'Safe'], ['broken', 'Broken']], scenarios: [['default', 'Default']],
    names: { Flip: 'Flip', Jam: 'Jam' }, failures: { OnIsBinary: 'The switch is neither on nor off.' },
    scope: 'One switch; flips saturate at two.',
    entry: 'Toggle.bend',
    proofs: lab => lab.proofs(lab.closure.claim(), obligations, id => `T.check(T.${id}{}, ${lab.closure.states()})`),
    sources(design, _scenario, lab) {
        return {
            'Toggle.bend': fs.readFileSync(path.join(import.meta.dirname, 'Toggle.bend'), 'utf8'),
            'Config.bend': `import ./Toggle.bend as T\ndef policy() -> T.Policy:\n  T.${designs[design]}{}\n`,
            ...lab.proofModules(imports, this.proofs),
        };
    },
    explore(m, design, _scenario, lab) {
        const p = { $: designs[design] };
        const graph = lab.explore({
            initial: m.initial(), events: lab.list(m.events()), obligations,
            step: (event, state) => m.step(p, event, state), equal: m.equal,
            holds: (id, before, after) => m.holds({ $: id }, before, after),
            node: state => ({ on: Number(state.on), flips: Number(state.flips), safe: m.holds_in({ $: 'OnIsBinary' }, state) }),
        });
        return { ...graph, walkthrough: lab.walk(graph.edges, ['Flip', 'Flip']),
            generated: lab.closure.modules({ imports: 'import Base\nimport ./Toggle.bend as T\nimport ./Config.bend as Config\n',
                type: 'T.State', event: 'T.Act', render: s => `T.State{${Number(s.on)}n, ${Number(s.flips)}n}`, explored: graph,
                step: (e, s) => `T.step(Config.policy(), ${e}, ${s})`, initial: 'T.initial()', equal: 'T.equal', events: 'T.events()' }) };
    },
    view: { rows: [{ label: 'Switch', field: 'on', labels: ['Off', 'On', 'Jammed'] }, { label: 'Flips', field: 'flips', labels: ['0', '1', '2+'] }] },
};
```

The Bend model (`Toggle.bend`) defines `initial`, `step`, `events`, `equal`,
`holds`, `holds_in` and `check`; nothing about certificates. The fixture adds
`describe`, `transition` and an architecture to the 40 lines above.

## What `case.mjs` exports

A default export with these members. `bun` runs it from the project root.
Methods are called on the case, so `this.proofs` is the resolved proof list.

| Member | What it is |
|---|---|
| `label` | Short name for the tab |
| `title`, `intro` | Heading and one-line question the case answers |
| `designs`, `scenarios` | `[[id, label], …]`: two independent choices (what we choose, and what we cannot control). The first of each is the default. Older cases call designs `policies`; both work. |
| `designLabel`, `scenarioLabel` | Captions for those two choices (default "Design", "Scenario"; `policyLabel` also works) |
| `names` | `{ Event: 'label' }` for every event the model can take |
| `failures` | `{ Law: 'what went wrong' }` for every law, shown when it breaks |
| `scope` | What the model covers and assumes, shown under the verdict |
| `walkthroughLabel` | Label of the play button for the walkthrough (default "Play scenario") |
| `entry` | The Bend file, among `sources`, that `explore` receives as a module |
| `sources(design, scenario, lab)` | `{ file: text }`: every Bend file to check, including proof modules |
| `proofs` | `[{ id, label, claim }]`, or `lab => […]`: one verification step each, run in order (at most 14) |
| `explore(model, design, scenario, lab)` | The reachable graph, see below |
| `view` | How to draw it, see below |
| `describe(node)` | Optional: captions, red components and metrics for one state |
| `transition(before, after, event)` | Optional: which components an event passes through |
| `progress` | Optional: `{ id, label, done(node), bend? }` or a list of them, see below |
| `compare(graph, design, scenario)` | Optional: replay the model against the real implementation, see below |
| `compareLabel` | Label of that verification step (default "Implementation matches the model") |
| `timeout` | Optional: seconds each proof may take, 1–110 (default 30) |

## `lab`

| Helper | What it does |
|---|---|
| `lab.list(value)` | A Bend list as an array |
| `lab.encode(value)` | A stable key for a Bend value (BigInt-safe) |
| `lab.name(value)` | A constructor's name without its module prefix |
| `lab.explore({ initial, events, step, equal, obligations, holds, node, name? })` | Breadth-first exploration: `{ nodes, edges, laws, events, raw, successors }`, each law with its shortest counterexample |
| `lab.walk(edges, events)` | The steps of a scenario the graph allows, from the start |
| `lab.proofs(complete, obligations, check, progress?)` | The usual proof list: closure, one check per law, one per progress property with `bend` |
| `lab.proofModules(imports, proofs)` | `<id>.bend` and `CHECK-<id>.bend` for each proof |
| `lab.closure.claim()`, `lab.closure.states()` | The closure claim and the proven-closed state list, as Bend text |
| `lab.closure.modules({ imports, type, event, render, explored, step, initial, equal, events, progress? })` | `CLOSURE.bend` (and progress certificates), see "Proofs" |
| `lab.certificate({ imports, type, render, states })` | The older `REACHABLE.bend` list, for a model with its own `complete` |

## `explore`

`model` is the entry module compiled by Bend 2.0.5: its definitions are
functions, constructors are `{ $: 'Name', …fields }`, `Nat` values are BigInts.
Return (what `lab.explore` returns, plus a walkthrough and the generated files):

```js
{
  nodes: [{ id: 1, <field>: <number>, …, safe: true }],  // id = position + 1; node 1 is the start
  edges: [{ from: 1, to: 2, event: 'Name' }],              // at most one edge per (from, event)
  laws: [{ id, label, passed, counterexample: ['Event', …] }], // a counterexample replays from node 1
  events: ['Name', …],                                     // every event, in display order
  walkthrough: ['Event', …],                               // what the play button replays
  generated: { 'CLOSURE.bend': '…' },                      // extra files the proofs import
}
```

Limits: 3000 states and 90000 transitions. Explore breadth-first so each
counterexample is the shortest one.

## Proofs

Each proof is checked on its own as `CHECK-<id>.bend`, which must exist in
`sources`. Model Lab runs `bend CHECK-<id>.bend` and counts it as proved only
when it prints `All terms check.`. A proof states its claim in the CHECK
module itself, so that an empty or weakened proof module cannot pass.

`lab.closure.modules` writes the certificate: every reachable state in a
balanced tree, each with, for every event of the model's `events()`, the path
to its successor. `lab.closure.claim()` checks that the tree holds `initial()`
and that every step from every state lands on the state its path names, so the
JS exploration cannot have missed a state. A wrong, missing or extra witness
makes it false. The per-law claims check `lab.closure.states()`, exactly that
set. The check costs about 0.1 ms per (state, event): 496 states × 30 events
take about 2 s.

## Progress

A law says something about every state. A progress property says something
about the future: from every reachable state, some state where `done(node)`
holds can still be reached (perhaps only through a person's action). Model
Lab computes it over the graph; if it fails, it lists the states that cannot
finish and replays the shortest way into one. With `bend`, a Bool expression
over the state `s`, it is also proved: the certificate gives each state its
distance to a finished state and an event leading one step closer.

```js
const progress = [{ id: 'Finishes', label: 'Every PO can still finish',
    done: node => node.po === 3 || node.po === 4,
    bend: 'match s:\n    case F.State{+p, r, w, o, n, b, t, x, k}: Bool.or(Nat.is_eq(p, 3n), Nat.is_eq(p, 4n))' }];
// in the case: progress, proofs: lab => lab.proofs(…, progress), and
// lab.closure.modules({ …, progress }) in explore. Give it a failure text.
```

## Conformance with the implementation

`compare(graph, design, scenario)` replays the model against the real code and
runs as the last verification step. `graph` is `{ nodes, edges, laws, events }`
with each node's fields. Return `{ status, message?, mismatches? }` where status
is `matched`, `mismatch` or `unavailable` (for example, not built yet); it may
be async, and it runs within the step's time limit (the plugin waits at most
two minutes). For example, run the implementation's test project with the
edges as input and compare each recorded state.

## `view`

```js
view: {
  rows: [{ label: 'PO in ERP Lite', field: 'po', labels: ['Created', 'Sending', 'Ordered'] }],
  details: [{ label: 'worker waiting', field: 'waiting', labels: ['0', '1', '2+'] }],
  architecture: {                       // optional
    width: 890, height: 400, card: { width: 160, height: 64 },
    components: [{ id: 'lite', x: 560, y: 200, title: 'ERP Lite' }, …],
    links: [{ from: 'lite', to: 'worker', label: 'optional' }, …],
  },
}
```

- `rows` draw the state machine: one row per field, with the box for the
  node's value (an index into `labels`) highlighted. Every node must have a
  valid value for every row.
- `details` are fields that are not drawn but are named in the caption when
  they change.
- `architecture` draws the real components. Links are straight lines along the
  axis that separates two boxes most, so place linked boxes on a shared row or
  column and nothing will cross a box.

## `describe(node)`

```js
{ captions: { lite: 'Ordered 01' }, danger: ['supplier'], metrics: [['Label', 'value', 'warning']] }
```

`captions` are the second line of each component; `danger` turns components
red (where a rule is broken); `metrics` are the numbers under the diagrams,
with an optional tone (`default`, `warning`, `danger`, `success`).

## `transition(before, after, event)`

```js
{ hops: ['worker', 'lite'], side: [{ from: 'lite', to: 'outbox', label: '+1' }], note: ' Also queued in the outbox.' }
```

`hops` are the components the step passes through, in order; `side` are side
effects drawn as dotted links; `note` is appended to the step's caption.
Distinct views are sent once, so returning the same object for many edges is cheap.
