-- AutoBG objective countdowns, resurrection waves and score projection.
-- Author & Maintainer: Fostercare5988
-- Built natively for ClassicAPI, SuperWoW 2.2+, NamPower

-- Strict Engine Dependency Guard (Mandatory ClassicAPI & SuperWoW v2.2+)

if type(CLASSIC_API_VERSION) ~= "number" or not SUPERWOW_VERSION then
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

-- =========================================================
-- Timer bars: one look for every countdown
-- =========================================================
-- Each row: the side's banner as its icon, then a glossy bar in the side's
-- color that drains with a spark at its edge, the time in a fixed column on
-- the left and the name after it. A one-pixel black line frames icon and bar.
-- Objectives, the match start, the respawn wave and queue waits all use it.
local FONT          = "Fonts\\FRIZQT__.TTF"
local NAME_FONT     = "Fonts\\ARIALN.TTF"
local BAR_TEXTURE   = [[Interface\AddOns\AutoBG\Textures\Gloss]]
local SPARK_TEXTURE = "Interface\\CastingBar\\UI-CastingBar-Spark"
local ALLIANCE_ICON = "Interface\\Icons\\INV_BannerPVP_02"
local HORDE_ICON    = "Interface\\Icons\\INV_BannerPVP_01"
local NEUTRAL_ICON  = "Interface\\Icons\\INV_Misc_PocketWatch_01"
local RESPAWN_ICON  = "Interface\\Icons\\Spell_Holy_Resurrection"
-- Objectives wear our own pictures (Textures\Nodes) on their side's color:
-- every Arathi Basin base its own, Alterac Valley bunkers and towers a keep,
-- graveyards (relief hut and aid station too) a headstone, mines a pick.
local NODE_KINDS = {
    ["Gold Mine"] = "GoldMine", ["Lumber Mill"] = "LumberMill", ["Blacksmith"] = "Blacksmith",
    ["Farm"] = "Farm", ["Stables"] = "Stables",
    ["Iceblood Tower"] = "Tower", ["Tower Point"] = "Tower",
    ["East Frostwolf Tower"] = "Tower", ["West Frostwolf Tower"] = "Tower",
    ["Stonehearth Bunker"] = "Tower", ["Icewing Bunker"] = "Tower",
    ["Dun Baldar North Bunker"] = "Tower", ["Dun Baldar South Bunker"] = "Tower",
    ["Frostwolf Relief Hut"] = "Grave", ["Snowfall Graveyard"] = "Grave",
    ["Stormpike Graveyard"] = "Grave", ["Iceblood Graveyard"] = "Grave",
    ["Frostwolf Graveyard"] = "Grave", ["Stonehearth Graveyard"] = "Grave",
    ["Stormpike Aid Station"] = "Grave",
    ["Irondeep Mine"] = "Mine", ["Coldtooth Mine"] = "Mine",
}
local NODE_ICONS = {} -- [node name][Alliance|Horde|Neutral] = texture path
for node, kind in pairs(NODE_KINDS) do
    local path = "Interface\\AddOns\\AutoBG\\Textures\\Nodes\\" .. kind .. "_"
    NODE_ICONS[node] = { Alliance = path .. "Alliance", Horde = path .. "Horde", Neutral = path .. "Neutral" }
end
local BAR_ROW_GAP   = 2
local BAR_TITLE_H   = 15
local BAR_COLORS = {
    Alliance = { 0.18, 0.42, 0.95 },
    Horde    = { 0.88, 0.17, 0.15 },
    neutral  = { 0.86, 0.64, 0.16 },
    spirit   = { 0.38, 0.76, 0.95 },
}
local TRACK_SHADE  = 0.22 -- the empty part of a bar: its own color, dark
local TIME_COLOR   = { 1, 1, 1 }
local URGENT_COLOR = { 1, 0.80, 0.25 }

local RenderTimers -- forward declaration: a row that runs out re-sorts its group

