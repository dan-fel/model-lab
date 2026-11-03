--!strict
-- The plugin's one task: run the runner (list, explore, prepare, advance),
-- read a large graph's pages, decode the wire format (wire.mjs) and check the
-- answer before it becomes the plugin's data.
local M = {}

local MAX_NODES, MAX_EDGES, MAX_PAGES = 3000, 90000, 150
local STATUSES = {'pending', 'complete', 'proved', 'unresolved', 'matched', 'mismatch', 'unavailable', 'stale', 'error'}

-- The decoded graph of the latest revision. A verification reuses it for every
-- step instead of reading its pages again; after an eviction it is read again.
local cache: any = nil

local function run(runner: string, args: {string}, timeout: number): (boolean, any)
    local full = {runner}
    for _, value in args do table.insert(full, value) end
    return pcall(jaide.run_process, {program = 'bun', args = full, json = true, timeout_ms = timeout})
end

local function catalogue(runner: string, epoch: number): any
    local ok, result = run(runner, {'list'}, 30000)
    if not ok then return {format = 'catalog', error = tostring(result), epoch = epoch} end
    if result.exit_code ~= 0 or type(result.json) ~= 'table' then
        return {format = 'catalog', error = result.stderr or 'Unreadable case list.', epoch = epoch}
    end
    return {format = 'catalog', cases = result.json.cases, problems = result.json.problems, epoch = epoch}
end

