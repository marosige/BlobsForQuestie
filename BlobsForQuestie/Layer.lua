-- Blobs for Questie: Layer
local ADDON_NAME, ns = ...
local QQ = ns.QQ
local floor, ceil, max, min, sqrt = math.floor, math.ceil, math.max, math.min, math.sqrt
local format = string.format
local pairs, ipairs, type, tostring, tonumber = pairs, ipairs, type, tostring, tonumber
local DEFAULTS = ns.DEFAULTS
local S = ns.S
local applyHide = ns.applyHide
local eachFrame = ns.eachFrame
local heatColor = ns.heatColor
local isHidden = ns.isHidden
local nearOpacity = ns.nearOpacity
local reportError = ns.reportError
local wantHide = ns.wantHide

---------------------------------------------------------------------------
-- The blob layer (a child of the map canvas, so it moves and scales with the map)
---------------------------------------------------------------------------

local KIND_KEYS = { "kill", "loot", "other", "available" }   -- "available" never gets a blob; it only follows the near / mouse rules

-- the blob takes the colour of the kind that dominates inside it (kill, loot, or everything else)
local function colorOf(kinds)
    if ns.DB.colorMode ~= "kind" then return ns.DB.colorAll end
    local best = 1
    if kinds[2] > kinds[best] then best = 2 end
    if kinds[3] > kinds[best] then best = 3 end
    local key = KIND_KEYS[best]
    return ns.DB.colors[key] or DEFAULTS.colors[key]
end

-- loot colour of a drop-rate band (101 poor, 102 mid, 103 good): three colours you choose
local LOOT_BAND_KEYS = { [101] = "lootLow", [102] = "lootMid", [103] = "loot" }
local function lootBandColor(band)
    local key = LOOT_BAND_KEYS[band] or "loot"
    return ns.DB.colors[key] or DEFAULTS.colors[key]
end

-- colour of one spot of a blob (see heatStep)
-- Spots near the player inside a merged blob carry NEAR_ADD on top of their class (NEAR_ONLY where the colour
-- has no class): the blob fades there (the "blob under the icons" strength) instead of splitting in two.
local NEAR_ADD, NEAR_ONLY = 10000, 999999
local function areaColor(h, col)
    if not h then return col end
    local k
    if h >= 5000 then
        k = nearOpacity() / 100
        if h == NEAR_ONLY then return { col[1], col[2], col[3], k } end
        h = h - NEAR_ADD
    end
    local c
    if ns.DB.colorMode == "kind" then
        if h >= 100 then c = lootBandColor(h) else c = ns.DB.colors[KIND_KEYS[h]] or col end
    elseif ns.DB.colorMode == "level" then c = heatColor(h)
    else c = col end
    if k then return { c[1], c[2], c[3], k } end
    return c
end

-- colour of a mix { class1, class2, share of class2 } (see buildFill)
local function mixColor(m, col)
    local c1 = areaColor(m[1], col)
    if not m[2] or m[3] <= 0 then return c1 end
    local c2, t = areaColor(m[2], col), m[3]
    local a1, a2 = c1[4] or 1, c2[4] or 1
    return { c1[1] + (c2[1] - c1[1]) * t, c1[2] + (c2[2] - c1[2]) * t, c1[3] + (c2[3] - c1[3]) * t, a1 + (a2 - a1) * t }
end

-- a fill piece with a left-to-right colour gradient (newer clients take colour objects, older ones numbers)
local function paintGradient(t, c1, c2, a)
    local a1, a2 = a * (c1[4] or 1), a * (c2[4] or 1)
    if c1[1] == c2[1] and c1[2] == c2[2] and c1[3] == c2[3] and a1 == a2 then
        if t._grad then t._grad = nil; t:SetVertexColor(1, 1, 1, 1) end
        t:SetColorTexture(c1[1], c1[2], c1[3], a1)
        return
    end
    t:SetColorTexture(1, 1, 1, 1)
    t._grad = true
    if CreateColor and t.SetGradient and pcall(t.SetGradient, t, "HORIZONTAL", CreateColor(c1[1], c1[2], c1[3], a1), CreateColor(c2[1], c2[2], c2[3], a2)) then return end
    if t.SetGradientAlpha and pcall(t.SetGradientAlpha, t, "HORIZONTAL", c1[1], c1[2], c1[3], a1, c2[1], c2[2], c2[3], a2) then return end
    t._grad = nil
    t:SetVertexColor(1, 1, 1, 1)
    t:SetColorTexture((c1[1] + c2[1]) / 2, (c1[2] + c2[2]) / 2, (c1[3] + c2[3]) / 2, (a1 + a2) / 2)