local function LayoutTimerRow(row, width, height)
    row:SetWidth(width)
    row:SetHeight(height)
    row.icon:SetWidth(height - 2)
    row.icon:SetHeight(height - 2)
    row.bar:ClearAllPoints()
    row.bar:SetPoint("TOPLEFT", row, "TOPLEFT", height, -1)
    row.bar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -1, 1)
    row.barWidth = width - height - 1
    row.spark:SetWidth(math.floor(height * 0.9))
    row.spark:SetHeight(height * 2)
    local fontSize = math.max(9, math.min(15, math.floor(height * 0.5)))
    local timeWidth = math.floor(fontSize * 2.8)
    row.timeFs:SetFont(FONT, fontSize)
    row.timeFs:SetWidth(timeWidth)
    row.labelFs:SetFont(NAME_FONT, fontSize + 2)
    row.labelFs:SetPoint("LEFT", row.bar, "LEFT", timeWidth + 8, 0)
    row.displaySec = nil
end

-- Presentation settings; stored anchors remain unchanged. widthScale makes
-- the respawn and queue bars narrower than the objective groups.
local function ApplyObjectiveAppearance(frame)
    local settings = AutoBG_Settings or {}
    local width = math.floor(math.max(180, math.min(420, tonumber(settings.ObjectiveWidth) or 225)) * frame.widthScale)
    local height = math.max(18, math.min(32, tonumber(settings.ObjectiveHeight) or 25))
    local scale = math.max(0.60, math.min(1.50, tonumber(settings.ObjectiveScale) or 1))
    local opacity = math.max(0.20, math.min(1, tonumber(settings.ObjectiveOpacity) or 0.9))
    if frame.appearanceWidth ~= width or frame.rowHeight ~= height then
        frame:SetWidth(width)
        frame.rowHeight = height
        frame.appearanceWidth = width
        frame.displayHeight = nil
        for i = 1, #frame.rows do
            LayoutTimerRow(frame.rows[i], width, height)
        end
    end
    if frame.appearanceScale ~= scale then frame:SetScale(scale); frame.appearanceScale = scale end
    if frame.appearanceOpacity ~= opacity then frame:SetAlpha(opacity); frame.appearanceOpacity = opacity end
end

-- Moves the fill and its spark; runs every frame while a bar drains.
local function SetRowValue(row, value)
    row.bar:SetValue(value)
    local share = (row.fillDuration and row.fillDuration > 0) and value / row.fillDuration or 0
    if share > 0.01 and share < 0.99 then
        row.spark:SetPoint("CENTER", row.bar, "LEFT", row.barWidth * share, 0)
        if not row.sparkShown then row.spark:Show(); row.sparkShown = true end
    elseif row.sparkShown then
        row.spark:Hide()
        row.sparkShown = false
    end
end

-- "21" under a minute, "1:51" from a minute up, as BigWigs shows them.
local function FormatClock(seconds)
    if seconds < 60 then return tostring(seconds) end
    local m = math.floor(seconds / 60)
    local s = seconds - m * 60
    return (s < 10) and (m .. ":0" .. s) or (m .. ":" .. s)
end

-- Rewrites the time only when the shown second changes.
local function SetRowClock(row, seconds)
    local sec = row.roundUp and math.ceil(seconds) or math.floor(seconds)
    if sec < 0 then sec = 0 end
    if row.displaySec == sec then return end
    row.displaySec = sec
    local text = FormatClock(sec)
    row.timeFs:SetText((row.clockPrefix or "") .. text)
    local urgent = (row.urgentAt and sec <= row.urgentAt) and true or false
    if row.displayUrgent ~= urgent then
        local c = urgent and URGENT_COLOR or TIME_COLOR
        row.timeFs:SetTextColor(c[1], c[2], c[3])
        row.displayUrgent = urgent
    end
    row.announceText = (row.announceName or "") .. ": " .. text
end

