-- AutoBG objective countdowns, resurrection waves and score projection.
-- Author & Maintainer: Fostercare5988
-- Built natively for ClassicAPI v1.17.7+, SuperWoW 2.2+, UnitXP SP3

-- Strict Engine Dependency Guard (Mandatory ClassicAPI v1.17.7+ & SuperWoW v2.2+)
local MIN_CLASSIC_API = 11707

if type(CLASSIC_API_VERSION) ~= "number" or not SUPERWOW_VERSION or
   CLASSIC_API_VERSION < MIN_CLASSIC_API then
    return
end

local timers = { AB = {}, AV = {}, WSG = {}, Global = {} }
local spiritHealerSyncTime = 0
local spiritHealerSynced = false
-- Raid members seen as ghosts. A ghost comes back only through a spirit
-- healer's wave, so the moment one turns alive is a wave.
local raidGhosts = {}
local nextGhostScan = 0

-- Assumes one 30s wave for the whole battleground, as on MaNGOS-based cores.
-- UNVERIFIED on OctoWoW: test in game that a teammate's ghost revival and your
-- own countdown hit 0:00 together.
local function SyncSpiritWave(at)
    spiritHealerSyncTime = at
    spiritHealerSynced = true
end
local updateTicker = nil
local SyncUpdateTicker
local queuedBattlegrounds = {}
local queuedCount = 0
local lastQueueSecond, lastQueuePreview, lastQueueEnabled = nil, nil, nil
local worldStateDirty = true

-- Queue membership changes on this event; waited/estimated times remain live reads.
local function RefreshQueuedBattlegrounds()
    lastQueueSecond = nil
    table.wipe(queuedBattlegrounds)
    queuedCount = 0
    for i = 1, MAX_BATTLEFIELD_QUEUES or 3 do
        local status, mapName = GetBattlefieldStatus(i)
        if status == "queued" then
            queuedCount = queuedCount + 1
            queuedBattlegrounds[queuedCount] = { id = i, map = mapName }
        end
    end
end

-- Cached Zone & Instance State
local cachedZone = ""
local isAB, isAV, isWSG, inPVP = false, false, false, false

local function UpdateZoneCache()
    cachedZone = string.lower((GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()) or "")
    local inInstance, instanceType = IsInInstance()
    inPVP = (inInstance and instanceType == "pvp") and true or false
    -- Only battleground instances count; Arathi Highlands and Alterac Mountains do not.
    isAB  = inPVP and string.find(cachedZone, "arathi")  ~= nil
    isAV  = inPVP and string.find(cachedZone, "alterac") ~= nil
    isWSG = inPVP and string.find(cachedZone, "warsong") ~= nil
end
UpdateZoneCache()

-- Pre-allocated static sort buffer (Section 10 - Bounded Array Rule)
local activeSortBuffer = {}
for i = 1, 30 do activeSortBuffer[i] = { name = "", expire = 0, faction = nil } end

-- Pre-allocated static Unit ID array (Part D2)
local RAID_UNITS = {}
for i = 1, 40 do RAID_UNITS[i] = "raid" .. i end

local function SendTimerAnnouncement(text)
    if AutoBG_SendAnnouncement then
        AutoBG_SendAnnouncement(text)
        return
    end
    if not text or text == "" then return end
    local inInstance, instanceType = IsInInstance()
    local isPvP = (inInstance and instanceType == "pvp")
    local numRaid = (GetNumRaidMembers and GetNumRaidMembers()) or 0
    local numParty = (GetNumPartyMembers and GetNumPartyMembers()) or 0
    local chatType = isPvP and "BATTLEGROUND" or "RAID"

    if not isPvP and numRaid == 0 then
        if numParty > 0 then
            chatType = "PARTY"
        else
            chatType = "SAY"
        end
    end
    SendChatMessage(text, chatType)
end

-- =========================================================
-- Shared Bar Timer Frame Factory
-- =========================================================
local FONT             = "Fonts\\FRIZQT__.TTF"
local BAR_TEXTURE      = [[Interface\AddOns\AutoBG\Textures\barTexture.tga]]
local ALLIANCE_FLAG_TEX = "Interface\\WorldStateFrame\\AllianceFlag"
local HORDE_FLAG_TEX   = "Interface\\WorldStateFrame\\HordeFlag"

local NEUTRAL_ICON     = "Interface\\Icons\\INV_Misc_PocketWatch_01"
local BAR_ROW_GAP      = 2
local BAR_TITLE_H      = 15
local BAR_COLORS = {
    Alliance = { 0.20, 0.46, 0.86 },
    Horde    = { 0.80, 0.20, 0.17 },
    neutral  = { 0.80, 0.62, 0.18 },
}

-- Icon tile on the left, slim draining bar on the right; one dark frame around both.
local function LayoutTimerRow(row, width, height)
    row:SetWidth(width)
    row:SetHeight(height)
    row.icon:SetWidth(height - 2)
    row.icon:SetHeight(height - 2)
    row.bar:ClearAllPoints()
    row.bar:SetPoint("TOPLEFT", row, "TOPLEFT", height, -1)
    row.bar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -1, 1)
    local fontSize = math.max(9, math.min(14, math.floor(height * 0.52)))
    row.labelFs:SetFont(FONT, fontSize, "OUTLINE")
    row.timeFs:SetFont(FONT, fontSize, "OUTLINE")
end

-- Presentation settings affect objective groups only; stored anchors remain unchanged.
local function ApplyObjectiveAppearance(frame)
    local settings = AutoBG_Settings or {}
    local width = math.max(180, math.min(420, tonumber(settings.ObjectiveWidth) or 225))
    local height = math.max(18, math.min(32, tonumber(settings.ObjectiveHeight) or 25))
    local scale = math.max(0.60, math.min(1.50, tonumber(settings.ObjectiveScale) or 1))
    local opacity = math.max(0.20, math.min(1, tonumber(settings.ObjectiveOpacity) or 0.9))
    if frame.appearanceWidth ~= width or frame.rowHeight ~= height then
        frame:SetWidth(width)
        frame.rowHeight = height
        frame.appearanceWidth = width
        for i = 1, #frame.rows do
            LayoutTimerRow(frame.rows[i], width, height)
        end
    end
    if frame.appearanceScale ~= scale then frame:SetScale(scale); frame.appearanceScale = scale end
    if frame.appearanceOpacity ~= opacity then frame:SetAlpha(opacity); frame.appearanceOpacity = opacity end
end

-- This render-only handler runs only while its group is shown.
-- Event/timer logic still owns expiry, sorting, labels and announcements.
local function AnimateObjectiveFill()
    local frame = this
    local now = GetTime()
    for i = 1, #frame.rows do
        local row = frame.rows[i]
        if row:IsShown() and row.fillExpiry then
            row.bar:SetValue(math.max(0, row.fillExpiry - now))
        end
    end
end

