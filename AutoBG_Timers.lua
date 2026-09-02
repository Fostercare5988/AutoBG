-- AutoBG Timers & Objective Countdown Engine (Zero-Bloat Consolidated Architecture)
-- Author & Maintainer: Fostercare5988
-- Built natively for ClassicAPI, SuperWoW 2.2+, NamPower 4.6.2+, UnitXP SP3, DXVK

local timers = { AB = {}, AV = {}, WSG = {}, Global = {} }
local spiritHealerSyncTime = 0
local spiritHealerSynced = false

-- Pre-allocated static Unit ID array (Part D2)
local RAID_UNITS = {}
for i = 1, 40 do RAID_UNITS[i] = "raid" .. i end

local function SendTimerAnnouncement(text)
    if not text or text == "" then return end
    local inInstance, instanceType = IsInInstance()
    local chatType = (inInstance and instanceType == "pvp") and "BATTLEGROUND" or "RAID"
    local numRaid = (GetNumRaidMembers and GetNumRaidMembers()) or 0
    local numParty = (GetNumPartyMembers and GetNumPartyMembers()) or 0

    if numRaid == 0 and numParty > 0 then
        chatType = "PARTY"
    elseif numRaid == 0 and numParty == 0 and not (inInstance and instanceType == "pvp") then
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
        if AutoBG_SavePosition then AutoBG_SavePosition(this, name) end
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
                if AutoBG_SavePosition then AutoBG_SavePosition(this:GetParent(), this:GetParent():GetName()) end
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
            btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

            local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("CENTER", btn, "CENTER", 0, 0)
            btn.fs = fs
            self.activeRows[index] = btn
        end
        return self.activeRows[index]
    end

    function frame:UpdateSize(index)
        local maxWidth = self.title:GetStringWidth() + 30
        local count = #self.activeRows
        for i = index, count do self.activeRows[i]:Hide() end

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
        if AutoBG_SavePosition then AutoBG_SavePosition(this, name) end
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
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
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
    local s = math.floor(seconds - m * 60)
    return (s < 10) and (m .. ":0" .. s) or (m .. ":" .. s)
end

local function FormatQueueTime(seconds)
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds - h * 3600) / 60)
    local s = math.floor(seconds - h * 3600 - m * 60)
    if h > 0 then
        return string.format("%d %s %d %s", h, (h == 1 and "Hr" or "Hrs"), m, (m == 1 and "Min" or "Mins"))
    elseif m > 0 then
        return string.format("%d %s %d %s", m, (m == 1 and "Min" or "Mins"), s, (s == 1 and "Sec" or "Secs"))
    else
        return string.format("%d %s", s, (s == 1 and "Sec" or "Secs"))
    end
end

-- Consolidated DRY Node / Timer Renderer (Replaces 180 lines of duplicated code)
local function RenderGenericTimerList(frame, timerTable, isEnabled, isZone, testRows)
    local rowIndex = 1
    local now = GetTime()
    local isTestAll = AutoBG_Settings and AutoBG_Settings.TestAllTimers
    local useColors = AutoBG_Settings and AutoBG_Settings.NodeColors

    if isEnabled and (isTestAll or isZone) then
        if isTestAll and testRows then
            for i = 1, #testRows do
                local row = frame:GetOrCreateRow(rowIndex)
                row.fs:SetText(testRows[i].text)
                row.announceText = testRows[i].announce
                row:Show()
                rowIndex = rowIndex + 1
            end
        else
            for name, data in pairs(timerTable) do
                local expireTime = (type(data) == "table" and data.expire) or data
                local faction = (type(data) == "table" and data.faction) or nil
                local remaining = math.floor(expireTime - now)

                if remaining > 0 then
                    local row = frame:GetOrCreateRow(rowIndex)
                    local colorPrefix = ""
                    if useColors and faction == "Horde" then colorPrefix = "|cFFFF4040"
                    elseif useColors and faction == "Alliance" then colorPrefix = "|cFF4090FF"
                    elseif string.find(name, "Alliance") then colorPrefix = "|cFF4090FF"
                    elseif string.find(name, "Horde") then colorPrefix = "|cFFFF4040"
                    end

                    row.fs:SetText((colorPrefix ~= "" and (colorPrefix .. name .. ": " .. FormatTime(remaining) .. "|r")) or (name .. ": " .. FormatTime(remaining)))
                    local facText = faction and (" (" .. faction .. ")") or ""
                    row.announceText = name .. facText .. ": " .. FormatTime(remaining)
                    row:Show()
                    rowIndex = rowIndex + 1
                else
                    timerTable[name] = nil
                end
            end
            if timers.Global["Match Starts"] and isZone then
                local remaining = math.floor(timers.Global["Match Starts"] - now)
                if remaining > 0 then
                    local row = frame:GetOrCreateRow(rowIndex)
                    row.fs:SetText("|cFFFFFF00Match Starts: " .. FormatTime(remaining) .. "|r")
                    row.announceText = "Gates: " .. FormatTime(remaining)
                    row:Show()
                    rowIndex = rowIndex + 1
                else
                    timers.Global["Match Starts"] = nil
                end
            end
        end
    else
        if not isTestAll then
            if table.wipe then
                table.wipe(timerTable)
            else
                for k in pairs(timerTable) do timerTable[k] = nil end
            end
        end
    end
    frame:UpdateSize(rowIndex)
