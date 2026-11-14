-- AutoBG Warsong Flag Carrier (FC) Tracker (Zero-Bloat Consolidated Architecture)
-- Author & Maintainer: Fostercare5988
-- Needs ClassicAPI and SuperWoW loaded; AutoBG.lua says what is missing.

if type(CLASSIC_API_VERSION) ~= "number" or not SUPERWOW_VERSION then
    return
end

local carrierAlliance = nil
local carrierHorde = nil
local scanTicker = nil
local SyncCarrierTicker
-- The frame preview (the settings window's Preview button); never saved.
local preview = false

local isWSG = false

local function UpdateZoneCache()
    isWSG = string.find(string.lower(GetRealZoneText() or ""), "warsong") ~= nil
end
UpdateZoneCache()

-- Canonical 4-Stage Distance Color Grading (Rule B8)
local function GetDistanceColor(d)
    if not d then return "|cFF808080" end
    if d <= 30 then return "|cFF00FF00"
    elseif d <= 50 then return "|cFFFFFF00"
    elseif d <= 80 then return "|cFFFF8000"
    else return "|cFFFF4040" end
end

local CarrierNameMatches
local OnCarrierDebuff

-- The frames are ClassicAPI unit buttons (AutoBG_Targets.BindUnit) once the
-- carrier's GUID is known; until then, and for /abg efc, ffc and focus, the
-- enemy frames' selector finds the carrier by name.
local function SelectCarrier(name, guid, focus)
    if not name or name == "" or not AutoBG_Targets then return false end
    return AutoBG_Targets.SelectEnemy(name, guid, focus and "RightButton" or "LeftButton")
end

local function BindCarrier(frame, guid)
    if AutoBG_Targets and AutoBG_Targets.BindUnit then AutoBG_Targets.BindUnit(frame, guid) end
end

local function CreateFCFrame(name, titleText, xOffset, yOffset, flagTexture)
    local frame = CreateFrame("Button", name, UIParent)
    frame:SetWidth(220)
    frame:SetHeight(42)
    frame:SetPoint("TOP", UIParent, "TOP", xOffset, yOffset)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    frame:SetBackdropColor(0.12, 0.16, 0.22, 0.95)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() this:StartMoving() end)
    frame:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        AutoBG_SavePosition(this, name)
    end)
    frame:Hide()

    -- Bound, ClassicAPI targets and focuses; this handles a carrier not yet seen.
    frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    frame:SetScript("OnClick", function()
        SelectCarrier(this.carrierName, this.carrierGuid, GetMouseButtonClicked() == "RightButton")
    end)

    frame:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetText(this.carrierName or titleText, 1, 1, 1)
        GameTooltip:AddLine("|cFF00FF00Left-Click:|r Target Flag Carrier", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("|cFF00FF00Right-Click:|r Focus Flag Carrier", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(24); icon:SetHeight(24)
    icon:SetPoint("LEFT", frame, "LEFT", 8, 0)
    icon:SetTexture(flagTexture)

    local distText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    distText:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -5)
    distText:SetWidth(60); distText:SetHeight(14)
    distText:SetJustifyH("RIGHT")
    distText:SetText("|cFF808080? yd|r")

    local nameText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    nameText:SetPoint("TOPLEFT", frame, "TOPLEFT", 36, -5)
    nameText:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -64, -5)
    nameText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    nameText:SetHeight(16); nameText:SetJustifyH("LEFT")
    nameText:SetText(titleText)

    local healthBar = CreateFrame("StatusBar", name .. "HealthBar", frame)
    healthBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 36, 6)
    healthBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 6)
    healthBar:SetHeight(12)
    healthBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    healthBar:SetMinMaxValues(0, 100); healthBar:SetValue(100)
    healthBar:SetStatusBarColor(0.1, 0.85, 0.1)
    -- Rule C8: Disable mouse on child statusbar to guarantee click passthrough to parent Button
    healthBar:EnableMouse(false)

    local barBg = healthBar:CreateTexture(nil, "BACKGROUND")
    barBg:SetAllPoints(healthBar)
    barBg:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    barBg:SetVertexColor(0.2, 0.2, 0.2, 0.7)

    local hpText = healthBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hpText:SetPoint("CENTER", healthBar, "CENTER", 0, 0)
    hpText:SetText("100%")

    local debuffText = healthBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    debuffText:SetPoint("RIGHT", healthBar, "RIGHT", -2, 0)
    debuffText:SetText("")

    frame.nameText = nameText
    frame.distText = distText
    frame.healthBar = healthBar
    frame.hpText = hpText
    frame.debuffText = debuffText
    frame.carrierGuid = nil
    return frame
