// Runs the real runner and Bend checker against the fixture project.
import { test, expect } from 'bun:test';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { encode } from '../wire.mjs';

const runner = path.resolve(import.meta.dirname, '../runner.mjs');
const CASE = '.model-lab/cases/toggle/case.mjs';

function project() {
    const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'model-lab-test-'));
    fs.cpSync(path.join(import.meta.dirname, 'fixture'), directory, { recursive: true });
    return directory;
}
function spawn(cwd, ...args) {
    return spawnSync(process.execPath, [runner, ...args], { cwd, encoding: 'utf8', timeout: 120000 });
}
function run(cwd, ...args) {
    const result = spawn(cwd, ...args);
    if (result.status !== 0) throw new Error(result.stderr);
    return JSON.parse(result.stdout);
}
// Edit the fixture case in place: each pair replaces one exact piece of text.
function edit(cwd, ...pairs) {
    const file = path.join(cwd, CASE);
    let source = fs.readFileSync(file, 'utf8');
    for (let index = 0; index < pairs.length; index += 2) {
        if (!source.includes(pairs[index])) throw new Error(`Fixture has no ${pairs[index]}`);
        source = source.replace(pairs[index], pairs[index + 1]);
    }
    fs.writeFileSync(file, source);
}
// The graph as the plugin rebuilds it from the wire format (inline or paged).
function graph(result) {
    let { parts = [], nodes = [], edge_views = [], edges = [] } = result.graph;
    for (let number = 1; nodes.length === 0 && number <= result.graph.pages; number++) {
        const chunk = JSON.parse(fs.readFileSync(path.join(result.artifact, 'pages', `${number}.json`), 'utf8'));
        parts = parts.concat(chunk.parts); nodes = nodes.concat(chunk.nodes);
        edge_views = edge_views.concat(chunk.edge_views); edges = edges.concat(chunk.edges);
        if (number === result.graph.pages) break;
    }
    const { fields, view_keys, events } = result.graph;
    return {
        nodes: nodes.map((row, index) => ({ id: index + 1, ...Object.fromEntries(fields.map((field, k) => [field, row[k]])),
            view: Object.fromEntries(view_keys.flatMap((key, k) => row[fields.length + k] ? [[key, parts[row[fields.length + k] - 1]]] : [])) })),
        edges: edges.map(([from, to, event, view]) => ({ from, to, event: events[event - 1], view: edge_views[view - 1] })),
    };
}

test('discovers cases in the project and in its folders', () => {
    const cwd = project();
    fs.cpSync(path.join(cwd, '.model-lab'), path.join(cwd, 'service', '.model-lab'), { recursive: true });
    const { cases, problems } = run(cwd, 'list');
    expect(problems).toEqual([]);
    expect(cases.map(c => c.id)).toEqual(['toggle', 'service/toggle']);
    expect(cases[0].designs).toEqual([['safe', 'Safe'], ['broken', 'Broken']]);
    expect(cases[0].problems).toEqual([]);
});

test('reports a case that fails to load without hiding the others', () => {
    const cwd = project();
    fs.mkdirSync(path.join(cwd, '.model-lab/cases/broken'));
    fs.writeFileSync(path.join(cwd, '.model-lab/cases/broken/case.mjs'), 'export default { label: "x" };');
    const { cases, problems } = run(cwd, 'list');
    expect(cases.map(c => c.id)).toEqual(['toggle']);
    expect(problems[0]).toContain('broken');
});

test('the safe design proves every law, with view data on every node and edge', () => {
    const cwd = project();
    const result = run(cwd, 'verify', 'toggle', 'safe', 'default');
    expect(result).toMatchObject({ format: 4, case: 'toggle', design: 'safe', scenario: 'default' });
    expect(result.proof.status).toBe('proved');
    expect(result.steps.slice(1).map(s => s.status)).toEqual(['proved', 'proved']);
    expect(result.meta.rows[0].field).toBe('on');
    const { nodes, edges } = graph(result);
    expect(nodes.length).toBe(result.graph.counts.nodes);
    expect(nodes.every(n => Array.isArray(n.view.metrics))).toBe(true);
    expect(edges.every(e => Array.isArray(e.view.hops))).toBe(true);
    expect(result.catalog.map(c => c.id)).toEqual(['toggle']);
    expect(result.report).toContain('**Verdict:** All laws proved');
    expect(fs.readFileSync(path.join(result.artifact, 'report.md'), 'utf8')).toBe(result.report);
});

