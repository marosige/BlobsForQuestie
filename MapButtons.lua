-- Blobs for Questie: MapButtons
local ADDON_NAME, ns = ...
local QQ = ns.QQ
local floor, ceil, max, min, sqrt = math.floor, math.ceil, math.max, math.min, math.sqrt
local format = string.format
local pairs, ipairs, type, tostring, tonumber = pairs, ipairs, type, tostring, tonumber
local ICONS = ns.ICONS
local kindIcon = ns.kindIcon
local questColor = ns.questColor
local questieIcon = ns.questieIcon
local hGradient = ns.hGradient
local safeScan = ns.safeScan

---------------------------------------------------------------------------
-- Map buttons: a small box on the world map with the switches that matter while playing
---------------------------------------------------------------------------

local panelChecks = {}

-- the colour and grouping buttons step through their modes: left-click forward, right-click back
local STEP_HINT = "Click: next, right-click: back"
local function stepOf(button) return button == "RightButton" and -1 or 1 end

local function buildPanel()
    -- it sits at the top left of the world map, under Questie's own button
    local host = UIParent
    if type(WorldMapFrame) == "table" then
        host = type(WorldMapFrame.ScrollContainer) == "table" and WorldMapFrame.ScrollContainer or WorldMapFrame
    end
    local f = CreateFrame("Frame", "BlobsForQuestiePanel", host)
    local ARROW = 16   -- width of the fold arrow, right of the addon switch
    local function px(i) return ARROW + 8 + (i - 2) * 26 end   -- x of button i (the addon switch is the round button)
    local OPEN_W = ARROW + 8 + 4 * 26 + 20 + 6
    f:SetSize(OPEN_W, 28)
    f:SetFrameLevel(min((host:GetFrameLevel() or 1) + 500, 9000))   -- above the map's pins
    f:EnableMouse(true)
    f:SetScript("OnShow", function() for _, fn in ipairs(panelChecks) do fn() end end)

    -- the addon switch is a round map button in the stack under Questie's own (top left of the map)
    local KB = LibStub and LibStub("Krowi_WorldMapButtons-1.4", true)
    local main
    if KB and KB.Add and type(WorldMapFrame) == "table" and WorldMapFrame.GetCanvasContainer then
        main = KB:Add(nil, "BUTTON")   -- same stacking as Questie's button: the library keeps the order and the spacing
        main.krowi = KB
    else
        main = CreateFrame("Button", "BlobsForQuestieMapButton", host)
        main:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 8, 8)
    end
    main:SetSize(32, 32)
    main:SetFrameStrata("HIGH")   -- as Questie's own map button: above the map
    main:SetFrameLevel(max(main:GetFrameLevel() or 1, (host:GetFrameLevel() or 1) + 10))
    main:Show()
    local mbg = main:CreateTexture(nil, "BACKGROUND")
    mbg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    mbg:SetSize(25, 25); mbg:SetPoint("TOPLEFT", 2, -4)
    local mic = main:CreateTexture(nil, "ARTWORK")
    mic:SetTexture(ICONS .. "icon.png")
    mic:SetSize(22, 22); mic:SetPoint("TOPLEFT", 6, -5)
    local mbd = main:CreateTexture(nil, "OVERLAY")
    mbd:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    mbd:SetSize(54, 54); mbd:SetPoint("TOPLEFT")
    main:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
    main.Refresh = function() end
    main:SetScript("OnClick", function()
        ns.DB.enabled = not ns.DB.enabled
        safeScan()
        QQ:RefreshGUI()
        if GameTooltip:IsOwned(main) then main:GetScript("OnEnter")(main) end   -- the tooltip shows the new state
    end)
    main:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Blobs for Questie: " .. (ns.DB.enabled and "on" or "off"), 1, 1, 1)
        GameTooltip:Show()
    end)
    main:SetScript("OnLeave", function() GameTooltip:Hide() end)
    panelChecks[#panelChecks + 1] = function()
        mic:SetDesaturated(not ns.DB.enabled)
        mic:SetAlpha(ns.DB.enabled and 1 or 0.5)
    end
    f.main = main
    f:SetPoint("LEFT", main, "RIGHT", -4, 0)
    f:HookScript("OnShow", function() main:Show(); if main.krowi then main.krowi.SetPoints() end end)
    f:HookScript("OnHide", function() main:Hide(); if main.krowi then main.krowi.SetPoints() end end)

    local panelBtns = {}
    -- a rounded dark box behind the opened buttons
    local bar = CreateFrame("Frame", nil, f, "BackdropTemplate")
    bar:SetAllPoints(f)
    bar:SetFrameLevel(f:GetFrameLevel() or 1)
    if bar.SetBackdrop then
        bar:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        bar:SetBackdropColor(0.05, 0.07, 0.10, 0.8)
        bar:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.9)
    end
        -- icon switches: coloured = on, grey = off
    local function questieIcon(kind)
        local icType = Questie and kindIcon(kind)
        return icType and Questie.usedIcons and Questie.usedIcons[icType]
    end
    local function switch(i, texture, badge, title, onText, offText, isOn, toggle)
        local b = CreateFrame("Button", nil, f)
        b:SetSize(20, 20)
        b:SetPoint("LEFT", px(i), 0)
        panelBtns[i] = b
        local t = b:CreateTexture(nil, "ARTWORK")
        t:SetAllPoints()
        if texture then t:SetTexture(texture) end
        local bd
        if badge then   -- small ! in the lower right quarter
            bd = b:CreateTexture(nil, "OVERLAY")
            bd:SetSize(10, 10)
            bd:SetPoint("BOTTOMRIGHT", 2, -2)
            bd:SetTexture(badge)
        end
        b:SetScript("OnClick", function()
            toggle()
            safeScan()
            QQ:RefreshGUI()
            if GameTooltip:IsOwned(b) then b:GetScript("OnEnter")(b) end   -- the tooltip shows the new state
        end)
        b:SetScript("OnEnter", function(self)
            local on = isOn()
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(title .. ": " .. (on and "on" or "off"), 1, 1, 1)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        panelChecks[#panelChecks + 1] = function()
            local on = isOn()
            t:SetDesaturated(not on)
            t:SetAlpha(on and 1 or 0.45)
            if bd then bd:SetDesaturated(not on); bd:SetAlpha(on and 1 or 0.45) end
        end
    end
    switch(2, questieIcon(4), nil, "Available quests",
        "All available quests are shown.", "Only the available quests near you (or the mouse) are shown.",
        function() return not ns.DB.hideFarAvail end, function() ns.DB.hideFarAvail = not ns.DB.hideFarAvail end)
    switch(3, questieIcon(2), questieIcon(4), "Quests started by a drop",
        "Available quests that start from a dropped item are shown.", "Available quests that start from a dropped item are hidden.",
        function() return not ns.DB.hideItemStarts end, function() ns.DB.hideItemStarts = not ns.DB.hideItemStarts end)
    -- the neighbouring zones' Questie icons on a zone map: coloured = shown like the zone's own, grey = left empty
    switch(4, ICONS .. "zones.png", nil, "Neighbouring zones",
        "A zone map also shows the Questie icons of the zones around it.", "A zone map shows only its own Questie icons.",
        function() return not ns.DB.hideOtherZones end, function() ns.DB.hideOtherZones = not ns.DB.hideOtherZones end)

    -- 5: blob colour, steps through the three modes. Its picture is always a blob in the mode's colours, with a
    -- sign for what they mean: none (one color), a ! (by quest level), Questie's loot bag (by objective)
    do
        local MODES = { "single", "kind", "level" }
        local NAMES = { single = "One color", level = "By quest level", kind = "By objective" }
        local b = CreateFrame("Button", nil, f)
        b:SetSize(20, 20)
        b:SetPoint("LEFT", px(5), 0)
        panelBtns[5] = b
        -- the blob in the mode's colours (two halves, each a gradient), its outline, and a sign on top
        local halves = {}
        for k = 1, 2 do
            local t = b:CreateTexture(nil, "ARTWORK")
            t:SetTexture(ICONS .. "blob.png")
            t:SetSize(10.5, 14)
            t:SetPoint("LEFT", -1 + (k - 1) * 10.5, 0)
            t:SetTexCoord((k - 1) / 2, k / 2, 0, 1)
            halves[k] = t
        end
        local line = b:CreateTexture(nil, "OVERLAY")
        line:SetTexture(ICONS .. "blobline.png")
        line:SetSize(21, 14)
        line:SetPoint("LEFT", -1, 0)
        line:SetVertexColor(1, 0.95, 0.8, 0.9)
        local sign = b:CreateTexture(nil, "OVERLAY", nil, 1)   -- by quest level: our !, by objective: Questie's loot bag
        sign:SetPoint("CENTER", 0, 0)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetScript("OnClick", function(_, button)
            local cur = 1
            for n, m in ipairs(MODES) do if m == ns.DB.colorMode then cur = n end end
            ns.DB.colorMode = MODES[(cur - 1 + stepOf(button)) % #MODES + 1]
            if ns.heat then ns.heat._dsig = nil end
            safeScan()
            QQ:RefreshGUI()
            if GameTooltip:IsOwned(b) then b:GetScript("OnEnter")(b) end
        end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Blob color: " .. (NAMES[ns.DB.colorMode] or ""), 1, 1, 1)
            GameTooltip:AddLine(STEP_HINT, 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        panelChecks[#panelChecks + 1] = function()
            local m = ns.DB.colorMode
            local cols
            if m == "level" then cols = { questColor(-3), questColor(0), questColor(5) }
            elseif m == "kind" then cols = { ns.DB.colors.kill, ns.DB.colors.loot, ns.DB.colors.other }
            else cols = { ns.DB.colorAll, ns.DB.colorAll, ns.DB.colorAll } end
            for k, t in ipairs(halves) do
                local c1, c2 = cols[k], cols[k + 1]
                if not (m ~= "single" and hGradient(t, c1, c2, 0.95)) then t:SetVertexColor(c1[1], c1[2], c1[3], 0.95) end
            end
            local loot = questieIcon(2)
            if m == "level" then
                sign:SetTexture(ICONS .. "bang.png"); sign:SetSize(17, 17); sign:Show()
            elseif m == "kind" and loot then
                sign:SetTexture(loot); sign:SetSize(13, 13); sign:Show()
            else
                sign:Hide()
            end
        end
    end

    -- 6: grouping: none (a blob per objective) -> by color (one blob per color) -> all together (one blob).
    -- With the color modes in the order one color, by objective, by quest level, "by objective + by color" and
    -- "by quest level + all together" are one step apart on both buttons: one click on each switches between them.
    do
        local b = CreateFrame("Button", nil, f)
        b:SetSize(20, 20)
        b:SetPoint("LEFT", px(6), 0)
        panelBtns[6] = b
        local one = b:CreateTexture(nil, "ARTWORK")   -- unified: one wide blob
        one:SetTexture(ICONS .. "blobwide.png")
        one:SetSize(24, 14)
        one:SetPoint("CENTER")
        local two = {}                                   -- per objective: two small blobs
        for k = 1, 2 do
            two[k] = b:CreateTexture(nil, "ARTWORK")
            two[k]:SetTexture(ICONS .. "blob.png")
            two[k]:SetSize(11, 14)
            two[k]:SetPoint("CENTER", (k == 1 and -6 or 6), 0)
        end
        local NEXT = { quest = "color", color = "all", all = "quest" }
        local PREV = { quest = "all", color = "quest", all = "color" }
        local NAMES = { quest = "none", all = "all together", color = "by color" }
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetScript("OnClick", function(_, button)
            ns.DB.groupMode = (stepOf(button) < 0 and PREV or NEXT)[ns.DB.groupMode] or "all"
            if ns.heat then ns.heat._dsig = nil end
            safeScan()
            QQ:RefreshGUI()
            if GameTooltip:IsOwned(b) then b:GetScript("OnEnter")(b) end
        end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Grouping: " .. (NAMES[ns.DB.groupMode] or ""), 1, 1, 1)
            GameTooltip:AddLine(STEP_HINT, 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        panelChecks[#panelChecks + 1] = function()
            local mode = ns.DB.groupMode
            -- the same two neighbouring colours in every picture: unified flows from one to the other, by color
            -- splits them into two blobs
            local c, c2
            if ns.DB.colorMode == "level" then c, c2 = questColor(0), questColor(3)
            elseif ns.DB.colorMode == "kind" then c, c2 = ns.DB.colors.loot, ns.DB.colors.lootMid or ns.DB.colors.loot
            else c, c2 = ns.DB.colorAll, ns.DB.colorAll end
            local byColor = mode == "color" and ns.DB.colorMode ~= "single"
            one:SetShown(mode == "all" or (mode == "color" and not byColor))
            for _, t in ipairs(two) do t:SetShown(mode == "quest" or byColor) end   -- by color: two separate blobs, two colors
            local flow = mode == "all" and ns.DB.colorMode ~= "single"
            if not (flow and hGradient(one, c, c2, 0.95)) then one:SetVertexColor(c[1], c[2], c[3], 0.95) end
            two[1]:SetVertexColor(c[1], c[2], c[3], 0.95)
            local d = byColor and c2 or c
            two[2]:SetVertexColor(d[1], d[2], d[3], 0.95)
        end
    end
    -- fold arrow (like the one at the buffs): folds the buttons away, only the round addon button stays
    do
        local ab = CreateFrame("Button", nil, f)
        ab:SetSize(ARROW, 28)
        ab:SetPoint("LEFT", 2, 0)
        local at = ab:CreateTexture(nil, "ARTWORK")
        at:SetSize(12, 18)
        at:SetPoint("CENTER", 1, 0)
        at:SetTexture(ICONS .. "arrow.png")
        local function layout()
            local folded = ns.DB.panelCollapsed and true or false
            for i = 2, 6 do if panelBtns[i] then panelBtns[i]:SetShown(not folded) end end
            bar:SetShown(not folded)
            f:SetWidth(folded and (ARROW + 6) or OPEN_W)
            if folded then at:SetTexCoord(1, 0, 0, 1) else at:SetTexCoord(0, 1, 0, 1) end   -- open: points left; folded: points right
        end
        ab:SetScript("OnClick", function()
            ns.DB.panelCollapsed = not ns.DB.panelCollapsed
            layout()
            if GameTooltip:IsOwned(ab) then ab:GetScript("OnEnter")(ab) end
        end)
        ab:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(ns.DB.panelCollapsed and "Show" or "Hide", 1, 1, 1)
            GameTooltip:Show()
        end)
        ab:SetScript("OnLeave", function() GameTooltip:Hide() end)
        at:SetVertexColor(1, 1, 1, 0.9)
        panelChecks[#panelChecks + 1] = layout
    end
    return f
end

function QQ:ApplyPanel()
    if not ns.DB then return end
    if ns.DB.showPanel then
        if not ns.panel then ns.panel = buildPanel() end
        ns.panel:Show()
        for _, fn in ipairs(panelChecks) do fn() end   -- the icons take the current colors and states
    elseif ns.panel then
        ns.panel:Hide()
    end
end


ns.panelChecks = panelChecks
