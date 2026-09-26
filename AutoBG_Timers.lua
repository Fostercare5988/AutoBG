-- AutoBG Timers & Objective Countdown Engine (Zero-Bloat Consolidated Architecture)
-- Author & Maintainer: Fostercare5988
-- Built natively for ClassicAPI v1.15.14+, SuperWoW 2.2+, UnitXP SP3

-- Strict Engine Dependency Guard (Mandatory ClassicAPI v1.15.14+ & SuperWoW v2.2+)
local MIN_CLASSIC_API = 11514

if not (CLASSIC_API_VERSION and SUPERWOW_VERSION) or
   (type(CLASSIC_API_VERSION) == "number" and CLASSIC_API_VERSION < MIN_CLASSIC_API) then
    return
end

local timers = { AB = {}, AV = {}, WSG = {}, Global = {} }
local spiritHealerSyncTime = 0
local spiritHealerSynced = false

-- Cached Zone & Instance State
local cachedZone = ""
local isAB, isAV, isWSG, inPVP = false, false, false, false

local function UpdateZoneCache()
    cachedZone = string.lower((GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()) or "")
    isAB  = (string.find(cachedZone, "arathi")  ~= nil)
    isAV  = (string.find(cachedZone, "alterac") ~= nil)
    isWSG = (string.find(cachedZone, "warsong") ~= nil)
    local inInstance, instanceType = IsInInstance()
    inPVP = (inInstance and instanceType == "pvp")
end
UpdateZoneCache()

-- Pre-allocated static sort buffer (Section 10 - Bounded Array Rule)
local activeSortBuffer = {}
for i = 1, 30 do activeSortBuffer[i] = { name = "", expire = 0, faction = nil } end

-- Pre-allocated static Unit ID array (Part D2)
local RAID_UNITS = {}
for i = 1, 40 do RAID_UNITS[i] = "raid" .. i end

local function SendTimerAnnouncement(text)
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

local BAR_WIDTH    = 280
local BAR_ROW_H    = 31
local BAR_ROW_GAP  = 3
local BAR_HEADER_H = 24

