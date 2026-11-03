--!strict
-- Draws a case from the data it provides: its state rows and, when it describes
-- one, its architecture. Both consume the same recorded transition, so they
-- animate together.
local motion = require('./motion')

local function escape(text: string): string
    return (string.gsub(string.gsub(string.gsub(text, '&', '&amp;'), '<', '&lt;'), '>', '&gt;'))
end

-- One row per described field; the box for the field's value is highlighted.
local function rows(spec: {any}, node: any, before: any, transition: any, failed: boolean): string
    local height = 52 + #spec * 92 - 30
    local parts = {`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 640 {height}" data-jaide-reduced-motion-ms="650">`}
    local color = if failed or node.safe == false then 'var(--bad)' else 'var(--accent)'
    for r, row in spec do
        local y = 52 + (r - 1) * 92
        local count = #row.labels
        local gap = 620 / count
        local width = gap - 10
        local selected, previous = (node[row.field] or 0) + 1, (before[row.field] or 0) + 1
        local animate = transition ~= nil and selected ~= previous
        table.insert(parts, `<text x="12" y="{y - 30}" fill="currentColor" font-size="12">{escape(row.label)}</text>`)
        for index, text in row.labels do
            local x = 10 + gap * (index - 0.5)
            local shape = `<rect x="{x - width / 2}" y="{y - 20}" width="{width}" height="40" rx="8" fill="{color}" fill-opacity=".12" stroke="{color}" stroke-width="2"/>`
            table.insert(parts, `<rect x="{x - width / 2}" y="{y - 20}" width="{width}" height="40" rx="8" fill="currentColor" fill-opacity=".025" stroke="currentColor" stroke-opacity=".2"/>`)
            table.insert(parts, motion.highlight(`row-{r}-{index}`, shape, index == selected, index == previous, animate))
            table.insert(parts, `<text x="{x}" y="{y + 4}" text-anchor="middle" fill="currentColor" font-size="12">{escape(text)}</text>`)
        end
        if animate then
            local x, xx = 10 + gap * (previous - 0.5), 10 + gap * (selected - 0.5)
            table.insert(parts, motion.marker(`row-{r}-transition`, `M {x} {y - 20} Q {(x + xx) / 2} {y - 44} {xx} {y - 20}`, color))
        end
    end
    table.insert(parts, '</svg>')
    return table.concat(parts)
end

-- Where a line from a leaves a's box towards b, and where it enters b's. Links
-- are drawn along the axis that separates the boxes most.
local function route(a: any, b: any, W: number, H: number): {{number}}
    if math.abs(b.x - a.x) >= math.abs(b.y - a.y) then
        local d = if b.x > a.x then 1 else -1
        return {{a.x + d * W / 2, a.y}, {b.x - d * W / 2, b.y}}
    end
    local d = if b.y > a.y then 1 else -1
    return {{a.x, a.y + d * H / 2}, {b.x, b.y - d * H / 2}}
end

