// A Markdown summary of a run that an agent can paste into a PR or a plan: the
// verdict, every law with its proof, and each counterexample step by step.
// `runner.mjs report` prints it; the plugin's `report` operation returns the
// same text, which the runner stores with every run.

const MAX_TRACE = 40;

// "PO in ERP Lite: Sending 00 → Ordered 01; …" over the drawn and detail fields.
export function changes(before, after, fields) {
    const parts = [];
    for (const field of fields) {
        const a = before[field.field], b = after[field.field];
        if (a !== undefined && b !== undefined && a !== b) {
            parts.push(`${field.label}: ${field.labels[a] ?? a} → ${field.labels[b] ?? b}`);
        }
    }
    return parts.length === 0 ? 'nothing changes' : parts.join('; ');
}

// Each step of a trace from the start: the event, its label and the state after it.
export function replay(result, trace) {
    const outgoing = new Map(result.edges.map(edge => [`${edge.from} ${edge.event}`, edge.to]));
    const fields = [...result.meta.rows, ...result.meta.details];
    const steps = [];
    let current = 1;
    for (const event of trace) {
        const next = outgoing.get(`${current} ${event}`);
        if (next === undefined) break;
        steps.push({ event, label: result.meta.names[event] ?? event, from: current, to: next,
            changes: changes(result.nodes[current - 1], result.nodes[next - 1], fields) });
        current = next;
    }
    return steps;
}

const escape = text => String(text).replace(/\|/g, '\\|').replace(/\n/g, ' ');

export function verdict(result) {
    const failed = result.laws.filter(law => !law.passed).length;
    if (failed > 0) return `Counterexample found (${failed} of ${result.laws.length} laws broken)`;
    if (result.proof?.status === 'proved') return 'All laws proved';
    if (result.proof) return 'Proof unresolved';
    if (Array.isArray(result.steps) && result.steps.some(step => step.status === 'pending')) return 'Verification not finished';
    return 'Not verified yet: every law holds in the explored graph';
}

export function report(result) {
    const meta = result.meta;
    const proofs = new Map((result.steps ?? []).filter(step => step.kind !== 'prepare').map(step => [step.id, step]));
    const status = step => !step ? '–' : step.status === 'error' ? `error: ${escape(step.message ?? 'failed')}` : step.status;
    const lines = [
        `## Model Lab: ${meta.title}`,
        '',
        `**${meta.design_label}:** ${meta.design} · **${meta.scenario_label}:** ${meta.scenario}`,
        '',
        `**Verdict:** ${verdict(result)}`,
        '',
        `${result.nodes.length} reachable states, ${result.edges.length} transitions · ${result.checker.version} · revision \`${result.revision.slice(0, 12)}\` · ${result.checked_at}`,
        '',
        '| Law | In the explored graph | Proof |',
        '|---|---|---|',
        ...result.laws.map(law => `| ${escape(law.label)} | ${law.passed ? 'holds' : `**broken** in ${law.counterexample.length} steps`} | ${status(proofs.get(law.id))} |`),
    ];
    const others = [...proofs.values()].filter(step => !result.laws.some(law => law.id === step.id));
    if (others.length > 0) {
        lines.push('', '| Other verification step | Result |', '|---|---|',
            ...others.map(step => `| ${escape(step.label)} | ${status(step)}${step.message && step.status !== 'error' ? ` (${escape(step.message)})` : ''} |`));
    }
    for (const law of result.laws.filter(law => !law.passed)) {
        const steps = replay(result, law.counterexample);
        lines.push('', `### ${law.label}`, '', meta.failures[law.id] ?? 'This law breaks.', '');
        if (law.stuck) lines.push(`${law.stuck.length} reachable ${law.stuck.length === 1 ? 'state cannot' : 'states cannot'} finish; the shortest way into one:`, '');
        steps.slice(0, MAX_TRACE).forEach((step, index) => lines.push(`${index + 1}. **${escape(step.label)}**: ${escape(step.changes)}.`));
        if (steps.length > MAX_TRACE) lines.push(`… ${steps.length - MAX_TRACE} more steps.`);
        if (steps.length === 0) lines.push('It breaks in the start state.');
    }
    if (result.scope) lines.push('', `**Scope:** ${result.scope}`);
    lines.push('', `Evidence: \`${result.artifact}\``);
    return lines.join('\n') + '\n';
}
