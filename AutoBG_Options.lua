-- -------------------------------------------------------------------------- --
-- AutoBG: Options window (VanillaForge ForgeUI layout, Ember palette)         --
-- World of Warcraft 1.12.1, ClassicAPI v1.16.0+, SuperWoW v2.2+                --
-- -------------------------------------------------------------------------- --

-- Strict Engine Dependency Guard (Mandatory ClassicAPI v1.16.0+ & SuperWoW v2.2+)
local MIN_CLASSIC_API = 11600

if type(CLASSIC_API_VERSION) ~= "number" or not SUPERWOW_VERSION or
   CLASSIC_API_VERSION < MIN_CLASSIC_API then
	return
end

local _, ns = ...
local UI = ns.UI
local Targets = AutoBG_Targets
local Spy = AutoBG_Spy
local BRACKETS = { 10, 15, 40 }
local WIDTH = 500
local selectedTab = 1
local selectedBracket = 10
local startPreview
local previewButton
local Refresh = {}

local function RefreshTimers(includeCarriers)
	if AutoBG_Timers_UpdateVisibility then AutoBG_Timers_UpdateVisibility() end
	if includeCarriers and AutoBG_FC_UpdateVisibility then AutoBG_FC_UpdateVisibility() end
end

local function PreviewActive()
	return (Targets and Targets.isConfig) or (Spy and Spy.isTestMode)
		or (AutoBG_Settings and AutoBG_Settings.TestAllTimers)
end

-- The preview button fills while any frame preview is showing.
local function RefreshTestCaption()
	if not previewButton then return end
	local active = PreviewActive() and true or false
	UI.Select(previewButton, active)
	previewButton:SetText(active and "Hide preview" or "Preview frames")
end

-- A switch bound to a top-level AutoBG_Settings key.
local function Setting(name, parent, text, tip, x, y, key, after, hitWidth)
	return UI.Switch(name, parent, text, tip, x, y, function(value)
		if AutoBG_Settings then AutoBG_Settings[key] = value end
		if after then after(value) end
	end, hitWidth)
end

local function SpySettings()
	if not AutoBG_Settings then AutoBG_Settings = {} end
	AutoBG_Settings.Spy = AutoBG_Settings.Spy or {}
	return AutoBG_Settings.Spy
end

local function Hint(parent, text, x, y, width)
	local hint = UI.Label(parent, text, x, y, "GameFontDisableSmall")
	if width then hint:SetWidth(width) end
	return hint
end

local function Percent(value) return value .. "%" end
local function Seconds(value) return value .. "s" end

-- -------------------------------------------------------------------------- --
-- Window and tabs                                                            --
-- -------------------------------------------------------------------------- --
local panel = UI.Window("AutoBG_OptionsPanel", "AutoBG", WIDTH, 446, GetAddOnMetadata("AutoBG", "Version"))
BattlegroundTargets_OptionsFrame = panel -- Backwards compatibility alias

local pages, ShowTab = UI.Tabs(panel, "AutoBG_Options", {
	{ label = "General", height = 446 },
	{ label = "Timers", height = 436 },
	{ label = "Enemy frames", height = 542 },
	{ label = "Spy", height = 362 },
}, function(index)
	selectedTab = index
	Refresh[index]()
end)
local panelGeneral, panelTimers, panelTargets, panelSpy = pages[1], pages[2], pages[3], pages[4]

-- -------------------------------------------------------------------------- --
-- General: queue pops, after the match, auto queue, notifications            --
-- -------------------------------------------------------------------------- --
UI.Heading(panelGeneral, "Queue pop", 28, -98)
local cbAutoAccept = Setting("AutoBG_Opt_AutoAccept", panelGeneral, "Accept queue pops",
	"Automatically accept battleground queue pops.", 28, -118, "AutoAccept")
local cbSkipAFK = Setting("AutoBG_Opt_SkipAFK", panelGeneral, "Pause while AFK",
	"Do not accept, queue or rejoin automatically while you are flagged AFK.", 28, -144, "SkipIfAFK")
local sliderAcceptDelay = UI.Slider("AutoBG_Opt_AcceptDelay", panelGeneral, "Enter delay", 28, -176, 200, 0, AutoBG_MAX_ENTER_DELAY, 1,
	function(value)
		if AutoBG_Settings then AutoBG_Settings.AutoAcceptDelay = value end
	end, function(value) return value == 0 and "Instant" or (value .. "s") end)