local function CreateBarTimerFrame(name, titleText, titleR, titleG, titleB, xOffset, yOffset, maxRows, compact)
    local width = compact and 260 or BAR_WIDTH
    local rowHeight = compact and 24 or BAR_ROW_H
    local headerHeight = compact and 19 or BAR_HEADER_H
    local rowFont = FONT
    local fontFlags = compact and "" or "OUTLINE"
    local frame = CreateFrame("Frame", name, UIParent)
    frame:SetWidth(width)
    frame:SetHeight(headerHeight)
    frame.rowHeight = rowHeight
    frame.headerHeight = headerHeight
    frame:SetPoint("TOP", UIParent, "TOP", xOffset, yOffset)
    frame:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background" })
    frame:SetBackdropColor(0.10, 0.14, 0.19, compact and 0 or 0.96)
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

    local headerBg = frame:CreateTexture(nil, "BACKGROUND")
    headerBg:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    headerBg:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
    headerBg:SetHeight(headerHeight - 1)
    headerBg:SetTexture(0.16, 0.21, 0.28, compact and 0 or 0.96)

    local headerRule = frame:CreateTexture(nil, "ARTWORK")
    headerRule:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -headerHeight)
    headerRule:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -headerHeight)
    headerRule:SetHeight(1)
    headerRule:SetTexture(titleR, titleG, titleB, compact and 0 or 0.70)

    local titleFs = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    titleFs:SetFont(rowFont, compact and 11 or 13, fontFlags)
    titleFs:SetShadowColor(0, 0, 0, 0.85)
    titleFs:SetShadowOffset(1, -1)
    titleFs:SetPoint("LEFT", frame, "TOPLEFT", compact and 5 or 9, -headerHeight / 2)
    titleFs:SetText(titleText)
    titleFs:SetTextColor(0.78, 0.77, 0.72)
    frame.titleFs = titleFs

    local dragHint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dragHint:SetFont(FONT, 8, "OUTLINE")
    dragHint:SetPoint("RIGHT", frame, "TOPRIGHT", -9, -12)
    dragHint:SetText(compact and "" or "DRAG")
    dragHint:SetTextColor(0.57, 0.65, 0.74)

    frame.rows = {}
    for i = 1, maxRows do
        local row = CreateFrame("Button", name .. "Row" .. i, frame)
        row:SetWidth(width - 10)
        row:SetHeight(rowHeight)
        row.compact = compact
        if i == 1 then
            row:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -headerHeight - 3)
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
        local rowBg = row:CreateTexture(nil, "BACKGROUND")
        rowBg:SetAllPoints(row)
        rowBg:SetTexture(0.14, 0.18, 0.24, 0.96)
        if compact then rowBg:SetTexture(0.08, 0.09, 0.10, 0.90) end
        row.rowBg = rowBg

        -- A single hairline separates rows without tooltip-style chrome.
        local bBottom = row:CreateTexture(nil, "OVERLAY")
        bBottom:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
        bBottom:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
        bBottom:SetHeight(1)
        bBottom:SetTexture(0.23, 0.29, 0.36, compact and 0 or 0.65)

        local hover = row:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints(row)
        hover:SetTexture(0.30, 0.45, 0.56, 0.14)

        -- Full-height progress fill; labels live on the bar above its fill texture.
        local bar = CreateFrame("StatusBar", name .. "Row" .. i .. "Bar", row)
        bar:SetPoint("TOPLEFT", row, "TOPLEFT", 1, -1)
        bar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -1, 1)
        bar:SetStatusBarTexture(BAR_TEXTURE)
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(1)
        bar:SetStatusBarColor(0.1, 0.85, 0.1)
        bar:EnableMouse(false)
        row.bar = bar

        local barBg = row:CreateTexture(nil, "BORDER")
        barBg:SetAllPoints(bar)
        barBg:SetTexture(BAR_TEXTURE)
        barBg:SetVertexColor(0.20, 0.24, 0.29, 0.85)
        if compact then barBg:SetVertexColor(0.12, 0.13, 0.14, 0.92) end
        row.barBg = barBg

        -- Faction icon and color rail remain visible as the progress track empties.
        local factionRail = bar:CreateTexture(nil, "OVERLAY")
        factionRail:SetPoint("TOPLEFT", row, "TOPLEFT", 0, compact and -1 or -3)
        factionRail:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, compact and 1 or 6)
        factionRail:SetWidth(compact and 2 or 3)
        factionRail:SetTexture(0.45, 0.50, 0.55)
        row.factionRail = factionRail

        local flagIcon = bar:CreateTexture(nil, "OVERLAY")
        flagIcon:SetWidth(14)
        flagIcon:SetHeight(14)
        flagIcon:SetPoint("LEFT", row, "LEFT", 8, 0)
        flagIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        flagIcon:Hide()
        row.flagIcon = flagIcon

        local timeFs = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        timeFs:SetFont(rowFont, compact and 12 or 15, fontFlags)
        timeFs:SetShadowColor(0, 0, 0, 0.8)
        timeFs:SetShadowOffset(1, -1)
        timeFs:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        timeFs:SetJustifyH("RIGHT")
        timeFs:SetTextColor(1, 1, 1, 1)
        row.timeFs = timeFs

        local labelFs = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        labelFs:SetFont(rowFont, 13, fontFlags)
        labelFs:SetShadowColor(0, 0, 0, 0.8)
        labelFs:SetShadowOffset(1, -1)
        labelFs:SetPoint("LEFT", row, "LEFT", 48, 0)
        labelFs:SetPoint("RIGHT", row, "RIGHT", -48, 0)
        labelFs:SetJustifyH("CENTER")
        labelFs:SetTextColor(1, 1, 1, 1)
        row.labelFs = labelFs
        row.lastFaction = "unset"

        row:Hide()
        frame.rows[i] = row
    end

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
        for i = index, count do self.activeRows[i]:Hide() end

        for i = 1, index - 1 do
            local w = self.activeRows[i].fs:GetStringWidth() + 38
            if w > maxWidth then maxWidth = w end
        end

        if index > 1 then
            self:SetWidth(math.max(minWidth or 130, maxWidth))
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