end

-- Questie's FakeShow/FakeHide are slow, so changes are queued and applied within a small time budget per frame.
local pending, pendingN = {}, 0
local function queueHide(fr, hide)
    if fr._qqHide ~= hide or (isHidden(fr) and true or false) ~= hide then
        fr._qqHide = hide
        if not fr._qqQueued then
            fr._qqQueued = true
            pendingN = pendingN + 1
            pending[pendingN] = fr
        end
    end
end
-- "focus" state: QQ.focusQuest (a quest picked in the quest log) or QQ.focusKey (the objective pointed at)
local function objectiveKeyOf(fr)
    local d = fr.data
    if type(d) ~= "table" or not d.Id or d.ObjectiveIndex == nil then return nil end
    return d.Id .. ":" .. d.ObjectiveIndex
end
local function setBlobShown(blob, show)
    local fq, fk = QQ.focusQuest, QQ.focusKey   -- only that quest's / that objective's icons stay
    for _, it in ipairs(blob.items) do
        if fq then
            queueHide(it.f, not (it.f.data and it.f.data.Id == fq))
        elseif fk then
            queueHide(it.f, objectiveKeyOf(it.f) ~= fk)
        else
            queueHide(it.f, not (show or it.near or it.f._qqCur))
        end
    end
end
local function flushPending(budgetMs)
    if pendingN == 0 then return end
    local clock = debugprofilestop
    local t0 = clock and clock() or 0
    local done = 0
    for i = 1, pendingN do
        local fr = pending[i]
        fr._qqQueued = nil
        applyHide(fr, fr._qqHide and true or false)
        pending[i] = nil
        done = i
        if clock and clock() - t0 > budgetMs then break end
    end
    if done < pendingN then
        local n = 0
        for i = done + 1, pendingN do n = n + 1; pending[n] = pending[i]; pending[i] = nil end
        pendingN = n
    else
        pendingN = 0
    end
end
local function bboxOf(c)
    if not c.bx1 then
        local x1, y1, x2, y2 = 1e9, 1e9, -1e9, -1e9
        for _, r in ipairs(c.rects) do
            if r[1] < x1 then x1 = r[1] end
            if r[2] < y1 then y1 = r[2] end
            if r[3] > x2 then x2 = r[3] end
            if r[4] > y2 then y2 = r[4] end
        end
        c.bx1, c.by1, c.bx2, c.by2 = x1, y1, x2, y2
    end
    return c.bx1, c.by1, c.bx2, c.by2
end

local function lookBlob(f, blob)
    local c = blob.c
    if not c.t1 then return end
    local hot = QQ.hover[blob.key] and true or false
    local a = ns.DB.blobAlpha
    local la = min(1, a * 3)   -- the outline follows the blob strength too
    if not S.continent and not blob._focus then   -- a focused blob stays a plain blob: only the focus slider dims it
        if blob.near then
            local k = nearOpacity() / 100
            a, la = a * k, la * k
        elseif hot and not (f.mask and (ns.DB.mouseOpacity or 0) == 0) then
            -- no mask: the blob under the cursor just gets paler (the setting, or a default dimming)
            local k = (ns.DB.mouseOpacity or 0) > 0 and ns.DB.mouseOpacity / 100 or 0.35
            a, la = a * k, la * k
        end
    end
    a = min(a, 0.7)
    local col = c.col
    local heatOn = ns.DB.colorMode ~= "single" or c.heat
    for i = c.t1, c.t2 do
        local t = f.tex[i]
        if heatOn and t._mL then
            paintGradient(t, mixColor(t._mL, col), mixColor(t._mR or t._mL, col), a)
        else
            local hc = heatOn and areaColor(t._h, col) or col
            if t._grad then t._grad = nil; t:SetVertexColor(1, 1, 1, 1) end
            t:SetColorTexture(hc[1], hc[2], hc[3], a * (hc[4] or 1))
        end
    end
    local er, eg, eb = (col[1] + 1) / 2, (col[2] + 1) / 2, (col[3] + 1) / 2
    if f._cx and (f._cr or 0) > 1 and not S.continent then
        -- outline segments dissolve around the mouse like the fill does (clear inside half the radius)
        local rad, cx, cy = f._cr, f._cx, f._cy
        for i = c.l1, c.l2 do
            local dx, dy = f.lmx[i] - cx, f.lmy[i] - cy
            local d = sqrt(dx * dx + dy * dy) / rad
            local k = 1
            if d <= 0.5 then k = 0 elseif d < 1 then local t = (d - 0.5) * 2; k = t * t * (3 - 2 * t) end
            local op = (ns.DB.mouseOpacity or 0) / 100
            if op > 0 then k = op + (1 - op) * k end   -- the outline keeps that much of its strength inside the circle
            local ln = f.lines[i]
            if heatOn and ln._h then
                local hc = areaColor(ln._h, col)
                ln:SetColorTexture((hc[1] + 1) / 2, (hc[2] + 1) / 2, (hc[3] + 1) / 2, la * k)
            else
                ln:SetColorTexture(er, eg, eb, la * k)
            end
        end
    else
        for i = c.l1, c.l2 do
            local ln = f.lines[i]
            if heatOn and ln._h then
                local hc = areaColor(ln._h, col)
                ln:SetColorTexture((hc[1] + 1) / 2, (hc[2] + 1) / 2, (hc[3] + 1) / 2, la)
            else
                ln:SetColorTexture(er, eg, eb, la)
            end
        end
    end
