-- AutoBG Timers for WoW 1.12.1 (Vanilla / OctoWOW)
local timers = {
    AB = {},
    AV = {},
    WSG = {},
    Global = {}
}

local spiritHealerSyncTime = 0
local spiritHealerSynced = false

local function CreateDraggableTimerFrame(name, titleText, xOffset, yOffset, minWidth)
    local frame = CreateFrame("Frame", name, UIParent)
    frame:SetWidth(minWidth or 100)
    frame:SetHeight(30)
    frame:SetPoint("TOP", UIParent, "TOP", xOffset, yOffset)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    frame:SetBackdropColor(0, 0, 0, 0.7)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() this:StartMoving() end)
    frame:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        if AutoBG_SavePosition then
            AutoBG_SavePosition(this, name)
        end
    end)
    frame:Hide()

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -8)
    title:SetText(titleText)

    frame.title = title
    frame.activeStrings = {}

    function frame:GetOrCreateFontString(index)
        if not self.activeStrings[index] then
            local fs = self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            if index == 1 then
                fs:SetPoint("TOP", self, "TOP", 0, -28)
            else
                fs:SetPoint("TOP", self.activeStrings[index-1], "BOTTOM", 0, -5)
            end
            self.activeStrings[index] = fs
        end
        return self.activeStrings[index]
    end

    function frame:UpdateSize(index)
        local maxWidth = self.title:GetStringWidth() + 30
        local count = table.getn(self.activeStrings)
        for i = index, count do
            self.activeStrings[i]:Hide()
        end

        for i = 1, index - 1 do
            local w = self.activeStrings[i]:GetStringWidth() + 30
            if w > maxWidth then maxWidth = w end
        end

        if index > 1 then
            self:SetWidth(math.max(minWidth or 100, maxWidth))
            self:SetHeight(32 + (index - 1) * 15)
            self:Show()
        else
            self:Hide()
        end
    end

    return frame
end

local QueueFrame = CreateDraggableTimerFrame("AutoBG_QueueFrame", "BG Queues", -220, -100, 130)
local RespawnFrame = CreateDraggableTimerFrame("AutoBG_RespawnFrame", "Respawn", 0, -100, 80)
local NodeFrame = CreateDraggableTimerFrame("AutoBG_NodeFrame", "AB Nodes", 220, -100, 160)
local AVNodeFrame = CreateDraggableTimerFrame("AutoBG_AVNodeFrame", "AV Nodes", 220, -150, 160)
local WSGFlagFrame = CreateDraggableTimerFrame("AutoBG_WSGFlagFrame", "WSG Timers", -110, -150, 140)

function AutoBG_LoadTimerPositions()
    if AutoBG_LoadPosition then
        AutoBG_LoadPosition(QueueFrame, "AutoBG_QueueFrame", "TOP", -220, -100)
        AutoBG_LoadPosition(RespawnFrame, "AutoBG_RespawnFrame", "TOP", 0, -100)
        AutoBG_LoadPosition(NodeFrame, "AutoBG_NodeFrame", "TOP", 220, -100)
        AutoBG_LoadPosition(AVNodeFrame, "AutoBG_AVNodeFrame", "TOP", 220, -150)
        AutoBG_LoadPosition(WSGFlagFrame, "AutoBG_WSGFlagFrame", "TOP", -110, -150)
    end
end

function AutoBG_ResetTimerPositions()
    QueueFrame:ClearAllPoints(); QueueFrame:SetPoint("TOP", UIParent, "TOP", -220, -100)
    RespawnFrame:ClearAllPoints(); RespawnFrame:SetPoint("TOP", UIParent, "TOP", 0, -100)
    NodeFrame:ClearAllPoints(); NodeFrame:SetPoint("TOP", UIParent, "TOP", 220, -100)
    AVNodeFrame:ClearAllPoints(); AVNodeFrame:SetPoint("TOP", UIParent, "TOP", 220, -150)
    WSGFlagFrame:ClearAllPoints(); WSGFlagFrame:SetPoint("TOP", UIParent, "TOP", -110, -150)
end

local function FormatTime(seconds)
    local m = math.floor(seconds / 60)
    local s = math.floor(math.mod(seconds, 60))
    return string.format("%d:%02d", m, s)
end

