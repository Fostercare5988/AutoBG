-- AutoBG Timers for WoW 1.12.1 (Vanilla / OctoWOW)
local timers = {
    AB = {},
    AV = {},
    WSG = {},
    Global = {}
}

local spiritHealerSyncTime = 0
local spiritHealerSynced = false

local function SendTimerAnnouncement(text)
    if not text or text == "" then return end
    local inInstance, instanceType = IsInInstance()
    local chatType = (inInstance and instanceType == "pvp") and "BATTLEGROUND" or "RAID"
    if GetNumRaidMembers() == 0 and GetNumPartyMembers() > 0 then
        chatType = "PARTY"
    elseif GetNumRaidMembers() == 0 and GetNumPartyMembers() == 0 and not (inInstance and instanceType == "pvp") then
        chatType = "SAY"
    end
    SendChatMessage(text, chatType)
end

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
    frame.activeRows = {}

    function frame:GetOrCreateRow(index)
        if not self.activeRows[index] then
            local btn = CreateFrame("Button", self:GetName() .. "Row" .. index, self)
            btn:SetHeight(14)
            btn:SetWidth(self:GetWidth() - 16)
            if index == 1 then
                btn:SetPoint("TOP", self, "TOP", 0, -26)
            else
                btn:SetPoint("TOP", self.activeRows[index-1], "BOTTOM", 0, -2)
            end
            btn:EnableMouse(true)
            btn:RegisterForClicks("LeftButtonUp")
            btn:RegisterForDrag("LeftButton")
            btn:SetScript("OnDragStart", function() this:GetParent():StartMoving() end)
            btn:SetScript("OnDragStop", function()
                this:GetParent():StopMovingOrSizing()
                if AutoBG_SavePosition then
                    AutoBG_SavePosition(this:GetParent(), this:GetParent():GetName())
                end
            end)
            btn:SetScript("OnClick", function()
                if IsControlKeyDown() and this.announceText then
                    SendTimerAnnouncement(this.announceText)
                end
            end)
            btn:SetScript("OnEnter", function()
                if this.announceText and this.announceText ~= "" then
                    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
                    GameTooltip:SetText(this.announceText, 1, 1, 1)
                    GameTooltip:AddLine("|cFF00FF00CTRL+LeftClick:|r Announce to chat", 0.7, 0.7, 0.7)
                    GameTooltip:Show()
                end
            end)
            btn:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)

            local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("CENTER", btn, "CENTER", 0, 0)
            btn.fs = fs

            self.activeRows[index] = btn
        end
        return self.activeRows[index]
    end

    function frame:UpdateSize(index)
        local maxWidth = self.title:GetStringWidth() + 30
        local count = table.getn(self.activeRows)
        for i = index, count do
            self.activeRows[i]:Hide()
        end

        for i = 1, index - 1 do
            local w = self.activeRows[i].fs:GetStringWidth() + 30
            if w > maxWidth then maxWidth = w end
        end

        if index > 1 then
            self:SetWidth(math.max(minWidth or 100, maxWidth))
            self:SetHeight(30 + (index - 1) * 16)
            for i = 1, index - 1 do
                self.activeRows[i]:SetWidth(self:GetWidth() - 16)
            end
            self:Show()
        else
            self:Hide()
        end
    end

    return frame
end

local function CreateRespawnFrame(name, xOffset, yOffset)
    local frame = CreateFrame("Button", name, UIParent)
    frame:SetWidth(110)
    frame:SetHeight(38)
    frame:SetPoint("TOP", UIParent, "TOP", xOffset, yOffset)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    frame:SetBackdropColor(0, 0, 0, 0.8)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForClicks("LeftButtonUp")
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() this:StartMoving() end)
    frame:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        if AutoBG_SavePosition then
            AutoBG_SavePosition(this, name)
        end
    end)
    frame:SetScript("OnClick", function()
        if IsControlKeyDown() and this.announceText then
            SendTimerAnnouncement(this.announceText)
        end
    end)
    frame:SetScript("OnEnter", function()
        if this.announceText and this.announceText ~= "" then
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
            GameTooltip:SetText(this.announceText, 1, 1, 1)
            GameTooltip:AddLine("|cFF00FF00CTRL+LeftClick:|r Announce to chat", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end
    end)
    frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    frame:Hide()

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -6)
    title:SetText("Respawn")

    local timeText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    timeText:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -6)
    timeText:SetText("0:30")

    local bar = CreateFrame("StatusBar", name .. "Bar", frame)
    bar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 8, 7)
    bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 7)
    bar:SetHeight(8)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetMinMaxValues(0, 30)
    bar:SetValue(30)
    bar:SetStatusBarColor(0.1, 0.85, 0.1)

    local barBg = bar:CreateTexture(nil, "BACKGROUND")
    barBg:SetAllPoints(bar)
    barBg:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    barBg:SetVertexColor(0.2, 0.2, 0.2, 0.8)

    frame.title = title
    frame.timeText = timeText
    frame.bar = bar

    return frame
