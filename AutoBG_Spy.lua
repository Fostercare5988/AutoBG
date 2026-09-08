-- -------------------------------------------------------------------------- --
-- AutoBG: Open-World Spy Module (Consolidated from BattlegroundTargets)       --
-- Engineered natively for World of Warcraft 1.12.1 (Enhanced Engine)        --
-- Leveraging SuperWoW v2.2+, ClassicAPI v1.14.0+, NamPower v4.6.3+, UnitXP  --
-- -------------------------------------------------------------------------- --

-- Strict Engine Dependency Guard (Mandatory ClassicAPI v1.14.0+ & SuperWoW v2.2+)
local MIN_CLASSIC_API = 11400

if not (CLASSIC_API_VERSION and SUPERWOW_VERSION) or 
   (type(CLASSIC_API_VERSION) == "number" and CLASSIC_API_VERSION < MIN_CLASSIC_API) then
	return
end

AutoBG_Spy = AutoBG_Spy or {}
local Spy = AutoBG_Spy
local Targets = AutoBG_Targets

-- Backwards-compatibility aliases
if not BattlegroundTargets then BattlegroundTargets = AutoBG_Targets or {} end
BattlegroundTargets.Spy = AutoBG_Spy

local MAX_SPY_ENEMIES = 20
local MAX_SPY_ROWS = 10
local FONT = "Fonts\\FRIZQT__.TTF"
local BAR_TEXTURE = [[Interface\AddOns\AutoBG\Textures\barTexture.tga]]
local PROWL_TEXTURE = [[Interface\AddOns\AutoBG\Textures\prowl.tga]]
local SOUND_ENEMY_DETECTED = [[Interface\AddOns\AutoBG\Sounds\detected-nearby.mp3]]
local SOUND_STEALTH_DETECTED = [[Interface\AddOns\AutoBG\Sounds\detected-stealth.mp3]]

function Spy:PlayEnemyDetectedSound()
	PlaySoundFile(SOUND_ENEMY_DETECTED, "Master")
end

function Spy:PlayStealthDetectedSound()
	PlaySoundFile(SOUND_STEALTH_DETECTED, "Master")
end

local function GetSpySettings()
	if not AutoBG_Settings then AutoBG_Settings = {} end
	if not AutoBG_Settings.Spy then
		AutoBG_Settings.Spy = {
			Enabled = true,
			SoundAlert = true,
			StealthAlert = true,
			AutoHide = false,
			Timeout = 30,
			MaxRows = 5,
			Scale = 1.0,
		}
	end
	return AutoBG_Settings.Spy
end

-- Pre-allocated memory tables (Rule D1 Zero GC Churn)
local trackedEnemies = {}
for i = 1, MAX_SPY_ENEMIES do
	trackedEnemies[i] = {
		name = nil,
		shortName = nil,
		classToken = nil,
		race = nil,
		level = nil,
		healthPct = 100,
		lastSeen = 0,
		guid = nil,
		isStealthed = false,
		stealthSpell = nil,
		wasStealthedAlerted = false,
	}
end
local activeEnemyCount = 0

local nameToTrackIndex = {}
local guidToName = {}
local hostileCache = {}
local friendlyCache = {}
local soundDebounce = {}
local playerRaceCache = {}

Spy.isTestMode = false

-- -------------------------------------------------------------------------- --
-- Hostility & Entity Resolution Helpers                                      --
-- -------------------------------------------------------------------------- --
local function StripRealm(name)
	if not name then return "" end
	local p = string.find(name, "-", 1, true)
	if p then
		return string.sub(name, 1, p - 1)
	end
	return name
end

local function GetPlayerFaction()
	return UnitFactionGroup("player")
end

-- -------------------------------------------------------------------------- --
-- Race & Class Formatting & Racial Detection Telemetry                       --
-- -------------------------------------------------------------------------- --
local CLASS_DISPLAY = {
	["WARRIOR"] = "Warrior",
	["PALADIN"] = "Paladin",
	["HUNTER"] = "Hunter",
	["ROGUE"] = "Rogue",
	["PRIEST"] = "Priest",
	["SHAMAN"] = "Shaman",
	["MAGE"] = "Mage",
	["WARLOCK"] = "Warlock",
	["DRUID"] = "Druid",
}

local CANONICAL_RACES = {
	["HUMAN"] = "Human",
	["DWARF"] = "Dwarf",
	["NIGHTELF"] = "Night Elf",
	["NIGHT ELF"] = "Night Elf",
	["GNOME"] = "Gnome",
	["HIGHELF"] = "High Elf",
	["HIGH ELF"] = "High Elf",
	["ORC"] = "Orc",
	["UNDEAD"] = "Undead",
	["SCOURGE"] = "Undead",
	["TAUREN"] = "Tauren",
	["TROLL"] = "Troll",
	["BLOODELF"] = "Blood Elf",
	["BLOOD ELF"] = "Blood Elf",
	["GOBLIN"] = "Goblin",
}

local RACIAL_SPELL_IDS = {
	-- Night Elf
	[20580] = "Night Elf", -- Shadowmeld
	[2651] = "Night Elf",  -- Elune's Grace (Rank 1)
	[10795] = "Night Elf", -- Elune's Grace (Rank 2)
	[10796] = "Night Elf", -- Elune's Grace (Rank 3)
	[10797] = "Night Elf", -- Starshards (Rank 1)
	[19296] = "Night Elf", -- Starshards (Rank 2)
	[19299] = "Night Elf", -- Starshards (Rank 3)
	[19302] = "Night Elf", -- Starshards (Rank 4)
	[19303] = "Night Elf", -- Starshards (Rank 5)
	[19304] = "Night Elf", -- Starshards (Rank 6)
	[19305] = "Night Elf", -- Starshards (Rank 7)

	-- Dwarf
	[20594] = "Dwarf",     -- Stoneform
	[6346] = "Dwarf",      -- Fear Ward

	-- Gnome
	[20589] = "Gnome",     -- Escape Artist

	-- Human
	[20600] = "Human",     -- Perception
	[10793] = "Human",     -- Feedback (Rank 1)
	[19261] = "Human",     -- Feedback (Rank 2)
	[19262] = "Human",     -- Feedback (Rank 3)
	[19264] = "Human",     -- Feedback (Rank 4)
	[19265] = "Human",     -- Feedback (Rank 5)

	-- Undead
	[7744] = "Undead",      -- Will of the Forsaken
	[20577] = "Undead",     -- Cannibalize
	[2652] = "Undead",      -- Touch of Weakness

	-- Orc
	[20572] = "Orc",         -- Blood Fury

	-- Tauren
	[20549] = "Tauren",      -- War Stomp

	-- Troll
	[20554] = "Troll",       -- Berserking
	[26296] = "Troll",
	[26297] = "Troll",
	[9035] = "Troll",        -- Hex of Weakness
}

