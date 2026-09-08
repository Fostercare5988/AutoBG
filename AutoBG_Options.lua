-- -------------------------------------------------------------------------- --
-- AutoBG: Unified Options Panel (Consolidated Battleground Command Center)   --
-- Engineered natively for World of Warcraft 1.12.1 (Enhanced Engine)        --
-- ClassicAPI v1.14.0+, SuperWoW v2.2+, NamPower v4.6.3+, UnitXP, DXVK       --
-- -------------------------------------------------------------------------- --

-- Strict Engine Dependency Guard (Mandatory ClassicAPI v1.14.0+ & SuperWoW v2.2+)
local MIN_CLASSIC_API = 11400

if not (CLASSIC_API_VERSION and SUPERWOW_VERSION) or 
   (type(CLASSIC_API_VERSION) == "number" and CLASSIC_API_VERSION < MIN_CLASSIC_API) then
	return
end

local Targets = AutoBG_Targets
local Spy = AutoBG_Spy
local BRACKETS = { 10, 15, 40 }
local selectedTab = 1
local selectedBracket = 10

-- -------------------------------------------------------------------------- --
-- UI Factory Helpers                                                         --
-- -------------------------------------------------------------------------- --
local function CreateCheckButton(name, parent, text, tooltip, onClick)
	local cb = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
	cb:SetWidth(20)
	cb:SetHeight(20)
	local label = _G[name .. "Text"] or cb:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	label:SetPoint("LEFT", cb, "RIGHT", 4, 1)
	label:SetText(text)
	cb.Label = label
	cb.tooltipText = tooltip

	cb:SetScript("OnClick", function()
		if onClick then onClick() end
	end)

	if tooltip then
		cb:SetScript("OnEnter", function()
			GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
			GameTooltip:SetText(this.tooltipText, 1, 1, 1, nil, 1)
			GameTooltip:Show()
		end)
		cb:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
	end

	return cb
end

local function CreateSlider(name, parent, text, minVal, maxVal, step, isPercent, onValChanged)
	local s = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
	s:SetWidth(170)
	s:SetHeight(16)
	s:SetMinMaxValues(minVal, maxVal)
	s:SetValueStep(step)
	_G[name .. "Low"]:SetText(tostring(minVal) .. (isPercent and "%" or ""))
	_G[name .. "High"]:SetText(tostring(maxVal) .. (isPercent and "%" or ""))
	_G[name .. "Text"]:SetText(text)
	s.ValueText = s:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	s.ValueText:SetPoint("LEFT", s, "RIGHT", 10, 0)
	s:SetScript("OnValueChanged", function()
		local val = math.floor(this:GetValue() + 0.5)
		s.ValueText:SetText(isPercent and (val .. "%") or tostring(val))
		if onValChanged then onValChanged(val) end
	end)
	return s
end

local function CreateSectionHeader(parent, text, x, y)
	local h = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	h:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	h:SetText(text)
	return h
end

-- -------------------------------------------------------------------------- --
-- Main Window Assembly                                                       --
-- -------------------------------------------------------------------------- --
local panel = CreateFrame("Frame", "AutoBG_OptionsPanel", UIParent)
BattlegroundTargets_OptionsFrame = panel -- Backwards compatibility alias
panel:SetWidth(500)
panel:SetHeight(554)
panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
panel:SetFrameStrata("DIALOG")
panel:SetToplevel(true)
panel:EnableMouse(true)
panel:SetMovable(true)
panel:SetClampedToScreen(true)
panel:RegisterForDrag("LeftButton")
panel:SetScript("OnDragStart", function() this:StartMoving() end)
panel:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
panel:Hide()

tinsert(UISpecialFrames, "AutoBG_OptionsPanel")

panel:SetBackdrop({
	bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
	edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
	tile = true, tileSize = 32, edgeSize = 32,
	insets = { left = 11, right = 12, top = 12, bottom = 11 }
})

local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOP", panel, "TOP", 0, -15)
title:SetText("AutoBG Settings")

local author = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
author:SetPoint("TOP", title, "BOTTOM", 0, -4)
author:SetText("Made by Fostercare5988")
author:SetTextColor(0.60, 0.60, 0.60)

local closeX = CreateFrame("Button", "AutoBG_OptionsCloseX", panel, "UIPanelCloseButton")
closeX:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -8)
closeX:SetScript("OnClick", function() panel:Hide() end)

-- Inner Card Framing (crisp border for tab content)
local innerCard = CreateFrame("Frame", "AutoBG_OptionsInnerCard", panel)
innerCard:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -86)
innerCard:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -14, 46)
innerCard:SetBackdrop({
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 12, edgeSize = 12,
	insets = { left = 3, right = 3, top = 3, bottom = 3 }
})
innerCard:SetBackdropColor(0.03, 0.03, 0.06, 0.85)
innerCard:SetBackdropBorderColor(0.25, 0.25, 0.35, 0.85)

-- Sub-panels
local panelGeneral = CreateFrame("Frame", "AutoBG_TabPanel_General", innerCard)
local panelTimers = CreateFrame("Frame", "AutoBG_TabPanel_Timers", innerCard)
local panelTargets = CreateFrame("Frame", "AutoBG_TabPanel_Targets", innerCard)
local panelSpy = CreateFrame("Frame", "AutoBG_TabPanel_Spy", innerCard)

local tabPanels = { panelGeneral, panelTimers, panelTargets, panelSpy }
for _, p in ipairs(tabPanels) do
	p:SetPoint("TOPLEFT", innerCard, "TOPLEFT", 6, -6)
	p:SetPoint("BOTTOMRIGHT", innerCard, "BOTTOMRIGHT", -6, 6)
	p:Hide()
end

-- -------------------------------------------------------------------------- --
-- Tab Buttons Bar (General, Timers & FC, Enemy Frames, Spy)                  --
-- -------------------------------------------------------------------------- --
local tabs = {}
local tabDefs = {
	{ id = 1, name = "General" },
	{ id = 2, name = "Timers & FC" },
	{ id = 3, name = "Enemy Frames" },
	{ id = 4, name = "Spy" },
}

local SelectTab -- forward declaration

for i, def in ipairs(tabDefs) do
	local tab = CreateFrame("Button", "AutoBG_OptionsTab" .. i, panel)
	tab.tabId = def.id
	tab:SetWidth(110)
	tab:SetHeight(24)
	tab:SetPoint("TOPLEFT", panel, "TOPLEFT", 16 + (i - 1) * 118, -58)
	tab:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 10, edgeSize = 10,
		insets = { left = 2, right = 2, top = 2, bottom = 2 }
	})
	tab.Text = tab:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	tab.Text:SetPoint("CENTER", 0, 0)
	tab.Text:SetText(def.name)

	tab:SetScript("OnClick", function()
		SelectTab(this.tabId)
	end)
	tabs[i] = tab
