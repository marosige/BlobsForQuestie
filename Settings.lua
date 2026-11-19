-- Blobs for Questie: Settings
local ADDON_NAME, ns = ...
local QQ = ns.QQ
local floor, ceil, max, min, sqrt = math.floor, math.ceil, math.max, math.min, math.sqrt
local format = string.format
local pairs, ipairs, type, tostring, tonumber = pairs, ipairs, type, tostring, tonumber
local CW = ns.CW
local GOLD = ns.GOLD
local GUI_H = ns.GUI_H
local GUI_W = ns.GUI_W
local ICONS = ns.ICONS
local KIND_KEYS = ns.KIND_KEYS
local PAD = ns.PAD
local attachTip = ns.attachTip
local greenRange = ns.greenRange
local hGradient = ns.hGradient
local heatColor = ns.heatColor
local initDB = ns.initDB
local kindIcon = ns.kindIcon
local lootBandColor = ns.lootBandColor
local makeCheck = ns.makeCheck
local makeHeader = ns.makeHeader
local makeHint = ns.makeHint
local makeSegmented = ns.makeSegmented
local makeSlider = ns.makeSlider
local makeSwatch = ns.makeSwatch
local makeSwitch = ns.makeSwitch
local paintAvail = ns.paintAvail
local panelChecks = ns.panelChecks
local questKey = ns.questKey
local questieIcon = ns.questieIcon
local safeScan = ns.safeScan
local setActive = ns.setActive
local solid = ns.solid
local widgets = ns.widgets

function QQ:RefreshGUI()
    for _, fn in ipairs(panelChecks) do fn() end
    if not ns.gui then return end
    for _, fn in ipairs(widgets) do fn() end
end

local currentTab = 1

