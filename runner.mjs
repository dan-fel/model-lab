// Model Lab's runner. It discovers the project's verification cases, explores
// a case's reachable graph, and runs each proof as its own step against frozen
// inputs. Run from the project root (the plugin's working folder).
//
//   bun runner.mjs list
//   bun runner.mjs explore|verify <case> <design> <scenario>
//   bun runner.mjs report <case> <design> <scenario> [--fresh]   Markdown of the latest verification
//   bun runner.mjs check-case <case> [<design> <scenario>]       every problem in a case, one per line
//   bun runner.mjs prepare <case> <design> <scenario> <revision> (the plugin's verification steps)
//   bun runner.mjs advance <run directory> <step>
//   bun runner.mjs page <run directory> <n>
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import { pathToFileURL } from 'node:url';
import { digest, run } from './checker.mjs';
import * as lab from './lab.mjs';
import { checkDefinition, checkGraph } from './check.mjs';
import { report } from './report.mjs';
import { encode, pages, PAGE_BYTES } from './wire.mjs';

const RUNS = '.jaide/model-lab/runs';
const FORMAT = 4;
const DEFAULT_TIMEOUT = 30;

// ---- Discovery ----------------------------------------------------------------

const isDirectory = file => { try { return fs.statSync(file).isDirectory(); } catch { return false; } };

// Cases live in .model-lab/cases/<id>/case.mjs of the project, or of a folder one
// level down (a space with several repositories side by side).
function caseFiles() {
    const roots = ['.'];
    for (const entry of fs.readdirSync('.', { withFileTypes: true })) {
        if (!entry.name.startsWith('.') && entry.name !== 'node_modules' && isDirectory(entry.name)) roots.push(entry.name);
    }
    const found = [];
    for (const root of roots) {
        const directory = path.join(root, '.model-lab', 'cases');
        if (!isDirectory(directory)) continue;
        for (const name of fs.readdirSync(directory)) {
            const file = path.join(directory, name, 'case.mjs');
            if (fs.existsSync(file)) found.push({ id: name, file: path.resolve(file), root });
        }
    }
    return found.sort((a, b) => a.id.localeCompare(b.id) || a.root.localeCompare(b.root));
}

const REQUIRED = ['label', 'title', 'scenarios', 'names', 'entry', 'sources', 'proofs', 'explore', 'view'];

// A case as the runner uses it. `designs`/`designLabel` were first called
// `policies`/`policyLabel`; both spellings work.
async function load(file) {
    const module = await import(pathToFileURL(file).href);
    const definition = module.default;
    if (!definition || typeof definition !== 'object') throw new Error(`${file} has no default export.`);
    const missing = REQUIRED.filter(key => definition[key] === undefined);
    if (definition.designs === undefined && definition.policies === undefined) missing.unshift('designs');
    if (missing.length) throw new Error(`${file} is missing ${missing.join(', ')}.`);
    const proofs = typeof definition.proofs === 'function' ? definition.proofs(lab) : definition.proofs;
    return { ...definition, proofs, designs: definition.designs ?? definition.policies,
        designLabel: definition.designLabel ?? definition.policyLabel ?? 'Design',
        scenarioLabel: definition.scenarioLabel ?? 'Scenario' };
}

const relative = file => path.relative(process.cwd(), file);

function summary(id, definition, file) {
    return { id, label: definition.label, title: definition.title, intro: definition.intro ?? '',
        design_label: definition.designLabel, scenario_label: definition.scenarioLabel,
        designs: definition.designs, scenarios: definition.scenarios,
        problems: checkDefinition(definition, relative(file)) };
}

export async function catalog() {
    const cases = [], problems = [];
    const seen = new Set();
    for (const { id, file, root } of caseFiles()) {
        const key = seen.has(id) ? `${root}/${id}` : id;
        seen.add(key);
        try { cases.push(summary(key, await load(file), file)); }
        catch (error) { problems.push(`${key}: ${error.message}`); }
    }
    return { cases, problems };
}

async function resolve(id) {
    const entries = caseFiles();
    const seen = new Set();
    for (const entry of entries) {
        const key = seen.has(entry.id) ? `${entry.root}/${entry.id}` : entry.id;
        seen.add(key);
        if (key === id) return { ...entry, definition: await load(entry.file) };
    }
    throw new Error(`No case "${id}" in .model-lab/cases.`);
}