end

local AllianceFC = CreateFCFrame("AutoBG_AllianceFC", "Alliance FC", -130, -150, "Interface\\WorldStateFrame\\HordeFlag")
local HordeFC = CreateFCFrame("AutoBG_HordeFC", "Horde FC", 130, -150, "Interface\\WorldStateFrame\\AllianceFlag")

function AutoBG_LoadFCPositions()
    AutoBG_LoadPosition(AllianceFC, "AutoBG_AllianceFC", "TOP", -130, -150)
    AutoBG_LoadPosition(HordeFC, "AutoBG_HordeFC", "TOP", 130, -150)
end

function AutoBG_ResetFCPositions()
    if AutoBG_Settings and AutoBG_Settings.Positions then
        AutoBG_Settings.Positions["AutoBG_AllianceFC"] = nil
        AutoBG_Settings.Positions["AutoBG_HordeFC"] = nil
    end
    AllianceFC:ClearAllPoints(); AllianceFC:SetPoint("TOP", UIParent, "TOP", -130, -150)
    HordeFC:ClearAllPoints(); HordeFC:SetPoint("TOP", UIParent, "TOP", 130, -150)
end

local function NotifyCarrierChanged()
    if AutoBG_Targets and AutoBG_Targets.OnCarrierChanged then
        AutoBG_Targets:OnCarrierChanged()
    end
    SyncCarrierTicker()
end

local function UpdateFCButton(frame, carrierName)
    frame.carrierName = carrierName
    frame.carrierGuid, frame.stackGuid = nil, nil
    BindCarrier(frame, nil)
    frame.displayHealth, frame.displayHP, frame.displayDistance, frame.displayStacks = nil, nil, nil, nil
    if carrierName and carrierName ~= "" and (not AutoBG_Settings or AutoBG_Settings.FCFrame ~= false) then
        local color = AutoBG_GetClassColor(AutoBG_FindPlayerClass(carrierName))
        frame.nameText:SetText(color and (color .. carrierName .. "|r") or carrierName)
        frame.healthBar:SetValue(100)
        frame.healthBar:SetStatusBarColor(0.1, 0.85, 0.1)
        frame.hpText:SetText("???")
        frame.distText:SetText("|cFF808080? yd|r")
        frame.debuffText:SetText("")
        frame:Show()
    else
        frame:Hide()
    end
end

local EventFrame = CreateFrame("Frame", "AutoBG_FCEventFrame")
EventFrame:RegisterEvent("CHAT_MSG_BG_SYSTEM_ALLIANCE")
EventFrame:RegisterEvent("CHAT_MSG_BG_SYSTEM_HORDE")
EventFrame:RegisterEvent("CHAT_MSG_BG_SYSTEM_NEUTRAL")
EventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
EventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")

local ShowCarrierHealth