local function FormatQueueTime(seconds)
    local h = math.floor(seconds / 3600)
    local m = math.floor(math.mod(seconds, 3600) / 60)
    local s = math.floor(math.mod(seconds, 60))

    if h > 0 then
        local hrStr = (h == 1) and "Hr" or "Hrs"
        local minStr = (m == 1) and "Min" or "Mins"
        return string.format("%d %s %d %s", h, hrStr, m, minStr)
    elseif m > 0 then
        local minStr = (m == 1) and "Min" or "Mins"
        local secStr = (s == 1) and "Sec" or "Secs"
        return string.format("%d %s %d %s", m, minStr, s, secStr)
    else
        local secStr = (s == 1) and "Sec" or "Secs"
        return string.format("%d %s", s, secStr)
    end
end

local updateThrottle = 0
local ControllerFrame = CreateFrame("Frame", "AutoBG_TimerController")
ControllerFrame:SetScript("OnUpdate", function()
    if not AutoBG_Settings then return end

    updateThrottle = updateThrottle + (arg1 or 0.05)
    if updateThrottle < 0.1 then return end
    updateThrottle = 0

    local now = GetTime()
    local currentZone = (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()) or ""
    local isTestAll = AutoBG_Settings.TestAllTimers
    local useColors = AutoBG_Settings.NodeColors

    -- 1. AB Node Timers
    local nodeIndex = 1
    if AutoBG_Settings.ABTimers then
        if isTestAll then
            local fs = NodeFrame:GetOrCreateFontString(1)
            fs:SetText("|cFFFF4040Blacksmith: 0:59|r")
            fs:Show()
            local fs2 = NodeFrame:GetOrCreateFontString(2)
            fs2:SetText("|cFF4090FFLumber Mill: 0:42|r")
            fs2:Show()
            nodeIndex = 3
        else
            for name, data in pairs(timers.AB) do
                local expireTime = (type(data) == "table" and data.expire) or data
                local faction = (type(data) == "table" and data.faction) or nil
                local remaining = math.floor(expireTime - now)

                if remaining > 0 then
                    local fs = NodeFrame:GetOrCreateFontString(nodeIndex)
                    local colorPrefix = ""
                    if useColors and faction == "Horde" then
                        colorPrefix = "|cFFFF4040"
                    elseif useColors and faction == "Alliance" then
                        colorPrefix = "|cFF4090FF"
                    end

                    if colorPrefix ~= "" then
                        fs:SetText(colorPrefix .. name .. ": " .. FormatTime(remaining) .. "|r")
                    else
                        fs:SetText(name .. ": " .. FormatTime(remaining))
                    end
                    fs:Show()
                    nodeIndex = nodeIndex + 1
                else
                    timers.AB[name] = nil
                end
            end
            if timers.Global["Match Starts"] and currentZone == "Arathi Basin" then
                local remaining = math.floor(timers.Global["Match Starts"] - now)
                if remaining > 0 then
                    local fs = NodeFrame:GetOrCreateFontString(nodeIndex)
                    fs:SetText("|cFFFFFF00Match Starts: " .. FormatTime(remaining) .. "|r")
                    fs:Show()
                    nodeIndex = nodeIndex + 1
                else
                    timers.Global["Match Starts"] = nil
                end
            end
        end
    end
    NodeFrame:UpdateSize(nodeIndex)

    -- 2. AV Node Timers
    local avIndex = 1
    if AutoBG_Settings.AVTimers then
        if isTestAll then
            local fs = AVNodeFrame:GetOrCreateFontString(1)
            fs:SetText("|cFFFF4040Stonehearth Bunker: 4:59|r")
            fs:Show()
            local fs2 = AVNodeFrame:GetOrCreateFontString(2)
            fs2:SetText("|cFF4090FFIceblood Tower: 3:30|r")
            fs2:Show()
            avIndex = 3
        else
            for name, data in pairs(timers.AV) do
                local expireTime = (type(data) == "table" and data.expire) or data
                local faction = (type(data) == "table" and data.faction) or nil
                local remaining = math.floor(expireTime - now)

                if remaining > 0 then
                    local fs = AVNodeFrame:GetOrCreateFontString(avIndex)
                    local colorPrefix = ""
                    if useColors and faction == "Horde" then
                        colorPrefix = "|cFFFF4040"
                    elseif useColors and faction == "Alliance" then
                        colorPrefix = "|cFF4090FF"
                    end

                    if colorPrefix ~= "" then
                        fs:SetText(colorPrefix .. name .. ": " .. FormatTime(remaining) .. "|r")
                    else
                        fs:SetText(name .. ": " .. FormatTime(remaining))
                    end
                    fs:Show()
                    avIndex = avIndex + 1
                else
                    timers.AV[name] = nil
                end
            end
            if timers.Global["Match Starts"] and currentZone == "Alterac Valley" then
                local remaining = math.floor(timers.Global["Match Starts"] - now)
                if remaining > 0 then
                    local fs = AVNodeFrame:GetOrCreateFontString(avIndex)
                    fs:SetText("|cFFFFFF00Match Starts: " .. FormatTime(remaining) .. "|r")
                    fs:Show()
                    avIndex = avIndex + 1
                else
                    timers.Global["Match Starts"] = nil
                end
            end
        end
    end
    AVNodeFrame:UpdateSize(avIndex)

    -- 3. WSG Timers (Flags & Buffs)
    local wsgIndex = 1
    if AutoBG_Settings.WSGTimers then
        if isTestAll then
            local fs = WSGFlagFrame:GetOrCreateFontString(1)
            fs:SetText("|cFF4090FFAlliance Flag: 0:23|r")
            fs:Show()
            local fs2 = WSGFlagFrame:GetOrCreateFontString(2)
            fs2:SetText("|cFFFFD100Speed Buff: 3:00|r")
            fs2:Show()
            wsgIndex = 3
        else
            for name, expireTime in pairs(timers.WSG) do
                local remaining = math.floor(expireTime - now)
                if remaining > 0 then
                    local fs = WSGFlagFrame:GetOrCreateFontString(wsgIndex)
                    local color = "|cFFFFFFFF"
                    if string.find(name, "Alliance") then color = "|cFF4090FF"
                    elseif string.find(name, "Horde") then color = "|cFFFF4040"
                    elseif string.find(name, "Speed") then color = "|cFFFFD100"
                    elseif string.find(name, "Resto") then color = "|cFF00FF00"
                    elseif string.find(name, "Berserk") then color = "|cFFFF0000" end

                    fs:SetText(color .. name .. ": " .. FormatTime(remaining) .. "|r")
                    fs:Show()
                    wsgIndex = wsgIndex + 1
                else
                    timers.WSG[name] = nil
                end
            end
            if timers.Global["Match Starts"] and currentZone == "Warsong Gulch" then
                local remaining = math.floor(timers.Global["Match Starts"] - now)
                if remaining > 0 then
                    local fs = WSGFlagFrame:GetOrCreateFontString(wsgIndex)
                    fs:SetText("|cFFFFFF00Match Starts: " .. FormatTime(remaining) .. "|r")
                    fs:Show()
                    wsgIndex = wsgIndex + 1
                else
                    timers.Global["Match Starts"] = nil
                end
            end
        end
    end
    WSGFlagFrame:UpdateSize(wsgIndex)

    -- 4. Respawn Timer (Spirit Healer 30s Multi-Source Synchronized Wave)
    local respawnIndex = 1
    local isInstance, instanceType = IsInInstance()
    local inBG = (isInstance and instanceType == "pvp")
    local isDead = UnitIsDead("player") or UnitIsGhost("player")

    if inBG then
        local healerTime = (GetAreaSpiritHealerTime and GetAreaSpiritHealerTime()) or 0
        if healerTime and healerTime > 0 then
            spiritHealerSyncTime = now - (30 - healerTime)
            spiritHealerSynced = true
        end

        if spiritHealerSyncTime == 0 then
            local instanceTime = (GetBattlefieldInstanceRunTime and GetBattlefieldInstanceRunTime()) or 0
            if instanceTime > 0 then
                spiritHealerSyncTime = now - math.mod(instanceTime / 1000, 30)
            else
                spiritHealerSyncTime = now
            end
            spiritHealerSynced = false
        end
    else
        spiritHealerSyncTime = 0
        spiritHealerSynced = false
    end

    if AutoBG_Settings.RessTimer then
        if isTestAll then
            local fs = RespawnFrame:GetOrCreateFontString(1)
            fs:SetText("|cFF00FF000:30|r")
            fs:Show()
            respawnIndex = 2
        elseif inBG and spiritHealerSyncTime > 0 then
            local elapsedSinceSync = now - spiritHealerSyncTime
            local remaining = 30 - math.mod(elapsedSinceSync, 30)
            local fs = RespawnFrame:GetOrCreateFontString(1)
            local numRemaining = math.ceil(remaining)
            if numRemaining <= 0 then numRemaining = 30 end

            local color = "|cFF00FF00"
            if isDead then
                color = "|cFF00FF00"
            elseif numRemaining <= 2 then
                color = "|cFFFF8000" -- Orange: Imminent wave!
            elseif numRemaining <= 5 then
                color = "|cFFFFFF00" -- Yellow: Wave approaching
            end

            local prefix = spiritHealerSynced and "" or "~"
            fs:SetText(color .. prefix .. FormatTime(numRemaining) .. "|r")
            fs:Show()
            respawnIndex = 2
        end
    end
    RespawnFrame:UpdateSize(respawnIndex)

    -- 5. Queue Timers
    local queueIndex = 1
    if AutoBG_Settings.QueueTimers then
        if isTestAll then
            local fs = QueueFrame:GetOrCreateFontString(1)
            fs:SetText("WSG: 1:15")
            fs:Show()
            local fs2 = QueueFrame:GetOrCreateFontString(2)
            fs2:SetText("AB: 4:32")
            fs2:Show()
            queueIndex = 3
        else
            local maxQueues = MAX_BATTLEFIELD_QUEUES or 3
            for i = 1, maxQueues do
                local status, mapName = GetBattlefieldStatus(i)
                if status == "queued" then
                    local waitTime = (GetBattlefieldTimeWaited and GetBattlefieldTimeWaited(i)) or 0
                    local elapsedSeconds = math.floor(waitTime / 1000)
                    local fs = QueueFrame:GetOrCreateFontString(queueIndex)

                    local abbrev = mapName or "BG"
                    if mapName == "Warsong Gulch" then abbrev = "WSG"
                    elseif mapName == "Arathi Basin" then abbrev = "AB"
                    elseif mapName == "Alterac Valley" then abbrev = "AV" end

                    fs:SetText(abbrev .. ": " .. FormatQueueTime(elapsedSeconds))
                    fs:Show()
                    queueIndex = queueIndex + 1
                end
            end
        end
    end
    QueueFrame:UpdateSize(queueIndex)
end)

