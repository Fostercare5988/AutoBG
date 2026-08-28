-- AutoBG for World of Warcraft 1.12.1 (Vanilla / OctoWoW)
-- Author & Maintainer: Fostercare5988
-- Built natively for SuperWoW 2.2+, NamPower 4.6.2+, UnitXP SP3, DXVK 3.0.2+

local addonName = "AutoBG"

-- Direct C++ Engine Timer Interface
function AutoBG_TimerAfter(delay, func)
    if C_Timer and C_Timer.After then
        C_Timer.After(delay, func)
    elseif func then
        func()
    end
end

-- Pre-allocated static Unit ID arrays (Eliminates GC string allocations)
local RAID_UNITS = {}
local PARTY_UNITS = {}
for i = 1, 40 do RAID_UNITS[i] = "raid" .. i end
for i = 1, 4 do PARTY_UNITS[i] = "party" .. i end

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
    ChatMessages = true,
    AutoAccept = false,
    AutoAcceptDelay = 0,
    AutoLeave = true,
    AutoRejoin = false,
    AutoQueueLogin = false,
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
    LastPlayedBG = nil,
    Positions = {},
}

function AutoBG_Print(msg, force)
    if (force or (AutoBG_Settings and AutoBG_Settings.ChatMessages)) and DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00AutoBG:|r " .. msg)
    end
end

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

-- Class Color Table
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

local CLASS_MAP = {
    ["WARRIOR"] = "WARRIOR", ["MAGE"] = "MAGE", ["ROGUE"] = "ROGUE", ["DRUID"] = "DRUID",
    ["HUNTER"] = "HUNTER", ["PRIEST"] = "PRIEST", ["WARLOCK"] = "WARLOCK", ["PALADIN"] = "PALADIN", ["SHAMAN"] = "SHAMAN",
    ["Warrior"] = "WARRIOR", ["Mage"] = "MAGE", ["Rogue"] = "ROGUE", ["Druid"] = "DRUID",
    ["Hunter"] = "HUNTER", ["Priest"] = "PRIEST", ["Warlock"] = "WARLOCK", ["Paladin"] = "PALADIN", ["Shaman"] = "SHAMAN",
}

function AutoBG_GetClassColor(classOrToken)
    if not classOrToken then return nil end
    local token = CLASS_MAP[classOrToken] or (type(classOrToken) == "string" and string.upper(classOrToken))
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

    -- 2. Check Raid / Party using pre-allocated unit arrays
    local numRaid = (GetNumRaidMembers and GetNumRaidMembers()) or 0
    if numRaid > 0 then
        for i = 1, numRaid do
            if UnitName(RAID_UNITS[i]) == cleanTarget then
                local _, token = UnitClass(RAID_UNITS[i])
                return token
            end
        end
    else
        local numParty = (GetNumPartyMembers and GetNumPartyMembers()) or 0
        for i = 1, numParty do
            if UnitName(PARTY_UNITS[i]) == cleanTarget then
                local _, token = UnitClass(PARTY_UNITS[i])
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

local function GetBGButtonIndex(bgName)
    if not bgName then return 4, "Warsong Gulch" end
    local lower = string.lower(bgName)
    if string.find(lower, "arathi") or string.find(lower, "ab") then
        return 5, "Arathi Basin"
    elseif string.find(lower, "alterac") or string.find(lower, "av") then
        return 7, "Alterac Valley"
    elseif string.find(lower, "thorn") or string.find(lower, "gorge") or string.find(lower, "tg") then
        return 6, "Thorn Gorge"
    elseif string.find(lower, "arena") then
        return 3, "Arena"
    else
        return 4, "Warsong Gulch"
    end
end

local function ClickFrame(f)
    if not f then return false end
    if f.Click then
        f:Click()
        return true
    end
    local onClick = nil
    pcall(function() onClick = f:GetScript("OnClick") end)
    if onClick then
        onClick()
        return true
    end
    return false
