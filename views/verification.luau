--!strict
-- The verification panel: one line with a progress bar; Show steps lists each proof.
local lab = require('../state')
local ui = require('@jaide/ui')

local function label(item: any, pending: boolean, active: boolean, running: boolean): string
    if pending then return if active and running then 'Running' elseif running then 'Queued' else 'Not completed' end
    local status = item.status
    return if status == 'unavailable' then 'Build required' elseif status == 'stale' then 'Rebuild required'
        elseif status == 'unresolved' then 'Unresolved' elseif status == 'error' then 'Error'
        elseif status == 'mismatch' then 'Mismatch' elseif status == 'proved' then 'Proved'
        elseif status == 'matched' then 'Matched' else 'Done'
end

return function(state: any, data: any): any
    local preparing = state.pending == 'prepare'
    local running = preparing or state.pending == 'advance'
    local steps = if preparing then {} else data.steps
    local completed, rows = 0, {}
    local active = if not preparing then lab.next_check(data) else nil
    local issues = false
    for index, item in steps do
        local pending = item.status == 'pending'
        if not pending then completed += 1 end
        local good = table.find({'complete', 'proved', 'matched'}, item.status) ~= nil
        issues = issues or (not pending and not good)
        table.insert(rows, ui.row {key = item.id, class = 'verification-step' .. (if index == active and running then ' active' else ''),
            ui.text {key = 'name', class = 'verification-name', text = item.label},
            ui.text {key = 'status', class = 'caption', text = label(item, pending, index == active, running),
                tone = if pending then 'default' elseif good then 'success' else 'warning'},
        })
    end
    local total = #steps
    local finished = total > 0 and completed == total
    local title = if running then 'Verifying model' elseif finished then (if issues then 'Verification finished with issues' else 'Verification complete')
        else 'Verification stopped'
    local detail = if preparing then 'Preparing a frozen snapshot and the proof list…'
        elseif running and active then (if steps[active].kind == 'proof' then 'Checking proof: ' else '') .. steps[active].label
        elseif finished then 'Every step has returned. Unresolved proofs do not count as passes.'
        else 'Completed results are retained. Verify starts a new run.'
    local width = if total > 0 then 300 * completed / total else 0
    -- Collapsed by default: one line with the bar; the steps open on request.
    local open = state.verification_open == true
    local panel = ui.column {key = 'verification-progress', class = 'verification-progress',
        ui.row {key = 'heading', class = 'spread',
            ui.text {key = 'title', style = 'strong', text = title,
                tone = if finished and issues then 'warning' elseif finished then 'success' else 'default'},
            ui.row {key = 'summary', class = 'actions',
                ui.text {key = 'count', class = 'caption', text = if total > 0 then `{completed}/{total} steps completed` else 'Preparing'},
                ui.button {key = 'toggle', class = 'verification-toggle', label = if open then 'Hide steps' else 'Show steps',
                    action = ui.event('toggle_verification')},
            },
        },
        ui.svg {key = 'bar', class = 'verification-bar', fit = 'stretch', label = if total > 0 then `{completed} of {total} verification steps completed` else 'Preparing verification',
            source = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 300 8"><rect width="300" height="8" rx="4" fill="currentColor" fill-opacity="0.15"/><rect width="{width}" height="8" rx="4" fill="currentColor"/></svg>`},
    }
    if open then
        table.insert(panel.children, ui.text {key = 'detail', class = 'caption', text = detail})
        table.insert(panel.children, ui.column {key = 'steps', class = 'verification-steps', children = rows})
    end
    return panel
end