-- Animation only: the shown rows drain every frame. A row that runs out asks
-- for one render, which drops it or starts its next cycle.
local function AnimateTimerRows()
    local frame = this
    local now = GetTime()
    for i = 1, frame.activeCount or 0 do
        local row = frame.rows[i]
        local expiry = row.fillExpiry
        if expiry then
            local remaining = expiry - now
            if remaining <= 0 then
                if RenderTimers then RenderTimers() end
                return
            end
            SetRowValue(row, remaining)
            SetRowClock(row, remaining)
        end
    end
end

local function OnRowEnter()
    if not this.announceText or this.announceText == "" then return end
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    GameTooltip:SetText(this.announceText, 1, 1, 1)
    if this.estText then GameTooltip:AddLine(this.estText, 0.9, 0.9, 0.5) end
    GameTooltip:AddLine("Ctrl-click: announce in chat", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

local function OnRowLeave() GameTooltip:Hide() end

local function OnRowClick()
    if IsControlKeyDown() and this.announceText then AutoBG_SendAnnouncement(this.announceText) end
end

local function CreateTimerRow(frame, name)
    local row = CreateFrame("Button", name, frame)
    row:EnableMouse(true)
    row:RegisterForClicks("LeftButtonUp")
    row:RegisterForDrag("LeftButton")
    row:SetScript("OnDragStart", function()
        GameTooltip:Hide()
        frame:StartMoving()
    end)
    row:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        if AutoBG_SavePosition then AutoBG_SavePosition(frame, frame:GetName()) end
    end)
    row:SetScript("OnClick", OnRowClick)
    row:SetScript("OnEnter", OnRowEnter)
    row:SetScript("OnLeave", OnRowLeave)

    -- Black behind everything: the frame line and the gap between icon and bar.
    local back = row:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints(row)
    back:SetTexture(0, 0, 0, 0.85)

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", row, "TOPLEFT", 1, -1)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.icon = icon

    local bar = CreateFrame("StatusBar", name .. "Bar", row)
    bar:SetStatusBarTexture(BAR_TEXTURE)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    bar:EnableMouse(false)
    row.bar = bar

    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints(bar)
    track:SetTexture(BAR_TEXTURE)
    row.track = track

    -- Spark and text sit on their own layer above the fill.
    local top = CreateFrame("Frame", nil, bar)
    top:SetAllPoints(bar)

    local spark = top:CreateTexture(nil, "ARTWORK")
    spark:SetTexture(SPARK_TEXTURE)
    spark:SetBlendMode("ADD")
    spark:SetAlpha(0.8)
    spark:Hide()
    row.spark, row.sparkShown = spark, false

    local timeFs = top:CreateFontString(nil, "OVERLAY")
    timeFs:SetPoint("LEFT", bar, "LEFT", 5, 0)
    timeFs:SetJustifyH("LEFT")
    timeFs:SetShadowOffset(1, -1)
    timeFs:SetShadowColor(0, 0, 0, 1)
    row.timeFs = timeFs

    local labelFs = top:CreateFontString(nil, "OVERLAY")
    labelFs:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    labelFs:SetJustifyH("LEFT")
    labelFs:SetShadowOffset(1, -1)
    labelFs:SetShadowColor(0, 0, 0, 1)
    row.labelFs = labelFs

    LayoutTimerRow(row, frame:GetWidth(), frame.rowHeight)
    timeFs:SetTextColor(1, 1, 1)
    labelFs:SetTextColor(1, 1, 1)
    row:Hide()
    return row
end