-- Rebuild nodes and edges as tables, and index each state's outgoing events.
local function decode(header: any, parts: any, rows: any, edge_views: any, edges: any): (any, string?)
    local fields, keys, events = header.fields, header.view_keys, header.events
    if type(fields) ~= 'table' or type(keys) ~= 'table' or type(events) ~= 'table' then return nil, 'The runner sent no graph header.' end
    if #rows == 0 or #rows > MAX_NODES or #edges > MAX_EDGES then return nil, `The graph must have 1–{MAX_NODES} states and at most {MAX_EDGES} transitions.` end
    local nodes, out = {}, {}
    for index, row in rows do
        local node: any = {id = index, refs = {}}
        for k, field in fields do node[field] = row[k] end
        for k = 1, #keys do
            local ref = row[#fields + k]
            if type(ref) ~= 'number' or ref < 0 or ref > #parts then return nil, `State {index} names a missing view.` end
            node.refs[k] = ref
        end
        nodes[index] = node
        out[index] = jaide.object {}
    end
    local decoded = {}
    for index, item in edges do
        local from, to, event, view = item[1], item[2], events[item[3]], item[4]
        if not nodes[from] or not nodes[to] or type(event) ~= 'string' or not edge_views[view] then
            return nil, `Transition {index} leaves the graph.`
        end
        if out[from][event] ~= nil then return nil, `State {from} has two "{event}" transitions.` end
        out[from][event] = index
        decoded[index] = {from = from, to = to, event = event, v = view}
    end
    return {nodes = nodes, edges = decoded, out = out, parts = parts, edge_views = edge_views,
        view_keys = keys, events = events}, nil
end

local function pages(runner: string, data: any): (any, string?)
    local count = data.graph.pages
    if type(count) ~= 'number' or count < 1 or count > MAX_PAGES or count % 1 ~= 0 then return nil, 'Invalid page count from runner.' end
    local parts, rows, edge_views, edges = {}, {}, {}, {}
    for number = 1, count do
        local ok, chunk = run(runner, {'page', data.artifact, tostring(number)}, 30000)
        if not ok then return nil, tostring(chunk) end
        if chunk.exit_code ~= 0 or type(chunk.json) ~= 'table' then return nil, chunk.stderr or 'Unreadable page.' end
        for _, item in chunk.json.parts do table.insert(parts, item) end
        for _, item in chunk.json.nodes do table.insert(rows, item) end
        for _, item in chunk.json.edge_views do table.insert(edge_views, item) end
        for _, item in chunk.json.edges do table.insert(edges, item) end
    end
    return decode(data.graph, parts, rows, edge_views, edges)
end

local function valid(data: any, arguments: any): string?
    if type(data) ~= 'table' or data.format ~= 4 or data.case ~= arguments.case
        or data.design ~= arguments.design or data.scenario ~= arguments.scenario
        or type(data.revision) ~= 'string' or #data.revision ~= 64 or type(data.laws) ~= 'table' or #data.laws == 0
        or type(data.walkthrough) ~= 'table' or type(data.scope) ~= 'string' or type(data.artifact) ~= 'string'
        or type(data.checker) ~= 'table' or type(data.checker.version) ~= 'string' or type(data.graph) ~= 'table'
        or type(data.meta) ~= 'table' or type(data.meta.names) ~= 'table' or type(data.meta.rows) ~= 'table' then
        return 'The model runner returned an invalid answer.'
    end
    -- The runner reports broken values with their file and field (check.mjs);
    -- these checks keep a broken runner from drawing nonsense.
    for index, node in data.nodes do
        for _, row in data.meta.rows do
            local value = node[row.field]
            if type(value) ~= 'number' or value % 1 ~= 0 or value < 0 or value >= #row.labels then
                return `State {index} has no valid "{row.field}".`
            end
        end
    end
    for _, edge in data.edges do
        if not data.meta.names[edge.event] then return `No label for event "{edge.event}".` end
    end
    for _, law in data.laws do
        if type(law.id) ~= 'string' or type(law.label) ~= 'string' or type(law.passed) ~= 'boolean'
            or type(law.counterexample) ~= 'table' then return 'Invalid law from runner.' end
        local current = 1
        for _, event in law.counterexample do
            local index = data.out[current][event]
            if index == nil then return 'A counterexample does not follow the returned graph.' end
            current = data.edges[index].to
        end
    end
    if arguments.operation ~= 'explore' then
        if type(data.steps) ~= 'table' or #data.steps < 2 or #data.steps > 16 then return 'Invalid verification plan.' end
        local pending = false
        for _, item in data.steps do
            if type(item.id) ~= 'string' or type(item.label) ~= 'string'
                or not table.find({'prepare', 'proof', 'compare'}, item.kind) or not table.find(STATUSES, item.status) then
                return 'Invalid verification step.'
            end
            if pending and item.status ~= 'pending' then return 'Verification results arrived out of order.' end
            pending = pending or item.status == 'pending'
        end
    end
    return nil
end

-- arguments: operation (list, explore, prepare, advance), epoch, case, design,
-- scenario, revision (prepare), artifact and step (advance), timeout (seconds).
function M.read(runner: string, arguments: any): any
    if arguments.operation == 'list' then return catalogue(runner, arguments.epoch) end
    local function failed(message: string): any
        return {error = message, epoch = arguments.epoch, case = arguments.case}
    end
    local args = {arguments.operation}
    if arguments.operation == 'advance' then
        table.insert(args, arguments.artifact); table.insert(args, tostring(arguments.step))
    else
        for _, value in {arguments.case, arguments.design, arguments.scenario, arguments.revision} do table.insert(args, value) end
    end
    -- A proof may run for the case's own timeout; leave room for the runner.
    local timeout = math.clamp(((arguments.timeout or 30) + 10) * 1000, 40000, 120000)
    local ok, result = run(runner, args, timeout)
    if not ok then return failed(tostring(result)) end
    if result.exit_code ~= 0 then return failed(result.stderr) end
    local data = result.json
    if type(data) ~= 'table' or type(data.graph) ~= 'table' then return failed('The model runner returned an invalid answer.') end
    local decoded, problem
    if type(data.graph.nodes) == 'table' then
        decoded, problem = decode(data.graph, data.graph.parts, data.graph.nodes, data.graph.edge_views, data.graph.edges)
    elseif cache and cache.revision == data.revision then
        decoded = cache.graph
    else
        decoded, problem = pages(runner, data)
    end
    if problem then return failed(problem) end
    cache = {revision = data.revision, graph = decoded}
    for key, value in decoded do data[key] = value end
    data.graph = {counts = data.graph.counts, pages = data.graph.pages}
    local invalid = valid(data, arguments)
    if invalid then return failed(invalid) end
    data.epoch = arguments.epoch
    return data
end

return M
