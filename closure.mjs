// A closure certificate whose check costs O(n·E·log n) instead of the
// O(n²·E) of a list `contains`.
//
// The candidate set is a binary tree of states (heap layout: the state with
// index k sits at node k, whose children are 2k+1 and 2k+2). Each node also
// carries a witness row: for every event of the model's events() list, in
// order, the path from the root to the node holding the successor. The check
// walks every node, steps its state by every event in events() and compares
// the result with the state found at the witnessed path. Membership is
// therefore by construction: a path can only reach a state of the tree, and a
// path that leads off the tree, or to an unequal state, makes the check False.
// A row with fewer or more paths than events() has entries is False too, so a
// generator cannot skip an event. Self-loops are ordinary witnesses.
//
// So `closed(tree(), start()) == True` means: the set of states stored in the
// tree contains initial() and, for every state in it and every event in
// events(), step(event, state) is equal to a state in it. `states()` lists
// exactly those states, for the per-law checks.

// The path from the root to node k, outermost step first.
function path(k) {
    const steps = [];
    while (k > 0) {
        if (k % 2 === 1) { steps.push('L'); k = (k - 1) / 2; } else { steps.push('R'); k = (k - 2) / 2; }
    }
    return steps.reverse();
}

const pathName = k => `p${k}`;

function pathDef(k) {
    let text = 'Here{}';
    for (const step of path(k).reverse()) text = step === 'L' ? `Left{${text}}` : `Right{${text}}`;
    return `def ${pathName(k)}() -> Path:\n  ${text}\n`;
}

// Successor indices (0-based) for every state and every event, in events()
// order, self-loops included. `key` must agree with the model's equality.
export function successors({ states, events, step, key }) {
    const ids = new Map(states.map((state, i) => [key(state), i]));
    if (ids.size !== states.length) throw new Error('Duplicate states in the closure certificate.');
    return states.map(state => events.map(event => {
        const id = ids.get(key(step(event, state)));
        if (id === undefined) throw new Error('A successor is missing from the state list; exploration is incomplete.');
        return id;
    }));
}

// The claim and the state list depend only on the import alias, so a case can
// state its proofs before exploring.
export const closureClaim = (module = 'Closure') => `${module}.closed(${module}.tree(), ${module}.start())`;
export const closureStates = (module = 'Closure') => `${module}.states()`;
export const progressModule = id => `${id}Progress`;
export const progressClaim = (id, closure = 'Closure') => `${progressModule(id)}.finishes(${progressModule(id)}.tree(), ${closure}.states())`;