local function CreateBarTimerFrame(name, titleText, xOffset, yOffset, maxRows, defaultIcon, widthScale)
    local width, rowHeight = 225, 25
    local titleHeight = titleText and BAR_TITLE_H or 0
    local frame = CreateFrame("Frame", name, UIParent)
    frame:SetWidth(width)
    frame:SetHeight(titleHeight + rowHeight)
    frame.rowHeight = rowHeight
    frame.headerHeight = titleHeight
    frame.defaultIcon = defaultIcon or NEUTRAL_ICON
    frame.widthScale = widthScale or 1
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
        local titleFs = frame:CreateFontString(nil, "OVERLAY")
        titleFs:SetFont(NAME_FONT, 12)
        titleFs:SetShadowOffset(1, -1)
        titleFs:SetShadowColor(0, 0, 0, 1)
        titleFs:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, 0)
        titleFs:SetJustifyH("LEFT")
        titleFs:SetTextColor(0.95, 0.82, 0.55)
        titleFs:SetText(titleText)
        frame.titleFs = titleFs
    end

    frame.rows = {}
    for i = 1, maxRows do
        local row = CreateTimerRow(frame, name .. "Row" .. i)
        if i == 1 then
            row:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -titleHeight)
        else
            row:SetPoint("TOPLEFT", frame.rows[i - 1], "BOTTOMLEFT", 0, -BAR_ROW_GAP)
        end
        frame.rows[i] = row
    end

    frame:SetScript("OnUpdate", AnimateTimerRows)
    return frame
end

-- Shows the first count rows of a group and fits its height to them.
local function ShowRows(frame, count)
    frame.activeCount = count
    for i = count + 1, #frame.rows do
        local row = frame.rows[i]
        row.fillExpiry = nil
        if row:IsShown() then row:Hide() end
    end
    if count > 0 then
        local height = frame.headerHeight + count * frame.rowHeight + (count - 1) * BAR_ROW_GAP
        if frame.displayHeight ~= height then frame:SetHeight(height); frame.displayHeight = height end
        if not frame:IsShown() then frame:Show() end
    elseif frame:IsShown() then
        frame:Hide()
    end
end

local function PaintRow(row, colorKey)
    if row.displayColor == colorKey then return end
    local c = BAR_COLORS[colorKey]
    row.bar:SetStatusBarColor(c[1], c[2], c[3])
    row.track:SetVertexColor(c[1] * TRACK_SHADE, c[2] * TRACK_SHADE, c[3] * TRACK_SHADE, 0.9)
    row.displayColor = colorKey
end

local function SetRowIcon(row, icon)
    if row.displayIcon ~= icon then
        row.icon:SetTexture(icon)
        row.displayIcon = icon
    end
end

-- name is shown; announceName starts the Ctrl-click line ("<announceName>: 1:51").
local function SetRowName(row, name, announceName)
    if row.displayName ~= name then
        row.labelFs:SetText(name)
        row.displayName = name
    end
    if row.announceName ~= announceName then
        row.announceName = announceName
        row.displaySec = nil
    end
end

local function SetRowDuration(row, duration)
    if row.fillDuration ~= duration then
        row.bar:SetMinMaxValues(0, duration)
        row.fillDuration = duration
    end
end

-- =========================================================
-- Frame Instantiation
-- =========================================================
local QueueFrame      = CreateBarTimerFrame("AutoBG_QueueFrame",      "Queues",         -220, -100, 3, nil, 0.85)
local RespawnFrame    = CreateBarTimerFrame("AutoBG_RespawnFrame",    nil,                 0, -100, 1, RESPAWN_ICON, 0.7)
local StartTimerFrame = CreateBarTimerFrame("AutoBG_StartTimerFrame", nil,                 0,  -60, 1)
local NodeBarFrame    = CreateBarTimerFrame("AutoBG_NodeFrame",       "Arathi Basin",    220, -100, 5)
local AVNodeFrame     = CreateBarTimerFrame("AutoBG_AVNodeFrame",     "Alterac Valley",  220, -150, 10)
local WSGFlagFrame    = CreateBarTimerFrame("AutoBG_WSGFlagFrame",    "Warsong Gulch",  -110, -150, 2)

-- The respawn bar is always the same row: the spirit healer's 30-second wave.
do
    local row = RespawnFrame.rows[1]
    row.roundUp, row.urgentAt = true, 5
    SetRowIcon(row, RESPAWN_ICON)
    SetRowName(row, "Respawn", "Ress in")
    PaintRow(row, "spirit")
    SetRowDuration(row, 30)