const label = (choices, value) => choices.find(([id]) => id === value)?.[1] ?? value;

// ---- Exploring ----------------------------------------------------------------

function save(result) {
    const file = path.join(result.artifact, 'result.json');
    const temporary = file + '.next';
    result.report = report(result);
    fs.writeFileSync(temporary, JSON.stringify(result));
    fs.renameSync(temporary, file);
    fs.writeFileSync(path.join(result.artifact, 'report.md'), result.report);
    return result;
}

function checkerPaths() {
    const root = fs.realpathSync(process.env.MODEL_LAB_BEND ?? path.join(os.homedir(), '.bend/current'));
    return { root, entry: path.join(root, 'bend2/main.ts') };
}

// The case describes every state and transition for the plugin's diagrams.
function annotate(definition, graph) {
    const describe = definition.describe ?? (() => ({}));
    const transition = definition.transition ?? (() => ({}));
    for (const node of graph.nodes) node.view = describe(node) ?? {};
    for (const edge of graph.edges) {
        edge.view = transition(graph.nodes[edge.from - 1], graph.nodes[edge.to - 1], edge.event) ?? {};
    }
}

// Progress: from every reachable state some finished state is reachable. A
// failure replays the shortest path into a state that can no longer finish.
function progress(definition, graph) {
    const items = definition.progress === undefined ? [] : [definition.progress].flat();
    return items.map(({ id, label: text, done }) => {
        const n = graph.nodes.length;
        const finishes = graph.nodes.map(node => Boolean(done(node)));
        const incoming = Array.from({ length: n + 1 }, () => []);
        for (const edge of graph.edges) incoming[edge.to].push(edge.from);
        const queue = graph.nodes.filter((_, index) => finishes[index]).map(node => node.id);
        while (queue.length) {
            for (const from of incoming[queue.shift()]) {
                if (!finishes[from - 1]) { finishes[from - 1] = true; queue.push(from); }
            }
        }
        const stuck = graph.nodes.filter((_, index) => !finishes[index]).map(node => node.id);
        let counterexample = [];
        if (stuck.length > 0) {
            const parent = new Map([[1, null]]);
            const order = [1];
            for (let index = 0; index < order.length; index++) {
                const at = order[index];
                if (!finishes[at - 1]) {
                    for (let step = parent.get(at); step; step = parent.get(step.from)) counterexample.unshift(step.event);
                    break;
                }
                for (const edge of graph.edges) {
                    if (edge.from === at && !parent.has(edge.to)) { parent.set(edge.to, edge); order.push(edge.to); }
                }
            }
        }
        return { id, label: text, kind: 'progress', passed: stuck.length === 0, counterexample, stuck: stuck.slice(0, 500) };
    });
}

function meta(definition, design, scenario) {
    return { title: definition.title, names: definition.names, failures: definition.failures ?? {}, rows: definition.view.rows,
        details: definition.view.details ?? [], architecture: definition.view.architecture ?? null,
        walkthrough_label: definition.walkthroughLabel ?? 'Play scenario',
        design_label: definition.designLabel, scenario_label: definition.scenarioLabel,
        design: label(definition.designs, design), scenario: label(definition.scenarios, scenario) };
}