end

local QueueFrame = CreateDraggableTimerFrame("AutoBG_QueueFrame", "BG Queues", -220, -100, 130)
local RespawnFrame = CreateRespawnFrame("AutoBG_RespawnFrame", 0, -100)
local NodeFrame = CreateDraggableTimerFrame("AutoBG_NodeFrame", "AB Nodes", 220, -100, 160)
local AVNodeFrame = CreateDraggableTimerFrame("AutoBG_AVNodeFrame", "AV Nodes", 220, -150, 160)
local WSGFlagFrame = CreateDraggableTimerFrame("AutoBG_WSGFlagFrame", "WSG Flags", -110, -150, 140)

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
    local lowerZone = string.lower(currentZone)
    local isAB = (string.find(lowerZone, "arathi") ~= nil)
    local isAV = (string.find(lowerZone, "alterac") ~= nil)
    local isWSG = (string.find(lowerZone, "warsong") ~= nil)
    local isTestAll = AutoBG_Settings.TestAllTimers
    local useColors = AutoBG_Settings.NodeColors

    -- 1. AB Node Timers
    local nodeIndex = 1
    if AutoBG_Settings.ABTimers and (isTestAll or isAB) then
        if isTestAll then
            local row1 = NodeFrame:GetOrCreateRow(1)
            row1.fs:SetText("|cFFFF4040Blacksmith: 0:59|r")
            row1.announceText = "Blacksmith (Horde): 0:59"
            row1:Show()
            local row2 = NodeFrame:GetOrCreateRow(2)
            row2.fs:SetText("|cFF4090FFLumber Mill: 0:42|r")
            row2.announceText = "Lumber Mill (Alliance): 0:42"
            row2:Show()
            nodeIndex = 3
        else
            for name, data in pairs(timers.AB) do
                local expireTime = (type(data) == "table" and data.expire) or data
                local faction = (type(data) == "table" and data.faction) or nil
                local remaining = math.floor(expireTime - now)

                if remaining > 0 then
                    local row = NodeFrame:GetOrCreateRow(nodeIndex)
                    local colorPrefix = ""
                    if useColors and faction == "Horde" then
                        colorPrefix = "|cFFFF4040"
                    elseif useColors and faction == "Alliance" then
                        colorPrefix = "|cFF4090FF"
                    end

                    if colorPrefix ~= "" then
                        row.fs:SetText(colorPrefix .. name .. ": " .. FormatTime(remaining) .. "|r")
                    else
                        row.fs:SetText(name .. ": " .. FormatTime(remaining))
                    end
                    local facText = faction and (" (" .. faction .. ")") or ""
                    row.announceText = name .. facText .. ": " .. FormatTime(remaining)
                    row:Show()
                    nodeIndex = nodeIndex + 1
                else
                    timers.AB[name] = nil
                end
            end
            if timers.Global["Match Starts"] and isAB then
                local remaining = math.floor(timers.Global["Match Starts"] - now)
                if remaining > 0 then
                    local row = NodeFrame:GetOrCreateRow(nodeIndex)
                    row.fs:SetText("|cFFFFFF00Match Starts: " .. FormatTime(remaining) .. "|r")
                    row.announceText = "Gates: " .. FormatTime(remaining)
                    row:Show()
                    nodeIndex = nodeIndex + 1
                else
                    timers.Global["Match Starts"] = nil
                end
            end
        end
    else
        if not isTestAll then
            timers.AB = {}
        end
    end
    NodeFrame:UpdateSize(nodeIndex)

    -- 2. AV Node Timers
    local avIndex = 1
    if AutoBG_Settings.AVTimers and (isTestAll or isAV) then
        if isTestAll then
            local row1 = AVNodeFrame:GetOrCreateRow(1)
            row1.fs:SetText("|cFFFF4040Stonehearth Bunker: 4:59|r")
            row1.announceText = "Stonehearth Bunker (Horde): 4:59"
            row1:Show()
            local row2 = AVNodeFrame:GetOrCreateRow(2)
            row2.fs:SetText("|cFF4090FFIceblood Tower: 3:30|r")
            row2.announceText = "Iceblood Tower (Alliance): 3:30"
            row2:Show()
            avIndex = 3
        else
            for name, data in pairs(timers.AV) do
                local expireTime = (type(data) == "table" and data.expire) or data
                local faction = (type(data) == "table" and data.faction) or nil
                local remaining = math.floor(expireTime - now)

                if remaining > 0 then
                    local row = AVNodeFrame:GetOrCreateRow(avIndex)
                    local colorPrefix = ""
                    if useColors and faction == "Horde" then
                        colorPrefix = "|cFFFF4040"
                    elseif useColors and faction == "Alliance" then
                        colorPrefix = "|cFF4090FF"
                    end

                    if colorPrefix ~= "" then
                        row.fs:SetText(colorPrefix .. name .. ": " .. FormatTime(remaining) .. "|r")
                    else
                        row.fs:SetText(name .. ": " .. FormatTime(remaining))
                    end
                    local facText = faction and (" (" .. faction .. ")") or ""
                    row.announceText = name .. facText .. ": " .. FormatTime(remaining)
                    row:Show()
                    avIndex = avIndex + 1
                else
                    timers.AV[name] = nil
                end
            end
            if timers.Global["Match Starts"] and isAV then
                local remaining = math.floor(timers.Global["Match Starts"] - now)
                if remaining > 0 then
                    local row = AVNodeFrame:GetOrCreateRow(avIndex)
                    row.fs:SetText("|cFFFFFF00Match Starts: " .. FormatTime(remaining) .. "|r")
                    row.announceText = "Gates: " .. FormatTime(remaining)
                    row:Show()
                    avIndex = avIndex + 1
                else
                    timers.Global["Match Starts"] = nil
                end
            end
        end
    else
        if not isTestAll then
            timers.AV = {}
        end
    end
    AVNodeFrame:UpdateSize(avIndex)

    -- 3. WSG Timers (Flag Respawns 23s)
    local wsgIndex = 1
    if AutoBG_Settings.WSGTimers and (isTestAll or isWSG) then
        if isTestAll then
            local row1 = WSGFlagFrame:GetOrCreateRow(1)
            row1.fs:SetText("|cFF4090FFAlliance Flag: 0:23|r")
            row1.announceText = "Alliance Flag: 0:23"
            row1:Show()
            local row2 = WSGFlagFrame:GetOrCreateRow(2)
            row2.fs:SetText("|cFFFF4040Horde Flag: 0:17|r")
            row2.announceText = "Horde Flag: 0:17"
            row2:Show()
            wsgIndex = 3
        else
            for name, expireTime in pairs(timers.WSG) do
                local remaining = math.floor(expireTime - now)
                if remaining > 0 then
                    local row = WSGFlagFrame:GetOrCreateRow(wsgIndex)
                    local color = "|cFFFFFFFF"
                    if string.find(name, "Alliance") then color = "|cFF4090FF"
                    elseif string.find(name, "Horde") then color = "|cFFFF4040" end

                    row.fs:SetText(color .. name .. ": " .. FormatTime(remaining) .. "|r")
                    row.announceText = name .. ": " .. FormatTime(remaining)
                    row:Show()
                    wsgIndex = wsgIndex + 1
                else
                    timers.WSG[name] = nil
                end
            end
            if timers.Global["Match Starts"] and isWSG then
                local remaining = math.floor(timers.Global["Match Starts"] - now)
                if remaining > 0 then
                    local row = WSGFlagFrame:GetOrCreateRow(wsgIndex)
                    row.fs:SetText("|cFFFFFF00Match Starts: " .. FormatTime(remaining) .. "|r")
                    row.announceText = "Gates: " .. FormatTime(remaining)
                    row:Show()
                    wsgIndex = wsgIndex + 1
                else
                    timers.Global["Match Starts"] = nil
                end
            end
        end
    else
        if not isTestAll then
            timers.WSG = {}
        end
    end
    WSGFlagFrame:UpdateSize(wsgIndex)

    -- 4. Respawn Timer (Spirit Healer 30s Multi-Source Synchronized Wave)
    local isInstance, instanceType = IsInInstance()
    local inBG = (isInstance and instanceType == "pvp")

    if inBG and AutoBG_Settings.RessTimer then
        local healerTime = (GetAreaSpiritHealerTime and GetAreaSpiritHealerTime()) or 0
        if healerTime and healerTime > 0 then
            spiritHealerSyncTime = now - (30 - healerTime)
            spiritHealerSynced = true
        end

        if spiritHealerSyncTime == 0 then
            spiritHealerSyncTime = now
        end

        local elapsed = now - spiritHealerSyncTime
        local remaining = 30 - math.mod(elapsed, 30)
        local numRemaining = math.ceil(remaining)
        if numRemaining <= 0 then numRemaining = 30 end

        RespawnFrame.bar:SetValue(remaining)

        local r, g, b, colorCode
        if numRemaining > 10 then
            r, g, b = 0.1, 0.9, 0.2
            colorCode = "|cFF00FF00"
        elseif numRemaining > 5 then
            r, g, b = 1.0, 0.85, 0.0
            colorCode = "|cFFFFFF00"
        elseif numRemaining > 2 then
            r, g, b = 1.0, 0.5, 0.0
            colorCode = "|cFFFF8000"
        else
            r, g, b = 1.0, 0.15, 0.15
            colorCode = "|cFFFF2020"
        end

        RespawnFrame.bar:SetStatusBarColor(r, g, b)
        local prefix = spiritHealerSynced and "" or "~"
        RespawnFrame.timeText:SetText(colorCode .. prefix .. FormatTime(numRemaining) .. "|r")
        RespawnFrame.announceText = "Rez: " .. FormatTime(numRemaining)
        RespawnFrame:Show()
    elseif isTestAll and AutoBG_Settings.RessTimer then
        RespawnFrame.timeText:SetText("|cFF00FF000:24|r")
        RespawnFrame.bar:SetValue(24)
        RespawnFrame.bar:SetStatusBarColor(0.1, 0.9, 0.2)
        RespawnFrame.announceText = "Rez: 0:24"
        RespawnFrame:Show()
    else
        RespawnFrame:Hide()
    end

    -- 5. Queue Timers
    local queueIndex = 1
    if AutoBG_Settings.QueueTimers then
        if isTestAll then
            local row1 = QueueFrame:GetOrCreateRow(1)
            row1.fs:SetText("WSG: 1:15")
            row1.announceText = "WSG Queue: 1:15"
            row1:Show()
            local row2 = QueueFrame:GetOrCreateRow(2)
            row2.fs:SetText("AB: 4:32")
            row2.announceText = "AB Queue: 4:32"
            row2:Show()
            queueIndex = 3
        else
            local maxQueues = MAX_BATTLEFIELD_QUEUES or 3
            for i = 1, maxQueues do
                local status, mapName = GetBattlefieldStatus(i)
                if status == "queued" then
                    local waitTime = (GetBattlefieldTimeWaited and GetBattlefieldTimeWaited(i)) or 0
                    local elapsedSeconds = math.floor(waitTime / 1000)
                    local row = QueueFrame:GetOrCreateRow(queueIndex)

                    local abbrev = mapName or "BG"
                    if mapName == "Warsong Gulch" then abbrev = "WSG"
                    elseif mapName == "Arathi Basin" then abbrev = "AB"
                    elseif mapName == "Alterac Valley" then abbrev = "AV" end

                    row.fs:SetText(abbrev .. ": " .. FormatQueueTime(elapsedSeconds))
                    row.announceText = abbrev .. " Queue: " .. FormatQueueTime(elapsedSeconds)
                    row:Show()
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