local function buildGUI()
    local f = CreateFrame("Frame", "BlobsForQuestieGUI", UIParent)
    f:SetSize(GUI_W, GUI_H)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)

    local bg = solid(f, "BACKGROUND", 0.05, 0.07, 0.10, 0.97)
    bg:SetAllPoints()
    local function edge(point, w, h)
        local t = solid(f, "BORDER", 1, 0.8, 0.3, 0.9)
        t:SetPoint(point)
        t:SetSize(w, h)
    end
    edge("TOPLEFT", GUI_W, 2); edge("BOTTOMLEFT", GUI_W, 2); edge("TOPLEFT", 2, GUI_H); edge("TOPRIGHT", 2, GUI_H)

    -- header: logo, name, master switch, close ------------------------------------------------
    local logo = f:CreateTexture(nil, "ARTWORK")
    logo:SetTexture(ICONS .. "icon.png")
    logo:SetSize(30, 30)
    logo:SetPoint("TOPLEFT", 14, -10)
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", logo, "RIGHT", 8, 0)
    title:SetText("Blobs for Questie")
    local ver = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ver:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 6, 1)
    ver:SetText("v" .. QQ.version)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    local sw = makeSwitch(f, function() return ns.DB.enabled end, function(v) ns.DB.enabled = v end,
        "Turns the addon on or off. Off: Questie's map looks as it does without it.")
    sw:SetPoint("TOPRIGHT", -40, -17)

    -- tabs: three equal boxes; the chosen one opens into the framed panel below it ----------------
    local TAB_TOP, TAB_H = -50, 34
    local PANEL_TOP = TAB_TOP - TAB_H
    local PX0, PW = PAD - 8, CW + 16
    local PANEL_BG = { 0.11, 0.12, 0.15 }
    local gpanel = CreateFrame("Frame", nil, f)
    gpanel:SetPoint("TOPLEFT", PX0, PANEL_TOP)
    gpanel:SetPoint("BOTTOMRIGHT", -(GUI_W - PX0 - PW), 54)
    local pbgT = solid(gpanel, "BACKGROUND", PANEL_BG[1], PANEL_BG[2], PANEL_BG[3], 1)
    pbgT:SetAllPoints()
    local function border(parent, a, thick)
        local function side(p1, p2, w, h)
            local t = solid(parent, "BORDER", 1, 0.8, 0.3, a)
            t:SetPoint(p1); t:SetPoint(p2)
            if w then t:SetWidth(w) else t:SetHeight(h) end
            return t
        end
        return side("TOPLEFT", "TOPRIGHT", nil, thick), side("TOPLEFT", "BOTTOMLEFT", thick), side("TOPRIGHT", "BOTTOMRIGHT", thick), side("BOTTOMLEFT", "BOTTOMRIGHT", nil, thick)
    end
    border(gpanel, 0.55, 1)

    local pagesBox = CreateFrame("Frame", nil, f)
    pagesBox:SetPoint("TOPLEFT", 0, PANEL_TOP - 10)
    pagesBox:SetPoint("BOTTOMRIGHT", 0, 58)
    pagesBox:SetFrameLevel((gpanel:GetFrameLevel() or 1) + 2)
    local pages, tabs = {}, {}
    local function showTab(i)
        currentTab = i
        for n, pg in ipairs(pages) do pg:SetShown(n == i) end
        for n, t in ipairs(tabs) do
            local on = n == i
            if on then
                t.bg:SetColorTexture(PANEL_BG[1], PANEL_BG[2], PANEL_BG[3], 1)
                t.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
            else
                t.bg:SetColorTexture(0.06, 0.07, 0.09, 1)
                t.text:SetTextColor(0.62, 0.62, 0.62)
            end
            for _, b in ipairs(t.onB) do b:SetShown(on) end
            for _, b in ipairs(t.offB) do b:SetShown(not on) end
            t.gap:SetShown(on)
        end
    end
    local GAPW = 4
    local tw = (PW - GAPW * 2) / 3
    for i, name in ipairs({ "Blobs", "Questie icons", "Available quests" }) do
        local t = CreateFrame("Button", nil, f)
        t:SetSize(tw, TAB_H)
        t:SetPoint("TOPLEFT", PX0 + (i - 1) * (tw + GAPW), TAB_TOP)
        t:SetFrameLevel((gpanel:GetFrameLevel() or 1) + 1)
        t.bg = solid(t, "BACKGROUND", 0.06, 0.07, 0.09, 1)
        t.bg:SetAllPoints()
        t.text = t:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        do   -- a bit smaller than the large font
            local face, _, flags
            if type(GameFontNormal) == "table" and GameFontNormal.GetFont then face, _, flags = GameFontNormal:GetFont() end
            if face and t.text.SetFont then t.text:SetFont(face, 14, flags) end
        end
        t.text:SetPoint("CENTER", 0, 0)
        t.text:SetText(name)
        -- chosen: bright frame on top and sides, open at the bottom; not chosen: a dim frame all round
        local top, left, right = border(t, 0.95, 2)
        t.onB = { top, left, right }
        local a1, a2, a3, a4 = border(t, 0.3, 1)
        t.offB = { a1, a2, a3, a4 }
        -- covers the panel's top line under the chosen tab, so the two read as one
        t.gap = solid(t, "OVERLAY", PANEL_BG[1], PANEL_BG[2], PANEL_BG[3], 1)
        t.gap:SetPoint("BOTTOMLEFT", 2, -1)
        t.gap:SetPoint("BOTTOMRIGHT", -2, -1)
        t.gap:SetHeight(2)
        local hl = t:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.07)
        t:SetScript("OnClick", function() showTab(i) end)
        tabs[i] = t
        local pg = CreateFrame("Frame", nil, pagesBox)
        pg:SetAllPoints()
        pages[i] = pg
    end
    -- everything greys out while the addon is off
    widgets[#widgets + 1] = function() pagesBox:SetAlpha(ns.DB.enabled and 1 or 0.45) end

    local X = PAD
    local function check(p, y, key, label, tip, after, icon, invert)
        return makeCheck(p, X, y, label, tip,
            function() if invert then return not ns.DB[key] end return ns.DB[key] end,
            function(v) if invert then v = not v end ns.DB[key] = v; if after then after() end end,
            nil, icon)
    end
    local function redraw() if ns.heat then ns.heat._dsig = nil end end

    -- 1: Blobs --------------------------------------------------------------------------------
    local p = pages[1]
    local PH = 84
    local box = CreateFrame("Frame", nil, p)
    box:SetPoint("TOPLEFT", X, -2)
    box:SetSize(CW, PH)
    local pbg = box:CreateTexture(nil, "BACKGROUND")
    pbg:SetTexture(ICONS .. "mapbg.png")
    pbg:SetTexCoord(0, 1, 0.1, 0.1 + (PH / CW) * 2)   -- a strip of the map texture, not stretched
    pbg:SetAllPoints()
    local pedge = solid(box, "BORDER", 0.55, 0.45, 0.28, 0.6)
    pedge:SetPoint("BOTTOMLEFT"); pedge:SetPoint("BOTTOMRIGHT"); pedge:SetHeight(1)
    local blobs = {}
    for i = 1, 5 do
        local b = {}
        b.fill = box:CreateTexture(nil, "ARTWORK")
        b.fill:SetTexture(ICONS .. "blob.png")
        b.fill:SetSize(92, 54)
        b.line = box:CreateTexture(nil, "ARTWORK", nil, 1)
        b.line:SetTexture(ICONS .. "blobline.png")
        b.line:SetAllPoints(b.fill)
        if i % 2 == 0 then b.fill:SetTexCoord(1, 0, 0, 1); b.line:SetTexCoord(1, 0, 0, 1) end
        b.icon = box:CreateTexture(nil, "OVERLAY")
        b.icon:SetSize(18, 18)
        b.cap = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        -- the same spot as a slice of one merged blob (Grouping: Merged blobs)
        b.sfill = box:CreateTexture(nil, "ARTWORK")
        b.sfill:SetTexture(ICONS .. "blobwide.png")
        b.sline = box:CreateTexture(nil, "ARTWORK", nil, 1)
        b.sline:SetTexture(ICONS .. "blobwideline.png")
        b.sline:SetAllPoints(b.sfill)
        blobs[i] = b
    end
    local LEVEL_CAPS = { "trivial", "easy", "your level", "hard", "very hard" }
    local WW = CW - 30   -- width of the merged blob
    widgets[#widgets + 1] = function()
        local mode = ns.DB.colorMode
        local gm = ns.DB.groupMode
        local layout = (gm == "quest") and "quest" or ((gm == "all" or mode == "single") and "all" or "color")
        local merged = layout ~= "quest"
        local n = mode == "level" and 5 or 3
        local drop = mode == "kind"   -- the strip always shows a good, a mid and a poor loot spot (same color when shading is off)
        local kinds, caps = { 1, 2, 3 }, nil
        if mode == "level" then caps = LEVEL_CAPS end
        if drop then n, kinds, caps = 5, { 1, 2, 2, 2, 3 }, { "kill", "loot 90%", "loot 55%", "loot 15%", "other" } end
        local a, la = min(ns.DB.blobAlpha, 0.7), min(1, ns.DB.blobAlpha * 3)
        local gr = greenRange()
        local steps = { -(gr + 1), -3, 0, 3, 5 }
        local dy = (mode == "level" or drop) and 7 or 0
        local cols = {}
        for i = 1, n do
            if drop then
                if ns.DB.lootByDrop and (i >= 2 and i <= 4) then cols[i] = lootBandColor(({ [2] = 103, [3] = 102, [4] = 101 })[i])
                else cols[i] = ns.DB.colors[KIND_KEYS[kinds[i]]] end
            elseif mode == "kind" then cols[i] = ns.DB.colors[KIND_KEYS[i]]
            elseif mode == "level" then cols[i] = heatColor(steps[i])
            else cols[i] = ns.DB.colorAll end
        end
        for i, b in ipairs(blobs) do
            local shown = i <= n
            b.fill:SetShown(shown and not merged); b.line:SetShown(shown and not merged)
            b.sfill:SetShown(shown and merged); b.sline:SetShown(shown and merged)
            b.icon:SetShown(shown and mode == "kind")
            b.cap:SetShown(shown and caps ~= nil)
            if shown and mode == "kind" then
                local path = questieIcon(kindIcon(kinds[i]))
                if path then b.icon:SetTexture(path) end
            end
            if shown then
                local tgt
                if merged then
                    local sw = WW / n
                    b.sfill:ClearAllPoints()
                    if layout == "all" then
                        b.sfill:SetSize(sw, (mode == "level" or drop) and 58 or 72)
                        b.sfill:SetPoint("LEFT", box, "LEFT", 15 + (i - 1) * sw, dy)
                        b.sfill:SetTexCoord((i - 1) / n, i / n, 0, 1)
                        b.sline:SetTexCoord((i - 1) / n, i / n, 0, 1)
                    else   -- unified by color: every color is a whole blob of its own
                        b.sfill:SetSize(sw * 0.94, (mode == "level" or drop) and 50 or 62)
                        b.sfill:SetPoint("CENTER", box, "LEFT", 15 + (i - 0.5) * sw, dy)
                        b.sfill:SetTexCoord(0, 1, 0, 1)
                        b.sline:SetTexCoord(0, 1, 0, 1)
                    end
                    tgt = b.sfill
                else
                    b.fill:ClearAllPoints()
                    if mode == "level" or drop then b.fill:SetSize(80, 46) else b.fill:SetSize(92, 54) end
                    b.fill:SetPoint("CENTER", box, "LEFT", CW * (i - 0.5) / n, dy)
                    tgt = b.fill
                end
                b.icon:ClearAllPoints(); b.icon:SetPoint("CENTER", tgt, "CENTER", 0, 1)
                b.cap:ClearAllPoints(); b.cap:SetPoint("TOP", tgt, "BOTTOM", 0, -2)
                if caps then b.cap:SetText(caps[i]) end
                local c = cols[i]
                local f, l = merged and b.sfill or b.fill, merged and b.sline or b.line
                local function light(x) return { (x[1] + 1) / 2, (x[2] + 1) / 2, (x[3] + 1) / 2 } end
                local graded = false
                if layout == "all" then
                    -- the parts flow into each other: each slice runs from the middle of its left neighbour's colour to the right one's
                    local cl, cr = cols[i - 1] or c, cols[i + 1] or c
                    local c1 = { (cl[1] + c[1]) / 2, (cl[2] + c[2]) / 2, (cl[3] + c[3]) / 2 }
                    local c2 = { (cr[1] + c[1]) / 2, (cr[2] + c[2]) / 2, (cr[3] + c[3]) / 2 }
                    f:SetVertexColor(1, 1, 1); l:SetVertexColor(1, 1, 1)
                    graded = hGradient(f, c1, c2, a) and hGradient(l, light(c1), light(c2), la)
                end
                if not graded then
                    f:SetVertexColor(c[1], c[2], c[3])
                    local lc = light(c)
                    l:SetVertexColor(lc[1], lc[2], lc[3])
                end
                if graded then f:SetAlpha(1); l:SetAlpha(1) else f:SetAlpha(a); l:SetAlpha(la) end   -- a gradient carries its own alpha
            end
        end
    end

    makeSlider(p, X + 4, -PH - 12, CW - 8, "Strength",
        "How strongly the blobs show on the map.",
        0.10, 0.80, 0.02, function(v) return format("%d%%", floor(v * 100 + 0.5)) end,
        function() return ns.DB.blobAlpha end, function(v) ns.DB.blobAlpha = v end)

    makeHeader(p, X, -PH - 62, "Color")
    makeSegmented(p, X, -PH - 84, CW, {
        { "level", "By quest level", "Colored like quest titles in the game, from grey to red." },
        { "single", "One color", "All blobs share one color." },
        { "kind", "By objective", "Kill, loot and other objectives each get their own color." },
    }, function() return ns.DB.colorMode end, function(v) ns.DB.colorMode = v; redraw() end)

    -- the colour pickers of the selected mode
    local rowY = -PH - 118
    local rowSingle = CreateFrame("Frame", nil, p)
    rowSingle:SetPoint("TOPLEFT", X, rowY); rowSingle:SetSize(CW, 20)
    local sl1 = rowSingle:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sl1:SetPoint("LEFT", 4, 0); sl1:SetText("Blob color")
    makeSwatch(rowSingle, 84, -1, "all", "Blob color")
    local lootEntry = {}   -- the plain loot color: only without drop-rate shading
    local rowKind = CreateFrame("Frame", nil, p)
    rowKind:SetPoint("TOPLEFT", X, rowY); rowKind:SetSize(CW, 20)
    for i, key in ipairs({ "kill", "loot", "other" }) do
        local x0 = 4 + (i - 1) * 140
        local ic = rowKind:CreateTexture(nil, "ARTWORK")
        ic:SetSize(18, 18); ic:SetPoint("LEFT", x0, 0)
        if i == 2 then lootEntry[#lootEntry + 1] = ic end
        local path = questieIcon(kindIcon(i))
        if path then ic:SetTexture(path) end
        local fs = rowKind:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        fs:SetPoint("LEFT", x0 + 22, 0)
        fs:SetText(({ "Kill", "Loot", "Other" })[i])
        local sw = makeSwatch(rowKind, x0 + 70, -1, key, ({ "Kill", "Loot", "Other" })[i])
        if i == 2 then lootEntry[#lootEntry + 1] = fs; lootEntry[#lootEntry + 1] = sw end
    end
    local rowLevel = makeHint(p, X + 4, rowY - 3, "Colored like quest titles in the game.")
    widgets[#widgets + 1] = function()
        rowSingle:SetShown(ns.DB.colorMode == "single")
        rowKind:SetShown(ns.DB.colorMode == "kind")
        rowLevel:SetShown(ns.DB.colorMode == "level")
    end

    local ldrop = check(p, -PH - 142, "lootByDrop", "Shade loot by drop rate",
        "Colors loot blobs by how often the item drops: good (80% and up), mid (30-80%) or poor (under 30%). Choose the three colors on the right.", redraw)
    local dropHold = CreateFrame("Frame", nil, p)
    dropHold:SetPoint("TOPLEFT", X, 0); dropHold:SetSize(CW, 1)
    for i, r in ipairs({ { "loot", "good", "80% and up" }, { "lootMid", "mid", "30-80%" }, { "lootLow", "poor", "under 30%" } }) do
        local x0 = CW - 252 + (i - 1) * 84
        local fs = dropHold:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", x0, -PH - 146); fs:SetText(r[2])
        makeSwatch(dropHold, x0 + 33, -PH - 143, r[1], "Loot, " .. r[2] .. " drop rate (" .. r[3] .. ")")
    end
    widgets[#widgets + 1] = function()
        ldrop:SetShown(ns.DB.colorMode == "kind")
        local on = ns.DB.colorMode == "kind" and ns.DB.lootByDrop
        dropHold:SetShown(on)
        for _, w in ipairs(lootEntry) do w:SetShown(ns.DB.colorMode == "kind" and not on) end   -- the three colors below replace it
    end

    makeHeader(p, X, -PH - 176, "Grouping")
    makeSegmented(p, X, -PH - 198, CW, {
        { "quest", "One blob per quest", "Each quest objective gets its own blob, even where blobs overlap." },
        { "all", "Unified", "Objectives close together merge into one blob. Each part keeps its own color." },
        { "color", "Unified by color", "Objectives of the same color merge into one blob: the same difficulty, or the same objective type (loot by drop rate)." },
    }, function() return ns.DB.groupMode end, function(v) ns.DB.groupMode = v end)
    check(p, -PH - 236, "blobsWorld", "Blobs on the continent and world map",
        "Shows one blob per zone on these maps. Off: no blobs there.", redraw)
    check(p, -PH - 262, "minimapBlobs", "Blobs on the minimap",
        "Turns far objectives on the minimap into blobs too, with the same colors, grouping and filters. Off: the minimap stays as Questie draws it.")

    local DEMO_SCALE = 2.4   -- demo strips: pixels per percent of the map width

    -- a strip of map for the demo pictures
    local function mapStrip(parent, v0)
        local b = CreateFrame("Frame", nil, parent)
        b:SetPoint("TOPLEFT", X, -2)
        b:SetSize(CW, PH)
        local t = b:CreateTexture(nil, "BACKGROUND")
        t:SetTexture(ICONS .. "mapbg.png")
        t:SetTexCoord(0, 1, v0, v0 + (PH / CW) * 2)
        t:SetAllPoints()
        return b
    end

    -- 2: Questie icons -----------------------------------------------------------------------
    p = pages[2]
    -- preview: the same blob twice, Questie's icons shown around the character (left) and around the mouse (right)
    do
        local box2 = mapStrip(p, 0.5)
        local killIcon = questieIcon(kindIcon(1))
        local ICON_POS = { { -86, -4 }, { -68, 16 }, { -50, -16 }, { -30, 6 }, { -12, -18 }, { 6, 16 }, { 22, -4 }, { 40, -20 }, { 56, 12 }, { 74, -8 }, { 90, 8 } }
        local function scene(cx, marker, key, distKey, caption)
            local sc = {}
            local function blobTex(layer, file)
                local t = box2:CreateTexture(nil, "ARTWORK", nil, layer)
                t:SetTexture(ICONS .. file)
                t:SetSize(224, 84)
                t:SetPoint("CENTER", box2, "LEFT", cx, 3)
                return t
            end
            sc.fill = blobTex(1, "blob.png")
            sc.line = blobTex(2, "blobline.png")
            sc.icons = {}
            for i, pos in ipairs(ICON_POS) do
                local t = box2:CreateTexture(nil, "OVERLAY")
                t:SetSize(14, 14)
                t:SetPoint("CENTER", box2, "LEFT", cx + pos[1], 3 + pos[2])
                if killIcon then t:SetTexture(killIcon) end
                sc.icons[i] = t
            end
            local m = box2:CreateTexture(nil, "OVERLAY", nil, 2)
            m:SetTexture(ICONS .. marker)
            m:SetSize(22, 22)
            if marker == "cursor.png" then m:SetPoint("TOPLEFT", box2, "LEFT", cx - 3, 3 + 3) else m:SetPoint("CENTER", box2, "LEFT", cx, 3) end
            local cap = box2:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            cap:SetPoint("BOTTOM", box2, "BOTTOMLEFT", cx, 4)
            cap:SetText(caption)
            widgets[#widgets + 1] = function()
                local c = ns.DB.colorMode == "kind" and ns.DB.colors.kill or (ns.DB.colorMode == "level" and heatColor(0)) or ns.DB.colorAll
                local a, la = min(ns.DB.blobAlpha, 0.7), min(1, ns.DB.blobAlpha * 3)
                local all = ns.DB.revealAll and true or false
                local on = not all and ns.DB[key] and true or false
                local rad = min(max((ns.DB[distKey] or 0) * DEMO_SCALE, 4), 110)   -- the strip shows about half of a map
                sc.fill:SetVertexColor(c[1], c[2], c[3])
                sc.line:SetVertexColor((c[1] + 1) / 2, (c[2] + 1) / 2, (c[3] + 1) / 2)
                sc.fill:SetAlpha(a); sc.line:SetAlpha(la)   -- the blob stays under the icons, as on the map
                for i, pos in ipairs(ICON_POS) do
                    sc.icons[i]:SetShown(all or (on and (pos[1] * pos[1] + pos[2] * pos[2]) <= rad * rad))
                end
            end
        end
        scene(CW * 0.25, "player.png", "showNearPlayer", "objPlayer", "around your character")
        scene(CW * 0.75, "cursor.png", "showNearMouse", "objMouse", "around the mouse")
    end
    makeHeader(p, X, -PH - 12, "Show Questie's own icons")
    local HALF = floor((CW - 28 - 24) / 2)
    local function plainCheck(y, key, label, tip, after)
        local cb = check(p, y, key, label, tip, after)
        cb.label:SetFontObject("GameFontNormal")
        cb.label:SetWidth(240)
        cb:SetHitRectInsets(0, -240, 0, 0)
        return cb
    end
    plainCheck(-PH - 34, "revealAll", "Everywhere",
        "Shows every Questie icon instead of blobs. The radius no longer matters.")
    -- each of the two has its own radius, in line with its checkbox
    local SLX = X + 196
    local SLW = CW - 196 - 52
    local cbP = plainCheck(-PH - 60, "showNearPlayer", "Around your character",
        "Shows Questie's icons instead of blobs near your character.")
    local cbM = plainCheck(-PH - 86, "showNearMouse", "Around the mouse",
        "Shows Questie's icons instead of blobs around the mouse pointer.", function() if QQ.ClearCursor then QQ:ClearCursor() end end)
    local function radius(y, key, tip, flag)
        local sl = makeSlider(p, SLX, y - 6, SLW, "Radius", tip, 1, 40, 1,
            function(v) return format("%d%%", v) end,
            function() return ns.DB[key] end, function(v) ns.DB[key] = v end, true)
        widgets[#widgets + 1] = function() setActive(sl, ns.DB[flag] and not ns.DB.revealAll and true or false) end
        return sl
    end
    radius(-PH - 60, "objPlayer", "Radius around your character, in percent of the map width.", "showNearPlayer")
    radius(-PH - 86, "objMouse", "Radius around the mouse, in percent of the map width.", "showNearMouse")

    -- two columns: what to hide, and what happens when you point at something
    local COLW = floor((CW - 16) / 2)
    local X2 = X + COLW + 16
    local function colCheck(x, y, key, label, tip, after)
        return makeCheck(p, x, y, label, tip,
            function() return ns.DB[key] end,
            function(v) ns.DB[key] = v; if after then after() end end, COLW)
    end
    makeHeader(p, X, -PH - 118, "Hide Questie icons", COLW)
    colCheck(X, -PH - 140, "hideOtherZones", "From neighbouring zones",
        "Zone maps show only the icons of that zone, not those of the zones around it. Cities inside the zone stay.")
    colCheck(X, -PH - 176, "hideDungeonQuests", "Of dungeon quests on outdoor maps",
        "Hides the icons Questie draws at a dungeon entrance for quests that happen inside the dungeon.")

    makeHeader(p, X2, -PH - 118, "Mouse over", COLW)
    colCheck(X2, -PH - 140, "hoverShow", "Show every spot of an objective when pointing at it",
        "Point at a Questie icon on the map to see that objective's icons in every blob.", function() if QQ.ClearCursor then QQ:ClearCursor() end end)
    colCheck(X2, -PH - 176, "shiftFocus", "Hold Shift over an objective or quest to hide the rest",
        "Hold Shift while pointing at a Questie icon on the map or at a quest in the quest log: only that objective or quest keeps its icons. All other icons, quest givers and turn-ins hide. Blobs always stay. Shift + click on an icon opens that quest's details in the quest log.", function() if QQ.ClearCursor then QQ:ClearCursor() end end)
    colCheck(X2, -PH - 212, "logDetails", "Show only a quest's objectives while its details are open",
        "Shows only that quest's icons on the map as long as its details are open in the quest log. Hold Shift to show everything again.")

    -- 3: Available quests -------------------------------------------------------------------
    p = pages[3]
    local avail = questieIcon(Questie and Questie.ICON_TYPE_AVAILABLE)
    -- demo: available quests around the character and the mouse
    do
        local box3 = mapStrip(p, 0.3)
        local CY = PH / 2
        local PX, MX = CW * 0.28, CW * 0.74
        local function ring(x)
            local t = box3:CreateTexture(nil, "BORDER")
            t:SetTexture(ICONS .. "splat.png")
            t:SetPoint("CENTER", box3, "TOPLEFT", x, -CY)
            t:SetVertexColor(1, 1, 1, 0.18)
            return t
        end
        local ringP, ringM = ring(PX), ring(MX)
        local ICONS3 = {   -- x, y, kind (n = normal, d = started by a drop, p = PvP, r = repeatable, g = dungeon), level step
            { 22, -18, "g", -99 }, { 48, 14, "d", 0 }, { 74, -6, "n", 3 }, { 96, 22, "r", -3 }, { 108, -24, "n", 0 },
            { 140, 12, "n", 5 }, { 150, -14, "d", -3 }, { 176, 24, "p", 0 }, { 196, -4, "n", -99 }, { 222, -26, "r", 3 },
            { 244, 16, "g", 0 }, { 268, -10, "d", 5 }, { 290, 24, "n", -3 }, { 306, -22, "n", 3 }, { 344, 12, "r", 0 },
            { 356, -16, "n", -3 }, { 340, -19, "n", 0 }, { 309, -5, "n", 3 }, { 372, 26, "d", 5 }, { 394, -2, "p", -99 }, { 412, 20, "g", 3 }, { 430, -20, "n", 3 },
        }
        local pathOf = {
            n = avail, d = avail, g = avail,
            p = questieIcon(Questie and Questie.ICON_TYPE_PVPQUEST) or avail,
            r = questieIcon(Questie and Questie.ICON_TYPE_REPEATABLE) or avail,
        }
        local loot = questieIcon(Questie and Questie.ICON_TYPE_LOOT)
        local shown = {}
        for n, q in ipairs(ICONS3) do
            local t = box3:CreateTexture(nil, "ARTWORK")
            t:SetSize(16, 16)
            t:SetPoint("CENTER", box3, "TOPLEFT", q[1], -(CY + q[2]))
            if pathOf[q[3]] then t:SetTexture(pathOf[q[3]]) end
            local badge
            if q[3] == "d" and loot then   -- a small bag: started by a dropped item
                badge = box3:CreateTexture(nil, "OVERLAY")
                badge:SetSize(9, 9)
                badge:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", 3, -2)
                badge:SetTexture(loot)
            end
            shown[n] = { t = t, badge = badge }
        end
        local pl = box3:CreateTexture(nil, "OVERLAY", nil, 2)
        pl:SetTexture(ICONS .. "player.png"); pl:SetSize(22, 22)
        pl:SetPoint("CENTER", box3, "TOPLEFT", PX, -CY)
        local cu = box3:CreateTexture(nil, "OVERLAY", nil, 2)
        cu:SetTexture(ICONS .. "cursor.png"); cu:SetSize(22, 22)
        cu:SetPoint("TOPLEFT", box3, "TOPLEFT", MX - 3, -(CY - 3))
        widgets[#widgets + 1] = function()
            local near = ns.DB.hideFarAvail and not ns.DB.revealAll and true or false
            local rp = ns.DB.showNearPlayer and (ns.DB.objPlayer or 0) * DEMO_SCALE or 0
            local rm = ns.DB.showNearMouse and (ns.DB.objMouse or 0) * DEMO_SCALE or 0
            ringP:SetShown(near and rp > 0); ringP:SetSize(rp * 2 + 1, rp * 2 + 1)
            ringM:SetShown(near and rm > 0); ringM:SetSize(rm * 2 + 1, rm * 2 + 1)
            local gr = greenRange()
            for n, q in ipairs(ICONS3) do
                local ok = not ((q[3] == "d" and ns.DB.hideItemStarts) or (q[3] == "p" and ns.DB.hidePvPQuests) or (q[3] == "r" and ns.DB.hideRepeatable) or (q[3] == "g" and ns.DB.hideDungeonAvail))
                if ok and near then
                    local dp = (q[1] - PX) ^ 2 + q[2] ^ 2
                    local dm = (q[1] - MX) ^ 2 + q[2] ^ 2
                    ok = (rp > 0 and dp <= rp * rp) or (rm > 0 and dm <= rm * rm)
                end
                local e = shown[n]
                e.t:SetShown(ok and true or false)
                if e.badge then e.badge:SetShown(ok and true or false) end
                local key = ns.DB.colorAvail and questKey(q[4] == -99 and -(gr + 1) or q[4]) or nil
                local path = key and avail or pathOf[q[3]]
                if path then e.t:SetTexture(path) end
                paintAvail(e.t, key)
            end
        end
    end
    makeHeader(p, X, -PH - 12, "Show")
    makeSegmented(p, X, -PH - 34, CW, {
        { false, "All", "Shows every available quest on every map." },
        { true, "Only nearby", "Shows available quests only near your character or the mouse, like objectives (see Questie icons). Hidden on the continent and world map." },
    }, function() return ns.DB.hideFarAvail and true or false end, function(v) ns.DB.hideFarAvail = v end)

    makeHeader(p, X, -PH - 76, "Include")
    check(p, -PH - 98, "hideItemStarts", "Quests started by a dropped item",
        "Quests that start from an item dropped by a monster or found in an object.", nil,
        questieIcon(Questie and Questie.ICON_TYPE_LOOT), true)
    check(p, -PH - 124, "hidePvPQuests", "PvP quests", "Battleground and other PvP quests.", nil,
        questieIcon(Questie and Questie.ICON_TYPE_PVPQUEST) or avail, true)
    check(p, -PH - 150, "hideRepeatable", "Repeatable quests", "Quests you can do again, such as dailies.", nil,
        questieIcon(Questie and Questie.ICON_TYPE_REPEATABLE) or avail, true)
    check(p, -PH - 176, "hideDungeonAvail", "Dungeon and raid quests",
        "Quests done inside a dungeon or raid.", nil, avail, true)

    makeHeader(p, X, -PH - 216, "Look")
    check(p, -PH - 238, "colorAvail", "Color the ! by difficulty",
        "Colors available quest icons like quest titles in the game.")
    local BAND_STEPS = { -99, -3, 0, 3, 5 }   -- grey, green, yellow, orange, red
    local samples = {}
    for i = 1, #BAND_STEPS do
        local t = p:CreateTexture(nil, "ARTWORK")
        t:SetSize(20, 20)
        t:SetPoint("TOPLEFT", X + CW - 22 * (#BAND_STEPS - i + 1), -PH - 240)
        if avail then t:SetTexture(avail) end
        samples[i] = t
    end
    widgets[#widgets + 1] = function()
        for i, t in ipairs(samples) do
            paintAvail(t, ns.DB.colorAvail and questKey(BAND_STEPS[i] == -99 and -(greenRange() + 1) or BAND_STEPS[i]) or nil)
        end
    end


    -- footer ----------------------------------------------------------------------------------
    local mm = makeCheck(f, PAD - 4, -(GUI_H - 34), "Minimap button",
        "Left-click: these settings. Right-click: addon on / off.",
        function() return not ns.DB.minimap.hide end,
        function(v)
            ns.DB.minimap.hide = not v
            local icon = LibStub and LibStub("LibDBIcon-1.0", true)
            if icon then if v then icon:Show("BlobsForQuestie") else icon:Hide("BlobsForQuestie") end end
        end, 130)
    makeCheck(f, PAD + 126, -(GUI_H - 34), "Map buttons",
        "Adds a round button under Questie's own button at the top left of the world map, with a small bar next to it: addon on / off, available quests, quests started by a drop, blob color and grouping.",
        function() return ns.DB.showPanel end,
        function(v) ns.DB.showPanel = v; QQ:ApplyPanel() end, 110)

    local function button(text, w, x, tip, onClick)
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(w, 22)
        b:SetPoint("BOTTOMRIGHT", x, 14)
        b:SetText(text)
        b:SetScript("OnClick", onClick)
        attachTip(b, text, tip)
        return b
    end
    local armed = false
    local def
    def = button("Defaults", 78, -PAD + 4, "Resets all settings to their defaults. Click twice to confirm.", function()
        if not armed then
            armed = true
            def:SetText("Sure?")
            if C_Timer and C_Timer.After then
                C_Timer.After(3, function() armed = false; def:SetText("Defaults") end)
            end
            return
        end
        armed = false
        def:SetText("Defaults")
        QQ:ResetDefaults()
        QQ:ApplyPanel()
        redraw()
        safeScan()
        QQ:RefreshGUI()
    end)
    button("Questie options", 120, -PAD - 78, "Questie's own settings: icon theme, sizes and which quests to show.", function()
        local ok, O = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieOptions")
        if ok and O and O.ToggleConfigWindow then O:ToggleConfigWindow() end
    end)

    showTab(currentTab)
    f:SetScript("OnShow", function() QQ:RefreshGUI() end)
    tinsert(UISpecialFrames, "BlobsForQuestieGUI")
    f:Hide()
    return f
end

function QQ:ToggleGUI()
    if not ns.DB then initDB() end
    if not ns.gui then ns.gui = buildGUI() end
    if ns.gui:IsShown() then ns.gui:Hide() else QQ:RefreshGUI(); ns.gui:Show() end
end


