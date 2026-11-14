-- -------------------------------------------------------------------------- --
-- AutoBG: settings (VanillaForge ForgeUI, Ember palette)                     --
-- Five pages, shown in the /abg window in two columns and, one at a time,    --
-- in Game Menu > AddOn Options > AutoBG in one column (ForgeLayout.lua).     --
-- Each page follows a match: queue, the pop, the match, what it shows.       --
-- -------------------------------------------------------------------------- --

-- Needs ClassicAPI and SuperWoW loaded; AutoBG.lua says what is missing.

if type(CLASSIC_API_VERSION) ~= "number" or not SUPERWOW_VERSION then
	return
end

local _, ns = ...
local UI = ns.UI
local L, R = UI.L, UI.R
local Targets = AutoBG_Targets
local Spy = AutoBG_Spy
local FlagAlert = AutoBG_FlagAlert
-- 5 is the arena bracket (2v2 to 5v5), as in AutoBG_Targets.lua.
local BRACKETS = { 10, 15, 40, 5 }
local selectedTab = 1
local selectedBracket = 10
local timersPreview = false
local book         -- the pages in AddOn Options

local layout = UI.NewLayout()
local syncs = { {}, {}, {}, {}, {} } -- per page: functions that show the saved values
local previewButtons = {}

local function S() return AutoBG_Settings end
local function TargetOptions() return AutoBG_Settings.Targets end
local function SpyOptions() return Spy:EnsureOptions() end
local function Percent(value) return value .. "%" end
local function Seconds(value) return value .. "s" end

local function PreviewActive()
	return (Targets and Targets.isConfig) or (Spy and Spy.isTestMode)
		or (FlagAlert and FlagAlert.isPreview)
		or timersPreview
end
AutoBG_IsPreviewActive = PreviewActive

-- The preview buttons fill while any frame preview is showing.
local function RefreshPreviewButtons()
	local active = PreviewActive() and true or false
	for _, button in ipairs(previewButtons) do
		UI.Select(button, active)
		button:SetText(active and "Hide preview" or "Preview frames")
	end
end

-- Shows the saved values of the page on screen, then lays it out for the
-- width it has (two columns in the window, one in AddOn Options).
local function Refresh()
	if not AutoBG_Settings then return end
	for _, sync in ipairs(syncs[selectedTab]) do sync() end
	RefreshPreviewButtons()
	book:Place(selectedTab)
end
AutoBG_Options_Refresh = Refresh

-- Dims a slider the way UI.Sync dims a switch.
local function Dim(slider, on)
	local alpha = on and 1 or 0.4
	slider:EnableMouse(on and true or false); slider:SetAlpha(alpha)
	slider.label:SetAlpha(alpha); slider.valueText:SetAlpha(alpha)
end

-- Dims a segmented choice.
local function DimChoice(buttons, track, on)
	for _, button in ipairs(buttons) do UI.SetEnabled(button, on) end
	track:SetAlpha(on and 1 or 0.4)
end

-- -------------------------------------------------------------------------- --
-- Items: every control made at (0, 0) and handed to the layout               --
-- -------------------------------------------------------------------------- --
-- A switch: get() is its value, set(value) saves it, needs() dims it.
-- options.ownLine: a block places it (it shares its line with a button).
local function Switch(index, page, column, name, text, tip, get, set, options, needs)
	local widget = UI.Switch(name, page, text, tip, 0, 0, function(value)
		set(value)
		Refresh()
	end, (options and options.indent) and 156 or (column == L and 190 or 172))
	table.insert(syncs[index], function()
		local enabled
		if needs then enabled = needs() and true or false end
		UI.Sync(widget, get(), enabled)
	end)
	if not (options and options.ownLine) then layout:Switch(page, column, widget, options) end
	return widget
end

-- A switch for one top-level AutoBG_Settings key.
local function Setting(index, page, column, name, text, tip, key, after, options, needs)
	return Switch(index, page, column, name, text, tip,
		function() return S()[key] end,
		function(value) S()[key] = value; if after then after(value) end end, options, needs)
end

