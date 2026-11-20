-- Blobs for Questie: Geometry
local ADDON_NAME, ns = ...
local QQ = ns.QQ
local floor, ceil, max, min, sqrt = math.floor, math.ceil, math.max, math.min, math.sqrt
local format = string.format
local pairs, ipairs, type, tostring, tonumber = pairs, ipairs, type, tostring, tonumber
local classOf = ns.classOf
local greenRange = ns.greenRange
local questColor = ns.questColor

---------------------------------------------------------------------------
-- Blob geometry: a smooth metaball field around the spawn points. Outline = interpolated
-- marching squares, fill = merged rectangles. Separate islands become separate blobs.
---------------------------------------------------------------------------

local BLOB_T = 0.34
local outlineSegments
local SEGTAB = {
    [1] = { { "L", "T" } }, [2] = { { "T", "R" } }, [3] = { { "L", "R" } }, [4] = { { "R", "B" } },
    [5] = { { "L", "T" }, { "R", "B" } }, [6] = { { "T", "B" } }, [7] = { { "L", "B" } },
    [8] = { { "L", "B" } }, [9] = { { "T", "B" } }, [10] = { { "T", "R" }, { "L", "B" } },
    [11] = { { "R", "B" } }, [12] = { { "L", "R" } }, [13] = { { "T", "R" } }, [14] = { { "L", "T" } },
}

