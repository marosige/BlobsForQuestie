-- Blobs for Questie: Scan
local ADDON_NAME, ns = ...
local QQ = ns.QQ
local floor, ceil, max, min, sqrt = math.floor, math.ceil, math.max, math.min, math.sqrt
local format = string.format
local pairs, ipairs, type, tostring, tonumber = pairs, ipairs, type, tostring, tonumber
local NEAR_ADD = ns.NEAR_ADD
local NEAR_ONLY = ns.NEAR_ONLY
local OBJECTIVE_TYPES = ns.OBJECTIVE_TYPES
local S = ns.S
local applyHide = ns.applyHide
local availForced = ns.availForced
local availHide = ns.availHide
local buildGeometry = ns.buildGeometry
local cachedGeometry = ns.cachedGeometry
local classOf = ns.classOf
local compAt = ns.compAt
local distYards = ns.distYards
local drawBlobs = ns.drawBlobs
local dungeonHide = ns.dungeonHide
local eachFrame = ns.eachFrame
local heatStep = ns.heatStep
local hideLayer = ns.hideLayer
local hookFrame = ns.hookFrame
local lookBlob = ns.lookBlob
local nearOpacity = ns.nearOpacity
local objKey = ns.objKey
local playerYards = ns.playerYards
local questKey = ns.questKey
local questieHides = ns.questieHides
local refocusOthers = ns.refocusOthers
local reportError = ns.reportError
local restoreAll = ns.restoreAll
local setBlobShown = ns.setBlobShown
local tintAvail = ns.tintAvail
local updateLayer = ns.updateLayer
local updateState = ns.updateState

---------------------------------------------------------------------------
-- The scan
---------------------------------------------------------------------------

-- Which blob a spot belongs to when the blobs are unified by colour: the quest level colour ("level"),
-- kill / loot band / other ("kind"); one colour is one blob ("single"). step = heatStep of the spot.
local function colorGroupKey(step)
    local m = ns.DB.colorMode
    if m == "kind" then return "K" .. (step or 2) end
    if m == "level" then return step and ("L" .. questKey(step)) or "LN" end
    return "ALL"
end

---------------------------------------------------------------------------
-- Patrol paths: a walking mob's whole route belongs to its blob, not just its spawn point.
-- Questie keeps the routes on the icon's data (data.waypointPaths: points in map percent and in world yards).
---------------------------------------------------------------------------

local patrolCache = setmetatable({}, { __mode = "k" })
local miniPatrolCache = setmetatable({}, { __mode = "k" })

