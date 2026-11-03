--!strict
-- Explore the model: the controls, both diagrams, what the last step changed,
-- the possible events, the metrics, the history and a counterexample's trace.
-- Controls sit above everything whose size changes between steps.
local ui = require('@jaide/ui')
local render = require('../render')
local graph = require('../graph')
local lab = require('../state')
local trails = require('./history')

local M = {}

-- The law being shown: the replayed one, otherwise the first that breaks.
function M.failure(s: any, data: any): any
    if s.failure then return lab.failed_law(data, s.failure) end
    for _, law in data.laws do if not law.passed then return law end end
    return nil
end

function M.banner(failure: any, failures: any, busy: boolean, playing: boolean): any
    return ui.row {key = 'counterexample', class = 'failure-banner',
        ui.column {key = 'description', class = 'intro',
            ui.text {key = 'heading', class = 'caption', text = 'COUNTEREXAMPLE FOUND', tone = 'danger'},
            ui.text {key = 'cause', style = 'strong', text = failures[failure.id] or failure.label},
            ui.text {key = 'hint', class = 'caption',
                text = `A {#failure.counterexample}-step execution breaks this rule. Replay it or select a step below.`},
        },
        ui.button {key = 'replay', class = 'failure-action', label = 'Show how it fails',
            action = ui.event('show_failure', failure.id), disabled = busy or playing},
    }
end

-- Reserve room for the state with the most events, so the list's height (and
-- everything below it) stays put while stepping or playing.
local function widest(data: any): number
    local most = 0
    for _, out in data.out do
        local count = 0
        for _ in out do count += 1 end
        if count > most then most = count end
    end
    return most
end

function M.stage(state: any, data: any, failure: any, busy: boolean): any
    local s, meta = lab.selected(state), data.meta
    local names = meta.names
    local failures = if type(meta.failures) == 'table' then meta.failures else {}
    local replaying = failure ~= nil and s.failure == failure.id
    local at_failure = replaying and s.cursor > #s.playback
    local events = {}
    for _, name in graph.possible(data, s.current) do
        table.insert(events, ui.button {key = name, label = names[name], class = 'event',
            action = ui.event('take_event', name), disabled = busy or s.playing})
    end
    local event_lines = math.clamp(math.ceil(widest(data) / 4), 1, 8)
    local node = data.nodes[s.current]
    local before = if s.transition then data.nodes[s.transition.from] else node
    local view = graph.node_view(data, node)
    local metrics = {}
    for index, metric in (if type(view.metrics) == 'table' then view.metrics else {}) do
        table.insert(metrics, ui.column {key = index, class = 'metric',
            ui.text {key = 'value', class = 'metric-value', text = metric[2], tone = metric[3]},
            ui.text {key = 'label', class = 'caption', text = metric[1]},
        })
    end
    -- The recorded transition, with the case's description of it.
    local step = if s.transition then graph.edge_view(data, graph.edge(data, s.transition.from, s.transition.event)) else nil
    local architecture = meta.architecture ~= nil and meta.architecture ~= jaide.null
    local explanation = if s.transition
        then `{names[s.transition.event] or s.transition.event}: {render.changes(before, node, graph.fields(meta))}{if step and step.note then step.note else ''}`
        else 'Step an event to see what changes' .. (if architecture
            then ' and which systems it passes through. Red marks a component where a rule is broken.' else '.')
    local panels = {
        ui.column {key = 'state', class = 'diagram-panel',
            ui.text {key = 'heading', style = 'strong', text = 'State machine'},
            ui.svg {key = if s.transition then `machine:{s.motion}` else 'machine:rest', class = 'diagram',
                label = if at_failure then 'State after the rule-breaking event' else 'Current model state and transition',
                source = render.rows(meta.rows, node, before, s.transition, at_failure)},
        },
    }
    if architecture then
        table.insert(panels, ui.column {key = 'architecture', class = 'diagram-panel',
            ui.text {key = 'heading', style = 'strong', text = 'Architecture'},
            ui.svg {key = if s.transition then `architecture:{s.motion}` else 'architecture:rest', class = 'diagram',
                label = 'Components participating in the current model event',
                source = render.architecture(meta.architecture, view, step, s.transition, at_failure)},
        })
    end
    local stage = ui.column {key = 'explore', class = if state.expanded then 'stage expanded' else 'stage',
        ui.row {key = 'heading', class = 'spread',
            ui.text {key = 'title', style = 'strong', text = if at_failure then 'Rule breaks here' else 'Explore the model',
                tone = if at_failure then 'danger' else 'default'},
            ui.row {key = 'controls', class = 'actions stage-controls',
                ui.text {key = 'position', class = 'caption position',
                    text = (if replaying then `Step {s.cursor - 1}/{#s.playback} · ` else '') .. `state {s.current}/{#data.nodes}`},
                ui.button {key = 'expand', label = if state.expanded then 'Collapse diagrams' else 'Expand diagrams',
                    action = ui.event('expand')},
            },
        },
        ui.row {key = 'playback', class = 'actions',
            ui.button {key = 'back', class = 'nav', label = '← Back', action = ui.event('go_back'),
                disabled = busy or s.playing or not lab.can_back(s)},
            ui.button {key = 'forward', class = 'nav', label = 'Forward →', action = ui.event('go_forward'),
                disabled = busy or s.playing or not lab.can_forward(s)},
            ui.button {key = 'play', class = 'play',
                label = if s.playing then 'Pause' elseif s.cursor <= #s.playback then 'Resume'
                    elseif s.failure then 'Replay counterexample' else (meta.walkthrough_label or 'Play scenario'),
                action = ui.event('play'), disabled = busy or (#data.walkthrough == 0 and #s.playback == 0)},
            ui.button {key = 'step', label = 'Step', action = ui.event('walk'),
                disabled = busy or s.playing or (#data.walkthrough == 0 and #s.playback == 0)},
            ui.button {key = 'reset', label = 'Reset', action = ui.event('reset'), disabled = busy},
        },
        ui.row {key = 'diagrams', class = 'diagrams', children = panels},
        ui.text {key = 'explanation', class = 'transition-detail', text = explanation,
            tone = if at_failure then 'danger' else 'default'},
        ui.text {key = 'events-heading', class = 'caption', text = 'POSSIBLE NEXT EVENTS'},
        ui.column {key = 'events-box', class = `events-box events-{event_lines}`,
            ui.row {key = 'events', class = 'actions events', children = events},
        },
        ui.row {key = 'metrics', class = 'metrics', children = metrics},
        trails.history(s, names, busy),
    }
    if failure then table.insert(stage.children, trails.trace(s, failure, names, failures, replaying, at_failure, busy)) end
    return stage
end

return M