end

function AutoBG_TriggerBattlegroundFinder(bgName)
    local btnIdx, cleanName = GetBGButtonIndex(bgName)
    pendingAutoRejoin = cleanName

    -- Ensure any existing dropdown is cleanly closed before reopening
    if CloseDropDownMenus then
        CloseDropDownMenus()
    end

    local mmBtn = getglobal("TWMiniMapBattlefieldFrame") or getglobal("MiniMapBattlefieldFrame")
    if mmBtn then
        ClickFrame(mmBtn)
    end

    -- Allow 0.08s for dropdown items to construct and render
    AutoBG_TimerAfter(0.08, function()
        local targetFound = false
        local lowerTarget = string.lower(cleanName)

        -- 1. Scan across all potential DropDownList1 buttons matching the BG name
        for i = 1, 12 do
            local dropBtn = getglobal("DropDownList1Button" .. i)
            if dropBtn and dropBtn:IsShown() then
                local text = dropBtn:GetText()
                if not text then
                    local textObj = getglobal("DropDownList1Button" .. i .. "NormalText")
                    if textObj and textObj.GetText then text = textObj:GetText() end
                end
                if text and string.find(string.lower(text), lowerTarget) then
                    ClickFrame(dropBtn)
                    targetFound = true
                    break
                end
            end
        end

        -- 2. Fallback to direct button index if text scan was ambiguous
        if not targetFound then
            local b = getglobal("DropDownList1Button" .. btnIdx)
            if b and b:IsShown() then
                ClickFrame(b)
            end
        end
    end)
end

-- Global Macro Button: /click AutoBG_QuickQueueButton or /abg q
-- Multi-BG Auto-Queue Engine (WSG, AB, AV)
local isAutoQueueing = false
local hasQueuedOnLogin = false

function AutoBG_QueueAllBGs()
    if isAutoQueueing then return end

    local inInstance, instanceType = IsInInstance()
    if inInstance and instanceType == "pvp" then return end

    local bgsToQueue = {"Warsong Gulch", "Arathi Basin", "Alterac Valley"}
    local queueQueue = {}

    -- Check which BGs we are NOT yet queued for
    local maxQueues = MAX_BATTLEFIELD_QUEUES or 3
    for _, bg in ipairs(bgsToQueue) do
        local alreadyQueued = false
        for i = 1, maxQueues do
            local status, mapName = GetBattlefieldStatus(i)
            if status and status ~= "none" and mapName and string.find(string.lower(mapName), string.lower(bg)) then
                alreadyQueued = true
                break
            end
        end
        if not alreadyQueued then
            table.insert(queueQueue, bg)
        end
    end

    local totalToQueue = table.getn(queueQueue)
    if totalToQueue == 0 then
        AutoBG_Print("Already queued for all 3 Battlegrounds (WSG, AB, AV).")
        return
    end

    isAutoQueueing = true
    local queueIdx = 1

    local function StepQueue()
        if queueIdx > totalToQueue then
            isAutoQueueing = false
            AutoBG_Print("Auto-Queue complete: Queued for WSG, AB, and AV!")
            return
        end

        local currentBG = queueQueue[queueIdx]
        queueIdx = queueIdx + 1

        AutoBG_Print("Auto-queuing for |cFFFFFF00" .. currentBG .. "|r (" .. (queueIdx - 1) .. "/" .. totalToQueue .. ")...")
        AutoBG_TriggerBattlegroundFinder(currentBG)

        -- 2.2s delay between BG requests to allow server handshake & dropdown reset
        AutoBG_TimerAfter(2.2, StepQueue)
    end

    StepQueue()
end

