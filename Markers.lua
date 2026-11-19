-- Blobs for Questie: Markers
-- Quest markers on the world map. The available ! and the turn-in ? get the addon's own picture with an outline
-- in the quest-title colour of their difficulty (a green ? : turn it in before it goes grey), and quests that are
-- new in WoW Classic Forever get a small infinity badge. Everything sits in a frame of its own above Questie's
-- icon, so a tint another addon lays over Questie's picture does not cover it.
local ADDON_NAME, ns = ...
local QQ = ns.QQ
local ipairs, type = ipairs, type

local ICONS = "Interface\\AddOns\\BlobsForQuestie\\Icons\\"
local MARK_SCALE = 1.3            -- the pictures are 1.3x the icon: room for the outline around it
local BADGE_SCALE = 0.62          -- the badge, of the icon's size
local LAST_CLASSIC_QUEST = 9665   -- every quest of the original Classic has a lower ID; WoW Classic Forever's new ones higher
local PICTURES = {   -- our own pictures (not Questie's): the sign, and the white outline that takes the colour
    bang = { ICONS .. "bang.png", ICONS .. "bangline.png" },
    ask = { ICONS .. "ask.png", ICONS .. "askline.png" },
}

local function isForeverQuest(id)
    return type(id) == "number" and id > LAST_CLASSIC_QUEST
end

-- Which of our pictures replaces Questie's: "bang" (available !), "ask" (turn-in ?), nil = Questie's own stays
-- (repeatable, PvP and event quests keep their colours). grey: Questie's grey ! (too low, or not yet available).
local function glyphOf(d)
    if not Questie then return nil end
    local ic = d.Icon
    if d.Type == "available" then
        if ic == Questie.ICON_TYPE_AVAILABLE then return "bang", false end
        if ic == Questie.ICON_TYPE_AVAILABLE_GRAY then return "bang", true end
    elseif d.Type == "complete" and ic == Questie.ICON_TYPE_COMPLETE then
        return "ask", false
    end
    return nil
end

local function layout(f)
    local m = f._qqMark
    local w, h = f:GetSize()
    if not m or type(w) ~= "number" or w <= 0 or type(h) ~= "number" or h <= 0 then return end
    m:ClearAllPoints()
    m:SetPoint("CENTER", f, "CENTER")
    m:SetSize(w * MARK_SCALE, h * MARK_SCALE)
    m:SetFrameLevel((f:GetFrameLevel() or 1) + 2)
    m.badge:SetSize(w * BADGE_SCALE, h * BADGE_SCALE)
end

local function ensureMark(f)
    local m = f._qqMark
    if m then return m end
    m = CreateFrame("Frame", nil, f)
    m:EnableMouse(false)   -- Questie's tooltip and clicks stay on the icon
    m.line = m:CreateTexture(nil, "ARTWORK")
    m.line:SetAllPoints()
    m.glyph = m:CreateTexture(nil, "OVERLAY", nil, 1)
    m.glyph:SetAllPoints()
    m.over = m:CreateTexture(nil, "OVERLAY", nil, 2)    -- Questie's "started by a drop / an object" sign, kept on top
    m.badge = m:CreateTexture(nil, "OVERLAY", nil, 3)
    m.badge:SetTexture(ICONS .. "forever.png")
    m.badge:SetPoint("TOPRIGHT", m, "TOPRIGHT", 0, 0)
    f._qqMark = m
    -- Questie sizes its icons with the map's zoom and its own settings: the pictures follow
    if f.HookScript then f:HookScript("OnSizeChanged", function(self) if self._qqMark and self._qqMark:IsShown() then layout(self) end end) end
    return m
end

-- takes our marker away and gives Questie's picture back
local function unmark(f)
    local m = f._qqMark
    if m and m:IsShown() then m:Hide() end
    if f._qqGlyph then
        f._qqGlyph = nil
        if f.texture and f.texture.SetAlpha then f.texture:SetAlpha(1) end
    end
end

-- f: a Questie icon; plevel: the player's level. World map only: the minimap stays as Questie draws it.
local function markIcon(f, plevel)
    local d = f.data
    if not (ns.DB and ns.DB.enabled and type(d) == "table" and not f.miniMapIcon and (d.Type == "available" or d.Type == "complete")) then
        unmark(f)
        return
    end
    local glyph, grey, key
    if ns.DB.colorAvail then
        glyph, grey = glyphOf(d)
        key = glyph and ns.levelBand(d, plevel)
        if not key then glyph = nil end   -- level unknown: Questie's picture stays
    end
    local badge = ns.DB.markForever and isForeverQuest(d.Id)
    if not glyph and not badge then
        unmark(f)
        return
    end
    local m = ensureMark(f)
    layout(f)
    if glyph then
        local c = ns.keyColor(key)
        local pic = PICTURES[glyph]
        m.line:SetTexture(pic[2])
        m.line:SetVertexColor(c[1], c[2], c[3], 1)
        m.glyph:SetTexture(pic[1])
        m.glyph:SetDesaturated(grey and true or false)
        m.line:Show(); m.glyph:Show()
        if f.texture and f.texture.SetAlpha then f.texture:SetAlpha(0) end   -- Questie's own picture under ours
        f._qqGlyph = true
        local ov = f.overlayTexture
        if type(ov) == "table" and ov.IsShown and ov:IsShown() and ov.GetTexture and ov:GetTexture() then
            m.over:SetTexture(ov:GetTexture())
            m.over:ClearAllPoints()
            m.over:SetAllPoints(ov)
            m.over:Show()
        else
            m.over:Hide()
        end
    else
        m.line:Hide(); m.glyph:Hide(); m.over:Hide()
        if f._qqGlyph then
            f._qqGlyph = nil
            if f.texture and f.texture.SetAlpha then f.texture:SetAlpha(1) end
        end
    end
    m.badge:SetShown(badge and true or false)
    m:Show()
end

-- Questie hands the frame to another icon: nothing of ours stays on it
ns.forgetHooks[#ns.forgetHooks + 1] = unmark

ns.isForeverQuest = isForeverQuest
ns.markIcon = markIcon
ns.unmark = unmark
