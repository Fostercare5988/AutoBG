-- AutoBG Options Panel
-- Authors: [Original Author], Fostercare5988 (Maintainer: Fostercare5988)
-- Built natively for SuperWoW 2.2+, NamPower 4.6.2+, UnitXP SP3, DXVK 3.0.2+

local panel = CreateFrame("Frame", "AutoBG_OptionsPanel", UIParent)
panel:SetWidth(460)
panel:SetHeight(510)
panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
panel:SetFrameStrata("DIALOG")
panel:SetToplevel(true)
panel:EnableMouse(true)
panel:SetMovable(true)
panel:RegisterForDrag("LeftButton")
panel:SetScript("OnDragStart", function() this:StartMoving() end)
panel:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
panel:Hide()

-- Allow closing with ESC key
tinsert(UISpecialFrames, "AutoBG_OptionsPanel")

-- Standard Vanilla Dialog Backdrop
panel:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 }
})

-- Header Title
local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOP", panel, "TOP", 0, -16)
title:SetText("AutoBG Settings")

local checkboxes = {}

local function CreateCheckbox(name, labelText, tooltipText, settingKey, anchor, x, y)
    local cb = CreateFrame("CheckButton", name, panel, "UICheckButtonTemplate")
    cb:SetWidth(22)
    cb:SetHeight(22)
    cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x or 0, y or -4)

    local text = getglobal(name .. "Text")
    if text then
        text:SetText(labelText)
        text:SetFontObject("GameFontHighlightSmall")
        text:SetPoint("LEFT", cb, "RIGHT", 4, 1)
    end
    cb.tooltipText = tooltipText
    cb.settingKey = settingKey

    cb:SetScript("OnClick", function()
        if AutoBG_Settings then
            local isChecked = (this:GetChecked() == 1 or this:GetChecked() == true)
            AutoBG_Settings[settingKey] = isChecked

            if settingKey == "HideCastbar" then
                if isChecked and CastingBarFrame then
                    CastingBarFrame:UnregisterAllEvents()
                    CastingBarFrame:Hide()
                elseif not isChecked then
                    if DEFAULT_CHAT_FRAME then
                        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00AutoBG:|r Please type /reload to restore default cast bar.")
                    end
                end
            elseif settingKey == "HideStanceBar" then
                if AutoBG_UpdateStanceBar then
                    AutoBG_UpdateStanceBar()
                end
                if not isChecked then
                    if DEFAULT_CHAT_FRAME then
                        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00AutoBG:|r Please type /reload to restore stance/stealth bar.")
                    end
                end
            elseif settingKey == "TestAllTimers" then
                if AutoBG_LoadTimerPositions then AutoBG_LoadTimerPositions() end
            end
        end
    end)

    cb:SetScript("OnEnter", function()
        if this.tooltipText then
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
            GameTooltip:SetText(this.tooltipText, 1, 1, 1, nil, 1)
            GameTooltip:Show()
        end
    end)
    cb:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    tinsert(checkboxes, cb)
    return cb
end

local function CreateHeader(text, anchor, x, y)
    local h = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    h:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x or 0, y or -10)
    h:SetText(text)
    return h
end

-- ==========================================================
-- COLUMN 1: LEFT SIDE (Alerts & Automation + General Tweaks)
-- ==========================================================
local headerAlerts = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
headerAlerts:SetPoint("TOPLEFT", panel, "TOPLEFT", 22, -46)
headerAlerts:SetText("Alerts & Automation")

local cbSound = CreateCheckbox("AutoBG_Opt_Sound", "Loud Sound Alerts", "Play a loud ready check sound when queues pop or end.", "NotifySound", headerAlerts, 0, -4)
local cbFlash = CreateCheckbox("AutoBG_Opt_Flash", "Taskbar Flashing", "Flash the game window in taskbar on queue pop.", "FlashTaskbar", cbSound)
local cbChatMsg = CreateCheckbox("AutoBG_Opt_ChatMsg", "Chat Notifications", "Display status messages in chat for queues, auto-leave, and joins.", "ChatMessages", cbFlash)
local cbAccept = CreateCheckbox("AutoBG_Opt_Accept", "Auto-Accept Queue Pop", "Automatically accept the battleground queue and enter when ready.", "AutoAccept", cbChatMsg)

