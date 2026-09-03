-- AutoBG Warsong Flag Carrier (FC) Tracker (Zero-Bloat Consolidated Architecture)
-- Author & Maintainer: Fostercare5988
-- Built natively for ClassicAPI v1.13.3+, SuperWoW 2.2+, NamPower 4.6.2+, UnitXP SP3, DXVK

-- Strict Engine Dependency Guard (Mandatory ClassicAPI v1.13.3+ & SuperWoW v2.2+)
if not (CLASSIC_API_VERSION and SUPERWOW_VERSION) then return end

local carrierAlliance = nil
local carrierHorde = nil

-- Static Unit IDs
local SCAN_UNITS = { "target", "mouseover", "targettarget", "player" }
for i = 1, 40 do table.insert(SCAN_UNITS, "raid" .. i); table.insert(SCAN_UNITS, "raid" .. i .. "target") end
for i = 1, 4 do table.insert(SCAN_UNITS, "party" .. i); table.insert(SCAN_UNITS, "party" .. i .. "target") end

-- Canonical 4-Stage Distance Color Grading (Rule B8)
local function GetDistanceColor(d)
    if not d then return "|cFF808080" end
    if d <= 30 then return "|cFF00FF00"
    elseif d <= 50 then return "|cFFFFFF00"
    elseif d <= 80 then return "|cFFFF8000"
    else return "|cFFFF4040" end
end

local function CreateFCFrame(name, titleText, xOffset, yOffset, flagTexture)
    local frame = CreateFrame("Button", name, UIParent)
    frame:SetWidth(185)
    frame:SetHeight(48)
    frame:SetPoint("TOP", UIParent, "TOP", xOffset, yOffset)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    frame:SetBackdropColor(0, 0, 0, 0.85)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() this:StartMoving() end)
    frame:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        if AutoBG_SavePosition then AutoBG_SavePosition(this, name) end
    end)
    frame:Hide()

    -- SuperWoW Hybrid Targeting (Rule B9 & D1)
    frame:SetScript("OnClick", function()
        if this.carrierGuid and TargetUnit then
            if TargetUnit(this.carrierGuid) then return end
        end
        if this.carrierName and this.carrierName ~= "" then
            TargetByName(this.carrierName, true)
        end
    end)

    -- SuperWoW Native Mouseover (Rule D1)
    frame:SetScript("OnEnter", function()
        if this.carrierGuid and SetMouseoverUnit then
            SetMouseoverUnit(this.carrierGuid)
        end
    end)
    frame:SetScript("OnLeave", function()
        if SetMouseoverUnit then
            SetMouseoverUnit(nil)
        end
    end)

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(32); icon:SetHeight(32)
    icon:SetPoint("LEFT", frame, "LEFT", 8, 0)
    icon:SetTexture(flagTexture)

    local distText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    distText:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)
    distText:SetWidth(60); distText:SetHeight(14)
    distText:SetJustifyH("RIGHT")
    distText:SetText("|cFF808080? yd|r")

    local nameText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    nameText:SetPoint("TOPLEFT", frame, "TOPLEFT", 44, -8)
    nameText:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -70, -8)
    nameText:SetHeight(14); nameText:SetJustifyH("LEFT")
    nameText:SetText(titleText)

    local healthBar = CreateFrame("StatusBar", name .. "HealthBar", frame)
    healthBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 44, 8)
    healthBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 8)
    healthBar:SetHeight(13)
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

local AllianceFC = CreateFCFrame("AutoBG_AllianceFC", "Alliance FC", -100, -150, "Interface\\Icons\\INV_BannerPVP_02")
local HordeFC = CreateFCFrame("AutoBG_HordeFC", "Horde FC", 100, -150, "Interface\\Icons\\INV_BannerPVP_01")

function AutoBG_LoadFCPositions()
    if AutoBG_LoadPosition then
        AutoBG_LoadPosition(AllianceFC, "AutoBG_AllianceFC", "TOP", -100, -150)
        AutoBG_LoadPosition(HordeFC, "AutoBG_HordeFC", "TOP", 100, -150)
    end