local RACIAL_SPELL_NAMES = {
	["Shadowmeld"] = "Night Elf",
	["Elune's Grace"] = "Night Elf",
	["Starshards"] = "Night Elf",
	["Stoneform"] = "Dwarf",
	["Fear Ward"] = "Dwarf",
	["Escape Artist"] = "Gnome",
	["Perception"] = "Human",
	["Feedback"] = "Human",
	["Will of the Forsaken"] = "Undead",
	["Cannibalize"] = "Undead",
	["Blood Fury"] = "Orc",
	["War Stomp"] = "Tauren",
	["Berserking"] = "Troll",
	["Hex of Weakness"] = "Troll",
	["Touch of Weakness"] = "Undead",
	["Arcane Flash"] = "High Elf",
	["Meditation"] = "High Elf",
}

local function FormatRace(rawRace)
	if not rawRace or rawRace == "" then return nil end
	local upper = string.upper(rawRace)
	if CANONICAL_RACES[upper] then
		return CANONICAL_RACES[upper]
	end
	local stripped = string.gsub(upper, "%s+", "")
	if CANONICAL_RACES[stripped] then
		return CANONICAL_RACES[stripped]
	end
	return rawRace
end

local function FormatClass(rawClass)
	if not rawClass or rawClass == "" then return nil end
	local token = (Targets and Targets.ResolveClassToken and Targets.ResolveClassToken(rawClass)) or string.upper(rawClass)
	return CLASS_DISPLAY[token] or token
end

local function InferRaceFromFactionAndClass(classToken)
	if not classToken then return nil end
	local pf = GetPlayerFaction()
	if pf == "Horde" then
		if classToken == "DRUID" then
			return "Night Elf"
		end
	elseif pf == "Alliance" then
		if classToken == "DRUID" then
			return "Tauren"
		end
	end
	return nil
end

function Spy:CheckUnitStealth(unit)
	if not unit or not UnitExists(unit) then return false, nil end

	-- 1. Modern ClassicAPI C_UnitAuras query
	if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
		for i = 1, 32 do
			local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
			if not aura then break end
			if aura.spellId and Targets and Targets.CheckIsStealthSpell then
				local isS, sName = Targets.CheckIsStealthSpell(aura.spellId)
				if isS then return true, sName end
			end
			if aura.name and Targets and Targets.CheckIsStealthName then
				local isS, sName = Targets.CheckIsStealthName(aura.name)
				if isS then return true, sName end
			end
		end
	end

	-- 2. Native UnitBuff fallback (by icon texture match)
	for i = 1, 32 do
		local tex = UnitBuff(unit, i)
		if not tex then break end
		if string.find(tex, "Ability_Stealth") then
			return true, "Stealth"
		elseif string.find(tex, "Ability_Druid_Prowl") or string.find(tex, "Prowl") then
			return true, "Prowl"
		elseif string.find(tex, "Ability_Racial_ShadowMeld") or string.find(tex, "ShadowMeld") or string.find(tex, "Shadowmeld") then
			return true, "Shadowmeld"
		elseif string.find(tex, "Spell_Nature_Invisibilty") or string.find(tex, "Invis") then
			return true, "Invisibility"
		elseif string.find(tex, "INV_Misc_EngGizmos_04") then
			return true, "Cloaking"
		end
	end

	return false, nil
end

local function IsHostilePlayer(guid, name)
	if not guid and not name then return false end

	if name and friendlyCache[name] then return false end
	if name and hostileCache[name] then return true end

	if name and name == UnitName("player") then
		friendlyCache[name] = true
		return false
	end
	local pGUID = UnitGUID("player")
	if guid and pGUID and guid == pGUID then
		return false
	end

	-- In SuperWoW / 1.12.1, player GUIDs start with 0x0000
	if guid and type(guid) == "string" and string.sub(guid, 1, 6) ~= "0x0000" then
		return false
	end

	if guid and UnitIsPlayer and not UnitIsPlayer(guid) then
		return false
	end

	if guid and UnitCanAttack and UnitCanAttack("player", guid) then
		if name then hostileCache[name] = true end
		return true
	end

	local f = guid and UnitFactionGroup and UnitFactionGroup(guid)
	local pf = GetPlayerFaction()
	if f and pf then
		if f ~= pf then
			if name then hostileCache[name] = true end
			return true
		else
			if name then friendlyCache[name] = true end
			return false
		end
	end

	if guid and UnitIsFriend and UnitIsFriend("player", guid) == 1 then
		if name then friendlyCache[name] = true end
		return false
	end

	if name and hostileCache[name] then
		return true
	end

	return false
end

-- -------------------------------------------------------------------------- --
-- Allocation-Free Insertion Sort by lastSeen (Descending)                    --
-- -------------------------------------------------------------------------- --
local function SortTrackedEnemies()
	for i = 2, activeEnemyCount do
		local j = i
		while j > 1 and (trackedEnemies[j].lastSeen > trackedEnemies[j - 1].lastSeen) do
			trackedEnemies[j], trackedEnemies[j - 1] = trackedEnemies[j - 1], trackedEnemies[j]
			j = j - 1
		end
	end
	for i = 1, activeEnemyCount do
		nameToTrackIndex[trackedEnemies[i].name] = i
	end
end