local sliderDelay = CreateFrame("Slider", "AutoBG_Slider_AcceptDelay", panel, "OptionsSliderTemplate")
sliderDelay:SetPoint("TOPLEFT", cbAccept, "BOTTOMLEFT", 20, -14)
sliderDelay:SetMinMaxValues(0, 70)
sliderDelay:SetValueStep(1)
sliderDelay:SetWidth(150)
getglobal(sliderDelay:GetName() .. "Low"):SetText("0s")
getglobal(sliderDelay:GetName() .. "High"):SetText("70s")
getglobal(sliderDelay:GetName() .. "Text"):SetText("Enter Delay: Instant (0s)")
sliderDelay:SetScript("OnValueChanged", function()
    local val = math.floor(this:GetValue() + 0.5)
    if AutoBG_Settings then AutoBG_Settings.AutoAcceptDelay = val end
    if val == 0 then
        getglobal(this:GetName() .. "Text"):SetText("Enter Delay: Instant (0s)")
    else
        getglobal(this:GetName() .. "Text"):SetText("Enter Delay: " .. val .. "s")
    end
end)

local cbLeave = CreateCheckbox("AutoBG_Opt_Leave", "Auto-Leave BG on End", "Automatically leave the Battleground when the match finishes.", "AutoLeave", sliderDelay, -20, -18)
local cbRejoin = CreateCheckbox("AutoBG_Opt_Rejoin", "Auto-Rejoin BG on Exit", "Automatically queue for the same Battleground after match exit via Battleground Finder.", "AutoRejoin", cbLeave)
local cbQueueLogin = CreateCheckbox("AutoBG_Opt_QueueLogin", "Auto-Queue on Login (WSG/AB/AV)", "Automatically queue for Warsong Gulch, Arathi Basin, and Alterac Valley when logging in or reloading.", "AutoQueueLogin", cbRejoin)
local cbRelease = CreateCheckbox("AutoBG_Opt_Release", "Auto-Release Spirit", "Automatically release spirit upon dying in BG (skips if Soulstone/Ankh ready).", "AutoRelease", cbQueueLogin)

local headerTweaks = CreateHeader("General Tweaks", cbRelease, 0, -12)
local cbScoreColor = CreateCheckbox("AutoBG_Opt_ScoreColor", "Scoreboard Class Colors", "Color names on the scoreboard by player class.", "ScoreColor", headerTweaks, 0, -4)
local cbNodeColors = CreateCheckbox("AutoBG_Opt_NodeColors", "Faction Node Colors", "Color-code AB and AV node timers (Red = Horde, Blue = Alliance).", "NodeColors", cbScoreColor, 0, -4)
local cbHideCastbar = CreateCheckbox("AutoBG_Opt_HideCastbar", "Hide Default Castbar", "Hide default Blizzard cast bar (useful if using custom castbars).", "HideCastbar", cbNodeColors, 0, -4)
local cbHideStanceBar = CreateCheckbox("AutoBG_Opt_HideStanceBar", "Hide Stealth/Stance Bar", "Hide default Blizzard stance/shapeshift bar (Stealth, Stances, Forms, Auras).", "HideStanceBar", cbHideCastbar, 0, -4)

-- ==========================================================
-- COLUMN 2: RIGHT SIDE (Timers & Overlays + Testing)
-- ==========================================================
local headerTimers = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
headerTimers:SetPoint("TOPLEFT", panel, "TOPLEFT", 242, -46)
headerTimers:SetText("Timers & Overlays")