function AutoBG_Timers_UpdateVisibility()
    -- Triggers update on next frame tick
end

-- Node list definitions
local abNodes = { "Blacksmith", "Lumber Mill", "Gold Mine", "Farm", "Stables" }
local avNodes = {
    "Iceblood Tower", "Tower Point", "East Frostwolf Tower", "West Frostwolf Tower",
    "Stonehearth Bunker", "Icewing Bunker", "Dun Baldar North Bunker", "Dun Baldar South Bunker",
    "Frostwolf Relief Hut", "Snowfall Graveyard", "Stormpike Graveyard", "Iceblood Graveyard",
    "Frostwolf Graveyard", "Stonehearth Graveyard", "Stormpike Aid Station"
}

local function FindNode(msg, nodeList)
    local lowerMsg = string.lower(msg)
    for i = 1, table.getn(nodeList) do
        local node = nodeList[i]
        if string.find(lowerMsg, string.lower(node)) then
            return node
        end
    end
    return nil
end

local function ParseCombatMessage(msg, ev)
    if not AutoBG_Settings or not msg then return end

    local lowerMsg = string.lower(msg)
    local assaultingFaction = nil
    if string.find(lowerMsg, "horde") then
        assaultingFaction = "Horde"
    elseif string.find(lowerMsg, "alliance") then
        assaultingFaction = "Alliance"
    end

    -- Node Assaults (AB: 60s, AV: 300s)
    if string.find(lowerMsg, "assaulted") or string.find(lowerMsg, "claims") or string.find(lowerMsg, "under attack") then
        local abNode = FindNode(msg, abNodes)
        if abNode and AutoBG_Settings.ABTimers then
            timers.AB[abNode] = { expire = GetTime() + 60, faction = assaultingFaction }
        end

        local avNode = FindNode(msg, avNodes)
        if avNode and AutoBG_Settings.AVTimers then
            timers.AV[avNode] = { expire = GetTime() + 300, faction = assaultingFaction }
        end
    end

    -- Node Defended / Taken / Destroyed
    if string.find(lowerMsg, "taken") or string.find(lowerMsg, "defended") or string.find(lowerMsg, "destroyed") or string.find(lowerMsg, "captured") then
        local abNode = FindNode(msg, abNodes)
        if abNode then
            timers.AB[abNode] = nil
        end

        local avNode = FindNode(msg, avNodes)
        if avNode then
            timers.AV[avNode] = nil
        end
    end

    -- BG Start Countdowns
    if (ev == "CHAT_MSG_BG_SYSTEM_NEUTRAL" or ev == "CHAT_MSG_SYSTEM") and
       (string.find(lowerMsg, "begins") or string.find(lowerMsg, "starts") or string.find(lowerMsg, "gates")) then
        if string.find(lowerMsg, "2 minute") then
            timers.Global["Match Starts"] = GetTime() + 120
        elseif string.find(lowerMsg, "1 minute") or string.find(lowerMsg, "one minute") then
            timers.Global["Match Starts"] = GetTime() + 60
        elseif string.find(lowerMsg, "30 second") or string.find(lowerMsg, "thirty second") then
            timers.Global["Match Starts"] = GetTime() + 30
        elseif string.find(lowerMsg, "15 second") or string.find(lowerMsg, "fifteen second") then
            timers.Global["Match Starts"] = GetTime() + 15
        end
    end

    -- WSG Flag Respawns (23s)
    if AutoBG_Settings.WSGTimers then
        if string.find(lowerMsg, "captured the alliance flag") or string.find(lowerMsg, "captured the horde flag") then
            if string.find(lowerMsg, "alliance flag") then
                timers.WSG["Alliance Flag"] = GetTime() + 23
            elseif string.find(lowerMsg, "horde flag") then
                timers.WSG["Horde Flag"] = GetTime() + 23
            end
        end

        -- WSG Speed / Restoration / Berserking Buffs
        if string.find(lowerMsg, "gains speed") then
            timers.WSG["Speed Buff"] = GetTime() + 180
        elseif string.find(lowerMsg, "gains restoration") then
            timers.WSG["Resto Buff"] = GetTime() + 120
        elseif string.find(lowerMsg, "gains berserking") then
            timers.WSG["Berserk Buff"] = GetTime() + 120
        end
    end

    -- Multi-Source Spirit Healer Wave Sync (Aura Gain & Combat Log)
    if string.find(lowerMsg, "spirit healing") or string.find(lowerMsg, "honorless target") or string.find(lowerMsg, "resurrection sickness") then
        if AutoBG_Settings.RessTimer then
            spiritHealerSyncTime = GetTime()
            spiritHealerSynced = true
        end
    end

    -- Sync Spirit Healer timer when BG begins
    if string.find(lowerMsg, "begun!") or string.find(lowerMsg, "has begun") or string.find(lowerMsg, "gates are open") or string.find(lowerMsg, "gates have opened") then
        if AutoBG_Settings.RessTimer then
            spiritHealerSyncTime = GetTime()
            spiritHealerSynced = true
        end
        timers.Global["Match Starts"] = nil
    end