local function CreateBarTimerFrame(name, titleText, xOffset, yOffset, maxRows, defaultIcon)
    local width, rowHeight = 260, 22
    local titleHeight = titleText and BAR_TITLE_H or 0
    local frame = CreateFrame("Frame", name, UIParent)
    frame:SetWidth(width)
    frame:SetHeight(titleHeight + rowHeight)
    frame.rowHeight = rowHeight
    frame.headerHeight = titleHeight
    frame.defaultIcon = defaultIcon or NEUTRAL_ICON
    frame:SetPoint("TOP", UIParent, "TOP", xOffset, yOffset)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() this:StartMoving() end)
    frame:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        if AutoBG_SavePosition then AutoBG_SavePosition(this, name) end
    end)
    frame:Hide()

    if titleText then
        local titleFs = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        titleFs:SetFont(FONT, 10, "OUTLINE")
        titleFs:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
        titleFs:SetJustifyH("LEFT")
        titleFs:SetText(titleText)
        titleFs:SetTextColor(0.86, 0.84, 0.78)
        frame.titleFs = titleFs
    end

    frame.rows = {}
    for i = 1, maxRows do
        local row = CreateFrame("Button", name .. "Row" .. i, frame)
        if i == 1 then
            row:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -titleHeight)
        else
            row:SetPoint("TOPLEFT", frame.rows[i - 1], "BOTTOMLEFT", 0, -BAR_ROW_GAP)
        end
        row:EnableMouse(true)
        row:RegisterForClicks("LeftButtonUp")
        row:RegisterForDrag("LeftButton")
        row:SetScript("OnDragStart", function()
            GameTooltip:Hide()
            frame:StartMoving()
        end)
        row:SetScript("OnDragStop", function()
            frame:StopMovingOrSizing()
            if AutoBG_SavePosition then AutoBG_SavePosition(frame, name) end
        end)
        row:SetScript("OnClick", function()
            if IsControlKeyDown() and this.announceText then SendTimerAnnouncement(this.announceText) end
        end)
        row:SetScript("OnEnter", function()
            if this.announceText and this.announceText ~= "" then
                GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
                GameTooltip:SetText(this.announceText, 1, 1, 1)
                GameTooltip:AddLine("|cFF7CD8FFCTRL+LeftClick:|r Announce timer to /bg", 0.7, 0.7, 0.7)
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)

        -- The row button owns the full click area; textures and font strings do not take mouse input.
        local frameBg = row:CreateTexture(nil, "BACKGROUND")
        frameBg:SetAllPoints(row)
        frameBg:SetTexture(0, 0, 0, 0.70)

        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("LEFT", row, "LEFT", 1, 0)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.icon = icon

        local bar = CreateFrame("StatusBar", name .. "Row" .. i .. "Bar", row)
        bar:SetStatusBarTexture(BAR_TEXTURE)
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(1)
        bar:EnableMouse(false)
        row.bar = bar

        local track = bar:CreateTexture(nil, "BACKGROUND")
        track:SetAllPoints(bar)
        track:SetTexture(BAR_TEXTURE)
        track:SetVertexColor(0.13, 0.13, 0.15, 0.90)

        local hover = row:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints(row)
        hover:SetTexture(1, 1, 1, 0.07)

        local labelFs = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        labelFs:SetPoint("LEFT", bar, "LEFT", 5, 0)
        labelFs:SetPoint("RIGHT", bar, "RIGHT", -46, 0)
        labelFs:SetJustifyH("LEFT")
        labelFs:SetTextColor(1, 1, 1, 1)
        row.labelFs = labelFs

        local timeFs = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        timeFs:SetPoint("RIGHT", bar, "RIGHT", -5, 0)
        timeFs:SetJustifyH("RIGHT")
        timeFs:SetTextColor(1, 1, 1, 1)
        row.timeFs = timeFs

        LayoutTimerRow(row, width, rowHeight)
        row:Hide()
        frame.rows[i] = row
    end

    frame:SetScript("OnUpdate", AnimateObjectiveFill)
    return frame
end

-- =========================================================
-- Respawn Frame (Spirit Healer 30s Wave)
-- =========================================================
local function CreateRespawnFrame(name, xOffset, yOffset)
    local frame = CreateFrame("Button", name, UIParent)
    frame:SetWidth(110)
    frame:SetHeight(38)
    frame:SetPoint("TOP", UIParent, "TOP", xOffset, yOffset)
    frame:SetBackdrop({
        bgFile  = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    frame:SetBackdropColor(0, 0, 0, 0.80)
    frame:SetBackdropBorderColor(0.35, 0.10, 0.10, 0.90)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:RegisterForClicks("LeftButtonUp")
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() this:StartMoving() end)
    frame:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        if AutoBG_SavePosition then AutoBG_SavePosition(this, name) end
    end)
    frame:SetScript("OnClick", function()
        if IsControlKeyDown() and this.announceText then SendTimerAnnouncement(this.announceText) end
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
    title:SetTextColor(0.90, 0.20, 0.20)

    local timeText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    timeText:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -6)
    timeText:SetText("0:30")

    local bar = CreateFrame("StatusBar", name .. "Bar", frame)
    bar:SetPoint("BOTTOMLEFT",  frame, "BOTTOMLEFT",   8, 7)
    bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 7)
    bar:SetHeight(8)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetMinMaxValues(0, 30)
    bar:SetValue(30)
    bar:SetStatusBarColor(0.1, 0.85, 0.1)
    bar:EnableMouse(false)

    local barBg = bar:CreateTexture(nil, "BACKGROUND")
    barBg:SetAllPoints(bar)
    barBg:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    barBg:SetVertexColor(0.2, 0.2, 0.2, 0.8)

    frame.title    = title
    frame.timeText = timeText
    frame.bar      = bar
    return frame
end

-- =========================================================
-- Draggable Text Timer Frame Factory (BG Queues)
-- =========================================================
local function CreateDraggableTimerFrame(name, titleText, xOffset, yOffset, minWidth)
    local frame = CreateFrame("Frame", name, UIParent)
    frame:SetWidth(minWidth or 130)
    frame:SetHeight(30)
    frame:SetPoint("TOP", UIParent, "TOP", xOffset, yOffset)
    frame:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile     = true, tileSize = 16, edgeSize = 16,
        insets   = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    frame:SetBackdropColor(0, 0, 0, 0.75)
    frame:SetBackdropBorderColor(0.35, 0.10, 0.10, 0.90)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
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
    title:SetTextColor(0.85, 0.70, 0.10)
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
                    if this.estText and this.estText ~= "" then
                        GameTooltip:AddLine(this.estText, 0.9, 0.9, 0.5)
                    end
                    GameTooltip:AddLine("|cFF00FF00CTRL+LeftClick:|r Announce to chat", 0.7, 0.7, 0.7)
                    GameTooltip:Show()
                end
            end)
            btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

            local icon = btn:CreateTexture(nil, "OVERLAY")
            icon:SetWidth(12)
            icon:SetHeight(12)
            icon:SetPoint("LEFT", btn, "LEFT", 4, 0)
            icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            btn.icon = icon

            local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("LEFT", icon, "RIGHT", 4, 0)
            btn.fs = fs
            self.activeRows[index] = btn
        end
        return self.activeRows[index]
    end

    function frame:UpdateSize(index)
        local maxWidth = self.title:GetStringWidth() + 30
        local count = #self.activeRows
        for i = index, count do
            if self.activeRows[i]:IsShown() then self.activeRows[i]:Hide() end
        end

        for i = 1, index - 1 do
            local w = self.activeRows[i].fs:GetStringWidth() + 38
            if w > maxWidth then maxWidth = w end
        end

        if index > 1 then
            local width = math.max(minWidth or 130, maxWidth)
            if self.displayWidth ~= width or self.displayCount ~= index - 1 then
                self:SetWidth(width)
                self:SetHeight(30 + (index - 1) * 16)
                for i = 1, index - 1 do
                    self.activeRows[i]:SetWidth(width - 16)
                end
                self.displayWidth, self.displayCount = width, index - 1
            end
            if not self:IsShown() then self:Show() end
        else
            if self:IsShown() then self:Hide() end
        end
    end

    return frame
end

-- =========================================================
-- Frame Instantiation
-- =========================================================
local QueueFrame   = CreateDraggableTimerFrame("AutoBG_QueueFrame", "BG Queues", -220, -100, 130)
local RespawnFrame = CreateRespawnFrame("AutoBG_RespawnFrame", 0, -100)
local StartTimerFrame = CreateBarTimerFrame("AutoBG_StartTimerFrame", nil,              0,   -60, 1)
local NodeBarFrame = CreateBarTimerFrame("AutoBG_NodeFrame",    "Arathi Basin",   220, -100, 5)
local AVNodeFrame  = CreateBarTimerFrame("AutoBG_AVNodeFrame",  "Alterac Valley", 220, -150, 8)
local WSGFlagFrame = CreateBarTimerFrame("AutoBG_WSGFlagFrame", "Warsong Gulch", -110, -150, 2)