UI.Heading(panelGeneral, "After the match", 28, -228)
local cbAutoLeave = Setting("AutoBG_Opt_AutoLeave", panelGeneral, "Leave when it ends",
	"Automatically leave battlegrounds when the match concludes.", 28, -248, "AutoLeave")
local cbAutoRejoin = Setting("AutoBG_Opt_AutoRejoin", panelGeneral, "Queue again after leaving",
	"Request the same battleground queue after leaving a completed match.", 28, -274, "AutoRejoin")
local cbAutoRelease = Setting("AutoBG_Opt_AutoRelease", panelGeneral, "Release spirit",
	"Automatically release your spirit when you die in a battleground (skipped while a Soulstone or Ankh is ready).", 28, -300, "AutoRelease")

UI.Heading(panelGeneral, "Auto queue", 264, -98)
local cbQueueWSG = Setting("AutoBG_Opt_QueueWSG", panelGeneral, "Warsong Gulch",
	"Include Warsong Gulch when you queue.", 264, -118, "AutoQueue_WSG", nil, 172)
local cbQueueAB = Setting("AutoBG_Opt_QueueAB", panelGeneral, "Arathi Basin",
	"Include Arathi Basin when you queue.", 264, -144, "AutoQueue_AB", nil, 172)
local cbQueueAV = Setting("AutoBG_Opt_QueueAV", panelGeneral, "Alterac Valley",
	"Include Alterac Valley when you queue.", 264, -170, "AutoQueue_AV", nil, 172)
local cbAutoQueue = Setting("AutoBG_Opt_AutoQueue", panelGeneral, "Queue on login",
	"Queue for the checked battlegrounds when you log in or reload.", 264, -196, "AutoQueueLogin", nil, 172)
local btnQueueAll = UI.Button("AutoBG_BtnQueueAll", panelGeneral, "Queue now", 264, -226, 100, function()
	if AutoBG_QueueAllBGs then AutoBG_QueueAllBGs() end
end)
UI.Tooltip(btnQueueAll, "Queue for the checked battlegrounds now.\n/abg aq now does the same.")
local btnCancelAll = UI.Button("AutoBG_BtnCancelAll", panelGeneral, "Leave queues", 372, -226, 100, function()
	if AutoBG_CancelAllQueues then AutoBG_CancelAllQueues() end
end)
UI.Tooltip(btnCancelAll, "Leave every battleground queue.\n/abg cancel does the same.")

UI.Heading(panelGeneral, "Notifications", 264, -266)
local cbSound = Setting("AutoBG_Opt_Sound", panelGeneral, "Queue sound",
	"Play a loud ready-check sound when a queue pops or a match ends.", 264, -286, "NotifySound", function(value)
		if not value and AutoBG_StopNotificationSound then AutoBG_StopNotificationSound() end
	end, 110)
local btnTestSound = UI.Button("AutoBG_BtnTestSound", panelGeneral, "Play", 420, -284, 52, function()
	if AutoBG_PlayNotificationSound then
		AutoBG_PlayNotificationSound()
	else
		PlaySound("ReadyCheck")
	end
end, { height = 20 })
UI.Tooltip(btnTestSound, "Play the queue sound once.")
local cbFlash = Setting("AutoBG_Opt_Flash", panelGeneral, "Flash the taskbar",
	"Flash the game window in the Windows taskbar when a queue pops.", 264, -312, "FlashTaskbar", nil, 172)
local cbChatMsg = Setting("AutoBG_Opt_ChatMsg", panelGeneral, "Chat messages",
	"Print status messages in chat for queues, joins and exits.", 264, -338, "ChatMessages", nil, 172)
local cbScoreColor = Setting("AutoBG_Opt_ScoreColor", panelGeneral, "Class colors on scoreboard",
	"Color player names on the scoreboard by class.", 264, -364, "ScoreColor", nil, 172)

