// What every case needs and used to copy: Bend value decoding, a breadth-first
// exploration with shortest counterexamples, proof modules and the reachable-set
// certificate. The runner passes this module to a case as `lab`:
//   explore(model, design, scenario, lab) and sources(design, scenario, lab).
// Cases cannot import the plugin by path, because its folder id varies.
import { closureModules, closureClaim, closureStates, progressModules, progressModule, progressClaim } from './closure.mjs';

export const MAX_NODES = 3000;
export const MAX_EDGES = 90000;

// A Bend list ({ $: 'Con', head, tail } … { $: 'Nil' }) as an array.
export function list(value) {
    const result = [];
    while (value && value.$ === 'Con') { result.push(value.head); value = value.tail; }
    if (!value || value.$ !== 'Nil') throw new Error('Bend returned an invalid list.');
    return result;
}

// A stable key for a Bend value; Nat values are BigInts.
export const encode = value => JSON.stringify(value, (_, v) => typeof v === 'bigint' ? Number(v) : v);

// The constructor name of a Bend value, without its module path ('F.Claim' → 'Claim').
export const name = value => String(value.$).split('.').pop();

// Breadth-first exploration: every reachable state, every event from each, and
// the first (shortest) path that breaks each law.
//   initial            the start state (a Bend value)
//   events             the events, in display order (Bend values)
//   step(event, state) the next state
//   equal(a, b)        state equality; a step to an equal state draws no edge
//   obligations        { LawId: 'label' }
//   holds(id, before, after)  whether the law holds over one step
//   node(state)        the fields the plugin draws, as small integers
//   name(event)        the event's name (default: its constructor)
// Returns { nodes, edges, laws, events, raw, successors }: raw are the states as
// Bend values in node order, successors[i][k] the node id that event k leads to
// from node i + 1 (including steps that change nothing).
export function explore({ initial, events, step, equal, obligations, holds, node, name: label = name, limit = MAX_NODES }) {
    const raw = [initial], paths = [[]];
    const ids = new Map([[encode(initial), 1]]);
    const nodes = [], edges = [], successors = [];
    const laws = Object.entries(obligations).map(([id, text]) => ({ id, label: text, passed: true, counterexample: [] }));
    const names = events.map(label);
    for (let index = 0; index < raw.length; index++) {
        if (raw.length > limit) throw new Error(`Model exceeds ${limit} reachable states; exploration is incomplete.`);
        const state = raw[index];
        nodes.push({ id: index + 1, ...node(state) });
        const row = [];
        events.forEach((event, k) => {
            const next = step(event, state);
            let violated = false;
            for (const law of laws) {
                if (!holds(law.id, state, next)) {
                    violated = true;
                    if (law.passed) { law.passed = false; law.counterexample = [...paths[index], names[k]]; }
                }
            }
            if (equal(state, next) && !violated) { row.push(index + 1); return; }
            const key = encode(next);
            let id = ids.get(key);
            if (id === undefined) {
                id = raw.length + 1; ids.set(key, id); raw.push(next); paths.push([...paths[index], names[k]]);
            }
            row.push(id);
            edges.push({ from: index + 1, to: id, event: names[k] });
        });
        successors.push(row);
    }
    return { nodes, edges, laws, events: names, raw, successors };
}

// The steps of a scenario that the graph actually allows, from the start.
export function walk(edges, events) {
    let current = 1;
    return events.filter(event => {
        const edge = edges.find(e => e.from === current && e.event === event);
        if (!edge) return false;
        current = edge.to; return true;
    });
}

// One proof module per claim; CHECK-<id> requires the intended claim, so an
// empty or weakened proof module cannot pass. imports: the lines both modules
// need; a proof may add its own `imports` (a progress proof imports its certificate).
export function proofModules(imports, proofs) {
    const header = imports.endsWith('\n') ? imports : imports + '\n';
    return Object.fromEntries(proofs.flatMap(({ id, claim, imports: own = '' }) => [
        [`${id}.bend`, `${header}${own}\n# Normalization checks the claim over every state of the closed certificate.\ndef holds() -> {${claim} == True{} : Bool}:\n  {==}\n`],
        [`CHECK-${id}.bend`, `${header}${own}import ./${id}.bend as Proof\ndef required() -> {${claim} == True{} : Bool}:\n  Proof.holds()\n`],
    ]));
}

// The usual proof list: the reachable set is closed, then one check per law,
// then one per progress property that gives its Bend `done` test.
//   complete: the closure claim; check(id): the claim that law id holds in every state.
export function proofs(complete, obligations, check, progress = []) {
    return [
        { id: 'ExplorationComplete', label: 'Reachable set contains the start and is closed under every event', claim: complete },
        ...Object.entries(obligations).map(([id, label]) => ({ id, label, claim: check(id) })),
        ...[progress].flat().filter(item => item.bend).map(({ id, label }) => ({ id, label, claim: progressClaim(id),
            imports: `import ./${progressModule(id)}.bend as ${progressModule(id)}\n` })),
    ];
}

// The candidate reachable set as a Bend module (REACHABLE.bend by convention):
//   imports: lines importing the model; type: the state type ('F.State');
//   render(state): the state as a Bend expression; states: explore's raw.
// The ExplorationComplete proof shows independently that it contains the start
// and is closed under every event, so an incomplete list cannot hide a state.
export function certificate({ imports, type, render, states }) {
    const header = imports.endsWith('\n') ? imports : imports + '\n';
    return `import Base\n${header}\n# Generated candidate set; ExplorationComplete independently proves initial membership and closure.\ndef states() -> List<&2, ${type}>:\n  [${states.map(render).join(',\n    ')}]\n`;
}

// The scalable closure certificate (closure.mjs), checked in O(n·E·log n): the
// states in a tree, each with a witness path to its successor under every event.
//   claim(): the ExplorationComplete claim; states(): the proven-closed set, for
//   the per-law checks. Both are fixed text, so proofs can be listed up front.
//   modules({ imports, type, event, render, explored, step, initial, equal, events })
//     imports: lines importing Base and the model (not CLOSURE.bend itself)
//     type, event: the state and event types ('F.State', 'F.Act')
//     render(state): a state as Bend text; explored: what explore() returned
//     step(e, s): Bend text of one step of the event variable e from state s
//     initial, equal, events: Bend texts ('F.initial()', 'F.equal', 'F.events()'),
//     where events() lists the events in the order explore() was given them.
//     progress: the case's progress properties; each with `bend` (a Bool
//     expression over the state `s`) also gets its certificate, <Id>Progress.bend.
// Returns { 'CLOSURE.bend': source, … }; proofs import it as Closure.
export const closure = {
    claim: (module = 'Closure') => closureClaim(module),
    states: (module = 'Closure') => closureStates(module),
    modules({ explored, module = 'Closure', progress = [], ...rest }) {
        const successors = explored.successors.map(row => row.map(id => id - 1));
        const modules = closureModules({ ...rest, module, states: explored.raw, successors }).modules;
        for (const item of [progress].flat().filter(entry => entry.bend)) {
            Object.assign(modules, progressModules({ ...rest, states: explored.raw, successors, done: item.bend,
                finished: explored.nodes.map(node => Boolean(item.done(node))), module: progressModule(item.id), closure: module }).modules);
        }
        return modules;
    },
};
