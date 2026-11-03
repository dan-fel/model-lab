// Checks a case and its explored graph, reporting each mistake as one readable
// line that names the file and field. Used by `runner.mjs check-case`, by every
// load (so a broken graph fails with a reason rather than late in the pane),
// and by the catalogue (static checks only), which the pane shows by the tab.

const isText = value => typeof value === 'string' && value.length > 0;
const pairs = value => Array.isArray(value) && value.length > 0
    && value.every(item => Array.isArray(item) && item.length === 2 && isText(item[0]) && isText(item[1]));
const plural = (n, one, many = one + 's') => `${n} ${n === 1 ? one : many}`;

// What can be checked without running the model.
export function checkDefinition(definition, file) {
    const problems = [];
    const say = (field, text) => problems.push(`${file}: ${field}: ${text}`);
    for (const key of ['label', 'title']) if (!isText(definition[key])) say(key, 'must be a non-empty string.');
    if (!pairs(definition.designs)) say('designs (or policies)', 'must be a non-empty list of [id, label] pairs.');
    if (!pairs(definition.scenarios)) say('scenarios', 'must be a non-empty list of [id, label] pairs.');
    if (!definition.names || typeof definition.names !== 'object') say('names', 'must map every event to a label.');
    if (definition.failures !== undefined && typeof definition.failures !== 'object') say('failures', 'must map law ids to failure texts.');
    if (typeof definition.sources !== 'function') say('sources', 'must be a function (design, scenario, lab) returning { file: text }.');
    if (typeof definition.explore !== 'function') say('explore', 'must be a function (model, design, scenario, lab).');
    if (!isText(definition.entry)) say('entry', 'must name the Bend file that explore receives.');
    if (definition.timeout !== undefined && !(Number.isFinite(definition.timeout) && definition.timeout >= 1 && definition.timeout <= 110)) {
        say('timeout', 'must be a number of seconds from 1 to 110.');
    }
    if (definition.compare !== undefined && typeof definition.compare !== 'function') say('compare', 'must be a function (graph, design, scenario).');
    const proofs = definition.proofs;
    if (!Array.isArray(proofs) || proofs.length === 0) say('proofs', 'must list at least one { id, label, claim }.');
    else {
        const seen = new Set();
        proofs.forEach((proof, index) => {
            if (!isText(proof?.id) || !/^[A-Za-z0-9_-]+$/.test(proof.id)) say(`proofs[${index}].id`, 'must be letters, digits, _ or -.');
            else if (seen.has(proof.id)) say(`proofs[${index}].id`, `"${proof.id}" is used twice.`);
            else seen.add(proof.id);
            if (!isText(proof?.label)) say(`proofs[${index}].label`, 'must be a non-empty string.');
        });
        if (proofs.length > 14) say('proofs', `at most 14 proofs fit one verification (found ${proofs.length}).`);
    }
    const progress = definition.progress === undefined ? [] : [definition.progress].flat();
    progress.forEach((item, index) => {
        if (!isText(item?.id) || !isText(item?.label) || typeof item?.done !== 'function') {
            say(`progress[${index}]`, 'must be { id, label, done(node) }.');
        }
    });
    const view = definition.view;
    if (!view || !Array.isArray(view.rows) || view.rows.length === 0) say('view.rows', 'must list at least one { label, field, labels }.');
    for (const [group, items] of [['view.rows', view?.rows], ['view.details', view?.details]]) {
        if (items === undefined && group === 'view.details') continue;
        if (!Array.isArray(items)) { if (group === 'view.details') say(group, 'must be a list.'); continue; }
        items.forEach((row, index) => {
            const where = `${group}[${index}]${isText(row?.label) ? ` ("${row.label}")` : ''}`;
            if (!isText(row?.label)) say(where, 'needs a label.');
            if (!isText(row?.field)) say(where, 'needs the node field it draws.');
            if (!Array.isArray(row?.labels) || row.labels.length === 0 || !row.labels.every(isText)) say(where, 'labels must be a non-empty list of strings.');
        });
    }
    const architecture = view?.architecture;
    if (architecture) {
        const ids = new Set();
        (architecture.components ?? []).forEach((component, index) => {
            if (!isText(component?.id) || !Number.isFinite(component?.x) || !Number.isFinite(component?.y) || !isText(component?.title)) {
                say(`view.architecture.components[${index}]`, 'must be { id, x, y, title }.');
            } else ids.add(component.id);
        });
        if (!Array.isArray(architecture.components) || ids.size === 0) say('view.architecture.components', 'must list at least one component.');
        (architecture.links ?? []).forEach((link, index) => {
            for (const end of ['from', 'to']) {
                if (!ids.has(link?.[end])) say(`view.architecture.links[${index}].${end}`, `"${link?.[end]}" is not a component id.`);
            }
        });
    }
    return problems;
}

