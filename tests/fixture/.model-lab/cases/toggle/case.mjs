// The smallest useful case: one law, two designs, one of which breaks it.
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
    proofs(lab) { return lab.proofs(lab.closure.claim(), obligations, id => `T.check(T.${id}{}, ${lab.closure.states()})`, this.progress ?? []); },
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
                type: 'T.State', event: 'T.Act', render: s => `T.State{${Number(s.on)}n, ${Number(s.flips)}n}`, explored: graph, progress: this.progress ?? [],
                step: (e, s) => `T.step(Config.policy(), ${e}, ${s})`, initial: 'T.initial()', equal: 'T.equal', events: 'T.events()' }) };
    },
    view: {
        rows: [{ label: 'Switch', field: 'on', labels: ['Off', 'On', 'Jammed'] }, { label: 'Flips', field: 'flips', labels: ['0', '1', '2+'] }],
        architecture: { width: 400, height: 120, components: [{ id: 'switch', x: 100, y: 60, title: 'Switch' }, { id: 'lamp', x: 300, y: 60, title: 'Lamp' }],
            links: [{ from: 'switch', to: 'lamp' }] },
    },
    describe: node => ({ captions: { switch: ['off', 'on', 'jammed'][node.on], lamp: node.on === 1 ? 'lit' : 'dark' },
        danger: node.on === 2 ? ['switch'] : [], metrics: [['Flips', String(node.flips)]] }),
    transition: (before, after, event) => ({ hops: event === 'Flip' ? ['switch', 'lamp'] : ['switch'] }),
};