-- -------------------------------------------------------------------------- --
-- Record / Update Hostile Player Entry                                       --
-- -------------------------------------------------------------------------- --
function Spy:RecordEnemy(name, classToken, level, guid, healthPct, isStealth, stealthSpell, race)
	if not name or name == "" then return end
	if friendlyCache[name] then return end

	local opt = GetSpySettings()
	if opt and not opt.Enabled then return end
	if Targets and Targets.activeBG then return end

	local now = GetTime()
	local idx = nameToTrackIndex[name]
	local isNew = false

	if not idx then
		if activeEnemyCount < MAX_SPY_ENEMIES then
			activeEnemyCount = activeEnemyCount + 1
			idx = activeEnemyCount
		else
			idx = activeEnemyCount
			if trackedEnemies[idx].name then
				nameToTrackIndex[trackedEnemies[idx].name] = nil
			end
		end
		nameToTrackIndex[name] = idx
		isNew = true
	end

	local e = trackedEnemies[idx]
	e.name = name
	e.shortName = StripRealm(name)
	if classToken then
		e.classToken = (Targets and Targets.ResolveClassToken and Targets.ResolveClassToken(classToken)) or classToken
	end

	-- Race Resolution Pipeline
	if race then
		race = FormatRace(race)
	end
	if not race and guid and UnitRace then
		local r = UnitRace(guid)
		if r and r ~= "" then
			race = FormatRace(r)
		end
	end
	if not race and playerRaceCache[name] then
		race = playerRaceCache[name]
	end
	if not race and (e.classToken or classToken) then
		race = InferRaceFromFactionAndClass(e.classToken or classToken)
	end

	if race then
		playerRaceCache[name] = race
		e.race = race
	end

	if level and level > 0 then e.level = level end
	if guid then
		e.guid = guid
		guidToName[guid] = name
	end
	if healthPct then e.healthPct = healthPct end
	e.lastSeen = now

	if isStealth ~= nil then
		e.isStealthed = isStealth
		if stealthSpell then e.stealthSpell = stealthSpell end
		if not isStealth then e.wasStealthedAlerted = false end
	end

	-- Audio notification with debouncing
	if opt and opt.SoundAlert and isNew then
		local lastSound = soundDebounce[name] or 0
		if (now - lastSound) > 8 then
			soundDebounce[name] = now
			if e.isStealthed and opt.StealthAlert then
				e.wasStealthedAlerted = true
				PlaySoundFile(SOUND_STEALTH_DETECTED, "Master")
				Spy:ShowAlert(e.stealthSpell or "Stealth", e.name, e.classToken, e.guid)
			else
				PlaySoundFile(SOUND_ENEMY_DETECTED, "Master")
			end
		end
	elseif opt and opt.StealthAlert and isStealth and not e.wasStealthedAlerted then
		e.wasStealthedAlerted = true
		PlaySoundFile(SOUND_STEALTH_DETECTED, "Master")
		Spy:ShowAlert(e.stealthSpell or "Stealth", e.name, e.classToken, e.guid)
	end

	SortTrackedEnemies()
	Spy:RenderRows()
end

function Spy:SetUnitStealthState(name, isStealthed, spellName)
	if not name or not nameToTrackIndex[name] then return end
	local idx = nameToTrackIndex[name]
	local e = trackedEnemies[idx]
	e.isStealthed = isStealthed
	if spellName then e.stealthSpell = spellName end
	e.lastSeen = GetTime()

	local opt = GetSpySettings()
	if isStealthed then
		if opt and opt.StealthAlert and not e.wasStealthedAlerted then
			e.wasStealthedAlerted = true
			PlaySoundFile(SOUND_STEALTH_DETECTED, "Master")
			Spy:ShowAlert(spellName or e.stealthSpell or "Stealth", name, e.classToken, e.guid)
		end
	else
		e.wasStealthedAlerted = false
	end

	SortTrackedEnemies()
	Spy:RenderRows()
end

-- -------------------------------------------------------------------------- --
-- Clear History                                                              --
-- -------------------------------------------------------------------------- --
function Spy:ClearHistory()
	table.wipe(nameToTrackIndex)
	for i = 1, MAX_SPY_ENEMIES do
		local e = trackedEnemies[i]
		e.name = nil
		e.shortName = nil
		e.classToken = nil
		e.race = nil
		e.level = nil
		e.healthPct = 100
		e.lastSeen = 0
		e.guid = nil
		e.isStealthed = false
		e.stealthSpell = nil
		e.wasStealthedAlerted = false
	end
	activeEnemyCount = 0
	Spy:RenderRows()
end

-- -------------------------------------------------------------------------- --
-- Formatting Elapsed Time                                                    --
-- -------------------------------------------------------------------------- --
local function FormatElapsedTime(lastSeen, now)
	local diff = math.max(0, math.floor(now - lastSeen))
	if diff < 60 then
		return diff .. "s"
	else
		local mins = math.floor(diff / 60)
		return mins .. "m"
	end
end

-- -------------------------------------------------------------------------- --
-- Spy Frame Creation & Interactions                                          --
-- -------------------------------------------------------------------------- --
local function SpyFrame_OnDragStart(self)
	local f = self or this or (Spy and Spy.Frame)
	if f and f.StartMoving then f:StartMoving() end
end

local function SpyFrame_OnDragStop(self)
	local f = self or this or (Spy and Spy.Frame)
	if f and f.StopMovingOrSizing then f:StopMovingOrSizing() end
	Spy:SavePosition()
end

local function SpyClearBtn_OnClick(self)
	Spy:ClearHistory()
end

local function SpyRow_OnClick(self, button)
	local b = self or this
	local btn = button or arg1
	local tName = b.targetName
	if not tName then return end
	local tGUID = b.targetGUID or guidToName[tName]

	if btn == "LeftButton" then
		if tGUID then
			TargetUnit(tGUID)
		else
			TargetByName(tName, true)
		end
	elseif btn == "RightButton" then
		if tGUID then
			FocusUnit(tGUID)
		else
			TargetByName(tName, true)
			if UnitExists("target") and UnitName("target") == tName then
				FocusUnit("target")
			end
		end
	end
end

