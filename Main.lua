-- Blobs for Questie: Main
local ADDON_NAME, ns = ...
local QQ = ns.QQ
local floor, ceil, max, min, sqrt = math.floor, math.ceil, math.max, math.min, math.sqrt
local format = string.format
local pairs, ipairs, type, tostring, tonumber = pairs, ipairs, type, tostring, tonumber
local initDB = ns.initDB
local reportError = ns.reportError
local safeScan = ns.safeScan
local say = ns.say
local slash = ns.slash
local startMinimap = ns.startMinimap

---------------------------------------------------------------------------
-- Startup
---------------------------------------------------------------------------

local function setup()
    -- newer Questie versions carry HereBeDragons as their own module ("HBD"), older ones as a library
    ns.HBD = LibStub and LibStub("HereBeDragons-2.0", true)
    if not ns.HBD and QuestieLoader then
        local ok, m = pcall(QuestieLoader.ImportModule, QuestieLoader, "HBD")
        if ok and type(m) == "table" and type(m.GetPlayerZone) == "function" then ns.HBD = m; ns.hbdSource = "Questie module" end
    elseif ns.HBD then
        ns.hbdSource = "library"
    end
    if QuestieLoader then
        ns.QuestieMap = QuestieLoader:ImportModule("QuestieMap")
    end
    if not (ns.HBD and ns.QuestieMap and Questie) then
        return false, (ns.HBD and "" or "HereBeDragons ") .. (ns.QuestieMap and "" or "QuestieMap ") .. (Questie and "" or "Questie ")
    end

    if WorldMapFrame then
        WorldMapFrame:HookScript("OnShow", function() C_Timer.After(0.05, safeScan) end)
        WorldMapFrame:HookScript("OnHide", function() QQ:ClearCursor() end)
        if WorldMapFrame.OnMapChanged then
            hooksecurefunc(WorldMapFrame, "OnMapChanged", function() C_Timer.After(0.05, safeScan) end)
        end
    end

    local ldb = LibStub("LibDataBroker-1.1", true)
    local dbicon = LibStub("LibDBIcon-1.0", true)
    if ldb and dbicon then
        local obj = ldb:GetDataObjectByName("BlobsForQuestie") or ldb:NewDataObject("BlobsForQuestie", {
            type = "launcher",
            text = "Blobs for Questie",
            icon = "Interface\\AddOns\\BlobsForQuestie\\Icons\\icon.png",
            OnClick = function(_, button)
                if button == "RightButton" then
                    ns.DB.enabled = not ns.DB.enabled
                    say(ns.DB.enabled and "enabled" or "disabled")
                    safeScan()
                    QQ:RefreshGUI()
                else
                    QQ:ToggleGUI()
                end
            end,
            OnTooltipShow = function(tt)
                tt:AddLine("Blobs for Questie", 1, 1, 1)
                tt:AddLine("Left-click: settings", 0.7, 0.9, 1)
                tt:AddLine("Right-click: turn " .. (ns.DB.enabled and "off" or "on"), 0.7, 0.9, 1)
            end,
        })
        if obj and not dbicon:IsRegistered("BlobsForQuestie") then
            dbicon:Register("BlobsForQuestie", obj, ns.DB.minimap)
        end
    end

    -- an entry in the game's Options > AddOns list that opens the settings window
    pcall(function()
        local pg = CreateFrame("Frame", "BlobsForQuestieOptions")
        pg.name = "Blobs for Questie"
        local title = pg:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -16)
        title:SetText("Blobs for Questie")
        local desc = pg:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
        desc:SetWidth(520)
        desc:SetJustifyH("LEFT")
        desc:SetText("Far quest objectives become soft blobs; Questie's own icons show near you and the mouse.")
        local btn = CreateFrame("Button", nil, pg, "UIPanelButtonTemplate")
        btn:SetSize(180, 24)
        btn:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -16)
        btn:SetText("Open settings")
        btn:SetScript("OnClick", function()
            if SettingsPanel and SettingsPanel.Hide and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
            QQ:ToggleGUI()
        end)
        if Settings and Settings.RegisterCanvasLayoutCategory then
            local cat = Settings.RegisterCanvasLayoutCategory(pg, pg.name)
            Settings.RegisterAddOnCategory(cat)
        elseif InterfaceOptions_AddCategory then
            InterfaceOptions_AddCategory(pg)
        end
    end)

    -- Rescan only when something relevant changed (map shown, you moved, Questie redrew).
    startMinimap()
    if ns.startQuestFocus then ns.startQuestFocus() end
    C_Timer.NewTicker(1.0, function()
        if not (WorldMapFrame and WorldMapFrame:IsShown()) then return end
        local frames = 0
        if ns.QuestieMap and ns.QuestieMap.questIdFrames then
            for _, names in pairs(ns.QuestieMap.questIdFrames) do
                for _ in pairs(names) do frames = frames + 1 end
            end
        end
        ns.eachManual(function() frames = frames + 1 end)   -- town icons Questie added or removed
        local px, py = 0, 0
        local x, y = ns.HBD:GetPlayerZonePosition()
        if x and y then px, py = floor(x * 200), floor(y * 200) end
        -- QQ.unloads: Questie gave icon frames back to its pool (it redraws them), even if their count stays the same
        local sig = format("%s|%d|%d|%d|%d", tostring(WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()), frames, px, py, QQ.unloads or 0)
        if sig ~= QQ._tickSig then
            QQ._tickSig = sig
            safeScan()
        end
    end)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        initDB()
    elseif event == "PLAYER_LOGIN" then
        if not ns.DB then initDB() end
        -- Questie may still be loading its libraries: try again for a while before giving up
        local tries = 0
        local function start()
            local ok, done, missing = pcall(setup)
            if not ok then ns.setupState = "error: " .. tostring(done); reportError("setup: " .. tostring(done)); return end
            if done == false then
                tries = tries + 1
                if tries < 30 and C_Timer and C_Timer.After then
                    C_Timer.After(1, start)
                else
                    ns.setupState = "inactive, missing: " .. tostring(missing)
                    say("could not find Questie internals (" .. tostring(missing) .. "missing); addon inactive.")
                end
                return
            end
            ns.setupState = "ok"
            local ok2, err2 = pcall(QQ.ApplyPanel, QQ)
            if not ok2 then reportError("map buttons: " .. tostring(err2)) end
        end
        start()
    end
end)

SLASH_BLOBSFORQUESTIE1 = "/blob"
SLASH_BLOBSFORQUESTIE2 = "/bq"
SLASH_BLOBSFORQUESTIE3 = "/blobs"
SlashCmdList["BLOBSFORQUESTIE"] = function(msg)
    if not ns.DB then initDB() end
    slash(msg)
end


