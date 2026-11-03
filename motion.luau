--!strict
-- One native, 650 ms transition. No plugin tasks run between its frames.
local function marker(id: string, path: string, color: string): string
    return `<g id="{id}" opacity="0"><circle r="5" fill="{color}"/><animateMotion path="{path}" dur=".65s" fill="freeze"/><animate attributeName="opacity" values="0;1;1;0" keyTimes="0;.08;.9;1" dur=".65s" fill="freeze"/></g>`
end
local function highlight(id: string, shape: string, active: boolean, previous: boolean, animated: boolean): string
    if not animated then return if active then shape else '' end
    local parts = {}
    if previous then
        table.insert(parts, `<g id="{id}-previous" opacity="1">{shape}<animate attributeName="opacity" from="1" to="0" dur=".12s" fill="freeze"/></g>`)
    end
    if active then
        table.insert(parts, `<g id="{id}-current" opacity="0">{shape}<animate attributeName="opacity" from="0" to="1" begin=".5s" dur=".15s" fill="freeze"/></g>`)
    end
    return table.concat(parts)
end
return {marker = marker, highlight = highlight}