-- Node list definitions & smart pattern matchers
local avNodes = {
    "Iceblood Tower", "Tower Point", "East Frostwolf Tower", "West Frostwolf Tower",
    "Stonehearth Bunker", "Icewing Bunker", "Dun Baldar North Bunker", "Dun Baldar South Bunker",
    "Frostwolf Relief Hut", "Snowfall Graveyard", "Stormpike Graveyard", "Iceblood Graveyard",
    "Frostwolf Graveyard", "Stonehearth Graveyard", "Stormpike Aid Station"
}

local function FindABNode(msg)
    local lowerMsg = string.lower(msg)
    if string.find(lowerMsg, "gold mine") or string.find(lowerMsg, "the mine") or string.find(lowerMsg, "mine!") or string.find(lowerMsg, " mine") then
        return "Gold Mine"
    elseif string.find(lowerMsg, "lumber mill") or string.find(lowerMsg, "the mill") or string.find(lowerMsg, "mill!") or string.find(lowerMsg, " mill") then
        return "Lumber Mill"
    elseif string.find(lowerMsg, "blacksmith") or string.find(lowerMsg, "the smith") or string.find(lowerMsg, "smith") then
        return "Blacksmith"
    elseif string.find(lowerMsg, "farm") then
        return "Farm"
    elseif string.find(lowerMsg, "stables") or string.find(lowerMsg, "stable") then
        return "Stables"
    end
    return nil