// imports:   module header text (must import Base and every module the
//            step/initial/equal/events texts mention)
// type:      the state type, e.g. 'F.State'
// event:     the event type, e.g. 'F.Act'
// render:    state => Bend text of that state
// states:    the states; states[k] is stored at node k
// successors: per state, the successor index for each event in events() order
// step:      (eventVar, stateVar) => Bend text of one step
// initial, equal, events: Bend texts, e.g. 'F.initial()', 'F.equal', 'F.events()'
// start:     index of the initial state (default 0)
// module:    the alias the proofs import CLOSURE.bend as (default 'Closure')
export function closureModules({ imports, type, event, render, states, successors: rows, step, initial, equal, events, start = 0, module = 'Closure' }) {
    if (!states.length || rows.length !== states.length) throw new Error('Expected one successor row per state.');
    const width = rows[0].length;
    for (const row of rows) {
        if (row.length !== width) throw new Error('Every successor row must cover every event.');
        for (const id of row) if (!Number.isInteger(id) || id < 0 || id >= states.length) throw new Error('Successor index out of range.');
    }
    const node = k => {
        if (k >= states.length) return 'Leaf{}';
        const row = `[${rows[k].map(id => `${pathName(id)}()`).join(', ')}]`;
        return `Node{${node(2 * k + 1)},\n  ${render(states[k])}, ${row},\n  ${node(2 * k + 2)}}`;
    };
    const source = `${imports}
# Generated closure certificate; see model-lab/closure.mjs. Only the path defs,
# start() and tree() depend on the exploration; the rest is fixed text.
# A def may only use defs declared above it.

type Path is Data:
  Here{}
  Left{rest: Path}
  Right{rest: Path}

type Tree is Data:
  Leaf{}
  Node{left: Tree, state: ${type}, next: List<&2, Path>, right: Tree}

# True when the node at path exists and holds a state equal to wanted.
def at(tree: Tree, +wanted: ${type}, path: Path) -> Bool:
  match tree:
    case Leaf{}: False{}
    case Node{l, s, n, r}:
      match path:
        case Here{}: ${equal}(s, wanted)
        case Left{p}: at(l, wanted, p)
        case Right{p}: at(r, wanted, p)

# Every event, in events() order, leads from state to the witnessed node;
# a row shorter or longer than events() fails.
def closed_events(events: List<&2, ${event}>, paths: List<&2, Path>, +state: ${type}, +whole: Tree) -> Bool:
  match events:
    case Nil{}:
      match paths:
        case Nil{}: True{}
        case Con{p, ps}: False{}
    case Con{e, es}:
      match paths:
        case Nil{}: False{}
        case Con{p, ps}:
          Bool.and(at(whole, ${step('e', 'state')}, p), closed_events(es, ps, state, whole))

def closed_nodes(tree: Tree, +whole: Tree) -> Bool:
  match tree:
    case Leaf{}: True{}
    case Node{l, s, n, r}:
      Bool.and(closed_events(${events}, n, s, whole), Bool.and(closed_nodes(l, whole), closed_nodes(r, whole)))

# The states of the tree contain initial() and are closed under every event.
def closed(+whole: Tree, start: Path) -> Bool:
  Bool.and(at(whole, ${initial}, start), closed_nodes(whole, whole))

def collect(tree: Tree, rest: List<&2, ${type}>) -> List<&2, ${type}>:
  match tree:
    case Leaf{}: rest
    case Node{l, s, n, r}: Con{s, collect(l, collect(r, rest))}

${states.map((_, k) => pathDef(k)).join('')}
def start() -> Path:
  ${pathName(start)}()

def tree() -> Tree:
  ${node(0)}

# Exactly the states of the tree, for the per-law checks.
def states() -> List<&2, ${type}>:
  collect(tree(), Nil{})
`;
    return { modules: { 'CLOSURE.bend': source }, claim: closureClaim(module), states: closureStates(module) };
}

