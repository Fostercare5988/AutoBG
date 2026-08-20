-- AutoBG for WoW 1.12.1 (Vanilla / OctoWOW)
local addonName = "AutoBG"

-- Lua 5.0 Compatibility Polyfills
if not math.mod then
    math.mod = math.fmod or function(a, b)
        return a - math.floor(a / b) * b
    end
end
if not mod then
    mod = math.mod
end

if not string.match then
    string.match = function(str, pattern, init)
        local start, finish, c1, c2, c3, c4, c5, c6, c7, c8, c9 = string.find(str, pattern, init)
        if start then
            if c1 then
                return c1, c2, c3, c4, c5, c6, c7, c8, c9
            else
                return string.sub(str, start, finish)
            end
        end
    end
end

local function print(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(msg)
    end
end

-- Lightweight Timer Scheduler (Replacement for C_Timer.After in 1.12)
AutoBG_TimersQueue = AutoBG_TimersQueue or {}
local TimerScheduler = CreateFrame("Frame", "AutoBG_TimerScheduler")
TimerScheduler:SetScript("OnUpdate", function()
    local now = GetTime()
    local count = table.getn(AutoBG_TimersQueue)
    for i = count, 1, -1 do
        local item = AutoBG_TimersQueue[i]
        if now >= item.time then
            table.remove(AutoBG_TimersQueue, i)
            if item.func then
                item.func()
            end
        end
    end
end)

function AutoBG_TimerAfter(delay, func)
    if C_Timer and C_Timer.After then
        C_Timer.After(delay, func)
    else
        table.insert(AutoBG_TimersQueue, { time = GetTime() + delay, func = func })
    end
end

-- Frame Position Persistence Helpers
function AutoBG_SavePosition(frame, name)
    if not AutoBG_Settings then return end
    AutoBG_Settings.Positions = AutoBG_Settings.Positions or {}
    local point, _, relPoint, x, y = frame:GetPoint()
    AutoBG_Settings.Positions[name] = { point = point, relPoint = relPoint, x = x, y = y }
end

function AutoBG_LoadPosition(frame, name, defaultPoint, defaultX, defaultY)
    if AutoBG_Settings and AutoBG_Settings.Positions and AutoBG_Settings.Positions[name] then
        local pos = AutoBG_Settings.Positions[name]
        frame:ClearAllPoints()
        frame:SetPoint(pos.point or defaultPoint or "CENTER", UIParent, pos.relPoint or defaultPoint or "CENTER", pos.x or defaultX, pos.y or defaultY)
    else
        frame:ClearAllPoints()
        frame:SetPoint(defaultPoint or "CENTER", UIParent, defaultPoint or "CENTER", defaultX, defaultY)
    end
end

local defaultSettings = {
    NotifySound = true,
    FlashTaskbar = true,
    AutoAccept = false,
    AutoLeave = true,
    AutoRejoin = false,
    ScoreColor = true,
    NodeColors = true,
    AutoRelease = true,
    ABTimers = true,
    AVTimers = true,
    RessTimer = true,
    QueueTimers = true,
    FCFrame = true,
    WSGTimers = true,
    HideCastbar = false,
    HideStanceBar = false,
    TestAllTimers = false,
    Positions = {},
}

function AutoBG_UpdateStanceBar()
    if not AutoBG_Settings then return end
    if AutoBG_Settings.HideStanceBar then
        if ShapeshiftBarFrame then
            ShapeshiftBarFrame:UnregisterAllEvents()
            ShapeshiftBarFrame:Hide()
            ShapeshiftBarFrame:SetAlpha(0)
        end
        for i = 1, 12 do
            local btn = getglobal("ShapeshiftButton" .. i)
            if btn then
                btn:Hide()
                btn:SetAlpha(0)
            end
        end
    end
end

-- Hook ShapeshiftBar_Update to keep it hidden across form/stance changes
local orig_ShapeshiftBar_Update = ShapeshiftBar_Update
ShapeshiftBar_Update = function()
    if AutoBG_Settings and AutoBG_Settings.HideStanceBar then
        AutoBG_UpdateStanceBar()
        return
    end
    if orig_ShapeshiftBar_Update then
        orig_ShapeshiftBar_Update()
    end
end

-- Hook UIParent_ManageFramePositions in case other UI mods re-show it
local orig_UIParent_ManageFramePositions = UIParent_ManageFramePositions
UIParent_ManageFramePositions = function(a1, a2, a3)
    if orig_UIParent_ManageFramePositions then
        orig_UIParent_ManageFramePositions(a1, a2, a3)
    end
    if AutoBG_Settings and AutoBG_Settings.HideStanceBar then
        AutoBG_UpdateStanceBar()
    end
end

-- Class Color Table & Multi-Locale Name Map
local classColors = {}
if RAID_CLASS_COLORS then
    for class, color in pairs(RAID_CLASS_COLORS) do
        classColors[class] = string.format("|cff%02x%02x%02x", color.r * 255, color.g * 255, color.b * 255)
    end
end
-- Fallback standard hex values if not defined
classColors["WARRIOR"] = classColors["WARRIOR"] or "|cffc79c6e"
classColors["MAGE"] = classColors["MAGE"] or "|cff69ccf0"
classColors["ROGUE"] = classColors["ROGUE"] or "|cfffff569"
classColors["DRUID"] = classColors["DRUID"] or "|cffff7d0a"
classColors["HUNTER"] = classColors["HUNTER"] or "|cffabd473"
classColors["PRIEST"] = classColors["PRIEST"] or "|cffffffff"
classColors["WARLOCK"] = classColors["WARLOCK"] or "|cff9482c9"
classColors["PALADIN"] = classColors["PALADIN"] or "|cfff58cba"
classColors["SHAMAN"] = classColors["SHAMAN"] or "|cfff58cba"

local LOCALIZED_CLASS_MAP = {
    -- English
    ["WARRIOR"] = "WARRIOR", ["MAGE"] = "MAGE", ["ROGUE"] = "ROGUE", ["DRUID"] = "DRUID",
    ["HUNTER"] = "HUNTER", ["PRIEST"] = "PRIEST", ["WARLOCK"] = "WARLOCK", ["PALADIN"] = "PALADIN", ["SHAMAN"] = "SHAMAN",
    ["Warrior"] = "WARRIOR", ["Mage"] = "MAGE", ["Rogue"] = "ROGUE", ["Druid"] = "DRUID",
    ["Hunter"] = "HUNTER", ["Priest"] = "PRIEST", ["Warlock"] = "WARLOCK", ["Paladin"] = "PALADIN", ["Shaman"] = "SHAMAN",
    -- German
    ["Krieger"] = "WARRIOR", ["Magier"] = "MAGE", ["Schurke"] = "ROGUE", ["Druide"] = "DRUID",
    ["Jäger"] = "HUNTER", ["Priester"] = "PRIEST", ["Hexenmeister"] = "WARLOCK", ["Paladin"] = "PALADIN", ["Schamane"] = "SHAMAN",
    -- French
    ["Guerrier"] = "WARRIOR", ["Voleur"] = "ROGUE", ["Chasseur"] = "HUNTER", ["Prêtre"] = "PRIEST",
    ["Démoniste"] = "WARLOCK", ["Chaman"] = "SHAMAN",
    -- Russian
    ["Воин"] = "WARRIOR", ["Маг"] = "MAGE", ["Разбойник"] = "ROGUE", ["Друид"] = "DRUID",
    ["Охотник"] = "HUNTER", ["Жрец"] = "PRIEST", ["Чернокнижник"] = "WARLOCK", ["Паладин"] = "PALADIN", ["Шаман"] = "SHAMAN",
}

function AutoBG_GetClassColor(classOrToken)
    if not classOrToken then return nil end
    local token = LOCALIZED_CLASS_MAP[classOrToken]
    if not token and type(classOrToken) == "string" then
        token = string.upper(classOrToken)
    end
    if token and classColors[token] then
        return classColors[token], token
    end
    return nil, token
end

function AutoBG_FindPlayerClass(playerName)
    if not playerName or playerName == "" then return nil end
    local cleanTarget = playerName
    local dash = string.find(cleanTarget, "-")
    if dash then cleanTarget = string.sub(cleanTarget, 1, dash - 1) end
    cleanTarget = string.gsub(cleanTarget, "^%s*(.-)%s*$", "%1")

    -- 1. Check Scoreboard
    local numScores = (GetNumBattlefieldScores and GetNumBattlefieldScores()) or 0
    for i = 1, numScores do
        local name, _, _, _, _, _, _, _, localizedClass, classToken = GetBattlefieldScore(i)
        if name then
            local clean = name
            local d = string.find(clean, "-")
            if d then clean = string.sub(clean, 1, d - 1) end
            clean = string.gsub(clean, "^%s*(.-)%s*$", "%1")
            if clean == cleanTarget then
                return classToken or localizedClass
            end
        end
    end

    -- 2. Check Raid / Party
    local numRaid = (GetNumRaidMembers and GetNumRaidMembers()) or 0
    if numRaid > 0 then
        for i = 1, numRaid do
            if UnitName("raid" .. i) == cleanTarget then
                local _, token = UnitClass("raid" .. i)
                return token
            end
        end
    else
        local numParty = (GetNumPartyMembers and GetNumPartyMembers()) or 0
        for i = 1, numParty do
            if UnitName("party" .. i) == cleanTarget then
                local _, token = UnitClass("party" .. i)
                return token
            end
        end
    end

    if UnitName("player") == cleanTarget then
        local _, token = UnitClass("player")
        return token
    end

    return nil
end

local notifiedQueues = {}
local hasHandledEnd = false
local lastPlayedBG = nil
local pendingAutoRejoin = nil

local frame = CreateFrame("Frame", "AutoBGFrame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("UPDATE_BATTLEFIELD_STATUS")
frame:RegisterEvent("BATTLEFIELDS_SHOW")
frame:RegisterEvent("PLAYER_DEAD")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("CHAT_MSG_BG_SYSTEM_NEUTRAL")
frame:RegisterEvent("CHAT_MSG_BG_SYSTEM_ALLIANCE")
frame:RegisterEvent("CHAT_MSG_BG_SYSTEM_HORDE")
frame:RegisterEvent("CHAT_MSG_SYSTEM")

function AutoBG_PlayNotificationSound()
    PlaySound("ReadyCheck")
    AutoBG_TimerAfter(0.8, function() PlaySound("ReadyCheck") end)
    AutoBG_TimerAfter(1.6, function() PlaySound("ReadyCheck") end)
end

local PlayLoudNotification = AutoBG_PlayNotificationSound

local function GetBGMapIndex(bgName)
    if not bgName then return 1, "Warsong Gulch" end
    local lower = string.lower(bgName)
    if string.find(lower, "arathi") or string.find(lower, "ab") then
        return 2, "Arathi Basin"
    elseif string.find(lower, "alterac") or string.find(lower, "av") then
        return 3, "Alterac Valley"
    elseif string.find(lower, "thorn") or string.find(lower, "gorge") or string.find(lower, "tg") then
        return 4, "Thorn Gorge"
    elseif string.find(lower, "arena") then
        return 5, "Arena"
    else
        return 1, "Warsong Gulch"
    end
end

local function AutoBG_TriggerBattlegroundFinder(bgName)
    if not bgName or not AutoBG_Settings or not AutoBG_Settings.AutoRejoin then return end

    local mapId, cleanName = GetBGMapIndex(bgName)
    pendingAutoRejoin = cleanName

    print("|cFF00FF00AutoBG:|r Auto-rejoining " .. cleanName .. " via Battleground Finder...")

    -- 1. Direct 1.12 client request (triggers BATTLEFIELDS_SHOW packet)
    if RequestBattlefieldList then
        RequestBattlefieldList(mapId)
    end

    -- 2. Search and click menu item if OctoWOW Battleground Finder menu is open
    local function searchAndClick(parent)
        if not parent or not parent.GetChildren then return false end
        local children = { parent:GetChildren() }
        for i = 1, table.getn(children) do
            local child = children[i]
            if child and child.GetText and child:GetText() then
                local text = child:GetText()
                if string.find(string.lower(text), string.lower(cleanName)) then
                    if child.Click then
                        child:Click()
                        return true
                    elseif child:GetScript("OnClick") then
                        child:GetScript("OnClick")()
                        return true
                    end
                end
            end
        end
        return false
    end

    searchAndClick(UIParent)

    -- 3. If needed, click the Battleground Finder minimap button to open dropdown
    local function findMinimapButton()
        if not Minimap or not Minimap.GetChildren then return nil end
        local mmChildren = { Minimap:GetChildren() }
        for i = 1, table.getn(mmChildren) do
            local btn = mmChildren[i]
            if btn then
                local name = btn:GetName() or ""
                local lowerName = string.lower(name)
                if string.find(lowerName, "battleground") or string.find(lowerName, "bg") or string.find(lowerName, "finder") or string.find(lowerName, "pvp") then
                    return btn
                end
            end
        end
        return nil
    end

    local mmBtn = findMinimapButton()
    if mmBtn then
        if mmBtn.Click then
            mmBtn:Click()
        elseif mmBtn:GetScript("OnClick") then
            mmBtn:GetScript("OnClick")()
        end

        AutoBG_TimerAfter(0.15, function()
            searchAndClick(UIParent)
        end)
    end
end

local function HandleMatchEnd()
    if hasHandledEnd then return end
    hasHandledEnd = true

    -- Instant leave
    if AutoBG_Settings and AutoBG_Settings.AutoLeave then
        LeaveBattlefield(0)
        print("|cFF00FF00AutoBG:|r Instantly left battleground.")
    end
end

frame:SetScript("OnEvent", function()
    local ev = event
    local a1 = arg1

    if ev == "ADDON_LOADED" and a1 == addonName then
        if not AutoBG_Settings then
            AutoBG_Settings = defaultSettings
        else
            for k, v in pairs(defaultSettings) do
                if AutoBG_Settings[k] == nil then
                    AutoBG_Settings[k] = v
                end
            end
            if AutoBG_Settings.Positions == nil then
                AutoBG_Settings.Positions = {}
            end
        end
        print("|cFF00FF00AutoBG:|r Loaded. Type |cFFFFFF00/abg|r for options.")

        if AutoBG_Settings.HideCastbar and CastingBarFrame then
            CastingBarFrame:UnregisterAllEvents()
            CastingBarFrame:Hide()
        end

        if AutoBG_Settings.HideStanceBar and AutoBG_UpdateStanceBar then
            AutoBG_UpdateStanceBar()
        end

    elseif ev == "PLAYER_ENTERING_WORLD" then
        if AutoBG_Settings and AutoBG_Settings.HideStanceBar and AutoBG_UpdateStanceBar then
            AutoBG_UpdateStanceBar()
        end

        local inInstance, instanceType = IsInInstance()
        if inInstance and instanceType == "pvp" then
            local zone = (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()) or ""
            if zone ~= "" then
                lastPlayedBG = zone
            end
            hasHandledEnd = false
            pendingAutoRejoin = nil
        else
            -- Outside BG: if a match just ended, automatically re-open Battleground Finder to join next game
            if hasHandledEnd and lastPlayedBG and AutoBG_Settings and AutoBG_Settings.AutoRejoin then
                local bgToQueue = lastPlayedBG
                AutoBG_TimerAfter(0.25, function()
                    AutoBG_TriggerBattlegroundFinder(bgToQueue)
                end)
            else
                hasHandledEnd = false
            end
        end

    elseif ev == "BATTLEFIELDS_SHOW" then
        if pendingAutoRejoin or (hasHandledEnd and lastPlayedBG and AutoBG_Settings and AutoBG_Settings.AutoRejoin) then
            local bgTitle = pendingAutoRejoin or (GetBattlefieldInfo and GetBattlefieldInfo()) or "Battleground"
            JoinBattlefield(0)
            if BattlefieldFrame and BattlefieldFrame:IsShown() then
                HideUIPanel(BattlefieldFrame)
            end
            print("|cFF00FF00AutoBG:|r Successfully joined queue for |cFFFFFF00" .. bgTitle .. "|r!")
            pendingAutoRejoin = nil
            hasHandledEnd = false
        end

    elseif ev == "CHAT_MSG_BG_SYSTEM_NEUTRAL" or ev == "CHAT_MSG_BG_SYSTEM_ALLIANCE" or ev == "CHAT_MSG_BG_SYSTEM_HORDE" or ev == "CHAT_MSG_SYSTEM" then
        if a1 and (string.find(a1, "wins!") or string.find(a1, "won the battle") or string.find(a1, "wins the battle") or string.find(a1, "victorious!")) then
            local inInstance, instanceType = IsInInstance()
            if inInstance and instanceType == "pvp" then
                HandleMatchEnd()
            end
        end

    elseif ev == "UPDATE_BATTLEFIELD_STATUS" then
        if not AutoBG_Settings then return end

        local function checkBG(id)
            local status, mapName, instanceID = GetBattlefieldStatus(id)

            if status == "confirm" then
                if not notifiedQueues[id] then
                    notifiedQueues[id] = true

                    -- Instant Auto-Accept (0 ms delay)
                    if AutoBG_Settings.AutoAccept then
                        AcceptBattlefieldPort(id, 1)
                        if StaticPopup_Hide then
                            StaticPopup_Hide("CONFIRM_BATTLEFIELD_ENTRY")
                        end
                        print("|cFF00FF00AutoBG:|r Instant Auto-Accepted " .. (mapName or "Battleground") .. "!")
                    end

                    if AutoBG_Settings.NotifySound then
                        PlayLoudNotification()
                    end

                    if AutoBG_Settings.FlashTaskbar and FlashClientIcon then
                        FlashClientIcon()
                    end

                    if not AutoBG_Settings.AutoAccept then
                        print("|cFF00FF00AutoBG:|r Queue is ready for " .. (mapName or "Battleground") .. "!")
                    end
                end
            elseif status == "active" or status == "none" then
                notifiedQueues[id] = false

                if status == "active" then
                    if mapName and mapName ~= "" then
                        lastPlayedBG = mapName
                    end

                    -- Check if winner is already declared
                    if GetBattlefieldWinner() then
                        HandleMatchEnd()
                    end
                end
            end
        end

        local maxQueues = MAX_BATTLEFIELD_QUEUES or 3
        for i = 1, maxQueues do
            checkBG(i)
        end

    elseif ev == "PLAYER_DEAD" then
        if AutoBG_Settings and AutoBG_Settings.AutoRelease then
            local inInstance, instanceType = IsInInstance()
            if inInstance and instanceType == "pvp" then
                local hasSS = (HasSoulstone and HasSoulstone()) or (CanUseSoulstone and CanUseSoulstone())
                if not hasSS then
                    RepopMe()
                    if StaticPopup_Hide then
                        StaticPopup_Hide("DEATH")
                    end
                else
                    print("|cFF00FF00AutoBG:|r Self-resurrection available. Not releasing.")
                end
            end
        end
    end
end)

-- Safe BattlefieldFrame OnShow Hook
if BattlefieldFrame then
    local orig_BattlefieldFrame_OnShow = BattlefieldFrame:GetScript("OnShow")
    BattlefieldFrame:SetScript("OnShow", function()
        if orig_BattlefieldFrame_OnShow then orig_BattlefieldFrame_OnShow() end
        if pendingAutoRejoin or (hasHandledEnd and lastPlayedBG and AutoBG_Settings and AutoBG_Settings.AutoRejoin) then
            local bgTitle = pendingAutoRejoin or (GetBattlefieldInfo and GetBattlefieldInfo()) or "Battleground"
            JoinBattlefield(0)
            HideUIPanel(BattlefieldFrame)
            print("|cFF00FF00AutoBG:|r Successfully joined queue for |cFFFFFF00" .. bgTitle .. "|r!")
            pendingAutoRejoin = nil
            hasHandledEnd = false
        end
    end)
end

-- Vanilla 1.12 Scoreboard hook
local orig_WorldStateScoreFrame_Update = WorldStateScoreFrame_Update
WorldStateScoreFrame_Update = function()
    if orig_WorldStateScoreFrame_Update then
        orig_WorldStateScoreFrame_Update()
    end
    if not AutoBG_Settings then return end

    local offset = (WorldStateScoreScrollFrame and FauxScrollFrame_GetOffset(WorldStateScoreScrollFrame)) or 0
    local maxButtons = MAX_WORLDSTATE_SCORE_BUTTONS or 20
    for i = 1, maxButtons do
        local scoreIndex = offset + i
        local name, killingBlows, honorableKills, deaths, honorGained, faction, rank, race, class, classToken = GetBattlefieldScore(scoreIndex)
        if name and name ~= "" then
            local nameText = getglobal("WorldStateScoreButton" .. i .. "NameText") or getglobal("WorldStateScoreButton" .. i .. "Name")
            if nameText then
                -- Strip "- Realm" suffix
                local cleanName = name
                local dashPos = string.find(cleanName, "-")
                if dashPos then
                    cleanName = string.sub(cleanName, 1, dashPos - 1)
                end
                cleanName = string.gsub(cleanName, "^%s*(.-)%s*$", "%1")

                if AutoBG_Settings.ScoreColor then
                    local color = AutoBG_GetClassColor(classToken or class)

                    if color and color ~= "" then
                        nameText:SetText(color .. cleanName .. "|r")
                    else
                        nameText:SetText(cleanName)
                        if faction == 0 then
                            nameText:SetTextColor(1.0, 0.1, 0.1) -- Horde Red
                        else
                            nameText:SetTextColor(0.0, 0.68, 1.0) -- Alliance Blue
                        end
                    end
                else
                    nameText:SetText(cleanName)
                    if faction == 0 then
                        nameText:SetTextColor(1.0, 0.1, 0.1)
                    else
                        nameText:SetTextColor(0.0, 0.68, 1.0)
                    end
                end
            end
        end
    end
end

-- Slash Commands
SLASH_AUTOBG1 = "/abg"
SLASH_AUTOBG2 = "/autobg"
SlashCmdList["AUTOBG"] = function(msg)
    local cmd = ""
    if msg then
        cmd = string.lower(string.gsub(msg, "^%s*(.-)%s*$", "%1"))
    end

    if cmd == "s" or cmd == "sound" then
        AutoBG_Settings.NotifySound = not AutoBG_Settings.NotifySound
        print("|cFF00FF00AutoBG:|r Loud Sound Notification is now " .. (AutoBG_Settings.NotifySound and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r"))
        if AutoBG_Options_Refresh then AutoBG_Options_Refresh() end
    elseif cmd == "f" or cmd == "flash" then
        AutoBG_Settings.FlashTaskbar = not AutoBG_Settings.FlashTaskbar
        print("|cFF00FF00AutoBG:|r Taskbar Flashing is now " .. (AutoBG_Settings.FlashTaskbar and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r"))
        if AutoBG_Options_Refresh then AutoBG_Options_Refresh() end
    elseif cmd == "a" or cmd == "accept" then
        AutoBG_Settings.AutoAccept = not AutoBG_Settings.AutoAccept
        print("|cFF00FF00AutoBG:|r Auto-Accept Queue Pop is now " .. (AutoBG_Settings.AutoAccept and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r"))
        if AutoBG_Options_Refresh then AutoBG_Options_Refresh() end
    elseif cmd == "j" or cmd == "rejoin" or cmd == "requeue" then
        AutoBG_Settings.AutoRejoin = not AutoBG_Settings.AutoRejoin
        print("|cFF00FF00AutoBG:|r Auto-Rejoin BG is now " .. (AutoBG_Settings.AutoRejoin and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r"))
        if AutoBG_Options_Refresh then AutoBG_Options_Refresh() end
    elseif cmd == "l" or cmd == "leave" then
        AutoBG_Settings.AutoLeave = not AutoBG_Settings.AutoLeave
        print("|cFF00FF00AutoBG:|r Auto-Leave is now " .. (AutoBG_Settings.AutoLeave and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r"))
        if AutoBG_Options_Refresh then AutoBG_Options_Refresh() end
    elseif cmd == "c" or cmd == "color" then
        AutoBG_Settings.ScoreColor = not AutoBG_Settings.ScoreColor
        print("|cFF00FF00AutoBG:|r Scoreboard Class Colors is now " .. (AutoBG_Settings.ScoreColor and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r"))
        if AutoBG_Options_Refresh then AutoBG_Options_Refresh() end
    elseif cmd == "r" or cmd == "release" then
        AutoBG_Settings.AutoRelease = not AutoBG_Settings.AutoRelease
        print("|cFF00FF00AutoBG:|r Auto-Release is now " .. (AutoBG_Settings.AutoRelease and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r"))
        if AutoBG_Options_Refresh then AutoBG_Options_Refresh() end
    elseif cmd == "t" or cmd == "test" then
        AutoBG_Settings.TestAllTimers = not AutoBG_Settings.TestAllTimers
        print("|cFF00FF00AutoBG:|r Test Mode (All Timers) is now " .. (AutoBG_Settings.TestAllTimers and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r"))
        if AutoBG_Options_Refresh then AutoBG_Options_Refresh() end
    elseif cmd == "stealth" or cmd == "stance" then
        AutoBG_Settings.HideStanceBar = not AutoBG_Settings.HideStanceBar
        print("|cFF00FF00AutoBG:|r Hide Stealth/Stance Bar is now " .. (AutoBG_Settings.HideStanceBar and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r"))
        if AutoBG_UpdateStanceBar then AutoBG_UpdateStanceBar() end
        if AutoBG_Options_Refresh then AutoBG_Options_Refresh() end
    elseif cmd == "reset" then
        AutoBG_Settings = nil
        print("|cFF00FF00AutoBG:|r Settings reset to default. Reloading UI...")
        ReloadUI()
    elseif cmd == "help" then
        print("|cFF00FF00AutoBG Commands:|r")
        print("  |cFFFFFF00/abg|r - Open options window")
        print("  |cFFFFFF00/abg s|r - Toggle sound alerts")
        print("  |cFFFFFF00/abg f|r - Toggle taskbar flashing")
        print("  |cFFFFFF00/abg a|r - Toggle auto-accept queue pop")
        print("  |cFFFFFF00/abg l|r - Toggle auto-leave BG on end")
        print("  |cFFFFFF00/abg j|r - Toggle auto-rejoin BG after exit")
        print("  |cFFFFFF00/abg r|r - Toggle auto-release")
        print("  |cFFFFFF00/abg c|r - Toggle scoreboard class colors")
        print("  |cFFFFFF00/abg stealth|r - Toggle hide stealth / stance bar")
        print("  |cFFFFFF00/abg test|r - Toggle test mode to reposition timers")
        print("  |cFFFFFF00/abg reset|r - Reset all settings and positions")
    else
        if AutoBG_OptionsPanel then
            if AutoBG_OptionsPanel:IsShown() then
                AutoBG_OptionsPanel:Hide()
            else
                AutoBG_OptionsPanel:Show()
            end
        end
    end
end