end

local function FindAVNode(msg)
    local lowerMsg = string.lower(msg)
    for i = 1, table.getn(avNodes) do
        local node = avNodes[i]
        if string.find(lowerMsg, string.lower(node)) then
            return node
        end
    end
    return nil
end

local function GetFactionFromMessage(msg, ev)
    if not msg then return nil end
    local lowerMsg = string.lower(msg)
    if string.find(lowerMsg, "horde") then
        return "Horde"
    elseif string.find(lowerMsg, "alliance") then
        return "Alliance"
    end

    if ev == "CHAT_MSG_BG_SYSTEM_HORDE" then
        return "Horde"
    elseif ev == "CHAT_MSG_BG_SYSTEM_ALLIANCE" then
        return "Alliance"
    end

    -- Extract player name: "<Player> has assaulted..." or "<Player> claims..."
    local _, _, playerName = string.find(msg, "^([^%s!]+)%s+has assaulted")
    if not playerName then
        _, _, playerName = string.find(msg, "^([^%s!]+)%s+claims")
    end
    if not playerName then
        _, _, playerName = string.find(msg, "^([^%s!]+)%s+has claimed")
    end
    if not playerName then
        _, _, playerName = string.find(msg, "^([^%s!]+)%s+assaulted")
    end

    if playerName then
        local myFaction = UnitFactionGroup("player")
        if not myFaction then return nil end
        local isFriendly = false
        local myName = UnitName("player")
        if myName and string.lower(myName) == string.lower(playerName) then
            isFriendly = true
        else
            local numRaid = GetNumRaidMembers()
            if numRaid and numRaid > 0 then
                for i = 1, numRaid do
                    local rName = UnitName("raid" .. i)
                    if rName and string.lower(rName) == string.lower(playerName) then
                        isFriendly = true
                        break
                    end
                end
            end
        end

        if isFriendly then
            return myFaction
        else
            return (myFaction == "Horde") and "Alliance" or "Horde"
        end
    end

    return nil
