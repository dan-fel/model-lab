--!strict
-- The whole pane: the case tabs, the case's heading and choices, verification
-- progress, a found counterexample, then the explorer beside the evidence.
local ui = require('@jaide/ui')
local lab = require('../state')
local verification = require('./verification')
local explorer = require('./explorer')
local evidence = require('./evidence')

local function captions(texts: {string}): {any}
    local items = {}
    for index, text in texts do table.insert(items, ui.text {key = index, class = 'caption', tone = 'warning', text = text}) end
    return items
end

local function empty(busy: boolean, problems: {string}): any
    return ui.page {key = 'model-lab', class = 'lab', children = {
        ui.column {key = 'empty-stage', class = 'stage empty-stage',
            ui.text {key = 'title', class = 'empty-title', text = if busy then 'Reading this project\'s cases…' else 'No verification cases yet'},
            ui.text {key = 'description', class = 'muted', text = if busy then 'Looking in .model-lab/cases.'
                else 'Model Lab checks Bend models that the project describes. Add a case as .model-lab/cases/<id>/case.mjs, in the project or in one of its folders, then rescan. The plugin\'s docs/CASES.md describes the format.'},
            ui.column {key = 'problems', class = 'problems', children = captions(problems)},
            ui.button {key = 'rescan', label = 'Rescan cases', action = ui.event('rescan_cases'), disabled = busy},
        },
    }}
end

return function(state: any, data: any): any
    local s, item = lab.selected(state), lab.entry(state, state.case)
    local available, busy = lab.ready(state, data), state.pending ~= nil
    if item == nil or s == nil then return empty(busy, state.problems) end
    -- Project problems, then the selected case's: its catalogue checks, or the
    -- loaded run's (check.mjs), each naming the file and field.
    local problems = table.clone(state.problems)
    local own = if available and type(data.problems) == 'table' then data.problems
        elseif type(item.problems) == 'table' then item.problems else {}
    for _, text in own do table.insert(problems, text) end
    local switches = {}
    for _, case in state.catalog do
        local flagged = type(case.problems) == 'table' and #case.problems > 0
        table.insert(switches, ui.button {key = case.id, label = case.label .. (if flagged then ' ⚠' else ''),
            class = if state.case == case.id then 'selected' else nil, action = ui.event('select_case', case.id)})
    end
    table.insert(switches, ui.button {key = 'rescan', class = 'rescan', label = 'Rescan', action = ui.event('rescan_cases'), disabled = busy})
    local content = {
        ui.row {key = 'examples', class = 'tabs', children = switches},
        ui.column {key = 'problems', class = 'problems', children = captions(problems)},
        ui.row {key = 'heading', class = 'heading',
            ui.column {key = 'intro', class = 'intro',
                ui.text {key = 'title', class = 'title', text = item.title},
                ui.text {key = 'description', class = 'muted', text = item.intro},
            },
            ui.row {key = 'actions', class = 'actions',
                ui.button {key = 'reload', label = 'Reload', action = ui.event('load'), disabled = busy or not available},
                ui.button {key = 'verify', class = 'primary',
                    label = if busy then 'Cancel' elseif available then 'Verify' else 'Load model',
                    action = ui.event(if busy then 'cancel' elseif available then 'check' else 'load')},
            },
        },
    }
    local settings = {}
    for _, group in {{'design', item.design_label, item.designs}, {'scenario', item.scenario_label, item.scenarios}} do
        local buttons = {}
        for _, option in group[3] do
            table.insert(buttons, ui.button {key = option[1], class = if s[group[1]] == option[1] then 'selected' else nil,
                label = option[2], action = ui.event(group[1], option[1])})
        end
        -- Keys stay 'policy'/'scenario' so the rendered tree is unchanged.
        table.insert(settings, ui.column {key = if group[1] == 'design' then 'policy' else 'scenario', class = 'setting',
            ui.text {key = 'label', class = 'caption', text = group[2]},
            ui.row {key = 'choices', class = 'segments', children = buttons},
        })
    end
    table.insert(content, ui.row {key = 'settings', class = 'settings', children = settings})
    if s.error then table.insert(content, ui.text {key = 'error', class = 'error', tone = 'danger', text = s.error}) end
    if state.pending == 'prepare' or (available and type(data.steps) == 'table' and data.steps ~= jaide.null) then
        table.insert(content, verification(state, data))
    end
    if available then
        local failure = explorer.failure(s, data)
        local failures = if type(data.meta.failures) == 'table' then data.meta.failures else {}
        if failure then table.insert(content, explorer.banner(failure, failures, busy, s.playing)) end
        table.insert(content, ui.column {key = 'workspace', class = 'workspace',
            explorer.stage(state, data, failure, busy), evidence(data, busy),
        })
    else
        table.insert(content, ui.column {key = 'empty-stage', class = 'stage empty-stage',
            ui.text {key = 'title', class = 'empty-title', text = if busy then 'Preparing the state machine…' else 'Explore what happens next.'},
            ui.text {key = 'description', class = 'muted', text = if busy then 'Bend is deriving the reachable states.'
                else 'Load the model, play a scenario, then verify its laws.'},
        })
    end
    return ui.page {key = 'model-lab', class = 'lab', children = content}
end