local function SpyRow_OnEnter(self)
	local b = self or this
	if not b.targetName then return end
	GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
	GameTooltip:ClearLines()
	GameTooltip:AddLine(b.targetName, 1, 1, 1)

	local race = b.targetRace or (playerRaceCache and playerRaceCache[b.targetName])
	local cls = FormatClass(b.targetClass)
	local raceClassText = nil

	if race and cls then
		raceClassText = race .. " " .. cls
	elseif race then
		raceClassText = race
	elseif cls then
		raceClassText = cls
	end

	if raceClassText then
		local color = (Targets and Targets.GetClassColor and Targets.GetClassColor(b.targetClass)) or { r = 0.8, g = 0.8, b = 0.8 }
		GameTooltip:AddLine(raceClassText, color.r, color.g, color.b)
	end

	if b.targetLevel and b.targetLevel > 0 then
		GameTooltip:AddLine("Level: " .. b.targetLevel, 1, 0.82, 0)
	end
	if b.targetHealth then
		GameTooltip:AddLine("Health: " .. b.targetHealth .. "%", 0.2, 1, 0.2)
	end
	if b.targetStealth then
		GameTooltip:AddLine("State: STEALTHED (" .. (b.targetStealthSpell or "Stealth") .. ")", 0.4, 0.6, 1)
	end
	if b.targetLastSeen and b.targetLastSeen > 0 then
		local diff = math.max(0, math.floor(GetTime() - b.targetLastSeen))
		GameTooltip:AddLine("Last Seen: " .. (diff < 60 and (diff .. "s ago") or (math.floor(diff / 60) .. "m ago")), 0.7, 0.7, 0.7)
	end
	GameTooltip:AddLine("Left-Click: Target  |  Right-Click: Focus", 0.5, 0.5, 0.5)
	GameTooltip:Show()
end

local function SpyRow_OnLeave(self)
	GameTooltip:Hide()
end

function Spy:CreateFrames()
	if Spy.Frame then return end

	local f = CreateFrame("Frame", "AutoBG_SpyFrame", UIParent)
	BattlegroundTargets_SpyFrame = f -- Compatibility alias
	f:SetWidth(185)
	f:SetHeight(40)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:SetClampedToScreen(true)
	f:Hide()

	f:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 12, edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 }
	})
	f:SetBackdropColor(0.05, 0.05, 0.08, 0.85)
	f:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.9)

	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", SpyFrame_OnDragStart)
	f:SetScript("OnDragStop", SpyFrame_OnDragStop)

	-- Header Title
	local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	title:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -6)
	title:SetText("Spy (0)")
	f.Title = title

	-- Clear Button (X)
	local clearBtn = CreateFrame("Button", nil, f)
	clearBtn:SetWidth(14)
	clearBtn:SetHeight(14)
	clearBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -4)
	local clearText = clearBtn:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	clearText:SetPoint("CENTER", 0, 0)
	clearText:SetText("x")
	clearBtn:SetScript("OnClick", SpyClearBtn_OnClick)

	-- Pre-allocated Rows
	f.rows = {}
	for i = 1, MAX_SPY_ROWS do
		local btn = CreateFrame("Button", "AutoBG_SpyRow" .. i, f)
		_G["BattlegroundTargets_SpyRow" .. i] = btn -- Compatibility alias
		btn:SetWidth(175)
		btn:SetHeight(20)
		btn:SetPoint("TOPLEFT", f, "TOPLEFT", 5, -20 - (i - 1) * 21)

		-- Row Background
		local bg = btn:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetTexture(0, 0, 0, 0.6)
		btn.Bg = bg

		-- Status Bar (Class Colored)
		local sb = btn:CreateTexture(nil, "BORDER")
		sb:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
		sb:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
		sb:SetTexture(BAR_TEXTURE)
		btn.StatusBar = sb

		-- Icon (Class or Stealth)
		local icon = btn:CreateTexture(nil, "ARTWORK")
		icon:SetWidth(16)
		icon:SetHeight(16)
		icon:SetPoint("LEFT", btn, "LEFT", 2, 0)
		icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		btn.Icon = icon

		-- Level Text
		local lvl = btn:CreateFontString(nil, "OVERLAY")
		lvl:SetFont(FONT, 9, "OUTLINE")
		lvl:SetPoint("LEFT", icon, "RIGHT", 3, 0)
		lvl:SetTextColor(1, 0.82, 0)
		btn.LevelText = lvl

		-- Elapsed Time Text (anchored to row right border)
		local timeText = btn:CreateFontString(nil, "OVERLAY")
		timeText:SetFont(FONT, 8, "OUTLINE")
		timeText:SetPoint("RIGHT", btn, "RIGHT", -3, 0)
		timeText:SetTextColor(0.8, 0.8, 0.8)
		btn.TimeText = timeText

		-- State Tag (e.g. STEALTH, 95% - chained to left of timeText)
		local tag = btn:CreateFontString(nil, "OVERLAY")
		tag:SetFont(FONT, 8, "OUTLINE")
		tag:SetPoint("RIGHT", timeText, "LEFT", -3, 0)
		btn.TagText = tag

		-- Name Text (bounded between level and tag)
		local nameText = btn:CreateFontString(nil, "OVERLAY")
		nameText:SetFont(FONT, 10, "OUTLINE")
		nameText:SetPoint("LEFT", lvl, "RIGHT", 3, 0)
		nameText:SetPoint("RIGHT", tag, "LEFT", -3, 0)
		nameText:SetJustifyH("LEFT")
		btn.NameText = nameText

		btn:EnableMouse(true)
		btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		btn:SetScript("OnClick", SpyRow_OnClick)
		btn:SetScript("OnEnter", SpyRow_OnEnter)
		btn:SetScript("OnLeave", SpyRow_OnLeave)

		btn:Hide()
		f.rows[i] = btn
	end

	Spy.Frame = f
	Spy:CreateAlertWindow()
	Spy:ApplyPosition()
	Spy:ApplyScale()
end

