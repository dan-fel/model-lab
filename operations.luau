--!strict
-- What agents can do through `operations`/`perform`: load a case, verify it,
-- move through its graph and read what they find. Moves answer with `explain`.
local lab = require('./state')
local graph = require('./graph')

local function object(properties: any, required: {string}?): any
    return {type = 'object', additionalProperties = false, properties = properties or jaide.object {},
        required = if required then required else nil}
end
local none = object(nil)
local text = {type = 'string'}
local explained = {type = 'object', description = 'The position after the move, as the explain operation returns it.'}

local function loaded(state: any, data: any)
    assert(lab.ready(state, data), 'No model is loaded. Use configure (or reload), then wait until status shows pending = null.')
    assert(state.pending == nil, `Model Lab is busy ({state.pending}); wait until status shows pending = null.`)
end
local function moved(handler: (any, any, any) -> ()): (any, any, any) -> any
    return function(state: any, arguments: any, data: any): any
        loaded(state, data)
        handler(state, arguments, data)
        return graph.explain(state, data)
    end
end
local function strip(steps: any): any
    if type(steps) ~= 'table' or steps == jaide.null then return jaide.null end
    local result = {}
    for _, step in steps do
        table.insert(result, {id = step.id, label = step.label, kind = step.kind, status = step.status,
            message = step.message or jaide.null, seconds = step.seconds or jaide.null})
    end
    return result
end

return {
    reload = jaide.operation {
        description = 'Load the selected case and its reachable graph again.', effect = 'keep',
        arguments = none, result = text,
        handler = function(state: any) lab.request(state, 'explore'); return 'Model load requested; status shows pending = null when it is loaded.' end,
    },
    configure = jaide.operation {
        description = 'Select a case (its id under .model-lab/cases) with a design and scenario id, and load it. The status operation lists the cases and their choices.',
        effect = 'keep',
        arguments = object({case = text, design = text, scenario = text}, {'case', 'design', 'scenario'}), result = text,
        handler = function(state: any, arguments: any) lab.configure(state, arguments); return 'Model load requested; status shows pending = null when it is loaded.' end,
    },
    rescan = jaide.operation {
        description = 'Read the project\'s .model-lab/cases again.', effect = 'keep',
        arguments = none, result = text,
        handler = function(state: any) lab.request(state, 'list'); return 'Case list requested.' end,
    },
    verify = jaide.operation {
        description = 'Verify the loaded model revision, one proof at a time. Poll status until pending = null, then read report.',
        effect = 'keep', arguments = none, result = text,
        handler = function(state: any, _arguments: any, data: any)
            loaded(state, data); lab.request(state, 'verify'); return 'Verification requested.'
        end,
    },
    status = jaide.operation {
        description = 'Read the project\'s cases with their designs and scenarios, the selected case, whether a model is loaded or a task is pending, and the latest verification.',
        effect = 'observe', arguments = none, result = {type = 'object'},
        handler = function(state: any, _arguments: any, data: any)
            local loaded_now = lab.ready(state, data)
            local s = lab.selected(state)
            local laws = {}
            if loaded_now then
                for _, law in data.laws do
                    table.insert(laws, {id = law.id, label = law.label, kind = law.kind or 'invariant', passed = law.passed,
                        steps = #law.counterexample})
                end
            end
            return {cases = state.catalog, problems = state.problems, case = state.case,
                design = if s then s.design else jaide.null, scenario = if s then s.scenario else jaide.null,
                pending = state.pending or jaide.null, loaded = loaded_now, error = if s and s.error then s.error else jaide.null,
                revision = if loaded_now then data.revision else jaide.null,
                states = if loaded_now then #data.nodes else jaide.null,
                walkthrough = if loaded_now then data.walkthrough else jaide.array {},
                proof = if loaded_now then data.proof else jaide.null, laws = laws,
                steps = if loaded_now then strip(data.steps) else jaide.null,
                case_problems = if loaded_now and type(data.problems) == 'table' then data.problems else jaide.array {},
                artifact = if loaded_now then data.artifact else jaide.null}
        end,
    },
    explain = jaide.operation {
        description = 'The current state as text: each row\'s value, the metrics, the possible next events with their names, and what the last step changed.',
        effect = 'observe', arguments = none, result = explained,
        handler = function(state: any, _arguments: any, data: any) loaded(state, data); return graph.explain(state, data) end,
    },
    step = jaide.operation {
        description = 'Take one event (its id, as explain lists under possible) from the current state.', effect = 'keep',
        arguments = object({event = text}, {'event'}), result = explained,
        handler = moved(function(state: any, arguments: any, data: any) lab.take(state, data, arguments.event) end),
    },
    back = jaide.operation {
        description = 'Go back one step.', effect = 'keep', arguments = none, result = explained,
        handler = moved(function(state: any, _arguments: any, data: any) lab.stop(state); lab.back(lab.selected(state), data) end),
    },
    forward = jaide.operation {
        description = 'Go forward one step: the next step of a replay, or one that back undid.', effect = 'keep',
        arguments = none, result = explained,
        handler = moved(function(state: any, _arguments: any, data: any) lab.stop(state); lab.forward(lab.selected(state), data) end),
    },
    seek = jaide.operation {
        description = 'Move to a step of the history (0 is the start).', effect = 'keep',
        arguments = object({step = {type = 'integer', minimum = 0}}, {'step'}), result = explained,
        handler = moved(function(state: any, arguments: any, data: any) lab.stop(state); lab.seek(lab.selected(state), data, arguments.step) end),
    },
    replay = jaide.operation {
        description = 'Replay a broken law\'s counterexample from the start, to its last step or to step (0 is the start).',
        effect = 'keep', arguments = object({law = text, step = {type = 'integer', minimum = 0}}, {'law'}), result = explained,
        handler = moved(function(state: any, arguments: any, data: any) lab.replay_failure(state, data, arguments.law, arguments.step) end),
    },
    reset = jaide.operation {
        description = 'Go back to the start state and forget the history.', effect = 'keep', arguments = none, result = explained,
        handler = moved(function(state: any) lab.stop(state); lab.reset_session(lab.selected(state)) end),
    },
    counterexamples = jaide.operation {
        description = 'Each broken law with its failure text and its trace as event names, with what each step changed and the state after it.',
        effect = 'observe', arguments = none, result = {type = 'array'},
        handler = function(state: any, _arguments: any, data: any)
            loaded(state, data)
            local result = graph.counterexamples(data)
            return if #result == 0 then jaide.array {} else result
        end,
    },
    report = jaide.operation {
        description = 'A Markdown summary of the latest verification (laws, proof results, counterexamples) to paste into a PR or plan. The terminal equivalent is `bun <plugin>/runner.mjs report <case> <design> <scenario>`.',
        effect = 'observe', arguments = none, result = text,
        handler = function(state: any, _arguments: any, data: any) loaded(state, data); return data.report end,
    },
}
