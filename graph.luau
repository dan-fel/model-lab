--!strict
-- Reading the loaded graph (bulk data, decoded by load.luau): the next state
-- for an event, a state's or a step's view, and the explanations the agent
-- operations return.
local render = require('./render')

local M = {}

function M.next(data: any, from: number, event: string): number?
    local out = data.out[from]
    local index = out and out[event]
    return if index then data.edges[index].to else nil
end
function M.edge(data: any, from: number, event: string): any
    local out = data.out[from]
    local index = out and out[event]
    return if index then data.edges[index] else nil
end
-- A state's captions, danger and metrics; the runner sends each distinct part once.
function M.node_view(data: any, node: any): any
    local view = {}
    for k, key in data.view_keys do
        local ref = node.refs[k]
        if ref and ref > 0 then view[key] = data.parts[ref] end
    end
    return view
end
function M.edge_view(data: any, edge: any): any
    return if edge then data.edge_views[edge.v] else nil
end
-- The events possible from a state, in the case's own order.
function M.possible(data: any, from: number): {string}
    local out, names, result = data.out[from] or {}, data.meta.names, {}
    for _, event in data.events do
        if out[event] and names[event] then table.insert(result, event) end
    end
    return result
end
function M.fields(meta: any): {any}
    local fields = table.clone(meta.rows)
    for _, detail in meta.details do table.insert(fields, detail) end
    return fields
end
-- "PUT: stored · 201/200: PO in ERP Lite: Not stored → Created 00." plus the case's note.
function M.caption(data: any, from: number, event: string): string
    local before, edge = data.nodes[from], M.edge(data, from, event)
    local after = data.nodes[edge.to]
    local view = M.edge_view(data, edge)
    return `{data.meta.names[event] or event}: {render.changes(before, after, M.fields(data.meta))}{if view and view.note then view.note else ''}`
end
-- Each field's value label in one state.
function M.values(data: any, node: any, rows: {any}): {any}
    local result = jaide.array {}
    for _, row in rows do
        local value = node[row.field]
        table.insert(result, {label = row.label, value = row.labels[(value or 0) + 1] or tostring(value)})
    end
    return result
end

local function law_label(data: any, id: string): string
    for _, law in data.laws do if law.id == id then return law.label end end
    return id
end

-- The current position as text and as fields, for agents.
function M.explain(state: any, data: any): any
    local s = state.sessions[state.case]
    local node = data.nodes[s.current]
    local view = M.node_view(data, node)
    local names = data.meta.names
    local trail = jaide.array {}
    for _, event in s.trail do table.insert(trail, names[event] or event) end
    local possible = jaide.array {}
    for _, event in M.possible(data, s.current) do table.insert(possible, {event = event, label = names[event]}) end
    local metrics = jaide.array {}
    for _, metric in (if type(view.metrics) == 'table' then view.metrics else {}) do
        table.insert(metrics, {label = metric[1], value = metric[2]})
    end
    local last = if s.transition then M.caption(data, s.transition.from, s.transition.event) else jaide.null
    local replay = jaide.null
    if #s.playback > 0 then
        replay = {law = if s.failure then s.failure else jaide.null, step = s.cursor - 1, of = #s.playback,
            label = if s.failure then law_label(data, s.failure) else data.meta.walkthrough_label}
    end
    local rows, details = M.values(data, node, data.meta.rows), M.values(data, node, data.meta.details)
    local lines = {`State {s.current} of {#data.nodes}, after {#trail} step{if #trail == 1 then '' else 's'}`
        .. (if replay ~= jaide.null then ` (replaying "{replay.label}", step {replay.step} of {replay.of})` else '')
        .. (if node.safe == false then ' · a law is broken in this state' else '')}
    if last ~= jaide.null then table.insert(lines, 'Last step: ' .. last) end
    for _, item in rows do table.insert(lines, `{item.label}: {item.value}`) end
    for _, item in details do table.insert(lines, `{item.label}: {item.value}`) end
    if #metrics > 0 then
        local parts = {}
        for _, metric in metrics do table.insert(parts, `{metric.label} {metric.value}`) end
        table.insert(lines, 'Metrics: ' .. table.concat(parts, '; '))
    end
    local options = {}
    for _, item in possible do table.insert(options, `{item.event} ({item.label})`) end
    table.insert(lines, if #options > 0 then 'Possible next events: ' .. table.concat(options, ', ') else 'No event is possible from here.')
    return {text = table.concat(lines, '\n'), case = state.case, design = s.design, scenario = s.scenario,
        state = s.current, states = #data.nodes, step = #trail, trail = trail, safe = node.safe ~= false,
        rows = rows, details = details, metrics = metrics, possible = possible, last = last, replay = replay}
end

-- Every broken law with its failure text and its trace as event names, with the
-- state after each step.
function M.counterexamples(data: any): {any}
    local result = jaide.array {}
    for _, law in data.laws do
        if not law.passed then
            local steps, current = jaide.array {}, 1
            for index, event in law.counterexample do
                local caption = M.caption(data, current, event)
                current = M.next(data, current, event) :: number
                table.insert(steps, {step = index, event = event, label = data.meta.names[event] or event, caption = caption,
                    state = current, values = M.values(data, data.nodes[current], data.meta.rows)})
            end
            table.insert(result, {id = law.id, label = law.label, kind = law.kind or 'invariant',
                failure = data.meta.failures[law.id] or law.label, events = law.counterexample, steps = steps,
                stuck = if law.stuck_count then law.stuck_count else jaide.null})
        end
    end
    return result
end

return M