local cbABTimers = CreateCheckbox("AutoBG_Opt_ABTimers", "Arathi Basin Nodes", "Show 60s node capture countdowns in Arathi Basin.", "ABTimers", headerTimers, 0, -4)
local cbAVTimers = CreateCheckbox("AutoBG_Opt_AVTimers", "Alterac Valley Nodes", "Show 5m bunker/tower capture countdowns in AV.", "AVTimers", cbABTimers)
local cbWSGTimers = CreateCheckbox("AutoBG_Opt_WSGTimers", "WSG Flag Respawns", "Show 23s flag respawn countdowns in Warsong Gulch.", "WSGTimers", cbAVTimers)
local cbRessTimer = CreateCheckbox("AutoBG_Opt_RessTimer", "Spirit Healer Timer", "Show synced 30s Spirit Healer resurrection wave timer.", "RessTimer", cbWSGTimers)
local cbQueueTimers = CreateCheckbox("AutoBG_Opt_QueueTimers", "BG Queue Timers", "Show on-screen timer for active BG queue wait times.", "QueueTimers", cbRessTimer)
local cbFCFrame = CreateCheckbox("AutoBG_Opt_FCFrame", "WSG Flag Carrier Frames", "Show clickable frames to target and track WSG flag carriers.", "FCFrame", cbQueueTimers)

local headerTest = CreateHeader("Positioning & Testing", cbFCFrame, 0, -12)
local cbTestAll = CreateCheckbox("AutoBG_Opt_TestAll", "Test Mode (Unlock Timers)", "Show all timer and FC frames on screen so you can drag them to preferred positions.", "TestAllTimers", headerTest, 0, -4)

-- Reset Positions Button
local btnResetPos = CreateFrame("Button", "AutoBG_BtnResetPos", panel, "UIPanelButtonTemplate")
btnResetPos:SetWidth(95)
btnResetPos:SetHeight(22)
btnResetPos:SetPoint("TOPLEFT", cbTestAll, "BOTTOMLEFT", 0, -8)
btnResetPos:SetText("Reset Pos")
btnResetPos:SetScript("OnClick", function()
    if AutoBG_Settings then
        AutoBG_Settings.Positions = {}
        if AutoBG_ResetTimerPositions then AutoBG_ResetTimerPositions() end
        if AutoBG_ResetFCPositions then AutoBG_ResetFCPositions() end
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00AutoBG:|r Frame positions have been reset to defaults.")
        end
    end
end)

-- Test Sound Button
local btnTestSound = CreateFrame("Button", "AutoBG_BtnTestSound", panel, "UIPanelButtonTemplate")
btnTestSound:SetWidth(95)
btnTestSound:SetHeight(22)
btnTestSound:SetPoint("LEFT", btnResetPos, "RIGHT", 8, 0)
btnTestSound:SetText("Test Sound")
btnTestSound:SetScript("OnClick", function()
    if AutoBG_PlayNotificationSound then
        AutoBG_PlayNotificationSound()
    else
        PlaySound("ReadyCheck")
    end
end)

-- Close Button (Top-right X)
local closeButton = CreateFrame("Button", "AutoBG_CloseButton", panel, "UIPanelCloseButton")
closeButton:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -6, -6)

-- Done / Close Button (Bottom Center)
local btnDone = CreateFrame("Button", "AutoBG_BtnDone", panel, "UIPanelButtonTemplate")
btnDone:SetWidth(100)
btnDone:SetHeight(24)
btnDone:SetPoint("BOTTOM", panel, "BOTTOM", 0, 14)
btnDone:SetText("Close")
btnDone:SetScript("OnClick", function()
    panel:Hide()
end)

function AutoBG_Options_Refresh()
    if not AutoBG_Settings then return end
    for i = 1, table.getn(checkboxes) do
        local cb = checkboxes[i]
        if cb and cb.settingKey then
            cb:SetChecked(AutoBG_Settings[cb.settingKey] and 1 or nil)
        end
    end
    if AutoBG_Slider_AcceptDelay then
        local delay = AutoBG_Settings.AutoAcceptDelay or 0
        AutoBG_Slider_AcceptDelay:SetValue(delay)
        if delay == 0 then
            getglobal("AutoBG_Slider_AcceptDelayText"):SetText("Enter Delay: Instant (0s)")
        else
            getglobal("AutoBG_Slider_AcceptDelayText"):SetText("Enter Delay: " .. delay .. "s")
        end
    end
end

panel:SetScript("OnShow", function()
    AutoBG_Options_Refresh()
end)