// Load a case and explore one design × scenario. Returns the graph, the sources
// and every problem check.mjs finds; throws only when nothing can be explored.
async function explore(found, design, scenario) {
    const definition = found.definition;
    if (!definition.designs.some(([value]) => value === design) || !definition.scenarios.some(([value]) => value === scenario)) {
        throw new Error(`Unknown ${found.id} design or scenario.`);
    }
    const checker = checkerPaths();
    const version = run(process.execPath, [checker.entry, '--version'], os.tmpdir());
    if (version.exit_code !== 0 || version.stdout.trim() !== 'bend 2.0.5') {
        throw new Error(`Model Lab requires Bend 2.0.5; found ${version.stdout.trim() || version.stderr}.`);
    }
    const sources = definition.sources(design, scenario, lab);
    const caseSource = fs.readFileSync(found.file, 'utf8');
    // The case's own code shapes the graph, so it is part of the revision.
    const revision = digest(JSON.stringify({ id: found.id, sources, case: caseSource }));
    const snapshot = fs.mkdtempSync(path.join(os.tmpdir(), 'model-lab-'));
    try {
        for (const [name, source] of Object.entries(sources)) fs.writeFileSync(path.join(snapshot, name), source);
        await import(pathToFileURL(checker.entry).href);
        if (!(definition.entry in sources)) throw new Error(`${relative(found.file)}: entry: "${definition.entry}" is not among sources().`);
        const model = (await import(pathToFileURL(path.join(snapshot, definition.entry)).href)).default;
        const { generated = {}, raw: _raw, successors: _successors, ...graph } = definition.explore(model, design, scenario, lab);
        if (!Array.isArray(graph.nodes) || graph.nodes.length === 0 || graph.nodes.length > lab.MAX_NODES
            || !Array.isArray(graph.edges) || graph.edges.length > lab.MAX_EDGES) {
            throw new Error(`${relative(found.file)}: explore: the graph must have 1–${lab.MAX_NODES} states and at most ${lab.MAX_EDGES} transitions.`);
        }
        graph.laws = [...(graph.laws ?? []), ...progress(definition, graph)];
        annotate(definition, graph);
        const all = { ...sources, ...generated };
        const checks = checkGraph(definition, relative(found.file), graph, all);
        return { definition, graph, sources: all, generated, revision, version: version.stdout.trim(), checker,
            case_sha256: digest(caseSource), problems: [...checkDefinition(definition, relative(found.file)), ...checks.problems],
            fatal: checks.fatal };
    } finally { fs.rmSync(snapshot, { recursive: true, force: true }); }
}

export async function prepare(operation, id, design, scenario, expected = '') {
    if (!['explore', 'verify'].includes(operation)) throw new Error('Expected explore or verify.');
    const found = await resolve(id);
    const explored = await explore(found, design, scenario);
    const { definition, graph, sources, generated, revision, checker } = explored;
    if (expected && revision !== expected) throw new Error('The model changed since it was loaded. Reload before verifying.');
    if (explored.fatal.length > 0) throw new Error(explored.fatal.join('\n'));
    const directory = path.resolve(RUNS, crypto.randomUUID());
    fs.mkdirSync(directory, { recursive: true });
    for (const [name, source] of Object.entries(sources)) fs.writeFileSync(path.join(directory, name), source);
    const steps = operation === 'verify' ? [
        { id: 'snapshot', kind: 'prepare', label: 'Freeze model and enumerate reachable states', status: 'complete' },
        ...definition.proofs.map(({ id: proof, label: text }) => ({ id: proof, label: text, kind: 'proof', status: 'pending' })),
        ...(definition.compare ? [{ id: 'conformance', kind: 'compare', label: definition.compareLabel ?? 'Implementation matches the model', status: 'pending' }] : []),
    ] : null;
    const result = save({ format: FORMAT, operation, case: id, design, scenario, revision,
        checker: { version: explored.version, entry_sha256: digest(fs.readFileSync(checker.entry)), root: checker.root },
        case_file: found.file, case_sha256: explored.case_sha256,
        generated_sha256: digest(JSON.stringify(generated)), scope: definition.scope ?? '',
        timeout: definition.timeout ?? DEFAULT_TIMEOUT, problems: explored.problems,
        source_sha256: Object.fromEntries(Object.entries(sources).map(([name, source]) => [name, digest(source)])),
        meta: meta(definition, design, scenario), walkthrough: graph.walkthrough ?? [], events: graph.events ?? [],
        ...graph, steps, proof: null, checked_at: new Date().toISOString(), artifact: directory });
    pages(result);
    return result;
}

// ---- Verifying ----------------------------------------------------------------