-- points along the routes of an icon's NPC, about every `stepPx` pixels of a W x H map: { x%, y%, px, py }
local function patrolPoints(f, W, H, stepPx)
    local paths = f.data and f.data.waypointPaths
    if type(paths) ~= "table" or #paths == 0 or not f.UiMapID then return nil end
    local out
    local key = floor(stepPx * 10) .. "|" .. floor(W) .. "|" .. floor(H)
    for _, path in ipairs(paths) do
        local pts = type(path) == "table" and path.points
        if type(pts) == "table" and #pts >= 2 and path.uiMapId == f.UiMapID then
            local c = patrolCache[path]
            if not c or c.key ~= key then
                local list = {}
                for i = 1, #pts - 1 do
                    local a, b = pts[i], pts[i + 1]
                    local len = sqrt(((b.x - a.x) * W / 100) ^ 2 + ((b.y - a.y) * H / 100) ^ 2)
                    local n = max(1, ceil(len / stepPx))
                    for k = 0, n - 1 do
                        local t = k / n
                        local x, y = a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t
                        list[#list + 1] = { x, y, x * W / 100, y * H / 100 }
                    end
                end
                local last = pts[#pts]
                list[#list + 1] = { last.x, last.y, last.x * W / 100, last.y * H / 100 }
                c = { key = key, list = list }
                patrolCache[path] = c
            end
            out = out or {}
            for _, e in ipairs(c.list) do out[#out + 1] = e end
        end
    end
    return out
end

local function scanZone()
    local canvas = WorldMapFrame:GetCanvas()
    local W, H = canvas:GetSize()
    if type(W) ~= "number" or type(H) ~= "number" or W < 10 or H < 10 then return end

    local all = {}
    local plevel = UnitLevel("player") or 1
    eachFrame(function(f, d)
        hookFrame(f)
        tintAvail(f, plevel)
        local t = d.Type
        local other = f.UiMapID ~= S.viewMap
        if other and ns.DB.hideOtherZones then
            -- Questie also draws neighbouring zones on a zone map: that is only noise here
            f._qqHide = true
            applyHide(f, true, true)
            return
        end
        if dungeonHide(f) then
            f._qqHide = true
            applyHide(f, true, true)
            return
        end
        if availForced(d) then
            f._qqHide = true
            applyHide(f, true, true)
            return
        end
        if t == "available" and not ns.DB.hideFarAvail then
            if f._qqHid then f._qqHide = nil; applyHide(f, false) end
        elseif t == "available" or OBJECTIVE_TYPES[t] then
            if questieHides(f, true) then return end
            if other then
                -- belongs to another map: not drawn here; just don't leave it hidden from an earlier view
                if f._qqHid then f._qqHide = nil; applyHide(f, false) end
                return
            end
            local px, py = f.x * W / 100, f.y * H / 100
            local isAvail = t == "available"
            all[#all + 1] = { f = f, x = px, y = py, kind = isAvail and 4 or classOf(d.Icon), obj = isAvail and "AVAIL" or objKey(d), step = heatStep(d, plevel),
                extra = (not isAvail) and patrolPoints(f, W, H, max(W * 0.026, 14) * 0.7 * 0.8) or nil }
        elseif f._qqHid then
            f._qqHide = nil
            applyHide(f, false)
        end
    end)

    -- Everything of one colour is ONE set of blobs (no overlapping, darker patches). Icons near the player are
    -- not part of the far blobs: they show as plain icons (optionally over a paler blob of their own).
    local R = max(W * 0.026, 14) * 0.7
    local py = playerYards()
    local groups = {}
    for _, it in ipairs(all) do
        local dist = (py > 0 and not ns.DB.revealAll) and distYards(it.f) or nil
        local near = ns.DB.revealAll or (dist ~= nil and dist <= py)
        local merged = ns.DB.groupMode ~= "quest" and it.kind ~= 4
        it.near = near
        local gk
        if it.kind == 4 then gk = "AVAIL"
        elseif ns.DB.groupMode == "quest" then gk = it.obj
        elseif ns.DB.groupMode == "color" then gk = colorGroupKey(it.step)
        else gk = "ALL" end
        -- merged blobs stay ONE blob: spots near the player just fade inside it (the icons show on top)
        if not merged then gk = gk .. (near and "N" or "F") end
        local g = groups[gk]
        if not g then g = { key = gk, near = near and not merged, noDraw = it.kind == 4, items = {}, pts = {}, seen = {} }; groups[gk] = g end
        g.items[#g.items + 1] = it
        local cell = floor(it.f.x * 1.25) * 1000 + floor(it.f.y * 1.25) + (merged and near and 5000000 or 0)   -- one point per ~0.8% cell is plenty
        if not g.seen[cell] then
            g.seen[cell] = true
            local step = it.step
            if merged and near then step = step and (step + NEAR_ADD) or NEAR_ONLY end
            g.pts[#g.pts + 1] = { it.x, it.y, it.kind, step }
        end
        if it.extra then   -- the whole patrol route is part of the blob
            for _, e in ipairs(it.extra) do
                local ec = floor(e[1] * 1.25) * 1000 + floor(e[2] * 1.25) + (merged and near and 5000000 or 0)
                if not g.seen[ec] then
                    g.seen[ec] = true
                    local step = it.step
                    if merged and near then step = step and (step + NEAR_ADD) or NEAR_ONLY end
                    g.pts[#g.pts + 1] = { e[3], e[4], it.kind, step }
                end
            end
        end
    end

    local list = {}
    for key, g in pairs(groups) do
        if g.near and (g.noDraw or nearOpacity() <= 0) then
            setBlobShown({ items = g.items }, true)   -- no blob under them: just the icons
        else
            local G = cachedGeometry("Z|" .. key, g.pts, R, W, H)
            local blobs = {}
            for i, c in ipairs(G.comps) do
                blobs[i] = { c = c, key = key .. "#" .. S.viewMap .. "#" .. i, items = {}, near = g.near, noDraw = g.noDraw }
            end
            for _, it in ipairs(g.items) do
                local b = blobs[compAt(G, it.x, it.y) or 1]
                if b then b.items[#b.items + 1] = it end
            end
            for _, b in ipairs(blobs) do
                if #b.items > 0 then list[#list + 1] = b end
            end
        end
    end
    table.sort(list, function(a, b) return a.key < b.key end)

    QQ.blobs = list
    local live = {}
    for _, b in ipairs(list) do
        live[b.key] = true
        setBlobShown(b, b.near)
    end
    for k in pairs(QQ.hover) do
        if not live[k] then QQ.hover[k] = nil end
    end
    if #list == 0 then hideLayer() return end
    updateLayer(list, W, H)
end

local rectCache = {}
local function zoneRect(map)
    local key = tostring(map) .. ">" .. tostring(S.viewMap)
    local r = rectCache[key]
    if r == nil then
        r = false
        if C_Map and C_Map.GetMapRectOnMap then
            local ok, l, rr, t, b = pcall(C_Map.GetMapRectOnMap, map, S.viewMap)
            if ok and l and rr and t and b and rr > l and b > t then r = { l, rr, t, b } end
        end
        rectCache[key] = r
    end
    return r or nil
end

local function scanContinent()
    local canvas = WorldMapFrame:GetCanvas()
    local W, H = canvas:GetSize()
    if type(W) ~= "number" or type(H) ~= "number" or W < 10 or H < 10 then return end

    local zones = {}
    local plevel = UnitLevel("player") or 1
    eachFrame(function(f, d)
        hookFrame(f)
        tintAvail(f, plevel)
        local t = d.Type
        if dungeonHide(f) then
            f._qqHide = true
            applyHide(f, true, true)
            return
        end
        if t == "available" then
            applyHide(f, availHide(f), true)
        elseif OBJECTIVE_TYPES[t] then
            if questieHides(f, true) then return end
            f._qqHide = true
            applyHide(f, true)
            local r = zoneRect(f.UiMapID)
            if not r then return end
            local z = zones[f.UiMapID]
            if not z then z = { pts = {}, seen = {} }; zones[f.UiMapID] = z end
            local cell = floor(f.x * 0.8) * 1000 + floor(f.y * 0.8)
            local kd = classOf(d.Icon)
            if not z.seen[cell] then
                z.seen[cell] = true
                z.pts[#z.pts + 1] = { (r[1] + f.x / 100 * (r[2] - r[1])) * W, (r[3] + f.y / 100 * (r[4] - r[3])) * H,
                    kd, heatStep(d, plevel) }
            end
            local ex = patrolPoints(f, 100, 100, 1.5)   -- in map percent here: about every 1.5%
            if ex then
                for _, e in ipairs(ex) do
                    local ec = floor(e[1] * 0.8) * 1000 + floor(e[2] * 0.8)
                    if not z.seen[ec] then
                        z.seen[ec] = true
                        z.pts[#z.pts + 1] = { (r[1] + e[1] / 100 * (r[2] - r[1])) * W, (r[3] + e[2] / 100 * (r[4] - r[3])) * H, kd, heatStep(d, plevel) }
                    end
                end
            end
        elseif f._qqHid then
            f._qqHide = nil
            applyHide(f, false)
        end
    end)

    if not ns.DB.blobsWorld then
        QQ.blobs = nil
        QQ.hover = {}
        hideLayer()
        return
    end
    local R = max(W * 0.012, 9) * 0.7
    local list = {}
    for map, z in pairs(zones) do
      if #z.pts > 0 then
        local G = cachedGeometry("C|" .. map, z.pts, R, W, H)
        for i, c in ipairs(G.comps) do
            list[#list + 1] = { c = c, key = "C|" .. map .. "#" .. i, items = {}, near = false }
        end
      end
    end
    table.sort(list, function(a, b) return a.key < b.key end)
    QQ.blobs = nil
    QQ.hover = {}
    if #list == 0 then hideLayer() return end
    updateLayer(list, W, H)
end

-- Flight masters, innkeepers, trainers... (Questie's manual icons): on a zone map the ones of other zones go too.
local function scanManual()
    if not (ns.QuestieMap and ns.QuestieMap.manualFrames) then return end
    local want0 = ns.DB.hideOtherZones and not S.continent and S.viewMap
    for _, names in pairs(ns.QuestieMap.manualFrames) do
        for _, name in pairs(names) do
            local f = _G[name]
            if f and f.data and not f.miniMapIcon and f.UiMapID and f.FakeHide then
                if want0 and f.UiMapID ~= S.viewMap then
                    f._qqHide = true
                    applyHide(f, true, true)
                elseif f._qqHid then
                    f._qqHide = nil
                    applyHide(f, false, true)
                end
            end
        end
    end
end

function QQ:Scan()
    if QQ.SyncMini then QQ:SyncMini() end
    if not (ns.HBD and ns.QuestieMap and ns.QuestieMap.questIdFrames and Questie and Questie.db) then return end
    if not ns.DB.enabled then
        restoreAll()
        return
    end
    updateState()
    if not S.viewMap or not WorldMapFrame then return end
    local t0 = debugprofilestop and debugprofilestop()
    scanManual()
    if S.continent then scanContinent() else scanZone() end
    if QQ.focusQuest or QQ.focusKey then refocusOthers() end
    QQ.stats = { ms = t0 and (debugprofilestop() - t0) or nil, blobs = QQ.blobs and #QQ.blobs or 0, map = S.viewMap, continent = S.continent and true or false }   -- for /blob debug
end

---------------------------------------------------------------------------
-- Minimap (optional): the same rules as on the zone map. Distances are % of the minimap's width, the
-- map you are looking at there. Blobs are drawn on a layer of the minimap, clipped to its circle.
---------------------------------------------------------------------------

local MINIMAP_SIZE = {   -- diameter in yards per zoom level (as HereBeDragons-Pins)
    indoor = { [0] = 300, 240, 180, 120, 80, 50 },
    outdoor = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 6, 200, 133 + 1 / 3 },
}
local mini
local miniList, miniListT = {}, -99
local miniHidden = {}   -- minimap icons hidden by us

local function miniRadius()
    if C_Minimap and C_Minimap.GetViewRadius then
        local v = C_Minimap.GetViewRadius()
        if type(v) == "number" and v > 0 then return v end
    end
    local zoom = Minimap:GetZoom() or 0
    local where = (tonumber(GetCVar("minimapZoom")) == zoom) and "outdoor" or "indoor"
    return (MINIMAP_SIZE[where][zoom] or 466) / 2
end

-- Blob size on the minimap: the same size in the world as on the zone map, so blobs there merge and look
-- like on the big map (the minimap shows a much smaller area, so the radius grows by that ratio).
local function miniBlobRadius(radius, widthPx, fallbackMap)
    local R = max(widthPx * 0.026, 14) * 0.7
    local zw
    if ns.HBD then
        local zone = ns.HBD.GetPlayerZone and ns.HBD:GetPlayerZone() or fallbackMap
        if zone and ns.HBD.GetZoneSize then
            local w = ns.HBD:GetZoneSize(zone)
            if type(w) == "number" and w > 0 then zw = w end
        end
    end
    if zw and radius > 0 then
        local zoneR = zw * 0.026 * 0.7   -- the zone map's blob radius in yards
        R = zoneR / (radius * 2) * widthPx
    end
    return min(max(R, 6), widthPx * 0.4)
end

local function miniHide(f, hide)
    if hide then
        if not miniHidden[f] then
            local a = f:GetAlpha()
            miniHidden[f] = type(a) == "number" and a or 1
            f:SetAlpha(0)
            f:EnableMouse(false)
        end
    elseif miniHidden[f] then
        f:SetAlpha(miniHidden[f])
        f:EnableMouse(true)
        miniHidden[f] = nil
    end
end

local function miniRestore()
    for f in pairs(miniHidden) do miniHide(f, false) end
    for _, f in ipairs(miniList) do if f._qqTint then tintAvail(f, 1, true) end end
    if mini then mini:Hide() end
end

local function ensureMini()
    if mini then return mini end
    mini = CreateFrame("Frame", "BlobsForQuestieMinimap", Minimap)
    mini:SetAllPoints(Minimap)
    mini:SetFrameLevel((Minimap:GetFrameLevel() or 1))   -- below the icons (they are children of the minimap one level up)
    mini:EnableMouse(false)
    mini.tex, mini.lines, mini.lmx, mini.lmy = {}, {}, {}, {}
    if mini.CreateMaskTexture then   -- clip the blobs to the round minimap
        local m = mini:CreateMaskTexture()
        if type(m) == "table" and m.SetTexture then
            m:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            m:SetAllPoints(mini)
            mini.mask = m
        end
    end
    local probe = mini:CreateTexture()
    mini.voOK = type(probe) == "table" and probe.SetVertexOffset ~= nil
    probe:Hide()
    return mini
end

-- a tiny frame of its own drives the minimap updates (the blob layer itself may be hidden)
local function startMinimap()
    if QQ._miniDriver or not Minimap then return end
    local drv = CreateFrame("Frame")
    QQ._miniDriver = drv
    drv:SetScript("OnUpdate", function(self, elapsed)
        self._t = (self._t or 0) + elapsed
        if self._t < 0.15 then return end
        self._t = 0
        local ok, err = pcall(QQ.MinimapTick, QQ)
        if not ok then reportError("minimap: " .. tostring(err)) end
    end)
    QQ:SyncMini()
end

-- the minimap driver only runs while the minimap blobs are on; switching them off restores the minimap once
function QQ:SyncMini()
    local drv = QQ._miniDriver
    if not drv then return end
    local want = ns.DB and ns.DB.enabled and ns.DB.minimapBlobs and true or false
    if want and not drv:IsShown() then
        drv:Show()
    elseif not want and drv:IsShown() then
        pcall(QQ.MinimapTick, QQ)
        drv:Hide()
    end
end

function QQ:MinimapTick()
    if not (ns.DB and ns.DB.enabled and ns.DB.minimapBlobs and ns.HBD and ns.QuestieMap and ns.QuestieMap.questIdFrames) then
        if next(miniHidden) or (mini and mini:IsShown()) then miniRestore() end
        return
    end
    local now = GetTime and GetTime() or 0
    if now - miniListT > 2 then   -- the list of Questie's minimap icons, refreshed now and then
        miniListT = now
        miniList = {}
        for _, names in pairs(ns.QuestieMap.questIdFrames) do
            for _, name in pairs(names) do
                local f = _G[name]
                if f and f.miniMapIcon and f.data and f.UiMapID and f.x and f.y then miniList[#miniList + 1] = f end
            end
        end
        for f in pairs(miniHidden) do   -- recycled frames that are no longer minimap icons
            if not f.miniMapIcon then miniHide(f, false) end
        end
    end
    local px, py, pinst = ns.HBD:GetPlayerWorldPosition()
    if not px then return end
    local radius = miniRadius()
    local halfW, halfH = Minimap:GetWidth() / 2, Minimap:GetHeight() / 2
    local nearY
    if ns.DB.revealAll then nearY = 1e9
    elseif ns.DB.showNearPlayer then nearY = (ns.DB.objPlayer or 0) / 100 * radius * 2
    else nearY = -1 end
    local rot = GetCVar("rotateMinimap") == "1"
    local facing = rot and GetPlayerFacing and GetPlayerFacing() or 0
    if rot and not facing then return end
    local sn, cs = math.sin(facing), math.cos(facing)
    local plevel = UnitLevel("player") or 1
    local groups, sig = {}, {}
    local Rpx = miniBlobRadius(radius, halfW * 2, miniList[1] and miniList[1].UiMapID)
    local stepYd = max(Rpx * 0.8, 3) / halfW * radius   -- patrol sample spacing in yards
    for _, f in ipairs(miniList) do
        local d = f.data
        if f.miniMapIcon and d then
            tintAvail(f, plevel)
            local hide, near, onMap, mx, my = false, true, false, 0, 0
            local wx, wy, inst = ns.HBD:GetWorldCoordinatesFromZone(f.x / 100, f.y / 100, f.UiMapID)
            local dist
            if wx and inst == pinst then
                local dx, dy = px - wx, py - wy
                dist = sqrt(dx * dx + dy * dy)
                if rot then dx, dy = dx * cs - dy * sn, dx * sn + dy * cs end
                mx, my = halfW + dx / radius * halfW, halfH + dy / radius * halfH   -- pixels from the minimap's top left
                onMap = dist <= radius * 1.15
            end
            if d.Type == "available" then
                hide = availForced(d) or dungeonHide(f) or (ns.DB.hideFarAvail and (dist == nil or dist > nearY))
            elseif OBJECTIVE_TYPES[d.Type] then
                if dungeonHide(f) then hide = true
                else
                    near = dist ~= nil and dist <= nearY
                    hide = not near
                    if onMap and (ns.DB.groupMode ~= "quest" or not near or nearOpacity() > 0) then
                        -- merged: one blob, the spots near the player fade inside it
                        local step = heatStep(d, plevel)
                        local gk
                        if ns.DB.groupMode == "quest" then gk = objKey(d) .. (near and "N" or "F")
                        elseif ns.DB.groupMode == "color" then gk = colorGroupKey(step)
                        else gk = "ALL" end
                        local g = groups[gk]
                        if not g then g = { key = gk, near = near and ns.DB.groupMode == "quest", pts = {}, items = {} }; groups[gk] = g end
                        if ns.DB.groupMode ~= "quest" and near then step = step and (step + NEAR_ADD) or NEAR_ONLY end
                        g.pts[#g.pts + 1] = { mx, my, classOf(d.Icon), step }
                        sig[#sig + 1] = floor(mx) .. "," .. floor(my) .. gk .. (near and "n" or "")
                        -- the whole patrol route belongs to the blob
                        local paths = d.waypointPaths
                        if type(paths) == "table" then
                            for _, path in ipairs(paths) do
                                local wl = type(path) == "table" and path.world
                                if type(wl) == "table" and #wl >= 2 and path.instanceId == pinst then
                                    local cc = miniPatrolCache[path]
                                    local ck = "w" .. floor(stepYd * 10)
                                    if not cc or cc.wkey ~= ck then
                                        local list = {}
                                        for i = 1, #wl - 1 do
                                            local a, b = wl[i], wl[i + 1]
                                            local n = max(1, ceil(sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2) / stepYd))
                                            for k = 0, n - 1 do list[#list + 1] = { a.x + (b.x - a.x) * k / n, a.y + (b.y - a.y) * k / n } end
                                        end
                                        list[#list + 1] = { wl[#wl].x, wl[#wl].y }
                                        cc = cc or {}
                                        cc.wkey, cc.wlist = ck, list
                                        miniPatrolCache[path] = cc
                                    end
                                    for _, e in ipairs(cc.wlist) do
                                        local ex, ey = px - e[1], py - e[2]
                                        if rot then ex, ey = ex * cs - ey * sn, ex * sn + ey * cs end
                                        local qx, qy = halfW + ex / radius * halfW, halfH + ey / radius * halfH
                                        if qx > -Rpx and qx < halfW * 2 + Rpx and qy > -Rpx and qy < halfH * 2 + Rpx then
                                            g.pts[#g.pts + 1] = { qx, qy, classOf(d.Icon), step }
                                            sig[#sig + 1] = floor(qx) .. "," .. floor(qy) .. gk
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
            miniHide(f, hide)
        end
    end
    -- redraw only when something moved
    local m = ensureMini()
    table.sort(sig)
    local cl = ns.DB.colorAll
    local key = table.concat(sig, ";") .. "|" .. ns.DB.colorMode .. "|" .. ns.DB.groupMode .. "|" .. nearOpacity() .. "|" .. ns.DB.blobAlpha .. "|" .. floor(radius)
        .. "|" .. format("%.3f%.3f%.3f", cl[1], cl[2], cl[3])
    for _, k in ipairs({ "kill", "loot", "other" }) do local c = ns.DB.colors[k]; key = key .. format("%.3f%.3f%.3f", c[1], c[2], c[3]) end
    if key ~= m._sig then
        m._sig = key
        local R = miniBlobRadius(radius, halfW * 2, miniList[1] and miniList[1].UiMapID)
        local list = {}
        for gk, g in pairs(groups) do
            local G = buildGeometry(g.pts, R)
            for n, c in ipairs(G.comps) do list[#list + 1] = { c = c, key = "M" .. gk .. n, items = {}, near = g.near } end
        end
        local cont = S.continent
        S.continent = false   -- the zone-map rules, whatever the world map shows
        drawBlobs(m, list, halfW * 2, halfH * 2)
        for _, b in ipairs(list) do lookBlob(m, b) end
        S.continent = cont
        -- outline pieces outside the round minimap are not clipped by the mask: hide them
        local lim = (min(halfW, halfH) - 1) ^ 2
        for n, ln in ipairs(m.lines) do
            if ln:IsShown() and ((m.lmx[n] or 0) - halfW) ^ 2 + ((m.lmy[n] or 0) - halfH) ^ 2 > lim then ln:Hide() end
        end
    end
    m:Show()
end

local function safeScan()
    local ok, err = pcall(QQ.Scan, QQ)
    if not ok then reportError(err) end
end


ns.startMinimap = startMinimap
ns.safeScan = safeScan