function Spy:CreateAlertWindow()
	if Spy.AlertWindow then return end

	local f = CreateFrame("Button", "AutoBG_SpyAlertWindow", UIParent)
	f:SetWidth(190)
	f:SetHeight(42)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:SetClampedToScreen(true)
	f:Hide()

	f:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 12, edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 }
	})
	f:SetBackdropColor(0.06, 0.06, 0.10, 0.90)
	f:SetBackdropBorderColor(0.2, 0.8, 1.0, 0.95)

	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function()
		local frame = this or self
		if frame and frame.StartMoving then
			frame:StartMoving()
			frame.isMoving = true
		end
	end)
	f:SetScript("OnDragStop", function()
		local frame = this or self
		if frame and frame.StopMovingOrSizing then
			frame:StopMovingOrSizing()
			frame.isMoving = false
			Spy:SaveAlertPosition()
		end
	end)
	f:SetScript("OnClick", function()
		local frame = this or self
		if frame and frame.isMoving then return end
		local tGUID = frame and frame.targetGUID
		local tName = frame and frame.targetName
		if tGUID then
			TargetUnit(tGUID)
		elseif tName then
			TargetByName(tName, true)
		end
	end)

	-- Icon
	local icon = f:CreateTexture(nil, "ARTWORK")
	icon:SetWidth(30)
	icon:SetHeight(30)
	icon:SetPoint("LEFT", f, "LEFT", 6, 0)
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	icon:SetTexture("Interface\\Icons\\Ability_Stealth")
	f.Icon = icon

	-- Title
	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 6, -2)
	title:SetText("|cff00ffffStealth Detected!|r")
	f.Title = title

	-- Name
	local nameText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	nameText:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 6, 3)
	nameText:SetText("Unknown")
	f.Name = nameText

	Spy.AlertWindow = f
	Spy:ApplyAlertPosition()
end

-- -------------------------------------------------------------------------- --
-- Position & Scale Management                                                --
-- -------------------------------------------------------------------------- --
function Spy:ApplyAlertPosition()
	if not Spy.AlertWindow then return end
	local opt = GetSpySettings()
	local x = opt and opt.alertPosX
	local y = opt and opt.alertPosY

	if not (x and y) and AutoBG_Settings and AutoBG_Settings.Positions and AutoBG_Settings.Positions["AutoBG_SpyAlertWindow"] then
		x = AutoBG_Settings.Positions["AutoBG_SpyAlertWindow"].x
		y = AutoBG_Settings.Positions["AutoBG_SpyAlertWindow"].y
	end

	Spy.AlertWindow:ClearAllPoints()
	if x and y then
		Spy.AlertWindow:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
	else
		Spy.AlertWindow:SetPoint("TOP", UIParent, "TOP", 0, -140)
	end
end

function Spy:SaveAlertPosition()
	if not Spy.AlertWindow then return end
	local opt = GetSpySettings()
	opt.alertPosX = Spy.AlertWindow:GetLeft()
	opt.alertPosY = Spy.AlertWindow:GetTop()

	if AutoBG_Settings then
		AutoBG_Settings.Positions = AutoBG_Settings.Positions or {}
		AutoBG_Settings.Positions["AutoBG_SpyAlertWindow"] = {
			x = opt.alertPosX,
			y = opt.alertPosY,
		}
	end
end

function Spy:ResetAlertPosition()
	local opt = GetSpySettings()
	if opt then
		opt.alertPosX = nil
		opt.alertPosY = nil
	end
	if AutoBG_Settings and AutoBG_Settings.Positions then
		AutoBG_Settings.Positions["AutoBG_SpyAlertWindow"] = nil
	end
	Spy:ApplyAlertPosition()
end

local alertDismissTimer = 0

function Spy:ShowAlert(spellName, enemyName, classToken, guid)
	if not Spy.AlertWindow then Spy:CreateAlertWindow() end
	local w = Spy.AlertWindow
	if not w then return end

	local sName = spellName or "Stealth"
	local tex = "Interface\\Icons\\Ability_Stealth"
	local titleText = "|cff00ffffStealth Detected!|r"
	local borderR, borderG, borderB = 0.2, 0.8, 1.0

	if sName == "Prowl" then
		tex = PROWL_TEXTURE or "Interface\\Icons\\Ability_Druid_Prowl"
		titleText = "|cffff9900Prowl Detected!|r"
		borderR, borderG, borderB = 1.0, 0.5, 0.0
	elseif sName == "Shadowmeld" then
		tex = "Interface\\Icons\\Ability_Racial_ShadowMeld"
		titleText = "|cffbb88ffShadowmeld Detected!|r"
		borderR, borderG, borderB = 0.7, 0.4, 0.9
	elseif sName == "Vanish" then
		tex = "Interface\\Icons\\Ability_Stealth"
		titleText = "|cff00ffffVanish Detected!|r"
		borderR, borderG, borderB = 0.3, 0.9, 1.0
	elseif string.find(sName, "Invis") then
		tex = "Interface\\Icons\\Spell_Nature_Invisibilty"
		titleText = "|cff88ccffInvisibility Detected!|r"
		borderR, borderG, borderB = 0.5, 0.8, 1.0
	elseif sName == "Cloaking" then
		tex = "Interface\\Icons\\INV_Misc_EngGizmos_04"
		titleText = "|cffffff00Cloaking Detected!|r"
		borderR, borderG, borderB = 0.9, 0.9, 0.2
	end

	w.Icon:SetTexture(tex)
	w.Title:SetText(titleText)
	w.targetName = enemyName or "Unknown"
	w.targetGUID = guid

	local color = (classToken and Targets and Targets.GetClassColor and Targets.GetClassColor(classToken)) or { r = 1, g = 1, b = 1 }
	w.Name:SetText(enemyName or "Unknown")
	w.Name:SetTextColor(color.r, color.g, color.b)

	w:SetBackdropBorderColor(borderR, borderG, borderB, 0.95)

	local titleW = (w.Title.GetStringWidth and w.Title:GetStringWidth()) or 100
	local nameW = (w.Name.GetStringWidth and w.Name:GetStringWidth()) or 80
	local neededW = math.max(190, math.max(titleW, nameW) + 52)
	w:SetWidth(neededW)

	w:Show()

	alertDismissTimer = GetTime() + 4.5
	if C_Timer and C_Timer.After then
		C_Timer.After(4.6, function()
			if not Spy.isTestMode and GetTime() >= alertDismissTimer then
				if Spy.AlertWindow and Spy.AlertWindow:IsShown() then
					Spy.AlertWindow:Hide()
				end
			end
		end)
	end