end

local function ParseCombatMessage(msg, ev)
    if not AutoBG_Settings or not msg then return end

    local currentZone = (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()) or ""
    local lowerZone = string.lower(currentZone)
    local isAB = (string.find(lowerZone, "arathi") ~= nil)
    local isAV = (string.find(lowerZone, "alterac") ~= nil)
    local isWSG = (string.find(lowerZone, "warsong") ~= nil)

    local lowerMsg = string.lower(msg)
    local assaultingFaction = GetFactionFromMessage(msg, ev)

    -- Arathi Basin Node Capture Timers (60s - ONLY in Arathi Basin)
    if AutoBG_Settings.ABTimers and isAB then
        local matchedAB = FindABNode(msg)
        if matchedAB then
            if string.find(lowerMsg, "claims") or string.find(lowerMsg, "assaulted") or string.find(lowerMsg, "claimed") then
                timers.AB[matchedAB] = { expire = GetTime() + 60, faction = assaultingFaction }
            elseif string.find(lowerMsg, "taken") or string.find(lowerMsg, "defended") or string.find(lowerMsg, "controls") or string.find(lowerMsg, "captured") then
                timers.AB[matchedAB] = nil
            end
        end
    end

    -- Alterac Valley Node Capture Timers (300s - ONLY in Alterac Valley)
    if AutoBG_Settings.AVTimers and isAV then
        local matchedAV = FindAVNode(msg)
        if matchedAV then
            if string.find(lowerMsg, "claims") or string.find(lowerMsg, "assaulted") or string.find(lowerMsg, "under attack") then
                timers.AV[matchedAV] = { expire = GetTime() + 300, faction = assaultingFaction }
            elseif string.find(lowerMsg, "taken") or string.find(lowerMsg, "defended") or string.find(lowerMsg, "destroyed") or string.find(lowerMsg, "controls") or string.find(lowerMsg, "captured") then
                timers.AV[matchedAV] = nil
            end
        end
    end

    -- Exact OctoWOW / Turtle WoW Pre-Match Gate Announcements
    if string.find(lowerMsg, "begins in 2 minute") then
        timers.Global["Match Starts"] = GetTime() + 120
    elseif string.find(lowerMsg, "begins in 1 minute") then
        timers.Global["Match Starts"] = GetTime() + 60
    elseif string.find(lowerMsg, "begins in 30 second") then
        timers.Global["Match Starts"] = GetTime() + 30
    elseif string.find(lowerMsg, "begins in 15 second") then
        timers.Global["Match Starts"] = GetTime() + 15
    elseif string.find(lowerMsg, "has begun") or string.find(lowerMsg, "begun!") or string.find(lowerMsg, "let the battle begin") or string.find(lowerMsg, "gates are open") or string.find(lowerMsg, "gates have opened") then
        timers.Global["Match Starts"] = nil
    end

    -- WSG Flag Respawns (23s - ONLY in Warsong Gulch)
    if AutoBG_Settings.WSGTimers and isWSG then
        if string.find(lowerMsg, "captured the alliance flag") or string.find(lowerMsg, "captured the horde flag") then
            if string.find(lowerMsg, "alliance flag") then
                timers.WSG["Alliance Flag"] = GetTime() + 23
            elseif string.find(lowerMsg, "horde flag") then
                timers.WSG["Horde Flag"] = GetTime() + 23
            end
        end
    end
