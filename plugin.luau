--!strict
-- Model Lab: explore a project's Bend state machines, verify their laws one
-- proof at a time and replay any counterexample. This file wires the parts:
--   state.luau       cases, sessions and moving through the graph
--   load.luau        the runner task: catalogue, graphs, pages, verification steps
--   graph.luau       reading the loaded graph; explanations for agents
--   operations.luau  what agents can do through operations/perform
--   views/           the pane
local lab = require('./state')
local load = require('./load')
local operations = require('./operations')
local page = require('./views/page')

-- Where this plugin is installed in the project. A development install under
-- another folder name rewrites this line (scripts/install-dev.sh).
local ROOT = '.jaide/plugins/model-lab'
local RUNNER = ROOT .. '/runner.mjs'

-- Every move needs a loaded model and no running task.
local function idle(handler: (any, any, any) -> ()): (any, any, any) -> ()
    return function(state: any, payload: any, data: any)
        assert(lab.idle(state, data), 'Wait for the model to load.')
        handler(state, payload, data)
    end
end

return jaide.plugin {
    version = lab.VERSION,
    init = lab.initial,
    migrate = function(old: any, version: number, _data: any): any return lab.migrate(old, version) end,
    title = function(state: any) return if state.label ~= '' then 'Model Lab · ' .. state.label else 'Model Lab' end,
    operations = operations,
    watch = function(state: any, data: any)
        local s, watches = lab.selected(state), {}
        if state.pending == 'list' then
            table.insert(watches, jaide.every {key = 'model', seconds = 86400, task = 'read', on = 'received', data = true,
                arguments = {operation = 'list', epoch = state.epoch}})
        elseif state.pending and s then
            local advancing = state.pending == 'advance'
            table.insert(watches, jaide.every {key = 'model', seconds = 86400, task = 'read', on = 'received', data = true,
                arguments = {operation = state.pending, epoch = state.epoch, case = state.case, design = s.design,
                    scenario = s.scenario, revision = if state.pending == 'prepare' then data.revision else '',
                    artifact = if advancing then data.artifact else '',
                    step = if advancing then (lab.next_check(data) :: number) - 1 else 0,
                    timeout = if lab.ready(state, data) and type(data.timeout) == 'number' then data.timeout else 30}})
        end
        if s and s.playing then
            table.insert(watches, jaide.every {key = 'playback', seconds = 1, task = 'pulse', on = 'tick',
                arguments = {epoch = state.epoch, case = state.case}})
        end
        return watches
    end,
    tasks = {
        read = function(arguments: any) return load.read(RUNNER, arguments) end,
        pulse = function(arguments: any) return arguments end,
    },
    on = {
        expand = function(state: any) state.expanded = not state.expanded end,
        toggle_verification = function(state: any) state.verification_open = not state.verification_open end,
        load = function(state: any) lab.request(state, 'explore') end,
        cancel = function(state: any) lab.stop(state); state.pending = nil end,
        check = idle(function(state: any) lab.request(state, 'verify') end),
        received = function(state: any, _payload: any, data: any)
            if data.format == 'catalog' then
                assert(data.epoch == state.epoch, 'Obsolete case list.')
                state.pending = nil
                if data.error then state.problems = jaide.array {data.error}; return end
                state.catalog = data.cases or jaide.array {}
                state.problems = data.problems or jaide.array {}
                if (state.case == '' or not lab.entry(state, state.case)) and #state.catalog > 0 then
                    lab.choose(state, state.catalog[1].id)
                elseif state.case ~= '' then
                    lab.request(state, 'explore')
                end
                return
            end
            assert(data.epoch == state.epoch and data.case == state.case, 'Obsolete model result.')
            if type(data.catalog) == 'table' then state.catalog = data.catalog end
            local s = lab.selected(state)
            if data.error then state.pending = nil; s.error = data.error; return end
            assert(lab.ready(state, data), 'Model settings changed before completion.')
            if s.revision ~= data.revision then lab.reset_session(s) end
            assert(data.nodes[s.current], 'Saved position must belong to the loaded revision.')
            s.revision, s.artifact, s.error = data.revision, data.artifact, nil
            state.pending = if lab.next_check(data) then 'advance' else nil
        end,
        select_case = function(state: any, id: string) lab.choose(state, id) end,
        rescan_cases = function(state: any) lab.request(state, 'list') end,
        design = function(state: any, design: string)
            assert(lab.choice(lab.entry(state, state.case).designs, design)); lab.selected(state).design = design; lab.request(state, 'explore')
        end,
        scenario = function(state: any, scenario: string)
            assert(lab.choice(lab.entry(state, state.case).scenarios, scenario)); lab.selected(state).scenario = scenario; lab.request(state, 'explore')
        end,
        take_event = idle(function(state: any, event: string, data: any) lab.take(state, data, event) end),
        reset = function(state: any) if lab.selected(state) then lab.stop(state); lab.reset_session(lab.selected(state)) end end,
        go_back = idle(function(state: any, _payload: any, data: any) lab.stop(state); lab.back(lab.selected(state), data) end),
        go_forward = idle(function(state: any, _payload: any, data: any) lab.stop(state); lab.forward(lab.selected(state), data) end),
        seek_history = idle(function(state: any, target: number, data: any) lab.stop(state); lab.seek(lab.selected(state), data, target) end),
        play = idle(function(state: any, _payload: any, data: any)
            local s = lab.selected(state)
            local was_playing = s.playing
            lab.stop(state)
            if was_playing then return end
            if s.cursor > #s.playback then
                lab.begin(s, if s.failure then lab.failed_law(data, s.failure).counterexample else data.walkthrough, s.failure)
            end
            s.playing = s.cursor <= #s.playback
        end),
        show_failure = idle(function(state: any, id: string, data: any)
            lab.replay_failure(state, data, id, 0)
            local s = lab.selected(state)
            s.playing = #s.playback > 0
        end),
        seek_failure = idle(function(state: any, payload: any, data: any) lab.replay_failure(state, data, payload.law, payload.step) end),
        tick = function(state: any, payload: any, data: any)
            local s = lab.selected(state)
            if payload.epoch ~= state.epoch or payload.case ~= state.case or not s or not s.playing then return end
            assert(lab.idle(state, data))
            lab.step(s, data)
        end,
        walk = idle(function(state: any, _payload: any, data: any) lab.walk(state, data) end),
    },
    view = page,
}