end

-- 10 Hz Native Hardware Ticker (ClassicAPI C_Timer)
local function UpdateAllTimers()
    if not AutoBG_Settings then return end

    local currentZone = (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()) or ""
    local lowerZone = string.lower(currentZone)
    local isAB = (string.find(lowerZone, "arathi") ~= nil)
    local isAV = (string.find(lowerZone, "alterac") ~= nil)
    local isWSG = (string.find(lowerZone, "warsong") ~= nil)
    local now = GetTime()

    -- 1. AB Nodes
    RenderGenericTimerList(NodeFrame, timers.AB, AutoBG_Settings.ABTimers, isAB, {
        { text = "|cFFFF4040Blacksmith: 0:59|r", announce = "Blacksmith (Horde): 0:59" },
        { text = "|cFF4090FFLumber Mill: 0:42|r", announce = "Lumber Mill (Alliance): 0:42" }
    })

    -- 2. AV Nodes
    RenderGenericTimerList(AVNodeFrame, timers.AV, AutoBG_Settings.AVTimers, isAV, {
        { text = "|cFFFF4040Stonehearth Bunker: 4:59|r", announce = "Stonehearth Bunker (Horde): 4:59" },
        { text = "|cFF4090FFIceblood Tower: 3:30|r", announce = "Iceblood Tower (Alliance): 3:30" }
    })

    -- 3. WSG Flags
    RenderGenericTimerList(WSGFlagFrame, timers.WSG, AutoBG_Settings.WSGTimers, isWSG, {
        { text = "|cFF4090FFAlliance Flag: 0:23|r", announce = "Alliance Flag: 0:23" },
        { text = "|cFFFF4040Horde Flag: 0:17|r", announce = "Horde Flag: 0:17" }
    })

    -- 4. Respawn Timer (Spirit Healer 30s Wave)
    local inInstance, instanceType = IsInInstance()
    local inPVP = (inInstance and instanceType == "pvp")
    local isTestAll = AutoBG_Settings.TestAllTimers

    if inPVP and AutoBG_Settings.RessTimer then
        local healerTime = (GetAreaSpiritHealerTime and GetAreaSpiritHealerTime()) or 0
        if healerTime > 0 then
            spiritHealerSyncTime = now - (30 - healerTime)
            spiritHealerSynced = true
        end
        if spiritHealerSyncTime == 0 then spiritHealerSyncTime = now end

        local elapsed = now - spiritHealerSyncTime
        local remaining = 30 - (elapsed % 30)
        local numRemaining = math.ceil(remaining)
        if numRemaining <= 0 then numRemaining = 30 end

        RespawnFrame.bar:SetValue(remaining)
        local colorCode = (numRemaining > 10 and "|cFF00FF00") or (numRemaining > 5 and "|cFFFFFF00") or (numRemaining > 2 and "|cFFFF8000") or "|cFFFF2020"
        local r, g, b = (numRemaining > 10 and 0.1) or (numRemaining > 5 and 1.0) or 1.0, (numRemaining > 10 and 0.9) or (numRemaining > 5 and 0.85) or 0.15, (numRemaining > 10 and 0.2) or 0.0

        RespawnFrame.bar:SetStatusBarColor(r, g, b)
        RespawnFrame.timeText:SetText(colorCode .. (spiritHealerSynced and "" or "~") .. FormatTime(numRemaining) .. "|r")
        RespawnFrame.announceText = "Ress: " .. FormatTime(numRemaining)
        RespawnFrame:Show()
    elseif isTestAll and AutoBG_Settings.RessTimer then
        RespawnFrame.timeText:SetText("|cFF00FF000:24|r")
        RespawnFrame.bar:SetValue(24)
        RespawnFrame.bar:SetStatusBarColor(0.1, 0.9, 0.2)
        RespawnFrame.announceText = "Ress: 0:24"
        RespawnFrame:Show()
    else
        RespawnFrame:Hide()
    end

    -- 5. Queue Timers
    local qIndex = 1
    if AutoBG_Settings.QueueTimers then
        if isTestAll then
            local r1 = QueueFrame:GetOrCreateRow(1); r1.fs:SetText("WSG: 1:15"); r1.announceText = "WSG Queue: 1:15"; r1:Show()
            local r2 = QueueFrame:GetOrCreateRow(2); r2.fs:SetText("AB: 4:32"); r2.announceText = "AB Queue: 4:32"; r2:Show()
            qIndex = 3
        else
            local maxQ = MAX_BATTLEFIELD_QUEUES or 3
            for i = 1, maxQ do
                local status, mapName = GetBattlefieldStatus(i)
                if status == "queued" then
                    local waitTime = (GetBattlefieldTimeWaited and GetBattlefieldTimeWaited(i)) or 0
                    local sec = math.floor(waitTime / 1000)
                    local row = QueueFrame:GetOrCreateRow(qIndex)
                    local abbrev = (mapName == "Warsong Gulch" and "WSG") or (mapName == "Arathi Basin" and "AB") or (mapName == "Alterac Valley" and "AV") or mapName or "BG"
                    row.fs:SetText(abbrev .. ": " .. FormatQueueTime(sec))
                    row.announceText = abbrev .. " Queue: " .. FormatQueueTime(sec)
                    row:Show()
                    qIndex = qIndex + 1
                end
            end
        end
    end
    QueueFrame:UpdateSize(qIndex)