-- =========================================================
-- Frame Instantiation
-- =========================================================
local QueueFrame   = CreateDraggableTimerFrame("AutoBG_QueueFrame", "BG Queues", -220, -100, 130)
local RespawnFrame = CreateRespawnFrame("AutoBG_RespawnFrame", 0, -100)
local NodeBarFrame = CreateBarTimerFrame("AutoBG_NodeFrame",    "AB Nodes",  0.90, 0.20, 0.20,  220, -100, 5, true)
local AVNodeFrame  = CreateBarTimerFrame("AutoBG_AVNodeFrame",  "AV Nodes",  0.75, 0.75, 0.75,  220, -150, 8, true)
local WSGFlagFrame = CreateBarTimerFrame("AutoBG_WSGFlagFrame", "WSG Flags", 0.70, 0.40, 1.00, -110, -150, 2)

-- =========================================================
-- Arathi Basin Score Projection Frame (Sleek 2-Row Dual-Column Layout)
-- =========================================================
local AB_PROJ_WIDTH = 156
local AB_PROJ_HEIGHT = 38

local function CreateABProjectionFrame(name)
    local frame = CreateFrame("Button", name, UIParent)
    frame:SetWidth(AB_PROJ_WIDTH)
    frame:SetHeight(AB_PROJ_HEIGHT)
    frame:SetFrameStrata("HIGH")
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
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
    frame:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetText("Arathi Basin Score Projection", 1, 0.82, 0)
        GameTooltip:AddLine("Live score forecast based on base capture rates and impending flips.", 0.9, 0.9, 0.9, 1)
        GameTooltip:AddLine("Row 1: Projected Alliance Score & Win/Loss ETA", 0.4, 0.7, 1.0)
        GameTooltip:AddLine("Row 2: Projected Horde Score & Bases Needed to Win", 1.0, 0.4, 0.4)
        GameTooltip:AddLine("|cFF00FF00Left-drag:|r Reposition HUD overlay", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Row 1: Alliance Row (y = +8 from center)
    local r1Status = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r1Status:SetPoint("LEFT", frame, "LEFT", 6, 8)
    r1Status:SetPoint("RIGHT", frame, "RIGHT", -52, 8)
    r1Status:SetJustifyH("RIGHT")
    r1Status:SetText("")
    frame.r1Status = r1Status

    local r1Score = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r1Score:SetPoint("RIGHT", frame, "RIGHT", -6, 8)
    r1Score:SetWidth(44)
    r1Score:SetJustifyH("RIGHT")
    r1Score:SetTextColor(0.38, 0.69, 1.00) -- Alliance Blue
    r1Score:SetText("")
    frame.r1Score = r1Score

    -- Row 2: Horde Row (y = -8 from center)
    local r2Bases = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r2Bases:SetPoint("LEFT", frame, "LEFT", 6, -8)
    r2Bases:SetPoint("RIGHT", frame, "RIGHT", -52, -8)
    r2Bases:SetJustifyH("RIGHT")
    r2Bases:SetTextColor(1.00, 0.82, 0.00) -- Gold
    r2Bases:SetText("")
    frame.r2Bases = r2Bases

    local r2Score = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r2Score:SetPoint("RIGHT", frame, "RIGHT", -6, -8)
    r2Score:SetWidth(44)
    r2Score:SetJustifyH("RIGHT")
    r2Score:SetTextColor(1.00, 0.38, 0.38) -- Horde Red
    r2Score:SetText("")
    frame.r2Score = r2Score

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
        AutoBG_Settings.Positions["AutoBG_ABProjectionFrame"] = nil
    end

    QueueFrame:ClearAllPoints();   QueueFrame:SetPoint("TOP",   UIParent, "TOP", -220, -100) -- octowow-ignore: AP-31
    RespawnFrame:ClearAllPoints(); RespawnFrame:SetPoint("TOP", UIParent, "TOP",    0, -100) -- octowow-ignore: AP-31
    NodeBarFrame:ClearAllPoints(); NodeBarFrame:SetPoint("TOP", UIParent, "TOP",  220, -100) -- octowow-ignore: AP-31
    AVNodeFrame:ClearAllPoints();  AVNodeFrame:SetPoint("TOP",  UIParent, "TOP",  220, -150) -- octowow-ignore: AP-31
    WSGFlagFrame:ClearAllPoints(); WSGFlagFrame:SetPoint("TOP", UIParent, "TOP", -110, -150) -- octowow-ignore: AP-31

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
-- Color Helpers
-- =========================================================
local function TimeBarColor(remaining, maxTime)
    local pct = remaining / maxTime
    if pct > 0.50 then     return 0.10, 0.85, 0.10
    elseif pct > 0.25 then return 0.90, 0.80, 0.10
    elseif pct > 0.08 then return 1.00, 0.40, 0.00
    else                   return 1.00, 0.10, 0.10
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

-- =========================================================
-- Generic Countdown Bar Row Styler & Renderer (AB / AV / WSG)
-- colorMode = "time"    -> bar color proportional to remaining/maxTime
-- colorMode = "faction" -> bar color fixed by faction (WSG: blue/red)
-- =========================================================
local function ApplyTimerRowData(row, name, faction, remaining, maxTime, colorMode, useColors)
    -- WSG live timers store a flag name and expiry; the row presentation supplies its faction.
    if colorMode == "faction" and not faction then
        if name == "Alliance Flag" then faction = "Alliance"
        elseif name == "Horde Flag" then faction = "Horde" end
    end
    local barR, barG, barB
    if colorMode == "faction" then
        if faction == "Alliance" then
            barR, barG, barB = 0.20, 0.50, 1.00
        else
            barR, barG, barB = 1.00, 0.15, 0.15
        end
    else
        barR, barG, barB = TimeBarColor(remaining, maxTime)
    end

    if row.lastFaction ~= faction then
        row.lastFaction = faction
        if faction == "Alliance" then
            row.flagIcon:SetTexture(ALLIANCE_FLAG_TEX)
            row.flagIcon:Show()
        elseif faction == "Horde" then
            row.flagIcon:SetTexture(HORDE_FLAG_TEX)
            row.flagIcon:Show()
        else
            row.flagIcon:Hide()
        end
    end

    local railFaction = (useColors or colorMode == "faction") and faction or "neutral"
    if row.lastRailFaction ~= railFaction then
        row.lastRailFaction = railFaction
        if railFaction == "Alliance" then row.factionRail:SetTexture(0.32, 0.62, 0.95)
        elseif railFaction == "Horde" then row.factionRail:SetTexture(0.94, 0.35, 0.34)
        else row.factionRail:SetTexture(0.45, 0.50, 0.55) end
    end

    row.labelFs:SetText(name)
    row.labelFs:SetTextColor(0.94, 0.93, 0.88)

    local timeStr = FormatTime(remaining)
    row.timeFs:SetText(timeStr)
    if remaining <= 10 then
        row.timeFs:SetTextColor(1, 0.78, 0.44)
    else
        row.timeFs:SetTextColor(1, 1, 1)
    end

    row.bar:SetMinMaxValues(0, maxTime)
    row.bar:SetValue(remaining)
    if row.compact then
        -- Stable, muted fills: urgency is conveyed by the countdown, not a red/green sweep.
        if useColors and faction == "Alliance" then
            row.bar:SetStatusBarColor(0.22, 0.34, 0.41)
        elseif useColors and faction == "Horde" then
            row.bar:SetStatusBarColor(0.39, 0.25, 0.24)
        else
            row.bar:SetStatusBarColor(0.30, 0.32, 0.30)
        end
    else
        row.bar:SetStatusBarColor(barR * 0.60, barG * 0.60, barB * 0.60)
    end

    local facText = faction and (" (" .. faction .. ")") or ""
    row.announceText = name .. facText .. ": " .. timeStr
    row:Show()
end

local function RenderCountdownBars(frame, timerTable, isEnabled, isZone, maxTime, testData, colorMode)
    if not frame or not frame.rows then return end
    local now       = GetTime()
    local isTestAll = AutoBG_Settings and AutoBG_Settings.TestAllTimers
    local useColors = AutoBG_Settings and AutoBG_Settings.NodeColors
    local maxRows   = #frame.rows
    local activeCount = 0

    if isEnabled and (isTestAll or isZone) then
        if isTestAll and testData then
            activeCount = math.min(#testData, maxRows)
            for i = 1, activeCount do
                local d   = testData[i]
                local row = frame.rows[i]
                ApplyTimerRowData(row, d.name, d.faction, d.remaining, maxTime, colorMode, useColors)
            end
        else
            local sortCount = 0
            for nodeName, data in pairs(timerTable) do
                local expireTime = (type(data) == "table" and data.expire) or data
                local faction    = (type(data) == "table" and data.faction) or nil
                local remaining  = expireTime - now
                if remaining > 0 then
                    sortCount = sortCount + 1
                    local item = activeSortBuffer[sortCount]
                    if not item then item = {}; activeSortBuffer[sortCount] = item end
                    item.name    = nodeName
                    item.expire  = expireTime
                    item.faction = faction
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
                local remaining = math.floor(item.expire - now)
                if remaining > 0 then
                    displayCount = displayCount + 1
                    local row = frame.rows[displayCount]
                    ApplyTimerRowData(row, item.name, item.faction, remaining, maxTime, colorMode, useColors)
                end
            end
            activeCount = displayCount
        end
    else
        if not isTestAll then table.wipe(timerTable) end
    end

    for i = activeCount + 1, maxRows do frame.rows[i]:Hide() end
    if activeCount > 0 then
        frame:SetHeight(frame.headerHeight + activeCount * (frame.rowHeight + BAR_ROW_GAP) + 5)
        frame:Show()
    else
        frame:Hide()
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

local function GetABWorldStateInfo()
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

local pendingCapsBuffer = {}
local function GetABPendingCaps()
    table.wipe(pendingCapsBuffer)
    local now = GetTime()
    for node, data in pairs(timers.AB) do
        local expire = (type(data) == "table" and data.expire) or data
        local faction = (type(data) == "table" and data.faction) or nil
        if expire and expire > now and faction then
            local rem = expire - now
            table.insert(pendingCapsBuffer, { node = node, time = rem, faction = faction })
        end
    end
    table.sort(pendingCapsBuffer, function(x, y) return x.time < y.time end)
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
        if cap.faction == "Alliance" then
            ab = math.min(5, ab + 1)
            hb = math.max(0, hb - 1)
        else
            hb = math.min(5, hb + 1)
            ab = math.max(0, ab - 1)
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

local function BasesNeededToWin(aRes, hRes)
    local faction = UnitFactionGroup("player")
    if not faction then return nil end
    local myRes, theirRes
    if faction == "Alliance" then
        myRes = aRes; theirRes = hRes
    else
        myRes = hRes; theirRes = aRes
    end
    for b = 1, 5 do
        local myRate = AB_RPS[b] or 0
        local theirRate = AB_RPS[5 - b] or 0
        local myTime = myRate > 0 and (AB_MAX_RESOURCES - myRes) / myRate or 999999
        local theirTime = theirRate > 0 and (AB_MAX_RESOURCES - theirRes) / theirRate or 999999
        if myTime < theirTime then
            local word = (b == 1) and "Base" or "Bases"
            return string.format("Need %d %s", b, word)
        end
    end
    return "Need 5 Bases"
end

local lastProjWinner = nil
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

    local DEAD_HEAT = 12
    local timeDiff = aTime - hTime
    local winner
    if math.abs(timeDiff) > DEAD_HEAT or aTime >= 999999 or hTime >= 999999 then
        winner = (aTime <= hTime) and "Alliance" or "Horde"
    elseif lastProjWinner then
        winner = lastProjWinner
    else
        winner = (aRes >= hRes) and "Alliance" or "Horde"
    end
    lastProjWinner = winner

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
    local playerWins = (winner == myFaction)
    local mins = math.floor(eta / 60)
    local secs = math.floor(eta - mins * 60)
    local etaStr = string.format("%s %d:%02d", (playerWins and "Win" or "Loss"), mins, secs)
    local etaColor = playerWins and "|cFF00FF00" or "|cFFFF5555"

    local basesNeeded = BasesNeededToWin(aRes, hRes) or "Need 3 Bases"

    return aFinal, hFinal, etaStr, etaColor, basesNeeded
end

-- Diff cache for AB Projection strings to guarantee zero layout thrashing (Rule C15 / AP-31)
local lastR1Status, lastR1Score = "", ""
local lastR2Bases, lastR2Score = "", ""

local function UpdateABProjection(isTestAll, isAB)
    if not AutoBG_Settings or AutoBG_Settings.ABProjection == false then
        if ABProjectionFrame:IsShown() then ABProjectionFrame:Hide() end
        return
    end

    if isTestAll then
        local r1Stat = "|cFF00FF00Win 03:45|r"
        local r1Sc   = "1450"
        local r2Base = "|cFFFFD100Need 3 Bases|r"
        local r2Sc   = "1280"

        if lastR1Status ~= r1Stat then ABProjectionFrame.r1Status:SetText(r1Stat); lastR1Status = r1Stat end
        if lastR1Score ~= r1Sc then ABProjectionFrame.r1Score:SetText(r1Sc); lastR1Score = r1Sc end
        if lastR2Bases ~= r2Base then ABProjectionFrame.r2Bases:SetText(r2Base); lastR2Bases = r2Base end
        if lastR2Score ~= r2Sc then ABProjectionFrame.r2Score:SetText(r2Sc); lastR2Score = r2Sc end

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
        return
    end

    local aRes, hRes, aBases, hBases = GetABWorldStateInfo()
    if not aRes or not hRes then
        if ABProjectionFrame:IsShown() then ABProjectionFrame:Hide() end
        return
    end

    local aFinal, hFinal, etaStr, etaColor, basesNeeded = CalculateABProjection(aRes, hRes, aBases, hBases)
    if not aFinal then
        if ABProjectionFrame:IsShown() then ABProjectionFrame:Hide() end
        return
    end

    local r1Stat = (etaColor or "|cFFFFFFFF") .. (etaStr or "") .. "|r"
    local r1Sc   = tostring(aFinal)
    local r2Base = "|cFFFFD100" .. (basesNeeded or "") .. "|r"
    local r2Sc   = tostring(hFinal)

    if lastR1Status ~= r1Stat then ABProjectionFrame.r1Status:SetText(r1Stat); lastR1Status = r1Stat end
    if lastR1Score ~= r1Sc then ABProjectionFrame.r1Score:SetText(r1Sc); lastR1Score = r1Sc end
    if lastR2Bases ~= r2Base then ABProjectionFrame.r2Bases:SetText(r2Base); lastR2Bases = r2Base end
    if lastR2Score ~= r2Sc then ABProjectionFrame.r2Score:SetText(r2Sc); lastR2Score = r2Sc end

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

    -- 1. AB Nodes: proportional time-color bars (60s cap)
    RenderCountdownBars(NodeBarFrame, timers.AB, AutoBG_Settings.ABTimers, isAB, 60, AB_TEST_DATA, "time")

    -- 1b. AB Projected Score Overlay (Aligned 2-row dual-column HUD)
    UpdateABProjection(isTestAll, isAB)

    -- 2. AV Nodes: proportional time-color bars (300s cap)
    RenderCountdownBars(AVNodeFrame, timers.AV, AutoBG_Settings.AVTimers, isAV, 300, AV_TEST_DATA, "time")

    -- 3. WSG Flags: fixed faction colors — Alliance=blue, Horde=red (23s cap)
    RenderCountdownBars(WSGFlagFrame, timers.WSG, AutoBG_Settings.WSGTimers, isWSG, 23, WSG_TEST_DATA, "faction")

    -- 4. Respawn Timer (Spirit Healer 30s Wave)
    if inPVP and AutoBG_Settings.RessTimer then
        local healerTime = (GetAreaSpiritHealerTime and GetAreaSpiritHealerTime()) or 0
        if healerTime > 0 then
            spiritHealerSyncTime = now - (30 - healerTime)
            spiritHealerSynced = true
        end
        if spiritHealerSyncTime == 0 then spiritHealerSyncTime = now end

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

    -- 5. Queue Timers (Original Blizzard format numbers + Visual Icons)
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
            local maxQ = MAX_BATTLEFIELD_QUEUES or 3
            for i = 1, maxQ do
                local status, mapName = GetBattlefieldStatus(i)
                if status == "queued" then
                    local waitTime = (GetBattlefieldTimeWaited and GetBattlefieldTimeWaited(i)) or 0
                    local estTime  = (GetBattlefieldEstimatedWaitTime and GetBattlefieldEstimatedWaitTime(i)) or 0
                    local sec      = math.floor(waitTime / 1000)
                    local row      = QueueFrame:GetOrCreateRow(qIndex)
                    local abbrev   = (mapName == "Warsong Gulch" and "WSG") or (mapName == "Arathi Basin" and "AB") or
                                     (mapName == "Alterac Valley" and "AV")  or (mapName == "Thorn Gorge"  and "TG") or mapName or "BG"
                    local bgIcon   = (AutoBG_GetBGIcon and AutoBG_GetBGIcon(mapName))
                    if bgIcon then
                        row.icon:SetTexture(bgIcon)
                        row.icon:Show()
                        row.fs:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
                    else
                        row.icon:Hide()
                        row.fs:SetPoint("CENTER", row, "CENTER", 0, 0)
                    end
                    row.fs:SetText(abbrev .. ": " .. FormatQueueTime(sec))
                    row.announceText = abbrev .. " Queue: " .. FormatQueueTime(sec)
                    if estTime > 0 then
                        row.estText = "Estimated: " .. FormatQueueTime(math.floor(estTime / 1000))
                    else
                        row.estText = nil
                    end
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
    if not AutoBG_Settings or not msg then return end
    local lower = string.lower(msg)
    local faction = GetFactionFromMessage(msg, ev)

    -- 1. AB Nodes (60s)
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
            if string.find(lower, "claims") or string.find(lower, "assaulted") or string.find(lower, "under attack") then
                timers.AV[node] = { expire = GetTime() + 300, faction = faction }
            elseif string.find(lower, "taken") or string.find(lower, "defended") or string.find(lower, "destroyed") or string.find(lower, "captured") then
                timers.AV[node] = nil
            end
        end
    end

    -- 3. Gate Pre-Match Announcements
    if     string.find(lower, "begins in 2 minute")  then timers.Global["Match Starts"] = GetTime() + 120
    elseif string.find(lower, "begins in 1 minute")  then timers.Global["Match Starts"] = GetTime() + 60
    elseif string.find(lower, "begins in 30 second") then timers.Global["Match Starts"] = GetTime() + 30
    elseif string.find(lower, "begins in 15 second") then timers.Global["Match Starts"] = GetTime() + 15
    elseif string.find(lower, "begun") or string.find(lower, "open") then
        timers.Global["Match Starts"] = nil
    end

    -- 4. WSG Flag Respawns (23s)
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
EventFrame:RegisterEvent("PLAYER_UNGHOST")
EventFrame:RegisterEvent("PLAYER_ALIVE")
EventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
EventFrame:RegisterEvent("ZONE_CHANGED")
EventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")

EventFrame:SetScript("OnEvent", function(arg1_param, arg2_param, arg3_param)
    local ev  = (type(arg1_param) == "string" and arg1_param) or arg2_param or event
    local msg = (type(arg1_param) == "string" and (arg2_param or arg1)) or arg3_param or arg1
    if ev == "PLAYER_ENTERING_WORLD" or ev == "ZONE_CHANGED" or ev == "ZONE_CHANGED_NEW_AREA" then
        UpdateZoneCache()
        if not isAB then
            table.wipe(timers.AB)
            if NodeBarFrame and NodeBarFrame:IsShown() then NodeBarFrame:Hide() end
            if ABProjectionFrame and ABProjectionFrame:IsShown() then ABProjectionFrame:Hide() end
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
            if RessFrame and RessFrame:IsShown() then RessFrame:Hide() end
        end
        if ev == "PLAYER_ENTERING_WORLD" then
            AutoBG_LoadTimerPositions()
            table.wipe(timers.Global)
            lastR1Status, lastR1Score = "", ""
            lastR2Bases, lastR2Score = "", ""
            lastProjWinner = nil
            spiritHealerSyncTime = GetTime()
            spiritHealerSynced   = false
        end
    elseif ev == "PLAYER_UNGHOST" or ev == "PLAYER_ALIVE" then
        if inPVP then
            local healerTime     = (GetAreaSpiritHealerTime and GetAreaSpiritHealerTime()) or 0
            spiritHealerSyncTime = (healerTime > 0) and (GetTime() - (30 - healerTime)) or GetTime()
            spiritHealerSynced   = true
        end
    else
        ParseCombatMessage(msg or arg1, ev)
    end
end)
