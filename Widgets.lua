-- Blobs for Questie: Widgets
local ADDON_NAME, ns = ...
local QQ = ns.QQ
local floor, ceil, max, min, sqrt = math.floor, math.ceil, math.max, math.min, math.sqrt
local format = string.format
local pairs, ipairs, type, tostring, tonumber = pairs, ipairs, type, tostring, tonumber
local DEFAULTS = ns.DEFAULTS
local copyDefault = ns.copyDefault
local safeScan = ns.safeScan

---------------------------------------------------------------------------
-- Settings window
---------------------------------------------------------------------------

local widgets = {}
local GUI_W, GUI_H = 480, 592
local PAD = 18
local CW = GUI_W - 2 * PAD   -- content width
local ICONS = "Interface\\AddOns\\BlobsForQuestie\\Icons\\"
local GOLD = { 1, 0.82, 0 }

local function solid(parent, layer, r, g, b, a)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    t:SetColorTexture(r, g, b, a or 1)
    return t
end

-- horizontal colour gradient on a texture (newer clients take colour objects, older ones numbers)
local function hGradient(t, c1, c2, a)
    if CreateColor and t.SetGradient then
        local ok = pcall(t.SetGradient, t, "HORIZONTAL", CreateColor(c1[1], c1[2], c1[3], a), CreateColor(c2[1], c2[2], c2[3], a))
        if ok then return true end
    end
    if t.SetGradientAlpha then
        return (pcall(t.SetGradientAlpha, t, "HORIZONTAL", c1[1], c1[2], c1[3], a, c2[1], c2[2], c2[3], a))
    end
    return false
end

local function questieIcon(iconType)
    return iconType and Questie and Questie.usedIcons and Questie.usedIcons[iconType]
end

local function attachTip(frame, title, text)
    if not text then return end
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(title, 1, 1, 1)
        GameTooltip:AddLine(text, 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- greys out a control (and stops it reacting) while the switch it belongs to is off
local function setActive(w, on)
    w:SetAlpha(on and 1 or 0.35)
    if w.SetEnabled then w:SetEnabled(on) end
    w:EnableMouse(on)
end

local function makeCheck(parent, x, y, label, tip, get, set, w, icon)
    w = w or CW
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", x, y)
    cb:SetSize(24, 24)
    local tx = 4
    if icon then
        local ic = cb:CreateTexture(nil, "ARTWORK")
        ic:SetSize(18, 18)
        ic:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        ic:SetTexture(icon)
        tx = 26
    end
    cb.label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    cb.label:SetPoint("LEFT", cb, "RIGHT", tx, 1)
    cb.label:SetWidth(w - 30 - tx)
    cb.label:SetJustifyH("LEFT")
    cb.label:SetText(label)
    cb:SetHitRectInsets(0, -(w - 30), 0, 0)
    cb:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
        safeScan()
        QQ:RefreshGUI()
    end)
    attachTip(cb, label, tip)
    widgets[#widgets + 1] = function() cb:SetChecked(get() and true or false) end
    return cb
end

-- label on the left above the bar, value on the right; show(v) formats the value
local sliderCount = 0
local function makeSlider(parent, x, y, w, label, tip, minV, maxV, step, show, get, set, inline)
    sliderCount = sliderCount + 1
    local name = "BlobsForQuestieSlider" .. sliderCount
    local sl = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    sl:SetPoint("TOPLEFT", x, inline and y or y - 18)   -- inline: on the row of a checkbox, value at the end
    sl:SetWidth(w)
    sl:SetMinMaxValues(minV, maxV)
    sl:SetValueStep(step)
    if sl.SetObeyStepOnDrag then sl:SetObeyStepOnDrag(true) end
    local function part(k)
        local v = _G[name .. k]
        if type(v) ~= "table" then v = rawget(sl, k) end
        return type(v) == "table" and v or nil
    end
    local text, low, high = part("Text"), part("Low"), part("High")
    if low then low:SetText("") end
    if high then high:SetText("") end
    if text then
        text:ClearAllPoints()
        text:SetPoint("BOTTOMLEFT", sl, "TOPLEFT", 2, 2)
        text:SetText(inline and "" or label)
    end
    local val = sl:CreateFontString(nil, "OVERLAY", inline and "GameFontHighlight" or "GameFontNormal")   -- inline: white like its row
    if inline then val:SetPoint("LEFT", sl, "RIGHT", 8, 0) else val:SetPoint("BOTTOMRIGHT", sl, "TOPRIGHT", -2, 2) end
    sl._refreshing = false
    sl:SetScript("OnValueChanged", function(self, v)
        v = floor(v / step + 0.5) * step
        val:SetText(show(v))
        if self._refreshing then return end
        set(v)
        safeScan()
        QQ:RefreshGUI()
    end)
    attachTip(sl, label, tip)
    widgets[#widgets + 1] = function()
        sl._refreshing = true
        sl:SetValue(get())
        val:SetText(show(get()))
        sl._refreshing = false
    end
    return sl
end

local function makeHeader(parent, x, y, text, w)
    local h = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h:SetPoint("TOPLEFT", x, y)
    h:SetText(text)
    local line = solid(parent, "ARTWORK", 1, 0.8, 0.3, 0.25)
    line:SetPoint("TOPLEFT", x - 2, y - 16)
    line:SetSize(w or CW, 1)
    return h
end

local function makeHint(parent, x, y, text, w)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetWidth(w or CW)
    fs:SetJustifyH("LEFT")
    fs:SetTextColor(0.68, 0.68, 0.68)
    fs:SetText(text)
    return fs
end

-- a row of buttons, one of them selected: items = { { value, label, tip }, ... }
local function makeSegmented(parent, x, y, w, items, get, set)
    local n = #items
    local bw = (w - (n - 1) * 3) / n
    local btns = {}
    for i, it in ipairs(items) do
        local b = CreateFrame("Button", nil, parent)
        b:SetSize(bw, 26)
        b:SetPoint("TOPLEFT", x + (i - 1) * (bw + 3), y)
        b.bg = solid(b, "BACKGROUND", 0.13, 0.15, 0.19)
        b.bg:SetAllPoints()
        b.line = solid(b, "BORDER", 1, 0.8, 0.3, 1)
        b.line:SetPoint("BOTTOMLEFT")
        b.line:SetPoint("BOTTOMRIGHT")
        b.line:SetHeight(2)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.08)
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        b.text:SetPoint("CENTER", 0, 1)
        b.text:SetText(it[2])
        b:SetScript("OnClick", function()
            set(it[1])
            safeScan()
            QQ:RefreshGUI()
        end)
        attachTip(b, it[2], it[3])
        btns[i] = b
    end
    widgets[#widgets + 1] = function()
        local cur = get()
        for i, it in ipairs(items) do
            local b, on = btns[i], it[1] == cur
            if on then b.bg:SetColorTexture(0.30, 0.24, 0.10, 1) else b.bg:SetColorTexture(0.13, 0.15, 0.19, 1) end
            b.line:SetShown(on)
            if on then b.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3]) else b.text:SetTextColor(0.72, 0.72, 0.72) end
        end
    end
    return btns