end

if C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(0.1, UpdateAllTimers)
end

function AutoBG_Timers_UpdateVisibility() UpdateAllTimers() end

-- Static Node Tables & Matchers
local AB_NODES = { "Gold Mine", "Lumber Mill", "Blacksmith", "Farm", "Stables" }
local AV_NODES = {
    "Iceblood Tower", "Tower Point", "East Frostwolf Tower", "West Frostwolf Tower",
    "Stonehearth Bunker", "Icewing Bunker", "Dun Baldar North Bunker", "Dun Baldar South Bunker",
    "Frostwolf Relief Hut", "Snowfall Graveyard", "Stormpike Graveyard", "Iceblood Graveyard",
    "Frostwolf Graveyard", "Stonehearth Graveyard", "Stormpike Aid Station"
}

local function MatchNodeName(msg, nodeList)
    local lower = string.lower(msg)
    for i = 1, #nodeList do
        if string.find(lower, string.lower(nodeList[i])) then return nodeList[i] end
    end
    if string.find(lower, "mine") then return "Gold Mine"
    elseif string.find(lower, "mill") then return "Lumber Mill"
    elseif string.find(lower, "smith") then return "Blacksmith"
    elseif string.find(lower, "stable") then return "Stables" end
    return nil
end

local function GetFactionFromMessage(msg, ev)
    if not msg then return nil end
    local lower = string.lower(msg)
    if string.find(lower, "horde") or ev == "CHAT_MSG_BG_SYSTEM_HORDE" then return "Horde" end
    if string.find(lower, "alliance") or ev == "CHAT_MSG_BG_SYSTEM_ALLIANCE" then return "Alliance" end

    local _, _, player = string.find(msg, "^([^%s!]+)%s+[ha]s?%s*claims?")
    if not player then _, _, player = string.find(msg, "^([^%s!]+)%s+assaulted") end

    if player then
        local myFaction = UnitFactionGroup("player")
        local isFriendly = (string.lower(UnitName("player") or "") == string.lower(player))
        if not isFriendly then
            local numRaid = (GetNumRaidMembers and GetNumRaidMembers()) or 0
            for i = 1, numRaid do
                local u = RAID_UNITS[i]
                if u and string.lower(UnitName(u) or "") == string.lower(player) then
                    isFriendly = true
                    break
                end
            end
        end
        return isFriendly and myFaction or ((myFaction == "Horde") and "Alliance" or "Horde")
    end
    return nil