end

function Spy:ApplyPosition()
	Spy:ApplyAlertPosition()
	if not Spy.Frame then return end
	local opt = GetSpySettings()
	local x = opt and opt.posX
	local y = opt and opt.posY

	if not (x and y) and AutoBG_Settings and AutoBG_Settings.Positions and AutoBG_Settings.Positions["AutoBG_SpyFrame"] then
		x = AutoBG_Settings.Positions["AutoBG_SpyFrame"].x
		y = AutoBG_Settings.Positions["AutoBG_SpyFrame"].y
	end

	Spy.Frame:ClearAllPoints()
	if x and y then
		Spy.Frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
	else
		Spy.Frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 100, -200)
	end
end

function Spy:SavePosition()
	if not Spy.Frame then return end
	local opt = GetSpySettings()
	opt.posX = Spy.Frame:GetLeft()
	opt.posY = Spy.Frame:GetTop()

	if AutoBG_Settings and AutoBG_Settings.Targets then
		AutoBG_Settings.Targets.pos = AutoBG_Settings.Targets.pos or {}
		AutoBG_Settings.Targets.pos["AutoBG_SpyFrame_posX"] = opt.posX
		AutoBG_Settings.Targets.pos["AutoBG_SpyFrame_posY"] = opt.posY
	end
end

function Spy:ResetPosition()
	local opt = GetSpySettings()
	opt.posX = nil
	opt.posY = nil
	if AutoBG_Settings and AutoBG_Settings.Positions then
		AutoBG_Settings.Positions["AutoBG_SpyFrame"] = nil
	end
	Spy:ResetAlertPosition()
	Spy:ApplyPosition()
end

function Spy:ApplyScale()
	if not Spy.Frame then return end
	local opt = GetSpySettings()
	local scale = (opt and opt.Scale) or 1.0
	Spy.Frame:SetScale(scale)
end

-- -------------------------------------------------------------------------- --
-- Render Spy Rows                                                            --
-- -------------------------------------------------------------------------- --
function Spy:RenderRows()
	if not Spy.Frame then return end

	local opt = GetSpySettings()
	if not opt or not opt.Enabled or (Targets and Targets.activeBG) then
		Spy.Frame:Hide()
		return
	end

	local now = GetTime()
	local maxRows = math.min(MAX_SPY_ROWS, opt.MaxRows or 5)
	local count = Spy.isTestMode and 3 or activeEnemyCount

	if count == 0 then
		if opt.AutoHide then
			Spy.Frame:Hide()
		else
			Spy.Frame.Title:SetText("Spy (0)")
			for i = 1, MAX_SPY_ROWS do
				Spy.Frame.rows[i]:Hide()
			end
			Spy.Frame:SetHeight(26)
			Spy.Frame:Show()
		end
		return
	end

	Spy.Frame.Title:SetText("Spy (" .. count .. ")")
	local visibleCount = math.min(count, maxRows)

	for i = 1, visibleCount do
		local row = Spy.Frame.rows[i]
		local data = trackedEnemies[i]

		row.targetName = data.name
		row.targetGUID = data.guid
		row.targetClass = data.classToken
		row.targetRace = data.race or (data.name and playerRaceCache[data.name])
		row.targetLevel = data.level
		row.targetHealth = data.healthPct
		row.targetStealth = data.isStealthed
		row.targetStealthSpell = data.stealthSpell
		row.targetLastSeen = data.lastSeen

		-- Class color
		local color = (Targets and Targets.GetClassColor and Targets.GetClassColor(data.classToken)) or { r = 0.6, g = 0.6, b = 0.6 }
		row.StatusBar:SetVertexColor(color.r, color.g, color.b, 0.9)

		-- Level
		if data.level and data.level > 0 then
			row.LevelText:SetText(tostring(data.level))
		else
			row.LevelText:SetText("??")
		end

		-- Name
		row.NameText:SetText(data.shortName or data.name or "Unknown")

		-- Icon & State Tag
		if data.isStealthed then
			local sName = data.stealthSpell or "Stealth"
			local tex = (sName == "Prowl" and PROWL_TEXTURE) or "Interface\\Icons\\Ability_Stealth"
			row.Icon:SetTexture(tex)
			row.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
			row.Icon:Show()
			local tag = (sName == "Prowl" and "PROWL")
				or (sName == "Vanish" and "VANISH")
				or (sName == "Shadowmeld" and "MELD")
				or (sName == "Cloaking" and "CLOAK")
				or (string.find(sName, "Invis") and "INVIS")
				or "STEALTH"
			row.TagText:SetText("|cff00ffff" .. tag .. "|r")
		else
			if data.classToken then
				row.Icon:SetTexture("Interface\\WorldStateFrame\\Icons-Classes")
				local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[data.classToken]
				if coords then
					row.Icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
				else
					row.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
				end
				row.Icon:Show()
			else
				row.Icon:Hide()
			end

			if data.healthPct and data.healthPct < 100 then
				row.TagText:SetText(data.healthPct .. "%")
			else
				row.TagText:SetText("")
			end
		end

		-- Time elapsed
		row.TimeText:SetText(FormatElapsedTime(data.lastSeen, now))
		row:Show()
	end

	for i = visibleCount + 1, MAX_SPY_ROWS do
		Spy.Frame.rows[i]:Hide()
	end

	Spy.Frame:SetHeight(24 + (visibleCount * 21) + 4)
	Spy.Frame:Show()
end

