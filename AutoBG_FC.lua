-- AutoBG Warsong Flag Carrier (FC) Tracker
-- Author & Maintainer: Fostercare5988
-- Built natively for SuperWoW 2.2+, NamPower 4.6.2+, UnitXP SP3, DXVK 3.0.2+

local carrierAlliance = nil
local carrierHorde = nil

-- Static pre-allocated Unit ID arrays (Eliminates GC allocations during scan loops)
local RAID_UNITS = {}
local RAID_TARGET_UNITS = {}
local PARTY_UNITS = {}
local PARTY_TARGET_UNITS = {}

for i = 1, 40 do
    RAID_UNITS[i] = "raid" .. i
    RAID_TARGET_UNITS[i] = "raid" .. i .. "target"
end
for i = 1, 4 do
    PARTY_UNITS[i] = "party" .. i
    PARTY_TARGET_UNITS[i] = "party" .. i .. "target"
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
        if AutoBG_SavePosition then
            AutoBG_SavePosition(this, name)
        end
    end)
    frame:Hide()

    -- SuperWoW Exact whole-name targeting
    frame:SetScript("OnClick", function()
        if this.carrierName and this.carrierName ~= "" then
            TargetByName(this.carrierName, true)
        end
    end)

    -- Flag Icon
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(32)
    icon:SetHeight(32)
    icon:SetPoint("LEFT", frame, "LEFT", 8, 0)
    icon:SetTexture(flagTexture)

    -- Distance FontString (Top-right aligned with dedicated width)
    local distText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    distText:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)
    distText:SetWidth(60)
    distText:SetHeight(14)
    distText:SetJustifyH("RIGHT")
    distText:SetText("|cFF808080? yd|r")

    -- Carrier Name FontString (Cleanly positioned above the health bar, left of distance)
    local nameText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    nameText:SetPoint("TOPLEFT", frame, "TOPLEFT", 44, -8)
    nameText:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -70, -8)
    nameText:SetHeight(14)
    nameText:SetJustifyH("LEFT")
    nameText:SetText(titleText)

    -- Visual Health Bar (Cleanly anchored to the bottom with breathing room)
    local healthBar = CreateFrame("StatusBar", name .. "HealthBar", frame)
    healthBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 44, 8)
    healthBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 8)
    healthBar:SetHeight(13)
    healthBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    healthBar:SetMinMaxValues(0, 100)
    healthBar:SetValue(100)
    healthBar:SetStatusBarColor(0.1, 0.85, 0.1)

    local barBg = healthBar:CreateTexture(nil, "BACKGROUND")
    barBg:SetAllPoints(healthBar)
    barBg:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    barBg:SetVertexColor(0.2, 0.2, 0.2, 0.7)

    local hpText = healthBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hpText:SetPoint("CENTER", healthBar, "CENTER", 0, 0)
    hpText:SetText("100%")

    frame.nameText = nameText
    frame.distText = distText
    frame.healthBar = healthBar
    frame.hpText = hpText
    frame.icon = icon

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
    if carrierName and carrierName ~= "" then
        local classColor = (AutoBG_FindPlayerClass and AutoBG_GetClassColor and AutoBG_GetClassColor(AutoBG_FindPlayerClass(carrierName)))
        if classColor then
            frame.nameText:SetText(classColor .. carrierName .. "|r")
        else
            frame.nameText:SetText(carrierName)
        end
        frame.healthBar:SetValue(100)
        frame.healthBar:SetStatusBarColor(0.1, 0.85, 0.1)
        frame.hpText:SetText("???")
        frame.distText:SetText("|cFF808080? yd|r")
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

    local ev = event
    local msg = arg1
    local currentZone = (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()) or ""
    local isWSG = (string.find(string.lower(currentZone), "warsong") ~= nil)

    if ev == "PLAYER_ENTERING_WORLD" then
        AutoBG_LoadFCPositions()
        carrierAlliance = nil
        carrierHorde = nil
        UpdateFCButton(AllianceFC, nil)
        UpdateFCButton(HordeFC, nil)
        return
    end

    if not isWSG or not msg then return end

    local _, _, a_picker = string.find(msg, "[Aa]lliance [Ff]lag was picked up by ([^!%.]+)")
    if a_picker then
        carrierAlliance = a_picker
        UpdateFCButton(AllianceFC, carrierAlliance)
    end

    local _, _, h_picker = string.find(msg, "[Hh]orde [Ff]lag was picked up by ([^!%.]+)")
    if h_picker then
        carrierHorde = h_picker
        UpdateFCButton(HordeFC, carrierHorde)
    end

    if string.find(msg, "[Aa]lliance [Ff]lag was dropped") or string.find(msg, "captured the [Aa]lliance [Ff]lag") or string.find(msg, "[Aa]lliance [Ff]lag was returned") or string.find(msg, "flags are now placed at their bases") then
        carrierAlliance = nil
        UpdateFCButton(AllianceFC, nil)
    end

    if string.find(msg, "[Hh]orde [Ff]lag was dropped") or string.find(msg, "captured the [Hh]orde [Ff]lag") or string.find(msg, "[Hh]orde [Ff]lag was returned") or string.find(msg, "flags are now placed at their bases") then
        carrierHorde = nil
        UpdateFCButton(HordeFC, nil)
    end