end

local function ParseCombatMessage(msg, ev)
    if not AutoBG_Settings or not msg then return end
    local zone = string.lower((GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()) or "")
    local lower = string.lower(msg)
    local faction = GetFactionFromMessage(msg, ev)

    -- 1. AB Nodes (60s)
    if AutoBG_Settings.ABTimers and string.find(zone, "arathi") then
        local node = MatchNodeName(msg, AB_NODES)
        if node then
            if string.find(lower, "claims") or string.find(lower, "assaulted") or string.find(lower, "claimed") then
                timers.AB[node] = { expire = GetTime() + 60, faction = faction }
            elseif string.find(lower, "taken") or string.find(lower, "defended") or string.find(lower, "captured") then
                timers.AB[node] = nil
            end
        end
    end

    -- 2. AV Nodes (300s)
    if AutoBG_Settings.AVTimers and string.find(zone, "alterac") then
        local node = MatchNodeName(msg, AV_NODES)
        if node then
            if string.find(lower, "claims") or string.find(lower, "assaulted") or string.find(lower, "under attack") then
                timers.AV[node] = { expire = GetTime() + 300, faction = faction }
            elseif string.find(lower, "taken") or string.find(lower, "defended") or string.find(lower, "destroyed") or string.find(lower, "captured") then
                timers.AV[node] = nil
            end
        end
    end

    -- 3. Gate Pre-Match Announcements
    if string.find(lower, "begins in 2 minute") then timers.Global["Match Starts"] = GetTime() + 120
    elseif string.find(lower, "begins in 1 minute") then timers.Global["Match Starts"] = GetTime() + 60
    elseif string.find(lower, "begins in 30 second") then timers.Global["Match Starts"] = GetTime() + 30
    elseif string.find(lower, "begins in 15 second") then timers.Global["Match Starts"] = GetTime() + 15
    elseif string.find(lower, "begun") or string.find(lower, "open") then timers.Global["Match Starts"] = nil end

    -- 4. WSG Flag Respawns (23s)
    if AutoBG_Settings.WSGTimers and string.find(zone, "warsong") then
        if string.find(lower, "captured the alliance flag") then timers.WSG["Alliance Flag"] = GetTime() + 23
        elseif string.find(lower, "captured the horde flag") then timers.WSG["Horde Flag"] = GetTime() + 23 end
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
    if ev == "PLAYER_ENTERING_WORLD" then
        AutoBG_LoadTimerPositions()
        if table.wipe then
            table.wipe(timers.AB)
            table.wipe(timers.AV)
            table.wipe(timers.WSG)
            table.wipe(timers.Global)
        else
            for k in pairs(timers.AB) do timers.AB[k] = nil end
            for k in pairs(timers.AV) do timers.AV[k] = nil end
            for k in pairs(timers.WSG) do timers.WSG[k] = nil end
            for k in pairs(timers.Global) do timers.Global[k] = nil end
        end
        spiritHealerSyncTime = GetTime()
        spiritHealerSynced = false
    elseif ev == "PLAYER_UNGHOST" or ev == "PLAYER_ALIVE" then
        local inInstance, instanceType = IsInInstance()
        if inInstance and instanceType == "pvp" then
            local healerTime = (GetAreaSpiritHealerTime and GetAreaSpiritHealerTime()) or 0
            spiritHealerSyncTime = (healerTime > 0) and (GetTime() - (30 - healerTime)) or GetTime()
            spiritHealerSynced = true
        end
    else
        ParseCombatMessage(arg1, ev)
    end
end)