EventFrame:SetScript("OnEvent", function()
    local ev, msg = event, arg1

    if ev == "UNIT_HEALTH_GUID" then
        -- NamPower: one event per health change of any loaded unit (arg1 GUID).
        local frame = (msg == AllianceFC.carrierGuid and AllianceFC) or (msg == HordeFC.carrierGuid and HordeFC)
        if frame then ShowCarrierHealth(frame, msg) end
        return
    end

    if ev == "DEBUFF_ADDED_OTHER" or ev == "DEBUFF_REMOVED_OTHER" then
        -- NamPower native globals: arg1 guid, arg3 spell ID, arg4 stacks, arg7 state (1 = removed).
        OnCarrierDebuff(arg1, arg3, arg4, arg7)
        return
    end

    if ev == "PLAYER_ENTERING_WORLD" or ev == "ZONE_CHANGED_NEW_AREA" then
        UpdateZoneCache()
        if not isWSG then
            carrierAlliance = nil; carrierHorde = nil
            UpdateFCButton(AllianceFC, nil); UpdateFCButton(HordeFC, nil)
            NotifyCarrierChanged()
            if AllianceFC:IsShown() then AllianceFC:Hide() end
            if HordeFC:IsShown() then HordeFC:Hide() end
        end
        if ev == "PLAYER_ENTERING_WORLD" then
            AutoBG_LoadFCPositions()
            carrierAlliance = nil; carrierHorde = nil
            UpdateFCButton(AllianceFC, nil); UpdateFCButton(HordeFC, nil)
            NotifyCarrierChanged()
        end
        SyncCarrierTicker()
        return
    end

    if not isWSG or not msg then return end

    -- Horde / Warsong Flag picked up by an Alliance player -> Alliance FC!
    local _, _, h_pick = string.find(msg, "[Hh]orde [Ff]lag was picked up by ([^!%.]+)")
    if not h_pick then
        _, _, h_pick = string.find(msg, "[Ww]arsong [Ff]lag was picked up by ([^!%.]+)")
    end
    if h_pick then
        local name = string.gsub(h_pick, "^%s*(.-)%s*$", "%1")
        -- Whoever carries the Horde flag plays for the Alliance.
        AutoBG_NoteSide(name, "Alliance")
        if carrierAlliance ~= name then
            carrierAlliance = name
            UpdateFCButton(AllianceFC, carrierAlliance)
            NotifyCarrierChanged()
        end
    end

    -- Alliance / Silverwing Flag picked up by a Horde player -> Horde FC!
    local _, _, a_pick = string.find(msg, "[Aa]lliance [Ff]lag was picked up by ([^!%.]+)")
    if not a_pick then
        _, _, a_pick = string.find(msg, "[Ss]ilverwing [Ff]lag was picked up by ([^!%.]+)")
    end
    if a_pick then
        local name = string.gsub(a_pick, "^%s*(.-)%s*$", "%1")
        AutoBG_NoteSide(name, "Horde")
        if carrierHorde ~= name then
            carrierHorde = name
            UpdateFCButton(HordeFC, carrierHorde)
            NotifyCarrierChanged()
        end
    end

    -- Horde / Warsong flag dropped, captured, or returned -> clear Alliance FC
    if string.find(msg, "[Hh]orde [Ff]lag was dropped") or string.find(msg, "[Ww]arsong [Ff]lag was dropped") or string.find(msg, "captured the [Hh]orde [Ff]lag") or string.find(msg, "captured the [Ww]arsong [Ff]lag") or string.find(msg, "[Hh]orde [Ff]lag was captured") or string.find(msg, "[Ww]arsong [Ff]lag was captured") or string.find(msg, "[Hh]orde [Ff]lag was returned") or string.find(msg, "[Ww]arsong [Ff]lag was returned") then
        carrierAlliance = nil; UpdateFCButton(AllianceFC, nil)
        NotifyCarrierChanged()
    end

    -- Alliance / Silverwing flag dropped, captured, or returned -> clear Horde FC
    if string.find(msg, "[Aa]lliance [Ff]lag was dropped") or string.find(msg, "[Ss]ilverwing [Ff]lag was dropped") or string.find(msg, "captured the [Aa]lliance [Ff]lag") or string.find(msg, "captured the [Ss]ilverwing [Ff]lag") or string.find(msg, "[Aa]lliance [Ff]lag was captured") or string.find(msg, "[Ss]ilverwing [Ff]lag was captured") or string.find(msg, "[Aa]lliance [Ff]lag was returned") or string.find(msg, "[Ss]ilverwing [Ff]lag was returned") then
        carrierHorde = nil; UpdateFCButton(HordeFC, nil)
        NotifyCarrierChanged()
    end

    if string.find(msg, "flags are now placed at their bases") then
        carrierAlliance = nil; carrierHorde = nil
        UpdateFCButton(AllianceFC, nil); UpdateFCButton(HordeFC, nil)
        NotifyCarrierChanged()
    end
end)

-- ClassicAPI distance, as the enemy frames and Spy use; nil when unknown.
local function GetDistance(unit)
    local distanceSquared, checked = UnitDistanceSquared(unit)
    if checked and distanceSquared then return math.floor(math.sqrt(distanceSquared) + 0.5) end
end

local carrierAuraSlots = {}
CarrierNameMatches = function(unit, name)
    if not unit or not UnitExists(unit) or not UnitIsPlayer(unit) then return false end
    local actual = UnitName(unit)
    if not actual or not name then return false end
    if string.find(actual, "-", 1, true) and string.find(name, "-", 1, true) then
        return actual == name
    end
    return string.gsub(actual, "%-.*$", "") == string.gsub(name, "%-.*$", "")
end

local function ResolveCarrierUnit(carrierName, guid)
    -- Revalidate GUID identity; never retain an unstable party/nameplate token.
    if CarrierNameMatches(guid, carrierName) then return guid end
    if CarrierNameMatches("target", carrierName) then return "target" end
    local unit = UnitTokenFromName(carrierName, true)
    if CarrierNameMatches(unit, carrierName) then return unit end
    if string.find(carrierName, "-", 1, true) then
        unit = UnitTokenFromName(string.gsub(carrierName, "%-.*$", ""), true)
        if CarrierNameMatches(unit, carrierName) then return unit end
    end
    return nil
end