end

local MASK_PATH = "Interface\\AddOns\\BlobsForQuestie\\Icons\\mask.png"

local function ensureHeat()
    if ns.heat then return ns.heat end
    local canvas = WorldMapFrame:GetCanvas()
    ns.heat = CreateFrame("Frame", "BlobsForQuestieBlobs", canvas)
    ns.heat:SetAllPoints(canvas)
    ns.heat:SetFrameLevel((canvas:GetFrameLevel() or 1) + 30)
    ns.heat:EnableMouse(false)
    if ns.heat.CreateMaskTexture then
        local m = ns.heat:CreateMaskTexture()
        if type(m) == "table" and m.SetTexture then
            m:SetTexture(MASK_PATH, "CLAMP", "CLAMP")   -- CLAMP: outside the picture the opaque edge continues
            m:SetSize(1, 1)
            m:SetPoint("TOPLEFT", ns.heat, "TOPLEFT", -50, 50)
            ns.heat.mask = m
        end
    end
    ns.heat.tex, ns.heat.lines = {}, {}
    do   -- can textures be bent (vertex offsets)? then the fill follows the outline exactly
        local probe = ns.heat:CreateTexture()
        ns.heat.voOK = type(probe) == "table" and probe.SetVertexOffset ~= nil
        probe:Hide()
    end
    ns.heat.lmx, ns.heat.lmy = {}, {}   -- midpoint of every outline segment (for the fade around the mouse)
    ns.heat:SetScript("OnUpdate", function(self, elapsed) QQ:HoverTick(self, elapsed) end)
    ns.heat:Hide()
    return ns.heat
end

