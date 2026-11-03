--!strict
-- Beside the explorer: the verdict, each law and the model's scope.
local ui = require('@jaide/ui')

return function(data: any, busy: boolean): any
    local failures = 0
    for _, law in data.laws do if not law.passed then failures += 1 end end
    local proof = data.proof
    local proved = type(proof) == 'table' and proof ~= jaide.null and proof.status == 'proved'
    local laws = {}
    for _, law in data.laws do
        local progress = law.kind == 'progress'
        local row = {
            ui.text {key = 'law', text = law.label},
            ui.text {key = 'result', class = 'caption',
                text = if law.passed then (if progress then 'Every reachable state can finish' else 'Holds in the reachable graph')
                    elseif progress then `{law.stuck_count or #law.stuck} reachable states cannot finish`
                    else 'Violated by a reachable execution',
                tone = if law.passed then 'default' else 'danger'},
        }
        if not law.passed then table.insert(row, ui.button {key = 'replay', label = 'Replay failure', class = 'replay',
            action = ui.event('show_failure', law.id), disabled = busy}) end
        table.insert(laws, ui.column {key = law.id, class = 'law', children = row})
    end
    local verdict = if failures > 0 then 'Counterexample found' elseif proved then 'All laws proved'
        elseif proof ~= nil and proof ~= jaide.null then 'Proof unresolved' else 'Ready to verify'
    local tone = if failures > 0 then 'danger' elseif proved then 'success' else 'warning'
    return ui.row {key = 'evidence', class = 'evidence', children = {
        ui.text {key = 'heading', class = 'caption', text = 'VERIFICATION'},
        ui.column {key = 'verdict', class = 'verdict ' .. tone,
            ui.text {key = 'result', class = 'verdict-title', text = verdict, tone = tone},
            ui.text {key = 'scope', class = 'caption', text = `Finite model · {#data.nodes} reachable states`},
        },
        ui.column {key = 'laws', class = 'laws', children = laws},
        ui.column {key = 'scope', class = 'scope',
            ui.text {key = 'heading', class = 'caption', text = 'MODEL SCOPE'},
            ui.text {key = 'bounds', class = 'caption', text = data.scope},
            ui.text {key = 'identity', class = 'caption', text = `{data.checker.version} · {string.sub(data.revision, 1, 12)}`},
        },
    }}
end
