--!strict
-- Below the diagrams: the clickable history of this exploration, and the trace
-- of the counterexample being shown.
local ui = require('@jaide/ui')
local lab = require('../state')

local M = {}

function M.history(s: any, names: any, busy: boolean): any
    local steps = lab.history(s)
    local items = {ui.button {key = 0, label = '0 · Start',
        class = if #s.trail == 0 then 'trace-step current' else 'trace-step visited',
        action = ui.event('seek_history', 0), disabled = busy or s.playing}}
    for index, name in steps do
        local class = if index == #s.trail then 'trace-step current'
            elseif index < #s.trail then 'trace-step visited' else 'trace-step'
        table.insert(items, ui.button {key = index, label = `{index} · {names[name] or name}`, class = class,
            action = ui.event('seek_history', index), disabled = busy or s.playing})
    end
    local ahead = #steps - #s.trail
    return ui.column {key = 'history', class = 'trace',
        ui.row {key = 'heading', class = 'spread',
            ui.text {key = 'title', style = 'strong', text = 'History'},
            ui.text {key = 'summary', class = 'caption', text = if #steps == 0 then 'Choose an event or play the scenario.'
                else `At step {#s.trail} of {#steps}` .. (if ahead > 0 then ` · {ahead} ahead (Forward)` else '')},
        },
        ui.row {key = 'steps', class = 'trace-steps', children = items},
    }
end

-- failure: the law shown; replaying: whether its trace is the one being played.
function M.trace(s: any, failure: any, names: any, failures: any, replaying: boolean, at_failure: boolean, busy: boolean): any
    local trace = {ui.button {key = 'start', class = if replaying and s.cursor == 1 then 'trace-step current' else 'trace-step',
        label = '0 · Start', action = ui.event('seek_failure', {law = failure.id, step = 0}), disabled = busy or s.playing}}
    for index, name in failure.counterexample do
        local current = replaying and index == s.cursor - 1
        local broken = current and at_failure
        table.insert(trace, ui.button {key = index,
            class = 'trace-step' .. (if broken then ' broken' elseif current then ' current' elseif replaying and index < s.cursor then ' visited' else ''),
            label = `{index} · {names[name] or name}{if broken then ' · Rule breaks' else ''}`,
            action = ui.event('seek_failure', {law = failure.id, step = index}), disabled = busy or s.playing})
    end
    return ui.column {key = 'trace', class = 'trace',
        ui.column {key = 'divider', class = 'divider'},
        ui.row {key = 'heading', class = 'spread',
            ui.text {key = 'title', style = 'strong', text = 'Counterexample trace'},
            ui.text {key = 'progress', class = 'caption', text = if replaying then `Step {s.cursor - 1} of {#s.playback}` else 'Select a step to inspect'},
        },
        ui.text {key = 'law', class = 'caption', text = failure.label},
        ui.row {key = 'steps', class = 'trace-steps', children = trace},
        ui.text {key = 'explanation', class = 'caption', tone = if at_failure then 'danger' else 'default',
            text = if at_failure then (failures[failure.id] or 'This event violates the selected rule.')
                elseif replaying then 'Follow the marker to the next state. Pause finishes the current transition.'
                else 'The last step is the first violation on this execution.'},
    }
end

return M