-- -------------------------------------------------------------------------- --
-- Periodic Purge Ticker (Hardware C_Timer.NewTicker, 1.0s cadence)           --
-- -------------------------------------------------------------------------- --
local function OnSpyTick()
	if Targets and Targets.activeBG then
		if Spy.Frame and Spy.Frame:IsShown() then Spy.Frame:Hide() end
		return
	end

	local opt = GetSpySettings()
	if not opt or not opt.Enabled then
		if Spy.Frame and Spy.Frame:IsShown() then Spy.Frame:Hide() end
		return
	end

	if Spy.isTestMode then return end

	local now = GetTime()
	local timeout = opt.Timeout or 30
	local changed = false

	local i = 1
	while i <= activeEnemyCount do
		local e = trackedEnemies[i]
		if (now - e.lastSeen) > timeout then
			nameToTrackIndex[e.name] = nil
			for k = i, activeEnemyCount - 1 do
				trackedEnemies[k], trackedEnemies[k + 1] = trackedEnemies[k + 1], trackedEnemies[k]
			end
			trackedEnemies[activeEnemyCount].name = nil
			trackedEnemies[activeEnemyCount].shortName = nil
			trackedEnemies[activeEnemyCount].classToken = nil
			trackedEnemies[activeEnemyCount].race = nil
			trackedEnemies[activeEnemyCount].level = nil
			trackedEnemies[activeEnemyCount].healthPct = 100
			trackedEnemies[activeEnemyCount].lastSeen = 0
			trackedEnemies[activeEnemyCount].guid = nil
			trackedEnemies[activeEnemyCount].isStealthed = false
			trackedEnemies[activeEnemyCount].stealthSpell = nil
			trackedEnemies[activeEnemyCount].wasStealthedAlerted = false
			activeEnemyCount = activeEnemyCount - 1
			changed = true
		else
			i = i + 1
		end
	end

	if changed then
		for k = 1, activeEnemyCount do
			nameToTrackIndex[trackedEnemies[k].name] = k
		end
	end

	Spy:RenderRows()
end

if C_Timer and C_Timer.NewTicker then
	C_Timer.NewTicker(1.0, OnSpyTick)
end

-- -------------------------------------------------------------------------- --
-- Test Mode Preview                                                          --
-- -------------------------------------------------------------------------- --
function Spy:EnableTestMode()
	Spy.isTestMode = true
	local now = GetTime()

	local mock = {
		{ name = "Shadowstalker-Realm", classToken = "ROGUE", race = "Night Elf", level = 60, healthPct = 82, isStealthed = true, stealthSpell = "Stealth", lastSeen = now - 2 },
		{ name = "Frostweaver-Realm", classToken = "MAGE", race = "Gnome", level = 60, healthPct = 100, isStealthed = false, lastSeen = now - 9 },
		{ name = "Ironbreaker-Realm", classToken = "WARRIOR", race = "Dwarf", level = 58, healthPct = 65, isStealthed = false, lastSeen = now - 22 },
	}

	for i = 1, 3 do
		local e = trackedEnemies[i]
		local m = mock[i]
		e.name = m.name
		e.shortName = StripRealm(m.name)
		e.classToken = m.classToken
		e.race = m.race
		e.level = m.level
		e.healthPct = m.healthPct
		e.isStealthed = m.isStealthed
		e.stealthSpell = m.stealthSpell
		e.lastSeen = m.lastSeen
		e.guid = nil
	end

	Spy:RenderRows()
	Spy:ShowAlert("Stealth", "Shadowstalker-Realm", "ROGUE", nil)
end

function Spy:DisableTestMode()
	Spy.isTestMode = false
	Spy:ClearHistory()
	if Spy.AlertWindow and Spy.AlertWindow:IsShown() then
		Spy.AlertWindow:Hide()
	end
end

function Spy:ToggleTestMode()
	if Spy.isTestMode then
		Spy:DisableTestMode()
	else
		Spy:EnableTestMode()
	end
end

function Spy:OnBattlegroundChanged(inBG)
	if inBG then
		if Spy.Frame and Spy.Frame:IsShown() then
			Spy.Frame:Hide()
		end
		if Spy.AlertWindow and Spy.AlertWindow:IsShown() then
			Spy.AlertWindow:Hide()
		end
	else
		Spy:RenderRows()
	end
end

-- -------------------------------------------------------------------------- --
-- Event Telemetry Engine                                                     --
-- -------------------------------------------------------------------------- --
local eventFrame = CreateFrame("Frame", "AutoBG_SpyEventFrame", UIParent)
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("UNIT_CASTEVENT")
eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
eventFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
eventFrame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_BUFFS")
eventFrame:RegisterEvent("CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF")
eventFrame:RegisterEvent("CHAT_MSG_SPELL_AURA_GONE_OTHER")
eventFrame:RegisterEvent("CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE")
eventFrame:RegisterEvent("CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS")