end

-- -------------------------------------------------------------------------- --
-- TAB 1: GENERAL (Automation, Queues, Alerts, Class Colors, Stances)         --
-- -------------------------------------------------------------------------- --
CreateSectionHeader(panelGeneral, "Automation & Queuing", 10, -8)

local cbAutoAccept = CreateCheckButton("AutoBG_Opt_AutoAccept", panelGeneral, "Auto-Accept Queue Pop", "Automatically accept battleground queue pops.", function()
	if AutoBG_Settings then AutoBG_Settings.AutoAccept = this:GetChecked() and true or false end
end)
cbAutoAccept:SetPoint("TOPLEFT", panelGeneral, "TOPLEFT", 10, -30)

local cbSkipAFK = CreateCheckButton("AutoBG_Opt_SkipAFK", panelGeneral, "Pause Auto-Enter if AFK", "Do not automatically enter battlegrounds if tagged as AFK.", function()
	if AutoBG_Settings then AutoBG_Settings.SkipIfAFK = this:GetChecked() and true or false end
end)
cbSkipAFK:SetPoint("TOPLEFT", cbAutoAccept, "BOTTOMLEFT", 0, -6)

local sliderAcceptDelay = CreateSlider("AutoBG_Opt_AcceptDelay", panelGeneral, "Enter Delay", 0, 70, 1, false, function(val)
	if AutoBG_Settings then
		AutoBG_Settings.AutoAcceptDelay = val
		if val == 0 then
			_G["AutoBG_Opt_AcceptDelayText"]:SetText("Enter Delay: Instant (0s)")
		else
			_G["AutoBG_Opt_AcceptDelayText"]:SetText("Enter Delay: " .. val .. "s")
		end
	end
end)
sliderAcceptDelay:SetPoint("TOPLEFT", cbSkipAFK, "BOTTOMLEFT", 4, -18)

local cbAutoLeave = CreateCheckButton("AutoBG_Opt_AutoLeave", panelGeneral, "Auto-Leave BG on End", "Automatically leave battlegrounds when match concludes.", function()
	if AutoBG_Settings then AutoBG_Settings.AutoLeave = this:GetChecked() and true or false end
end)
cbAutoLeave:SetPoint("TOPLEFT", sliderAcceptDelay, "BOTTOMLEFT", -4, -18)

local cbAutoRejoin = CreateCheckButton("AutoBG_Opt_AutoRejoin", panelGeneral, "Auto-Rejoin BG on Exit", "Automatically queue for the same Battleground after match exit via Battleground Finder.", function()
	if AutoBG_Settings then AutoBG_Settings.AutoRejoin = this:GetChecked() and true or false end
end)
cbAutoRejoin:SetPoint("TOPLEFT", cbAutoLeave, "BOTTOMLEFT", 0, -6)

local cbAutoQueue = CreateCheckButton("AutoBG_Opt_AutoQueue", panelGeneral, "Auto-Queue on Login", "Automatically queue for WSG, AB, and AV upon logging in or reloading.", function()
	if AutoBG_Settings then AutoBG_Settings.AutoQueueLogin = this:GetChecked() and true or false end
end)
cbAutoQueue:SetPoint("TOPLEFT", cbAutoRejoin, "BOTTOMLEFT", 0, -6)

local cbAutoRelease = CreateCheckButton("AutoBG_Opt_AutoRelease", panelGeneral, "Auto-Release Spirit", "Automatically release spirit upon dying in BG (skips if Soulstone/Ankh ready).", function()
	if AutoBG_Settings then AutoBG_Settings.AutoRelease = this:GetChecked() and true or false end
end)
cbAutoRelease:SetPoint("TOPLEFT", cbAutoQueue, "BOTTOMLEFT", 0, -6)

-- Column 2
CreateSectionHeader(panelGeneral, "Alerts & Visual Tweaks", 240, -8)

local cbSound = CreateCheckButton("AutoBG_Opt_Sound", panelGeneral, "Loud Sound Alerts", "Play a loud ready check sound when queues pop or end.", function()
	if AutoBG_Settings then AutoBG_Settings.NotifySound = this:GetChecked() and true or false end
end)
cbSound:SetPoint("TOPLEFT", panelGeneral, "TOPLEFT", 240, -30)

local cbFlash = CreateCheckButton("AutoBG_Opt_Flash", panelGeneral, "Taskbar Flashing", "Flash game window in Windows taskbar on queue pop.", function()
	if AutoBG_Settings then AutoBG_Settings.FlashTaskbar = this:GetChecked() and true or false end
end)
cbFlash:SetPoint("TOPLEFT", cbSound, "BOTTOMLEFT", 0, -6)

local cbChatMsg = CreateCheckButton("AutoBG_Opt_ChatMsg", panelGeneral, "Chat Notifications", "Display status messages in chat for queues, joins, and exits.", function()
	if AutoBG_Settings then AutoBG_Settings.ChatMessages = this:GetChecked() and true or false end
end)
cbChatMsg:SetPoint("TOPLEFT", cbFlash, "BOTTOMLEFT", 0, -6)

local cbScoreColor = CreateCheckButton("AutoBG_Opt_ScoreColor", panelGeneral, "Scoreboard Class Colors", "Color player names on scoreboard by character class.", function()
	if AutoBG_Settings then AutoBG_Settings.ScoreColor = this:GetChecked() and true or false end
end)
cbScoreColor:SetPoint("TOPLEFT", cbChatMsg, "BOTTOMLEFT", 0, -6)

local cbHideCastbar = CreateCheckButton("AutoBG_Opt_HideCastbar", panelGeneral, "Hide Default Castbar", "Hide default Blizzard cast bar (useful if using custom castbars).", function()
	if AutoBG_Settings then
		AutoBG_Settings.HideCastbar = this:GetChecked() and true or false
		if AutoBG_Settings.HideCastbar and CastingBarFrame then
			CastingBarFrame:UnregisterAllEvents()
			CastingBarFrame:Hide()
		end
	end
end)
cbHideCastbar:SetPoint("TOPLEFT", cbScoreColor, "BOTTOMLEFT", 0, -6)

