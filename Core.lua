-- Blobs for Questie
-- Declutters Questie's map. It only decides what Questie's own icons do: the icons, their tooltips
-- and their look all stay Questie's. Questie's files are never modified; the minimap only if asked (see Minimap).
--   * Zone map: far away quest objectives are replaced by soft blobs that follow their spawn points.
--     Near the player and near the mouse cursor the plain Questie icons show instead.
--   * Continent / world map: one small blob per zone, no icons.
--   * Available quests, quests started by a drop and icons of neighbouring zones / dungeon interiors
--     can be hidden as well. Turn-in (?) icons are never touched.
local ADDON_NAME, ns = ...

local QQ = {}
ns.QQ = QQ
_G.BlobsForQuestie = QQ
QQ.version = "1.0"
QQ.hover = {}

local floor, ceil, max, min, sqrt = math.floor, math.ceil, math.max, math.min, math.sqrt
local format = string.format
local pairs, ipairs, type, tostring, tonumber = pairs, ipairs, type, tostring, tonumber


local DEFAULTS = {
    enabled = true,
    showPanel = true,      -- the map buttons
    revealAll = false,     -- show the plain Questie icons everywhere (the near settings do not matter then)
    allOpacity = 100,      -- % of the blob strength kept under the icons (fixed: the blob stays)
    showNearPlayer = true, -- show the plain Questie icons near the character (instead of a blob)
    objPlayer = 10,        -- % of the map width around the character
    playerOpacity = 100,   -- % of the blob strength kept under those icons
    showNearMouse = true,  -- ... and around the mouse cursor on the map
    objMouse = 10,         -- % of the map width around the mouse cursor
    mouseOpacity = 100,    -- % of the blob strength kept under those icons
    hoverShow = true,      -- pointing at an icon: that objective shows its icons in every blob
    shiftFocus = true,     -- Shift while pointing (icon on the map, quest in the log): only that objective / quest shows
    logDetails = true,     -- a quest's details open in the quest log: only that quest shows on the map
    panelCollapsed = false, -- the map buttons are folded to the arrow and the addon switch
    hideFarAvail = false,  -- available quests follow the same rules as objectives; off = always shown
    blobAlpha = 0.30,      -- strength of the blobs
    hideItemStarts = false, -- hide the available quests that start from an item dropped by a monster or object
    hidePvPQuests = false, -- hide the available PvP quests
    hideRepeatable = false, -- hide the available repeatable quests
    hideDungeonAvail = false, -- hide the available dungeon and raid quests
    colorAvail = false,    -- color the available-quest icons by difficulty (grey .. red)
    blobsWorld = true,     -- blobs on the continent / world maps
    minimapBlobs = false,  -- the same rules (and blobs) on the minimap
    groupMode = "all",     -- "quest" (one blob per quest objective), "all" (one unified blob) or "color" (one unified blob per color)
    colorMode = "level",   -- blob colour: "single" (one colour), "level" (heat map of the quest levels) or "kind" (kill / loot / other)
    lootByDrop = true,     -- "kind" colours: loot changes to its low-rate color where the drop rate is low
    colorAll = { 0.10, 0.28, 0.70 },   -- the "single" colour (dark blue, like the game's own quest blobs)
    -- the "kind" colours; loot has three by drop rate: loot = good (80% and up), lootMid, lootLow = poor (under 30%)
    colors = { kill = { 0.62, 0.30, 0.92 }, loot = { 0.98, 0.84, 0.12 }, lootMid = { 0.98, 0.52, 0.10 }, lootLow = { 0.86, 0.14, 0.14 }, other = { 0.22, 0.68, 0.32 } },
    hideDungeonQuests = true,    -- hide quest icons drawn at dungeon entrances for things inside the dungeon
    hideOtherZones = true, -- zone map: hide the Questie icons of neighbouring zones
}

local S = { continent = false }

local OBJECTIVE_TYPES = { monster = true, object = true, item = true, event = true }

local function say(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff55ccffBlobs for Questie|r: " .. tostring(msg))
end

local lastError
local function reportError(err)
    err = tostring(err)
    if err ~= lastError then
        lastError = err
        say("error: " .. err)
    end
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function copyColors(src)
    local t = {}
    for k, c in pairs(src) do t[k] = { c[1], c[2], c[3] } end
    return t
end
local function copyDefault(k, v)
    if k == "colors" then return copyColors(v) end
    if k == "colorAll" then return { v[1], v[2], v[3] } end
    return v
end

local function isColor(c)
    return type(c) == "table" and type(c[1]) == "number" and type(c[2]) == "number" and type(c[3]) == "number"
end

-- Missing or broken values (hand-edited file, older version) fall back to the defaults.
local function initDB()
    BlobsForQuestieDB = type(BlobsForQuestieDB) == "table" and BlobsForQuestieDB or {}
    ns.DB = BlobsForQuestieDB
    local oldMerge = ns.DB.mergeBlobs   -- before the three grouping modes: merged or not
    for k in pairs(ns.DB) do
        if DEFAULTS[k] == nil and k ~= "minimap" then ns.DB[k] = nil end
    end
    for k, v in pairs(DEFAULTS) do
        if type(ns.DB[k]) ~= type(v) then ns.DB[k] = copyDefault(k, v) end
    end
    if ns.DB.colorMode ~= "single" and ns.DB.colorMode ~= "level" and ns.DB.colorMode ~= "kind" then ns.DB.colorMode = DEFAULTS.colorMode end
    -- the first kind colours (purple / blue / teal) were replaced: move them to the new ones
    local OLD = {
        kill = { { 0.60, 0.32, 0.95 }, { 0.80, 0.22, 0.22 } },
        loot = { { 0.28, 0.52, 1.00 }, { 0.20, 0.45, 0.92 }, { 0.10, 0.62, 0.98 } },
        lootLow = { { 0.60, 0.15, 0.85 } },
        other = { { 0.25, 0.80, 0.65 } },
    }
    for k, list in pairs(OLD) do
        local c = ns.DB.colors[k]
        for _, o in ipairs(list) do
            if isColor(c) and math.abs(c[1] - o[1]) < 0.01 and math.abs(c[2] - o[2]) < 0.01 and math.abs(c[3] - o[3]) < 0.01 then ns.DB.colors[k] = nil end
        end
    end
    for k, c in pairs(DEFAULTS.colors) do
        if not isColor(ns.DB.colors[k]) then ns.DB.colors[k] = { c[1], c[2], c[3] } end
    end
    if ns.DB.groupMode ~= "quest" and ns.DB.groupMode ~= "all" and ns.DB.groupMode ~= "color" then
        ns.DB.groupMode = (oldMerge == false) and "quest" or "all"
    end
    if not isColor(ns.DB.colorAll) then ns.DB.colorAll = copyDefault("colorAll", DEFAULTS.colorAll) end
    ns.DB.objPlayer = min(max(floor(ns.DB.objPlayer), 1), 40)
    ns.DB.objMouse = min(max(floor(ns.DB.objMouse), 1), 40)
    ns.DB.playerOpacity = min(max(ns.DB.playerOpacity, 0), 100)
    ns.DB.allOpacity = min(max(ns.DB.allOpacity, 0), 100)
    ns.DB.mouseOpacity = min(max(ns.DB.mouseOpacity, 0), 100)
    ns.DB.objMouse = ns.DB.objPlayer                                           -- one radius for the character and the mouse
    ns.DB.playerOpacity, ns.DB.mouseOpacity, ns.DB.allOpacity = 100, 100, 100   -- the blob always stays under the icons
    ns.DB.blobAlpha = min(max(ns.DB.blobAlpha, 0.1), 0.8)
    if type(ns.DB.minimap) ~= "table" then ns.DB.minimap = { hide = false, minimapPos = 215 } end
end

-- 1 = kill, 2 = loot, 3 = everything else
local function classOf(icon)
    if Questie and icon == Questie.ICON_TYPE_SLAY then return 1 end
    if Questie and icon == Questie.ICON_TYPE_LOOT then return 2 end
    return 3
end

local function kindIcon(kind)
    if not Questie then return nil end
    if kind == 1 then return Questie.ICON_TYPE_SLAY end
    if kind == 2 then return Questie.ICON_TYPE_LOOT end
    if kind == 4 then return Questie.ICON_TYPE_AVAILABLE end
    return Questie.ICON_TYPE_INTERACT or Questie.ICON_TYPE_EVENT
end

local function objKey(d)
    return tostring(d.Id) .. ":" .. tostring(d.ObjectiveIndex)
end

local function yardsPerFrac(map)
    QQ._ypf = QQ._ypf or {}
    local v = QQ._ypf[map]
    if v == nil then
        v = false
        if ns.HBD and ns.HBD.GetWorldCoordinatesFromZone then
            local x1, y1 = ns.HBD:GetWorldCoordinatesFromZone(0.4, 0.5, map)
            local x2, y2 = ns.HBD:GetWorldCoordinatesFromZone(0.6, 0.5, map)
            if type(x1) == "number" and type(x2) == "number" then
                local d = sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2) / 0.2
                if d > 0 then v = d end
            end
        end
        if not v and ns.HBD and ns.HBD.GetZoneDistance then
            local d = ns.HBD:GetZoneDistance(map, 0.4, 0.5, map, 0.6, 0.5)
            if type(d) == "number" and d > 0 then v = d / 0.2 end
        end
        QQ._ypf[map] = v
    end
    return v or nil
end

-- distances are % of the map width; yards only for the distance from the character
local function mapYards(pct)
    return pct / 100 * (S.ypf or 3000)
end

local function updateState()
    S.pmap, S.px, S.py, S.pwx, S.pwy, S.pinst = nil, nil, nil, nil, nil, nil
    local x, y, m = ns.HBD:GetPlayerZonePosition()
    if x and y and m then S.px, S.py, S.pmap = x, y, m end
    if ns.HBD.GetPlayerWorldPosition then
        local wx, wy, inst = ns.HBD:GetPlayerWorldPosition()
        if type(wx) == "number" and type(wy) == "number" then S.pwx, S.pwy, S.pinst = wx, wy, inst end
    end
    S.viewMap = nil
    S.continent = false
    S.ypf = nil
    if WorldMapFrame and WorldMapFrame.GetMapID then
        local id = WorldMapFrame:GetMapID()
        S.viewMap = id
        if id then
            S.ypf = yardsPerFrac(id)
            local info = C_Map.GetMapInfo(id)
            if info and info.mapType and info.mapType <= 2 then S.continent = true end   -- cosmic, world, continent
        end
    end
end

-- yards from the player; icon positions never change, so their world position is worked out once
local function distYards(f)
    if not S.pmap or not f.UiMapID or not f.x or not f.y then return nil end
    if S.pwx and ns.HBD.GetWorldCoordinatesFromZone then
        -- Questie recycles icon frames: forget the cached position when the frame got a new place
        if f._qqwx ~= nil and (f._qqpx ~= f.x or f._qqpy ~= f.y or f._qqpm ~= f.UiMapID) then f._qqwx = nil end
        local wx = f._qqwx
        if wx == nil then
            f._qqpx, f._qqpy, f._qqpm = f.x, f.y, f.UiMapID
            local a, b, inst = ns.HBD:GetWorldCoordinatesFromZone(f.x / 100, f.y / 100, f.UiMapID)
            if type(a) == "number" and type(b) == "number" then
                f._qqwx, f._qqwy, f._qqinst = a, b, inst
            else
                f._qqwx = false
            end
            wx = f._qqwx
        end
        if wx == false or f._qqinst ~= S.pinst then return nil end
        local dx, dy = wx - S.pwx, f._qqwy - S.pwy
        return sqrt(dx * dx + dy * dy)
    end
    return ns.HBD:GetZoneDistance(S.pmap, S.px, S.py, f.UiMapID, f.x / 100, f.y / 100)
end

---------------------------------------------------------------------------
-- Showing / hiding Questie's icons
---------------------------------------------------------------------------

-- % of the blob strength under the icons that show as plain Questie icons (near the player, or everywhere)
local function nearOpacity()
    if ns.DB.revealAll then return ns.DB.allOpacity or 0 end
    return ns.DB.playerOpacity or 0
end

-- yards around the character inside which the plain icons show (-1 = never)
local function playerYards()
    if not ns.DB.showNearPlayer then return -1 end
    return mapYards(ns.DB.objPlayer)
end

-- Available quests follow the objective rules: hidden unless near the player or the mouse.
-- dungeon and raid quests (Questie's own quest tags), remembered per quest
local instanceQuest = {}
local function isInstanceQuest(id)
    if type(id) ~= "number" then return false end
    local v = instanceQuest[id]
    if v == nil then
        v = false
        local ok, QDB = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieDB")
        if ok and QDB and QDB.IsDungeonQuest then
            local ok2, a = pcall(QDB.IsDungeonQuest, id)
            local ok3, b = pcall(QDB.IsRaidQuest or function() return false end, id)
            v = (ok2 and a) or (ok3 and b) or false
        end
        instanceQuest[id] = v
    end
    return v
end

local function availForced(d)
    if not d or d.Type ~= "available" then return false end
    if ns.DB.hideItemStarts and (d.StarterType == "itemFromMonster" or d.StarterType == "itemFromObject") then return true end
    if ns.DB.hidePvPQuests and d.Icon == (Questie and Questie.ICON_TYPE_PVPQUEST or 15) then return true end
    if ns.DB.hideRepeatable and d.QuestData and d.QuestData.IsRepeatable then return true end
    if ns.DB.hideDungeonAvail and isInstanceQuest(d.Id) then return true end
    return false
end

-- Available-quest icons coloured by difficulty: the icon is desaturated and tinted with the quest-title colour.
-- Quest difficulty colours: the game's own (the colour of a quest title), with the same level steps.
local function greenRange()
    local gr
    if GetQuestGreenRange then gr = GetQuestGreenRange()
    elseif C_QuestLog and C_QuestLog.GetTrivialRange then gr = C_QuestLog.GetTrivialRange() end
    return type(gr) == "number" and gr > 0 and gr or 8
end
local QCOL_FALLBACK = {
    impossible = { 1.00, 0.10, 0.10 }, verydifficult = { 1.00, 0.50, 0.25 }, difficult = { 1.00, 1.00, 0.00 },
    standard = { 0.25, 0.75, 0.25 }, trivial = { 0.50, 0.50, 0.50 },
}
local qcol = {}
local function questKey(diff)   -- diff = quest level - player level
    if diff >= 5 then return "impossible"
    elseif diff >= 3 then return "verydifficult"
    elseif diff >= -2 then return "difficult"
    elseif -diff <= greenRange() then return "standard" end
    return "trivial"
end
local function questColor(diff)
    local key = questKey(diff)
    local c = qcol[key]
    if not c then
        local t = QuestDifficultyColors and QuestDifficultyColors[key]
        c = (type(t) == "table" and type(t.r) == "number") and { t.r, t.g, t.b } or QCOL_FALLBACK[key]
        qcol[key] = c
    end
    return c
end
local function levelBand(d, plevel)   -- the difficulty key of an available quest (nil = level unknown)
    local q = d.QuestData
    local lv = q and q.level
    if type(lv) ~= "number" then return nil end
    if lv <= 0 then return "difficult" end   -- scaling quests
    return questKey(lv - plevel)
end

-- How the yellow "!" is coloured for each difficulty. Filtering the yellow picture keeps the colours bright;
-- yellow stays exactly as it is, only grey needs the picture made grey first.
local AVAIL_TINT = {
    impossible = { 1.00, 0.12, 0.50 }, verydifficult = { 1.00, 0.59, 1.00 }, difficult = { 1, 1, 1 },
    standard = { 0.25, 0.88, 1.00 }, trivial = { 0.65, 0.65, 0.65, grey = true },
}
local function paintAvail(tex, key, a)
    local t = AVAIL_TINT[key]
    if not t then tex:SetDesaturated(false); tex:SetVertexColor(1, 1, 1, a or 1); return end
    tex:SetDesaturated(t.grey and true or false)
    tex:SetVertexColor(t[1], t[2], t[3], a or 1)
end

local function tintAvail(f, plevel, off)
    local tex = f.texture
    if type(tex) ~= "table" or type(tex.GetVertexColor) ~= "function" then return end
    local d = f.data
    if ns.DB.colorAvail and not off and d and d.Type == "available" and (not f.miniMapIcon or (ns.DB.minimapBlobs and ns.DB.enabled)) then
        local c = levelBand(d, plevel)
        if c then
            local _, _, _, a = tex:GetVertexColor()
            -- every available quest is coloured from the plain yellow "!" (a PvP, repeatable or grey "!" would
            -- give darker shades); Questie's own picture is remembered and given back later
            local plain = Questie and Questie.usedIcons and Questie.usedIcons[Questie.ICON_TYPE_AVAILABLE]
            if plain and tex.GetTexture then
                local cur = tex:GetTexture()
                if cur ~= f._qqSetTex then f._qqTex = cur end
                tex:SetTexture(plain)
                f._qqSetTex = tex:GetTexture()
            end
            paintAvail(tex, c, a)
            if f.miniMapIcon and type(tex.r) == "number" then
                -- Questie's minimap fade sets the colour from these fields: keep the tint in them
                if not f._qqRGB then f._qqRGB = { tex.r, tex.g, tex.b } end
                local t = AVAIL_TINT[c] or { 1, 1, 1 }
                tex.r, tex.g, tex.b = t[1], t[2], t[3]
            end
            f._qqTint = true
            return
        end
    end
    if f._qqTint then   -- not (or no longer) tinted: give Questie's own look back
        f._qqTint = nil
        local _, _, _, a = tex:GetVertexColor()
        -- Questie's picture back, unless Questie has drawn something else in this frame since
        if f._qqTex and tex.GetTexture and tex:GetTexture() == f._qqSetTex then tex:SetTexture(f._qqTex) end
        f._qqTex, f._qqSetTex = nil, nil
        if f._qqRGB then tex.r, tex.g, tex.b = f._qqRGB[1], f._qqRGB[2], f._qqRGB[3]; f._qqRGB = nil end
        tex:SetDesaturated(false)
        tex:SetVertexColor(1, 1, 1, a or 1)
    end
end

local function availHide(f)
    if availForced(f.data) then return true end
    if not ns.DB.hideFarAvail then return false end
    if S.continent then return true end
    if ns.DB.revealAll then return false end   -- everything is shown on the zone map
    if f._qqHide ~= nil then return f._qqHide end   -- the scan decided (blob membership)
    if f._qqCur then return false end               -- the mouse cursor is close to it
    if not S.pmap then return false end
    local dist = distYards(f)
    return dist == nil or dist > playerYards()
end

-- Icons of things inside a dungeon are drawn by Questie at the dungeon's entrance on the outdoor map.
-- Anything sitting exactly on an entrance is such an icon; a quest giver standing outside is not.
local entrances
local function entranceTable()
    if entrances then return entrances end
    entrances = {}
    local zdb = QuestieLoader and QuestieLoader:ImportModule("ZoneDB")
    if zdb and zdb.GetDungeons and zdb.GetUiMapIdByAreaId then
        local ok, dungeons = pcall(zdb.GetDungeons, zdb)
        if ok and type(dungeons) == "table" then
            for _, d in pairs(dungeons) do
                local locs = type(d) == "table" and d[4]
                if type(locs) == "table" then
                    for _, loc in ipairs(locs) do
                        local okm, map = pcall(zdb.GetUiMapIdByAreaId, zdb, loc[1])
                        if okm and map and loc[2] and loc[3] then
                            local l = entrances[map]
                            if not l then l = {}; entrances[map] = l end
                            l[#l + 1] = { loc[2], loc[3] }
                        end
                    end
                end
            end
        end
    end
    return entrances
end

local function dungeonHide(f)
    if not ns.DB.hideDungeonQuests then return false end
    local d = f.data
    if not d or d.Type == "manual" or not f.UiMapID or not f.x or not f.y then return false end
    local l = entranceTable()[f.UiMapID]
    if not l then return false end
    for _, e in ipairs(l) do
        if math.abs(e[1] - f.x) < 0.15 and math.abs(e[2] - f.y) < 0.15 then return true end
    end
    return false
end

-- While something is in focus, the quest givers (available) and turn-in icons hide too; only the focused
-- quest's own turn-in stays. Returns nil when nothing is focused.
local function focusHide(f)
    local d = f.data
    if not d or not (QQ.focusQuest or QQ.focusKey) then return nil end
    if d.Type ~= "available" and d.Type ~= "complete" then return nil end
    if QQ.focusQuest then return d.Id ~= QQ.focusQuest end
    return true
end

-- An icon of another map that lies inside the viewed one (Thunder Bluff inside Mulgore) is not from a neighbouring
-- zone and stays. Blizzard lists such a city beside the zone, not under it, so the test is by position: does the
-- icon's place in the world fall on the viewed map?
function ns.insideView(f)
    local v = S.viewMap
    local map = f and f.UiMapID
    if not map or not v then return false end
    if map == v then return true end
    local c = f._qqIn
    if c and c.v == v and c.x == f.x and c.y == f.y and c.m == map then return c.r end
    local r = false
    local H = ns.HBD
    -- only a small map can be a city inside the zone; a zone of its own size or bigger (the Barrens next to Mulgore,
    -- whose map picture also shows some of it) is a neighbour even if the icon falls on the viewed picture
    local small = false
    if H and H.GetZoneSize then
        local ok, mw, mh = pcall(H.GetZoneSize, H, map)
        local ok2, vw, vh = pcall(H.GetZoneSize, H, v)
        small = ok and ok2 and type(mw) == "number" and type(vw) == "number" and vw > 0 and mw < vw * 0.5
    end
    if small and H.GetWorldCoordinatesFromZone and H.GetZoneCoordinatesFromWorld and f.x and f.y then
        local ok, wx, wy = pcall(H.GetWorldCoordinatesFromZone, H, f.x / 100, f.y / 100, map)
        if ok and type(wx) == "number" and type(wy) == "number" then
            local ok2, zx, zy = pcall(H.GetZoneCoordinatesFromWorld, H, wx, wy, v)
            r = ok2 and type(zx) == "number" and type(zy) == "number" and zx >= 0 and zx <= 1 and zy >= 0 and zy <= 1 or false
        end
    end
    f._qqIn = { v = v, x = f.x, y = f.y, m = map, r = r }
    return r
end

-- what the hooks use between two scans
local function wantHide(f)
    local d = f.data
    if not d then return false end
    if not f.miniMapIcon and focusHide(f) then return true end
    if ns.DB.hideOtherZones and not S.continent and S.viewMap and not ns.insideView(f) then return true end
    if dungeonHide(f) then return true end
    if d.Type == "available" then return availHide(f) end
    if OBJECTIVE_TYPES[d.Type] then
        if f._qqHide ~= nil then return f._qqHide end
        if S.continent then return true end
        local dist = distYards(f)
        return dist == nil or dist > playerYards()
    end
    return false
end

-- Questie's own opinion (finished objective, unexplored area...): not ours to override.
-- (f.hidden alone says nothing: Questie also hides icons because OUR ShouldBeHidden said so.)
-- The original ShouldBeHidden does several database lookups, so the answer is cached per frame;
-- scans ask for a fresh one, the hover queue reuses it.
local function questieHides(f, fresh)
    if fresh or f._qqQH == nil then
        f._qqQH = (f._qqOrig and f:_qqOrig() and true or false)
    end
    return f._qqQH
end

local function isHidden(f)
    return f.hidden or f._qqAlpha ~= nil
end

-- Icons are hidden with alpha 0 and no mouse: instant, and Questie's own state is not touched.
-- Icons that carry waypoint paths still use Questie's FakeHide so their path lines go away too.
local function applyHide(f, hide, fresh)
    if questieHides(f, fresh) then return end
    local paths = f.data and f.data.waypointPaths
    local viaQuestie = paths and paths[1]
    if hide then
        if viaQuestie then
            if not f.hidden then f:FakeHide() end
        elseif f._qqAlpha == nil and not f.hidden then
            local a = f:GetAlpha()
            f._qqAlpha = type(a) == "number" and a or 1
            f:SetAlpha(0)
            f:EnableMouse(false)
        end
        f._qqHid = true
    else
        if f.hidden then f:FakeShow() end
        if f._qqAlpha ~= nil then
            f:SetAlpha(f._qqAlpha)
            f:EnableMouse(true)
            f._qqAlpha = nil
        end
        f._qqHid = nil
    end
end

local function hookFrame(f)
    if f._qqHooked then return end
    f._qqHooked = true
    f._qqOrig = f.ShouldBeHidden
    f.ShouldBeHidden = function(self)
        if self._qqOrig and self:_qqOrig() then return true end
        if ns.DB and ns.DB.enabled and S.viewMap then return wantHide(self) and true or false end
        return false
    end
    -- Shift + click on an objective / turn-in icon: open that quest's details in the quest log.
    if f.HookScript and f.GetScript and f:GetScript("OnClick") then
        f:HookScript("OnClick", function(self, button)
            local d = self.data
            if button ~= "LeftButton" or self.miniMapIcon or type(d) ~= "table" or type(d.Id) ~= "number" then return end
            if not (ns.DB and ns.DB.enabled and ns.DB.shiftFocus and IsShiftKeyDown and IsShiftKeyDown()) then return end
            if d.Type == "available" or d.Type == "manual" or not d.QuestData then return end
            if ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow() then return end   -- Questie links the quest there
            if InCombatLockdown and InCombatLockdown() then return end
            if QuestMapFrame_OpenToQuestDetails then pcall(QuestMapFrame_OpenToQuestDetails, d.Id) end
        end)
    end
    -- If Questie / HereBeDragons shows an icon we want hidden, hide it again right away.
    f:HookScript("OnShow", function(self)
        if self._qqAlpha ~= nil then self:SetAlpha(0) end
        if ns.DB and ns.DB.enabled and S.viewMap and not self.hidden and self._qqAlpha == nil and not self.miniMapIcon
            and self.FakeHide and self.data and wantHide(self) then
            applyHide(self, true)
        end
    end)
end

local function eachFrame(fn)
    for _, names in pairs(ns.QuestieMap.questIdFrames) do
        for _, name in pairs(names) do
            local f = _G[name]
            if f and f.data and not f.miniMapIcon and f.UiMapID and f.x and f.y and f.FakeHide and f.FakeShow then
                fn(f, f.data)
            end
        end
    end
end

local function restoreAll()
    for _, tbl in ipairs({ ns.QuestieMap and ns.QuestieMap.questIdFrames or {}, ns.QuestieMap and ns.QuestieMap.manualFrames or {} }) do
        for _, names in pairs(tbl) do
            for _, name in pairs(names) do
                local f = _G[name]
                if f and f._qqTint then tintAvail(f, 1, true) end
                if f and (f._qqHid or f._qqHide ~= nil) then
                    f._qqHide = nil
                    f._qqHid = nil
                    if f.hidden and not questieHides(f, true) then f:FakeShow() end
                    if f._qqAlpha ~= nil then f:SetAlpha(f._qqAlpha); f:EnableMouse(true); f._qqAlpha = nil end
                end
            end
        end
    end
    QQ.blobs = nil
    QQ.hover = {}
    if ns.heat then
        ns.heat._dsig = nil
        ns.heat:Hide()
    end
end


ns.DEFAULTS = DEFAULTS
ns.S = S
ns.OBJECTIVE_TYPES = OBJECTIVE_TYPES
ns.say = say
ns.reportError = reportError
ns.copyDefault = copyDefault
ns.initDB = initDB
ns.classOf = classOf
ns.kindIcon = kindIcon
ns.objKey = objKey
ns.updateState = updateState
ns.distYards = distYards
ns.nearOpacity = nearOpacity
ns.playerYards = playerYards
ns.availForced = availForced
ns.greenRange = greenRange
ns.questKey = questKey
ns.questColor = questColor
ns.paintAvail = paintAvail
ns.tintAvail = tintAvail
ns.availHide = availHide
ns.dungeonHide = dungeonHide
ns.wantHide = wantHide
ns.questieHides = questieHides
ns.isHidden = isHidden
ns.applyHide = applyHide
ns.hookFrame = hookFrame
ns.eachFrame = eachFrame
ns.restoreAll = restoreAll
