-- Model Lab smoke test: drive one instance through its whole lifecycle
-- Run with run_luau. Set INSTANCE (and PLUGIN for a development install); with
-- one instance open, INSTANCE may stay nil. Uses only public operations, so any
-- conversation of the plugin's owner can run it; captures need check_plugin,
-- which only the conversation developing the plugin may call, and are skipped
-- elsewhere. Returns {pass, checks, failures, captures}.
local PLUGIN = 'model-lab'   -- the manifest id, e.g. 'model-lab-pnp' for a development install
local INSTANCE = nil          -- the instance id; operations lists them

local checks, failures, captures = {}, {}, {}
local function check(name: string, ok: boolean, detail: any?)
    table.insert(checks, {name = name, ok = ok})
    if not ok then table.insert(failures, {name = name, detail = if detail ~= nil then tostring(detail) else nil}) end
    return ok
end
local function call(name: string, arguments: any?): (boolean, any)
    local ok, answer = pcall(jaide.perform, {operation = `local/{PLUGIN}.{name}`,
        arguments = {instance = INSTANCE, arguments = arguments or jaide.object {}}})
    if not ok then return false, if type(answer) == 'table' then answer.message else answer end
    return true, answer.result
end
local function must(name: string, arguments: any?): any
    local ok, result = call(name, arguments)
    check(`{name} succeeds`, ok, result)
    if not ok then error(`{name}: {result}`, 0) end
    return result
end
-- Tasks run in the background; poll status until nothing is pending.
local function settle(what: string): any
    for _ = 1, 120 do
        local status = must('status')
        if status.pending == nil then
            check(`{what}: finished without error`, status.error == nil, status.error)
            return status
        end
    end
    check(`{what}: finished in time`, false)
    error(`{what} did not finish`, 0)
end
local function capture(label: string)
    local ok, answer = pcall(jaide.perform, {operation = 'check_plugin', arguments = {plugin = PLUGIN, instance = INSTANCE,
        capture = {width = 1280, height = 1600, theme = 'dark'}}})
    table.insert(captures, {label = label, taken = ok, note = if ok then nil else 'check_plugin is not available here'})
end

local ok, problem = pcall(function()
    if INSTANCE == nil then
        local listed = jaide.operations {describe = {`local/{PLUGIN}.status`}}
        local instances = listed.operations[1] and listed.operations[1].instances or {}
        assert(#instances == 1, `Set INSTANCE: {#instances} instances of {PLUGIN} are open.`)
        INSTANCE = instances[1].id
    end
    must('rescan')
    local status = settle('rescan')
    check('the project has cases', #status.cases > 0, 'no cases in .model-lab/cases')
    -- Every case loads with its first design and scenario, at the start.
    for _, case in status.cases do
        must('configure', {case = case.id, design = case.designs[1][1], scenario = case.scenarios[1][1]})
        local loaded = settle(`load {case.id}`)
        check(`{case.id} loads`, loaded.loaded and loaded.case == case.id, loaded.error)
        local here = must('explain')
        check(`{case.id} starts in state 1`, here.state == 1 and here.step == 0, here.text)
    end
    -- Find a design whose model breaks a law, so the replay has something to show.
    local case, broken = status.cases[1], nil
    for _, entry in status.cases do
        for _, design in entry.designs do
            must('configure', {case = entry.id, design = design[1], scenario = entry.scenarios[1][1]})
            local loaded = settle(`load {entry.id} {design[1]}`)
            for _, law in loaded.laws do if not law.passed and broken == nil then broken = law; case = entry end end
            if broken then break end
        end
        if broken then break end
    end
    if not broken then must('configure', {case = case.id, design = case.designs[1][1], scenario = case.scenarios[1][1]}); settle('reload') end
    local loaded = must('status')
    -- The walkthrough, one event at a time: each step adds exactly one to the trail.
    local trail = {}
    for index, event in loaded.walkthrough do
        local after = must('step', {event = event})
        table.insert(trail, after.state)
        check(`walkthrough step {index} ({event})`, after.step == index and after.last ~= nil, after.text)
    end
    local n = #loaded.walkthrough
    if n > 0 then
        capture(`after the walkthrough (step {n})`)
        local back = must('back')
        check('back undoes one step', back.step == n - 1 and back.state == (if n > 1 then trail[n - 1] else 1), back.text)
        local forward = must('forward')
        check('forward redoes it', forward.step == n and forward.state == trail[n], forward.text)
        local start = must('seek', {step = 0})
        check('seek 0 returns to the start', start.step == 0 and start.state == 1, start.text)
        local again = must('seek', {step = n})
        check('seek forward follows the same trail', again.step == n and again.state == trail[n], again.text)
    end
    local refused = call('step', {event = '__no_such_event__'})
    check('an impossible event is refused', not refused)
    if broken then
        local traces = must('counterexamples')
        check('counterexamples lists the broken law', #traces > 0 and traces[1].id == broken.id)
        local replayed = must('replay', {law = broken.id})
        check('the replay reaches the counterexample', replayed.replay ~= nil and replayed.step == broken.steps
            and replayed.replay.step == broken.steps, replayed.text)
        if broken.kind ~= 'progress' then check('the replayed state breaks a law', replayed.safe == false, replayed.text) end
        capture(`counterexample of {broken.id}`)
    end
    must('verify')
    local verified = settle('verify')
    check('verification finished', verified.proof ~= nil, verified.proof)
    for _, step in verified.steps or {} do
        check(`step {step.id} returned`, step.status ~= 'pending' and step.status ~= 'error', step.message or step.status)
    end
    local report = must('report')
    check('report is Markdown', type(report) == 'string' and string.sub(report, 1, 12) == '## Model Lab', report)
end)
if not ok then check('the lifecycle ran to the end', false, problem) end
return {pass = #failures == 0, checks = #checks, failures = failures, captures = captures}