end

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
            AutoBG_SendAnnouncement(self.announceText)
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
    { name = "Game Starts",  remaining = 45, faction = nil },
}

-- =========================================================
-- Countdown Bar Row Renderer (Game Start / AB / AV / WSG)
-- Rows take their faction's color and banner; colorMode = "faction" also
-- derives the faction from a WSG flag name. expiry is nil for preview rows,
-- which stand still.
-- =========================================================
local function ApplyTimerRowData(row, name, faction, remaining, maxTime, colorMode, defaultIcon, expiry)
    if colorMode == "faction" and not faction then
        if name == "Alliance Flag" then faction = "Alliance"
        elseif name == "Horde Flag" then faction = "Horde" end
    end
    local colorKey = BAR_COLORS[faction or ""] and faction or "neutral"
    local nodeIcons = NODE_ICONS[name]
    if nodeIcons then
        SetRowIcon(row, nodeIcons[faction or ""] or nodeIcons.Neutral)
    else
        SetRowIcon(row, (faction == "Alliance" and ALLIANCE_ICON) or (faction == "Horde" and HORDE_ICON) or defaultIcon)
    end
    SetRowName(row, name, faction and (name .. " (" .. faction .. ")") or name)
    PaintRow(row, colorKey)
    SetRowDuration(row, maxTime)
    row.urgentAt = 10
    row.fillExpiry = expiry
    SetRowValue(row, remaining)
    SetRowClock(row, remaining)
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
                local d = testData[i]
                ApplyTimerRowData(frame.rows[i], d.name, d.faction, d.remaining, maxTime, colorMode, frame.defaultIcon, nil)
            end
        else
            local sortCount = 0
            for nodeName, data in pairs(timerTable) do
                local expireTime = (type(data) == "table" and data.expire) or data
                local faction    = (type(data) == "table" and data.faction) or nil
                local rowMax     = (type(data) == "table" and data.max) or maxTime
                if expireTime - now > 0 then
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
            activeCount = math.min(sortCount, maxRows)
            for i = 1, activeCount do
                local item = activeSortBuffer[i]
                ApplyTimerRowData(frame.rows[i], item.name, item.faction, item.expire - now,
                    item.maxTime or maxTime, colorMode, frame.defaultIcon, item.expire)
            end
        end
    else
        if not isTestAll then table.wipe(timerTable) end
    end

    ShowRows(frame, activeCount)
end

-- A queue row counts up: the time waited, the bar filling toward the
-- estimated wait (full and still without an estimate).
local QUEUE_ABBREV = { ["Warsong Gulch"] = "WSG", ["Arathi Basin"] = "AB", ["Alterac Valley"] = "AV", ["Thorn Gorge"] = "TG" }