Refresh[1] = function()
	local s = AutoBG_Settings
	if not s then return end
	UI.Sync(cbAutoAccept, s.AutoAccept)
	UI.Sync(cbSkipAFK, s.SkipIfAFK ~= false)
	UI.SetSlider(sliderAcceptDelay, s.AutoAcceptDelay or 0)
	UI.Sync(cbAutoLeave, s.AutoLeave)
	UI.Sync(cbAutoRejoin, s.AutoRejoin)
	UI.Sync(cbAutoRelease, s.AutoRelease)
	UI.Sync(cbQueueWSG, s.AutoQueue_WSG ~= false)
	UI.Sync(cbQueueAB, s.AutoQueue_AB ~= false)
	UI.Sync(cbQueueAV, s.AutoQueue_AV ~= false)
	UI.Sync(cbAutoQueue, s.AutoQueueLogin)
	UI.Sync(cbSound, s.NotifySound)
	UI.Sync(cbFlash, s.FlashTaskbar)
	UI.Sync(cbChatMsg, s.ChatMessages)
	UI.Sync(cbScoreColor, s.ScoreColor)
end

-- -------------------------------------------------------------------------- --
-- Timers: objective countdowns, flag carriers, countdown appearance          --
-- -------------------------------------------------------------------------- --
local function TimerSetting(name, text, tip, y, key)
	return Setting(name, panelTimers, text, tip, 28, y, key, function() RefreshTimers() end)
end

UI.Heading(panelTimers, "Countdowns", 28, -98)
local cbABTimers = TimerSetting("AutoBG_Opt_ABTimers", "Arathi Basin bases",
	"Show 60-second capture countdowns for Arathi Basin bases.", -118, "ABTimers")
local cbAVTimers = TimerSetting("AutoBG_Opt_AVTimers", "Alterac Valley nodes",
	"Show 5-minute capture countdowns for Alterac Valley towers, bunkers and graveyards.", -144, "AVTimers")
local cbWSGTimers = TimerSetting("AutoBG_Opt_WSGTimers", "Warsong flag respawn",
	"Show the 23-second flag respawn countdown in Warsong Gulch.", -170, "WSGTimers")
local cbStartTimer = TimerSetting("AutoBG_Opt_StartTimer", "Match start",
	"Count down until the match starts.", -196, "StartTimer")
local cbRessTimer = TimerSetting("AutoBG_Opt_RessTimer", "Spirit healer waves",
	"Show the synced 30-second Spirit Healer resurrection wave.", -222, "RessTimer")
local cbQueueTimers = TimerSetting("AutoBG_Opt_QueueTimers", "Queue wait time",
	"Show how long you have waited in each battleground queue.", -248, "QueueTimers")

UI.Heading(panelTimers, "Flag carriers", 264, -98)
local cbFCFrame = Setting("AutoBG_Opt_FCFrame", panelTimers, "Flag carrier frames",
	"Show frames for both Warsong Gulch flag carriers with live health.", 264, -118, "FCFrame", function()
		if AutoBG_FC_UpdateVisibility then AutoBG_FC_UpdateVisibility() end
	end, 172)
Hint(panelTimers, "Left-click a carrier to target it, right-click to focus it. Drag to move.", 264, -146, 208)

local function TimerSlider(name, text, y, minValue, maxValue, step, store, format)
	return UI.Slider(name, panelTimers, text, 264, y, 208, minValue, maxValue, step, function(value)
		if AutoBG_Settings then store(value) end
		RefreshTimers()
	end, format)
end

UI.Heading(panelTimers, "Countdown look", 264, -190)
local sliderObjectiveWidth = TimerSlider("AutoBG_Opt_ObjectiveWidth", "Bar width", -210, 180, 420, 5,
	function(value) AutoBG_Settings.ObjectiveWidth = value end)
local sliderObjectiveHeight = TimerSlider("AutoBG_Opt_ObjectiveHeight", "Bar height", -252, 18, 32, 1,
	function(value) AutoBG_Settings.ObjectiveHeight = value end)
local sliderObjectiveScale = TimerSlider("AutoBG_Opt_ObjectiveScale", "Scale", -294, 60, 150, 5,
	function(value) AutoBG_Settings.ObjectiveScale = value / 100 end, Percent)
local sliderObjectiveOpacity = TimerSlider("AutoBG_Opt_ObjectiveOpacity", "Opacity", -336, 20, 100, 5,
	function(value) AutoBG_Settings.ObjectiveOpacity = value / 100 end, Percent)

