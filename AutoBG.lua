-- AutoBG for World of Warcraft 1.12.1 (Vanilla Enhanced)
-- Author & Maintainer: Fostercare5988
-- Built natively for ClassicAPI, SuperWoW 2.2+, NamPower 4.6.3+, UnitXP SP3, DXVK

-- Strict Engine Dependency Guard (Mandatory ClassicAPI v1.13.4+ & SuperWoW v2.2+)
if not (CLASSIC_API_VERSION and SUPERWOW_VERSION) then
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff2020[AutoBG Fatal Error]|r AutoBG requires ClassicAPI.dll (v1.13.4+) & SuperWoW (v2.2+)! Please ensure both DLLs are loaded.", 1, 0.2, 0.2)
    end
    return
end

local addonName = "AutoBG"

-- Native C++ Hardware Timer Wrapper (Zero GC overhead)
function AutoBG_TimerAfter(delay, func)
    if not func then return end
    if not delay or delay <= 0 then func() else C_Timer.After(delay, func) end
end

-- Pre-allocated static Unit ID arrays
local RAID_UNITS, PARTY_UNITS = {}, {}
for i = 1, 40 do RAID_UNITS[i] = "raid" .. i end
for i = 1, 4 do PARTY_UNITS[i] = "party" .. i end

-- Cached Zone State
local currentZoneText = ""
local currentZonePVP = false

local function UpdateZoneCache()
    currentZoneText = (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()) or ""
    local inInstance, instanceType = IsInInstance()
    currentZonePVP = (inInstance and instanceType == "pvp")
end

-- Frame Position Helpers
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
    NotifySound = true, FlashTaskbar = true, ChatMessages = true,
    AutoAccept = false, AutoAcceptDelay = 0, AutoLeave = true,
    AutoRejoin = false, AutoQueueLogin = false, ScoreColor = true,
    NodeColors = true, AutoRelease = true, ABTimers = true,
    AVTimers = true, RessTimer = true, QueueTimers = true,
    FCFrame = true, WSGTimers = true, HideCastbar = false,
    HideStanceBar = false, TestAllTimers = false, LastPlayedBG = nil,
    Positions = {}, SkipIfAFK = true,
}

local playerIsAFK = false

function AutoBG_IsPlayerAFK()
    if UnitIsAFK and UnitIsAFK("player") then
        return true
    end
    return playerIsAFK
end

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
            local btn = _G["ShapeshiftButton" .. i]
            if btn then btn:Hide(); btn:SetAlpha(0) end
        end
    end
end

-- Hook stance updates using modern hooksecurefunc (Rule B10)
hooksecurefunc("ShapeshiftBar_Update", function()
    if AutoBG_Settings and AutoBG_Settings.HideStanceBar then AutoBG_UpdateStanceBar() end
end)
hooksecurefunc("UIParent_ManageFramePositions", function()
    if AutoBG_Settings and AutoBG_Settings.HideStanceBar then AutoBG_UpdateStanceBar() end
end)


-- Class Color Table
local classColors = {
    WARRIOR = "|cffc79c6e", MAGE = "|cff69ccf0", ROGUE = "|cfffff569",
    DRUID = "|cffff7d0a", HUNTER = "|cffabd473", PRIEST = "|cffffffff",
    WARLOCK = "|cff9482c9", PALADIN = "|cfff58cba", SHAMAN = "|cfff58cba"
}
if RAID_CLASS_COLORS then
    for class, color in pairs(RAID_CLASS_COLORS) do
        classColors[class] = string.format("|cff%02x%02x%02x", color.r * 255, color.g * 255, color.b * 255)
    end
end

function AutoBG_GetClassColor(classOrToken)
    if not classOrToken then return nil end
    local token = string.upper(classOrToken)
    return classColors[token], token
end

