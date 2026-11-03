// How a graph travels to the plugin. Jaide's run_process reads at most 48 KiB
// of stdout, and the same few notes and routes repeat on thousands of edges, so:
//   nodes      [value of each of `fields`…, part index of each of `view_keys`…]
//   parts      distinct node view members (captions, danger, metrics), indexed from 1
//   edges      [from, to, event index into `events`, index into `edge_views`]
//   edge_views distinct transition views, indexed from 1
// A graph that does not fit one answer is split into pages under the run
// directory (pages/<n>.json, each { parts, nodes, edge_views, edges } in order),
// written once per run.
import fs from 'node:fs';
import path from 'node:path';

export const PAGE_BYTES = 40000;

function interner() {
    const values = [], index = new Map();
    const add = value => {
        const key = JSON.stringify(value);
        let found = index.get(key);
        if (found === undefined) { values.push(value); found = values.length; index.set(key, found); }
        return found;
    };
    return { values, add };
}

export function encode(result) {
    const fields = [], view_keys = [];
    for (const node of result.nodes) {
        for (const key of Object.keys(node)) if (key !== 'id' && key !== 'view' && !fields.includes(key)) fields.push(key);
        for (const key of Object.keys(node.view ?? {})) if (!view_keys.includes(key)) view_keys.push(key);
    }
    const parts = interner(), views = interner();
    const nodes = result.nodes.map(node => [
        ...fields.map(field => node[field] ?? false),
        ...view_keys.map(key => node.view?.[key] === undefined ? 0 : parts.add(node.view[key])),
    ]);
    const events = [...result.events];
    for (const edge of result.edges) if (!events.includes(edge.event)) events.push(edge.event);
    const position = new Map(events.map((event, index) => [event, index + 1]));
    const edges = result.edges.map(edge => [edge.from, edge.to, position.get(edge.event), views.add(edge.view ?? {})]);
    const chunks = [];
    let chunk = { parts: [], nodes: [], edge_views: [], edges: [] }, size = 0;
    for (const [field, items] of [['parts', parts.values], ['nodes', nodes], ['edge_views', views.values], ['edges', edges]]) {
        for (const item of items) {
            const length = JSON.stringify(item).length + 1;
            if (size + length > PAGE_BYTES - 200 && size > 0) {
                chunks.push(chunk); chunk = { parts: [], nodes: [], edge_views: [], edges: [] }; size = 0;
            }
            chunk[field].push(item); size += length;
        }
    }
    chunks.push(chunk);
    return { fields, view_keys, events, parts: parts.values, nodes, edge_views: views.values, edges, chunks, pages: chunks.length };
}

// Write the run's pages once; a later step of the same run reuses them.
export function pages(result) {
    const directory = path.join(result.artifact, 'pages');
    if (fs.existsSync(directory)) return;
    const { chunks } = encode(result);
    const temporary = directory + '.next';
    fs.mkdirSync(temporary, { recursive: true });
    chunks.forEach((chunk, index) => fs.writeFileSync(path.join(temporary, `${index + 1}.json`), JSON.stringify(chunk)));
    fs.renameSync(temporary, directory);
}