-- Put the blob layer above the map's own overlays (explored-area textures) but below the Questie icons:
-- find the highest frame level among the canvas children that are not Questie icons or ours, and the
-- lowest level of the Questie icons. Done rarely; the child list can be long.
local function raiseLayer(f)
    local now = GetTime and GetTime() or 0
    if f._lvlT and now - f._lvlT < 5 then return end
    f._lvlT = now
    local canvas = f:GetParent()
    if not canvas or not canvas.GetChildren then return end
    local top = canvas:GetFrameLevel() or 1
    local qmin
    local kids = { canvas:GetChildren() }
    local others = {}
    for i = 1, #kids do
        local k = kids[i]
        if k ~= f and type(k) == "table" and k.GetFrameLevel then
            local lv = k:GetFrameLevel()
            if type(lv) == "number" then
                -- Questie icons sit inside HereBeDragons pin frames (pin.icon); those pins decide the ceiling
                local ic = k.icon
                local nm = type(ic) == "table" and ic.GetName and ic:GetName()
                if nm and nm:find("^Questie") then
                    if not qmin or lv < qmin then qmin = lv end
                else
                    others[#others + 1] = lv
                end
            end
        end
    end
    for i = 1, #others do
        local lv = others[i]
        if lv > top and (not qmin or lv < qmin) then top = lv end
    end
    local want = top + 1
    if qmin and want >= qmin then want = qmin - 1 end
    want = min(want, 9990)
    if (f:GetFrameLevel() or 0) ~= want then f:SetFrameLevel(want) end
end

local function drawBlobs(f, list, W, H)
    local es = f:GetEffectiveScale()
    if type(es) ~= "number" or es <= 0 then es = 1 end
    local function snap(v) return floor(v * es + 0.5) / es end
    local ti, li = 0, 0

    local function drawOne(blob)
        local c = blob.c
        c.col = colorOf(c.kinds)
        c.t1 = ti + 1
        local graded = (ns.DB.colorMode ~= "single" or c.heat) and c.hrects
        for _, r in ipairs(graded or c.rects) do
            local x1, y1 = snap(max(r[1], 0)), snap(max(r[2], 0))
            local x2, y2 = snap(min(r[3], W)), snap(min(r[4], H))
            if x2 > x1 and y2 > y1 then
                ti = ti + 1
                local t = f.tex[ti]
                if not t then
                    t = f:CreateTexture(nil, "ARTWORK")
                    if f.mask and t.AddMaskTexture then t:AddMaskTexture(f.mask) end
                    f.tex[ti] = t
                end
                if t._vo then for v = 1, 4 do t:SetVertexOffset(v, 0, 0) end; t._vo = nil end
                t:ClearAllPoints()
                t:SetSize(x2 - x1, y2 - y1)
                t:SetPoint("TOPLEFT", f, "TOPLEFT", x1, -y1)
                if graded then t._h, t._mL, t._mR = nil, r[5], r[6] else t._h, t._mL, t._mR = r[5], nil, nil end
                t:Show()
            end
        end
        -- the cells the outline crosses: filled exactly up to the outline (quads bent with vertex offsets)
        local function newTex()
            ti = ti + 1
            local t = f.tex[ti]
            if not t then
                t = f:CreateTexture(nil, "ARTWORK")
                if f.mask and t.AddMaskTexture then t:AddMaskTexture(f.mask) end
                f.tex[ti] = t
            end
            t:ClearAllPoints()
            return t
        end
        if f.voOK then
            for _, q in ipairs((graded and c.hpieces) or c.pieces or {}) do
                -- the quad's box, then each corner moved onto its point (1 upper left, 2 lower left, 3 upper right, 4 lower right; y up)
                local bx1, by1 = snap(min(q[1], q[7])), snap(min(q[2], q[4]))
                local bx2, by2 = snap(max(q[3], q[5])), snap(max(q[6], q[8]))
                if bx2 - bx1 < 0.5 then bx2 = bx1 + 0.5 end
                if by2 - by1 < 0.5 then by2 = by1 + 0.5 end
                local t = newTex()
                t:SetSize(bx2 - bx1, by2 - by1)
                t:SetPoint("TOPLEFT", f, "TOPLEFT", bx1, -by1)
                t:SetVertexOffset(1, q[1] - bx1, by1 - q[2])
                t:SetVertexOffset(3, q[3] - bx2, by1 - q[4])
                t:SetVertexOffset(4, q[5] - bx2, by2 - q[6])
                t:SetVertexOffset(2, q[7] - bx1, by2 - q[8])
                t._vo = true
                if graded then t._h, t._mL, t._mR = nil, q.mL, q.mR else t._h, t._mL, t._mR = nil, nil, nil end
                t:Show()
            end
        else
            for _, e in ipairs(c.edges or {}) do
                if e.avgIn then   -- no bent quads in this client: the whole cell, as before
                    local t = newTex()
                    if t._vo then for v = 1, 4 do t:SetVertexOffset(v, 0, 0) end; t._vo = nil end
                    local x1, y1 = snap(e.x), snap(e.y)
                    t:SetSize(snap(e.x + e.cs) - x1, snap(e.y + e.cs) - y1)
                    t:SetPoint("TOPLEFT", f, "TOPLEFT", x1, -y1)
                    if graded then t._h, t._mL, t._mR = nil, e.mL, e.mR else t._h, t._mL, t._mR = nil, nil, nil end
                    t:Show()
                end
            end
        end
        c.t2 = ti

        c.l1 = li + 1
        for _, sg in ipairs(c.segs) do
            li = li + 1
            local ln = f.lines[li]
            if not ln then
                ln = f:CreateLine(nil, "OVERLAY")
                f.lines[li] = ln
            end
            f.lmx[li], f.lmy[li] = (sg[1] + sg[3]) / 2, (sg[2] + sg[4]) / 2
            ln._h = sg[5]
            ln:SetThickness(2)
            ln:SetStartPoint("TOPLEFT", f, sg[1], -sg[2])
            ln:SetEndPoint("TOPLEFT", f, sg[3], -sg[4])
            ln:Show()
        end
        c.l2 = li
    end
    for _, blob in ipairs(list) do
        if blob.noDraw or (blob.near and not S.continent and nearOpacity() <= 0) then
            blob.c.t1 = nil   -- within the detail distance the icons are shown, no blob
        else
            local ti0, li0 = ti, li
            local ok, err = pcall(drawOne, blob)
            if not ok then
                reportError("drawing a blob: " .. tostring(err))
                ti, li = ti0, li0
                blob.c.t1 = nil
            end
        end
    end
    for i = ti + 1, #f.tex do f.tex[i]:Hide() end
    for i = li + 1, #f.lines do f.lines[i]:Hide() end
end

local function updateLayer(list, W, H)
    local f = ensureHeat()
    raiseLayer(f)
    if S.continent and f._cx then QQ:ClearCursor() end
    local parts = {}
    for i, b in ipairs(list) do parts[i] = b.key .. (b.near and "n" or "f") .. (b.noDraw and "x" or "") .. (b.c.gid or 0) end
    table.sort(parts)
    local sig = format("%s|%d|%d|%s|", tostring(S.viewMap), floor(W), floor(H), (nearOpacity() > 0 and "p" or "")) .. table.concat(parts, ";")
    local nowT = GetTime and GetTime() or 0
    if f._dsig ~= sig or nowT - (f._dT or 0) > 10 then   -- redraw on change, and every 10 s as a safety net
        f._dsig = nil
        f._dT = nowT
        local ok, err = pcall(drawBlobs, f, list, W, H)
        if ok then f._dsig = sig else reportError("drawing blobs: " .. tostring(err)) end
    end
    f._W, f._H = W, H
    for _, b in ipairs(list) do lookBlob(f, b) end
    f:Show()
end

local function hideLayer()
    if QQ.ClearCursor then QQ:ClearCursor() end
    QQ.blobs = nil
    QQ.hover = {}
    if ns.heat then
        ns.heat._cx = nil
        ns.heat._dsig = nil
        ns.heat:Hide()
    end
end

---------------------------------------------------------------------------
-- Cursor: icons within the detail distance of the mouse appear, the blob under them fades
---------------------------------------------------------------------------

-- The detail distance also applies around the mouse cursor: icons of far blobs that lie within it show as
-- plain Questie icons (Questie's own tooltips), and the blob under them fades.

-- The mask is a picture that is opaque everywhere except a soft hole in the middle.
-- Hole fully clear inside 0.5 x radius, fully opaque again at 1 x radius (the picture's hole is 0.1..0.2 of its width).
local function aimMask(f, px, py, rad)
    local m = f.mask
    if not m then return end
    m:ClearAllPoints()
    if px and (ns.DB.mouseOpacity or 0) == 0 and rad and rad > 1 then
        local size = rad * 5
        m:SetSize(size, size)
        m:SetPoint("CENTER", f, "TOPLEFT", px, -py)
    else
        m:SetSize(1, 1)
        m:SetPoint("TOPLEFT", f, "TOPLEFT", -50, 50)   -- parked outside: the edge of the picture is opaque
    end
end

local applyFocus
local function refocusOthers()   -- available / turn-in icons follow the focus
    eachFrame(function(f, d)
        if (d.Type == "available" or d.Type == "complete") and not f.miniMapIcon then
            local want = wantHide(f) and true or false
            if (f._qqHid or false) ~= want then applyHide(f, want) end
        end
    end)
end
local function clearCursor(f)
    if QQ.focusKey or QQ.hoverObj then applyFocus(f, nil) end
    aimMask(f, nil)
    f._cx, f._cy, f._hovKey, f._shift = nil, nil, nil, nil
    QQ.hover = {}
    local blobs = QQ.blobs
    if not blobs then return end
    for _, b in ipairs(blobs) do
        local any = false
        for _, it in ipairs(b.items) do
            if it.f._qqCur then it.f._qqCur = nil; any = true end
        end
        if any then setBlobShown(b, b.near) end
        if any or b._lineAff then
            b._lineAff = nil
            lookBlob(f, b)
        end
    end
end

function QQ:ClearCursor() if ns.heat then clearCursor(ns.heat) end end

-- The objective of the Questie icon under the mouse ("questId:objectiveIndex"), nil if none: all places of that
-- objective show their icons while it is hovered, whether the character or the mouse is near them or not.
local function hoveredObjective()
    local focus
    if GetMouseFoci then
        local list = GetMouseFoci()
        focus = type(list) == "table" and list[1] or nil
    elseif GetMouseFocus then
        focus = GetMouseFocus()
    end
    local d = type(focus) == "table" and focus.data
    if type(d) ~= "table" or focus.miniMapIcon or not d.Id or d.ObjectiveIndex == nil then return nil end
    if d.Type == "available" or d.Type == "complete" then return nil end
    return d.Id .. ":" .. d.ObjectiveIndex
end

-- Pointing at an icon or picking a quest in the log: the blobs holding that objective / quest turn pale (the
-- "focus" slider), and in "show only it" / the quest log the other Questie icons hide. Blobs never hide.
function applyFocus(f, key, shift)
    QQ.hoverObj = key
    QQ.focusKey = shift and key or nil   -- Shift held: only that objective's icons stay
    local fq, fo = QQ.focusQuest, QQ.hoverObj
    for _, b in ipairs(QQ.blobs or {}) do
        local has = false
        if fq then
            for _, it in ipairs(b.items) do
                if it.f.data and it.f.data.Id == fq then has = true; break end
            end
        elseif fo then
            for _, it in ipairs(b.items) do
                if objectiveKeyOf(it.f) == fo then has = true; break end
            end
        end
        local foc = has or nil
        setBlobShown(b, b.near)
        if (b._focus or false) ~= (foc or false) then
            b._focus = foc
            lookBlob(f, b)
        end
    end
    refocusOthers()
end


-- The quest picked in the quest log next to the map: the one pointed at, else the one whose details are open.
local function questLogFocus()
    if not (ns.DB.shiftFocus or ns.DB.logDetails) or type(QuestMapFrame) ~= "table" then return nil end
    if ns.DB.shiftFocus and IsShiftKeyDown and IsShiftKeyDown() then   -- Shift needed: no accidental hiding
        local focus
        if GetMouseFoci then
            local list = GetMouseFoci()
            focus = type(list) == "table" and list[1] or nil
        elseif GetMouseFocus then
            focus = GetMouseFocus()
        end
        local fr, depth = focus, 0
        while type(fr) == "table" and depth < 8 do
            if type(fr.questID) == "number" and fr.questID > 0 then
                -- a quest log entry: it sits somewhere under the quest log frame
                local up, d2 = fr, 0
                while type(up) == "table" and d2 < 12 do
                    if up == QuestMapFrame then return fr.questID end
                    up = up.GetParent and up:GetParent() or nil
                    d2 = d2 + 1
                end
                return nil
            end
            fr = fr.GetParent and fr:GetParent() or nil
            depth = depth + 1
        end
    end
    if ns.DB.logDetails then
        -- Shift inverts the filter: while it is held, an open quest's details do not hide anything
        if ns.DB.shiftFocus and IsShiftKeyDown and IsShiftKeyDown() then return false end
        local df = QuestMapFrame.DetailsFrame
        if type(df) == "table" and df.IsShown and df:IsShown() then
            local id
            if QuestMapFrame_GetFocusedQuestID then id = QuestMapFrame_GetFocusedQuestID() end
            if (type(id) ~= "number" or id <= 0) and C_QuestLog and C_QuestLog.GetSelectedQuest then id = C_QuestLog.GetSelectedQuest() end
            if type(id) == "number" and id > 0 then return id end
        end
    end
    return nil
end

function QQ:HoverTick(f, elapsed)
    flushPending(3)
    f._t = (f._t or 0) + elapsed
    if f._t < 0.1 then return end
    f._t = 0
    local blobs = QQ.blobs
    if not blobs or S.continent or not f:IsVisible() then return end
    local now = GetTime and GetTime() or 0

    -- the quest log has gaps between its rows: keep the last quest for a moment so the map does not flip back and forth
    local qf = questLogFocus()
    if qf == false then
        qf = nil; f._qfLast = nil   -- Shift over open details: show everything right away
    elseif qf then
        f._qfLast, f._qfT = qf, now
    elseif f._qfLast and now - (f._qfT or 0) < 0.3 then
        qf = f._qfLast
    else
        f._qfLast = nil
    end
    if qf ~= QQ.focusQuest then
        QQ.focusQuest = qf
        applyFocus(f, f._hovKey, f._shift)
    end

    local sc = WorldMapFrame and WorldMapFrame.ScrollContainer
    local inside = not (sc and MouseIsOver and not MouseIsOver(sc))
    local w, h = f:GetWidth(), f:GetHeight()
    local left, top = f:GetLeft(), f:GetTop()
    local around = ns.DB.showNearMouse and (ns.DB.objMouse or 0) > 0
    local shift = (ns.DB.shiftFocus and IsShiftKeyDown and IsShiftKeyDown()) and true or false
    local hovKey = inside and (ns.DB.hoverShow or shift) and hoveredObjective() or nil
    if hovKey then
        f._hkT = now
    elseif inside and f._hovKey and now - (f._hkT or 0) < 0.2 then
        hovKey = f._hovKey   -- the pointer slipped off the icon for a moment: no flicker
    end
    if inside and (around or hovKey or f._hovKey) and left and top and w and w > 1 and h and h > 1 and f._W then
        f._hotT = now
        local cx, cy = GetCursorPosition()
        local s = f:GetEffectiveScale()
        local px = ((cx / s) - left) / w * f._W
        local py = (top - (cy / s)) / h * f._H
        local rad = around and (ns.DB.objMouse or 0) / 100 * f._W or 0     -- distances are % of the map width: canvas pixels
        local moved = (not f._cx) or ((px - f._cx) ^ 2 + (py - f._cy) ^ 2) > 25 or f._cr ~= rad or f._cdirty or f._hovKey ~= hovKey or f._shift ~= shift
        if not moved then return end
        local keyChanged = f._hovKey ~= hovKey or f._shift ~= shift
        f._cx, f._cy, f._cr, f._cdirty, f._hovKey, f._shift = px, py, rad, nil, hovKey, shift
        if keyChanged then applyFocus(f, hovKey, shift and hovKey ~= nil) end
        if QQ.hoverObj or QQ.focusQuest then aimMask(f, nil) else aimMask(f, px, py, rad) end   -- focus: no fading hole
        local r2 = rad * rad
        local W, H = f._W, f._H
        for _, b in ipairs(blobs) do
            if not b.near then
                local any, changed = false, false
                for _, it in ipairs(b.items) do
                    local fr = it.f
                    local dx, dy = (fr.x or 0) / 100 * W - px, (fr.y or 0) / 100 * H - py
                    local on = rad > 0 and (dx * dx + dy * dy) <= r2
                    if not on and hovKey then   -- the same objective as the hovered icon
                        local d = fr.data
                        on = d and d.Id and d.ObjectiveIndex ~= nil and (d.Id .. ":" .. d.ObjectiveIndex) == hovKey
                    end
                    if on then any = true end
                    if (fr._qqCur or false) ~= on then fr._qqCur = on or nil; changed = true end
                end
                if changed then setBlobShown(b, false) end
                -- the outline fade follows the cursor: redo the blobs under or just left by the circle
                local bx1, by1, bx2, by2 = bboxOf(b.c)
                local hit = px > bx1 - rad and px < bx2 + rad and py > by1 - rad and py < by2 + rad
                if any ~= (QQ.hover[b.key] or false) then
                    QQ.hover[b.key] = any or nil
                    lookBlob(f, b)
                elseif hit or b._lineAff then
                    lookBlob(f, b)
                end
                b._lineAff = hit or nil
            end
        end
    elseif f._cx and (now - (f._hotT or 0)) > 0.3 then
        clearCursor(f)
    end
end


ns.KIND_KEYS = KIND_KEYS
ns.lootBandColor = lootBandColor
ns.NEAR_ADD = NEAR_ADD
ns.NEAR_ONLY = NEAR_ONLY
ns.setBlobShown = setBlobShown
ns.lookBlob = lookBlob
ns.drawBlobs = drawBlobs
ns.updateLayer = updateLayer
ns.hideLayer = hideLayer
ns.refocusOthers = refocusOthers