function AutoBG_FindPlayerClass(playerName)
    if not playerName or playerName == "" then return nil end
    local clean = string.gsub(playerName, "-.*$", "")
    clean = string.gsub(clean, "^%s*(.-)%s*$", "%1")

    local numScores = (GetNumBattlefieldScores and GetNumBattlefieldScores()) or 0
    for i = 1, numScores do
        local name, _, _, _, _, _, _, _, locClass, token = GetBattlefieldScore(i)
        if name and string.gsub(name, "-.*$", "") == clean then
            return token or locClass
        end
    end

    local numRaid = (GetNumRaidMembers and GetNumRaidMembers()) or 0
    if numRaid > 0 then
        for i = 1, numRaid do
            if UnitName(RAID_UNITS[i]) == clean then
                local _, token = UnitClass(RAID_UNITS[i]); return token
            end
        end
    else
        local numParty = (GetNumPartyMembers and GetNumPartyMembers()) or 0
        for i = 1, numParty do
            if UnitName(PARTY_UNITS[i]) == clean then
                local _, token = UnitClass(PARTY_UNITS[i]); return token
            end
        end
    end

    if UnitName("player") == clean then
        local _, token = UnitClass("player"); return token
    end
    return nil
end

local notifiedQueues = {}
local hasHandledEnd = false
local lastPlayedBG = nil
local pendingAutoRejoin = nil
local needsQueueAfterResurrect = false