local function SetCarrierText(frame, field, widget, value)
    if frame[field] ~= value then widget:SetText(value); frame[field] = value end
end

-- NamPower GetUnitField reads the unit's health fields directly and falls back to
-- party/raid data for unloaded group members (Emyrk/nampower SCRIPTS.md).
local function ReadCarrierHealth(unit)
    local hp, maxHp = GetUnitField(unit, "health"), GetUnitField(unit, "maxHealth")
    if hp and maxHp and maxHp > 0 then return hp, maxHp end
    return UnitHealth(unit) or 0, UnitHealthMax(unit) or 100
end

ShowCarrierHealth = function(frame, unit)
    local hp, maxHp = ReadCarrierHealth(unit)
    if maxHp <= 0 then return end
    local pct = math.floor((hp / maxHp) * 100)
    if frame.displayHealth ~= pct then
        frame.healthBar:SetValue(pct)
        frame.healthBar:SetStatusBarColor(pct < 60 and 0.95 or 0.1, pct < 30 and 0.15 or (pct < 60 and 0.8 or 0.85), 0.1)
        frame.displayHealth = pct
    end
    -- Real values when the client holds them, otherwise 0-100.
    -- UNVERIFIED: test in game which form OctoWoW sends for enemy players.
    SetCarrierText(frame, "displayHP", frame.hpText, (maxHp > 100) and (hp .. " / " .. maxHp) or (pct .. "%"))
end

local ASSAULT_DEBUFFS = { ["Focused Assault"] = true, ["Brutal Assault"] = true }

local function SetCarrierStacks(frame, stacks)
    SetCarrierText(frame, "displayStacks", frame.debuffText, stacks > 0 and ("|cFFFF2020[" .. stacks .. "]|r") or "")
end

-- GetSpellInfo names the spell, so OctoWoW's spell IDs need not be known.
OnCarrierDebuff = function(guid, spellId, stacks, state)
    if not guid then return end
    local frame = (guid == AllianceFC.carrierGuid and AllianceFC) or (guid == HordeFC.carrierGuid and HordeFC)
    if not frame or not ASSAULT_DEBUFFS[GetSpellInfo(spellId) or ""] then return end
    SetCarrierStacks(frame, state == 1 and 0 or (stacks or 1))
end

local function ScanCarrier(carrierName, frame)
    if not carrierName or carrierName == "" then return end
    local u = ResolveCarrierUnit(carrierName, frame.carrierGuid)
    if u then
            frame.carrierGuid = UnitGUID(u)
            BindCarrier(frame, frame.carrierGuid)
            ShowCarrierHealth(frame, u)

            -- Read the stacks once per identified carrier; DEBUFF_*_OTHER events keep them current.
            if frame.stackGuid ~= frame.carrierGuid then
                local debuffStacks = 0
                local complete = true
                -- GetAuraSlots returns a continuation token, not a table.
                local _, count = C_UnitAuras.GetAuraSlots(u, "HARMFUL", nil, nil, carrierAuraSlots)
                for i = 1, count do
                    local name, _, applications = C_UnitAuras.UnitAuraBySlot(u, carrierAuraSlots[i])
                    if not name then complete = false end
                    if ASSAULT_DEBUFFS[name or ""] then
                        debuffStacks = applications or 1
                        break
                    end
                end
                if complete then
                    SetCarrierStacks(frame, debuffStacks)
                    frame.stackGuid = frame.carrierGuid
                end
            end

            local yard = GetDistance(u)
            if yard then
                SetCarrierText(frame, "displayDistance", frame.distText, GetDistanceColor(yard) .. yard .. " yd|r")
            else
                SetCarrierText(frame, "displayDistance", frame.distText, "|cFF808080? yd|r")
            end
            return
    end
    -- Lost identity must not leave the previous carrier's health on screen.
    frame.carrierGuid, frame.stackGuid = nil, nil
    BindCarrier(frame, nil)
    SetCarrierText(frame, "displayHP", frame.hpText, "???")
    SetCarrierText(frame, "displayDistance", frame.distText, "|cFF808080? yd|r")
    SetCarrierText(frame, "displayStacks", frame.debuffText, "")
end

-- Health follows UNIT_HEALTH_GUID; twice a second finds the carrier's unit,
-- reads the distance and keeps the health of a carrier without events right.
local SCAN_SECONDS = 0.5
local showingTest = false