-- =========================================================
-- Arathi Basin Score Projection Frame (Sleek 2-Row Dual-Column Layout)
-- =========================================================
local AB_PROJ_WIDTH = 132
local AB_PROJ_HEIGHT = 30

local function CreateABProjectionFrame(name)
    local frame = CreateFrame("Button", name, UIParent)
    frame:SetWidth(AB_PROJ_WIDTH)
    frame:SetHeight(AB_PROJ_HEIGHT)
    frame:SetFrameStrata("HIGH")
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:RegisterForClicks("LeftButtonUp")
    frame:RegisterForDrag("LeftButton")

    frame:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile     = true, tileSize = 16, edgeSize = 12,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    frame:SetBackdropColor(0, 0, 0, 0.65)
    frame:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.75)

    frame:SetScript("OnDragStart", function()
        this:StartMoving()
    end)
    frame:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        if AutoBG_SavePosition then AutoBG_SavePosition(this, name) end
    end)
    frame:SetScript("OnClick", function()
        local self = this or frame
        if IsControlKeyDown() and self.announceText and self.announceText ~= "" then
            SendTimerAnnouncement(self.announceText)
        end
    end)
    frame:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetText("Arathi Basin Score Projection", 1, 0.82, 0)
        GameTooltip:AddLine("Live score forecast based on base capture rates and impending flips.", 0.9, 0.9, 0.9, 1)
        GameTooltip:AddLine("|cFF00FF00CTRL+LeftClick:|r Announce projection to chat", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("|cFF00FF00Left-drag:|r Reposition HUD overlay", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Two rows: verdict and bases needed on the left, both starting at the same
    -- edge; final scores right-aligned in their own column.
    local r1Status = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r1Status:SetPoint("LEFT", frame, "LEFT", 7, 6)
    r1Status:SetPoint("RIGHT", frame, "RIGHT", -50, 6)
    r1Status:SetJustifyH("LEFT")
    r1Status:SetText("")
    frame.r1Status = r1Status

    local r1Score = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r1Score:SetPoint("RIGHT", frame, "RIGHT", -7, 6)
    r1Score:SetWidth(40)
    r1Score:SetJustifyH("RIGHT")
    r1Score:SetTextColor(0.38, 0.69, 1.00) -- Alliance Blue
    r1Score:SetText("")
    frame.r1Score = r1Score

    local r2Bases = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r2Bases:SetPoint("LEFT", frame, "LEFT", 7, -6)
    r2Bases:SetPoint("RIGHT", frame, "RIGHT", -50, -6)
    r2Bases:SetJustifyH("LEFT")
    r2Bases:SetTextColor(1.00, 0.82, 0.00) -- Gold
    r2Bases:SetText("")
    frame.r2Bases = r2Bases

    local r2Score = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r2Score:SetPoint("RIGHT", frame, "RIGHT", -7, -6)
    r2Score:SetWidth(40)
    r2Score:SetJustifyH("RIGHT")
    r2Score:SetTextColor(1.00, 0.38, 0.38) -- Horde Red
    r2Score:SetText("")
    frame.r2Score = r2Score

    -- A faint rule between the two columns.
    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetTexture(1, 1, 1, 0.12)
    divider:SetWidth(1)
    divider:SetPoint("TOP", frame, "TOPRIGHT", -46, -6)
    divider:SetPoint("BOTTOM", frame, "BOTTOMRIGHT", -46, 6)

    frame:Hide()
    return frame
end

local ABProjectionFrame = CreateABProjectionFrame("AutoBG_ABProjectionFrame")

function AutoBG_LoadTimerPositions()
    if AutoBG_LoadPosition then
        AutoBG_LoadPosition(QueueFrame,   "AutoBG_QueueFrame",   "TOP", -220, -100)
        AutoBG_LoadPosition(RespawnFrame, "AutoBG_RespawnFrame", "TOP",    0, -100)
        AutoBG_LoadPosition(NodeBarFrame, "AutoBG_NodeFrame",    "TOP",  220, -100)
        AutoBG_LoadPosition(AVNodeFrame,  "AutoBG_AVNodeFrame",  "TOP",  220, -150)
        AutoBG_LoadPosition(WSGFlagFrame, "AutoBG_WSGFlagFrame", "TOP", -110, -150)
        AutoBG_LoadPosition(StartTimerFrame, "AutoBG_StartTimerFrame", "TOP", 0, -60)

        if AutoBG_Settings and AutoBG_Settings.Positions and AutoBG_Settings.Positions["AutoBG_ABProjectionFrame"] then
            AutoBG_LoadPosition(ABProjectionFrame, "AutoBG_ABProjectionFrame", "TOP", -160, -25)
            ABProjectionFrame:SetBackdropColor(0, 0, 0, 0.65)
            ABProjectionFrame:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.75)
        elseif AlwaysUpFrame1 and AlwaysUpFrame1:IsShown() then
            ABProjectionFrame:ClearAllPoints()
            ABProjectionFrame:SetPoint("TOPRIGHT", AlwaysUpFrame1, "TOPLEFT", -6, 2)
            ABProjectionFrame:SetBackdropColor(0, 0, 0, 0.35)
            ABProjectionFrame:SetBackdropBorderColor(0, 0, 0, 0)
        else
            ABProjectionFrame:ClearAllPoints()
            ABProjectionFrame:SetPoint("TOP", UIParent, "TOP", -160, -25)
            ABProjectionFrame:SetBackdropColor(0, 0, 0, 0.65)
            ABProjectionFrame:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.75)
        end
    end
end

function AutoBG_ResetTimerPositions()
    if AutoBG_Settings and AutoBG_Settings.Positions then
        AutoBG_Settings.Positions["AutoBG_QueueFrame"] = nil
        AutoBG_Settings.Positions["AutoBG_RespawnFrame"] = nil
        AutoBG_Settings.Positions["AutoBG_NodeFrame"] = nil
        AutoBG_Settings.Positions["AutoBG_AVNodeFrame"] = nil
        AutoBG_Settings.Positions["AutoBG_WSGFlagFrame"] = nil
        AutoBG_Settings.Positions["AutoBG_StartTimerFrame"] = nil
        AutoBG_Settings.Positions["AutoBG_ABProjectionFrame"] = nil
    end

    QueueFrame:ClearAllPoints();   QueueFrame:SetPoint("TOP",   UIParent, "TOP", -220, -100) -- octowow-ignore: AP-31
    RespawnFrame:ClearAllPoints(); RespawnFrame:SetPoint("TOP", UIParent, "TOP",    0, -100) -- octowow-ignore: AP-31
    NodeBarFrame:ClearAllPoints(); NodeBarFrame:SetPoint("TOP", UIParent, "TOP",  220, -100) -- octowow-ignore: AP-31
    AVNodeFrame:ClearAllPoints();  AVNodeFrame:SetPoint("TOP",  UIParent, "TOP",  220, -150) -- octowow-ignore: AP-31
    WSGFlagFrame:ClearAllPoints(); WSGFlagFrame:SetPoint("TOP", UIParent, "TOP", -110, -150) -- octowow-ignore: AP-31
    StartTimerFrame:ClearAllPoints(); StartTimerFrame:SetPoint("TOP", UIParent, "TOP", 0, -60) -- octowow-ignore: AP-31

    ABProjectionFrame:ClearAllPoints()
    if AlwaysUpFrame1 and AlwaysUpFrame1:IsShown() then
        ABProjectionFrame:SetPoint("TOPRIGHT", AlwaysUpFrame1, "TOPLEFT", -6, 2)
        ABProjectionFrame:SetBackdropColor(0, 0, 0, 0.35)
        ABProjectionFrame:SetBackdropBorderColor(0, 0, 0, 0)
    else
        ABProjectionFrame:SetPoint("TOP", UIParent, "TOP", -160, -25)
        ABProjectionFrame:SetBackdropColor(0, 0, 0, 0.65)
        ABProjectionFrame:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.75)
    end