-- Global Macro Button: /click AutoBG_QuickQueueButton or /abg q
local quickQueueBtn = CreateFrame("Button", "AutoBG_QuickQueueButton", UIParent)
quickQueueBtn:SetScript("OnClick", function()
    local bg = (AutoBG_Settings and AutoBG_Settings.LastPlayedBG) or lastPlayedBG or "Warsong Gulch"
    AutoBG_Print("Quick-queue triggered for |cFFFFFF00" .. bg .. "|r...")
    AutoBG_TriggerBattlegroundFinder(bg)
end)

local function HandleMatchEnd()
    if hasHandledEnd then return end
    hasHandledEnd = true

    -- Ensure lastPlayedBG is captured and persisted across sessions
    local zone = (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()) or ""
    if zone ~= "" then
        lastPlayedBG = zone
        if AutoBG_Settings then
            AutoBG_Settings.LastPlayedBG = zone
        end
    end
    if AutoBG_Settings and AutoBG_Settings.AutoRejoin and lastPlayedBG then
        local _, cleanName = GetBGButtonIndex(lastPlayedBG)
        pendingAutoRejoin = cleanName
    end

    -- Instant leave
    if AutoBG_Settings and AutoBG_Settings.AutoLeave then
        LeaveBattlefield(0)
        AutoBG_Print("Instantly left |cFFFFFF00" .. (lastPlayedBG or "battleground") .. "|r.")
    end
end