// Progress: from every state of the closed set some finished state is
// reachable. The certificate ranks each state by its distance to a finished
// one; a finished state needs done(s), any other names an event (by position
// in events()) and the path to its successor, whose rank must be smaller. Its
// states must be exactly the closure's states, in order, so no state is left out.
//   done: Bend text of a Bool expression over the state variable `s`
//   successors: as for closureModules (0-based); finished: per state, done in JS
// Returns { modules: { '<module>.bend': source }, claim }. A state that cannot
// finish gets no valid witness, so the claim is then false, as it should be.
export function progressModules({ imports, type, event, render, states, successors: rows, finished, step, equal, events, done, module, closure = 'Closure' }) {
    const n = states.length;
    const rank = new Array(n).fill(-1), witness = new Array(n).fill(null);
    const incoming = Array.from({ length: n }, () => []);
    rows.forEach((row, from) => row.forEach((to, k) => incoming[to].push([from, k])));
    const queue = [];
    finished.forEach((yes, index) => { if (yes) { rank[index] = 0; queue.push(index); } });
    while (queue.length) {
        const at = queue.shift();
        for (const [from, k] of incoming[at]) {
            if (rank[from] === -1) { rank[from] = rank[at] + 1; witness[from] = [k, at]; queue.push(from); }
        }
    }
    const pick = k => k === 0 ? 'First{}' : `Next{${pick(k - 1)}}`;
    const node = k => {
        if (k >= n) return 'Leaf{}';
        const proof = witness[k] ? `Via{${pick(witness[k][0])}, p${witness[k][1]}()}` : 'Done{}';
        return `Node{${node(2 * k + 1)},\n  ${render(states[k])}, ${Math.max(rank[k], 0)}n, ${proof},\n  ${node(2 * k + 2)}}`;
    };
    const pathDef = k => {
        const steps = [];
        for (let at = k; at > 0; at = at % 2 === 1 ? (at - 1) / 2 : (at - 2) / 2) steps.push(at % 2 === 1 ? 'Left' : 'Right');
        let text = 'Here{}';
        for (const step of steps) text = `${step}{${text}}`;
        return `def p${k}() -> Path:\n  ${text}\n`;
    };
    const source = `${imports}
# Generated progress certificate; see model-lab/closure.mjs.

type Path is Data:
  Here{}
  Left{rest: Path}
  Right{rest: Path}

type Pick is Data:
  First{}
  Next{rest: Pick}

type Witness is Data:
  Done{}
  Via{event: Pick, next: Path}

type Tree is Data:
  Leaf{}
  Node{left: Tree, state: ${type}, rank: Nat, witness: Witness, right: Tree}

def done(s: ${type}) -> Bool:
  ${done}

# The node at path holds a state equal to wanted, with a rank below limit.
def below(tree: Tree, +wanted: ${type}, +limit: Nat, path: Path) -> Bool:
  match tree:
    case Leaf{}: False{}
    case Node{l, s, r, w, rr}:
      match path:
        case Here{}: Bool.and(${equal}(s, wanted), Nat.is_lt(r, limit))
        case Left{p}: below(l, wanted, limit, p)
        case Right{p}: below(rr, wanted, limit, p)

def via(events: List<&2, ${event}>, pick: Pick, +state: ${type}, +limit: Nat, path: Path, +whole: Tree) -> Bool:
  match events:
    case Nil{}: False{}
    case Con{e, es}:
      match pick:
        case First{}: below(whole, ${step('e', 'state')}, limit, path)
        case Next{k}: via(es, k, state, limit, path, whole)

def witnessed(w: Witness, +s: ${type}, +rank: Nat, +whole: Tree) -> Bool:
  match w:
    case Done{}: done(s)
    case Via{k, p}: via(${events}, k, s, rank, p, whole)

def finishes_nodes(tree: Tree, +whole: Tree) -> Bool:
  match tree:
    case Leaf{}: True{}
    case Node{l, s, r, w, rr}:
      Bool.and(witnessed(w, s, r, whole), Bool.and(finishes_nodes(l, whole), finishes_nodes(rr, whole)))

def collect(tree: Tree, rest: List<&2, ${type}>) -> List<&2, ${type}>:
  match tree:
    case Leaf{}: rest
    case Node{l, s, r, w, rr}: Con{s, collect(l, collect(rr, rest))}

def same(a: List<&2, ${type}>, b: List<&2, ${type}>) -> Bool:
  match a:
    case Nil{}:
      match b:
        case Nil{}: True{}
        case Con{y, ys}: False{}
    case Con{x, xs}:
      match b:
        case Nil{}: False{}
        case Con{y, ys}: Bool.and(${equal}(x, y), same(xs, ys))

# Exactly the given states, each able to reach a finished state.
def finishes(+whole: Tree, states: List<&2, ${type}>) -> Bool:
  Bool.and(same(collect(whole, Nil{}), states), finishes_nodes(whole, whole))

${states.map((_, k) => pathDef(k)).join('')}
def tree() -> Tree:
  ${node(0)}
`;
    return { modules: { [`${module}.bend`]: source }, claim: `${module}.finishes(${module}.tree(), ${closure}.states())` };
}