function proofStep(result, step, directory) {
    const checker = path.join(result.checker.root, 'bend2/main.ts');
    if (digest(fs.readFileSync(checker)) !== result.checker.entry_sha256) throw new Error('The checker changed during verification. Start a new check.');
    const sources = Object.fromEntries(Object.entries(result.source_sha256).map(([name, sha256]) => {
        const bytes = fs.readFileSync(path.join(directory, name));
        if (digest(bytes) !== sha256) throw new Error('Frozen verification inputs changed. Start a new check.');
        return [name, bytes];
    }));
    // Check the exact bytes whose digests were just validated, even if the saved
    // evidence is edited while the checker runs.
    const snapshot = fs.mkdtempSync(path.join(os.tmpdir(), 'model-lab-step-'));
    try {
        for (const [name, bytes] of Object.entries(sources)) {
            const file = path.join(snapshot, name);
            fs.mkdirSync(path.dirname(file), { recursive: true });
            fs.writeFileSync(file, bytes);
        }
        const started = Date.now();
        try {
            step.output = run(process.execPath, [checker, path.join(snapshot, `CHECK-${step.id}.bend`)], snapshot, undefined, result.timeout * 1000);
            step.status = step.output.exit_code === 0 && step.output.stdout.trim() === 'All terms check.' ? 'proved' : 'unresolved';
        } catch (error) {
            step.status = 'error';
            step.message = error.code === 'ETIMEDOUT' ? `Timed out after ${result.timeout} s (the case's timeout).` : error.message;
        }
        step.seconds = Math.round((Date.now() - started) / 100) / 10;
    } finally { fs.rmSync(snapshot, { recursive: true, force: true }); }
}

// Conformance: the case replays the model's graph against its real code.
async function compareStep(result, step) {
    const found = await resolve(result.case);
    if (found.file !== result.case_file || digest(fs.readFileSync(found.file, 'utf8')) !== result.case_sha256) {
        step.status = 'stale'; step.message = 'The case changed since this run was prepared.'; return;
    }
    try {
        const outcome = await found.definition.compare({ nodes: result.nodes, edges: result.edges, laws: result.laws, events: result.events },
            result.design, result.scenario) ?? {};
        step.status = ['matched', 'mismatch', 'unavailable'].includes(outcome.status) ? outcome.status : 'error';
        if (outcome.message) step.message = String(outcome.message);
        if (Array.isArray(outcome.mismatches)) step.mismatches = outcome.mismatches.slice(0, 50);
    } catch (error) { step.status = 'error'; step.message = error.message; }
}

// An accepted receipt is the only cursor. Repeating an already completed step
// returns it; a caller cannot skip ahead or accidentally launch the next proof.
export async function advance(directory, index) {
    const runs = path.resolve(RUNS);
    if (path.dirname(directory) !== runs || !/^[0-9a-f-]{36}$/.test(path.basename(directory))) {
        throw new Error('Expected an evidence run in this project.');
    }
    const result = JSON.parse(fs.readFileSync(path.join(directory, 'result.json'), 'utf8'));
    if (result.artifact !== directory || result.operation !== 'verify' || !Array.isArray(result.steps)
        || !Number.isInteger(index) || index < 1 || index >= result.steps.length) {
        throw new Error('Invalid verification step.');
    }
    if (result.steps[index].status !== 'pending') return result;
    if (result.steps.findIndex(step => step.status === 'pending') !== index) throw new Error('Verification steps must run in order.');
    const step = result.steps[index];
    if (step.kind === 'proof') proofStep(result, step, directory);
    else if (step.kind === 'compare') await compareStep(result, step);
    else throw new Error('Unknown verification step.');
    const proofs = result.steps.filter(item => item.kind === 'proof');
    if (result.steps.every(item => item.status !== 'pending')) {
        const proved = proofs.every(item => item.status === 'proved');
        if (proved && result.laws.some(law => !law.passed && law.kind !== 'progress')) throw new Error('Checker and executable model disagree.');
        result.proof = { status: proved ? 'proved' : 'unresolved' };
    }
    result.checked_at = new Date().toISOString();
    return save(result);
}

export async function execute(operation, ...arguments_) {
    let result = await prepare(operation, ...arguments_);
    if (operation === 'verify') {
        for (let index = 1; index < result.steps.length; index++) result = await advance(result.artifact, index);
    }
    return result;
}

// ---- Reports and checks ---------------------------------------------------------

function runs() {
    const directory = path.resolve(RUNS);
    if (!isDirectory(directory)) return [];
    return fs.readdirSync(directory).flatMap(name => {
        try { return [JSON.parse(fs.readFileSync(path.join(directory, name, 'result.json'), 'utf8'))]; } catch { return []; }
    });
}

// The latest finished verification of the current revision; a new one when
// there is none (or when asked for a fresh one).
export async function latestReport(id, design, scenario, fresh = false) {
    if (!fresh) {
        const found = await resolve(id);
        const current = (await explore(found, design, scenario)).revision;
        const finished = runs().filter(result => result.format === FORMAT && result.operation === 'verify' && result.case === id
            && result.design === design && result.scenario === scenario && result.revision === current && result.proof)
            .sort((a, b) => b.checked_at.localeCompare(a.checked_at));
        if (finished.length > 0) return report(finished[0]);
    }
    return (await execute('verify', id, design, scenario)).report;
}

