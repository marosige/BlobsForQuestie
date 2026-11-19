-- Blobs for Questie: Commands
local ADDON_NAME, ns = ...
local QQ = ns.QQ
local floor, ceil, max, min, sqrt = math.floor, math.ceil, math.max, math.min, math.sqrt
local format = string.format
local pairs, ipairs, type, tostring, tonumber = pairs, ipairs, type, tostring, tonumber
local safeScan = ns.safeScan
local say = ns.say

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

local function help()
    say("v" .. QQ.version .. "  -  commands (/blob, /bq or /blobs):")
    local lines = {
        "/blob gui  -  open the settings window",
        "/blob on | off | toggle  -  the addon itself",
        "/blob buttons [on|off]  -  the map buttons on the world map",
        "/blob avail [on|off]  -  all available quests (off: only nearby ones)",
        "/blob drop [on|off]  -  quests started by a dropped item",
        "/blob color [one|level|kind]  -  how blobs are colored (no word: next)",
        "/blob group [quest|all|color]  -  how blobs are grouped (no word: next)",
        "/blob debug  -  what the addon found and how it runs (paste this when reporting a problem)",
        "Without on / off a setting flips. These are the same switches as the map buttons.",
    }
    for _, l in ipairs(lines) do print("   |cffffd100" .. l .. "|r") end
end