Refresh[2] = function()
	local s = AutoBG_Settings
	if not s then return end
	UI.Sync(cbABTimers, s.ABTimers)
	UI.Sync(cbAVTimers, s.AVTimers)
	UI.Sync(cbWSGTimers, s.WSGTimers)
	UI.Sync(cbStartTimer, s.StartTimer ~= false)
	UI.Sync(cbRessTimer, s.RessTimer)
	UI.Sync(cbQueueTimers, s.QueueTimers)
	UI.Sync(cbFCFrame, s.FCFrame)
	UI.SetSlider(sliderObjectiveWidth, s.ObjectiveWidth or 225)
	UI.SetSlider(sliderObjectiveHeight, s.ObjectiveHeight or 25)
	UI.SetSlider(sliderObjectiveScale, math.floor((s.ObjectiveScale or 1) * 100 + 0.5))
	UI.SetSlider(sliderObjectiveOpacity, math.floor((s.ObjectiveOpacity or 0.9) * 100 + 0.5))
end

-- -------------------------------------------------------------------------- --
-- Enemy frames: per-size settings for the battleground enemy list            --
-- -------------------------------------------------------------------------- --
local UpdateTargetsWidgets -- forward declaration

local function TargetOptions()
	return AutoBG_Settings and AutoBG_Settings.Targets
end

local function Relayout()
	if Targets and Targets.SetupButtonLayout then Targets:SetupButtonLayout(selectedBracket) end
end

local function Rerender()
	if Targets and Targets.isConfig and Targets.RenderRoster then Targets:RenderRoster() end
end

-- A switch bound to one size's entry in a per-size Targets table.
local function BracketSetting(name, text, tip, x, y, key, relayout, rerender)
	return UI.Switch(name, panelTargets, text, tip, x, y, function(value)
		local o = TargetOptions()
		if not (o and o[key]) then return end
		o[key][selectedBracket] = value
		if relayout then Relayout() end
		if rerender then Rerender() end
		if key == "ShowTrinket" then UpdateTargetsWidgets(selectedBracket) end
	end)
end

local function SelectBracket(size, start)
	selectedBracket = size
	-- Inside a battleground the live enemy list stays; the preview button still works on request.
	if start ~= false and Targets and Targets.EnableConfigMode and not Targets.activeBG then
		Targets:EnableConfigMode(size)
	end
	UpdateTargetsWidgets(size)
end

UI.Heading(panelTargets, "Battleground size", 28, -98)
local _, ShowBracket = UI.Segmented("AutoBG_Targets_BracketBtn", panelTargets, { "10v10", "15v15", "40v40" }, 24, -114, 208,
	function(index) SelectBracket(BRACKETS[index]) end, { height = 26 })

local cbTgtEnable = BracketSetting("AutoBG_Tgt_Enable", "Show frames in 10v10",
	"Show enemy frames for this battleground size.", 28, -154, "EnableBracket", true)
local cbTgtHideRealm = BracketSetting("AutoBG_Tgt_HideRealm", "Hide realm names",
	"Strip the realm suffix from enemy names.", 28, -180, "ButtonHideRealm", false, true)
local cbTgtHealthText = BracketSetting("AutoBG_Tgt_HealthText", "Health percent",
	"Show each enemy's health percentage on the row.", 28, -206, "ButtonShowHealthText", false, true)
local cbTgtDim = BracketSetting("AutoBG_Tgt_DimStealth", "Dim stealthed enemies",
	"Fade the rows of enemies in stealth.", 28, -232, "DimStealthed", false, true)
local cbTgtTrinket = BracketSetting("AutoBG_Tgt_Trinket", "PvP trinket cooldown",
	"Track each enemy's 3-minute PvP trinket cooldown.", 28, -258, "ShowTrinket", true, true)
local cbTgtTrinketLeft = UI.Switch("AutoBG_Tgt_TrinketLeft", panelTargets, "Trinket on the left",
	"Put the trinket icon on the left of the row instead of the right.", 44, -284, function(value)
		local o = TargetOptions()
		if not o then return end
		o.TrinketPos = value and "LEFT" or "RIGHT"
		Relayout()
		Rerender()
	end)

local sizeHint = Hint(panelTargets, "", 28, -316, 208)