end

-- =========================================================
-- Time Utilities
-- =========================================================
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

-- =========================================================
-- Static Test Data Tables
-- =========================================================
local AB_TEST_DATA = {
    { name = "Blacksmith",  remaining = 31, faction = "Horde"    },
    { name = "Lumber Mill", remaining = 52, faction = "Alliance" },
}
local AV_TEST_DATA = {
    { name = "Stonehearth Bunker", remaining = 179, faction = "Horde"    },
    { name = "Iceblood Tower",     remaining = 210, faction = "Alliance" },
}
local WSG_TEST_DATA = {
    { name = "Alliance Flag", remaining = 11, faction = "Alliance" },
    { name = "Horde Flag",    remaining = 17, faction = "Horde"    },
}
local START_TEST_DATA = {
    { name = "Match Starts",  remaining = 45, faction = nil },
}

-- =========================================================
-- Countdown Bar Row Renderer (Match Start / AB / AV / WSG)
-- Rows take their faction's color; colorMode = "faction" also derives the
-- faction from a WSG flag name.
-- =========================================================
local function ApplyTimerRowData(row, name, faction, remaining, maxTime, colorMode, defaultIcon)
    -- WSG live timers store a flag name and expiry; the row presentation supplies its faction.
    if colorMode == "faction" and not faction then
        if name == "Alliance Flag" then faction = "Alliance"
        elseif name == "Horde Flag" then faction = "Horde" end
    end
    local colorKey = BAR_COLORS[faction or ""] and faction or "neutral"

    local icon = (faction == "Alliance" and ALLIANCE_FLAG_TEX) or (faction == "Horde" and HORDE_FLAG_TEX) or defaultIcon
    if row.displayIcon ~= icon then
        row.icon:SetTexture(icon)
        if icon == defaultIcon then row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        else row.icon:SetTexCoord(0, 1, 0, 1) end
        row.displayIcon = icon
    end

    if row.displayName ~= name then
        row.labelFs:SetText(name)
        row.displayName = name
    end

    local timeStr = FormatTime(remaining)
    if row.displayTime ~= timeStr then
        row.timeFs:SetText(timeStr)
        row.displayTime = timeStr
    end
    local urgent = remaining <= 10
    if row.displayUrgent ~= urgent then
        if urgent then row.timeFs:SetTextColor(1, 0.45, 0.35)
        else row.timeFs:SetTextColor(1, 1, 1) end
        row.displayUrgent = urgent
    end

    row.fillExpiry = (not (AutoBG_Settings and AutoBG_Settings.TestAllTimers)) and (GetTime() + remaining) or nil
    if row.fillDuration ~= maxTime then
        row.bar:SetMinMaxValues(0, maxTime)
        row.fillDuration = maxTime
    end
    row.bar:SetValue(remaining)
    if row.displayColor ~= colorKey then
        local c = BAR_COLORS[colorKey]
        row.bar:SetStatusBarColor(c[1], c[2], c[3])
        row.displayColor = colorKey
    end

    local facText = faction and (" (" .. faction .. ")") or ""
    row.announceText = name .. facText .. ": " .. timeStr
    if not row:IsShown() then row:Show() end
end