end

function AutoBG_ResetFCPositions()
    AllianceFC:ClearAllPoints(); AllianceFC:SetPoint("TOP", UIParent, "TOP", -100, -150)
    HordeFC:ClearAllPoints(); HordeFC:SetPoint("TOP", UIParent, "TOP", 100, -150)
end

local function UpdateFCButton(frame, carrierName)
    frame.carrierName = carrierName
    frame.carrierGuid = nil
    if carrierName and carrierName ~= "" then
        local color = (AutoBG_FindPlayerClass and AutoBG_GetClassColor and AutoBG_GetClassColor(AutoBG_FindPlayerClass(carrierName)))
        frame.nameText:SetText(color and (color .. carrierName .. "|r") or carrierName)
        frame.healthBar:SetValue(100)
        frame.healthBar:SetStatusBarColor(0.1, 0.85, 0.1)
        frame.hpText:SetText("???")
        frame.distText:SetText("|cFF808080? yd|r")
        if frame.debuffText then frame.debuffText:SetText("") end
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

EventFrame:SetScript("OnEvent", function()
    if not AutoBG_Settings or not AutoBG_Settings.FCFrame then return end
    local ev, msg = event, arg1
    local zone = string.lower((GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()) or "")

    if ev == "PLAYER_ENTERING_WORLD" then
        AutoBG_LoadFCPositions()
        carrierAlliance = nil; carrierHorde = nil
        UpdateFCButton(AllianceFC, nil); UpdateFCButton(HordeFC, nil)
        return
    end

    if not string.find(zone, "warsong") or not msg then return end

    local _, _, a_pick = string.find(msg, "[Aa]lliance [Ff]lag was picked up by ([^!%.]+)")
    if a_pick then carrierAlliance = a_pick; UpdateFCButton(AllianceFC, carrierAlliance) end

    local _, _, h_pick = string.find(msg, "[Hh]orde [Ff]lag was picked up by ([^!%.]+)")
    if h_pick then carrierHorde = h_pick; UpdateFCButton(HordeFC, carrierHorde) end

    if string.find(msg, "[Aa]lliance [Ff]lag was dropped") or string.find(msg, "captured the [Aa]lliance [Ff]lag") or string.find(msg, "[Aa]lliance [Ff]lag was returned") or string.find(msg, "flags are now placed at their bases") then
        carrierAlliance = nil; UpdateFCButton(AllianceFC, nil)
    end
    if string.find(msg, "[Hh]orde [Ff]lag was dropped") or string.find(msg, "captured the [Hh]orde [Ff]lag") or string.find(msg, "[Hh]orde [Ff]lag was returned") or string.find(msg, "flags are now placed at their bases") then
        carrierHorde = nil; UpdateFCButton(HordeFC, nil)
    end
end)

local function GetDistance(unit)
    if not unit or not UnitExists(unit) then return nil end
    -- 1. UnitXP Native Yard Engine (Rule B8 & B5)
    if UnitXP then
        local ok, dist = pcall(UnitXP, "distance", unit)
        if ok and dist and dist >= 0 then return math.floor(dist + 0.5) end
    end
    -- 2. SuperWoW 3D World Space (Instant exact yardage)
    if UnitPosition then
        local ok1, px, py, pz = pcall(UnitPosition, "player")
        local ok2, ux, uy, uz = pcall(UnitPosition, unit)
        if ok1 and ok2 and px and py and ux and uy then
            local dx, dy, dz = px - ux, py - uy, (pz and uz and (pz - uz) or 0)
            return math.floor(math.sqrt(dx * dx + dy * dy + dz * dz) + 0.5)
        end
    end
    return nil
end