// What needs the explored graph: values in range, ids that exist, coverage.
// graph has nodes and edges with their `view` objects (describe/transition).
// Returns every problem; `fatal` are those the pane cannot draw or replay.
export function checkGraph(definition, file, graph, sources) {
    const problems = [], fatal = [];
    const say = (field, text, stop = false) => {
        const line = `${file}: ${field}: ${text}`;
        problems.push(line);
        if (stop) fatal.push(line);
    };
    const nodes = graph.nodes ?? [], edges = graph.edges ?? [];
    nodes.forEach((node, index) => { if (node?.id !== index + 1) say('explore', `node ${index + 1} has id ${node?.id}; ids must be positions from 1.`, true); });
    for (const [group, items] of [['view.rows', definition.view?.rows ?? []], ['view.details', definition.view?.details ?? []]]) {
        items.forEach((row, index) => {
            if (!Array.isArray(row?.labels)) return;
            const bad = nodes.filter(node => {
                const value = node[row.field];
                return !Number.isInteger(value) || value < 0 || value >= row.labels.length;
            });
            if (bad.length > 0) {
                const first = bad[0];
                say(`${group}[${index}] ("${row.label}")`, `state ${first.id} has ${row.field} = ${JSON.stringify(first[row.field])}, `
                    + `outside 0–${row.labels.length - 1} (${plural(bad.length, 'state')} affected).`, group === 'view.rows');
            }
        });
    }
    const names = definition.names ?? {};
    const events = new Set([...(graph.events ?? []), ...edges.map(edge => edge.event)]);
    const unnamed = [...events].filter(event => !isText(names[event]));
    if (unnamed.length > 0) say('names', `no label for ${unnamed.map(e => `"${e}"`).join(', ')}.`, true);
    const outgoing = new Map();
    for (const edge of edges) {
        if (!nodes[edge.from - 1] || !nodes[edge.to - 1]) { say('explore', `edge ${edge.from} → ${edge.to} (${edge.event}) leaves the graph.`, true); continue; }
        const key = `${edge.from} ${edge.event}`;
        if (outgoing.has(key)) say('explore', `state ${edge.from} has two "${edge.event}" transitions; each (state, event) needs one.`, true);
        outgoing.set(key, edge.to);
    }
    const follows = trace => {
        let current = 1;
        for (const [index, event] of trace.entries()) {
            const next = outgoing.get(`${current} ${event}`);
            if (next === undefined) return `step ${index + 1} ("${event}") is not possible from state ${current}`;
            current = next;
        }
        return null;
    };
    const failures = definition.failures ?? {};
    for (const law of graph.laws ?? []) {
        if (!isText(law?.id) || !isText(law?.label) || typeof law?.passed !== 'boolean' || !Array.isArray(law?.counterexample)) {
            say('explore laws', 'each law must be { id, label, passed, counterexample }.', true); continue;
        }
        if (!isText(failures[law.id])) say('failures', `law "${law.id}" has no failure text.`);
        if (!law.passed) {
            const broken = follows(law.counterexample);
            if (broken) say(`law "${law.id}" counterexample`, `${broken}.`, true);
        }
    }
    if (!(graph.laws ?? []).length) say('explore', 'returned no laws.', true);
    const walkthrough = graph.walkthrough ?? [];
    const broken = follows(walkthrough);
    if (broken) say('walkthrough', `${broken}.`, true);
    const architecture = definition.view?.architecture;
    if (architecture) {
        const ids = new Set((architecture.components ?? []).map(component => component.id));
        const unknown = (where, values) => {
            const missing = [...new Set(values)].filter(id => !ids.has(id));
            if (missing.length > 0) say(where, `${missing.map(id => `"${id}"`).join(', ')} ${missing.length === 1 ? 'is not a component id' : 'are not component ids'}.`);
        };
        unknown('describe captions', nodes.flatMap(node => Object.keys(node.view?.captions ?? {})));
        unknown('describe danger', nodes.flatMap(node => node.view?.danger ?? []));
        unknown('transition hops', edges.flatMap(edge => edge.view?.hops ?? []));
        unknown('transition side', edges.flatMap(edge => (edge.view?.side ?? []).flatMap(link => [link.from, link.to])));
    }
    const metrics = nodes.find(node => node.view?.metrics !== undefined && !(Array.isArray(node.view.metrics)
        && node.view.metrics.every(metric => Array.isArray(metric) && metric.length >= 2 && typeof metric[1] === 'string')));
    if (metrics) say('describe metrics', `state ${metrics.id}: each metric must be [label, value text, tone?].`);
    if (sources) {
        if (!(definition.entry in sources)) say('entry', `"${definition.entry}" is not among sources().`);
        for (const proof of definition.proofs ?? []) {
            if (!(`CHECK-${proof.id}.bend` in sources)) say(`proofs "${proof.id}"`, `sources() has no CHECK-${proof.id}.bend.`);
        }
    }
    return { problems, fatal };
}