end

local function pickColor(key)
    local c = (key == "all") and ns.DB.colorAll or ns.DB.colors[key]
    local function apply(r, g, b)
        if key == "all" then ns.DB.colorAll = { r, g, b } else ns.DB.colors[key] = { r, g, b } end
        if ns.heat then ns.heat._dsig = nil end
        safeScan()
        QQ:RefreshGUI()
    end
    local r0, g0, b0 = c[1], c[2], c[3]
    if ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({
            r = r0, g = g0, b = b0, hasOpacity = false,
            swatchFunc = function() apply(ColorPickerFrame:GetColorRGB()) end,
            cancelFunc = function() apply(r0, g0, b0) end,
        })
    elseif ColorPickerFrame then
        ColorPickerFrame.hasOpacity = false
        ColorPickerFrame.previousValues = { r0, g0, b0 }
        ColorPickerFrame.func = function() apply(ColorPickerFrame:GetColorRGB()) end
        ColorPickerFrame.cancelFunc = function() apply(r0, g0, b0) end
        if ColorPickerFrame.SetColorRGB then ColorPickerFrame:SetColorRGB(r0, g0, b0) end
        ColorPickerFrame:Hide()
        ColorPickerFrame:Show()
    end
end

local function makeSwatch(parent, x, y, key, title)
    local sw = CreateFrame("Button", nil, parent)
    sw:SetSize(34, 18)
    sw:SetPoint("TOPLEFT", x, y)
    local border = solid(sw, "BACKGROUND", 1, 1, 1, 0.6)
    border:SetAllPoints()
    local fill = sw:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", -1, 1)
    sw:SetScript("OnClick", function() pickColor(key) end)
    attachTip(sw, title, "Click to choose the color.")
    widgets[#widgets + 1] = function()
        local c = (key == "all") and ns.DB.colorAll or ns.DB.colors[key]
        fill:SetColorTexture(c[1], c[2], c[3], 1)
    end
    return sw
end

-- on / off switch for the header
local function makeSwitch(parent, get, set, tip)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(38, 18)
    local track = solid(b, "BACKGROUND", 0.3, 0.3, 0.3)
    track:SetAllPoints()
    local knob = solid(b, "ARTWORK", 0.95, 0.95, 0.95)
    knob:SetSize(14, 14)
    local state = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    state:SetPoint("RIGHT", b, "LEFT", -6, 0)
    b:SetScript("OnClick", function()
        set(not get())
        safeScan()
        QQ:RefreshGUI()
    end)
    attachTip(b, "Blobs for Questie", tip)
    widgets[#widgets + 1] = function()
        local on = get() and true or false
        if on then track:SetColorTexture(0.18, 0.60, 0.24, 1) else track:SetColorTexture(0.30, 0.30, 0.33, 1) end
        knob:ClearAllPoints()
        knob:SetPoint(on and "RIGHT" or "LEFT", on and -2 or 2, 0)
        state:SetText(on and "On" or "Off")
        if on then state:SetTextColor(0.4, 1, 0.4) else state:SetTextColor(0.6, 0.6, 0.6) end
    end
    return b
end

function QQ:ResetDefaults()
    local minimap = ns.DB.minimap
    for k in pairs(ns.DB) do ns.DB[k] = nil end
    ns.DB.minimap = minimap
    for k, v in pairs(DEFAULTS) do ns.DB[k] = copyDefault(k, v) end
end


ns.widgets = widgets
ns.GUI_W = GUI_W
ns.GUI_H = GUI_H
ns.PAD = PAD
ns.CW = CW
ns.ICONS = ICONS
ns.GOLD = GOLD
ns.solid = solid
ns.hGradient = hGradient
ns.questieIcon = questieIcon
ns.attachTip = attachTip
ns.setActive = setActive
ns.makeCheck = makeCheck
ns.makeSlider = makeSlider
ns.makeHeader = makeHeader
ns.makeHint = makeHint
ns.makeSegmented = makeSegmented
ns.makeSwatch = makeSwatch
ns.makeSwitch = makeSwitch