-- Frame size: three presets per battleground size, and sliders below for
-- anything in between.
-- Each preset is { width, height, text size }.
local SIZE_PRESETS = {
	[10] = { { 170, 20, 10 }, { 210, 26, 12 }, { 250, 32, 14 } },
	[15] = { { 170, 20, 10 }, { 210, 26, 12 }, { 250, 32, 14 } },
	[40] = { { 160, 16, 9 }, { 210, 20, 11 }, { 240, 24, 12 } },
}
UI.Heading(panelTargets, "Frame size", 264, -98)
local _, ShowPreset = UI.Segmented("AutoBG_Tgt_Preset", panelTargets, { "Compact", "Standard", "Large" }, 260, -114, 212,
	function(index)
		local o = TargetOptions()
		if not (o and o.ButtonWidth and o.ButtonHeight and o.ButtonFontSize) then return end
		local preset = SIZE_PRESETS[selectedBracket][index]
		o.ButtonWidth[selectedBracket] = preset[1]
		o.ButtonHeight[selectedBracket] = preset[2]
		o.ButtonFontSize[selectedBracket] = preset[3]
		Relayout()
		Rerender()
		UpdateTargetsWidgets(selectedBracket)
	end, { height = 26 })

-- Row features shared by every battleground size.
local function RowFeature(name, text, tip, y, key)
	return UI.Switch(name, panelTargets, text, tip, 264, y, function(value)
		Targets:EnsureOptions()
		AutoBG_Settings.Targets[key] = value
		if Targets.ApplyRowFeatures then Targets:ApplyRowFeatures() end
		UpdateTargetsWidgets(selectedBracket)
	end, 172)
end

UI.Heading(panelTargets, "On each enemy", 264, -186)
local cbTgtCastBars = RowFeature("AutoBG_Tgt_CastBars", "Cast bars",
	"Show each enemy's cast or channel beside the row, with the spell name. Grey means it cannot be interrupted. Click a cast bar to target the caster.", -206, "ShowCastBars")
local cbTgtCastLeft = UI.Switch("AutoBG_Tgt_CastLeft", panelTargets, "Cast bars on the left",
	"Put cast bars on the left of the row instead of the right.", 280, -232, function(value)
		local o = TargetOptions()
		if not o then return end
		o.CastPos = value and "LEFT" or "RIGHT"
		Relayout()
		Rerender()
	end, 156)
local cbTgtRange = RowFeature("AutoBG_Tgt_FadeRange", "Mark enemies in range",
	"A thin green stripe on the left of each enemy within 80 yards, so the ones you can reach stand out. Nothing else changes; enemies you have not been near yet get no stripe.", -258, "FadeOutOfRange")
local cbTgtRaidIcons = RowFeature("AutoBG_Tgt_RaidIcons", "Raid icons",
	"Show the skull, cross and other raid icons your group puts on enemies.", -284, "ShowRaidIcons")
local cbTgtTargetCount = RowFeature("AutoBG_Tgt_TargetCount", "Who's on them",
	"Show how many of your group, you included, target each enemy, in orange beside the health.", -310, "ShowTargetCount")

local function TargetSlider(name, text, x, y, width, minValue, maxValue, step, store, rerender, format)
	return UI.Slider(name, panelTargets, text, x, y, width, minValue, maxValue, step, function(value)
		local o = TargetOptions()
		if not o then return end
		if not store(o, value) then return end
		Relayout()
		if rerender then Rerender() end
		UpdateTargetsWidgets(selectedBracket)
	end, format)
end

UI.Heading(panelTargets, "Custom size", 28, -340)
local sliderTgtFontSize = TargetSlider("AutoBG_Tgt_FontSize", "Text size", 28, -360, 200, 6, 20, 1, function(o, value)
	if not o.ButtonFontSize then return end
	o.ButtonFontSize[selectedBracket] = value
	return true
end, true)
local sliderTgtScale = TargetSlider("AutoBG_Tgt_Scale", "Scale", 264, -360, 208, 50, 200, 5, function(o, value)
	if not o.ButtonScale then return end
	o.ButtonScale[selectedBracket] = value / 100
	return true
end, false, Percent)
local sliderTgtWidth = TargetSlider("AutoBG_Tgt_Width", "Width", 28, -402, 200, 60, 300, 5, function(o, value)
	if not o.ButtonWidth then return end
	o.ButtonWidth[selectedBracket] = value
	return true
end, true)
local sliderTgtHeight = TargetSlider("AutoBG_Tgt_Height", "Height", 264, -402, 208, 10, 40, 1, function(o, value)
	if not o.ButtonHeight then return end
	o.ButtonHeight[selectedBracket] = value
	return true
end, true)
local sliderTgtOpacity = TargetSlider("AutoBG_Tgt_Opacity", "Opacity", 28, -444, 200, 20, 100, 5, function(o, value)
	o.ButtonOpacity = o.ButtonOpacity or {}
	o.ButtonOpacity[selectedBracket] = value / 100
	return true
end, false, Percent)