-- Hook StaticPopup_Show to intercept and auto-confirm CONFIRM_BATTLEFIELD_ENTRY with configurable delay
local orig_StaticPopup_Show = StaticPopup_Show
StaticPopup_Show = function(which, text_arg1, text_arg2, data)
    if which == "CONFIRM_BATTLEFIELD_ENTRY" and AutoBG_Settings and AutoBG_Settings.AutoAccept then
        local delay = AutoBG_Settings.AutoAcceptDelay or 0
        if delay <= 0 then
            local id = data or 1
            AcceptBattlefieldPort(id, 1)
            AutoBG_Print("Instant Auto-Accepted |cFFFFFF00" .. (text_arg1 or "Battleground") .. "|r!")
            return nil
        end
    end
    if orig_StaticPopup_Show then
        return orig_StaticPopup_Show(which, text_arg1, text_arg2, data)
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

        AutoBG_Print("Successfully loaded SuperWoW 2.2+, UnitXP SP3, NamPower. Type |cFFFFFF00/abg|r for options.", true)

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
                if AutoBG_Settings then
                    AutoBG_Settings.LastPlayedBG = zone
                end
            end
            hasHandledEnd = false
            pendingAutoRejoin = nil
        else
            -- Outside BG: if a match just ended, instantly trigger Battleground Finder
            local targetRejoin = lastPlayedBG or (AutoBG_Settings and AutoBG_Settings.LastPlayedBG)
            if hasHandledEnd and targetRejoin and AutoBG_Settings and AutoBG_Settings.AutoRejoin then
                local bgToQueue = targetRejoin
                AutoBG_TimerAfter(0.05, function()
                    if pendingAutoRejoin then
                        AutoBG_TriggerBattlegroundFinder(bgToQueue)
                    end
                end)
                AutoBG_TimerAfter(0.3, function()
                    if pendingAutoRejoin then
                        AutoBG_TriggerBattlegroundFinder(bgToQueue)
                    end
                end)
            else
                hasHandledEnd = false
            end

            -- Auto-Queue on login (runs once per session after 3s)
            if AutoBG_Settings and AutoBG_Settings.AutoQueueLogin and not hasQueuedOnLogin then
                hasQueuedOnLogin = true
                AutoBG_TimerAfter(3.0, function()
                    AutoBG_QueueAllBGs()
                end)
            end
        end

    elseif ev == "BATTLEFIELDS_SHOW" then
        if pendingAutoRejoin or (hasHandledEnd and lastPlayedBG and AutoBG_Settings and AutoBG_Settings.AutoRejoin) then
            local bgTitle = pendingAutoRejoin or (GetBattlefieldInfo and GetBattlefieldInfo()) or "Battleground"
            JoinBattlefield(0)
            if BattlefieldFrame and BattlefieldFrame:IsShown() then
                HideUIPanel(BattlefieldFrame)
            end
            AutoBG_Print("Successfully queued for |cFFFFFF00" .. bgTitle .. "|r via Battleground Finder!")
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

                    -- Auto-Accept with Configurable Delay
                    if AutoBG_Settings.AutoAccept then
                        local delay = AutoBG_Settings.AutoAcceptDelay or 0
                        local queueId = id
                        local bgName = mapName or "Battleground"

                        if delay <= 0 then
                            -- Instant (0ms)
                            AcceptBattlefieldPort(queueId, 1)
                            if StaticPopup_Hide then
                                StaticPopup_Hide("CONFIRM_BATTLEFIELD_ENTRY")
                            end
                            for s = 1, 4 do
                                local dlg = getglobal("StaticPopup" .. s)
                                if dlg and dlg:IsShown() and dlg.which == "CONFIRM_BATTLEFIELD_ENTRY" then
                                    dlg:Hide()
                                end
                            end
                            AutoBG_Print("Instant Auto-Accepted |cFFFFFF00" .. bgName .. "|r!")
                        else
                            -- Delayed Accept (Wait X seconds)
                            AutoBG_Print("Queue popped for |cFFFFFF00" .. bgName .. "|r! Auto-entering in |cFFFFFF00" .. delay .. "s|r...")
                            AutoBG_TimerAfter(delay, function()
                                if GetBattlefieldStatus(queueId) == "confirm" then
                                    AcceptBattlefieldPort(queueId, 1)
                                    if StaticPopup_Hide then
                                        StaticPopup_Hide("CONFIRM_BATTLEFIELD_ENTRY")
                                    end
                                    for s = 1, 4 do
                                        local dlg = getglobal("StaticPopup" .. s)
                                        if dlg and dlg:IsShown() and dlg.which == "CONFIRM_BATTLEFIELD_ENTRY" then
                                            dlg:Hide()
                                        end
                                    end
                                    AutoBG_Print("Auto-Entered |cFFFFFF00" .. bgName .. "|r after |cFFFFFF00" .. delay .. "s|r delay!")
                                end
                            end)
                        end
                    end

                    if AutoBG_Settings.NotifySound then
                        PlayLoudNotification()
                    end

                    if AutoBG_Settings.FlashTaskbar and FlashClientIcon then
                        FlashClientIcon()
                    end

                    if not AutoBG_Settings.AutoAccept then
                        AutoBG_Print("Queue is ready for |cFFFFFF00" .. (mapName or "Battleground") .. "|r! (Queue #" .. id .. ")")
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
                    AutoBG_Print("Self-resurrection available. Preserving spirit.")
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
            AutoBG_Print("Successfully queued for |cFFFFFF00" .. bgTitle .. "|r via Battleground Finder!")
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
    local raw = ""
    if msg then
        raw = string.gsub(msg, "^%s*(.-)%s*$", "%1")
    end

    local cmd, arg = "", ""
    local space = string.find(raw, " ")
    if space then
        cmd = string.lower(string.sub(raw, 1, space - 1))
        arg = string.lower(string.gsub(string.sub(raw, space + 1), "^%s*(.-)%s*$", "%1"))
    else
        cmd = string.lower(raw)
    end

    if cmd == "s" or cmd == "sound" then
        AutoBG_Settings.NotifySound = not AutoBG_Settings.NotifySound
        AutoBG_Print("Loud Sound Notification is now " .. (AutoBG_Settings.NotifySound and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r"), true)
        if AutoBG_Options_Refresh then AutoBG_Options_Refresh() end
    elseif cmd == "f" or cmd == "flash" then
        AutoBG_Settings.FlashTaskbar = not AutoBG_Settings.FlashTaskbar
        AutoBG_Print("Taskbar Flashing is now " .. (AutoBG_Settings.FlashTaskbar and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r"), true)
        if AutoBG_Options_Refresh then AutoBG_Options_Refresh() end
    elseif cmd == "msg" or cmd == "chat" or cmd == "messages" then
        AutoBG_Settings.ChatMessages = not AutoBG_Settings.ChatMessages
        AutoBG_Print("Chat Notifications are now " .. (AutoBG_Settings.ChatMessages and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r"), true)
        if AutoBG_Options_Refresh then AutoBG_Options_Refresh() end
    elseif cmd == "a" or cmd == "accept" then
        AutoBG_Settings.AutoAccept = not AutoBG_Settings.AutoAccept
        AutoBG_Print("Auto-Accept Queue Pop is now " .. (AutoBG_Settings.AutoAccept and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r"), true)
        if AutoBG_Options_Refresh then AutoBG_Options_Refresh() end
    elseif cmd == "j" or cmd == "autorejoin" then
        AutoBG_Settings.AutoRejoin = not AutoBG_Settings.AutoRejoin
        AutoBG_Print("Auto-Rejoin BG on Exit is now " .. (AutoBG_Settings.AutoRejoin and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r"), true)
        if AutoBG_Options_Refresh then AutoBG_Options_Refresh() end
    elseif cmd == "l" or cmd == "leave" then
        AutoBG_Settings.AutoLeave = not AutoBG_Settings.AutoLeave
        AutoBG_Print("Auto-Leave is now " .. (AutoBG_Settings.AutoLeave and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r"), true)
        if AutoBG_Options_Refresh then AutoBG_Options_Refresh() end
    elseif cmd == "c" or cmd == "color" then
        AutoBG_Settings.ScoreColor = not AutoBG_Settings.ScoreColor
        AutoBG_Print("Scoreboard Class Colors is now " .. (AutoBG_Settings.ScoreColor and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r"), true)
        if AutoBG_Options_Refresh then AutoBG_Options_Refresh() end
    elseif cmd == "r" or cmd == "release" then
        AutoBG_Settings.AutoRelease = not AutoBG_Settings.AutoRelease
        AutoBG_Print("Auto-Release is now " .. (AutoBG_Settings.AutoRelease and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r"), true)
        if AutoBG_Options_Refresh then AutoBG_Options_Refresh() end
    elseif cmd == "t" or cmd == "test" then
        AutoBG_Settings.TestAllTimers = not AutoBG_Settings.TestAllTimers
        AutoBG_Print("Test Mode (All Timers) is now " .. (AutoBG_Settings.TestAllTimers and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r"), true)
        if AutoBG_Options_Refresh then AutoBG_Options_Refresh() end
    elseif cmd == "stealth" or cmd == "stance" then
        AutoBG_Settings.HideStanceBar = not AutoBG_Settings.HideStanceBar
        AutoBG_Print("Hide Stealth/Stance Bar is now " .. (AutoBG_Settings.HideStanceBar and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r"), true)
        if AutoBG_UpdateStanceBar then AutoBG_UpdateStanceBar() end
        if AutoBG_Options_Refresh then AutoBG_Options_Refresh() end
    elseif cmd == "q" or cmd == "queue" or cmd == "join" or cmd == "rejoin" or cmd == "requeue" then
        if arg == "all" or arg == "3" or arg == "bg" or arg == "bgs" then
            AutoBG_QueueAllBGs()
            return
        end

        local targetBG = nil
        if arg ~= "" then
            if string.find(arg, "wsg") or string.find(arg, "war") then
                targetBG = "Warsong Gulch"
            elseif string.find(arg, "ab") or string.find(arg, "ara") then
                targetBG = "Arathi Basin"
            elseif string.find(arg, "av") or string.find(arg, "alt") then
                targetBG = "Alterac Valley"
            elseif string.find(arg, "tg") or string.find(arg, "thorn") or string.find(arg, "gorge") then
                targetBG = "Thorn Gorge"
            elseif string.find(arg, "arena") then
                targetBG = "Arena"
            end
        end

        if not targetBG then
            targetBG = (AutoBG_Settings and AutoBG_Settings.LastPlayedBG) or lastPlayedBG
        end

        if targetBG then
            if AutoBG_Settings then AutoBG_Settings.LastPlayedBG = targetBG end
            AutoBG_Print("Quick-queue triggered for |cFFFFFF00" .. targetBG .. "|r...", true)
            AutoBG_TriggerBattlegroundFinder(targetBG)
        else
            AutoBG_Print("No previous BG recorded. Opening Battleground Finder...", true)
            AutoBG_Print("  |cFFFFFF00Tip:|r Use |cFFFFFF00/abg q ab|r, |cFFFFFF00/abg q wsg|r, |cFFFFFF00/abg q av|r, or |cFFFFFF00/abg q tg|r", true)
            local mmBtn = FindBattlegroundFinderButton()
            if mmBtn then
                if mmBtn.Click then mmBtn:Click()
                else
                    pcall(function() if mmBtn:GetScript("OnClick") then mmBtn:GetScript("OnClick")() end end)
                end
            end
        end
    elseif cmd == "autoqueue" or cmd == "loginqueue" or cmd == "qlogin" then
        AutoBG_Settings.AutoQueueLogin = not AutoBG_Settings.AutoQueueLogin
        AutoBG_Print("Auto-Queue on Login is now " .. (AutoBG_Settings.AutoQueueLogin and "|cFF00FF00[ENABLED]|r" or "|cFFFF0000[DISABLED]|r"), true)
        if AutoBG_Options_Refresh then AutoBG_Options_Refresh() end
    elseif cmd == "delay" or cmd == "acceptdelay" then
        local val = tonumber(arg)
        if val then
            val = math.max(0, math.min(120, math.floor(val)))
            AutoBG_Settings.AutoAcceptDelay = val
            AutoBG_Print("Auto-Accept Enter Delay set to |cFFFFFF00" .. (val == 0 and "Instant (0s)" or (val .. "s")) .. "|r", true)
            if AutoBG_Options_Refresh then AutoBG_Options_Refresh() end
        else
            AutoBG_Print("Current Auto-Accept Enter Delay: |cFFFFFF00" .. ((AutoBG_Settings.AutoAcceptDelay or 0) == 0 and "Instant (0s)" or (AutoBG_Settings.AutoAcceptDelay .. "s")) .. "|r (Use |cFFFFFF00/abg delay 60|r to change)", true)
        end
    elseif cmd == "reset" then
        AutoBG_Settings = nil
        AutoBG_Print("Settings reset to default. Reloading UI...", true)
        ReloadUI()
    elseif cmd == "help" then
        print("|cFF00FF00AutoBG Commands:|r")
        print("  |cFFFFFF00/abg|r - Open options window")
        print("  |cFFFFFF00/abg q|r - Quick-queue for last played BG")
        print("  |cFFFFFF00/abg q ab|r - Quick-queue for Arathi Basin")
        print("  |cFFFFFF00/abg q wsg|r - Quick-queue for Warsong Gulch")
        print("  |cFFFFFF00/abg q av|r - Quick-queue for Alterac Valley")
        print("  |cFFFFFF00/abg q tg|r - Quick-queue for Thorn Gorge")
        print("  |cFFFFFF00/abg a|r - Toggle auto-accept queue pop")
        print("  |cFFFFFF00/abg delay <sec>|r - Set auto-accept delay (0=instant, up to 30s)")
        print("  |cFFFFFF00/abg msg|r - Toggle chat status notifications")
        print("  |cFFFFFF00/abg s|r - Toggle sound alerts")
        print("  |cFFFFFF00/abg f|r - Toggle taskbar flashing")
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