-- spec: {width, height, card, components, links}; view: the node's captions and
-- danger; step: the edge's hops (component ids in order), side links and note.
local function architecture(spec: any, view: any, step: any, transition: any, failed: boolean): string
    local W = if spec.card and spec.card.width then spec.card.width else 160
    local H = if spec.card and spec.card.height then spec.card.height else 64
    local by = {}
    for _, component in spec.components do by[component.id] = component end
    local captions = if view and view.captions then view.captions else {}
    local danger = {}
    if view and type(view.danger) == 'table' then for _, id in view.danger do danger[id] = true end end
    local hops = if step and type(step.hops) == 'table' then step.hops else {}
    local side = if step and type(step.side) == 'table' then step.side else {}
    local color = if failed then 'var(--bad)' else 'var(--accent)'
    local parts = {`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {spec.width or 890} {spec.height or 400}" data-jaide-reduced-motion-ms="650">`}
    for _, link in spec.links do
        local a, b = by[link.from], by[link.to]
        if a and b then
            local points = route(a, b, W, H)
            table.insert(parts, `<path d="M {points[1][1]} {points[1][2]} L {points[2][1]} {points[2][2]}" fill="none" stroke="currentColor" stroke-opacity=".3" stroke-width="1.5"/>`)
            for _, point in points do
                table.insert(parts, `<circle cx="{point[1]}" cy="{point[2]}" r="2.5" fill="currentColor" fill-opacity=".45"/>`)
            end
            if link.label then
                table.insert(parts, `<text x="{(points[1][1] + points[2][1]) / 2}" y="{points[1][2] - 8}" text-anchor="middle" fill="currentColor" fill-opacity=".55" font-size="11">{escape(link.label)}</text>`)
            end
        end
    end
    local source, destination = hops[1], hops[#hops]
    local touched = {}
    if transition then for _, link in side do touched[link.to] = true end end
    for index, component in spec.components do
        local id, cx, cy = component.id, component.x, component.y
        local x, y = cx - W / 2, cy - H / 2
        local tone = if danger[id] then 'var(--bad)' else color
        local shape = `<rect x="{x}" y="{y}" width="{W}" height="{H}" rx="10" fill="{tone}" fill-opacity=".14" stroke="{tone}" stroke-width="2"/>`
        table.insert(parts, `<rect x="{x}" y="{y}" width="{W}" height="{H}" rx="10" fill="{if danger[id] then 'var(--bad)' else 'currentColor'}" fill-opacity="{if danger[id] then '.1' else '.04'}" stroke="{if danger[id] then 'var(--bad)' else 'currentColor'}" stroke-opacity="{if danger[id] then '.9' else '.25'}"/>`)
        local active = id == destination or touched[id] == true
        table.insert(parts, motion.highlight(`component-{index}`, shape, active, id == source and source ~= destination, transition ~= nil))
        table.insert(parts, `<text x="{cx}" y="{cy - 4}" text-anchor="middle" fill="currentColor" font-size="14" font-weight="700">{escape(component.title)}</text>`)
        table.insert(parts, `<text x="{cx}" y="{cy + 16}" text-anchor="middle" fill="currentColor" fill-opacity=".7" font-size="11">{escape(captions[id] or '')}</text>`)
    end
    if transition and #hops > 0 then
        local route_parts, trail = {}, {}
        local first = by[hops[1]]
        if #hops == 1 and first then
            local loop = `M {first.x - 40} {first.y - H / 2} C {first.x - 70} {first.y - H / 2 - 46} {first.x + 70} {first.y - H / 2 - 46} {first.x + 40} {first.y - H / 2}`
            table.insert(route_parts, loop); table.insert(trail, loop)
        else
            for index = 2, #hops do
                local a, b = by[hops[index - 1]], by[hops[index]]
                if a and b then
                    local points = route(a, b, W, H)
                    local segment = `{points[1][1]} {points[1][2]} L {points[2][1]} {points[2][2]}`
                    table.insert(route_parts, (if #route_parts == 0 then 'M ' else 'L ') .. segment)
                    table.insert(trail, 'M ' .. segment)
                end
            end
        end
        if #route_parts > 0 then
            -- The trail is drawn only on links, so it never crosses a caption; the marker travels the whole route.
            table.insert(parts, `<path d="{table.concat(trail, ' ')}" fill="none" stroke="{color}" stroke-width="2.5" stroke-dasharray="6 4" stroke-linecap="round"/>`)
            table.insert(parts, motion.marker('architecture-transition', table.concat(route_parts, ' '), color))
        end
        -- Side effects of the same step, such as an entry queued for later.
        for _, link in side do
            local a, b = by[link.from], by[link.to]
            if a and b then
                local points = route(a, b, W, H)
                table.insert(parts, `<path d="M {points[1][1]} {points[1][2]} L {points[2][1]} {points[2][2]}" fill="none" stroke="{color}" stroke-width="2.5" stroke-dasharray="2 4" stroke-linecap="round"/>`)
                if link.label then
                    table.insert(parts, `<text x="{(points[1][1] + points[2][1]) / 2}" y="{points[1][2] + 18}" text-anchor="middle" fill="{color}" font-size="11">{escape(link.label)}</text>`)
                end
            end
        end
    end
    table.insert(parts, '</svg>')
    return table.concat(parts)
end

-- "PO in ERP Lite: Sending 00 → Ordered 01; …" over the rows and detail fields.
local function changes(before: any, node: any, fields: {any}): string
    local parts = {}
    for _, field in fields do
        local a, b = before[field.field], node[field.field]
        if a ~= nil and b ~= nil and a ~= b then
            table.insert(parts, `{field.label}: {field.labels[a + 1] or tostring(a)} → {field.labels[b + 1] or tostring(b)}`)
        end
    end
    return if #parts == 0 then 'nothing changes.' else table.concat(parts, '; ') .. '.'
end

return {rows = rows, architecture = architecture, changes = changes}