UpdateTargetsWidgets = function(sz)
	if Targets and Targets.EnsureOptions then Targets:EnsureOptions() end
	local o = TargetOptions()
	if not o then return end
	for i = 1, 3 do
		if BRACKETS[i] == sz then ShowBracket(i) end
	end
	local label = sz .. "v" .. sz
	cbTgtEnable.label:SetText("Show frames in " .. label)
	sizeHint:SetText("The switches above and the frame size apply to " .. label .. " only.")
	UI.Sync(cbTgtEnable, o.EnableBracket and o.EnableBracket[sz])
	UI.Sync(cbTgtHideRealm, o.ButtonHideRealm and o.ButtonHideRealm[sz])
	UI.Sync(cbTgtHealthText, o.ButtonShowHealthText and o.ButtonShowHealthText[sz])
	UI.Sync(cbTgtDim, o.DimStealthed and o.DimStealthed[sz])
	local trinket = o.ShowTrinket and o.ShowTrinket[sz]
	UI.Sync(cbTgtTrinket, trinket)
	UI.Sync(cbTgtTrinketLeft, o.TrinketPos == "LEFT", trinket and true or false)
	UI.Sync(cbTgtCastBars, o.ShowCastBars ~= false)
	UI.Sync(cbTgtCastLeft, o.CastPos ~= "RIGHT", o.ShowCastBars ~= false)
	UI.Sync(cbTgtRange, o.FadeOutOfRange ~= false)
	UI.Sync(cbTgtRaidIcons, o.ShowRaidIcons ~= false)
	UI.Sync(cbTgtTargetCount, o.ShowTargetCount ~= false)
	local width = (o.ButtonWidth and o.ButtonWidth[sz]) or 150
	local height = (o.ButtonHeight and o.ButtonHeight[sz]) or 20
	local fontSize = (o.ButtonFontSize and o.ButtonFontSize[sz]) or 10
	-- A preset lights up only while the size matches it exactly.
	local match = 0
	for i, preset in ipairs(SIZE_PRESETS[sz] or {}) do
		if preset[1] == width and preset[2] == height and preset[3] == fontSize then match = i end
	end
	ShowPreset(match)
	UI.SetSlider(sliderTgtFontSize, fontSize)
	UI.SetSlider(sliderTgtScale, math.floor(((o.ButtonScale and o.ButtonScale[sz]) or 1.0) * 100 + 0.5))
	UI.SetSlider(sliderTgtWidth, width)
	UI.SetSlider(sliderTgtHeight, height)
	UI.SetSlider(sliderTgtOpacity, math.floor(((o.ButtonOpacity and o.ButtonOpacity[sz]) or 1) * 100 + 0.5))
	RefreshTestCaption()
end

Refresh[3] = function()
	-- In a match, edit and preview the frame you are actually looking at.
	if Targets and Targets.activeBG and Targets.currentSize then selectedBracket = Targets.currentSize end
	SelectBracket(selectedBracket, startPreview)
end

-- -------------------------------------------------------------------------- --
-- Spy: open-world enemy list and alerts                                      --
-- -------------------------------------------------------------------------- --
local function SpySetting(name, text, tip, x, y, key, after, hitWidth)
	return UI.Switch(name, panelSpy, text, tip, x, y, function(value)
		SpySettings()[key] = value
		if after then after(value) end
	end, hitWidth)
end

local function RenderSpy()
	if Spy and Spy.RenderRows then Spy:RenderRows() end
end

UI.Heading(panelSpy, "Nearby enemies", 28, -98)
local cbSpyEnable = SpySetting("AutoBG_Spy_Enable", "Show the Spy list",
	"List nearby hostile players in the open world.", 28, -118, "Enabled", RenderSpy)