local cbHideStanceBar = CreateCheckButton("AutoBG_Opt_HideStanceBar", panelGeneral, "Hide Stealth/Stance Bar", "Hide default Blizzard stance/shapeshift bar (Stealth, Stances, Forms).", function()
	if AutoBG_Settings then
		AutoBG_Settings.HideStanceBar = this:GetChecked() and true or false
		if AutoBG_UpdateStanceBar then AutoBG_UpdateStanceBar() end
	end
end)
cbHideStanceBar:SetPoint("TOPLEFT", cbHideCastbar, "BOTTOMLEFT", 0, -6)

local btnTestSound = CreateFrame("Button", "AutoBG_BtnTestSound", panelGeneral, "UIPanelButtonTemplate")
btnTestSound:SetWidth(110)
btnTestSound:SetHeight(22)
btnTestSound:SetPoint("TOPLEFT", cbHideStanceBar, "BOTTOMLEFT", 4, -14)
btnTestSound:SetText("Test Sound")
btnTestSound:SetScript("OnClick", function()
	if AutoBG_PlayNotificationSound then
		AutoBG_PlayNotificationSound()
	else
		PlaySound("ReadyCheck")
	end
end)

-- -------------------------------------------------------------------------- --
-- TAB 2: TIMERS & FC (Node Timers, Respawn, Spirit Healer, Flag Carrier HUD) --
-- -------------------------------------------------------------------------- --
CreateSectionHeader(panelTimers, "Objective Countdowns", 10, -8)

local cbABTimers = CreateCheckButton("AutoBG_Opt_ABTimers", panelTimers, "Arathi Basin Nodes", "Show 60s node capture countdowns in Arathi Basin.", function()
	if AutoBG_Settings then AutoBG_Settings.ABTimers = this:GetChecked() and true or false end
end)
cbABTimers:SetPoint("TOPLEFT", panelTimers, "TOPLEFT", 10, -30)

local cbAVTimers = CreateCheckButton("AutoBG_Opt_AVTimers", panelTimers, "Alterac Valley Nodes", "Show 5m bunker/tower capture countdowns in Alterac Valley.", function()
	if AutoBG_Settings then AutoBG_Settings.AVTimers = this:GetChecked() and true or false end
end)
cbAVTimers:SetPoint("TOPLEFT", cbABTimers, "BOTTOMLEFT", 0, -6)

local cbWSGTimers = CreateCheckButton("AutoBG_Opt_WSGTimers", panelTimers, "WSG Flag Respawns", "Show 23s flag respawn countdowns in Warsong Gulch.", function()
	if AutoBG_Settings then AutoBG_Settings.WSGTimers = this:GetChecked() and true or false end
end)
cbWSGTimers:SetPoint("TOPLEFT", cbAVTimers, "BOTTOMLEFT", 0, -6)

local cbRessTimer = CreateCheckButton("AutoBG_Opt_RessTimer", panelTimers, "Spirit Healer Timer", "Show synced 30s Spirit Healer resurrection wave timer.", function()
	if AutoBG_Settings then AutoBG_Settings.RessTimer = this:GetChecked() and true or false end
end)
cbRessTimer:SetPoint("TOPLEFT", cbWSGTimers, "BOTTOMLEFT", 0, -6)

local cbQueueTimers = CreateCheckButton("AutoBG_Opt_QueueTimers", panelTimers, "BG Queue Timers", "Show on-screen timer for active BG queue wait times.", function()
	if AutoBG_Settings then AutoBG_Settings.QueueTimers = this:GetChecked() and true or false end
end)
cbQueueTimers:SetPoint("TOPLEFT", cbRessTimer, "BOTTOMLEFT", 0, -6)

local cbNodeColors = CreateCheckButton("AutoBG_Opt_NodeColors", panelTimers, "Faction Node Colors", "Color-code AB and AV node timers (Red = Horde, Blue = Alliance).", function()
	if AutoBG_Settings then AutoBG_Settings.NodeColors = this:GetChecked() and true or false end
end)
cbNodeColors:SetPoint("TOPLEFT", cbQueueTimers, "BOTTOMLEFT", 0, -6)

-- Column 2
CreateSectionHeader(panelTimers, "WSG Flag Carrier HUD", 240, -8)

local cbFCFrame = CreateCheckButton("AutoBG_Opt_FCFrame", panelTimers, "WSG Flag Carrier Frames", "Show clickable HUD frames to target and track WSG flag carriers.", function()
	if AutoBG_Settings then AutoBG_Settings.FCFrame = this:GetChecked() and true or false end
end)
cbFCFrame:SetPoint("TOPLEFT", panelTimers, "TOPLEFT", 240, -30)

local fcInfo = panelTimers:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
fcInfo:SetPoint("TOPLEFT", cbFCFrame, "BOTTOMLEFT", 0, -8)
fcInfo:SetPoint("RIGHT", panelTimers, "RIGHT", -12, 0)
fcInfo:SetJustifyH("LEFT")
fcInfo:SetText("HUD display for Warsong Gulch:\n- Left-Click to Target Carrier\n- Right-Click to Focus Carrier\n- Live Health & Authentic Flag Icons\n- Draggable anywhere on screen")

local btnTestTimers = CreateFrame("Button", "AutoBG_BtnTestTimers", panelTimers, "UIPanelButtonTemplate")
btnTestTimers:SetWidth(140)
btnTestTimers:SetHeight(22)
btnTestTimers:SetPoint("TOPLEFT", fcInfo, "BOTTOMLEFT", 0, -18)
btnTestTimers:SetText("Toggle Timers Test")
btnTestTimers:SetScript("OnClick", function()
	if AutoBG_Settings then
		AutoBG_Settings.TestAllTimers = not AutoBG_Settings.TestAllTimers
		if AutoBG_LoadTimerPositions then AutoBG_LoadTimerPositions() end
		this:SetText(AutoBG_Settings.TestAllTimers and "Hide Timers Test" or "Toggle Timers Test")
	end
end)

local btnResetTimersPos = CreateFrame("Button", "AutoBG_BtnResetTimersPos", panelTimers, "UIPanelButtonTemplate")
btnResetTimersPos:SetWidth(140)
btnResetTimersPos:SetHeight(22)
btnResetTimersPos:SetPoint("TOPLEFT", btnTestTimers, "BOTTOMLEFT", 0, -8)
btnResetTimersPos:SetText("Reset Timers Pos")
btnResetTimersPos:SetScript("OnClick", function()
	if AutoBG_ResetTimerPositions then AutoBG_ResetTimerPositions() end
	if AutoBG_ResetFCPositions then AutoBG_ResetFCPositions() end
	if DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00AutoBG:|r Timers and FC HUD positions reset.")
	end
end)