local function ScanCarrier(carrierName, frame, flagType)
    if not carrierName or carrierName == "" then return end
    for i = 1, #SCAN_UNITS do
        local u = SCAN_UNITS[i]
        if UnitExists(u) and UnitName(u) == carrierName then
            frame.carrierGuid = (UnitGUID and UnitGUID(u)) or nil
            local hp, maxHp = UnitHealth(u), UnitHealthMax(u)
            local rawHp, rawMax = nil, nil
            if UnitXP then
                rawHp = UnitXP("health", u)
                rawMax = UnitXP("maxhealth", u)
            end

            if maxHp > 0 then
                local pct = math.floor((hp / maxHp) * 100)
                frame.healthBar:SetValue(pct)
                frame.healthBar:SetStatusBarColor(pct < 30 and 0.95 or (pct < 60 and 0.95 or 0.1), pct < 30 and 0.15 or (pct < 60 and 0.8 or 0.85), 0.1)
                frame.hpText:SetText((rawMax and rawMax > 100 and (rawHp .. " (" .. pct .. "%)")) or (pct .. "%"))
            end

            -- ClassicAPI v1.13.3+ Linear O(n) Slot-Batching Aura Tracker (Focused / Brutal Assault debuff stacks)
            local debuffStacks = 0
            if C_UnitAuras and C_UnitAuras.GetAuraSlots and C_UnitAuras.GetAuraDataBySlot then
                local debuffSlots = C_UnitAuras.GetAuraSlots(u, "HARMFUL")
                if debuffSlots then
                    for s = 1, #debuffSlots do
                        local debuff = C_UnitAuras.GetAuraDataBySlot(u, debuffSlots[s])
                        if debuff and debuff.name and (string.find(debuff.name, "Assault") or string.find(debuff.name, "Flag")) then
                            debuffStacks = debuff.applications or 1
                            break
                        end
                    end
                end
            end
            if frame.debuffText then
                if debuffStacks > 0 then
                    frame.debuffText:SetText("|cFFFF2020[" .. debuffStacks .. "]|r")
                else
                    frame.debuffText:SetText("")
                end
            end

            local yard = GetDistance(u)
            if yard then
                frame.distText:SetText(GetDistanceColor(yard) .. yard .. " yd|r")
            else
                frame.distText:SetText("|cFF808080? yd|r")
            end
            return
        end
    end

    frame.distText:SetText("|cFF808080? yd|r")
    if frame.debuffText then frame.debuffText:SetText("") end
end

-- 6.6 Hz Native Hardware Ticker (ClassicAPI C_Timer)
local function ScanFlagCarriers()
    if not AutoBG_Settings or not AutoBG_Settings.FCFrame then
        if AllianceFC:IsShown() then AllianceFC:Hide() end
        if HordeFC:IsShown() then HordeFC:Hide() end
        return
    end

    local zone = string.lower((GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()) or "")
    local isWSG = (string.find(zone, "warsong") ~= nil)
    local isTestAll = AutoBG_Settings.TestAllTimers

    if not isTestAll and not isWSG then
        if AllianceFC:IsShown() then AllianceFC:Hide() end
        if HordeFC:IsShown() then HordeFC:Hide() end
        return
    end

    if isTestAll then
        AllianceFC:Show(); AllianceFC.nameText:SetText("|cFFFF7D0AAlliance Druid|r"); AllianceFC.healthBar:SetValue(82); AllianceFC.hpText:SetText("82%"); AllianceFC.distText:SetText("|cFF00FF0024 yd|r")
        HordeFC:Show(); HordeFC.nameText:SetText("|cFFC79C6EHorde Warrior|r"); HordeFC.healthBar:SetValue(45); HordeFC.hpText:SetText("45%"); HordeFC.distText:SetText("|cFFFFFF0042 yd|r")
        return
    end

    if not WorldMapFrame or not WorldMapFrame:IsShown() then pcall(SetMapToCurrentZone) end
    if carrierAlliance then ScanCarrier(carrierAlliance, AllianceFC, "Alliance") end
    if carrierHorde then ScanCarrier(carrierHorde, HordeFC, "Horde") end
end

if C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(0.15, ScanFlagCarriers)
end

function AutoBG_FC_UpdateVisibility() ScanFlagCarriers() end