local function simplify(pts, tol)
    local n = #pts
    if n < 3 then return pts end
    local out = { pts[1] }
    local anchor = 1
    for i = 3, n do
        local ax, ay, bx, by = pts[anchor][1], pts[anchor][2], pts[i][1], pts[i][2]
        local dx, dy = bx - ax, by - ay
        local len = sqrt(dx * dx + dy * dy)
        local bad = false
        if len > 0 then
            for k = anchor + 1, i - 1 do
                if math.abs(dy * (pts[k][1] - ax) - dx * (pts[k][2] - ay)) / len > tol then bad = true; break end
            end
        end
        if bad then
            out[#out + 1] = pts[i - 1]
            anchor = i - 1
        end
    end
    out[#out + 1] = pts[n]
    return out
end

-- edgeSegs = { {cellKey, edgeA, edgeB}, ... }  ->  { {x1, y1, x2, y2}, ... }
outlineSegments = function(edgeSegs, edgePt)
    local adj = {}
    for _, sg in ipairs(edgeSegs) do
        local a, b = sg[2], sg[3]
        local la = adj[a]; if not la then la = {}; adj[a] = la end
        la[#la + 1] = b
        local lb = adj[b]; if not lb then lb = {}; adj[b] = lb end
        lb[#lb + 1] = a
    end
    local visited, polys = {}, {}
    local function key(a, b)
        if a > b then a, b = b, a end
        return a * 4194304 + b
    end
    local function trace(a)
        local pts = { edgePt(a) }
        local cur = a
        while true do
            local nb
            for _, b in ipairs(adj[cur]) do
                if not visited[key(cur, b)] then nb = b; break end
            end
            if not nb then break end
            visited[key(cur, nb)] = true
            pts[#pts + 1] = edgePt(nb)
            cur = nb
        end
        return pts
    end
    for e, l in pairs(adj) do
        if #l == 1 then polys[#polys + 1] = trace(e) end
    end
    for e in pairs(adj) do
        local pts = trace(e)
        if #pts > 1 then polys[#polys + 1] = pts end
    end
    local out = {}
    for _, pts in ipairs(polys) do
        pts = simplify(pts, 0.8)
        for i = 1, #pts - 1 do
            out[#out + 1] = { pts[i][1], pts[i][2], pts[i + 1][1], pts[i + 1][2] }
        end
    end
    return out
end

-- Heat map: colour by how hard a quest is for the player's level. A "step" is the level difference (grey ... green ... yellow ... orange ... red, the same bands the game uses for quest titles).
local function heatColor(step) return questColor(step) end

-- Drop rate (percent) of a loot objective at this icon's monster, from Questie's drop tables; nil = unknown.
local dropCache = {}
local function dropRate(d)
    local o = d.ObjectiveData
    local item, npc = o and o.Type == "item" and o.Id, d.ObjectiveTargetId
    if type(item) ~= "number" or type(npc) ~= "number" then return nil end
    local key = item * 1000000 + npc
    local v = dropCache[key]
    if v == nil then
        v = false
        local ok, QDB = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieDB")
        if ok and QDB and QDB.GetItemDroprate then
            local ok2, res = pcall(QDB.GetItemDroprate, item, npc)
            if ok2 and type(res) == "table" and type(res[1]) == "number" then v = res[1] end
        end
        dropCache[key] = v
    end
    return v or nil
end

-- What colours a spot of a blob: the level step of the quest ("level" mode) or its kind 1..3 ("kind" mode;
-- loot with a known drop rate is 101 poor, 102 mid, 103 good). nil = one colour for the whole blob.
local function heatStep(d, plevel)
    if ns.DB.colorMode == "kind" then
        local k = classOf(d.Icon)
        if k == 2 and ns.DB.lootByDrop then
            local rate = dropRate(d)
            if rate then return 100 + (rate < 30 and 1 or (rate < 80 and 2 or 3)) end   -- poor / mid / good drop rate
        end
        return k
    end
    if ns.DB.colorMode ~= "level" then return nil end
    local q = d.QuestData
    local lv = q and q.level
    if type(lv) ~= "number" then return nil end
    if lv <= 0 then lv = plevel end   -- quests that scale with the player
    local step = lv - plevel
    return min(max(step, -(greenRange() + 1)), 5)
end

-- Colour modes: the blob is filled row by row (one cell high), each piece with a left-to-right colour
-- gradient. The colour at a spot is a mix of the quests around it: one kind alone gives its exact colour,
-- where two meet the colour runs from one to the other.
-- The cells the outline crosses become bent quads that end exactly at the outline. Where the outline runs
-- nearly straight through several cells in a row (or column), one quad covers them all.
-- mixOf(i, j) gives the colour mix at column i of row j (nil in one-colour mode).
local function edgePieces(edgeList, nj, mixOf)
    local byK, used, out = {}, {}, {}
    for _, e in ipairs(edgeList) do byK[e.k] = e end
    local function linear(vals, tol)   -- vals[1..n] close to the straight line from first to last?
        local n = #vals
        for m = 2, n - 1 do
            if math.abs(vals[m] - (vals[1] + (vals[n] - vals[1]) * (m - 1) / (n - 1))) > tol then return false end
        end
        return true
    end
    local function mixLinear(i1, i2, j)
        if not mixOf then return true end
        local a, b = mixOf(i1, j), mixOf(i2, j)
        if not a or not b or a[1] ~= b[1] or a[2] ~= b[2] then return false end
        for i = i1 + 1, i2 - 1 do
            local m = mixOf(i, j)
            if not m or m[1] ~= a[1] or m[2] ~= a[2] or math.abs(m[3] - (a[3] + (b[3] - a[3]) * (i - i1) / (i2 - i1))) > 0.07 then return false end
        end
        return true
    end
    local function sameMix(i, j1, j2)
        if not mixOf then return true end
        local a, b = mixOf(i, j1), mixOf(i + 1, j1)
        for j = j1 + 1, j2 do
            local c, d = mixOf(i, j), mixOf(i + 1, j)
            if (a and a.key) ~= (c and c.key) or (b and b.key) ~= (d and d.key) then return false end
        end
        return true
    end
    for _, e in ipairs(edgeList) do
        if not used[e.k] then
            local cs, tol = e.cs, e.cs * 0.12
            local piece
            if e.mask == 12 or e.mask == 3 then
                -- outline crosses the left and right edges: run to the right
                local run, ys = { e }, { e.yl, e.yr }
                while true do
                    local nx = byK[e.k + nj * #run]
                    if not nx or nx.mask ~= e.mask or used[nx.k] then break end
                    ys[#ys + 1] = nx.yr
                    if not linear(ys, tol) or not mixLinear(e.i, e.i + #run + 1, e.j) then ys[#ys] = nil; break end
                    run[#run + 1] = nx
                end
                local last = run[#run]
                local xl, xr = e.x, last.x + cs
                local yl, yr = e.yl, last.yr
                if e.mask == 12 then   -- inside below the line
                    piece = { xl, yl, xr, yr, xr, e.y + cs, xl, e.y + cs }
                else
                    piece = { xl, e.y, xr, e.y, xr, yr, xl, yl }
                end
                piece.mL, piece.mR = mixOf and mixOf(e.i, e.j), mixOf and mixOf(last.i + 1, e.j)
                for _, c in ipairs(run) do used[c.k] = true end
            elseif e.mask == 6 or e.mask == 9 then
                -- outline crosses the top and bottom edges: run downwards
                local run, xs = { e }, { e.xt, e.xb }
                while true do
                    local nx = byK[e.k + #run]
                    if not nx or nx.mask ~= e.mask or used[nx.k] then break end
                    xs[#xs + 1] = nx.xb
                    if not linear(xs, tol) or not sameMix(e.i, e.j, e.j + #run) then xs[#xs] = nil; break end
                    run[#run + 1] = nx
                end
                local last = run[#run]
                local yt, yb = e.y, last.y + cs
                local xt, xb = e.xt, last.xb
                if e.mask == 6 then   -- inside right of the line
                    piece = { xt, yt, e.x + cs, yt, e.x + cs, yb, xb, yb }
                else
                    piece = { e.x, yt, xt, yt, xb, yb, e.x, yb }
                end
                piece.mL, piece.mR = mixOf and mixOf(e.i, e.j), mixOf and mixOf(e.i + 1, e.j)
                for _, c in ipairs(run) do used[c.k] = true end
            end
            if piece then
                piece.k = e.k
                out[#out + 1] = piece
            else
                -- any other cell: its own polygon, as quads fanned from the first corner
                used[e.k] = true
                local poly, n = e.poly, #e.poly / 2
                local k = 2
                while k <= n - 1 do
                    local d = min(k + 2, n)
                    local q = { poly[1], poly[2], poly[k * 2 - 1], poly[k * 2], poly[k * 2 + 1], poly[k * 2 + 2], poly[d * 2 - 1], poly[d * 2] }
                    q.mL, q.mR, q.k = mixOf and mixOf(e.i, e.j), mixOf and mixOf(e.i + 1, e.j), e.k
                    out[#out + 1] = q
                    k = k + 2
                end
            end
        end
    end
    return out
end

local FILL_SUB = 1   -- rows per cell (2 is smoother vertically but draws about twice as many pieces)
local function mixKey(m) return m and (tostring(m[1]) .. ":" .. tostring(m[2]) .. ":" .. m[3]) or "" end
local function buildFill(comps, compOf, inside, edgeList, pts, R, x0, y0, cs, ni, nj)
    -- class weights at the sample points: column i (cell edges), sub-row s of cell row j
    local acc = {}
    local NS = nj * FILL_SUB
    for _, p in ipairs(pts) do
        local pr = p.r or R
        local pR2 = pr * pr
        local h = p[4] or "-"
        local i1, i2 = max(0, ceil((p[1] - pr - x0) / cs)), min(ni - 1, floor((p[1] + pr - x0) / cs))
        local r1 = max(0, ceil(((p[2] - pr - y0) / cs) * FILL_SUB - 0.5))
        local r2 = min(NS - 1, floor(((p[2] + pr - y0) / cs) * FILL_SUB - 0.5))
        for i = i1, i2 do
            local dx = x0 + i * cs - p[1]
            for rr = r1, r2 do
                local dy = y0 + (rr + 0.5) / FILL_SUB * cs - p[2]
                local d2 = (dx * dx + dy * dy) / pR2
                if d2 < 1 then
                    local v = 1 - d2
                    local key = i * NS + rr
                    local t = acc[key]
                    if not t then t = {}; acc[key] = t end
                    t[h] = (t[h] or 0) + v * v
                end
            end
        end
    end
    local mixes = {}
    local function mixAt(i, rr)
        local key = i * NS + rr
        local m = mixes[key]
        if m ~= nil then return m or nil end
        local t = acc[key]
        local h1, w1, h2, w2
        if t then
            for h, w in pairs(t) do
                if not w1 or w > w1 then h2, w2 = h1, w1; h1, w1 = h, w
                elseif not w2 or w > w2 then h2, w2 = h, w end
            end
        end
        if not h1 then mixes[key] = false; return nil end
        local f = (w2 and w2 > 0) and floor(w2 / (w1 + w2) * 16 + 0.5) / 16 or 0
        if f == 0 then h2 = nil end
        if h2 ~= nil and tostring(h1) > tostring(h2) then h1, h2, f = h2, h1, 1 - f end   -- one order per pair
        m = { h1 ~= "-" and h1 or nil, h2 ~= "-" and h2 or nil, f }
        m.key = mixKey(m)
        mixes[key] = m
        return m
    end
    local function samePair(a, b) return a and b and a[1] == b[1] and a[2] == b[2] end
    local open = {}
    for j = 0, nj - 2 do
        for s = 0, FILL_SUB - 1 do
            local rr = j * FILL_SUB + s
            local ya, yb = y0 + (j + s / FILL_SUB) * cs, y0 + (j + (s + 1) / FILL_SUB) * cs
            local nowOpen = {}
            local i = 0
            while i <= ni - 2 do
                local k = i * nj + j
                if inside[k] then
                    local mL, mR = mixAt(i, rr), mixAt(i + 1, rr)
                    local w = 1
                    -- longer pieces while the colour changes evenly between the two ends
                    while mL and i + w <= ni - 2 and inside[(i + w) * nj + j] do
                        local mn = mixAt(i + w + 1, rr)
                        if not samePair(mL, mn) then break end
                        local ok = true
                        for c = 1, w do
                            local mc = mixAt(i + c, rr)
                            if not samePair(mc, mL) or math.abs(mc[3] - (mL[3] + (mn[3] - mL[3]) * c / (w + 1))) > 0.07 then ok = false; break end
                        end
                        if not ok then break end
                        w = w + 1
                        mR = mn
                    end
                    local c = comps[compOf[k] or 0]
                    if c then
                        -- the same piece right above: make that one taller
                        local key = i .. "|" .. w .. "|" .. mixKey(mL) .. "|" .. mixKey(mR)
                        local prev = open[key]
                        if prev and prev.c == c then
                            prev[4] = yb
                            nowOpen[key] = prev
                        else
                            local l = c.hrects
                            if not l then l = {}; c.hrects = l end
                            local rect = { x0 + i * cs, ya, x0 + (i + w) * cs, yb, mL, mR, c = c }
                            l[#l + 1] = rect
                            nowOpen[key] = rect
                        end
                    end
                    i = i + w
                else
                    i = i + 1
                end
            end
            open = nowOpen
        end
    end
    -- the corner of an edge cell can lie where no point reaches: take the colour of the corner next to it
    local NEIGHBOURS = { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 }, { -1, 0 }, { 0, -1 } }
    local pieces = edgePieces(edgeList, nj, function(i, j)
        for _, d in ipairs(NEIGHBOURS) do
            local m = mixAt(i + d[1], (j + d[2]) * FILL_SUB)
            if m then return m end
        end
        return nil
    end)
    for _, q in ipairs(pieces) do
        local c = comps[compOf[q.k] or 0]
        if c then
            local l = c.hpieces
            if not l then l = {}; c.hpieces = l end
            l[#l + 1] = q
        end
    end
end

-- pts = { {x, y, kind, step}, ... } in canvas pixels
-- phx, phy (optional): where the grid lines of the field lie, modulo the cell size. With them the cells sit at
-- the same places whichever points are there, so a blob built again for the same spots has the same shape.
local function buildGeometry(pts, R, phx, phy)
    local cs = max(R / 3, 4)
    local minx, miny, maxx, maxy = 1e9, 1e9, -1e9, -1e9
    for _, p in ipairs(pts) do
        if p[1] < minx then minx = p[1] end
        if p[1] > maxx then maxx = p[1] end
        if p[2] < miny then miny = p[2] end
        if p[2] > maxy then maxy = p[2] end
    end
    -- a point with no neighbour close by (a lone icon) gets a smaller blob: 50% instead of 70% of the standard size
    local loneR = R * 5 / 7
    do
        local g, gs = {}, R * 2
        for _, p in ipairs(pts) do
            local k = floor(p[1] / gs) * 100003 + floor(p[2] / gs)
            local t = g[k]
            if not t then t = {}; g[k] = t end
            t[#t + 1] = p
        end
        for _, p in ipairs(pts) do
            local cx, cy, lone = floor(p[1] / gs), floor(p[2] / gs), true
            for dx = -1, 1 do
                for dy = -1, 1 do
                    local t = g[(cx + dx) * 100003 + cy + dy]
                    if t and lone then
                        for _, q in ipairs(t) do
                            if q ~= p and (q[1] - p[1]) ^ 2 + (q[2] - p[2]) ^ 2 <= gs * gs then lone = false; break end
                        end
                    end
                end
            end
            p.r = lone and loneR or R
        end
    end
    local x0, y0 = minx - R, miny - R
    if phx and phy then
        x0 = floor((x0 - phx) / cs) * cs + phx
        y0 = floor((y0 - phy) / cs) * cs + phy
    end
    local ni = ceil((maxx + R - x0) / cs) + 1
    local nj = ceil((maxy + R - y0) / cs) + 1

    local field, hs, hw = {}, {}, {}
    local hasHeat = false
    for _, p in ipairs(pts) do
        local ci, cj = (p[1] - x0) / cs, (p[2] - y0) / cs
        local pr = p.r or R
        local pR2 = pr * pr
        local prc = ceil(pr / cs)
        for i = max(0, floor(ci) - prc), min(ni - 1, ceil(ci) + prc) do
            for j = max(0, floor(cj) - prc), min(nj - 1, ceil(cj) + prc) do
                local dx, dy = (i - ci) * cs, (j - cj) * cs
                local d2 = (dx * dx + dy * dy) / pR2
                if d2 < 1 then
                    local v = 1 - d2
                    local k = i * nj + j
                    field[k] = (field[k] or 0) + v * v
                    if p[4] then
                        hasHeat = true
                        local w = v * v
                        if not hw[k] or w > hw[k] then hw[k], hs[k] = w, p[4] end
                    end
                end
            end
        end
    end

    local T = BLOB_T
    local cellSeen, active, inside, segs = {}, {}, {}, {}
    local full, edgeList = {}, {}   -- cells completely inside; cells the outline crosses (filled up to the outline)
    local function cellPoly(ci, cj, v00, v10, v11, v01)
        local xs = { x0 + ci * cs, x0 + (ci + 1) * cs, x0 + (ci + 1) * cs, x0 + ci * cs }
        local ys = { y0 + cj * cs, y0 + cj * cs, y0 + (cj + 1) * cs, y0 + (cj + 1) * cs }
        local vs = { v00, v10, v11, v01 }
        local poly = {}
        for n = 1, 4 do
            local m = n % 4 + 1
            local va, vb = vs[n], vs[m]
            if va >= T then poly[#poly + 1] = xs[n]; poly[#poly + 1] = ys[n] end
            if (va >= T) ~= (vb >= T) then
                local t = (T - va) / (vb - va)
                poly[#poly + 1] = xs[n] + (xs[m] - xs[n]) * t
                poly[#poly + 1] = ys[n] + (ys[m] - ys[n]) * t
            end
        end
        return poly
    end
    local activeList = {}
    for k in pairs(field) do
        local i, j = floor(k / nj), k % nj
        for ci = i - 1, i do
            for cj = j - 1, j do
                if ci >= 0 and cj >= 0 and ci < ni - 1 and cj < nj - 1 then
                    local ck = ci * nj + cj
                    if not cellSeen[ck] then
                        cellSeen[ck] = true
                        local v00 = field[ci * nj + cj] or 0
                        local v10 = field[(ci + 1) * nj + cj] or 0
                        local v01 = field[ci * nj + cj + 1] or 0
                        local v11 = field[(ci + 1) * nj + cj + 1] or 0
                        local mask = (v00 >= T and 1 or 0) + (v10 >= T and 2 or 0) + (v11 >= T and 4 or 0) + (v01 >= T and 8 or 0)
                        if mask ~= 0 then
                            active[ck] = true
                            activeList[#activeList + 1] = ck
                            if (v00 + v10 + v01 + v11) / 4 >= T then inside[ck] = true end
                            if mask == 15 then
                                full[ck] = true
                            else
                                edgeList[#edgeList + 1] = { k = ck, i = ci, j = cj, x = x0 + ci * cs, y = y0 + cj * cs, cs = cs, mask = mask,
                                    poly = cellPoly(ci, cj, v00, v10, v11, v01), avgIn = inside[ck],
                                    yl = y0 + (cj + (T - v00) / ((v01 - v00) ~= 0 and (v01 - v00) or 1e-9)) * cs,    -- crossing on the left edge
                                    yr = y0 + (cj + (T - v10) / ((v11 - v10) ~= 0 and (v11 - v10) or 1e-9)) * cs,    -- right edge
                                    xt = x0 + (ci + (T - v00) / ((v10 - v00) ~= 0 and (v10 - v00) or 1e-9)) * cs,    -- top edge
                                    xb = x0 + (ci + (T - v01) / ((v11 - v01) ~= 0 and (v11 - v01) or 1e-9)) * cs }   -- bottom edge
                            end
                            local sg = SEGTAB[mask]
                            if sg then
                                -- every crossed cell edge gets one integer id (shared by the two cells next to it)
                                local function eid(e)
                                    if e == "T" then return (ci * nj + cj) * 2 end
                                    if e == "B" then return (ci * nj + cj + 1) * 2 end
                                    if e == "L" then return (ci * nj + cj) * 2 + 1 end
                                    return ((ci + 1) * nj + cj) * 2 + 1
                                end
                                for _, e in ipairs(sg) do
                                    segs[#segs + 1] = { ck, eid(e[1]), eid(e[2]) }
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    table.sort(activeList)

    -- islands = connected groups of active cells
    local compOf, comps = {}, {}
    for _, start in ipairs(activeList) do
        if not compOf[start] then
            local c = { cellIn = {}, segs = {}, rects = {}, x0 = x0, y0 = y0, cs = cs, nj = nj, np = 0,
                kinds = { 0, 0, 0, 0 } }
            comps[#comps + 1] = c
            local idx = #comps
            local stack = { start }
            compOf[start] = idx
            while #stack > 0 do
                local cur = table.remove(stack)
                if inside[cur] then c.cellIn[cur] = true end
                for _, d in ipairs({ -nj - 1, -nj, -nj + 1, -1, 1, nj - 1, nj, nj + 1 }) do
                    local nk = cur + d
                    if active[nk] and not compOf[nk] then
                        compOf[nk] = idx
                        stack[#stack + 1] = nk
                    end
                end
            end
        end
    end
    -- outline: chain the little segments into polylines and drop points that do not bend the line
    local edgeCache = {}
    local function edgePt(id)
        local p = edgeCache[id]
        if p then return p end
        local k = floor(id / 2)
        local i, j = floor(k / nj), k % nj
        local vA = field[k] or 0
        if id % 2 == 0 then
            local vB = field[(i + 1) * nj + j] or 0
            p = { x0 + (i + (T - vA) / (vB - vA)) * cs, y0 + j * cs }
        else
            local vB = field[i * nj + j + 1] or 0
            p = { x0 + i * cs, y0 + (j + (T - vA) / (vB - vA)) * cs }
        end
        edgeCache[id] = p
        return p
    end
    local perComp = {}
    for _, sg in ipairs(segs) do
        local idx = compOf[sg[1]]
        if idx then
            local l = perComp[idx]
            if not l then l = {}; perComp[idx] = l end
            l[#l + 1] = sg
        end
    end
    -- heat map: a cell takes the step of the quest that is strongest at its corners
    local cst = {}
    local function cellStep(i, j)
        if not hasHeat then return nil end
        local ck = i * nj + j
        local v = cst[ck]
        if v == nil then
            local bw
            v = false
            for _, k in ipairs({ ck, ck + nj, ck + 1, ck + nj + 1 }) do
                local w = hw[k]
                if w and (not bw or w > bw) then bw, v = w, hs[k] end
            end
            cst[ck] = v
        end
        return v or nil
    end
    for idx, list in pairs(perComp) do
        local segs2 = outlineSegments(list, edgePt)
        if hasHeat then
            for _, sg in ipairs(segs2) do
                sg[5] = cellStep(floor(((sg[1] + sg[3]) / 2 - x0) / cs), floor(((sg[2] + sg[4]) / 2 - y0) / cs))
            end
        end
        comps[idx].segs = segs2
    end

    -- fill: merge cells into rectangles
    local used = {}
    for j = 0, nj - 2 do
        for i = 0, ni - 2 do
            local k = i * nj + j
            if full[k] and not used[k] then
                local st = cellStep(i, j)
                local w = 1
                while i + w <= ni - 2 and full[(i + w) * nj + j] and not used[(i + w) * nj + j] and cellStep(i + w, j) == st do w = w + 1 end
                local h, grow = 1, true
                while grow and j + h <= nj - 2 do
                    for x = i, i + w - 1 do
                        local kk = x * nj + j + h
                        if not full[kk] or used[kk] or cellStep(x, j + h) ~= st then grow = false; break end
                    end
                    if grow then h = h + 1 end
                end
                for x = i, i + w - 1 do
                    for y = j, j + h - 1 do used[x * nj + y] = true end
                end
                local c = comps[compOf[k]]
                if c then c.rects[#c.rects + 1] = { x0 + i * cs, y0 + j * cs, x0 + (i + w) * cs, y0 + (j + h) * cs, st } end
            end
        end
    end

    for _, q in ipairs(edgePieces(edgeList, nj, nil)) do
        local c = comps[compOf[q.k] or 0]
        if c then
            local l = c.pieces
            if not l then l = {}; c.pieces = l end
            l[#l + 1] = q
        end
    end
    -- the cells the outline crosses belong to their island too (drawn whole if quads cannot be bent)
    for _, e in ipairs(edgeList) do
        local c = comps[compOf[e.k] or 0]
        if c then
            local l = c.edges
            if not l then l = {}; c.edges = l end
            l[#l + 1] = e
        end
    end

    if hasHeat then
        for _, c in ipairs(comps) do c.heat = true end
        buildFill(comps, compOf, full, edgeList, pts, R, x0, y0, cs, ni, nj)
    end
    local G = { comps = comps, compOf = compOf, x0 = x0, y0 = y0, cs = cs, nj = nj, ni = ni }

    -- centre of every island, kinds of quests in it, and the spawn point closest to the centre
    local sums = {}
    for _, p in ipairs(pts) do
        local c = comps[G.compOf[floor((p[1] - x0) / cs) * nj + floor((p[2] - y0) / cs)] or 0]
        if c then
            local s = sums[c]
            if not s then s = { 0, 0, 0 }; sums[c] = s end
            s[1], s[2], s[3] = s[1] + p[1], s[2] + p[2], s[3] + 1
            local kd = p[3] or 3
            c.kinds[kd] = c.kinds[kd] + 1
            c.np = c.np + 1
        end
    end
    for c, s in pairs(sums) do
        c.cx, c.cy = s[1] / s[3], s[2] / s[3]
    end
    for _, c in ipairs(comps) do
        if not c.cx then
            local sx, sy, sn = 0, 0, 0
            for k in pairs(c.cellIn) do
                sx = sx + x0 + (floor(k / nj) + 0.5) * cs
                sy = sy + y0 + (k % nj + 0.5) * cs
                sn = sn + 1
            end
            c.cx, c.cy = sn > 0 and sx / sn or x0, sn > 0 and sy / sn or y0
        end
        c.ix, c.iy = c.cx, c.cy
    end
    for _, p in ipairs(pts) do
        local c = comps[G.compOf[floor((p[1] - x0) / cs) * nj + floor((p[2] - y0) / cs)] or 0]
        if c then
            local d = (p[1] - c.cx) ^ 2 + (p[2] - c.cy) ^ 2
            if not c._bd or d < c._bd then c._bd = d; c.ix, c.iy = p[1], p[2] end
        end
    end
    return G
end

-- which island of this geometry contains the point (pixels)?
local function compAt(G, x, y)
    local ci, cj = floor((x - G.x0) / G.cs), floor((y - G.y0) / G.cs)
    local idx = G.compOf[ci * G.nj + cj]
    if idx then return idx end
    for dx = -1, 1 do
        for dy = -1, 1 do
            idx = G.compOf[(ci + dx) * G.nj + cj + dy]
            if idx then return idx end
        end
    end
    -- nothing close: nearest island
    local best, bd = nil, 1e18
    for i, c in ipairs(G.comps) do
        local d = (c.cx - x) ^ 2 + (c.cy - y) ^ 2
        if d < bd then best, bd = i, d end
    end
    return best
end

-- The signature does not depend on the order of the points: Questie lists its icons in another order after it
-- redraws them (the same spots), and that must not build the blobs again (the costly part of a scan).
local geomCache, geomSerial = {}, 0
local function cachedGeometry(key, pts, R, W, H)
    local s1, s2 = 0, 0
    for _, p in ipairs(pts) do
        local v = (floor(p[1]) * 7919 + floor(p[2]) * 104729 + ((p[4] or 99) + 1000) * 13 + (p[3] or 0) * 3) % 1000003
        s1 = (s1 + v) % 2147483647
        s2 = (s2 + v * v) % 2147483647
    end
    local sig = format("%d|%d|%d|%d|%d|%d", floor(W), floor(H), floor(R), #pts, s1, s2)
    local e = geomCache[key]
    if e and e.sig == sig then return e.G end
    local t0 = debugprofilestop and debugprofilestop()
    local G = buildGeometry(pts, R)
    QQ.geomBuilds = (QQ.geomBuilds or 0) + 1   -- for /blob debug
    QQ.geomMs = t0 and (debugprofilestop() - t0) or nil
    geomSerial = geomSerial + 1
    for _, c in ipairs(G.comps) do c.gid = geomSerial end
    geomCache[key] = { sig = sig, G = G }
    return G
end


ns.heatColor = heatColor
ns.heatStep = heatStep
ns.buildGeometry = buildGeometry
ns.compAt = compAt
ns.cachedGeometry = cachedGeometry