// Every problem in a case, each on one line. Explores the first design and
// scenario unless others are given.
export async function checkCase(id, design, scenario) {
    let found;
    try { found = await resolve(id); } catch (error) { return [error.message]; }
    const definition = found.definition;
    const problems = checkDefinition(definition, relative(found.file));
    if (problems.some(line => /: (designs|scenarios)/.test(line))) return problems;
    try {
        const explored = await explore(found, design ?? definition.designs[0][0], scenario ?? definition.scenarios[0][0]);
        return [...new Set([...problems, ...explored.problems])];
    } catch (error) { return [...problems, ...error.message.split('\n')]; }
}

// ---- Output -------------------------------------------------------------------

// Jaide's run_process reads at most 48 KiB of stdout. The graph goes inline when
// it fits; otherwise the answer names its pages, written once per run.
function answer(result, inline) {
    const graph = encode(result);
    const { nodes: _n, edges: _e, ...rest } = result;
    if (Array.isArray(rest.steps)) {
        rest.steps = rest.steps.map(step => step.output ? { ...step, output: {
            exit_code: step.output.exit_code, stdout: step.output.stdout.slice(0, 1500), stderr: step.output.stderr.slice(0, 1500) } } : step);
    }
    rest.laws = rest.laws.map(law => law.stuck ? { ...law, stuck: law.stuck.slice(0, 50), stuck_count: law.stuck.length } : law);
    const header = { fields: graph.fields, view_keys: graph.view_keys, events: graph.events,
        counts: { nodes: result.nodes.length, edges: result.edges.length }, pages: graph.pages };
    const full = { ...rest, graph: { ...header, parts: graph.parts, nodes: graph.nodes, edge_views: graph.edge_views, edges: graph.edges } };
    if (inline && JSON.stringify(full).length <= PAGE_BYTES) return full;
    return { ...rest, graph: header };
}

function page(artifact, number) {
    const root = fs.realpathSync(path.resolve(RUNS));
    const directory = fs.realpathSync(artifact);
    if (path.dirname(directory) !== root || !/^[1-9][0-9]*$/.test(number)) throw new Error('Unknown page.');
    return JSON.parse(fs.readFileSync(path.join(directory, 'pages', `${number}.json`), 'utf8'));
}

if (import.meta.main) {
    const [operation, ...args] = process.argv.slice(2);
    try {
        if (operation === 'report') {
            const fresh = args.includes('--fresh');
            const [id, design, scenario] = args.filter(arg => arg !== '--fresh');
            if (!scenario) throw new Error('Usage: runner.mjs report <case> <design> <scenario> [--fresh]');
            process.stdout.write(await latestReport(id, design, scenario, fresh));
        } else if (operation === 'check-case') {
            if (!args[0]) throw new Error('Usage: runner.mjs check-case <case> [<design> <scenario>]');
            const problems = await checkCase(...args);
            process.stdout.write(problems.length === 0 ? `${args[0]}: no problems found.\n` : problems.join('\n') + '\n');
            if (problems.length > 0) process.exitCode = 1;
        } else {
            let result;
            if (operation === 'list') result = { format: 'catalog', ...(await catalog()) };
            else if (operation === 'page') result = page(args[0], args[1]);
            else {
                // The plugin already holds the graph of a run it is verifying, so
                // prepare and advance answer without it; it reads pages on a miss.
                const inline = !['prepare', 'advance'].includes(operation);
                const output = operation === 'prepare' ? await prepare('verify', ...args)
                    : operation === 'advance' ? await advance(args[0], Number(args[1]))
                    : ['explore', 'verify'].includes(operation) ? await execute(operation, ...args)
                    : (() => { throw new Error(`Unknown command "${operation}".`); })();
                result = answer(output, inline);
                // Every model answer carries the catalogue, so the tabs survive a reload.
                result.catalog = (await catalog()).cases;
            }
            process.stdout.write(JSON.stringify(result));
        }
    } catch (error) { process.stderr.write(`${error.message}\n`); process.exitCode = 1; }
}