end)

-- Live HP & Distance Scanner (Throttled at 5 Hz / 0.2s with Zero-GC Allocation)
local Scanner = CreateFrame("Frame", "AutoBG_FCScanner")
local updateTimer = 0
Scanner:SetScript("OnUpdate", function()
    if not AutoBG_Settings or not AutoBG_Settings.FCFrame then
        if AllianceFC:IsShown() then AllianceFC:Hide() end
        if HordeFC:IsShown() then HordeFC:Hide() end
        return
    end

    local currentZone = (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()) or ""
    local isWSG = (string.find(string.lower(currentZone), "warsong") ~= nil)
    local isTestAll = AutoBG_Settings.TestAllTimers

    if not isTestAll and not isWSG then
        if AllianceFC:IsShown() then AllianceFC:Hide() end
        if HordeFC:IsShown() then HordeFC:Hide() end
        return
    end

    if isTestAll then
        AllianceFC:Show()
        AllianceFC.nameText:SetText("|cFFFF7D0AAlliance Druid|r")
        AllianceFC.healthBar:SetValue(82)
        AllianceFC.healthBar:SetStatusBarColor(0.1, 0.85, 0.1)
        AllianceFC.hpText:SetText("82%")
        AllianceFC.distText:SetText("|cFF00FF0024 yd|r")

        HordeFC:Show()
        HordeFC.nameText:SetText("|cFFC79C6EHorde Warrior|r")
        HordeFC.healthBar:SetValue(45)
        HordeFC.healthBar:SetStatusBarColor(0.95, 0.75, 0.1)
        HordeFC.hpText:SetText("45%")
        HordeFC.distText:SetText("|cFFFFFF0042 yd|r")
        return
    else
        if not carrierAlliance and AllianceFC:IsShown() then AllianceFC:Hide() end
        if not carrierHorde and HordeFC:IsShown() then HordeFC:Hide() end
    end

    updateTimer = updateTimer + (arg1 or 0.05)
    if updateTimer > 0.2 then
        updateTimer = 0

        local function checkUnit(unit, targetName, frame)
            if targetName and UnitExists(unit) and UnitName(unit) == targetName then
                local hp = UnitHealth(unit)
                local maxHp = UnitHealthMax(unit)

                -- 1. UnitXP Real Health Detection (True uncapped raw HP)
                local rawHp, rawMaxHp = nil, nil
                if UnitXP then
                    pcall(function()
                        rawHp = UnitXP("health", unit)
                        rawMaxHp = UnitXP("maxhealth", unit)
                    end)
                end

                if maxHp and maxHp > 0 then
                    local pct = math.floor((hp / maxHp) * 100)
                    frame.healthBar:SetValue(pct)

                    if pct < 30 then
                        frame.healthBar:SetStatusBarColor(0.95, 0.15, 0.1) -- Red
                    elseif pct < 60 then
                        frame.healthBar:SetStatusBarColor(0.95, 0.80, 0.1) -- Yellow
                    else
                        frame.healthBar:SetStatusBarColor(0.1, 0.85, 0.1) -- Green
                    end

                    if rawHp and rawMaxHp and rawMaxHp > 100 then
                        frame.hpText:SetText(rawHp .. " (" .. pct .. "%)")
                    else
                        frame.hpText:SetText(pct .. "%")
                    end
                end

                -- 2. Real-Time Distance Detection (UnitXP / Map Position / Interact Brackets)
                local dist = nil
                if UnitXP then
                    pcall(function()
                        dist = UnitXP("distance", unit) or UnitXP("range", unit)
                    end)
                end

                if dist and type(dist) == "number" and dist >= 0 then
                    local yard = math.floor(dist + 0.5)
                    local color = "|cFF00FF00"
                    if yard > 80 then
                        color = "|cFFFF4040"
                    elseif yard > 50 then
                        color = "|cFFFF8000"
                    elseif yard > 30 then
                        color = "|cFFFFFF00"
                    end
                    frame.distText:SetText(color .. yard .. " yd|r")
                else
                    -- Friendly unit in raid/party map calculation
                    local px, py = GetPlayerMapPosition("player")
                    local ux, uy = GetPlayerMapPosition(unit)
                    if px and py and ux and uy and (px > 0 or py > 0) and (ux > 0 or uy > 0) then
                        local dx = (px - ux) * 500
                        local dy = (py - uy) * 670
                        local yard = math.floor(math.sqrt(dx * dx + dy * dy) + 0.5)
                        local color = "|cFF00FF00"
                        if yard > 80 then
                            color = "|cFFFF4040"
                        elseif yard > 50 then
                            color = "|cFFFF8000"
                        elseif yard > 30 then
                            color = "|cFFFFFF00"
                        end
                        frame.distText:SetText(color .. yard .. " yd|r")
                    elseif CheckInteractDistance(unit, 3) then
                        frame.distText:SetText("|cFF00FF00<10 yd|r")
                    elseif CheckInteractDistance(unit, 2) then
                        frame.distText:SetText("|cFF00FF00~11 yd|r")
                    elseif CheckInteractDistance(unit, 1) or CheckInteractDistance(unit, 4) then
                        frame.distText:SetText("|cFFFFFF00<28 yd|r")
                    else
                        frame.distText:SetText("|cFFFF4040>28 yd|r")
                    end
                end

                -- 3. Refresh class coloring if found
                local _, classToken = UnitClass(unit)
                if classToken and AutoBG_GetClassColor then
                    local classColor = AutoBG_GetClassColor(classToken)
                    if classColor then
                        frame.nameText:SetText(classColor .. targetName .. "|r")
                    end
                end

                return true
            end
            return false
        end

        local function scanFor(targetName, frame)
            if not targetName or targetName == "" then return end
            if checkUnit("target", targetName, frame) then return end
            if checkUnit("mouseover", targetName, frame) then return end
            if checkUnit("targettarget", targetName, frame) then return end
            if checkUnit("player", targetName, frame) then return end

            local numRaid = (GetNumRaidMembers and GetNumRaidMembers()) or 0
            if numRaid > 0 then
                for i = 1, numRaid do
                    if checkUnit(RAID_UNITS[i], targetName, frame) then return end
                    if checkUnit(RAID_TARGET_UNITS[i], targetName, frame) then return end
                end
            else
                local numParty = (GetNumPartyMembers and GetNumPartyMembers()) or 0
                for i = 1, numParty do
                    if checkUnit(PARTY_UNITS[i], targetName, frame) then return end
                    if checkUnit(PARTY_TARGET_UNITS[i], targetName, frame) then return end
                end
            end

            -- Carrier is active but not targeted by player or raid members
            frame.distText:SetText("|cFF808080? yd|r")
        end

        if carrierAlliance then
            scanFor(carrierAlliance, AllianceFC)
        end
        if carrierHorde then
            scanFor(carrierHorde, HordeFC)
        end
    end
end)

function AutoBG_FC_UpdateVisibility()
    -- Scanner handles on next tick
end