-- -------------------------------------------------------------------------- --
-- TAB 3: ENEMY FRAMES (BattlegroundTargets Engine & Brackets)                --
-- -------------------------------------------------------------------------- --
CreateSectionHeader(panelTargets, "Enemy Frames Configuration", 10, -8)

-- Bracket selector buttons (10v10, 15v15, 40v40)
local bracketButtons = {}
local function UpdateTargetsWidgets(size) end -- forward declaration

local function SelectBracket(size)
	selectedBracket = size
	for _, b in ipairs(bracketButtons) do
		if b.size == size then
			b:SetBackdropColor(0.70, 0.15, 0.15, 1.0)
			b:SetBackdropBorderColor(1.0, 0.35, 0.35, 1.0)
			b.Text:SetTextColor(1, 1, 1)
		else
			b:SetBackdropColor(0.10, 0.10, 0.14, 0.90)
			b:SetBackdropBorderColor(0.25, 0.25, 0.35, 0.85)
			b.Text:SetTextColor(0.8, 0.8, 0.8)
		end
	end
	UpdateTargetsWidgets(size)
	if Targets and Targets.EnableConfigMode then
		Targets:EnableConfigMode(size)
	end
end

for i, sz in ipairs(BRACKETS) do
	local b = CreateFrame("Button", "AutoBG_Targets_BracketBtn" .. sz, panelTargets)
	b.size = sz
	b:SetWidth(65)
	b:SetHeight(20)
	b:SetPoint("TOPLEFT", panelTargets, "TOPLEFT", 10 + (i - 1) * 72, -30)
	b:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 10, edgeSize = 10,
		insets = { left = 2, right = 2, top = 2, bottom = 2 }
	})
	b.Text = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	b.Text:SetPoint("CENTER", 0, 0)
	b.Text:SetText(sz .. "v" .. sz)
	b:SetScript("OnClick", function()
		SelectBracket(this.size)
	end)
	bracketButtons[i] = b
end

-- Targets Checkboxes (Column 1)
local cbTgtEnable = CreateCheckButton("AutoBG_Tgt_Enable", panelTargets, "Enable Bracket", "Show enemy target frames for this battleground size.", function()
	local o = AutoBG_Settings and AutoBG_Settings.Targets
	if o and o.EnableBracket then
		o.EnableBracket[selectedBracket] = this:GetChecked() and true or false
		if Targets and Targets.SetupButtonLayout then Targets:SetupButtonLayout(selectedBracket) end
	end
end)
cbTgtEnable:SetPoint("TOPLEFT", panelTargets, "TOPLEFT", 10, -58)

local cbTgtIndependentPos = CreateCheckButton("AutoBG_Tgt_IndependentPos", panelTargets, "Independent Positioning", "Store separate frame screen coordinates for this bracket.", function()
	local o = AutoBG_Settings and AutoBG_Settings.Targets
	if o and o.IndependentPositioning then
		o.IndependentPositioning[selectedBracket] = this:GetChecked() and true or false
		if Targets and Targets.Frame_SetupPosition then Targets:Frame_SetupPosition("AutoBG_TargetsMainFrame") end
	end
end)
cbTgtIndependentPos:SetPoint("TOPLEFT", cbTgtEnable, "BOTTOMLEFT", 0, -6)

local cbTgtHideRealm = CreateCheckButton("AutoBG_Tgt_HideRealm", panelTargets, "Hide Realm Name", "Strip realm suffix from enemy player names.", function()
	local o = AutoBG_Settings and AutoBG_Settings.Targets
	if o and o.ButtonHideRealm then
		o.ButtonHideRealm[selectedBracket] = this:GetChecked() and true or false
		if Targets and Targets.isConfig and Targets.RenderRoster then Targets:RenderRoster() end
	end
end)
cbTgtHideRealm:SetPoint("TOPLEFT", cbTgtIndependentPos, "BOTTOMLEFT", 0, -6)

local cbTgtFC = CreateCheckButton("AutoBG_Tgt_ShowFC", panelTargets, "Flag Carrier Icon", "Show flag icon on enemy flag carrier row in Warsong Gulch.", function()
	local o = AutoBG_Settings and AutoBG_Settings.Targets
	if o and o.ShowFlagCarrier then
		o.ShowFlagCarrier[selectedBracket] = this:GetChecked() and true or false
		if Targets and Targets.isConfig and Targets.RenderRoster then Targets:RenderRoster() end
	end
end)
cbTgtFC:SetPoint("TOPLEFT", cbTgtHideRealm, "BOTTOMLEFT", 0, -6)

local cbTgtHealthBar = CreateCheckButton("AutoBG_Tgt_HealthBar", panelTargets, "Show Health Bar", "Display class-colored health bar.", function()
	local o = AutoBG_Settings and AutoBG_Settings.Targets
	if o and o.ButtonShowHealthBar then
		o.ButtonShowHealthBar[selectedBracket] = this:GetChecked() and true or false
		if Targets and Targets.isConfig and Targets.RenderRoster then Targets:RenderRoster() end
	end
end)
cbTgtHealthBar:SetPoint("TOPLEFT", cbTgtFC, "BOTTOMLEFT", 0, -6)

local cbTgtHealthText = CreateCheckButton("AutoBG_Tgt_HealthText", panelTargets, "Show Health Percent", "Display health percentage number on rows.", function()
	local o = AutoBG_Settings and AutoBG_Settings.Targets
	if o and o.ButtonShowHealthText then
		o.ButtonShowHealthText[selectedBracket] = this:GetChecked() and true or false
		if Targets and Targets.isConfig and Targets.RenderRoster then Targets:RenderRoster() end
	end
end)
cbTgtHealthText:SetPoint("TOPLEFT", cbTgtHealthBar, "BOTTOMLEFT", 0, -6)

local cbTgtStealthIcon = CreateCheckButton("AutoBG_Tgt_StealthIcon", panelTargets, "Show Stealth Icon", "Show icon for Prowl, Stealth, Vanish, and Invisibility.", function()
	local o = AutoBG_Settings and AutoBG_Settings.Targets
	if o and o.ShowStealthIcon then
		o.ShowStealthIcon[selectedBracket] = this:GetChecked() and true or false
		if Targets and Targets.isConfig and Targets.RenderRoster then Targets:RenderRoster() end
	end
end)
cbTgtStealthIcon:SetPoint("TOPLEFT", cbTgtHealthText, "BOTTOMLEFT", 0, -6)