-- /blob debug: one screenful that says what the addon found and how it runs
function ns.debugReport()
    local function line(text) print("   |cffffd100" .. text .. "|r") end
    say("v" .. QQ.version .. "  -  status")
    line("setup: " .. tostring(ns.setupState or "not run"))
    local qv
    if Questie and QuestieLoader then
        local ok, lib = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieLib")
        if ok and lib and lib.GetAddonVersionString then qv = lib:GetAddonVersionString() end
    end
    line("Questie: " .. (Questie and (qv or "found") or "NOT found") .. (Questie and Questie.IsForever and "  (Forever)" or ""))
    line("HereBeDragons: " .. (ns.HBD and (ns.hbdSource or "found") or "NOT found"))
    local st0 = ns.objectiveStyle and ns.objectiveStyle()
    local styles = { questie = "Questie", pfquest = "pfQuest", blizzard = "Blizzard (Questie draws no objectives: nothing to show!)", custom = "custom" }
    line("Questie objective style: " .. (st0 and (styles[st0] or st0) or "unknown"))
    local frames, mini = 0, 0
    if ns.QuestieMap and ns.QuestieMap.questIdFrames then
        for _, names in pairs(ns.QuestieMap.questIdFrames) do
            for _, name in pairs(names) do
                frames = frames + 1
                local f = _G[name]
                if f and f.miniMapIcon then mini = mini + 1 end
            end
        end
    else
        frames = nil
    end
    line("Questie icon frames: " .. (frames and (frames .. " (" .. mini .. " on the minimap)") or "unavailable"))
    local KB = LibStub and LibStub("Krowi_WorldMapButtons-1.4", true)
    line("map button library: " .. (KB and "found" or "not found (map buttons use the lower left corner)"))
    local DB = ns.DB or {}
    line("settings: addon " .. (DB.enabled and "on" or "off") .. ", color " .. tostring(DB.colorMode) .. ", grouping " .. tostring(DB.groupMode)
        .. ", minimap blobs " .. (DB.minimapBlobs and "on" or "off") .. ", map buttons " .. (DB.showPanel and "on" or "off"))
    -- icons that belong to other maps than the viewed one (a city inside a zone, neighbouring zones)
    local view = ns.S and ns.S.viewMap
    if view and ns.QuestieMap and C_Map and C_Map.GetMapInfo then
        local function mapName(id)
            local ok, info = pcall(C_Map.GetMapInfo, id)
            if ok and type(info) == "table" then return tostring(id) .. " " .. tostring(info.name) .. ", parent " .. tostring(info.parentMapID) end
            return tostring(id)
        end
        line("viewed map: " .. mapName(view))
        local per, order = {}, {}
        local function count(f)
            if f.data and not f.miniMapIcon and f.UiMapID and f.UiMapID ~= view then
                local e = per[f.UiMapID]
                if not e then e = { n = 0, hid = 0, types = {} }; per[f.UiMapID] = e; order[#order + 1] = f.UiMapID end
                e.n = e.n + 1
                if ns.insideView(f) then e.inside = (e.inside or 0) + 1 end
                if f.hidden or f._qqHid then e.hid = e.hid + 1 end
                local t = tostring(f.data.Type)
                e.types[t] = (e.types[t] or 0) + 1
            end
        end
        for _, names in pairs(ns.QuestieMap.questIdFrames or {}) do
            for _, name in pairs(names) do
                local f = _G[name]
                if f then count(f) end
            end
        end
        ns.eachManual(count)
        table.sort(order)
        local parts = {}
        for _, id in ipairs(order) do
            local e = per[id]
            local ts = {}
            for t, n in pairs(e.types) do ts[#ts + 1] = t .. " " .. n end
            table.sort(ts)
            local ok, info = pcall(C_Map.GetMapInfo, id)
            local nm = ok and type(info) == "table" and tostring(info.name) or "?"
            local par = ok and type(info) == "table" and tostring(info.parentMapID) or "?"
            parts[#parts + 1] = id .. " " .. nm .. " (parent " .. par .. "): " .. e.hid .. "/" .. e.n .. " hidden, "
                .. ((e.inside or 0) > 0 and ("INSIDE " .. e.inside) or "outside") .. " [" .. table.concat(ts, ", ") .. "]"
        end
        -- the city / inside maps first, the rest after
        table.sort(parts, function(x, y) return (x:find("INSIDE", 1, true) and 0 or 1) < (y:find("INSIDE", 1, true) and 0 or 1) end)
        for _, l in ipairs(parts) do line("other map " .. l) end
    end
    local st = QQ.stats
    if st then
        line("last map scan: " .. (st.ms and format("%.1f ms", st.ms) or "?") .. ", " .. st.blobs .. " blobs, "
            .. (st.continent and "continent / world map" or "zone map") .. " " .. tostring(st.map))
        line("map scans: " .. (QQ.scans or 0) .. ", blob shapes built: " .. (QQ.geomBuilds or 0)
            .. (QQ.geomMs and format(" (last %.0f ms)", QQ.geomMs) or ""))
    else
        line("last map scan: none yet (open the map)")
    end
end

-- "on" / "off" / nothing (flip) -> the new boolean value
local function wanted(arg, current)
    if arg == "on" or arg == "1" or arg == "show" then return true end
    if arg == "off" or arg == "0" or arg == "hide" then return false end
    return not current
end

local function slash(msg)
    local cmd, arg = (msg or ""):match("^%s*(%S*)%s*(%S*)")
    cmd, arg = (cmd or ""):lower(), (arg or ""):lower()
    if cmd == "" or cmd == "help" or cmd == "?" then
        help()
        return
    elseif cmd == "gui" or cmd == "settings" or cmd == "options" or cmd == "config" then
        QQ:ToggleGUI()
        return
    elseif cmd == "on" then
        ns.DB.enabled = true; say("enabled")
    elseif cmd == "off" then
        ns.DB.enabled = false; say("disabled")
    elseif cmd == "toggle" then
        ns.DB.enabled = not ns.DB.enabled; say(ns.DB.enabled and "enabled" or "disabled")
    elseif cmd == "buttons" or cmd == "panel" then
        ns.DB.showPanel = wanted(arg, ns.DB.showPanel)
        say("map buttons " .. (ns.DB.showPanel and "on" or "off"))
        QQ:ApplyPanel()
    elseif cmd == "avail" or cmd == "available" then
        local on = wanted(arg, not ns.DB.hideFarAvail)
        ns.DB.hideFarAvail = not on
        say("available quests: " .. (on and "all shown" or "only nearby"))
    elseif cmd == "drop" then
        local on = wanted(arg, not ns.DB.hideItemStarts)
        ns.DB.hideItemStarts = not on
        say("quests started by a drop: " .. (on and "shown" or "hidden"))
    elseif cmd == "group" or cmd == "grouping" then
        local MODES = { "quest", "all", "color" }
        local mode = ({ quest = "quest", all = "all", unified = "all", color = "color", colour = "color" })[arg]
        if not mode then
            local nxt = 1
            for n, m in ipairs(MODES) do if m == ns.DB.groupMode then nxt = n % #MODES + 1 end end
            mode = MODES[nxt]
        end
        ns.DB.groupMode = mode
        say("grouping: " .. ({ quest = "one blob per quest", all = "unified blobs", color = "unified blobs by color" })[mode])
    elseif cmd == "debug" or cmd == "status" then
        ns.debugReport()
    elseif cmd == "color" or cmd == "colour" then
        local MODES = { "single", "level", "kind" }
        local ALIAS = { one = "single", single = "single", level = "level", kind = "kind", objective = "kind" }
        local mode = ALIAS[arg]
        if not mode then
            local nxt = 1
            for n, m in ipairs(MODES) do if m == ns.DB.colorMode then nxt = n % #MODES + 1 end end
            mode = MODES[nxt]
        end
        ns.DB.colorMode = mode
        if ns.heat then ns.heat._dsig = nil end
        say("blob color: " .. ({ single = "one color", level = "by quest level", kind = "by objective" })[mode])
    else
        help()
        return
    end
    safeScan()
    QQ:RefreshGUI()
    QQ:ApplyPanel()
end


ns.slash = slash