local function RenderCountdownBars(frame, timerTable, isEnabled, isZone, maxTime, testData, colorMode)
    if not frame or not frame.rows then return end
    ApplyObjectiveAppearance(frame)
    local now       = GetTime()
    local isTestAll = AutoBG_Settings and AutoBG_Settings.TestAllTimers
    local maxRows   = #frame.rows
    local activeCount = 0

    if isEnabled and (isTestAll or isZone) then
        if isTestAll and testData then
            activeCount = math.min(#testData, maxRows)
            for i = 1, activeCount do
                local d   = testData[i]
                local row = frame.rows[i]
                ApplyTimerRowData(row, d.name, d.faction, d.remaining, maxTime, colorMode, frame.defaultIcon)
            end
        else
            local sortCount = 0
            for nodeName, data in pairs(timerTable) do
                local expireTime = (type(data) == "table" and data.expire) or data
                local faction    = (type(data) == "table" and data.faction) or nil
                local rowMax     = (type(data) == "table" and data.max) or maxTime
                local remaining  = expireTime - now
                if remaining > 0 then
                    sortCount = sortCount + 1
                    local item = activeSortBuffer[sortCount]
                    if not item then item = {}; activeSortBuffer[sortCount] = item end
                    item.name    = nodeName
                    item.expire  = expireTime
                    item.faction = faction
                    item.maxTime = rowMax
                else
                    timerTable[nodeName] = nil
                end
            end
            if sortCount > 1 then
                for i = 2, sortCount do
                    local key = activeSortBuffer[i]
                    local j = i - 1
                    while j >= 1 and activeSortBuffer[j].expire > key.expire do
                        activeSortBuffer[j + 1] = activeSortBuffer[j]
                        j = j - 1
                    end
                    activeSortBuffer[j + 1] = key
                end
            end
            local displayCount = 0
            local limit = math.min(sortCount, maxRows)
            for i = 1, limit do
                local item      = activeSortBuffer[i]
                local remaining = item.expire - now
                if remaining > 0 then
                    displayCount = displayCount + 1
                    local row = frame.rows[displayCount]
                    ApplyTimerRowData(row, item.name, item.faction, remaining, item.maxTime or maxTime, colorMode, frame.defaultIcon)
                    row.fillExpiry = item.expire
                end
            end
            activeCount = displayCount
        end
    else
        if not isTestAll then table.wipe(timerTable) end
    end

    for i = activeCount + 1, maxRows do
        frame.rows[i].fillExpiry = nil
        if frame.rows[i]:IsShown() then frame.rows[i]:Hide() end
    end
    if activeCount > 0 then
        local height = frame.headerHeight + activeCount * frame.rowHeight + (activeCount - 1) * BAR_ROW_GAP
        if frame.displayHeight ~= height then frame:SetHeight(height); frame.displayHeight = height end
        if not frame:IsShown() then frame:Show() end
    else
        if frame:IsShown() then frame:Hide() end
    end
end

-- =========================================================
-- Arathi Basin Mathematical Projection Engine
-- =========================================================
local AB_MAX_RESOURCES = 2000
local AB_RPS = {
    [0] = 0,
    [1] = 10 / 12,
    [2] = 10 / 9,
    [3] = 10 / 6,
    [4] = 10 / 3,
    [5] = 30,
}

local AB_TICK_INTERVAL = { [0] = 0, [1] = 12, [2] = 9, [3] = 6, [4] = 3, [5] = 1 }

local function ReadABWorldStateInfo()
    local aRes, hRes, aBases, hBases
    local n = (GetNumWorldStateUI and GetNumWorldStateUI()) or 0
    for i = 1, n do
        local uiType, state, text = GetWorldStateUIInfo(i)
        local str1 = (state and tostring(state)) or ""
        local str2 = (text and tostring(text)) or ""
        local itemScore, itemBases
        if str1 ~= "" then
            local _, _, r = string.find(str1, "(%d+)%s*/%s*2000")
            if r then itemScore = tonumber(r) end
            local _, _, b = string.find(str1, "Bases:%s*(%d+)")
            if b then itemBases = tonumber(b) end
        end
        if (not itemScore or not itemBases) and str2 ~= "" then
            if not itemScore then
                local _, _, r = string.find(str2, "(%d+)%s*/%s*2000")
                if r then itemScore = tonumber(r) end
            end
            if not itemBases then
                local _, _, b = string.find(str2, "Bases:%s*(%d+)")
                if b then itemBases = tonumber(b) end
            end
        end
        if itemScore then
            if not aRes then aRes = itemScore else hRes = itemScore end
        end
        if itemBases then
            if not aBases then aBases = itemBases else hBases = itemBases end
        end
    end
    return aRes, hRes, aBases or 0, hBases or 0
end

local observedARes, observedHRes, observedABases, observedHBases
local function GetABWorldStateInfo()
    if worldStateDirty then
        observedARes, observedHRes, observedABases, observedHBases = ReadABWorldStateInfo()
        worldStateDirty = false
    end
    return observedARes, observedHRes, observedABases, observedHBases
end

local pendingCapsBuffer, pendingCapsPool = {}, {}
local function CapTimeSort(x, y) return x.time < y.time end
local function GetABPendingCaps()
    table.wipe(pendingCapsBuffer)
    local now = GetTime()
    for node, data in pairs(timers.AB) do
        local expire = (type(data) == "table" and data.expire) or data
        local faction = (type(data) == "table" and data.faction) or nil
        if expire and expire > now and faction then
            local rem = expire - now
            local index = #pendingCapsBuffer + 1
            local cap = pendingCapsPool[index]
            if not cap then cap = {}; pendingCapsPool[index] = cap end
            cap.node, cap.time, cap.faction = node, rem, faction
            pendingCapsBuffer[index] = cap
        end
    end
    table.sort(pendingCapsBuffer, CapTimeSort)
    return pendingCapsBuffer
end

local function ProjectWithCaps(aRes, hRes, aBases, hBases, caps)
    local t = 0
    local a, h = aRes, hRes
    local ab, hb = aBases or 0, hBases or 0

    for idx = 1, #caps do
        local cap = caps[idx]
        local dt = cap.time - t
        if dt > 0 then
            local ar = AB_RPS[ab] or 0
            local hr = AB_RPS[hb] or 0
            local aPT = ar > 0 and (AB_MAX_RESOURCES - a) / ar or 999999
            local hPT = hr > 0 and (AB_MAX_RESOURCES - h) / hr or 999999
            if aPT <= dt or hPT <= dt then
                local hAtAWin = math.min(AB_MAX_RESOURCES, h + hr * aPT)
                local aAtHWin = math.min(AB_MAX_RESOURCES, a + ar * hPT)
                return t + aPT, t + hPT, aAtHWin, hAtAWin
            end
            a = a + ar * dt
            h = h + hr * dt
        end
        t = cap.time
        -- A contested node earns for nobody: the defender's count already
        -- dropped at the assault, and a neutral claim never had an owner, so
        -- completion only adds the capturer's base.
        -- UNVERIFIED: test in game that "Bases:" drops when a node is assaulted.
        if cap.faction == "Alliance" then
            ab = math.min(5 - hb, ab + 1)
        else
            hb = math.min(5 - ab, hb + 1)
        end
    end

    local ar = AB_RPS[ab] or 0
    local hr = AB_RPS[hb] or 0
    local aPT = ar > 0 and (AB_MAX_RESOURCES - a) / ar or 999999
    local hPT = hr > 0 and (AB_MAX_RESOURCES - h) / hr or 999999
    local hAtAWin = math.min(AB_MAX_RESOURCES, h + hr * aPT)
    local aAtHWin = math.min(AB_MAX_RESOURCES, a + ar * hPT)
    return t + aPT, t + hPT, aAtHWin, hAtAWin
end

-- The fewest bases that win outright while the enemy holds the rest. A side
-- already winning is told what it must hold; anyone else what it needs.
local function BasesToWin(aRes, hRes, faction, winning)
    local myRes, theirRes
    if faction == "Alliance" then
        myRes = aRes; theirRes = hRes
    else
        myRes = hRes; theirRes = aRes
    end
    local verb = winning and "Hold" or "Need"
    for b = 1, 5 do
        local myRate = AB_RPS[b] or 0
        local theirRate = AB_RPS[5 - b] or 0
        local myTime = myRate > 0 and (AB_MAX_RESOURCES - myRes) / myRate or 999999
        local theirTime = theirRate > 0 and (AB_MAX_RESOURCES - theirRes) / theirRate or 999999
        if myTime < theirTime then
            return string.format("%s %d %s", verb, b, (b == 1) and "Base" or "Bases")
        end
    end
    return verb .. " 5 Bases"
end

local function CalculateABProjection(aRes, hRes, aBases, hBases)
    if not aRes or not hRes then return nil end
    local aRate = AB_RPS[aBases] or 0
    local hRate = AB_RPS[hBases] or 0

    local caps = GetABPendingCaps()
    local aTime, hTime, simAAtHWin, simHAtAWin
    if #caps > 0 then
        aTime, hTime, simAAtHWin, simHAtAWin = ProjectWithCaps(aRes, hRes, aBases, hBases, caps)
    else
        aTime = (aRate > 0) and (AB_MAX_RESOURCES - aRes) / aRate or 999999
        hTime = (hRate > 0) and (AB_MAX_RESOURCES - hRes) / hRate or 999999
    end

    -- Finishes this close are decided by tick timing, so call them a tie
    -- rather than repeating an earlier verdict.
    local DEAD_HEAT = 12
    local tie = aTime < 999999 and hTime < 999999 and math.abs(aTime - hTime) <= DEAD_HEAT
    local winner = (aTime <= hTime) and "Alliance" or "Horde"

    local aFinal, hFinal, eta
    if winner == "Alliance" then
        aFinal = AB_MAX_RESOURCES
        local hScore = simHAtAWin or (hRes + hRate * aTime)
        hFinal = math.min(AB_MAX_RESOURCES, math.floor(hScore / 10) * 10)
        eta = aTime
    else
        hFinal = AB_MAX_RESOURCES
        local aScore = simAAtHWin or (aRes + aRate * hTime)
        aFinal = math.min(AB_MAX_RESOURCES, math.floor(aScore / 10) * 10)
        eta = hTime
    end

    local myFaction = UnitFactionGroup("player") or "Alliance"
    local playerWins = not tie and winner == myFaction
    local etaStr, announceStr
    local verdict = tie and "Tie" or (playerWins and "Win" or "Loss")
    local etaColor = tie and "|cFFFFD100" or (playerWins and "|cFF00FF00" or "|cFFFF5555")

    if eta >= 999999 then
        etaStr = "--:--"
        etaColor = "|cFFFFFFFF"
        announceStr = nil
    else
        local totSec = math.floor(math.max(0, eta) + 0.05)
        local mins = math.floor(totSec / 60)
        local secs = totSec - mins * 60
        etaStr = string.format("%s %02d:%02d", verdict, mins, secs)
        announceStr = tie and string.format("Too close to call at %02d:%02d", mins, secs)
            or string.format("%s in %02d:%02d", verdict, mins, secs)
    end

    local basesNeeded = BasesToWin(aRes, hRes, myFaction, playerWins)

    return aFinal, hFinal, etaStr, etaColor, basesNeeded, announceStr
end

-- Observed scores and interpolated estimates have separate owners.
local lastR1Status, lastR1Score = "", ""
local lastR2Bases, lastR2Score = "", ""
local lastRecordedARes, lastRecordedHRes = nil, nil
local interpolatedARes, interpolatedHRes = nil, nil
local lastRecordedABases, lastRecordedHBases = nil, nil
local lastATickTime, lastHTickTime = nil, nil

local function UpdateABProjection(isTestAll, isAB)
    if not AutoBG_Settings then
        if ABProjectionFrame:IsShown() then ABProjectionFrame:Hide() end
        return
    end

    if isTestAll then
        local r1Stat = "|cFF00FF00Win 03:45|r"
        local r1Sc   = "A 1450"
        local r2Base = "|cFFFFD100Hold 3 Bases|r"
        local r2Sc   = "H 1280"

        if lastR1Status ~= r1Stat then ABProjectionFrame.r1Status:SetText(r1Stat); lastR1Status = r1Stat end
        if lastR1Score ~= r1Sc then ABProjectionFrame.r1Score:SetText(r1Sc); lastR1Score = r1Sc end
        if lastR2Bases ~= r2Base then ABProjectionFrame.r2Bases:SetText(r2Base); lastR2Bases = r2Base end
        if lastR2Score ~= r2Sc then ABProjectionFrame.r2Score:SetText(r2Sc); lastR2Score = r2Sc end
        ABProjectionFrame.announceText = "Win in 03:45"

        if not ABProjectionFrame:IsShown() then
            AutoBG_LoadTimerPositions()
            ABProjectionFrame:Show()
        end
        return
    end

    if not isAB then
        if ABProjectionFrame:IsShown() then ABProjectionFrame:Hide() end
        lastR1Status, lastR1Score = "", ""
        lastR2Bases, lastR2Score = "", ""
        lastRecordedARes, lastRecordedHRes = nil, nil
        interpolatedARes, interpolatedHRes = nil, nil
        lastRecordedABases, lastRecordedHBases = nil, nil
        lastATickTime, lastHTickTime = nil, nil
        ABProjectionFrame.announceText = nil
        return
    end

    local aRes, hRes, aBases, hBases = GetABWorldStateInfo()
    if not aRes or not hRes then
        if ABProjectionFrame:IsShown() then ABProjectionFrame:Hide() end
        ABProjectionFrame.announceText = nil
        return
    end

    local now = GetTime()

    if lastRecordedARes == nil or aRes ~= lastRecordedARes then
        lastRecordedARes = aRes
        interpolatedARes = aRes
        lastATickTime = now
    elseif aBases ~= lastRecordedABases then
        local oldRate = AB_RPS[lastRecordedABases or 0] or 0
        local elapsed = lastATickTime and math.max(0, now - lastATickTime) or 0
        interpolatedARes = math.min(AB_MAX_RESOURCES, interpolatedARes + oldRate * math.min(AB_TICK_INTERVAL[lastRecordedABases or 0] or 0, elapsed))
        lastATickTime = now
    end
    lastRecordedABases = aBases

    if lastRecordedHRes == nil or hRes ~= lastRecordedHRes then
        lastRecordedHRes = hRes
        interpolatedHRes = hRes
        lastHTickTime = now
    elseif hBases ~= lastRecordedHBases then
        local oldRate = AB_RPS[lastRecordedHBases or 0] or 0
        local elapsed = lastHTickTime and math.max(0, now - lastHTickTime) or 0
        interpolatedHRes = math.min(AB_MAX_RESOURCES, interpolatedHRes + oldRate * math.min(AB_TICK_INTERVAL[lastRecordedHBases or 0] or 0, elapsed))
        lastHTickTime = now
    end
    lastRecordedHBases = hBases

    local aRate = AB_RPS[aBases or 0] or 0
    local hRate = AB_RPS[hBases or 0] or 0

    local elapsedA = lastATickTime and math.max(0, now - lastATickTime) or 0
    local elapsedH = lastHTickTime and math.max(0, now - lastHTickTime) or 0

    local maxTickA = AB_TICK_INTERVAL[aBases] or 0
    local maxTickH = AB_TICK_INTERVAL[hBases] or 0

    local curARes = math.min(AB_MAX_RESOURCES, interpolatedARes + aRate * (maxTickA > 0 and math.min(maxTickA, elapsedA) or 0))
    local curHRes = math.min(AB_MAX_RESOURCES, interpolatedHRes + hRate * (maxTickH > 0 and math.min(maxTickH, elapsedH) or 0))

    local aFinal, hFinal, etaStr, etaColor, basesNeeded, announceStr = CalculateABProjection(curARes, curHRes, aBases, hBases)
    if not aFinal then
        if ABProjectionFrame:IsShown() then ABProjectionFrame:Hide() end
        ABProjectionFrame.announceText = nil
        return
    end

    local r1Stat = (etaColor or "|cFFFFFFFF") .. (etaStr or "") .. "|r"
    local r1Sc   = "A " .. aFinal
    local r2Base = "|cFFFFD100" .. (basesNeeded or "") .. "|r"
    local r2Sc   = "H " .. hFinal

    if lastR1Status ~= r1Stat then ABProjectionFrame.r1Status:SetText(r1Stat); lastR1Status = r1Stat end
    if lastR1Score ~= r1Sc then ABProjectionFrame.r1Score:SetText(r1Sc); lastR1Score = r1Sc end
    if lastR2Bases ~= r2Base then ABProjectionFrame.r2Bases:SetText(r2Base); lastR2Bases = r2Base end
    if lastR2Score ~= r2Sc then ABProjectionFrame.r2Score:SetText(r2Sc); lastR2Score = r2Sc end
    ABProjectionFrame.announceText = announceStr

    if not ABProjectionFrame:IsShown() then
        AutoBG_LoadTimerPositions()
        ABProjectionFrame:Show()
    end
end

-- =========================================================
-- Main 10 Hz Update Ticker
-- =========================================================
local function UpdateAllTimers()
    if not AutoBG_Settings then return end

    local now         = GetTime()
    local isTestAll   = AutoBG_Settings.TestAllTimers

    -- 0. Match Start Timer (Pre-game gate countdown)
    RenderCountdownBars(StartTimerFrame, timers.Global, AutoBG_Settings.StartTimer ~= false, inPVP, 120, START_TEST_DATA, "time")

    -- 1. AB Nodes: faction bars when Faction Node Colors is on (60s cap)
    RenderCountdownBars(NodeBarFrame, timers.AB, AutoBG_Settings.ABTimers, isAB, 60, AB_TEST_DATA, "time")

    -- 1b. AB Projected Score Overlay (Aligned 2-row dual-column HUD)
    UpdateABProjection(isTestAll, isAB)

    -- 2. AV Nodes: faction bars when Faction Node Colors is on (300s cap)
    RenderCountdownBars(AVNodeFrame, timers.AV, AutoBG_Settings.AVTimers, isAV, 300, AV_TEST_DATA, "time")

    -- 3. WSG Flags: fixed faction colors — Alliance=blue, Horde=red (23s cap)
    RenderCountdownBars(WSGFlagFrame, timers.WSG, AutoBG_Settings.WSGTimers, isWSG, 23, WSG_TEST_DATA, "faction")

    -- 4. Respawn Timer (Spirit Healer 30s Wave)
    if inPVP and AutoBG_Settings.RessTimer then
        local healerTime = (GetAreaSpiritHealerTime and GetAreaSpiritHealerTime()) or 0
        if healerTime > 0 then SyncSpiritWave(now - (30 - healerTime)) end
        if spiritHealerSyncTime == 0 then spiritHealerSyncTime = now end
        -- Learn who is a ghost once a second; UNIT_HEALTH times their revival.
        if now >= nextGhostScan then
            nextGhostScan = now + 1
            for i = 1, GetNumRaidMembers() do
                local unit = RAID_UNITS[i]
                if UnitIsGhost(unit) then raidGhosts[unit] = true end
            end
        end

        local elapsed      = now - spiritHealerSyncTime
        local remaining    = 30 - (elapsed % 30)
        local numRemaining = math.ceil(remaining)
        if numRemaining <= 0 then numRemaining = 30 end

        local pct = numRemaining / 30
        local r = (pct > 0.33 and 0.10) or (pct > 0.17 and 1.00) or 1.00
        local g = (pct > 0.33 and 0.90) or (pct > 0.17 and 0.85) or 0.15
        local b = (pct > 0.33 and 0.20) or 0.00
        local colorCode = (pct > 0.33 and "|cFF00FF00") or (pct > 0.17 and "|cFFFFFF00") or (pct > 0.07 and "|cFFFF8000") or "|cFFFF2020"

        RespawnFrame.bar:SetValue(remaining)
        if RespawnFrame.displayR ~= r or RespawnFrame.displayG ~= g or RespawnFrame.displayB ~= b then
            RespawnFrame.bar:SetStatusBarColor(r, g, b)
            RespawnFrame.displayR, RespawnFrame.displayG, RespawnFrame.displayB = r, g, b
        end
        local timeText = colorCode .. (spiritHealerSynced and "" or "~") .. FormatTime(numRemaining) .. "|r"
        if RespawnFrame.displayText ~= timeText then
            RespawnFrame.timeText:SetText(timeText)
            RespawnFrame.displayText = timeText
        end
        RespawnFrame.announceText = "Ress: " .. FormatTime(numRemaining)
        if not RespawnFrame:IsShown() then RespawnFrame:Show() end
    elseif isTestAll and AutoBG_Settings.RessTimer then
        if RespawnFrame.displayText ~= "|cFF00FF000:24|r" then
            RespawnFrame.timeText:SetText("|cFF00FF000:24|r")
            RespawnFrame.displayText = "|cFF00FF000:24|r"
        end
        RespawnFrame.bar:SetValue(24)
        RespawnFrame.bar:SetStatusBarColor(0.1, 0.9, 0.2)
        RespawnFrame.displayR, RespawnFrame.displayG, RespawnFrame.displayB = 0.1, 0.9, 0.2
        RespawnFrame.announceText = "Ress: 0:24"
        if not RespawnFrame:IsShown() then RespawnFrame:Show() end
    else
        if RespawnFrame:IsShown() then RespawnFrame:Hide() end
    end

    -- 5. Queue Timers (Original Blizzard format numbers + Visual Icons)
    local queueSecond = math.floor(now)
    if lastQueueSecond ~= queueSecond or lastQueuePreview ~= isTestAll or lastQueueEnabled ~= AutoBG_Settings.QueueTimers then
    lastQueueSecond, lastQueuePreview, lastQueueEnabled = queueSecond, isTestAll, AutoBG_Settings.QueueTimers
    local qIndex = 1
    if AutoBG_Settings.QueueTimers then
        if isTestAll then
            local r1 = QueueFrame:GetOrCreateRow(1)
            if AutoBG_GetBGIcon then
                r1.icon:SetTexture(AutoBG_GetBGIcon("wsg"))
                r1.icon:Show()
                r1.fs:SetPoint("LEFT", r1.icon, "RIGHT", 4, 0)
            else
                r1.icon:Hide()
                r1.fs:SetPoint("CENTER", r1, "CENTER", 0, 0)
            end
            r1.fs:SetText("WSG: 1:15")
            r1.announceText = "WSG Queue: 1:15"
            r1.estText = nil
            r1:Show()

            local r2 = QueueFrame:GetOrCreateRow(2)
            if AutoBG_GetBGIcon then
                r2.icon:SetTexture(AutoBG_GetBGIcon("ab"))
                r2.icon:Show()
                r2.fs:SetPoint("LEFT", r2.icon, "RIGHT", 4, 0)
            else
                r2.icon:Hide()
                r2.fs:SetPoint("CENTER", r2, "CENTER", 0, 0)
            end
            r2.fs:SetText("AB: 4:32")
            r2.announceText = "AB Queue: 4:32"
            r2.estText = nil
            r2:Show()
            qIndex = 3
        else
            for queueIndex = 1, queuedCount do
                local queue = queuedBattlegrounds[queueIndex]
                local i, mapName = queue.id, queue.map
                    local waitTime = (GetBattlefieldTimeWaited and GetBattlefieldTimeWaited(i)) or 0
                    local estTime  = (GetBattlefieldEstimatedWaitTime and GetBattlefieldEstimatedWaitTime(i)) or 0
                    local sec      = math.floor(waitTime / 1000)
                    local row      = QueueFrame:GetOrCreateRow(qIndex)
                    local abbrev   = (mapName == "Warsong Gulch" and "WSG") or (mapName == "Arathi Basin" and "AB") or
                                     (mapName == "Alterac Valley" and "AV")  or (mapName == "Thorn Gorge"  and "TG") or mapName or "BG"
                    local bgIcon   = (AutoBG_GetBGIcon and AutoBG_GetBGIcon(mapName))
                    if row.displayIcon ~= (bgIcon or false) then
                        row.displayIcon = bgIcon or false
                    if bgIcon then
                        row.icon:SetTexture(bgIcon)
                        row.icon:Show()
                        row.fs:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
                    else
                        row.icon:Hide()
                        row.fs:SetPoint("CENTER", row, "CENTER", 0, 0)
                    end
                    end
                    local displayText = abbrev .. ": " .. FormatQueueTime(sec)
                    if row.displayText ~= displayText then
                        row.fs:SetText(displayText)
                        row.displayText = displayText
                    end
                    row.announceText = abbrev .. " Queue: " .. FormatQueueTime(sec)
                    if estTime > 0 then
                        row.estText = "Estimated: " .. FormatQueueTime(math.floor(estTime / 1000))
                    else
                        row.estText = nil
                    end
                    if not row:IsShown() then row:Show() end
                    qIndex = qIndex + 1
            end
        end
    end
    QueueFrame:UpdateSize(qIndex)
    end
end

SyncUpdateTicker = function()
    local s = AutoBG_Settings
    -- Test mode always shows the AB projection, so it always needs the ticker.
    local needed = s and (s.TestAllTimers or
        (s.QueueTimers and queuedCount > 0) or
        (inPVP and (s.RessTimer or
         (s.StartTimer ~= false and next(timers.Global)) or
         isAB or -- the projection is always on
         (isAV and s.AVTimers and next(timers.AV)) or
         (isWSG and s.WSGTimers and next(timers.WSG)))))
    if needed and not updateTicker then
        local ticker
        ticker = C_Timer.NewTicker(0.1, function()
            if updateTicker ~= ticker then return end
            UpdateAllTimers()
            SyncUpdateTicker()
        end)
        updateTicker = ticker
    elseif not needed and updateTicker then
        updateTicker:Cancel()
        updateTicker = nil
    end
end

function AutoBG_Timers_UpdateVisibility()
    lastQueueSecond = nil
    UpdateAllTimers()
    SyncUpdateTicker()
end

-- =========================================================
-- Static Node Tables & Chat Message Parsers
-- =========================================================
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
    if     string.find(lower, "mine")   then return "Gold Mine"
    elseif string.find(lower, "mill")   then return "Lumber Mill"
    elseif string.find(lower, "smith")  then return "Blacksmith"
    elseif string.find(lower, "stable") then return "Stables" end
    return nil
end

local function GetFactionFromMessage(msg, ev)
    if not msg then return nil end
    local lower = string.lower(msg)
    if string.find(lower, "horde")    or ev == "CHAT_MSG_BG_SYSTEM_HORDE"    then return "Horde"    end
    if string.find(lower, "alliance") or ev == "CHAT_MSG_BG_SYSTEM_ALLIANCE" then return "Alliance" end

    local _, _, player = string.find(msg, "^([^%s!]+)%s+[ha]s?%s*claims?")
    if not player then _, _, player = string.find(msg, "^([^%s!]+)%s+assaulted") end

    if player then
        local myFaction  = UnitFactionGroup("player")
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
    if not AutoBG_Settings or not msg or not inPVP then return end
    local lower = string.lower(msg)
    local faction = GetFactionFromMessage(msg, ev)

    -- The flag watch learns from the same messages where flags stand and who holds them.
    if AutoBG_FlagWatch and (isAB or isAV) then
        local node = MatchNodeName(msg, isAB and AB_NODES or AV_NODES)
        if node then AutoBG_FlagWatch:OnNodeMessage(node, msg, faction) end
    end

    -- 1. AB Nodes: 60s on OctoWoW (confirmed in play, 2026-10-21)
    if AutoBG_Settings.ABTimers and isAB then
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
    if AutoBG_Settings.AVTimers and isAV then
        local node = MatchNodeName(msg, AV_NODES)
        if node then
            -- 5 min on OctoWoW (confirmed in play, 2026-10-21)
            if string.find(lower, "claims") or string.find(lower, "assaulted") or string.find(lower, "under attack") then
                timers.AV[node] = { expire = GetTime() + 300, faction = faction }
            elseif string.find(lower, "taken") or string.find(lower, "defended") or string.find(lower, "destroyed") or string.find(lower, "captured") then
                timers.AV[node] = nil
            end
        end
    end

    -- 3. Gate Pre-Match Announcements
    local _, _, m = string.find(lower, "begins? in (%d+)%s*min")
    if not m then _, _, m = string.find(lower, "begin in (%d+)%s*min") end
    if not m then _, _, m = string.find(lower, "starts? in (%d+)%s*min") end
    if not m then _, _, m = string.find(lower, "opens? in (%d+)%s*min") end
    if not m and string.find(lower, "two minute") then m = "2" end
    if not m and string.find(lower, "one minute") then m = "1" end

    if m then
        local sec = tonumber(m) * 60
        timers.Global["Match Starts"] = { expire = GetTime() + sec, max = sec }
    else
        local _, _, s = string.find(lower, "begins? in (%d+)%s*sec")
        if not s then _, _, s = string.find(lower, "begin in (%d+)%s*sec") end
        if not s then _, _, s = string.find(lower, "starts? in (%d+)%s*sec") end
        if not s then _, _, s = string.find(lower, "opens? in (%d+)%s*sec") end
        if not s and string.find(lower, "30 second") then s = "30" end
        if not s and string.find(lower, "15 second") then s = "15" end

        if s then
            local sec = tonumber(s)
            timers.Global["Match Starts"] = { expire = GetTime() + sec, max = sec }
        elseif string.find(lower, "begun") or string.find(lower, "let the battle begin") or string.find(lower, "gates? (.-)open") or string.find(lower, "gates have opened") then
            timers.Global["Match Starts"] = nil
        end
    end

    -- 4. WSG Flag Respawns: 23s on OctoWoW (confirmed in play, 2026-10-21)
    if AutoBG_Settings.WSGTimers and isWSG then
        if     string.find(lower, "captured the alliance flag") then timers.WSG["Alliance Flag"] = GetTime() + 23
        elseif string.find(lower, "captured the horde flag")    then timers.WSG["Horde Flag"]    = GetTime() + 23
        end
    end
end

-- =========================================================
-- Event Frame
-- =========================================================
local EventFrame = CreateFrame("Frame", "AutoBG_TimersEventFrame")
EventFrame:RegisterEvent("CHAT_MSG_BG_SYSTEM_NEUTRAL")
EventFrame:RegisterEvent("CHAT_MSG_BG_SYSTEM_ALLIANCE")
EventFrame:RegisterEvent("CHAT_MSG_BG_SYSTEM_HORDE")
EventFrame:RegisterEvent("CHAT_MSG_SYSTEM")
EventFrame:RegisterEvent("CHAT_MSG_MONSTER_YELL")
EventFrame:RegisterEvent("CHAT_MSG_RAID_BOSS_EMOTE")
EventFrame:RegisterEvent("CHAT_MSG_MONSTER_EMOTE")
EventFrame:RegisterEvent("ADDON_LOADED")
EventFrame:RegisterEvent("UPDATE_BATTLEFIELD_STATUS")
EventFrame:RegisterEvent("UPDATE_WORLD_STATES")
EventFrame:RegisterEvent("PLAYER_UNGHOST")
EventFrame:RegisterEvent("UNIT_HEALTH")
EventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
EventFrame:RegisterEvent("ZONE_CHANGED")
EventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")

EventFrame:SetScript("OnEvent", function(arg1_param, arg2_param, arg3_param)
    local ev  = (type(arg1_param) == "string" and arg1_param) or arg2_param or event
    local msg = (type(arg1_param) == "string" and (arg2_param or arg1)) or arg3_param or arg1
    if ev == "UNIT_HEALTH" then
        if raidGhosts[msg] and not UnitIsDeadOrGhost(msg) then
            raidGhosts[msg] = nil
            if inPVP then SyncSpiritWave(GetTime()) end
        end
        return
    end
    if ev == "ADDON_LOADED" then
        if msg ~= "AutoBG" then return end
        RefreshQueuedBattlegrounds()
    elseif ev == "UPDATE_BATTLEFIELD_STATUS" then
        RefreshQueuedBattlegrounds()
    elseif ev == "UPDATE_WORLD_STATES" then
        worldStateDirty = true
    end
    if ev == "PLAYER_ENTERING_WORLD" or ev == "ZONE_CHANGED" or ev == "ZONE_CHANGED_NEW_AREA" then
        UpdateZoneCache()
        worldStateDirty = true
        if not isAB then
            table.wipe(timers.AB)
            if NodeBarFrame and NodeBarFrame:IsShown() then NodeBarFrame:Hide() end
            if ABProjectionFrame and ABProjectionFrame:IsShown() then ABProjectionFrame:Hide() end
            lastRecordedARes, lastRecordedHRes = nil, nil
            interpolatedARes, interpolatedHRes = nil, nil
            lastRecordedABases, lastRecordedHBases = nil, nil
            lastATickTime, lastHTickTime = nil, nil
        end
        if not isAV then
            table.wipe(timers.AV)
            if AVNodeFrame and AVNodeFrame:IsShown() then AVNodeFrame:Hide() end
        end
        if not isWSG then
            table.wipe(timers.WSG)
            if WSGFlagFrame and WSGFlagFrame:IsShown() then WSGFlagFrame:Hide() end
        end
        if not inPVP then
            if RespawnFrame:IsShown() then RespawnFrame:Hide() end
            if StartTimerFrame and StartTimerFrame:IsShown() then StartTimerFrame:Hide() end
            table.wipe(timers.Global)
        end
        if ev == "PLAYER_ENTERING_WORLD" then
            RefreshQueuedBattlegrounds()
            AutoBG_LoadTimerPositions()
            table.wipe(timers.Global)
            if StartTimerFrame and StartTimerFrame:IsShown() then StartTimerFrame:Hide() end
            lastR1Status, lastR1Score = "", ""
            lastR2Bases, lastR2Score = "", ""
            lastRecordedARes, lastRecordedHRes = nil, nil
            interpolatedARes, interpolatedHRes = nil, nil
            lastRecordedABases, lastRecordedHBases = nil, nil
            lastATickTime, lastHTickTime = nil, nil
            spiritHealerSyncTime = GetTime()
            spiritHealerSynced   = false
            table.wipe(raidGhosts)
        end
    elseif ev == "PLAYER_UNGHOST" then
        -- Coming back from a ghost in a battleground is the spirit healer's wave.
        -- (PLAYER_ALIVE also fires on release, so it cannot time a wave.)
        if inPVP then SyncSpiritWave(GetTime()) end
    elseif ev ~= "ADDON_LOADED" and ev ~= "UPDATE_BATTLEFIELD_STATUS" and ev ~= "UPDATE_WORLD_STATES" then
        if not inPVP then return end
        ParseCombatMessage(msg or arg1, ev)
    end
    AutoBG_Timers_UpdateVisibility()
end)