end

local EventFrame = CreateFrame("Frame", "AutoBG_TimersEventFrame")
EventFrame:RegisterEvent("CHAT_MSG_BG_SYSTEM_NEUTRAL")
EventFrame:RegisterEvent("CHAT_MSG_BG_SYSTEM_ALLIANCE")
EventFrame:RegisterEvent("CHAT_MSG_BG_SYSTEM_HORDE")
EventFrame:RegisterEvent("CHAT_MSG_SYSTEM")
EventFrame:RegisterEvent("CHAT_MSG_MONSTER_YELL")
EventFrame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS")
EventFrame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_PARTY_BUFFS")
EventFrame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_BUFFS")
EventFrame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_BUFFS")
EventFrame:RegisterEvent("CHAT_MSG_SPELL_AURA_GONE_SELF")
EventFrame:RegisterEvent("CHAT_MSG_SPELL_AURA_GONE_PARTY")
EventFrame:RegisterEvent("CHAT_MSG_SPELL_AURA_GONE_OTHER")
EventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

EventFrame:SetScript("OnEvent", function()
    local ev = event
    local a1 = arg1

    if ev == "PLAYER_ENTERING_WORLD" then
        AutoBG_LoadTimerPositions()
        -- Reset stale timers when changing zone
        timers.AB = {}
        timers.AV = {}
        timers.WSG = {}
        timers.Global = {}

        local isInstance, instanceType = IsInInstance()
        if isInstance and instanceType == "pvp" then
            local runTime = (GetBattlefieldInstanceRunTime and GetBattlefieldInstanceRunTime()) or 0
            if runTime > 0 then
                spiritHealerSyncTime = GetTime() - math.mod(runTime / 1000, 30)
                spiritHealerSynced = false
            else
                spiritHealerSyncTime = GetTime()
                spiritHealerSynced = false
            end
        else
            spiritHealerSyncTime = 0
            spiritHealerSynced = false
        end
    else
        ParseCombatMessage(a1, ev)
    end
end)