local function Spy_OnEvent(arg1_param, arg2_param, arg3_param, arg4_param, arg5_param)
	local ev = (type(arg1_param) == "string" and arg1_param) or arg2_param or event
	local a1 = (type(arg1_param) == "string" and (arg2_param or arg1)) or arg3_param or arg1
	local a2 = (type(arg1_param) == "string" and (arg3_param or arg2)) or arg4_param or arg2
	local a3 = (type(arg1_param) == "string" and (arg4_param or arg3)) or arg5_param or arg3
	local a4 = (type(arg1_param) == "string" and arg5_param) or arg4

	if ev == "PLAYER_LOGIN" then
		Spy:CreateFrames()
		return
	end

	if Targets and Targets.activeBG then return end
	local opt = GetSpySettings()
	if not opt or not opt.Enabled then return end

	if ev == "UNIT_CASTEVENT" then
		local casterGUID = a1
		local eventType = a3
		local spellId = a4
		if not casterGUID then return end

		local rawName = UnitName(casterGUID) or guidToName[casterGUID]
		if not IsHostilePlayer(casterGUID, rawName) then return end

		local classToken = UnitClass(casterGUID)
		local level = UnitLevel(casterGUID)
		local isStealth = false
		local sName = nil
		local detectedRace = nil

		if UnitRace then
			local r = UnitRace(casterGUID)
			if r and r ~= "" then
				detectedRace = FormatRace(r)
			end
		end

		if not detectedRace and spellId and RACIAL_SPELL_IDS[spellId] then
			detectedRace = RACIAL_SPELL_IDS[spellId]
		end

		if eventType == "CAST" and Targets and Targets.CheckIsStealthSpell then
			local isS, spell, tex = Targets.CheckIsStealthSpell(spellId)
			if isS then
				isStealth = true
				sName = spell
			end
		end

		if not detectedRace and sName and RACIAL_SPELL_NAMES[sName] then
			detectedRace = RACIAL_SPELL_NAMES[sName]
		end

		if rawName then
			Spy:RecordEnemy(rawName, classToken, level, casterGUID, nil, isStealth, sName, detectedRace)
			if eventType == "START" or eventType == "CHANNEL" or eventType == "MAINHAND" or eventType == "OFFHAND" then
				Spy:SetUnitStealthState(rawName, false)
			end
		end

	elseif ev == "NAME_PLATE_UNIT_ADDED" then
		local unit = a1
		if not unit or not UnitIsPlayer(unit) then return end
		if not UnitCanAttack("player", unit) and UnitFactionGroup(unit) == GetPlayerFaction() then return end

		local name = UnitName(unit)
		if not name then return end
		hostileCache[name] = true

		local guid = UnitGUID(unit)
		local _, classToken = UnitClass(unit)
		local level = UnitLevel(unit)
		local rawRace = UnitRace(unit)
		local hp = UnitHealth(unit)
		local maxHp = UnitHealthMax(unit)
		local pct = 100
		if maxHp and maxHp > 0 then
			pct = math.floor((hp / maxHp) * 100 + 0.5)
		end

		local isStealth, sName = Spy:CheckUnitStealth(unit)
		Spy:RecordEnemy(name, classToken, level, guid, pct, isStealth, sName, rawRace)

	elseif ev == "PLAYER_TARGET_CHANGED" or ev == "UPDATE_MOUSEOVER_UNIT" or ev == "PLAYER_FOCUS_CHANGED" then
		local unit = ev == "PLAYER_TARGET_CHANGED" and "target" or (ev == "PLAYER_FOCUS_CHANGED" and "focus" or "mouseover")
		if UnitExists(unit) and UnitIsPlayer(unit) and UnitCanAttack("player", unit) then
			local name = UnitName(unit)
			if name then
				hostileCache[name] = true
				local guid = UnitGUID(unit)
				local _, classToken = UnitClass(unit)
				local level = UnitLevel(unit)
				local rawRace = UnitRace(unit)
				local hp = UnitHealth(unit)
				local maxHp = UnitHealthMax(unit)
				local pct = 100
				if maxHp and maxHp > 0 then
					pct = math.floor((hp / maxHp) * 100 + 0.5)
				end
				local isStealth, sName = Spy:CheckUnitStealth(unit)
				Spy:RecordEnemy(name, classToken, level, guid, pct, isStealth, sName, rawRace)
			end
		end

	elseif ev == "UNIT_AURA" then
		local unit = a1
		if unit and (unit == "target" or unit == "mouseover" or unit == "focus") then
			if UnitExists(unit) and UnitIsPlayer(unit) and UnitCanAttack("player", unit) then
				local name = UnitName(unit)
				if name then
					hostileCache[name] = true
					local guid = UnitGUID(unit)
					local _, classToken = UnitClass(unit)
					local level = UnitLevel(unit)
					local rawRace = UnitRace(unit)
					local hp = UnitHealth(unit)
					local maxHp = UnitHealthMax(unit)
					local pct = 100
					if maxHp and maxHp > 0 then
						pct = math.floor((hp / maxHp) * 100 + 0.5)
					end
					local isStealth, sName = Spy:CheckUnitStealth(unit)
					Spy:RecordEnemy(name, classToken, level, guid, pct, isStealth, sName, rawRace)
				end
			end
		end

	elseif ev == "CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF" then
		if a1 then
			local _, _, enemyName, spellName = string.find(a1, "^(.-) casts (.-)%.$")
			if not enemyName then
				_, _, enemyName, spellName = string.find(a1, "^(.-) performs (.-)%.$")
			end
			if enemyName and spellName then
				hostileCache[enemyName] = true
				local isStealth = Targets and Targets.CheckIsStealthName and Targets.CheckIsStealthName(spellName)
				local detectedRace = RACIAL_SPELL_NAMES[spellName]
				Spy:RecordEnemy(enemyName, nil, nil, nil, nil, isStealth and true or false, spellName, detectedRace)
			end
		end

	elseif ev == "CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_BUFFS" then
		if a1 then
			local _, _, enemyName, buffName = string.find(a1, "^(.-) gains (.-)%.$")
			if enemyName and buffName then
				hostileCache[enemyName] = true
				local isStealth = Targets and Targets.CheckIsStealthName and Targets.CheckIsStealthName(buffName)
				local detectedRace = RACIAL_SPELL_NAMES[buffName]
				Spy:RecordEnemy(enemyName, nil, nil, nil, nil, isStealth and true or false, buffName, detectedRace)
			end
		end

	elseif ev == "CHAT_MSG_SPELL_AURA_GONE_OTHER" then
		if a1 then
			local _, _, buffName, enemyName = string.find(a1, "^(.-) fades from (.-)%.$")
			if buffName and enemyName and Targets and Targets.CheckIsStealthName and Targets.CheckIsStealthName(buffName) then
				Spy:SetUnitStealthState(enemyName, false)
			end
		end

	elseif ev == "CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE" then
		if a1 then
			local _, _, enemyName = string.find(a1, "^(.-)'s ")
			if enemyName then
				hostileCache[enemyName] = true
				Spy:RecordEnemy(enemyName)
				Spy:SetUnitStealthState(enemyName, false)
			end
		end

	elseif ev == "CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS" then
		if a1 then
			local _, _, enemyName = string.find(a1, "^(.-) hits ")
			if not enemyName then _, _, enemyName = string.find(a1, "^(.-) crits ") end
			if not enemyName then _, _, enemyName = string.find(a1, "^(.-) misses ") end
			if not enemyName then _, _, enemyName = string.find(a1, "^(.-) attacks%.") end
			if enemyName then
				hostileCache[enemyName] = true
				Spy:RecordEnemy(enemyName)
				Spy:SetUnitStealthState(enemyName, false)
			end
		end
	end
end
eventFrame:SetScript("OnEvent", Spy_OnEvent)