test('the broken design fails its law with the shortest counterexample', () => {
    const result = run(project(), 'verify', 'toggle', 'broken', 'default');
    expect(result.proof.status).toBe('unresolved');
    expect(result.laws[0]).toMatchObject({ passed: false, counterexample: ['Jam'] });
});

test('a changed model is refused before verification', () => {
    const cwd = project();
    const loaded = run(cwd, 'explore', 'toggle', 'safe', 'default');
    fs.appendFileSync(path.join(cwd, '.model-lab/cases/toggle/Toggle.bend'), '\n# changed\n');
    expect(() => run(cwd, 'prepare', 'toggle', 'safe', 'default', loaded.revision)).toThrow('changed since it was loaded');
});

test('prepare and advance answer without the graph; its pages are written once', () => {
    const cwd = project();
    const loaded = run(cwd, 'explore', 'toggle', 'safe', 'default');
    expect(loaded.graph.nodes.length).toBe(loaded.graph.counts.nodes);
    const prepared = run(cwd, 'prepare', 'toggle', 'safe', 'default', loaded.revision);
    expect(prepared.graph.nodes).toBeUndefined();
    expect(prepared.graph.pages).toBe(1);
    const advanced = run(cwd, 'advance', prepared.artifact, '1');
    expect(advanced.graph.nodes).toBeUndefined();
    expect(advanced.steps[1].status).toBe('proved');
    expect(graph(advanced).edges.length).toBe(loaded.graph.counts.edges);
});

test('large graphs share repeated views and split into pages', () => {
    const view = { hops: ['a', 'b', 'c'], note: 'The same long note on every edge. '.repeat(4) };
    const nodes = Array.from({ length: 600 }, (_, index) => ({ id: index + 1, x: index % 3, safe: true,
        view: { captions: { a: `state ${index % 7}` }, metrics: [['Count', String(index % 3)]] } }));
    const edges = nodes.flatMap(node => ['Up', 'Down', 'Left', 'Right'].map((event, k) => ({ from: node.id, to: (node.id + k) % 600 + 1, event, view })));
    const encoded = encode({ nodes, edges, events: ['Up', 'Down', 'Left', 'Right'] });
    expect(encoded.edge_views.length).toBe(1);
    expect(encoded.parts.length).toBe(7 + 3);
    expect(JSON.stringify(edges).length).toBeGreaterThan(10 * JSON.stringify(encoded.edges).length);
    expect(encoded.pages).toBe(encoded.chunks.length);
    expect(encoded.chunks.every(chunk => JSON.stringify(chunk).length < 40000)).toBe(true);
    expect(encoded.chunks.flatMap(chunk => chunk.edges)).toEqual(encoded.edges);
});

test('report prints the latest verification as Markdown, verifying when there is none', () => {
    const cwd = project();
    const first = spawn(cwd, 'report', 'toggle', 'broken', 'default');
    expect(first.status).toBe(0);
    expect(first.stdout).toContain('**Verdict:** Counterexample found');
    expect(first.stdout).toContain('### The switch is on or off');
    expect(first.stdout).toContain('1. **Jam**: Switch: Off → Jammed.');
    expect(first.stdout).toContain('| The switch is on or off | **broken** in 1 steps | unresolved |');
    const runs = fs.readdirSync(path.join(cwd, '.jaide/model-lab/runs')).length;
    expect(spawn(cwd, 'report', 'toggle', 'broken', 'default').stdout).toBe(first.stdout);
    expect(fs.readdirSync(path.join(cwd, '.jaide/model-lab/runs')).length).toBe(runs);
});