local function ApplyQueueRow(row, mapName, waited, estimate)
    mapName = mapName or "Battleground"
    SetRowIcon(row, (AutoBG_GetBGIcon and AutoBG_GetBGIcon(mapName)) or NEUTRAL_ICON)
    SetRowName(row, mapName, (QUEUE_ABBREV[mapName] or mapName) .. " queue")
    PaintRow(row, "neutral")
    local full = estimate > 0 and estimate or 1
    SetRowDuration(row, full)
    row.fillExpiry = nil
    SetRowValue(row, estimate > 0 and math.min(waited, estimate) or full)
    SetRowClock(row, waited)
    row.estText = estimate > 0 and ("Estimated: " .. FormatClock(estimate)) or nil
    if not row:IsShown() then row:Show() end
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
-- Timer logic, once a second (the rows animate themselves)
-- =========================================================
local function UpdateAllTimers()
    if not AutoBG_Settings then return end

    local now         = GetTime()
    local isTestAll   = AutoBG_Settings.TestAllTimers

    -- 0. Game start (pre-game gate countdown)
    RenderCountdownBars(StartTimerFrame, timers.Global, AutoBG_Settings.StartTimer ~= false, inPVP, 120, START_TEST_DATA, "time")

    -- 1. AB bases (60 s)
    RenderCountdownBars(NodeBarFrame, timers.AB, AutoBG_Settings.ABTimers, isAB, 60, AB_TEST_DATA, "time")

    -- 1b. AB Projected Score Overlay (Aligned 2-row dual-column HUD)
    UpdateABProjection(isTestAll, isAB)

    -- 2. AV towers, graveyards and mines (300 s)
    RenderCountdownBars(AVNodeFrame, timers.AV, AutoBG_Settings.AVTimers, isAV, 300, AV_TEST_DATA, "time")

    -- 3. WSG flag returns (23 s), colored by flag
    RenderCountdownBars(WSGFlagFrame, timers.WSG, AutoBG_Settings.WSGTimers, isWSG, 23, WSG_TEST_DATA, "faction")

    -- 4. Respawn: the spirit healer's 30-second wave
    local respawnRow = RespawnFrame.rows[1]
    if (inPVP or isTestAll) and AutoBG_Settings.RessTimer then
        ApplyObjectiveAppearance(RespawnFrame)
        local remaining, prefix, expiry = 24, "", nil
        if inPVP then
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
            remaining = 30 - ((now - spiritHealerSyncTime) % 30)
            -- "~" until a wave has been seen: the countdown is a guess.
            prefix = spiritHealerSynced and "" or "~"
            expiry = now + remaining
        end
        if respawnRow.clockPrefix ~= prefix then
            respawnRow.clockPrefix = prefix
            respawnRow.displaySec = nil
        end
        respawnRow.fillExpiry = expiry
        SetRowValue(respawnRow, remaining)
        SetRowClock(respawnRow, remaining)
        if not respawnRow:IsShown() then respawnRow:Show() end
        ShowRows(RespawnFrame, 1)
    else
        ShowRows(RespawnFrame, 0)
    end

    -- 5. Queue waits, once a second
    local queueSecond = math.floor(now)
    if lastQueueSecond ~= queueSecond or lastQueuePreview ~= isTestAll or lastQueueEnabled ~= AutoBG_Settings.QueueTimers then
        lastQueueSecond, lastQueuePreview, lastQueueEnabled = queueSecond, isTestAll, AutoBG_Settings.QueueTimers
        local shown = 0
        if AutoBG_Settings.QueueTimers then
            ApplyObjectiveAppearance(QueueFrame)
            if isTestAll then
                ApplyQueueRow(QueueFrame.rows[1], "Warsong Gulch", 75, 0)
                ApplyQueueRow(QueueFrame.rows[2], "Arathi Basin", 272, 360)
                shown = 2
            else
                for queueIndex = 1, math.min(queuedCount, #QueueFrame.rows) do
                    local queue = queuedBattlegrounds[queueIndex]
                    local waited = (GetBattlefieldTimeWaited and GetBattlefieldTimeWaited(queue.id)) or 0
                    local estimate = (GetBattlefieldEstimatedWaitTime and GetBattlefieldEstimatedWaitTime(queue.id)) or 0
                    shown = shown + 1
                    ApplyQueueRow(QueueFrame.rows[shown], queue.map, math.floor(waited / 1000), math.floor(estimate / 1000))
                end
            end
        end
        ShowRows(QueueFrame, shown)
    end
end
RenderTimers = UpdateAllTimers

-- Text changes once a second and the bars animate on their own, so the
-- logic (expiry, sorting, spirit sync, queues, AB projection) runs at 1 Hz.
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
        ticker = C_Timer.NewTicker(1, function()
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
    "Frostwolf Graveyard", "Stonehearth Graveyard", "Stormpike Aid Station",
    "Irondeep Mine", "Coldtooth Mine",
}
-- A mine changes hands when its boss dies: "The Horde has taken the Irondeep
-- Mine! ..." (the line BigWigs' Alterac Valley module matches). 5 minutes from
-- that line, as BigWigs counts it; confirmed right for OctoWoW by the player,
-- 2026-10-26.
local AV_MINES = { ["Irondeep Mine"] = true, ["Coldtooth Mine"] = true }

local function MatchNodeName(msg, nodeList)
    local lower = string.lower(msg)
    for i = 1, #nodeList do
        if string.find(lower, string.lower(nodeList[i])) then return nodeList[i] end
    end
    -- Short Arathi Basin names ("the mine", "the mill") only mean Arathi Basin bases.
    if nodeList ~= AB_NODES then return nil end
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

    -- "Grom claims the Stables!", "Grom has assaulted the Blacksmith!" (the
    -- flag watch reads the same two forms).
    local _, _, player = string.find(msg, "^(%S+) claims")
    if not player then _, _, player = string.find(msg, "^(%S+) has assaulted") end

    if player then
        local myFaction  = UnitFactionGroup("player")
        -- ClassicAPI finds the named player in the group or around you; a
        -- player it cannot find is taken for an enemy.
        local isFriendly = string.lower(UnitName("player") or "") == string.lower(player)
        if not isFriendly then
            local unit = UnitTokenFromName(player, true)
            isFriendly = unit and UnitFactionGroup(unit) == myFaction
        end
        return isFriendly and myFaction or ((myFaction == "Horde") and "Alliance" or "Horde")
    end
    return nil
end

-- Seconds left in a start announcement: "1 minute until the battle for
-- Alterac Valley begins.", "The battle begins in 30 seconds!". The caller
-- checks the line is about the start; "This game will close in 30 seconds"
-- is the empty-game warning and must not count.
local START_WORDS = { one = 1, two = 2, fifteen = 15, thirty = 30 }
local function StartCountdown(lower)
    local _, _, n, unit = string.find(lower, "(%w+)%s+(m)in")
    if not n then _, _, n, unit = string.find(lower, "(%w+)%s+(s)ec") end
    n = n and (tonumber(n) or START_WORDS[n])
    if not n then return nil end
    return unit == "m" and n * 60 or n
end

local function ParseCombatMessage(msg, ev)
    if not AutoBG_Settings or not msg or not inPVP then return end
    local lower = string.lower(msg)
    local faction = GetFactionFromMessage(msg, ev)

    -- The flag watch learns from the same messages where flags stand and who holds them.
    if AutoBG_FlagWatch and isAB then
        local node = MatchNodeName(msg, AB_NODES)
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
        if node and AV_MINES[node] then
            if string.find(lower, "has taken") then
                timers.AV[node] = { expire = GetTime() + 300, faction = faction }
            end
        elseif node then
            -- 5 min on OctoWoW (confirmed in play, 2026-10-21)
            if string.find(lower, "claims") or string.find(lower, "assaulted") or string.find(lower, "under attack") then
                timers.AV[node] = { expire = GetTime() + 300, faction = faction }
            elseif string.find(lower, "taken") or string.find(lower, "defended") or string.find(lower, "destroyed") or string.find(lower, "captured") then
                timers.AV[node] = nil
            end
        end
    end

    -- 3. Game start: only a line about the battle beginning counts.
    local sec = (string.find(lower, "begin") or string.find(lower, "start") or string.find(lower, "open"))
        and StartCountdown(lower)
    if sec then
        timers.Global["Game Starts"] = { expire = GetTime() + sec, max = sec }
    elseif string.find(lower, "begun") or string.find(lower, "let the battle begin") or string.find(lower, "gates? (.-)open") then
        timers.Global["Game Starts"] = nil
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
        -- Revivals are timed only in a battleground, and only raid members count.
        if inPVP then EventFrame:RegisterUnitEvent("UNIT_HEALTH", unpack(RAID_UNITS))
        else EventFrame:UnregisterEvent("UNIT_HEALTH") end
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