local cbTgtStealthText = CreateCheckButton("AutoBG_Tgt_StealthText", panelTargets, "Show Stealth Text", "Display STEALTH / PROWL tag text.", function()
	local o = AutoBG_Settings and AutoBG_Settings.Targets
	if o and o.ShowStealthText then
		o.ShowStealthText[selectedBracket] = this:GetChecked() and true or false
		if Targets and Targets.isConfig and Targets.RenderRoster then Targets:RenderRoster() end
	end
end)
cbTgtStealthText:SetPoint("TOPLEFT", cbTgtStealthIcon, "BOTTOMLEFT", 0, -6)

local cbTgtDim = CreateCheckButton("AutoBG_Tgt_DimStealth", panelTargets, "Dim Stealthed Rows", "Dim the alpha of stealthed enemy rows.", function()
	local o = AutoBG_Settings and AutoBG_Settings.Targets
	if o and o.DimStealthed then
		o.DimStealthed[selectedBracket] = this:GetChecked() and true or false
		if Targets and Targets.isConfig and Targets.RenderRoster then Targets:RenderRoster() end
	end
end)
cbTgtDim:SetPoint("TOPLEFT", cbTgtStealthText, "BOTTOMLEFT", 0, -6)

local cbTgtTrinket = CreateCheckButton("AutoBG_Tgt_Trinket", panelTargets, "Show PvP Trinket CD", "Track and display enemy PvP trinket 3-minute cooldown timer.", function()
	local o = AutoBG_Settings and AutoBG_Settings.Targets
	if o and o.ShowTrinket then
		o.ShowTrinket[selectedBracket] = this:GetChecked() and true or false
		if Targets and Targets.SetupButtonLayout then Targets:SetupButtonLayout(selectedBracket) end
		if Targets and Targets.isConfig and Targets.RenderRoster then Targets:RenderRoster() end
	end
end)
cbTgtTrinket:SetPoint("TOPLEFT", cbTgtDim, "BOTTOMLEFT", 0, -6)

local cbTgtTrinketLeft = CreateCheckButton("AutoBG_Tgt_TrinketLeft", panelTargets, "Trinket On Left Side", "Anchor the PvP trinket icon to the left side of the row instead of the right.", function()
	local o = AutoBG_Settings and AutoBG_Settings.Targets
	if o then
		o.TrinketPos = this:GetChecked() and "LEFT" or "RIGHT"
		if Targets and Targets.SetupButtonLayout then Targets:SetupButtonLayout(selectedBracket) end
		if Targets and Targets.isConfig and Targets.RenderRoster then Targets:RenderRoster() end
	end
end)
cbTgtTrinketLeft:SetPoint("TOPLEFT", cbTgtTrinket, "BOTTOMLEFT", 0, -6)

-- Targets Sliders (Column 2)
local sliderTgtFontSize = CreateSlider("AutoBG_Tgt_FontSize", panelTargets, "Text Size", 6, 20, 1, false, function(val)
	local o = AutoBG_Settings and AutoBG_Settings.Targets
	if o and o.ButtonFontSize then
		o.ButtonFontSize[selectedBracket] = val
		if Targets and Targets.SetupButtonLayout then Targets:SetupButtonLayout(selectedBracket) end
		if Targets and Targets.isConfig and Targets.RenderRoster then Targets:RenderRoster() end
	end
end)
sliderTgtFontSize:SetPoint("TOPLEFT", panelTargets, "TOPLEFT", 240, -58)

local sliderTgtScale = CreateSlider("AutoBG_Tgt_Scale", panelTargets, "Scale", 50, 200, 5, true, function(val)
	local o = AutoBG_Settings and AutoBG_Settings.Targets
	if o and o.ButtonScale then
		o.ButtonScale[selectedBracket] = val / 100
		if Targets and Targets.SetupButtonLayout then Targets:SetupButtonLayout(selectedBracket) end
	end
end)
sliderTgtScale:SetPoint("TOPLEFT", sliderTgtFontSize, "BOTTOMLEFT", 0, -18)

local sliderTgtWidth = CreateSlider("AutoBG_Tgt_Width", panelTargets, "Width", 60, 300, 5, false, function(val)
	local o = AutoBG_Settings and AutoBG_Settings.Targets
	if o and o.ButtonWidth then
		o.ButtonWidth[selectedBracket] = val
		if Targets and Targets.SetupButtonLayout then Targets:SetupButtonLayout(selectedBracket) end
		if Targets and Targets.isConfig and Targets.RenderRoster then Targets:RenderRoster() end
	end
end)
sliderTgtWidth:SetPoint("TOPLEFT", sliderTgtScale, "BOTTOMLEFT", 0, -18)

local sliderTgtHeight = CreateSlider("AutoBG_Tgt_Height", panelTargets, "Height", 10, 40, 1, false, function(val)
	local o = AutoBG_Settings and AutoBG_Settings.Targets
	if o and o.ButtonHeight then
		o.ButtonHeight[selectedBracket] = val
		if Targets and Targets.SetupButtonLayout then Targets:SetupButtonLayout(selectedBracket) end
		if Targets and Targets.isConfig and Targets.RenderRoster then Targets:RenderRoster() end
	end
end)
sliderTgtHeight:SetPoint("TOPLEFT", sliderTgtWidth, "BOTTOMLEFT", 0, -18)

local btnTgtTogglePreview = CreateFrame("Button", "AutoBG_BtnTgtPreview", panelTargets, "UIPanelButtonTemplate")
btnTgtTogglePreview:SetWidth(110)
btnTgtTogglePreview:SetHeight(22)
btnTgtTogglePreview:SetPoint("TOPLEFT", sliderTgtHeight, "BOTTOMLEFT", 0, -16)
btnTgtTogglePreview:SetText("Toggle Preview")
btnTgtTogglePreview:SetScript("OnClick", function()
	if Targets and Targets.ToggleTestMode then
		Targets:ToggleTestMode(selectedBracket)
		this:SetText(Targets.isConfig and "Hide Preview" or "Toggle Preview")
	end
end)

local btnTgtResetPos = CreateFrame("Button", "AutoBG_BtnTgtResetPos", panelTargets, "UIPanelButtonTemplate")
btnTgtResetPos:SetWidth(110)
btnTgtResetPos:SetHeight(22)
btnTgtResetPos:SetPoint("LEFT", btnTgtTogglePreview, "RIGHT", 8, 0)
btnTgtResetPos:SetText("Reset Pos")
btnTgtResetPos:SetScript("OnClick", function()
	if Targets and Targets.ResetPosition then
		Targets:ResetPosition(selectedBracket)
		if DEFAULT_CHAT_FRAME then
			DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00AutoBG:|r Enemy target frames position reset.")
		end
	end
end)