local cbSpyAutoHide = SpySetting("AutoBG_Spy_AutoHide", "Hide when empty",
	"Hide the Spy list completely while no enemies are tracked.", 28, -144, "AutoHide", RenderSpy)

UI.Heading(panelSpy, "Alerts", 28, -180)
local cbSpySound = SpySetting("AutoBG_Spy_SoundAlert", "Alert sounds",
	"Play a sound for new enemies and stealth warnings outside BGs. At most one alert per 8 seconds; repeated contacts stay quiet. Off by default. BG sounds have their own setting.", 28, -200, "SoundAlert")
local cbSpyStealth = SpySetting("AutoBG_Spy_StealthAlert", "Stealth warnings",
	"Show a brief stealth warning outside BGs. Its sound follows Alert sounds. Repeated warnings for the same enemy stay quiet for 60 seconds. BG alerts have their own setting.", 28, -226, "StealthAlert", function() Refresh[4]() end)
local cbSpyProximity = SpySetting("AutoBG_Spy_StealthProximityOnly", "Only enemies I can see",
	"On (default): warn only for a stealthed enemy you can actually see, at any distance your detection reaches. Off: Spy-style warning on a received stealth cast, even if you cannot see the enemy. BG warnings always need you to see them.", 44, -252, "StealthProximityOnly")
local cbSpyBGStealth = UI.Switch("AutoBG_Spy_BGStealthAlert", panelSpy, "Stealth warnings in BGs",
	"In battlegrounds, warn with a sound when you can see a stealthed enemy, at any distance your detection reaches. At most one warning per 8 seconds; the same enemy stays quiet for 60 seconds. Enemy frames still show who is hidden.", 28, -278, function(value)
		Targets:EnsureOptions()
		AutoBG_Settings.Targets.StealthAlert = value
	end)

UI.Heading(panelSpy, "List", 264, -98)
local sliderSpyTimeout = UI.Slider("AutoBG_Spy_Timeout", panelSpy, "Forget after", 264, -118, 208, 10, 120, 5,
	function(value) SpySettings().Timeout = value end, Seconds)
local sliderSpyMaxRows = UI.Slider("AutoBG_Spy_MaxRows", panelSpy, "Enemies shown", 264, -160, 208, 3, 20, 1,
	function(value)
		SpySettings().MaxRows = value
		RenderSpy()
	end)
local sliderSpyScale = UI.Slider("AutoBG_Spy_Scale", panelSpy, "Scale", 264, -202, 208, 50, 150, 5,
	function(value)
		SpySettings().Scale = value / 100
		if Spy and Spy.ApplyScale then Spy:ApplyScale() end
	end, Percent)
local btnSpyClear = UI.Button("AutoBG_BtnSpyClear", panelSpy, "Clear list", 264, -246, 100, function()
	if Spy and Spy.ClearHistory then Spy:ClearHistory() end
	RefreshTestCaption()
end)
UI.Tooltip(btnSpyClear, "Remove everyone from the Spy list and forget recent contacts.")

Refresh[4] = function()
	local opt = AutoBG_Settings and AutoBG_Settings.Spy
	if not opt then return end
	UI.Sync(cbSpyEnable, opt.Enabled)
	UI.Sync(cbSpyAutoHide, opt.AutoHide)
	UI.Sync(cbSpySound, opt.SoundAlert)
	UI.Sync(cbSpyStealth, opt.StealthAlert)
	UI.Sync(cbSpyProximity, opt.StealthProximityOnly ~= false, opt.StealthAlert and true or false)
	if Targets and Targets.EnsureOptions then Targets:EnsureOptions() end
	UI.Sync(cbSpyBGStealth, AutoBG_Settings.Targets and AutoBG_Settings.Targets.StealthAlert)
	UI.SetSlider(sliderSpyTimeout, opt.Timeout or 30)
	UI.SetSlider(sliderSpyMaxRows, opt.MaxRows or 5)
	UI.SetSlider(sliderSpyScale, math.floor((opt.Scale or 1.0) * 100 + 0.5))
end