-- A slider: get() is its value, set(value) saves it, needs() dims it.
local function Slider(index, page, column, name, text, tip, low, high, step, get, set, format, options, needs)
	local slider = UI.Slider(name, page, text, 0, 0, 208, low, high, step, function(value)
		set(value)
		if needs then Refresh() end
	end, format)
	if tip then UI.Tooltip(slider, tip) end
	table.insert(syncs[index], function()
		UI.SetSlider(slider, get())
		if needs then Dim(slider, needs()) end
	end)
	layout:Slider(page, column, slider, options)
	return slider
end

local function Hint(page, column, text, options) return layout:Hint(page, column, text, options) end

-- A segmented choice as a block; the track sits 4 left of the column, like the tabs.
local function Choice(page, column, prefix, labels, width, onClick, options)
	local buttons, show, track = UI.Segmented(prefix, page, labels, 0, 0, width, onClick, { height = 26 })
	options = options or {}
	options.height, options.regions = 32, { { track, "TOPLEFT", "TOPLEFT", -4, 0 } }
	layout:Add(page, column, options)
	return buttons, show, track
end

-- A switch with a small button at the end of its line (a battleground's queue
-- row, the sound's Play); buttonWidth is the button's.
local function SwitchWithButton(page, column, switch, button, buttonWidth)
	layout:Add(page, column, { place = function(x, y, width)
		switch:ClearAllPoints(); switch:SetPoint("TOPLEFT", page, "TOPLEFT", x, y - 2)
		button:ClearAllPoints(); button:SetPoint("TOPLEFT", page, "TOPLEFT", x + width - buttonWidth, y)
		return 26
	end })
end

-- One footer per page: one preview for every frame, one reset for every place.
local function Footers(index, page)
	local preview = UI.Button("AutoBG_BtnPreview" .. index, page, "Preview frames", 0, 0, 150, function()
		AutoBG_SetPreview(not PreviewActive())
	end)
	UI.Tooltip(preview, "Show every frame with samples so you can drag it into place: timers, flag carriers, the enemy frames of the size picked on the Enemy frames page, the Spy list, the stealth and flag warnings. Click again or close the settings to hide them.")
	table.insert(previewButtons, preview)
	layout:Footer(page, preview, 28)
	local reset = UI.Button("AutoBG_BtnReset" .. index, page, "Reset positions", 0, 0, 150, function()
		AutoBG_Settings.Positions = {}
		AutoBG_ResetTimerPositions()
		AutoBG_ResetFCPositions()
		Targets:ResetPosition()
		Spy:ResetPosition()
		if FlagAlert then FlagAlert:ResetPosition() end
		AutoBG_Print("Every frame is back in its place.", true)
	end)
	UI.Tooltip(reset, "Move every frame back to its first place: timers, flag carriers, enemy frames, the Spy list, the stealth and flag warnings.")
	layout:Footer(page, reset, 186)
end

-- -------------------------------------------------------------------------- --
-- Window and pages                                                           --
-- -------------------------------------------------------------------------- --
local panel = UI.Window("AutoBG_OptionsPanel", "AutoBG", 500, 446, GetAddOnMetadata("AutoBG", "Version"))
local TABS = {
	{ label = "General", height = 470 },
	{ label = "Timers", height = 440 },
	{ label = "Enemy frames", height = 560 },
	{ label = "Spy", height = 400 },
	{ label = "Arena", height = 330 },
}
local PAGE_KEYS = {
	general = 1, gen = 1,
	timers = 2, timer = 2, fc = 2,
	targets = 3, enemy = 3, bgt = 3, frames = 3,
	spy = 4,
	arena = 5,
}

-- Opening the Enemy frames page edits the frames being played in a match and
-- otherwise previews them.
local function OnPageOpen(index)
	selectedTab = index
	if index ~= 3 then return end
	if Targets.activeBG and Targets.currentSize then selectedBracket = Targets.currentSize end
	if not Targets.activeBG then Targets:EnableConfigMode(selectedBracket) end
end

local pages, ShowTab = UI.Tabs(panel, "AutoBG_Options", TABS, function(index)
	OnPageOpen(index)
	Refresh()
end)

-- -------------------------------------------------------------------------- --
-- General: queue, the pop, after the match, chat                             --
-- -------------------------------------------------------------------------- --
local general = pages[1]
layout:Section(general)
layout:Heading(general, L, "Queue")

-- Warsong and Arathi each pick the row they join: Cross-Faction (mixed teams),
-- Factioned (your faction only) or First Available (the server decides).
local QUEUE_MODES = { "xf", "fx", "fa" }
local QUEUE_MODE_TEXT = { xf = "Mixed", fx = "Own faction", fa = "Any" }
local function QueueRow(name, text, key, modeKey)
	local switch = Setting(1, general, L, "AutoBG_Opt_Queue" .. name, text,
		"Queue for " .. text .. ". The button beside it picks the teams.", key, nil, { ownLine = true })
	local button
	button = UI.Button("AutoBG_Opt_QueueMode" .. name, general, "", 0, 0, 76, function()
		local s = S()
		local nextIndex = 1
		for i = 1, #QUEUE_MODES do
			if QUEUE_MODES[i] == s[modeKey] then nextIndex = i % #QUEUE_MODES + 1 end
		end
		s[modeKey] = QUEUE_MODES[nextIndex]
		Refresh()
	end, { height = 18, font = "GameFontHighlightSmall" })
	UI.Tooltip(button, "Click to change the teams " .. text .. " queues for.\nMixed: Cross-Faction, both factions on each side.\nOwn faction: Factioned, your faction only.\nAny: First Available, the server decides.\nA row the list lacks falls back to Any.")
	SwitchWithButton(general, L, switch, button, 76)
	table.insert(syncs[1], function()
		local s = S()
		button:SetText(QUEUE_MODE_TEXT[s[modeKey]] or QUEUE_MODE_TEXT.xf)
		UI.SetEnabled(button, s[key] and true or false)
	end)
end
QueueRow("WSG", "Warsong Gulch", "AutoQueue_WSG", "QueueMode_WSG")
QueueRow("AB", "Arathi Basin", "AutoQueue_AB", "QueueMode_AB")
Setting(1, general, L, "AutoBG_Opt_QueueAV", "Alterac Valley", "Queue for Alterac Valley.", "AutoQueue_AV")
Setting(1, general, L, "AutoBG_Opt_QueueArena", "Arena",
	"Queue for the arena picked below together with the battlegrounds. A rated arena needs an arena team.", "AutoQueue_Arena")
local arenaTypeButtons, ShowArenaType, arenaTypeTrack
arenaTypeButtons, ShowArenaType, arenaTypeTrack = Choice(general, L, "AutoBG_Opt_ArenaType",
	{ "Skirmish", "2v2", "3v3", "5v5" }, 192, function(index)
		S().ArenaType = index - 1
		Refresh()
	end, { indent = 16 })
table.insert(syncs[1], function()
	ShowArenaType((S().ArenaType or 0) + 1)
	DimChoice(arenaTypeButtons, arenaTypeTrack, S().AutoQueue_Arena and true or false)
end)
Setting(1, general, L, "AutoBG_Opt_AutoQueue", "Queue on login",
	"Queue for everything picked above when you log in or reload.", "AutoQueueLogin")
local queueNow = UI.Button("AutoBG_BtnQueueAll", general, "Queue now", 0, 0, 100, function() AutoBG_QueueAllBGs() end)
UI.Tooltip(queueNow, "Queue for everything picked above now. /abg q does the same.")
local leaveQueues = UI.Button("AutoBG_BtnCancelAll", general, "Leave queues", 0, 0, 100, function() AutoBG_CancelAllQueues() end)
UI.Tooltip(leaveQueues, "Leave every battleground and arena queue. /abg cancel does the same.")
layout:Add(general, L, { before = 6, place = function(x, y)
	queueNow:ClearAllPoints(); queueNow:SetPoint("TOPLEFT", general, "TOPLEFT", x, y)
	leaveQueues:ClearAllPoints(); leaveQueues:SetPoint("TOPLEFT", general, "TOPLEFT", x + 108, y)
	return 24
end })

local function AutoAccept() return S().AutoAccept and true or false end
layout:Heading(general, R, "When it pops")
Setting(1, general, R, "AutoBG_Opt_AutoAccept", "Enter automatically",
	"Enter the battleground or arena when its queue pops. Never while you are AFK.", "AutoAccept")
Slider(1, general, R, "AutoBG_Opt_AcceptDelay", "Enter after",
	"Wait this long before entering, to finish what you are doing. AutoBG always enters a second before the invite runs out.",
	0, AutoBG_MAX_ENTER_DELAY, 1, function() return S().AutoAcceptDelay or 0 end,
	function(value) S().AutoAcceptDelay = value end,
	function(value) return value == 0 and "Instant" or (value .. "s") end, { indent = 16 }, AutoAccept)
local sound = Setting(1, general, R, "AutoBG_Opt_Sound", "Queue sound",
	"A loud ready-check sound when a queue pops or a match ends.", "NotifySound", function(value)
		if not value then AutoBG_StopNotificationSound() end
	end, { ownLine = true })
local play = UI.Button("AutoBG_BtnTestSound", general, "Play", 0, 0, 52, function() AutoBG_PlayNotificationSound() end,
	{ height = 20, ghost = true })
UI.Tooltip(play, "Play the queue sound once.")
SwitchWithButton(general, R, sound, play, 52)
Setting(1, general, R, "AutoBG_Opt_Flash", "Flash the taskbar",
	"Flash the game in the Windows taskbar when a queue pops or a match ends.", "FlashTaskbar")

layout:Heading(general, R, "After the match")
Setting(1, general, R, "AutoBG_Opt_AutoLeave", "Leave when it ends",
	"Leave the battleground as soon as the match is over.", "AutoLeave")
Setting(1, general, R, "AutoBG_Opt_AutoRejoin", "Queue again after leaving",
	"Queue for the same battleground or arena after a finished match.", "AutoRejoin")
Setting(1, general, R, "AutoBG_Opt_AutoRelease", "Release spirit",
	"Release your spirit when you die in a battleground, unless a Soulstone or Ankh is ready. Never in an arena.", "AutoRelease")
layout:Heading(general, L, "Chat")
Setting(1, general, L, "AutoBG_Opt_ChatMsg", "Chat messages",
	"Queues, entering and leaving, told in chat.", "ChatMessages")
Hint(general, L, "What stopped a queue (Deserter, all queues taken) always shows.")
Footers(1, general)

-- -------------------------------------------------------------------------- --
-- Timers: countdowns, flag carriers, their look                              --
-- -------------------------------------------------------------------------- --
local timers = pages[2]
local function RefreshTimers() AutoBG_Timers_UpdateVisibility() end
layout:Section(timers)
layout:Heading(timers, L, "Countdowns")
local function TimerSetting(name, text, tip, key)
	return Setting(2, timers, L, name, text, tip, key, RefreshTimers)
end
TimerSetting("AutoBG_Opt_ABTimers", "Arathi Basin bases", "A 60-second capture countdown for each Arathi Basin base.", "ABTimers")
TimerSetting("AutoBG_Opt_AVTimers", "Alterac Valley nodes", "5-minute countdowns for Alterac Valley towers, bunkers, graveyards and mines.", "AVTimers")
TimerSetting("AutoBG_Opt_WSGTimers", "Warsong flag return", "The 23 seconds until a captured Warsong Gulch flag is back.", "WSGTimers")
TimerSetting("AutoBG_Opt_StartTimer", "Game start", "Count down until the gates open.", "StartTimer")
TimerSetting("AutoBG_Opt_RessTimer", "Spirit healer waves", "The 30-second spirit healer wave, synced from your group.", "RessTimer")
TimerSetting("AutoBG_Opt_QueueTimers", "Queues", "How long you have waited in each queue, and how long an invite has left.", "QueueTimers")

layout:Heading(timers, R, "Flag carriers")
Setting(2, timers, R, "AutoBG_Opt_FCFrame", "Flag carrier frames",
	"Both Warsong Gulch flag carriers, with health, distance and the assault stacks.", "FCFrame",
	function() AutoBG_FC_UpdateVisibility() end)
Hint(timers, R, "Click a carrier to target it, right-click to focus.")
layout:Heading(timers, R, "Look")
local function TimerSlider(name, text, low, high, step, key, factor, format)
	factor = factor or 1
	return Slider(2, timers, R, name, text, nil, low, high, step,
		function() return math.floor((S()[key] or 1) * factor + 0.5) end,
		function(value) S()[key] = value / factor; RefreshTimers() end, format)
end
TimerSlider("AutoBG_Opt_ObjectiveWidth", "Bar width", 180, 420, 5, "ObjectiveWidth")
TimerSlider("AutoBG_Opt_ObjectiveHeight", "Bar height", 18, 32, 1, "ObjectiveHeight")
TimerSlider("AutoBG_Opt_ObjectiveScale", "Scale", 60, 150, 5, "ObjectiveScale", 100, Percent)
TimerSlider("AutoBG_Opt_ObjectiveOpacity", "Opacity", 20, 100, 5, "ObjectiveOpacity", 100, Percent)
Footers(2, timers)

-- -------------------------------------------------------------------------- --
-- Enemy frames: one battleground size at a time, then what every size shows  --
-- -------------------------------------------------------------------------- --
local frames = pages[3]
local function Relayout() Targets:SetupButtonLayout(selectedBracket) end
local function Rerender() if Targets.isConfig then Targets:RenderRoster() end end
local function SizeName(size) return size == 5 and "Arena" or (size .. "v" .. size) end

layout:Section(frames, true)
layout:Heading(frames, L, "Battleground size")
local _, ShowBracket = Choice(frames, L, "AutoBG_Targets_BracketBtn", { "10v10", "15v15", "40v40", "Arena" }, 212,
	function(index)
		selectedBracket = BRACKETS[index]
		-- Inside a battleground the live enemy list stays; Preview frames still works.
		if not Targets.activeBG then Targets:EnableConfigMode(selectedBracket) end
		Refresh()
	end)
table.insert(syncs[3], function()
	for i = 1, #BRACKETS do
		if BRACKETS[i] == selectedBracket then ShowBracket(i) end
	end
end)

-- A switch for one size's entry in a per-size table.
local function SizeSetting(name, text, tip, key, rerender)
	return Switch(3, frames, L, name, text, tip,
		function() return TargetOptions()[key][selectedBracket] end,
		function(value)
			TargetOptions()[key][selectedBracket] = value
			Relayout()
			if rerender then Rerender() end
		end)
end
-- A switch shared by every size.
local function RowFeature(name, text, tip, get, set, options, needs)
	return Switch(3, frames, R, name, text, tip, get, function(value)
		set(TargetOptions(), value)
		Relayout()
		Targets:ApplyRowFeatures()
	end, options, needs)
end
local function Flag(key) return function(o, value) o[key] = value end end
local function Side(key) return function(o, value) o[key] = value and "LEFT" or "RIGHT" end end

layout:Section(frames)
local sizeHeading = layout:Heading(frames, L, "10v10 frames")
SizeSetting("AutoBG_Tgt_Enable", "Show the frames", "Show enemy frames in battlegrounds of this size.", "EnableBracket", false)
SizeSetting("AutoBG_Tgt_HideRealm", "Hide realm names", "Leave the realm off enemy names, as cross-realm battlegrounds show them.", "ButtonHideRealm", true)
SizeSetting("AutoBG_Tgt_Trinket", "PvP trinket cooldown", "Each enemy's 3-minute PvP trinket cooldown, seen when they use it.", "ShowTrinket", true)
local function Trinket() return TargetOptions().ShowTrinket[selectedBracket] and true or false end
Switch(3, frames, L, "AutoBG_Tgt_TrinketLeft", "Trinket on the left", "Put the trinket on the left of the row instead of the right. Every size.",
	function() return TargetOptions().TrinketPos == "LEFT" end,
	function(value) TargetOptions().TrinketPos = value and "LEFT" or "RIGHT"; Relayout(); Rerender() end,
	{ indent = 16 }, Trinket)
table.insert(syncs[3], function() sizeHeading:SetText(string.upper(SizeName(selectedBracket) .. " frames")) end)

local function CastBars() return TargetOptions().ShowCastBars ~= false end
layout:Heading(frames, R, "Every size")
RowFeature("AutoBG_Tgt_CastBars", "Cast bars",
	"Each enemy's cast or channel beside the row, with the spell name. Grey: it cannot be interrupted. Click a cast bar to target the caster.",
	CastBars, Flag("ShowCastBars"))
RowFeature("AutoBG_Tgt_CastLeft", "Cast bars on the left", "Put cast bars on the left of the row instead of the right.",
	function() return TargetOptions().CastPos ~= "RIGHT" end, Side("CastPos"), { indent = 16 }, CastBars)
RowFeature("AutoBG_Tgt_FadeRange", "Mark enemies in range",
	"A thin green stripe on enemies within 80 yards, so the ones you can reach stand out. Enemies you have not been near yet get none.",
	function() return TargetOptions().FadeOutOfRange ~= false end, Flag("FadeOutOfRange"))
RowFeature("AutoBG_Tgt_TargetCount", "Who's on them",
	"How many of your group, you included, target each enemy, in orange beside the health.",
	function() return TargetOptions().ShowTargetCount ~= false end, Flag("ShowTargetCount"))
RowFeature("AutoBG_Tgt_FlagWatch", "Flag warnings",
	"Arathi Basin: a warning when an enemy starts opening a flag, or comes out of stealth at one. Flag spots are learned as flags are assaulted. Ctrl-click the warning to announce it.",
	function() return TargetOptions().FlagWatch ~= false end, Flag("FlagWatch"))

-- Size: three presets per battleground size, and sliders for anything between.
-- Each preset is { width, height, text size }.
local SIZE_PRESETS = {
	[10] = { { 170, 20, 10 }, { 210, 26, 12 }, { 250, 32, 14 } },
	[15] = { { 170, 20, 10 }, { 210, 26, 12 }, { 250, 32, 14 } },
	[40] = { { 160, 16, 10 }, { 210, 20, 11 }, { 240, 24, 12 } },
	[5] = { { 170, 20, 10 }, { 210, 26, 12 }, { 250, 32, 14 } },
}
local function Size(key) return TargetOptions()[key][selectedBracket] end
layout:Section(frames, true)
local presetHeading = layout:Heading(frames, L, "10v10 size")
local _, ShowPreset = Choice(frames, L, "AutoBG_Tgt_Preset", { "Compact", "Standard", "Large" }, 212, function(index)
	local o, preset = TargetOptions(), SIZE_PRESETS[selectedBracket][index]
	o.ButtonWidth[selectedBracket] = preset[1]
	o.ButtonHeight[selectedBracket] = preset[2]
	o.ButtonFontSize[selectedBracket] = preset[3]
	Relayout(); Rerender(); Refresh()
end)
table.insert(syncs[3], function()
	presetHeading:SetText(string.upper(SizeName(selectedBracket) .. " size"))
	-- A preset lights up only while the size matches it exactly.
	local match = 0
	for i, preset in ipairs(SIZE_PRESETS[selectedBracket]) do
		if preset[1] == Size("ButtonWidth") and preset[2] == Size("ButtonHeight") and preset[3] == Size("ButtonFontSize") then match = i end
	end
	ShowPreset(match)
end)

-- A slider for one size's entry; factor turns a saved fraction into percent.
local function SizeSlider(column, name, text, low, high, step, key, factor, format, rerender, options)
	factor = factor or 1
	return Slider(3, frames, column, name, text, nil, low, high, step,
		function() return math.floor((Size(key) or 1) * factor + 0.5) end,
		function(value)
			TargetOptions()[key][selectedBracket] = value / factor
			Relayout()
			if rerender then Rerender() end
			Refresh()
		end, format, options)
end
layout:Section(frames)
-- Text size 0-20 on the slider is font size 10-30: smaller is unreadable.
local TEXT_SIZE_BASE = 10
Slider(3, frames, L, "AutoBG_Tgt_FontSize", "Text size", nil, 0, 20, 1,
	function() return Size("ButtonFontSize") - TEXT_SIZE_BASE end,
	function(value)
		TargetOptions().ButtonFontSize[selectedBracket] = value + TEXT_SIZE_BASE
		Relayout(); Rerender(); Refresh()
	end, nil, { before = 4 })
SizeSlider(L, "AutoBG_Tgt_Width", "Width", 60, 300, 5, "ButtonWidth", nil, nil, true)
SizeSlider(L, "AutoBG_Tgt_Opacity", "Opacity", 20, 100, 5, "ButtonOpacity", 100, Percent)
SizeSlider(R, "AutoBG_Tgt_Scale", "Scale", 50, 200, 5, "ButtonScale", 100, Percent, false, { before = { 4, 0 } })
SizeSlider(R, "AutoBG_Tgt_Height", "Height", 10, 40, 1, "ButtonHeight", nil, nil, true)
Footers(3, frames)

-- -------------------------------------------------------------------------- --
-- Spy: open-world enemy list and alerts                                      --
-- -------------------------------------------------------------------------- --
local spy = pages[4]
local function RenderSpy() Spy:RenderRows() end
local function SpySetting(column, name, text, tip, key, after, options, needs)
	return Switch(4, spy, column, name, text, tip,
		function() return SpyOptions()[key] end,
		function(value) SpyOptions()[key] = value; if after then after(value) end end, options, needs)
end
local function SpyOn() return SpyOptions().Enabled and true or false end

layout:Section(spy)
layout:Heading(spy, L, "Nearby enemies")
SpySetting(L, "AutoBG_Spy_Enable", "Show the Spy list", "List the enemy players around you in the open world.", "Enabled", RenderSpy)
SpySetting(L, "AutoBG_Spy_AutoHide", "Hide when empty", "Hide the list while nobody is on it.", "AutoHide", RenderSpy, { indent = 16 }, SpyOn)
SpySetting(L, "AutoBG_Spy_DisableInRaids", "Off in raids", "No Spy list or warnings inside raids.", "DisableInRaids", RenderSpy)
layout:Heading(spy, L, "Warnings")
SpySetting(L, "AutoBG_Spy_StealthAlert", "Stealth warnings",
	"A short warning when you can see an enemy in stealth, outside battlegrounds. The same enemy stays quiet for 60 seconds.", "StealthAlert")
SpySetting(L, "AutoBG_Spy_SoundAlert", "Warning sounds",
	"A sound for a new enemy and for a stealth warning, outside battlegrounds. At most one every 8 seconds; an enemy met again stays quiet.", "SoundAlert")
Switch(4, spy, L, "AutoBG_Spy_BGStealthAlert", "Stealth warnings in battlegrounds",
	"In battlegrounds, a warning with a sound when you can see an enemy in stealth. At most one every 8 seconds; the same enemy stays quiet for 60 seconds.",
	function() return TargetOptions().StealthAlert end,
	function(value) TargetOptions().StealthAlert = value end)

layout:Heading(spy, R, "List")
Slider(4, spy, R, "AutoBG_Spy_Timeout", "Forget after", "An enemy not seen for this long leaves the list.", 10, 120, 5,
	function() return SpyOptions().Timeout or 30 end, function(value) SpyOptions().Timeout = value end, Seconds)
Slider(4, spy, R, "AutoBG_Spy_MaxRows", "Enemies shown", nil, 3, 20, 1,
	function() return SpyOptions().MaxRows or 5 end, function(value) SpyOptions().MaxRows = value; RenderSpy() end)
Slider(4, spy, R, "AutoBG_Spy_Scale", "Scale", nil, 50, 150, 5,
	function() return math.floor((SpyOptions().Scale or 1) * 100 + 0.5) end,
	function(value) SpyOptions().Scale = value / 100; Spy:ApplyScale() end, Percent)
local clear = UI.Button("AutoBG_BtnSpyClear", spy, "Clear list", 0, 0, 100, function()
	Spy:ClearHistory()
	Refresh()
end)
UI.Tooltip(clear, "Take everyone off the Spy list and forget who was met just now.")
layout:Button(spy, R, clear, { before = 4 })
Hint(spy, R, "Click a name to target, right-click to focus. Shift-click: kill on sight. Ctrl-click: ignore. /abg spy stats: who you meet most.")
Footers(4, spy)

-- -------------------------------------------------------------------------- --
-- Arena: what AutoBG adds to the enemy frames in an arena                    --
-- -------------------------------------------------------------------------- --
local arena = pages[5]
local function ArenaSwitch(column, name, text, tip, key)
	return Switch(5, arena, column, name, text, tip,
		function()
			local o = AutoBG_ArenaOptions()
			if key == "Callouts" then return o[key] end
			return o[key] ~= false
		end,
		function(value)
			AutoBG_ArenaOptions()[key] = value
			AutoBG_Arena.Refresh()
			AutoBG_ArenaPets.Refresh()
			AutoBG_Timers_UpdateVisibility()
		end)
end
layout:Section(arena)
layout:Heading(arena, L, "On each enemy")
ArenaSwitch(L, "AutoBG_Arena_Mana", "Mana and energy bars",
	"A thin bar under each enemy: mana, rage or energy. See at a glance when the healer runs low.", "Mana")
ArenaSwitch(L, "AutoBG_Arena_Abilities", "Key abilities",
	"Icons for the few abilities that matter: Divine Shield, Blessing of Protection, Blessing of Freedom and Hammer of Justice. Gold: on now. Grey: used, with the seconds since. A blessing shows on whoever received it.", "Abilities")
ArenaSwitch(L, "AutoBG_Arena_Pets", "Enemy pets",
	"The enemy pets and minions you have seen, under the enemy frames, with their owner and health. Click one to target it. Totems are left out.", "Pets")
layout:Heading(arena, L, "Shadow Sight")
ArenaSwitch(L, "AutoBG_Arena_ShadowSight", "Shadow Sight timers",
	"The orbs appear 90 seconds into every round. A pickup shows 15 seconds of sight for whoever took it, and that orb is back 3 minutes later. The timers sit with the other timer bars.", "ShadowSight")
layout:Heading(arena, R, "Alerts and finding enemies")
ArenaSwitch(R, "AutoBG_Arena_Drinking", "Drinking alert", "A message and a sound when an enemy starts drinking.", "Drinking")
ArenaSwitch(R, "AutoBG_Arena_Callouts", "Callouts to your team",
	"Say in your team's chat when an enemy drops to 25% health, and when one dies. Once per enemy.", "Callouts")
ArenaSwitch(R, "AutoBG_Arena_Scan", "Find enemies fast",
	"Step through the nearby enemies once a second (UnitXP) until the whole other team is listed. Only while you have no target, and it is cleared again. What your teammates target always counts.", "Scan")
Footers(5, arena)

-- -------------------------------------------------------------------------- --
-- The preview: one switch for every frame                                    --
-- -------------------------------------------------------------------------- --
-- Shared by the Preview buttons, closing the settings and /abg test.
function AutoBG_SetPreview(on)
	if on then
		Targets:EnableConfigMode(selectedBracket)
		Spy:EnableTestMode()
		if FlagAlert and selectedBracket == 15 then FlagAlert:SetPreview(true) end
	else
		if Targets.isConfig then Targets:DisableConfigMode() end
		if Spy.isTestMode then Spy:DisableTestMode() end
		if FlagAlert then FlagAlert:SetPreview(false) end
	end
	timersPreview = on and true or false
	AutoBG_Timers_SetPreview(timersPreview)
	AutoBG_FC_SetPreview(timersPreview)
	AutoBG_LoadTimerPositions()
	AutoBG_Timers_UpdateVisibility()
	AutoBG_FC_UpdateVisibility()
	Refresh()
end

-- A page back from AddOn Options is hidden even when its tab is the active one.
panel:SetScript("OnShow", function()
	ShowTab(selectedTab)
	pages[selectedTab]:Show()
end)
panel:SetScript("OnHide", function()
	if PreviewActive() then AutoBG_SetPreview(false) end
end)

-- Game Menu > AddOn Options > AutoBG (ClassicAPI): the same five pages, one
-- category each, in one column.
book = UI.Book({
	name = "AutoBG", text = "Open a page under AutoBG, or type /abg for the settings window.",
	open = function() AutoBG_OpenOptions() end,
	panel = panel, pages = pages, tabs = TABS, layout = layout, refresh = Refresh,
	select = OnPageOpen,
	hide = function() if PreviewActive() then AutoBG_SetPreview(false) end end,
})

-- -------------------------------------------------------------------------- --
-- Opening the window on a page (/abg, /bgt)                                  --
-- -------------------------------------------------------------------------- --
function AutoBG_OpenOptions(pageKey)
	local index = pageKey and PAGE_KEYS[string.lower(pageKey)]
	if index then selectedTab = index end
	if InterfaceOptionsFrame:IsShown() then InterfaceOptionsFrame:Hide() end
	if not panel:IsShown() then
		panel:Show()
	elseif index then
		ShowTab(selectedTab)
		pages[selectedTab]:Show()
	end
end