end

local EventFrame = CreateFrame("Frame", "AutoBG_TimersEventFrame")
EventFrame:RegisterEvent("CHAT_MSG_BG_SYSTEM_NEUTRAL")
EventFrame:RegisterEvent("CHAT_MSG_BG_SYSTEM_ALLIANCE")
EventFrame:RegisterEvent("CHAT_MSG_BG_SYSTEM_HORDE")
EventFrame:RegisterEvent("CHAT_MSG_SYSTEM")
EventFrame:RegisterEvent("CHAT_MSG_MONSTER_YELL")
EventFrame:RegisterEvent("PLAYER_UNGHOST")
EventFrame:RegisterEvent("PLAYER_ALIVE")
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
        spiritHealerSyncTime = GetTime()
        spiritHealerSynced = false

    elseif ev == "PLAYER_UNGHOST" or ev == "PLAYER_ALIVE" then
        local isInstance, instanceType = IsInInstance()
        if isInstance and instanceType == "pvp" then
            local healerTime = (GetAreaSpiritHealerTime and GetAreaSpiritHealerTime()) or 0
            if healerTime and healerTime > 0 then
                spiritHealerSyncTime = GetTime() - (30 - healerTime)
                spiritHealerSynced = true
            elseif ev == "PLAYER_UNGHOST" then
                spiritHealerSyncTime = GetTime()
                spiritHealerSynced = true
            end
        end
    else
        ParseCombatMessage(a1, ev)
    end
end)