UpdateTargetsWidgets = function(sz)
	if Targets and Targets.EnsureOptions then Targets:EnsureOptions() end
	local o = AutoBG_Settings and AutoBG_Settings.Targets
	if not o then return end

	cbTgtEnable:SetChecked(o.EnableBracket and o.EnableBracket[sz] and 1 or nil)
	cbTgtIndependentPos:SetChecked(o.IndependentPositioning and o.IndependentPositioning[sz] and 1 or nil)
	cbTgtHideRealm:SetChecked(o.ButtonHideRealm and o.ButtonHideRealm[sz] and 1 or nil)

	if sz == 10 then
		cbTgtFC:Show()
		cbTgtFC:SetChecked(o.ShowFlagCarrier and o.ShowFlagCarrier[sz] and 1 or nil)
		cbTgtHealthBar:ClearAllPoints()
		cbTgtHealthBar:SetPoint("TOPLEFT", cbTgtFC, "BOTTOMLEFT", 0, -6)
	else
		cbTgtFC:Hide()
		cbTgtHealthBar:ClearAllPoints()
		cbTgtHealthBar:SetPoint("TOPLEFT", cbTgtHideRealm, "BOTTOMLEFT", 0, -6)
	end

	cbTgtHealthBar:SetChecked(o.ButtonShowHealthBar and o.ButtonShowHealthBar[sz] and 1 or nil)
	cbTgtHealthText:SetChecked(o.ButtonShowHealthText and o.ButtonShowHealthText[sz] and 1 or nil)
	cbTgtStealthIcon:SetChecked(o.ShowStealthIcon and o.ShowStealthIcon[sz] and 1 or nil)
	cbTgtStealthText:SetChecked(o.ShowStealthText and o.ShowStealthText[sz] and 1 or nil)
	cbTgtDim:SetChecked(o.DimStealthed and o.DimStealthed[sz] and 1 or nil)
	cbTgtTrinket:SetChecked(o.ShowTrinket and o.ShowTrinket[sz] and 1 or nil)
	cbTgtTrinketLeft:SetChecked(o.TrinketPos == "LEFT" and 1 or nil)

	local fontSize = (o.ButtonFontSize and o.ButtonFontSize[sz]) or 10
	sliderTgtFontSize:SetValue(fontSize)
	sliderTgtFontSize.ValueText:SetText(tostring(fontSize))

	local scalePct = math.floor(((o.ButtonScale and o.ButtonScale[sz]) or 1.0) * 100)
	sliderTgtScale:SetValue(scalePct)
	sliderTgtScale.ValueText:SetText(scalePct .. "%")

	local width = (o.ButtonWidth and o.ButtonWidth[sz]) or 150
	sliderTgtWidth:SetValue(width)
	sliderTgtWidth.ValueText:SetText(tostring(width))

	local height = (o.ButtonHeight and o.ButtonHeight[sz]) or 20
	sliderTgtHeight:SetValue(height)
	sliderTgtHeight.ValueText:SetText(tostring(height))

	if Targets and Targets.isConfig then
		btnTgtTogglePreview:SetText("Hide Preview")
	else
		btnTgtTogglePreview:SetText("Toggle Preview")
	end
end

-- -------------------------------------------------------------------------- --
-- TAB 4: SPY (Open-World Enemy Radar, Telemetry & Alerts)                    --
-- -------------------------------------------------------------------------- --
CreateSectionHeader(panelSpy, "Open-World Enemy Radar (Spy)", 10, -8)

local cbSpyEnable = CreateCheckButton("AutoBG_Spy_Enable", panelSpy, "Enable Open-World Spy", "Show nearby hostile player tracker in open world.", function()
	if not AutoBG_Settings then AutoBG_Settings = {} end
	AutoBG_Settings.Spy = AutoBG_Settings.Spy or {}
	AutoBG_Settings.Spy.Enabled = this:GetChecked() and true or false
	if Spy and Spy.RenderRows then Spy:RenderRows() end
end)
cbSpyEnable:SetPoint("TOPLEFT", panelSpy, "TOPLEFT", 10, -30)

local cbSpySound = CreateCheckButton("AutoBG_Spy_SoundAlert", panelSpy, "Sound on Enemy Detected", "Play alert sound when a hostile enemy enters radar range.", function()
	if not AutoBG_Settings then AutoBG_Settings = {} end
	AutoBG_Settings.Spy = AutoBG_Settings.Spy or {}
	AutoBG_Settings.Spy.SoundAlert = this:GetChecked() and true or false
end)
cbSpySound:SetPoint("TOPLEFT", cbSpyEnable, "BOTTOMLEFT", 0, -6)

local cbSpyStealth = CreateCheckButton("AutoBG_Spy_StealthAlert", panelSpy, "Sound on Stealth Detected", "Play stealth alert sound when a stealthed enemy or stealth cast is detected.", function()
	if not AutoBG_Settings then AutoBG_Settings = {} end
	AutoBG_Settings.Spy = AutoBG_Settings.Spy or {}
	AutoBG_Settings.Spy.StealthAlert = this:GetChecked() and true or false
end)
cbSpyStealth:SetPoint("TOPLEFT", cbSpySound, "BOTTOMLEFT", 0, -6)

local cbSpyAutoHide = CreateCheckButton("AutoBG_Spy_AutoHide", panelSpy, "Auto-Hide When Empty", "Hide the Spy frame completely when no enemies are tracked.", function()
	if not AutoBG_Settings then AutoBG_Settings = {} end
	AutoBG_Settings.Spy = AutoBG_Settings.Spy or {}
	AutoBG_Settings.Spy.AutoHide = this:GetChecked() and true or false
	if Spy and Spy.RenderRows then Spy:RenderRows() end
end)
cbSpyAutoHide:SetPoint("TOPLEFT", cbSpyStealth, "BOTTOMLEFT", 0, -6)

local sliderSpyTimeout = CreateSlider("AutoBG_Spy_Timeout", panelSpy, "Inactivity Timeout (sec)", 10, 120, 5, false, function(val)
	if not AutoBG_Settings then AutoBG_Settings = {} end
	AutoBG_Settings.Spy = AutoBG_Settings.Spy or {}
	AutoBG_Settings.Spy.Timeout = val
end)
sliderSpyTimeout:SetPoint("TOPLEFT", cbSpyAutoHide, "BOTTOMLEFT", 4, -18)