test('check-case reports each kind of mistake on one line', () => {
    const clean = spawn(project(), 'check-case', 'toggle');
    expect(clean.status).toBe(0);
    expect(clean.stdout).toBe('toggle: no problems found.\n');
    const cwd = project();
    edit(cwd,
        "labels: ['Off', 'On', 'Jammed'] }", "labels: ['Off', 'On'] }",                       // a row value out of range
        "lamp: node.on === 1", "bulb: node.on === 1",                                            // an unknown component in describe
        "['switch', 'lamp'] : ['switch']", "['switch', 'lamp'] : ['switch', 'relay']",           // a hop to an unknown component
        "names: { Flip: 'Flip', Jam: 'Jam' }", "names: { Flip: 'Flip' }",                         // an event without a name
        "failures: { OnIsBinary: 'The switch is neither on nor off.' }", 'failures: {}',          // a law without a failure text
        '...lab.proofModules(imports, this.proofs),', '...lab.proofModules(imports, this.proofs.slice(1)),'); // a missing CHECK module
    const result = spawn(cwd, 'check-case', 'toggle', 'broken', 'default');
    expect(result.status).toBe(1);
    const lines = result.stdout.trim().split('\n');
    const expected = [
        'view.rows[0] ("Switch"): state 3 has on = 2, outside 0–1 (3 states affected).',
        'describe captions: "bulb" is not a component id.',
        'transition hops: "relay" is not a component id.',
        'names: no label for "Jam".',
        'failures: law "OnIsBinary" has no failure text.',
        'proofs "ExplorationComplete": sources() has no CHECK-ExplorationComplete.bend.',
    ];
    for (const text of expected) expect(lines.filter(line => line.endsWith(text)).length).toBe(1);
    expect(lines.length).toBe(expected.length);
    expect(lines.every(line => line.startsWith('.model-lab/cases/toggle/case.mjs: '))).toBe(true);
    // The same problems stop a load with their reasons instead of a vague error.
    expect(spawn(cwd, 'explore', 'toggle', 'broken', 'default').stderr).toContain('names: no label for "Jam".');
});

test('progress laws report the states that cannot finish, and Bend proves them over the closed set', () => {
    const cwd = project();
    edit(cwd, '    entry:', "    progress: { id: 'TurnsOff', label: 'The switch can always be turned off', done: node => node.on === 0,\n"
        + "        bend: 'match s:\\n    case T.State{+o, f}: Nat.is_eq(o, 0n)' },\n    entry:",
        "failures: { OnIsBinary: 'The switch is neither on nor off.' }",
        "failures: { OnIsBinary: 'The switch is neither on nor off.', TurnsOff: 'The switch can no longer be turned off.' }");
    const safe = run(cwd, 'verify', 'toggle', 'safe', 'default');
    expect(safe.laws.find(law => law.id === 'TurnsOff')).toMatchObject({ kind: 'progress', passed: true, stuck: [] });
    expect(safe.steps.find(step => step.id === 'TurnsOff').status).toBe('proved');
    expect(safe.proof.status).toBe('proved');
    // Flips saturate at two, so after the first Flip the switch never gets back to (off, 0 flips).
    edit(cwd, 'done: node => node.on === 0', 'done: node => node.on === 0 && node.flips === 0',
        'Nat.is_eq(o, 0n)', 'Bool.and(Nat.is_eq(o, 0n), Nat.is_eq(f, 0n))', 'T.State{+o, f}', 'T.State{+o, +f}');
    const stuck = run(cwd, 'verify', 'toggle', 'safe', 'default');
    const law = stuck.laws.find(item => item.id === 'TurnsOff');
    expect(law.passed).toBe(false);
    expect(law.counterexample).toEqual(['Flip']);
    expect(law.stuck_count).toBeGreaterThan(0);
    const step = stuck.steps.find(item => item.id === 'TurnsOff');
    expect(step.status).toBe('unresolved');
    expect(step.output.stderr).not.toContain('consumed');
    expect(stuck.report).toContain('cannot finish');
});

test('a case can compare its implementation as the last verification step', () => {
    const cwd = project();
    edit(cwd, '    entry:', "    compare: graph => graph.edges.every(edge => edge.view.hops.length > 0)\n"
        + "        ? { status: 'matched', message: `${graph.edges.length} transitions replayed` } : { status: 'mismatch' },\n    entry:");
    const result = run(cwd, 'verify', 'toggle', 'safe', 'default');
    expect(result.steps.at(-1)).toMatchObject({ id: 'conformance', kind: 'compare', status: 'matched' });
    expect(result.proof.status).toBe('proved');
    expect(result.report).toContain('| Implementation matches the model | matched (');
});

test('cases written with policies and policyLabel still load', () => {
    const cwd = project();
    edit(cwd, "designs: [['safe', 'Safe'], ['broken', 'Broken']]", "policies: [['safe', 'Safe'], ['broken', 'Broken']], policyLabel: 'Variant'");
    const { cases } = run(cwd, 'list');
    expect(cases[0]).toMatchObject({ designs: [['safe', 'Safe'], ['broken', 'Broken']], design_label: 'Variant' });
    expect(run(cwd, 'explore', 'toggle', 'broken', 'default').laws[0].passed).toBe(false);
});