local function ScanFlagCarriers()
    if not AutoBG_Settings or not AutoBG_Settings.FCFrame then
        if AllianceFC:IsShown() then AllianceFC:Hide() end
        if HordeFC:IsShown() then HordeFC:Hide() end
        return
    end

    if showingTest and not preview then
        -- The preview wrote over the live text; rebuild both frames from the tracked carriers.
        showingTest = false
        UpdateFCButton(AllianceFC, carrierAlliance)
        UpdateFCButton(HordeFC, carrierHorde)
    end

    if not preview and not isWSG then
        if AllianceFC:IsShown() then AllianceFC:Hide() end
        if HordeFC:IsShown() then HordeFC:Hide() end
        return
    end

    if preview then
        if not showingTest then
            AllianceFC:Show(); AllianceFC.nameText:SetText("|cFFFF7D0AAlliance Druid|r"); AllianceFC.healthBar:SetValue(82); AllianceFC.hpText:SetText("82%"); AllianceFC.distText:SetText("|cFF00FF0024 yd|r")
            HordeFC:Show(); HordeFC.nameText:SetText("|cFFC79C6EHorde Warrior|r"); HordeFC.healthBar:SetValue(45); HordeFC.hpText:SetText("45%"); HordeFC.distText:SetText("|cFFFFFF0042 yd|r")
            showingTest = true
        end
        return
    end

    if carrierAlliance then
        if not AllianceFC:IsShown() then AllianceFC:Show() end
        ScanCarrier(carrierAlliance, AllianceFC)
    elseif AllianceFC:IsShown() then AllianceFC:Hide() end
    if carrierHorde then
        if not HordeFC:IsShown() then HordeFC:Show() end
        ScanCarrier(carrierHorde, HordeFC)
    elseif HordeFC:IsShown() then HordeFC:Hide() end
end

-- NamPower's GUID events fire for every unit around you once registered (the
-- debuffs for every raid member and mob), so they are on only while a carrier
-- is tracked: health, and the assault stacks without polling the carrier's auras.
local CARRIER_EVENTS = { "UNIT_HEALTH_GUID", "DEBUFF_ADDED_OTHER", "DEBUFF_REMOVED_OTHER" }
local carrierEventsOn = false
SyncCarrierTicker = function()
    local s = AutoBG_Settings
    local live = s and s.FCFrame and isWSG and (carrierAlliance or carrierHorde) and true or false
    if carrierEventsOn ~= live then
        carrierEventsOn = live
        for i = 1, #CARRIER_EVENTS do
            if live then EventFrame:RegisterEvent(CARRIER_EVENTS[i]) else EventFrame:UnregisterEvent(CARRIER_EVENTS[i]) end
        end
    end
    local needed = live or (s and s.FCFrame and preview)
    if needed and not scanTicker then
        local ticker
        ticker = C_Timer.NewTicker(SCAN_SECONDS, function()
            if scanTicker ~= ticker then return end
            ScanFlagCarriers()
            SyncCarrierTicker()
        end)
        scanTicker = ticker
    elseif not needed and scanTicker then
        scanTicker:Cancel()
        scanTicker = nil
    end
end

-- The settings window's frame preview shows two sample carriers.
function AutoBG_FC_SetPreview(on)
    preview = on and true or false
end

function AutoBG_FC_UpdateVisibility()
    ScanFlagCarriers()
    SyncCarrierTicker()
end

-- The enemy frames read the enemy carrier; /abg efc, ffc and focus use both.
-- By the side you play on, which on a mixed team need not be your faction.
function AutoBG_GetFriendlyCarrier()
    if AutoBG_MySide() == "Horde" then return carrierHorde end
    return carrierAlliance
end

function AutoBG_GetEnemyCarrier()
    if AutoBG_MySide() == "Horde" then return carrierAlliance end
    return carrierHorde
end

-- Targets (or focuses) the friendly or enemy carrier for /abg efc, ffc and focus.
local function SelectCarrierByRole(which, focus)
    local friendly = which and (string.lower(which) == "friendly" or string.lower(which) == "ffc")
    local target = friendly and AutoBG_GetFriendlyCarrier() or AutoBG_GetEnemyCarrier()
    if not target or target == "" then
        AutoBG_Print("No " .. (friendly and "friendly" or "enemy") .. " flag carrier right now.")
        return false
    end
    local frame = (target == carrierAlliance and AllianceFC) or (target == carrierHorde and HordeFC)
    local selected = SelectCarrier(target, frame and frame.carrierGuid, focus)
    if selected then AutoBG_Print((focus and "Focused " or "Targeted ") .. target .. ".") end
    return selected
end

function AutoBG_TargetCarrier(which) return SelectCarrierByRole(which, false) end
function AutoBG_FocusCarrier(which) return SelectCarrierByRole(which, true) end