-- -------------------------------------------------------------------------- --
-- Footer: one preview for every frame, one reset for every position          --
-- -------------------------------------------------------------------------- --
previewButton = UI.Button("AutoBG_BtnTestAll", panel, "Preview frames", 0, 0, 150, function()
	if PreviewActive() then
		if Targets and Targets.DisableConfigMode then Targets:DisableConfigMode() end
		if Spy and Spy.DisableTestMode then Spy:DisableTestMode() end
		if AutoBG_Settings then AutoBG_Settings.TestAllTimers = false end
	else
		if Targets and Targets.EnableConfigMode then Targets:EnableConfigMode(selectedBracket) end
		if Spy and Spy.EnableTestMode then Spy:EnableTestMode() end
		if AutoBG_Settings then AutoBG_Settings.TestAllTimers = true end
	end
	if AutoBG_LoadTimerPositions then AutoBG_LoadTimerPositions() end
	AutoBG_Options_Refresh()
	RefreshTimers(true)
end)
previewButton:ClearAllPoints()
previewButton:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 28, 18)
UI.Tooltip(previewButton, "Show every AutoBG frame with sample enemies so you can drag it into place: timers, flag carriers, enemy frames for the selected size, the Spy list, and a stealth warning with its sound. Click again or close this window to hide them.")

local btnResetAll = UI.Button("AutoBG_BtnResetAll", panel, "Reset positions", 0, 0, 150, function()
	if AutoBG_Settings then
		AutoBG_Settings.Positions = {}
		if AutoBG_Settings.Targets and AutoBG_Settings.Targets.pos then
			AutoBG_Settings.Targets.pos = {}
		end
		if AutoBG_Settings.Spy then
			AutoBG_Settings.Spy.posX = nil
			AutoBG_Settings.Spy.posY = nil
			AutoBG_Settings.Spy.alertPosX = nil
			AutoBG_Settings.Spy.alertPosY = nil
		end
	end
	if AutoBG_ResetTimerPositions then AutoBG_ResetTimerPositions() end
	if AutoBG_ResetFCPositions then AutoBG_ResetFCPositions() end
	if Targets and Targets.ResetPosition then Targets:ResetPosition() end
	if Spy and Spy.ResetPosition then Spy:ResetPosition() end
	if DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00AutoBG:|r All frame positions reset to defaults.")
	end
end)
btnResetAll:ClearAllPoints()
btnResetAll:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 186, 18)
UI.Tooltip(btnResetAll, "Move every AutoBG frame back to its default position: timers, flag carriers, enemy frames, the Spy list and the stealth warning.")

-- -------------------------------------------------------------------------- --
-- Tab selection & universal refresh                                          --
-- -------------------------------------------------------------------------- --
-- start = false refreshes the enemy-frames page without starting its preview.
local function SelectTab(tabId, start)
	startPreview = start
	ShowTab(tabId)
	startPreview = nil
end

function AutoBG_Options_Refresh()
	SelectTab(selectedTab, false)
	RefreshTestCaption()
end

panel:SetScript("OnShow", function()
	SelectTab(selectedTab)
	RefreshTestCaption()
end)

panel:SetScript("OnHide", function()
	if Targets and Targets.isConfig then Targets:DisableConfigMode() end
	if Spy and Spy.isTestMode then Spy:DisableTestMode() end
	if AutoBG_Settings and AutoBG_Settings.TestAllTimers then
		AutoBG_Settings.TestAllTimers = false
		if AutoBG_LoadTimerPositions then AutoBG_LoadTimerPositions() end
		RefreshTimers(true)
	end
	RefreshTestCaption()
end)

-- -------------------------------------------------------------------------- --
-- Public API & Backward Compatibility Exports                                --
-- -------------------------------------------------------------------------- --
function AutoBG_OpenOptions(tabKey)
	local requestedTab
	if tabKey then
		local k = string.lower(tabKey)
		if k == "general" or k == "gen" then
			requestedTab = 1
		elseif k == "timers" or k == "timer" or k == "fc" then
			requestedTab = 2
		elseif k == "targets" or k == "enemy" or k == "bgt" or k == "frames" then
			requestedTab = 3
		elseif k == "spy" then
			requestedTab = 4
		end
	end
	-- Choose the requested page before OnShow refreshes it. Opening Spy must not
	-- briefly start the previously selected enemy-frame preview.
	if requestedTab then selectedTab = requestedTab end
	if not panel:IsShown() then
		panel:Show()
	elseif requestedTab then
		SelectTab(selectedTab)
		RefreshTestCaption()
	end
end

BattlegroundTargets_ToggleOptions = function()
	AutoBG_OpenOptions("targets")
end