local sliderSpyMaxRows = CreateSlider("AutoBG_Spy_MaxRows", panelSpy, "Max Enemies Displayed", 3, 10, 1, false, function(val)
	if not AutoBG_Settings then AutoBG_Settings = {} end
	AutoBG_Settings.Spy = AutoBG_Settings.Spy or {}
	AutoBG_Settings.Spy.MaxRows = val
	if Spy and Spy.RenderRows then Spy:RenderRows() end
end)
sliderSpyMaxRows:SetPoint("TOPLEFT", sliderSpyTimeout, "BOTTOMLEFT", 0, -18)

local sliderSpyScale = CreateSlider("AutoBG_Spy_Scale", panelSpy, "Spy Frame Scale", 50, 150, 5, true, function(val)
	if not AutoBG_Settings then AutoBG_Settings = {} end
	AutoBG_Settings.Spy = AutoBG_Settings.Spy or {}
	AutoBG_Settings.Spy.Scale = val / 100
	if Spy and Spy.ApplyScale then Spy:ApplyScale() end
end)
sliderSpyScale:SetPoint("TOPLEFT", sliderSpyMaxRows, "BOTTOMLEFT", 0, -18)

-- Spy Action Buttons
local btnSpyTest = CreateFrame("Button", "AutoBG_BtnSpyTest", panelSpy, "UIPanelButtonTemplate")
btnSpyTest:SetWidth(95)
btnSpyTest:SetHeight(22)
btnSpyTest:SetPoint("TOPLEFT", sliderSpyScale, "BOTTOMLEFT", 0, -16)
btnSpyTest:SetText("Test Spy")
btnSpyTest:SetScript("OnClick", function()
	if Spy and Spy.ToggleTestMode then
		Spy:ToggleTestMode()
		this:SetText(Spy.isTestMode and "Hide Test" or "Test Spy")
	end
end)

local btnSpyClear = CreateFrame("Button", "AutoBG_BtnSpyClear", panelSpy, "UIPanelButtonTemplate")
btnSpyClear:SetWidth(95)
btnSpyClear:SetHeight(22)
btnSpyClear:SetPoint("LEFT", btnSpyTest, "RIGHT", 6, 0)
btnSpyClear:SetText("Clear List")
btnSpyClear:SetScript("OnClick", function()
	if Spy and Spy.ClearHistory then Spy:ClearHistory() end
end)

local btnSpyResetPos = CreateFrame("Button", "AutoBG_BtnSpyResetPos", panelSpy, "UIPanelButtonTemplate")
btnSpyResetPos:SetWidth(95)
btnSpyResetPos:SetHeight(22)
btnSpyResetPos:SetPoint("LEFT", btnSpyClear, "RIGHT", 6, 0)
btnSpyResetPos:SetText("Reset Pos")
btnSpyResetPos:SetScript("OnClick", function()
	if Spy and Spy.ResetPosition then
		Spy:ResetPosition()
		if DEFAULT_CHAT_FRAME then
			DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00AutoBG:|r Spy frame position reset.")
		end
	end
end)

local btnSpyTestSoundDetect = CreateFrame("Button", "AutoBG_BtnSpyTestSoundDetect", panelSpy, "UIPanelButtonTemplate")
btnSpyTestSoundDetect:SetWidth(110)
btnSpyTestSoundDetect:SetHeight(22)
btnSpyTestSoundDetect:SetPoint("TOPLEFT", btnSpyTest, "BOTTOMLEFT", 0, -8)
btnSpyTestSoundDetect:SetText("Test Detect")
btnSpyTestSoundDetect:SetScript("OnClick", function()
	if Spy and Spy.PlayEnemyDetectedSound then
		Spy:PlayEnemyDetectedSound()
	else
		PlaySoundFile([[Interface\AddOns\AutoBG\Sounds\detected-nearby.mp3]], "Master")
	end
end)

local btnSpyTestSoundStealth = CreateFrame("Button", "AutoBG_BtnSpyTestSoundStealth", panelSpy, "UIPanelButtonTemplate")
btnSpyTestSoundStealth:SetWidth(110)
btnSpyTestSoundStealth:SetHeight(22)
btnSpyTestSoundStealth:SetPoint("LEFT", btnSpyTestSoundDetect, "RIGHT", 6, 0)
btnSpyTestSoundStealth:SetText("Test Stealth")
btnSpyTestSoundStealth:SetScript("OnClick", function()
	if Spy and Spy.PlayStealthDetectedSound then
		Spy:PlayStealthDetectedSound()
	else
		PlaySoundFile([[Interface\AddOns\AutoBG\Sounds\detected-stealth.mp3]], "Master")
	end
end)

local function UpdateSpyWidgets()
	local opt = AutoBG_Settings and AutoBG_Settings.Spy
	if not opt then return end

	cbSpyEnable:SetChecked(opt.Enabled and 1 or nil)
	cbSpySound:SetChecked(opt.SoundAlert and 1 or nil)
	cbSpyStealth:SetChecked(opt.StealthAlert and 1 or nil)
	cbSpyAutoHide:SetChecked(opt.AutoHide and 1 or nil)

	local timeout = opt.Timeout or 30
	sliderSpyTimeout:SetValue(timeout)
	sliderSpyTimeout.ValueText:SetText(tostring(timeout))

	local maxRows = opt.MaxRows or 5
	sliderSpyMaxRows:SetValue(maxRows)
	sliderSpyMaxRows.ValueText:SetText(tostring(maxRows))

	local scalePct = math.floor((opt.Scale or 1.0) * 100)
	sliderSpyScale:SetValue(scalePct)
	sliderSpyScale.ValueText:SetText(scalePct .. "%")

	if Spy and Spy.isTestMode then
		btnSpyTest:SetText("Hide Test")
	else
		btnSpyTest:SetText("Test Spy")
	end
end

