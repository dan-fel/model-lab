--!strict
-- The plugin's state: the project's cases, one session per case (its design,
-- scenario and position), and moving through the graph: events, Back, Forward,
-- seeking the history and replaying a walkthrough or counterexample.
local graph = require('./graph')

local M = {}
M.VERSION = 9

function M.session(design: string, scenario: string): any
    return {design = design, scenario = scenario, current = 1, trail = jaide.array {},
        playing = false, playback = jaide.array {}, cursor = 1, motion = 0}
end
-- Cases come from the project (.model-lab/cases); the first answer is the catalogue.
function M.initial(): any
    return {case = '', label = '', epoch = 0, expanded = true, sessions = jaide.object {},
        catalog = jaide.array {}, problems = jaide.array {}, pending = 'list'}
end
-- Version 8 said example/examples/policy; the sessions keep their choices.
function M.migrate(old: any, version: number): any
    local state = M.initial()
    if version ~= 8 or type(old) ~= 'table' then return state end
    for id, s in (if type(old.examples) == 'table' then old.examples else {}) do
        if type(s) == 'table' and type(s.policy) == 'string' and type(s.scenario) == 'string' then
            state.sessions[id] = M.session(s.policy, s.scenario)
        end
    end
    if type(old.example) == 'string' then state.case = old.example end
    if type(old.label) == 'string' then state.label = old.label end
    state.expanded = old.expanded ~= false
    return state
end

function M.selected(state: any): any return state.sessions[state.case] end
function M.entry(state: any, id: string): any
    for _, item in state.catalog do if item.id == id then return item end end
    return nil
end
function M.ready(state: any, data: any): boolean
    local s = M.selected(state)
    return s ~= nil and data.format == 4 and data.case == state.case and data.design == s.design and data.scenario == s.scenario
end
-- The model is loaded and nothing is running: the only time a position may change.
function M.idle(state: any, data: any): boolean return M.ready(state, data) and state.pending == nil end
function M.stop(state: any)
    state.epoch += 1
    local s = M.selected(state)
    if s then s.playing = false end
end
function M.reset_session(s: any)
    s.current, s.trail, s.cursor, s.playing, s.playback = 1, jaide.array {}, 1, false, jaide.array {}
    s.transition, s.failure, s.future = nil, nil, jaide.array {}
end
function M.request(state: any, operation: string)
    M.stop(state)
    state.pending = if operation == 'verify' then 'prepare' else operation
    local s = M.selected(state)
    if s then s.error = nil end
end
local function choice(choices: {{string}}, value: string): boolean
    for _, item in choices do if item[1] == value then return true end end
    return false
end
M.choice = choice
-- Switch to a case, keeping its own session (choices and position) if it had one.
function M.choose(state: any, id: string)
    local item = M.entry(state, id)
    assert(item, `Unknown case "{id}". The status operation lists the cases.`)
    if not state.sessions[id] then state.sessions[id] = M.session(item.designs[1][1], item.scenarios[1][1]) end
    M.stop(state)
    state.case, state.label = id, item.label
    M.request(state, 'explore')
end
function M.configure(state: any, arguments: any)
    local item = M.entry(state, arguments.case)
    assert(item, `Unknown case "{arguments.case}". The status operation lists the cases.`)
    assert(choice(item.designs, arguments.design), `Unknown design "{arguments.design}".`)
    assert(choice(item.scenarios, arguments.scenario), `Unknown scenario "{arguments.scenario}".`)
    M.choose(state, arguments.case)
    local s = M.selected(state)
    s.design, s.scenario = arguments.design, arguments.scenario
end

function M.move(s: any, data: any, event: string)
    local to = graph.next(data, s.current, event)
    assert(to, `"{event}" is not possible from state {s.current}.`)
    s.transition = {from = s.current, event = event}
    s.motion += 1
    s.current = to; table.insert(s.trail, event)
end
local function step(s: any, data: any)
    local event = s.playback[s.cursor]
    assert(event, 'Playback must have a next event.')
    M.move(s, data, event)
    s.cursor += 1
    if s.cursor > #s.playback then s.playing = false end