local function IsPlayerDeadOrGhost()
    return (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")) or (UnitIsDead and UnitIsDead("player")) or (UnitIsGhost and UnitIsGhost("player"))
end

local function DismissBattlefieldPopups()
    if StaticPopup_Hide then StaticPopup_Hide("CONFIRM_BATTLEFIELD_ENTRY") end
    for s = 1, 4 do
        local dlg = _G["StaticPopup" .. s]
        if dlg and dlg:IsShown() and dlg.which == "CONFIRM_BATTLEFIELD_ENTRY" then
            dlg:Hide()
        end
    end
end

function AutoBG_PlayNotificationSound()
    PlaySound("ReadyCheck")
    AutoBG_TimerAfter(0.8, function() PlaySound("ReadyCheck") end)
    AutoBG_TimerAfter(1.6, function() PlaySound("ReadyCheck") end)
end

local function GetBGButtonIndex(bgName)
    if not bgName then return 4, "Warsong Gulch" end
    local lower = string.lower(bgName)
    if string.find(lower, "arathi") or string.find(lower, "ab") then return 5, "Arathi Basin"
    elseif string.find(lower, "alterac") or string.find(lower, "av") then return 7, "Alterac Valley"
    elseif string.find(lower, "thorn") or string.find(lower, "gorge") or string.find(lower, "tg") then return 6, "Thorn Gorge"
    elseif string.find(lower, "arena") then return 3, "Arena"
    else return 4, "Warsong Gulch" end
end

local function ClickFrame(f)
    if not f then return false end
    if f.Click then f:Click(); return true end
    if f.IsObjectType and (f:IsObjectType("Button") or f:IsObjectType("CheckButton")) then
        local onClick = f.GetScript and f:GetScript("OnClick")
        if onClick then onClick(); return true end
    end
    return false
end

function AutoBG_TriggerBattlegroundFinder(bgName)
    local btnIdx, cleanName = GetBGButtonIndex(bgName)
    pendingAutoRejoin = cleanName
    if CloseDropDownMenus then CloseDropDownMenus() end

    local mmBtn = _G["TWMiniMapBattlefieldFrame"] or _G["MiniMapBattlefieldFrame"]
    if mmBtn then ClickFrame(mmBtn) end

    AutoBG_TimerAfter(0.08, function()
        local targetFound = false
        local lowerTarget = string.lower(cleanName)
        for i = 1, 12 do
            local dropBtn = _G["DropDownList1Button" .. i]
            if dropBtn and dropBtn:IsShown() then
                local text = dropBtn:GetText() or (_G["DropDownList1Button" .. i .. "NormalText"] and _G["DropDownList1Button" .. i .. "NormalText"]:GetText())
                if text and string.find(string.lower(text), lowerTarget) then
                    ClickFrame(dropBtn)
                    targetFound = true
                    break
                end
            end
        end
        if not targetFound then
            local b = _G["DropDownList1Button" .. btnIdx]
            if b and b:IsShown() then ClickFrame(b) end
        end
    end)
end


-- Multi-BG Auto-Queue Engine (Zero-GC Pre-allocated Buffers)
local isAutoQueueing = false
local hasQueuedOnLogin = false
local BGS_TO_QUEUE = { "Warsong Gulch", "Arathi Basin", "Alterac Valley" }
local queueQueueBuffer = {}

function AutoBG_QueueAllBGs()
    if isAutoQueueing or currentZonePVP then return end
    if (AutoBG_Settings and AutoBG_Settings.SkipIfAFK ~= false) and AutoBG_IsPlayerAFK() then
        AutoBG_Print("Auto-Queue skipped: You are tagged as |cFFFF5555AFK|r.")
        return
    end
    if IsPlayerDeadOrGhost() then
        needsQueueAfterResurrect = true
        AutoBG_Print("Cannot queue for battlegrounds while dead. Will auto-queue once resurrected.")
        return
    end

    table.wipe(queueQueueBuffer)
    local maxQueues = MAX_BATTLEFIELD_QUEUES or 3
    local total = 0

    for i = 1, #BGS_TO_QUEUE do
        local bg = BGS_TO_QUEUE[i]
        local alreadyQueued = false
        for q = 1, maxQueues do
            local status, mapName = GetBattlefieldStatus(q)
            if status and status ~= "none" and mapName and string.find(string.lower(mapName), string.lower(bg)) then
                alreadyQueued = true; break
            end
        end
        if not alreadyQueued then
            total = total + 1
            queueQueueBuffer[total] = bg
        end
    end
    table.setn(queueQueueBuffer, total)

    if total == 0 then
        AutoBG_Print("Already queued for all 3 Battlegrounds (WSG, AB, AV).")
        return
    end

    isAutoQueueing = true
    local idx = 1

    local function StepQueue()
        if (AutoBG_Settings and AutoBG_Settings.SkipIfAFK ~= false) and AutoBG_IsPlayerAFK() then
            isAutoQueueing = false
            AutoBG_Print("Auto-Queue paused: You are tagged as |cFFFF5555AFK|r.")
            return
        end
        if IsPlayerDeadOrGhost() then
            isAutoQueueing = false; needsQueueAfterResurrect = true
            AutoBG_Print("Auto-Queue paused (player dead/ghost). Will resume upon resurrection.")
            return
        end
        if idx > total then
            isAutoQueueing = false; AutoBG_Print("Auto-Queue complete: Queued for WSG, AB, and AV!")
            return
        end
        local currentBG = queueQueueBuffer[idx]
        idx = idx + 1
        AutoBG_Print("Auto-queuing for |cFFFFFF00" .. currentBG .. "|r (" .. (idx - 1) .. "/" .. total .. ")...")
        AutoBG_TriggerBattlegroundFinder(currentBG)
        AutoBG_TimerAfter(2.2, StepQueue)
    end
    StepQueue()
end

-- Macro Target Button
local quickQueueBtn = CreateFrame("Button", "AutoBG_QuickQueueButton", UIParent)
quickQueueBtn:SetScript("OnClick", function()
    local bg = (AutoBG_Settings and AutoBG_Settings.LastPlayedBG) or lastPlayedBG or "Warsong Gulch"
    AutoBG_Print("Quick-queue triggered for |cFFFFFF00" .. bg .. "|r...")
    AutoBG_TriggerBattlegroundFinder(bg)
end)

local function HandleMatchEnd()
    if hasHandledEnd then return end
    hasHandledEnd = true

    UpdateZoneCache()
    if currentZoneText ~= "" then
        lastPlayedBG = currentZoneText
        if AutoBG_Settings then AutoBG_Settings.LastPlayedBG = currentZoneText end
    end
    if AutoBG_Settings and AutoBG_Settings.AutoRejoin and lastPlayedBG then
        local _, cleanName = GetBGButtonIndex(lastPlayedBG)
        pendingAutoRejoin = cleanName
    end

    if AutoBG_Settings and AutoBG_Settings.FlashTaskbar and FlashClientIcon then
        FlashClientIcon()
    end

    if AutoBG_Settings and AutoBG_Settings.AutoLeave then
        LeaveBattlefield(0)
        AutoBG_Print("Instantly left |cFFFFFF00" .. (lastPlayedBG or "battleground") .. "|r.")
    end
end

-- Auto-Accept Popup Dismissal Hook (Rule B10)
hooksecurefunc("StaticPopup_Show", function(which, text_arg1, text_arg2, data)
    if which == "CONFIRM_BATTLEFIELD_ENTRY" and AutoBG_Settings and AutoBG_Settings.AutoAccept then
        if (AutoBG_Settings.SkipIfAFK ~= false) and AutoBG_IsPlayerAFK() then
            AutoBG_Print("Auto-Accept skipped: You are tagged as |cFFFF5555AFK|r.")
            return
        end
        local delay = AutoBG_Settings.AutoAcceptDelay or 0
        if delay <= 0 then
            AcceptBattlefieldPort(data or 1, 1)
            DismissBattlefieldPopups()
            AutoBG_Print("Instant Auto-Accepted |cFFFFFF00" .. (text_arg1 or "Battleground") .. "|r!")
        end
    end
end)


local frame = CreateFrame("Frame", "AutoBGFrame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("UPDATE_BATTLEFIELD_STATUS")
frame:RegisterEvent("BATTLEFIELDS_SHOW")
frame:RegisterEvent("PLAYER_FLAGS_CHANGED")
frame:RegisterEvent("PLAYER_DEAD")
frame:RegisterEvent("PLAYER_ALIVE")
frame:RegisterEvent("PLAYER_UNGHOST")
frame:RegisterEvent("UI_ERROR_MESSAGE")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("ZONE_CHANGED")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:RegisterEvent("CHAT_MSG_BG_SYSTEM_NEUTRAL")
frame:RegisterEvent("CHAT_MSG_BG_SYSTEM_ALLIANCE")
frame:RegisterEvent("CHAT_MSG_BG_SYSTEM_HORDE")
frame:RegisterEvent("CHAT_MSG_SYSTEM")

local function ProcessBattlefieldQueue(id)
    local status, mapName = GetBattlefieldStatus(id)
    if status == "confirm" then
        if not notifiedQueues[id] then
            notifiedQueues[id] = true
            if AutoBG_Settings.AutoAccept then
                if (AutoBG_Settings.SkipIfAFK ~= false) and AutoBG_IsPlayerAFK() then
                    AutoBG_Print("Queue popped for |cFFFFFF00" .. (mapName or "Battleground") .. "|r, but Auto-Enter is paused because you are |cFFFF5555AFK|r!")
                    if AutoBG_Settings.NotifySound then AutoBG_PlayNotificationSound() end
                    if AutoBG_Settings.FlashTaskbar and FlashClientIcon then FlashClientIcon() end
                    return
                end
                local delay = AutoBG_Settings.AutoAcceptDelay or 0
                local qId, bg = id, mapName or "Battleground"
                if delay <= 0 then
                    AcceptBattlefieldPort(qId, 1)
                    DismissBattlefieldPopups()
                    AutoBG_Print("Instant Auto-Accepted |cFFFFFF00" .. bg .. "|r!")
                else
                    AutoBG_Print("Queue popped for |cFFFFFF00" .. bg .. "|r! Entering in |cFFFFFF00" .. delay .. "s|r...")
                    AutoBG_TimerAfter(delay, function()
                        if (AutoBG_Settings.SkipIfAFK ~= false) and AutoBG_IsPlayerAFK() then
                            AutoBG_Print("Auto-Enter cancelled: Player became |cFFFF5555AFK|r!")
                            return
                        end
                        if GetBattlefieldStatus(qId) == "confirm" then
                            AcceptBattlefieldPort(qId, 1)
                            DismissBattlefieldPopups()
                            AutoBG_Print("Auto-Entered |cFFFFFF00" .. bg .. "|r after |cFFFFFF00" .. delay .. "s|r delay!")
                        end
                    end)
                end
            end
            if AutoBG_Settings.NotifySound then AutoBG_PlayNotificationSound() end
            if AutoBG_Settings.FlashTaskbar and FlashClientIcon then FlashClientIcon() end
            if not AutoBG_Settings.AutoAccept then
                AutoBG_Print("Queue is ready for |cFFFFFF00" .. (mapName or "Battleground") .. "|r! (Queue #" .. id .. ")")
            end
        end
    elseif status == "active" or status == "none" then
        notifiedQueues[id] = false
        if status == "active" then
            if mapName and mapName ~= "" then lastPlayedBG = mapName end
            if GetBattlefieldWinner() then HandleMatchEnd() end
        end
    end
end

frame:SetScript("OnEvent", function()
    local ev, a1 = event, arg1

    if ev == "ADDON_LOADED" and a1 == addonName then
        if not AutoBG_Settings then AutoBG_Settings = defaultSettings
        else
            for k, v in pairs(defaultSettings) do
                if AutoBG_Settings[k] == nil then AutoBG_Settings[k] = v end
            end
        end
        UpdateZoneCache()
        AutoBG_Print("Loaded natively for ClassicAPI, SuperWoW 2.2+, NamPower, UnitXP SP3, DXVK. Type |cFFFFFF00/abg|r for options.", true)
        if AutoBG_Settings.HideCastbar and CastingBarFrame then CastingBarFrame:UnregisterAllEvents(); CastingBarFrame:Hide() end
        if AutoBG_Settings.HideStanceBar then AutoBG_UpdateStanceBar() end

    elseif ev == "PLAYER_FLAGS_CHANGED" then
        if not a1 or a1 == "player" then
            if UnitIsAFK and UnitIsAFK("player") then
                playerIsAFK = true
            else
                playerIsAFK = false
            end
        end

    elseif ev == "PLAYER_ENTERING_WORLD" or ev == "ZONE_CHANGED" or ev == "ZONE_CHANGED_NEW_AREA" then
        UpdateZoneCache()
        if UnitIsAFK and UnitIsAFK("player") then playerIsAFK = true else playerIsAFK = false end
        if AutoBG_Settings and AutoBG_Settings.HideStanceBar then AutoBG_UpdateStanceBar() end

        if currentZonePVP then
            if currentZoneText ~= "" then
                lastPlayedBG = currentZoneText
                if AutoBG_Settings then AutoBG_Settings.LastPlayedBG = currentZoneText end
            end
            hasHandledEnd = false
            pendingAutoRejoin = nil
        else
            local targetRejoin = lastPlayedBG or (AutoBG_Settings and AutoBG_Settings.LastPlayedBG)
            if hasHandledEnd and targetRejoin and AutoBG_Settings and AutoBG_Settings.AutoRejoin then
                if (AutoBG_Settings.SkipIfAFK ~= false) and AutoBG_IsPlayerAFK() then
                    AutoBG_Print("Auto-Rejoin paused: You are tagged as |cFFFF5555AFK|r.")
                    hasHandledEnd = false
                else
                    AutoBG_TimerAfter(0.05, function() if pendingAutoRejoin then AutoBG_TriggerBattlegroundFinder(targetRejoin) end end)
                end
            else
                hasHandledEnd = false
            end

            if AutoBG_Settings and AutoBG_Settings.AutoQueueLogin and not hasQueuedOnLogin then
                if (AutoBG_Settings.SkipIfAFK ~= false) and AutoBG_IsPlayerAFK() then
                    AutoBG_Print("Auto-Queue on login skipped: You are tagged as |cFFFF5555AFK|r.")
                elseif IsPlayerDeadOrGhost() then
                    needsQueueAfterResurrect = true
                else
                    hasQueuedOnLogin = true
                    AutoBG_TimerAfter(3.0, function()
                        if (AutoBG_Settings.SkipIfAFK ~= false) and AutoBG_IsPlayerAFK() then
                            AutoBG_Print("Auto-Queue on login skipped: You are tagged as |cFFFF5555AFK|r.")
                            return
                        end
                        if not IsPlayerDeadOrGhost() then AutoBG_QueueAllBGs()
                        else needsQueueAfterResurrect = true; hasQueuedOnLogin = false end
                    end)
                end
            end
        end

    elseif ev == "BATTLEFIELDS_SHOW" then
        if pendingAutoRejoin or (hasHandledEnd and lastPlayedBG and AutoBG_Settings and AutoBG_Settings.AutoRejoin) or isAutoQueueing then
            if (AutoBG_Settings.SkipIfAFK ~= false) and AutoBG_IsPlayerAFK() then
                AutoBG_Print("Auto-Queue / Auto-Rejoin skipped: You are tagged as |cFFFF5555AFK|r.")
                pendingAutoRejoin = nil
                hasHandledEnd = false
                isAutoQueueing = false
                return
            end
            local bgTitle = pendingAutoRejoin or (GetBattlefieldInfo and GetBattlefieldInfo()) or "Battleground"
            if SetSelectedBattlefield then pcall(SetSelectedBattlefield, 0) end
            pcall(JoinBattlefield, 0)
            if BattlefieldFrame then HideUIPanel(BattlefieldFrame); BattlefieldFrame:Hide() end
            if CloseBattlefield then pcall(CloseBattlefield) end
            if CloseDropDownMenus then pcall(CloseDropDownMenus) end

            AutoBG_TimerAfter(0.04, function()
                if BattlefieldFrame and BattlefieldFrame:IsShown() then HideUIPanel(BattlefieldFrame); BattlefieldFrame:Hide() end
                if CloseDropDownMenus then pcall(CloseDropDownMenus) end
            end)
            AutoBG_Print("Successfully queued for |cFFFFFF00" .. bgTitle .. "|r (First Available)!")
            pendingAutoRejoin = nil; hasHandledEnd = false
        end

    elseif ev == "CHAT_MSG_BG_SYSTEM_NEUTRAL" or ev == "CHAT_MSG_BG_SYSTEM_ALLIANCE" or ev == "CHAT_MSG_BG_SYSTEM_HORDE" or ev == "CHAT_MSG_SYSTEM" then
        if ev == "CHAT_MSG_SYSTEM" and a1 then
            if (MARKED_AFK_MESSAGE and a1 == MARKED_AFK_MESSAGE) or string.find(a1, "You are now AFK") then
                playerIsAFK = true
            elseif (CLEARED_AFK and a1 == CLEARED_AFK) or string.find(a1, "You are no longer AFK") then
                playerIsAFK = false
            end
        end
        if a1 and (string.find(a1, "wins!") or string.find(a1, "won the battle") or string.find(a1, "wins the battle") or string.find(a1, "victorious!")) then
            if currentZonePVP then HandleMatchEnd() end
        end

    elseif ev == "UPDATE_BATTLEFIELD_STATUS" then
        if not AutoBG_Settings then return end
        local maxQueues = MAX_BATTLEFIELD_QUEUES or 3
        for i = 1, maxQueues do ProcessBattlefieldQueue(i) end

    elseif ev == "PLAYER_DEAD" then
        if AutoBG_Settings and AutoBG_Settings.AutoRelease and currentZonePVP then
            local hasSS = (HasSoulstone and HasSoulstone()) or (CanUseSoulstone and CanUseSoulstone())
            if not hasSS then
                RepopMe()
                if StaticPopup_Hide then StaticPopup_Hide("DEATH") end
            else
                AutoBG_Print("Self-resurrection available. Preserving spirit.")
            end
        end

    elseif ev == "PLAYER_ALIVE" or ev == "PLAYER_UNGHOST" then
        if needsQueueAfterResurrect and not IsPlayerDeadOrGhost() then
            needsQueueAfterResurrect = false; hasQueuedOnLogin = true
            AutoBG_TimerAfter(2.0, function()
                if not IsPlayerDeadOrGhost() then
                    AutoBG_Print("Resurrection detected! Initiating Battleground Auto-Queue...")
                    AutoBG_QueueAllBGs()
                end
            end)
        end

    elseif ev == "UI_ERROR_MESSAGE" then
        if a1 and (string.find(string.lower(a1), "cannot queue") or string.find(string.lower(a1), "while dead")) then
            if isAutoQueueing then
                isAutoQueueing = false; needsQueueAfterResurrect = true
                AutoBG_Print("Auto-Queue paused (cannot queue while dead). Will auto-queue once resurrected.")
            end
        end
    end
end)

-- Scoreboard Hook (Rule B10)
hooksecurefunc("WorldStateScoreFrame_Update", function()
    if not AutoBG_Settings or not AutoBG_Settings.ScoreColor then return end

    local offset = (WorldStateScoreScrollFrame and FauxScrollFrame_GetOffset(WorldStateScoreScrollFrame)) or 0
    local maxButtons = MAX_WORLDSTATE_SCORE_BUTTONS or 20
    for i = 1, maxButtons do
        local name, _, _, _, _, faction, _, _, class, classToken = GetBattlefieldScore(offset + i)
        if name and name ~= "" then
            local nameText = _G["WorldStateScoreButton" .. i .. "NameText"] or _G["WorldStateScoreButton" .. i .. "Name"]
            if nameText then
                local clean = string.gsub(string.gsub(name, "-.*$", ""), "^%s*(.-)%s*$", "%1")
                local color = AutoBG_GetClassColor(classToken or class)
                if color then
                    nameText:SetText(color .. clean .. "|r")
                else
                    nameText:SetText(clean)
                    if faction == 0 then nameText:SetTextColor(1.0, 0.1, 0.1) else nameText:SetTextColor(0.0, 0.68, 1.0) end
                end
            end
        end
    end
end)


-- Data-Driven Slash Command Dispatcher (Replaces 150 lines of repetitive if/elseif chains)
local toggleCommands = {
    s = { key = "NotifySound", label = "Loud Sound Notification" },
    sound = { key = "NotifySound", label = "Loud Sound Notification" },
    f = { key = "FlashTaskbar", label = "Taskbar Flashing" },
    flash = { key = "FlashTaskbar", label = "Taskbar Flashing" },
    msg = { key = "ChatMessages", label = "Chat Notifications" },
    chat = { key = "ChatMessages", label = "Chat Notifications" },
    a = { key = "AutoAccept", label = "Auto-Accept Queue Pop" },
    accept = { key = "AutoAccept", label = "Auto-Accept Queue Pop" },
    j = { key = "AutoRejoin", label = "Auto-Rejoin BG on Exit" },
    autorejoin = { key = "AutoRejoin", label = "Auto-Rejoin BG on Exit" },
    l = { key = "AutoLeave", label = "Auto-Leave BG on End" },
    leave = { key = "AutoLeave", label = "Auto-Leave BG on End" },
    c = { key = "ScoreColor", label = "Scoreboard Class Colors" },
    color = { key = "ScoreColor", label = "Scoreboard Class Colors" },
    r = { key = "AutoRelease", label = "Auto-Release Spirit" },
    release = { key = "AutoRelease", label = "Auto-Release Spirit" },
    t = { key = "TestAllTimers", label = "Test Mode (All Timers)" },
    test = { key = "TestAllTimers", label = "Test Mode (All Timers)" },
    autoqueue = { key = "AutoQueueLogin", label = "Auto-Queue on Login" },
}

SLASH_AUTOBG1 = "/abg"
SLASH_AUTOBG2 = "/autobg"
SlashCmdList["AUTOBG"] = function(msg)
    local raw = (msg and string.gsub(msg, "^%s*(.-)%s*$", "%1")) or ""
    local space = string.find(raw, " ")
    local cmd = string.lower(space and string.sub(raw, 1, space - 1) or raw)
    local arg = string.lower(space and string.gsub(string.sub(raw, space + 1), "^%s*(.-)%s*$", "%1") or "")

    if toggleCommands[cmd] then
        local entry = toggleCommands[cmd]
        AutoBG_Settings[entry.key] = not AutoBG_Settings[entry.key]
        AutoBG_Print(entry.label .. " is now " .. (AutoBG_Settings[entry.key] and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r"), true)
        if AutoBG_Options_Refresh then AutoBG_Options_Refresh() end
        return
    end

    if cmd == "stealth" or cmd == "stance" then
        AutoBG_Settings.HideStanceBar = not AutoBG_Settings.HideStanceBar
        AutoBG_Print("Hide Stealth/Stance Bar is now " .. (AutoBG_Settings.HideStanceBar and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r"), true)
        if AutoBG_UpdateStanceBar then AutoBG_UpdateStanceBar() end
        if AutoBG_Options_Refresh then AutoBG_Options_Refresh() end
    elseif cmd == "q" or cmd == "queue" or cmd == "join" or cmd == "rejoin" then
        if arg == "all" or arg == "3" or arg == "bg" or arg == "bgs" then AutoBG_QueueAllBGs(); return end
        local target = (string.find(arg, "wsg") and "Warsong Gulch") or (string.find(arg, "ab") and "Arathi Basin") or (string.find(arg, "av") and "Alterac Valley") or (string.find(arg, "tg") and "Thorn Gorge") or (AutoBG_Settings and AutoBG_Settings.LastPlayedBG) or lastPlayedBG
        if target then
            if AutoBG_Settings then AutoBG_Settings.LastPlayedBG = target end
            AutoBG_Print("Quick-queue triggered for |cFFFFFF00" .. target .. "|r...", true)
            AutoBG_TriggerBattlegroundFinder(target)
        else
            AutoBG_Print("No previous BG recorded. Opening Battleground Finder...", true)
            local mmBtn = _G["TWMiniMapBattlefieldFrame"] or _G["MiniMapBattlefieldFrame"]
            if mmBtn then ClickFrame(mmBtn) end

        end
    elseif cmd == "delay" or cmd == "acceptdelay" then
        local val = tonumber(arg)
        if val then
            AutoBG_Settings.AutoAcceptDelay = math.max(0, math.min(120, math.floor(val)))
            AutoBG_Print("Auto-Accept Enter Delay set to |cFFFFFF00" .. (AutoBG_Settings.AutoAcceptDelay == 0 and "Instant (0s)" or (AutoBG_Settings.AutoAcceptDelay .. "s")) .. "|r", true)
            if AutoBG_Options_Refresh then AutoBG_Options_Refresh() end
        else
            AutoBG_Print("Current Auto-Accept Enter Delay: |cFFFFFF00" .. ((AutoBG_Settings.AutoAcceptDelay or 0) == 0 and "Instant (0s)" or (AutoBG_Settings.AutoAcceptDelay .. "s")) .. "|r", true)
        end
    elseif cmd == "reset" then
        AutoBG_Settings = nil; AutoBG_Print("Settings reset to default. Reloading UI...", true); ReloadUI()
    elseif cmd == "help" then
        AutoBG_Print("|cFF00FF00AutoBG Commands:|r /abg, /abg q [ab|wsg|av|tg|all], /abg a, /abg delay <sec>, /abg l, /abg j, /abg r, /abg c, /abg stealth, /abg test, /abg reset", true)
    else
        if AutoBG_OptionsPanel then
            if AutoBG_OptionsPanel:IsShown() then AutoBG_OptionsPanel:Hide() else AutoBG_OptionsPanel:Show() end
        end
    end
end