-- -------------------------------------------------------------------------- --
-- Tab Selection & Universal Refresh                                          --
-- -------------------------------------------------------------------------- --
SelectTab = function(tabId)
	selectedTab = tabId
	for _, tab in ipairs(tabs) do
		if tab.tabId == tabId then
			tab:SetBackdropColor(0.70, 0.15, 0.15, 1.0)
			tab:SetBackdropBorderColor(1.0, 0.35, 0.35, 1.0)
			tab.Text:SetTextColor(1, 1, 1)
		else
			tab:SetBackdropColor(0.10, 0.10, 0.14, 0.90)
			tab:SetBackdropBorderColor(0.25, 0.25, 0.35, 0.85)
			tab.Text:SetTextColor(0.8, 0.8, 0.8)
		end
	end

	for i, p in ipairs(tabPanels) do
		if i == tabId then
			p:Show()
		else
			p:Hide()
		end
	end

	if tabId == 1 then
		-- General
		if AutoBG_Settings then
			cbAutoAccept:SetChecked(AutoBG_Settings.AutoAccept and 1 or nil)
			cbSkipAFK:SetChecked((AutoBG_Settings.SkipIfAFK ~= false) and 1 or nil)
			local delay = AutoBG_Settings.AutoAcceptDelay or 0
			sliderAcceptDelay:SetValue(delay)
			sliderAcceptDelay.ValueText:SetText(delay == 0 and "Instant (0s)" or (delay .. "s"))
			cbAutoLeave:SetChecked(AutoBG_Settings.AutoLeave and 1 or nil)
			cbAutoRejoin:SetChecked(AutoBG_Settings.AutoRejoin and 1 or nil)
			cbAutoQueue:SetChecked(AutoBG_Settings.AutoQueueLogin and 1 or nil)
			cbAutoRelease:SetChecked(AutoBG_Settings.AutoRelease and 1 or nil)

			cbSound:SetChecked(AutoBG_Settings.NotifySound and 1 or nil)
			cbFlash:SetChecked(AutoBG_Settings.FlashTaskbar and 1 or nil)
			cbChatMsg:SetChecked(AutoBG_Settings.ChatMessages and 1 or nil)
			cbScoreColor:SetChecked(AutoBG_Settings.ScoreColor and 1 or nil)
			cbHideCastbar:SetChecked(AutoBG_Settings.HideCastbar and 1 or nil)
			cbHideStanceBar:SetChecked(AutoBG_Settings.HideStanceBar and 1 or nil)
		end
	elseif tabId == 2 then
		-- Timers & FC
		if AutoBG_Settings then
			cbABTimers:SetChecked(AutoBG_Settings.ABTimers and 1 or nil)
			cbAVTimers:SetChecked(AutoBG_Settings.AVTimers and 1 or nil)
			cbWSGTimers:SetChecked(AutoBG_Settings.WSGTimers and 1 or nil)
			cbRessTimer:SetChecked(AutoBG_Settings.RessTimer and 1 or nil)
			cbQueueTimers:SetChecked(AutoBG_Settings.QueueTimers and 1 or nil)
			cbNodeColors:SetChecked(AutoBG_Settings.NodeColors and 1 or nil)
			cbFCFrame:SetChecked(AutoBG_Settings.FCFrame and 1 or nil)
			btnTestTimers:SetText(AutoBG_Settings.TestAllTimers and "Hide Timers Test" or "Toggle Timers Test")
		end
	elseif tabId == 3 then
		-- Enemy Frames
		SelectBracket(selectedBracket)
	elseif tabId == 4 then
		-- Spy
		UpdateSpyWidgets()
	end
end

function AutoBG_Options_Refresh()
	SelectTab(selectedTab)
end

panel:SetScript("OnShow", function()
	AutoBG_Options_Refresh()
end)

-- -------------------------------------------------------------------------- --
-- Bottom Action Bar (Test All Frames, Reset Positions, Close)                --
-- -------------------------------------------------------------------------- --
local btnTestAll = CreateFrame("Button", "AutoBG_BtnTestAll", panel, "UIPanelButtonTemplate")
btnTestAll:SetWidth(130)
btnTestAll:SetHeight(24)
btnTestAll:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 18, 14)
btnTestAll:SetText("Test All Frames")
btnTestAll:SetScript("OnClick", function()
	local targetsConfig = Targets and Targets.isConfig
	local spyConfig = Spy and Spy.isTestMode
	local anyActive = targetsConfig or spyConfig or (AutoBG_Settings and AutoBG_Settings.TestAllTimers)

	if anyActive then
		if Targets and Targets.DisableConfigMode then Targets:DisableConfigMode() end
		if Spy and Spy.DisableTestMode then Spy:DisableTestMode() end
		if AutoBG_Settings then AutoBG_Settings.TestAllTimers = false end
		if AutoBG_LoadTimerPositions then AutoBG_LoadTimerPositions() end
		this:SetText("Test All Frames")
	else
		if Targets and Targets.EnableConfigMode then Targets:EnableConfigMode(selectedBracket) end
		if Spy and Spy.EnableTestMode then Spy:EnableTestMode() end
		if AutoBG_Settings then AutoBG_Settings.TestAllTimers = true end
		if AutoBG_LoadTimerPositions then AutoBG_LoadTimerPositions() end
		this:SetText("Hide Test Frames")
	end
	AutoBG_Options_Refresh()
end)

local btnResetAll = CreateFrame("Button", "AutoBG_BtnResetAll", panel, "UIPanelButtonTemplate")
btnResetAll:SetWidth(130)
btnResetAll:SetHeight(24)
btnResetAll:SetPoint("LEFT", btnTestAll, "RIGHT", 10, 0)
btnResetAll:SetText("Reset Positions")
btnResetAll:SetScript("OnClick", function()
	if AutoBG_Settings then
		AutoBG_Settings.Positions = {}
	end
	if AutoBG_ResetTimerPositions then AutoBG_ResetTimerPositions() end
	if AutoBG_ResetFCPositions then AutoBG_ResetFCPositions() end
	if Targets and Targets.ResetPosition then Targets:ResetPosition() end
	if Spy and Spy.ResetPosition then Spy:ResetPosition() end
	if DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00AutoBG:|r All UI and frame positions reset to defaults.")
	end
end)

local btnClose = CreateFrame("Button", "AutoBG_BtnClose", panel, "UIPanelButtonTemplate")
btnClose:SetWidth(90)
btnClose:SetHeight(24)
btnClose:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -18, 14)
btnClose:SetText("Close")
btnClose:SetScript("OnClick", function()
	panel:Hide()
	if Targets and Targets.isConfig then
		Targets:DisableConfigMode()
	end
end)

-- -------------------------------------------------------------------------- --
-- Public API & Backward Compatibility Exports                                --
-- -------------------------------------------------------------------------- --
function AutoBG_OpenOptions(tabKey)
	if not panel:IsShown() then
		panel:Show()
	end
	if tabKey then
		local k = string.lower(tabKey)
		if k == "general" or k == "gen" then
			SelectTab(1)
		elseif k == "timers" or k == "timer" or k == "fc" then
			SelectTab(2)
		elseif k == "targets" or k == "enemy" or k == "bgt" or k == "frames" then
			SelectTab(3)
		elseif k == "spy" then
			SelectTab(4)
		end
	end
end

BattlegroundTargets_ToggleOptions = function()
	AutoBG_OpenOptions("targets")
end