end
M.step = step
-- A position is the events taken from the start; each (state, event) has one edge.
local function replay(s: any, data: any)
    local current = 1
    for _, event in s.trail do
        local found = graph.next(data, current, event)
        assert(found, 'The history must follow the graph.')
        current = found
    end
    s.current = current
end
function M.replaying(s: any): boolean return #s.playback > 0 end
function M.can_back(s: any): boolean return #s.trail > 0 end
function M.can_forward(s: any): boolean
    if M.replaying(s) then return s.cursor <= #s.playback end
    return s.future ~= nil and #s.future > 0
end
function M.back(s: any, data: any)
    assert(M.can_back(s), 'Nothing to go back to.')
    local event = table.remove(s.trail)
    if M.replaying(s) then s.cursor -= 1
    else
        if s.future == nil then s.future = jaide.array {} end
        table.insert(s.future, event)
    end
    replay(s, data)
    -- Going back shows the earlier state without replaying the transition.
    s.transition = nil
    s.motion += 1
end
function M.forward(s: any, data: any)
    assert(M.can_forward(s), 'Nothing to go forward to.')
    if M.replaying(s) then step(s, data) else M.move(s, data, table.remove(s.future)) end
end
-- Steps taken, then the ones Forward would take: the replay's rest, or what Back undid.
function M.history(s: any): {string}
    local steps = table.clone(s.trail)
    if M.replaying(s) then
        for index = s.cursor, #s.playback do table.insert(steps, s.playback[index]) end
    elseif s.future then
        for index = #s.future, 1, -1 do table.insert(steps, s.future[index]) end
    end
    return steps
end
function M.seek(s: any, data: any, target: number)
    assert(type(target) == 'number' and target % 1 == 0 and target >= 0 and target <= #M.history(s),
        `Invalid history step; choose 0 to {#M.history(s)}.`)
    while #s.trail > target and M.can_back(s) do M.back(s, data) end
    while #s.trail < target and M.can_forward(s) do M.forward(s, data) end
end
function M.begin(s: any, events: {string}, failure: string?)
    M.reset_session(s)
    s.playback = table.clone(events)
    s.failure = failure
end
function M.failed_law(data: any, id: string): any
    for _, law in data.laws do
        if law.id == id then
            assert(not law.passed, 'Only broken laws have counterexamples.')
            return law
        end
    end
    error(`Unknown law "{id}".`)
end
-- Take one event from the current state, leaving any replay.
function M.take(state: any, data: any, event: string)
    M.stop(state)
    local s = M.selected(state)
    s.playback, s.cursor = jaide.array {}, 1
    s.failure, s.future = nil, jaide.array {}
    M.move(s, data, event)
end
-- Show a counterexample from the start, stepped to `target` (its end by default).
function M.replay_failure(state: any, data: any, id: string, target: number?)
    local law = M.failed_law(data, id)
    local stop_at = if target == nil then #law.counterexample else target
    assert(type(stop_at) == 'number' and stop_at % 1 == 0 and stop_at >= 0 and stop_at <= #law.counterexample,
        `Invalid trace step; choose 0 to {#law.counterexample}.`)
    M.stop(state)
    local s = M.selected(state)
    M.begin(s, law.counterexample, law.id)
    for _ = 1, stop_at do step(s, data) end
end
-- The Step button: the next event of the walkthrough or counterexample.
function M.walk(state: any, data: any)
    M.stop(state)
    local s = M.selected(state)
    if s.cursor > #s.playback then
        M.begin(s, if s.failure then M.failed_law(data, s.failure).counterexample else data.walkthrough, s.failure)
    end
    if s.cursor <= #s.playback then step(s, data) end
end

-- The first verification step still to run, if a verification is under way.
function M.next_check(data: any): number?
    if type(data.steps) ~= 'table' or data.steps == jaide.null then return nil end
    for index, item in data.steps do if item.status == 'pending' then return index end end
    return nil
end

return M
