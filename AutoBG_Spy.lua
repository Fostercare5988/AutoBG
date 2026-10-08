-- -------------------------------------------------------------------------- --
-- AutoBG: Open-World Spy Module (Consolidated from BattlegroundTargets)       --
-- Engineered natively for World of Warcraft 1.12.1 (Enhanced Engine)        --
-- Leveraging SuperWoW v2.2+, ClassicAPI v1.15.15+, UnitXP SP3                 --
-- -------------------------------------------------------------------------- --

-- Strict Engine Dependency Guard (Mandatory ClassicAPI v1.15.15+ & SuperWoW v2.2+)
local MIN_CLASSIC_API = 11515

if type(CLASSIC_API_VERSION) ~= "number" or not SUPERWOW_VERSION or
   CLASSIC_API_VERSION < MIN_CLASSIC_API then
	return
end

AutoBG_Spy = AutoBG_Spy or {}
local Spy = AutoBG_Spy
local Targets = AutoBG_Targets

-- Backwards-compatibility aliases
if not BattlegroundTargets then BattlegroundTargets = AutoBG_Targets or {} end
BattlegroundTargets.Spy = AutoBG_Spy

local MAX_SPY_ENEMIES = 20
local MAX_SPY_ROWS = 20
local FONT = "Fonts\\FRIZQT__.TTF"
local BAR_TEXTURE = [[Interface\AddOns\AutoBG\Textures\barTexture.tga]]
local PROWL_TEXTURE = [[Interface\AddOns\AutoBG\Textures\prowl.tga]]
-- Character-create atlas cells, inset to keep neighboring icons out of the crop.
local CLASS_ICON_TEXTURE = [[Interface\Glues\CharacterCreate\UI-CharacterCreate-Classes]]
local CLASS_ICON_COORDS = {
    WARRIOR = {0.0234375, 0.2265625, 0.0234375, 0.2265625},
    MAGE    = {0.2734375, 0.4765625, 0.0234375, 0.2265625},
    ROGUE   = {0.5234375, 0.7265625, 0.0234375, 0.2265625},
    DRUID   = {0.7734375, 0.97265625, 0.0234375, 0.2265625},
    HUNTER  = {0.0234375, 0.2265625, 0.2734375, 0.4765625},
    SHAMAN  = {0.2734375, 0.4765625, 0.2734375, 0.4765625},
    PRIEST  = {0.5234375, 0.7265625, 0.2734375, 0.4765625},
    WARLOCK = {0.7734375, 0.97265625, 0.2734375, 0.4765625},
    PALADIN = {0.0234375, 0.2265625, 0.5234375, 0.7265625},
}
function Spy:PlayEnemyDetectedSound()
	PlaySound("MapPing")
end

function Spy:PlayStealthDetectedSound()
	PlaySound("RaidWarning")
end

local SPY_DEFAULTS = {
	Enabled = true, SoundAlert = false, StealthAlert = true, StealthProximityOnly = true,
	AutoHide = false, Timeout = 30, MaxRows = 5, Scale = 1.0,
}
local function GetSpySettings()
	if not AutoBG_Settings then AutoBG_Settings = {} end
	AutoBG_Settings.Spy = AutoBG_Settings.Spy or {}
	for key, value in pairs(SPY_DEFAULTS) do
		if AutoBG_Settings.Spy[key] == nil then AutoBG_Settings.Spy[key] = value end
	end
	return AutoBG_Settings.Spy
end

function Spy:EnsureOptions()
	return GetSpySettings()
end

-- A short, bounded session history outlives visible rows. Row expiry, eviction
-- and clearing the list must not turn the same encounter into another alarm.
local contactHistory, contactByName, contactByGUID, contactCursor = {}, {}, {}, 0
local nextAlertAt = 0
local function GetContact(name, guid)
	local contact = guid and contactByGUID[guid] or contactByName[name]
	if contact and guid and contact.guid and contact.guid ~= guid then contact = nil end
	if contact then
		if contact.name ~= name and contactByName[contact.name] == contact then contactByName[contact.name] = nil end
		contact.name = name
		contactByName[name] = contact
		if guid then contact.guid, contactByGUID[guid] = guid, contact end
		return contact
	end
	contactCursor = contactCursor % 64 + 1
	contact = contactHistory[contactCursor] or {}
	if contact.name and contactByName[contact.name] == contact then contactByName[contact.name] = nil end
	if contact.guid and contactByGUID[contact.guid] == contact then contactByGUID[contact.guid] = nil end
	table.wipe(contact)
	contact.name, contact.guid = name, guid
	contactHistory[contactCursor], contactByName[name] = contact, contact
	if guid then contactByGUID[guid] = contact end
	return contact
end

local function ShowStealth(name, spell, classToken, guid, opt, inBattleground)
	local now, contact = GetTime(), GetContact(name, guid)
	if contact.lastStealth and now - contact.lastStealth < 60 then return true end
	contact.lastStealth = now
	-- Consume suppressed episodes: do not queue sounds to replay after a burst.
	if now < nextAlertAt then return true end
	nextAlertAt = now + 8
	if inBattleground or opt.SoundAlert then Spy:PlayStealthDetectedSound() end
	Spy:ShowAlert(spell or "Stealth", name, classToken, guid)
	return true
end

local STEALTH_ALERT_DISTANCE_SQUARED = 10 * 10
function Spy:NotifyStealth(name, spell, classToken, guid, inBattleground, observedUnit)
	if not name or name == "" then return false end
	local opt = GetSpySettings()
	if inBattleground then
		if AutoBG_Settings.Targets and AutoBG_Settings.Targets.StealthAlert == false then return end
	elseif not opt.Enabled or not opt.StealthAlert then
		return false
	elseif not opt.StealthProximityOnly then
		-- Spy-style mode reports a received stealth event without requiring a loaded unit.
		return ShowStealth(name, spell, classToken, guid, opt, false)
	end
	if not guid then return false end
	if not observedUnit or UnitGUID(observedUnit) ~= guid then
		-- Cast telemetry alone is not an alert. Resolve a currently loaded exact-name unit,
		-- then verify identity before applying the visibility, range, LOS and aura gates.
		local resolved = UnitTokenFromName(name, true)
		if not resolved then
			local realmAt = string.find(name, "-", 1, true)
			if realmAt then resolved = UnitTokenFromName(string.sub(name, 1, realmAt - 1), true) end
		end
		if not resolved or UnitGUID(resolved) ~= guid then return false end
		observedUnit = resolved
	end
	if not UnitExists(observedUnit) or not UnitIsVisible(observedUnit)
		or not UnitIsPlayer(observedUnit) or not UnitCanAttack("player", observedUnit) then return false end
	if UnitIsDead(observedUnit) or UnitIsGhost(observedUnit) then return false end
	local distanceSquared, checked = UnitDistanceSquared(observedUnit)
	if not checked or not distanceSquared or distanceSquared > STEALTH_ALERT_DISTANCE_SQUARED then return false end
	if UnitInLineOfSight(observedUnit) ~= true then return false end
	local stealthed, currentSpell = Targets.CheckUnitStealth(observedUnit)
	if not stealthed then return false end
	return ShowStealth(name, currentSpell or spell, classToken, guid, opt, inBattleground)
end

-- Reuse the bounded set of tracking entries.
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
local nameToGUID = {}
local groupNames = {}
local groupGUIDs = {}

Spy.isTestMode = false
local renderTimer, purgeTicker, OnSpyTick, alertTimer
local pendingObservations, spareObservations, pendingByGUID, pendingCount = {}, {}, {}, 0
for i = 1, MAX_SPY_ENEMIES do pendingObservations[i], spareObservations[i] = {}, {} end
local FlushObservations, flushingObservations
local function ClearObservations()
	for i = 1, pendingCount do
		pendingObservations[i].guid, pendingObservations[i].unit = nil, nil
	end
	pendingCount = 0
	table.wipe(pendingByGUID)
end

function Spy:HideAlert()
	if alertTimer then alertTimer:Cancel(); alertTimer = nil end
	if Spy.AlertWindow then Spy.AlertWindow:Hide() end
end

local function StopTicker()
	if purgeTicker then purgeTicker:Cancel(); purgeTicker = nil end
end

local function MaintainTicker()
	local opt = GetSpySettings()
	if opt.Enabled and activeEnemyCount > 0 and not Spy.isTestMode and not (Targets and Targets.activeBG) then
		if not purgeTicker then purgeTicker = C_Timer.NewTicker(1, OnSpyTick) end
	else
		StopTicker()
	end
end

function Spy:RequestRender()
	if renderTimer or flushingObservations then return end
	-- One render after the current event burst. Direct settings actions still
	-- use RenderRows to apply immediately and cancel any pending render.
	local handle
	handle = C_Timer.NewTimer(0, function()
		if renderTimer ~= handle then return end
		renderTimer = nil
		Spy:RenderRows()
	end)
	renderTimer = handle
end

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

local function SetHostility(name, guid, hostile)
	if not name then return end
	local contact = guid and contactByGUID[guid] or contactByName[name]
	if contact and guid and contact.guid and contact.guid ~= guid then contact = nil end
	if hostile then contact = GetContact(name, guid) end
	if contact then contact.hostile = hostile and true or nil end
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

function Spy:CheckUnitStealth(unit)
	return Targets.CheckUnitStealth(unit)
end

local function IsGroupMember(name, guid, unit)
	if name then
		if name == UnitName("player") then return true end
		if groupNames[name] then return true end
		local realmAt = string.find(name, "-", 1, true)
		if realmAt and groupNames[string.sub(name, 1, realmAt - 1)] then return true end
	end
	if guid then
		local pGUID = UnitGUID("player")
		if pGUID and guid == pGUID then return true end
		if groupGUIDs[guid] then return true end
		if UnitInParty and UnitInParty(guid) then return true end
		if UnitInRaid and UnitInRaid(guid) then return true end
	end
	if unit then
		if UnitIsUnit and UnitIsUnit(unit, "player") then return true end
		if UnitInParty and UnitInParty(unit) then return true end
		if UnitInRaid and UnitInRaid(unit) then return true end
	end
	return false
end
Spy.IsGroupMember = IsGroupMember

local function IsHostilePlayer(guid, name, unit)
	if not guid and not name and not unit then return false end

	-- 1. Never hostile to player or any group member (party/raid)
	if IsGroupMember(name, guid, unit) then
		SetHostility(name, guid, false)
		return false
	end

	-- 2. In SuperWoW / 1.12.1, player GUIDs start with 0x0000
	if guid and type(guid) == "string" and string.sub(guid, 1, 6) ~= "0x0000" then
		return false
	end

	local checkTarget = unit or guid
	if checkTarget and UnitIsPlayer and not UnitIsPlayer(checkTarget) then
		return false
	end

	-- 3. Friendly check: if UnitIsFriend returns truthy and cannot attack, definitely not hostile
	if checkTarget and UnitIsFriend and UnitIsFriend("player", checkTarget) then
		local canAtk = UnitCanAttack and UnitCanAttack("player", checkTarget)
		if not canAtk then
			SetHostility(name, guid, false)
			return false
		end
	end

	-- 4. Authoritative attackability: if player can attack them, they are hostile
	if checkTarget and UnitCanAttack and UnitCanAttack("player", checkTarget) then
		SetHostility(name, guid, true)
		return true
	end

	-- 5. If we can verify they CANNOT be attacked:
	if checkTarget and UnitCanAttack and not UnitCanAttack("player", checkTarget) then
		SetHostility(name, guid, false)
		return false
	end

	-- 6. Different faction fallback (only when not verified unattackable above)
	local f = checkTarget and UnitFactionGroup and UnitFactionGroup(checkTarget)
	local pf = GetPlayerFaction()
	if f and pf then
		if f ~= pf then
			SetHostility(name, guid, true)
			return true
		else
			SetHostility(name, guid, false)
			return false
		end
	end

	-- 7. Hostility cache fallback (only if not a group member)
	local contact = name and contactByName[name]
	if contact and contact.hostile and (not guid or not contact.guid or contact.guid == guid) then
		return true
	end

	return false
end

-- -------------------------------------------------------------------------- --
-- Keep rows in detection order; activity updates must not move a player.     --
-- -------------------------------------------------------------------------- --
local function ResetEnemyEntry(e)
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
	e.observedGUID = nil
	e.pendingUntil = nil
end

function Spy:PruneGroupMembers()
	local changed = false
	local i = 1
	while i <= activeEnemyCount do
		local e = trackedEnemies[i]
		if e and (IsGroupMember(e.name, e.guid) or (e.guid and UnitIsFriend and UnitIsFriend("player", e.guid) and not (UnitCanAttack and UnitCanAttack("player", e.guid)))) then
			if e.name then
				SetHostility(e.name, e.guid, false)
				nameToTrackIndex[e.name] = nil
				if nameToGUID[e.name] == e.guid then nameToGUID[e.name] = nil end
			end
			if e.guid and guidToName[e.guid] == e.name then guidToName[e.guid] = nil end
			for k = i, activeEnemyCount - 1 do
				trackedEnemies[k], trackedEnemies[k + 1] = trackedEnemies[k + 1], trackedEnemies[k]
			end
			ResetEnemyEntry(trackedEnemies[activeEnemyCount])
			activeEnemyCount = activeEnemyCount - 1
			changed = true
		else
			i = i + 1
		end
	end
	if changed then
		for k = 1, activeEnemyCount do
			if trackedEnemies[k].name then
				nameToTrackIndex[trackedEnemies[k].name] = k
			end
		end
		Spy:RenderRows()
	end
end

local function UpdateGroupRoster()
	table.wipe(groupNames)
	table.wipe(groupGUIDs)

	local pName = UnitName("player")
	if pName then groupNames[pName] = true end
	local pGUID = UnitGUID("player")
	if pGUID then groupGUIDs[pGUID] = true end

	local numRaid = GetNumRaidMembers and GetNumRaidMembers() or 0
	if numRaid > 0 then
		for i = 1, numRaid do
			local name = GetRaidRosterInfo(i)
			if name then
				groupNames[name] = true
				local realmAt = string.find(name, "-", 1, true)
				if realmAt then groupNames[string.sub(name, 1, realmAt - 1)] = true end
			end
			local u = "raid" .. i
			local guid = UnitGUID(u)
			if guid then groupGUIDs[guid] = true end
		end
	else
		local numParty = GetNumPartyMembers and GetNumPartyMembers() or 0
		if numParty > 0 then
			for i = 1, numParty do
				local u = "party" .. i
				local name = UnitName(u)
				if name then
					groupNames[name] = true
					local realmAt = string.find(name, "-", 1, true)
					if realmAt then groupNames[string.sub(name, 1, realmAt - 1)] = true end
				end
				local guid = UnitGUID(u)
				if guid then groupGUIDs[guid] = true end
			end
		end
	end

	Spy:PruneGroupMembers()
end
Spy.UpdateGroupRoster = UpdateGroupRoster

-- -------------------------------------------------------------------------- --
-- Record / Update Hostile Player Entry                                       --
-- -------------------------------------------------------------------------- --
function Spy:RecordEnemy(name, classToken, level, guid, healthPct, isStealth, stealthSpell, race, observedUnit)
	if Spy.isTestMode then return end
	if not name or name == "" then return end
	if IsGroupMember(name, guid, observedUnit) then return end
	if observedUnit and UnitIsFriend and UnitIsFriend("player", observedUnit) and not (UnitCanAttack and UnitCanAttack("player", observedUnit)) then
		return
	end

	local opt = GetSpySettings()
	if opt and not opt.Enabled then return end
	if Targets and Targets.activeBG then return end

	local now = GetTime()
	local contact = GetContact(name, guid)
	local recentlySeen = contact.lastSeen and now - contact.lastSeen < 120
	contact.lastSeen = now
	local idx = nameToTrackIndex[name]
	local isNew = false

	local e
	if not idx then
		if activeEnemyCount < MAX_SPY_ENEMIES then
			activeEnemyCount = activeEnemyCount + 1
		end
		e = trackedEnemies[activeEnemyCount]
		if e.name then nameToTrackIndex[e.name] = nil end
		if e.guid and guidToName[e.guid] == e.name then guidToName[e.guid] = nil end
		if e.name and nameToGUID[e.name] == e.guid then nameToGUID[e.name] = nil end
		for i = activeEnemyCount, 2, -1 do
			trackedEnemies[i] = trackedEnemies[i - 1]
			nameToTrackIndex[trackedEnemies[i].name] = i
		end
		trackedEnemies[1] = e
		ResetEnemyEntry(e)
		idx = 1
		nameToTrackIndex[name] = idx
		isNew = true
	else
		e = trackedEnemies[idx]
	end
	-- A name may resolve to a different loaded object after a realm/session change.
	-- Retire the old identity before a row can be clicked or a stale cleanup runs.
	if guid and e.guid and e.guid ~= guid then
		if guidToName[e.guid] == e.name then guidToName[e.guid] = nil end
		ResetEnemyEntry(e)
		isNew = true
	end

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
	if not race and contact.race then
		race = contact.race
	end
	if race then
		contact.race = race
		e.race = race
	end

	if level and level > 0 then e.level = level end
	if guid then
		e.guid = guid
		guidToName[guid] = name
		nameToGUID[name] = guid
	end
	if healthPct then e.healthPct = healthPct end
	e.lastSeen = now
	if observedUnit and guid and UnitGUID(observedUnit) == guid then e.observedGUID = guid end

	if isStealth == false and observedUnit and e.pendingUntil and now < e.pendingUntil then isStealth = nil end
	if isStealth ~= nil then
		if isStealth and not observedUnit then e.pendingUntil = now + 0.5
		else e.pendingUntil = nil end
		e.isStealthed = isStealth
		if stealthSpell then e.stealthSpell = stealthSpell end
		if not isStealth then e.wasStealthedAlerted = false end
	end

	-- Stealth takes precedence over the nearby sound, including immediately after login.
	if opt.StealthAlert and e.isStealthed and not e.wasStealthedAlerted then
		e.wasStealthedAlerted = Spy:NotifyStealth(e.name, e.stealthSpell, e.classToken, e.guid, false, e.observedGUID) and true or false
	elseif opt.SoundAlert and isNew and not recentlySeen and (not e.isStealthed or not opt.StealthAlert) then
		if now >= nextAlertAt then
			nextAlertAt = now + 8
			Spy:PlayEnemyDetectedSound()
		end
	end

	Spy:RequestRender()
end

function Spy:SetUnitStealthState(name, isStealthed, spellName)
	if not name or not nameToTrackIndex[name] then return end
	local idx = nameToTrackIndex[name]
	local e = trackedEnemies[idx]
	e.isStealthed = isStealthed
	e.pendingUntil = nil
	if spellName then e.stealthSpell = spellName end
	e.lastSeen = GetTime()

	local opt = GetSpySettings()
	if isStealthed then
		if opt and opt.StealthAlert and not e.wasStealthedAlerted then
			e.wasStealthedAlerted = Spy:NotifyStealth(name, spellName or e.stealthSpell, e.classToken, e.guid, false, e.observedGUID) and true or false
		end
	else
		e.wasStealthedAlerted = false
	end

	Spy:RequestRender()
end

-- -------------------------------------------------------------------------- --
-- Clear History                                                              --
-- -------------------------------------------------------------------------- --
function Spy:ClearHistory()
	Spy.isTestMode = false
	Spy:HideAlert()
	ClearObservations()
	for _, contact in ipairs(contactHistory) do
		contact.hostile, contact.race = nil, nil
		contact.castSpell, contact.castAt, contact.castProvider = nil, nil, nil
	end
	table.wipe(nameToTrackIndex)
	table.wipe(guidToName)
	table.wipe(nameToGUID)
	for i = 1, MAX_SPY_ENEMIES do
		ResetEnemyEntry(trackedEnemies[i])
	end
	activeEnemyCount = 0
	Spy:RenderRows()
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
	Targets.SelectEnemy(b.targetName, b.targetGUID or nameToGUID[b.targetName], button or arg1)
end

local function SpyRow_OnEnter(self)
	local b = self or this
	if not b.targetName then return end
	GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
	GameTooltip:ClearLines()
	GameTooltip:AddLine(b.targetName, 1, 1, 1)

	local contact = contactByName[b.targetName]
	local race = b.targetRace or (contact and contact.race)
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
		local color = (Targets and Targets.GetClassColor and Targets.GetClassColor(b.targetClass)) or (AutoBG_GetClassColorRGB and AutoBG_GetClassColorRGB(b.targetClass)) or { r = 0.8, g = 0.8, b = 0.8 }
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
	f:SetWidth(190)
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
	f:SetBackdropColor(0.04, 0.04, 0.06, 0.85)
	f:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.9)

	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", SpyFrame_OnDragStart)
	f:SetScript("OnDragStop", SpyFrame_OnDragStop)

	-- Header Title
	local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	title:SetPoint("TOP", f, "TOP", 0, -4)
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
		btn:SetWidth(182)
		btn:SetHeight(15)
		btn:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -21 - (i - 1) * 16)

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
		icon:SetWidth(13)
		icon:SetHeight(13)
		icon:SetPoint("LEFT", btn, "LEFT", 2, 0)
		icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		btn.Icon = icon

		-- Name and level/class are the two columns. Health, race, stealth name
		-- and observation age remain in the tooltip, rather than crowding rows.
		local details = btn:CreateFontString(nil, "OVERLAY")
		details:SetFont(FONT, 10, "OUTLINE")
		details:SetPoint("RIGHT", btn, "RIGHT", -3, 0)
		details:SetWidth(65)
		details:SetJustifyH("RIGHT")
		btn.Details = details

		local nameText = btn:CreateFontString(nil, "OVERLAY")
		nameText:SetFont(FONT, 11, "OUTLINE")
		nameText:SetPoint("LEFT", icon, "RIGHT", 3, 0)
		nameText:SetPoint("RIGHT", details, "LEFT", -3, 0)
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
		Targets.SelectEnemy(tName, tGUID, "LeftButton")
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
	if AutoBG_LoadPosition then
		AutoBG_LoadPosition(Spy.AlertWindow, "AutoBG_SpyAlertWindow", "TOP", 0, -140, "TOP")
	else
		Spy.AlertWindow:ClearAllPoints()
		Spy.AlertWindow:SetPoint("TOP", UIParent, "TOP", 0, -140)
	end
end

function Spy:SaveAlertPosition()
	if not Spy.AlertWindow then return end
	if AutoBG_SavePosition then
		AutoBG_SavePosition(Spy.AlertWindow, "AutoBG_SpyAlertWindow")
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

	local color = (classToken and Targets and Targets.GetClassColor and Targets.GetClassColor(classToken)) or (classToken and AutoBG_GetClassColorRGB and AutoBG_GetClassColorRGB(classToken)) or { r = 1, g = 1, b = 1 }
	w.Name:SetText(enemyName or "Unknown")
	w.Name:SetTextColor(color.r, color.g, color.b)

	w:SetBackdropBorderColor(borderR, borderG, borderB, 0.95)

	local titleW = (w.Title.GetStringWidth and w.Title:GetStringWidth()) or 100
	local nameW = (w.Name.GetStringWidth and w.Name:GetStringWidth()) or 80
	local neededW = math.max(190, math.max(titleW, nameW) + 52)
	w:SetWidth(neededW)

	w:Show()

	if alertTimer then alertTimer:Cancel(); alertTimer = nil end
	if not Spy.isTestMode then
		alertTimer = C_Timer.NewTimer(4.5, function()
			alertTimer = nil
			Spy:HideAlert()
		end)
	end
end

function Spy:ApplyPosition()
	Spy:ApplyAlertPosition()
	if not Spy.Frame then return end
	if AutoBG_LoadPosition then
		AutoBG_LoadPosition(Spy.Frame, "AutoBG_SpyFrame", "TOPLEFT", 100, -200, "TOPLEFT")
	else
		Spy.Frame:ClearAllPoints()
		Spy.Frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 100, -200)
	end
end

function Spy:SavePosition()
	if not Spy.Frame then return end
	if AutoBG_SavePosition then
		AutoBG_SavePosition(Spy.Frame, "AutoBG_SpyFrame")
	end
end

function Spy:ResetPosition()
	local opt = GetSpySettings()
	if opt then
		opt.posX = nil
		opt.posY = nil
	end
	if AutoBG_Settings then
		if AutoBG_Settings.Positions then
			AutoBG_Settings.Positions["AutoBG_SpyFrame"] = nil
		end
		if AutoBG_Settings.Targets and AutoBG_Settings.Targets.pos then
			AutoBG_Settings.Targets.pos["AutoBG_SpyFrame_posX"] = nil
			AutoBG_Settings.Targets.pos["AutoBG_SpyFrame_posY"] = nil
		end
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
	if renderTimer then renderTimer:Cancel(); renderTimer = nil end
	if FlushObservations then FlushObservations() end
	MaintainTicker()
	if not Spy.Frame then return end
	local f, opt = Spy.Frame, GetSpySettings()
	if not opt.Enabled or (Targets and Targets.activeBG) then
		f:Hide()
		if not (Targets and Targets.activeBG) then Spy:HideAlert() end
		return
	end

	local count = Spy.isTestMode and 3 or activeEnemyCount
	local maxRows = math.max(3, math.min(MAX_SPY_ROWS, math.floor(tonumber(opt.MaxRows) or 5)))
	local visibleCount = math.min(count, maxRows)
	local title = count == 0 and "Spy (0)" or tostring(count) .. (count == 1 and " enemy" or " enemies")
	if count > visibleCount then title = title .. " (" .. visibleCount .. " shown)" end
	if f.Title:GetText() ~= title then f.Title:SetText(title) end
	local width, height = count == 0 and 96 or 190, count == 0 and 24 or 25 + visibleCount * 16
	if f:GetWidth() ~= width then f:SetWidth(width) end
	if f:GetHeight() ~= height then f:SetHeight(height) end

	for i = 1, visibleCount do
		local row, data = f.rows[i], trackedEnemies[i]
		local nameChanged = row.targetName ~= data.name
		local classChanged = nameChanged or row.targetClass ~= data.classToken
		local levelChanged = classChanged or row.targetLevel ~= data.level
		local iconChanged = classChanged or row.targetStealth ~= data.isStealthed or row.targetStealthSpell ~= data.stealthSpell
		row.targetName, row.targetGUID = data.name, data.guid
		local contact = contactByName[data.name]
		row.targetClass, row.targetRace = data.classToken, data.race or (contact and contact.race)
		row.targetLevel, row.targetHealth = data.level, data.healthPct
		row.targetStealth, row.targetStealthSpell = data.isStealthed, data.stealthSpell
		row.targetLastSeen = data.lastSeen

		if classChanged then
			local color = Targets.GetClassColor(data.classToken)
			row.StatusBar:SetVertexColor(color.r, color.g, color.b, 0.45)
		end
		if nameChanged then row.NameText:SetText(data.shortName or data.name) end
		if levelChanged then
			local level = data.level and data.level > 0 and tostring(data.level) or "??"
			row.Details:SetText(level .. " " .. (FormatClass(data.classToken) or ""))
		end
		if iconChanged then
			if data.isStealthed then
				local _, _, texture = Targets.CheckIsStealthName(data.stealthSpell or "Stealth")
				row.Icon:SetTexture(texture)
				row.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
				row.Icon:Show()
			else
				local uv = data.classToken and CLASS_ICON_COORDS[data.classToken]
				if uv then
					row.Icon:SetTexture(CLASS_ICON_TEXTURE)
					row.Icon:SetTexCoord(uv[1], uv[2], uv[3], uv[4])
					row.Icon:Show()
				else row.Icon:Hide() end
			end
		end
		if not row:IsShown() then row:Show() end
	end
	for i = visibleCount + 1, MAX_SPY_ROWS do
		if f.rows[i]:IsShown() then f.rows[i]:Hide() end
	end
	if count == 0 and opt.AutoHide then f:Hide()
	elseif not f:IsShown() then f:Show() end
end

-- -------------------------------------------------------------------------- --
-- Expiry and pending stealth checks; active only while tracking enemies.     --
-- -------------------------------------------------------------------------- --
OnSpyTick = function()
	local opt = GetSpySettings()
	if not opt.Enabled or (Targets and Targets.activeBG) then
		StopTicker()
		if Spy.Frame then Spy.Frame:Hide() end
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
			if e.guid and guidToName[e.guid] == e.name then guidToName[e.guid] = nil end
			if e.name and nameToGUID[e.name] == e.guid then nameToGUID[e.name] = nil end
			for k = i, activeEnemyCount - 1 do
				trackedEnemies[k], trackedEnemies[k + 1] = trackedEnemies[k + 1], trackedEnemies[k]
			end
			ResetEnemyEntry(trackedEnemies[activeEnemyCount])
			activeEnemyCount = activeEnemyCount - 1
			changed = true
		else
			if e.pendingUntil and now >= e.pendingUntil then
				e.pendingUntil = nil
				local found, spell = Spy:CheckUnitStealth(e.guid)
				if found ~= nil then
					e.isStealthed, e.stealthSpell = found, spell
					if not found then e.wasStealthedAlerted = false end
					changed = true
				end
			end
			if e.isStealthed and not e.wasStealthedAlerted and opt.StealthAlert then
				e.wasStealthedAlerted = Spy:NotifyStealth(e.name, e.stealthSpell, e.classToken, e.guid, false, e.observedGUID) and true or false
			end
			i = i + 1
		end
	end

	if changed then
		for k = 1, activeEnemyCount do
			nameToTrackIndex[trackedEnemies[k].name] = k
		end
		Spy:RenderRows()
	end
	MaintainTicker()
end

-- -------------------------------------------------------------------------- --
-- Test Mode Preview                                                          --
-- -------------------------------------------------------------------------- --
function Spy:EnableTestMode()
	Spy:ClearHistory()
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
end

function Spy:ToggleTestMode()
	if Spy.isTestMode then
		Spy:DisableTestMode()
	else
		Spy:EnableTestMode()
	end
end

function Spy:OnBattlegroundChanged(inBG)
	if Spy.inBattleground == inBG then return end
	Spy.inBattleground = inBG
	if inBG then
		ClearObservations()
		StopTicker()
		if renderTimer then renderTimer:Cancel(); renderTimer = nil end
		Spy:HideAlert()
		if Spy.Frame and Spy.Frame:IsShown() then
			Spy.Frame:Hide()
		end
	else
		Spy:RenderRows()
	end
end

-- -------------------------------------------------------------------------- --
-- Event Telemetry Engine                                                     --
-- -------------------------------------------------------------------------- --
local function ObserveUnit(unit, expectedGUID)
	if not UnitExists(unit) or UnitGUID(unit) ~= expectedGUID
		or not UnitIsPlayer(unit) or not UnitCanAttack("player", unit) then return end
	local name = UnitName(unit)
	if not name or IsGroupMember(name, expectedGUID, unit) then return end
	SetHostility(name, expectedGUID, true)
	local _, classToken = UnitClass(unit)
	local hp, maxHp = UnitHealth(unit), UnitHealthMax(unit)
	local pct = 100
	if maxHp and maxHp > 0 then pct = math.floor((hp / maxHp) * 100 + 0.5) end
	local isStealth, spell = Spy:CheckUnitStealth(unit)
	Spy:RecordEnemy(name, classToken, UnitLevel(unit), expectedGUID, pct,
		isStealth, spell, UnitRace(unit), unit)
end

-- Unit tokens can change before next-frame dispatch. Retain GUID identity and
-- read the final available aura snapshot once for each observed enemy.
local function QueueObservation(unit)
	if not unit then return end
	local guid = UnitGUID(unit)
	if not guid or not UnitIsPlayer(unit) or not UnitCanAttack("player", unit) then return end
	local index = pendingByGUID[guid]
	if not index then
		if pendingCount == MAX_SPY_ENEMIES then
			local oldest = pendingObservations[1]
			pendingByGUID[oldest.guid] = nil
			for i = 1, pendingCount - 1 do
				pendingObservations[i] = pendingObservations[i + 1]
				pendingByGUID[pendingObservations[i].guid] = i
			end
			pendingObservations[pendingCount] = oldest
		else
			pendingCount = pendingCount + 1
		end
		index = pendingCount
		pendingByGUID[guid] = index
	end
	pendingObservations[index].guid, pendingObservations[index].unit = guid, unit
	Spy:RequestRender()
end

FlushObservations = function()
	if flushingObservations or pendingCount == 0 then return end
	local opt = GetSpySettings()
	if not opt.Enabled or Spy.isTestMode or (Targets and Targets.activeBG) then
		ClearObservations()
		return
	end
	flushingObservations = true
	local batch, count = pendingObservations, pendingCount
	pendingObservations, spareObservations = spareObservations, batch
	pendingCount = 0
	table.wipe(pendingByGUID)
	for i = 1, count do
		local guid, unit = batch[i].guid, batch[i].unit
		batch[i].guid, batch[i].unit = nil, nil
		if UnitGUID(unit) ~= guid then unit = guid end
		ObserveUnit(unit, guid)
	end
	flushingObservations = false
	if pendingCount > 0 then Spy:RequestRender() end
end

local eventFrame = CreateFrame("Frame", "AutoBG_SpyEventFrame", UIParent)
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
eventFrame:RegisterEvent("UNIT_CASTEVENT")
eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
eventFrame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_BUFFS")
eventFrame:RegisterEvent("CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF")
eventFrame:RegisterEvent("CHAT_MSG_SPELL_AURA_GONE_OTHER")
eventFrame:RegisterEvent("CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE")
eventFrame:RegisterEvent("CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS")

local function Spy_OnEvent(p1, p2, p3, p4, p5, p6, p7)
	-- Accept frame/event arguments, event-first arguments and native 1.12 globals.
	local event, arg1, arg2, arg3, arg4, arg5
	if type(p1) == "table" or type(p1) == "userdata" then
		event, arg1, arg2, arg3, arg4, arg5 = p2, p3, p4, p5, p6, p7
	elseif type(p1) == "string" then
		event, arg1, arg2, arg3, arg4, arg5 = p1, p2, p3, p4, p5, p6
	else
		event, arg1, arg2, arg3, arg4, arg5 = _G.event, _G.arg1, _G.arg2, _G.arg3, _G.arg4, _G.arg5
	end
	if event == "PLAYER_ENTERING_WORLD" then
		Spy:ClearHistory()
		UpdateGroupRoster()
		return
	end
	if event == "PLAYER_LOGOUT" then
		ClearObservations()
		StopTicker()
		if renderTimer then renderTimer:Cancel(); renderTimer = nil end
		Spy:HideAlert()
		eventFrame:UnregisterAllEvents()
		eventFrame:SetScript("OnEvent", nil)
		return
	end
	if event == "PLAYER_LOGIN" then
		Spy:CreateFrames()
		UpdateGroupRoster()
		return
	end
	if event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" then
		UpdateGroupRoster()
		return
	end

	if Targets and Targets.activeBG then return end
	local opt = GetSpySettings()
	if not opt or not opt.Enabled or Spy.isTestMode then return end

	if event == "UNIT_CASTEVENT" or event == "UNIT_SPELLCAST_SUCCEEDED" then
		local modern = event == "UNIT_SPELLCAST_SUCCEEDED"
		local casterGUID = arg1
		if modern then casterGUID = UnitGUID(arg1) end
		local eventType = modern and "CAST" or arg3
		local spellId = modern and arg3 or arg4
		if not casterGUID then return end
		if type(casterGUID) == "string" and string.sub(casterGUID, 1, 6) ~= "0x0000" then return end

		local rawName = UnitName(casterGUID) or guidToName[casterGUID]
		if not IsHostilePlayer(casterGUID, rawName) then return end
		-- Both installed providers report successful casts. Preserve their coverage,
		-- but do not reprocess the same GUID/spell through both in one frame.
		if rawName and eventType == "CAST" then
			local contact, now = GetContact(rawName, casterGUID), GetTime()
			if contact.castAt == now and contact.castSpell == spellId and contact.castProvider ~= event then return end
			contact.castAt, contact.castSpell, contact.castProvider = now, spellId, event
		end

		local _, classToken = UnitClass(casterGUID)
		local level = UnitLevel(casterGUID)
		local isStealth = nil
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
			if eventType == "MAINHAND" or eventType == "OFFHAND" then
				Spy:SetUnitStealthState(rawName, false)
			end
		end

	elseif event == "NAME_PLATE_UNIT_ADDED" then
		QueueObservation(arg1)

	elseif event == "PLAYER_TARGET_CHANGED" or event == "UPDATE_MOUSEOVER_UNIT" or event == "PLAYER_FOCUS_CHANGED" then
		local unit = event == "PLAYER_TARGET_CHANGED" and "target" or (event == "PLAYER_FOCUS_CHANGED" and "focus" or "mouseover")
		QueueObservation(unit)

	elseif event == "UNIT_AURA" then
		QueueObservation(arg1)

	elseif event == "CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF" then
		if arg1 then
			local _, _, enemyName, spellName = string.find(arg1, "^(.-) casts (.-)%.$")
			if not enemyName then
				_, _, enemyName, spellName = string.find(arg1, "^(.-) performs (.-)%.$")
			end
			if enemyName and spellName and not IsGroupMember(enemyName) then
				SetHostility(enemyName, nil, true)
				local isStealth, canonicalName = Targets.CheckIsStealthName(spellName)
				local detectedRace = RACIAL_SPELL_NAMES[spellName]
				Spy:RecordEnemy(enemyName, nil, nil, nil, nil, isStealth and true or nil, canonicalName or spellName, detectedRace)
			end
		end

	elseif event == "CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_BUFFS" then
		if arg1 then
			local _, _, enemyName, buffName = string.find(arg1, "^(.-) gains (.-)%.$")
			if enemyName and buffName and not IsGroupMember(enemyName) then
				SetHostility(enemyName, nil, true)
				local isStealth, canonicalName = Targets.CheckIsStealthName(buffName)
				local detectedRace = RACIAL_SPELL_NAMES[buffName]
				Spy:RecordEnemy(enemyName, nil, nil, nil, nil, isStealth and true or nil, canonicalName or buffName, detectedRace)
			end
		end

	elseif event == "CHAT_MSG_SPELL_AURA_GONE_OTHER" then
		if arg1 then
			local _, _, buffName, enemyName = string.find(arg1, "^(.-) fades from (.-)%.$")
			local isStealth, canonicalName = Targets.CheckIsStealthName(buffName)
			if enemyName and isStealth and not IsGroupMember(enemyName) then
				local idx = nameToTrackIndex[enemyName]
				if idx and trackedEnemies[idx].stealthSpell == canonicalName then
					Spy:SetUnitStealthState(enemyName, false)
				end
			end
		end

	elseif event == "CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE" then
		if arg1 then
			local _, _, enemyName = string.find(arg1, "^(.-)'s ")
			if enemyName and not IsGroupMember(enemyName) then
				SetHostility(enemyName, nil, true)
				Spy:RecordEnemy(enemyName)
			end
		end

	elseif event == "CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS" then
		if arg1 then
			local _, _, enemyName = string.find(arg1, "^(.-) hits ")
			if not enemyName then _, _, enemyName = string.find(arg1, "^(.-) crits ") end
			if not enemyName then _, _, enemyName = string.find(arg1, "^(.-) misses ") end
			if not enemyName then _, _, enemyName = string.find(arg1, "^(.-) attacks%.") end
			if enemyName and not IsGroupMember(enemyName) then
				SetHostility(enemyName, nil, true)
				Spy:RecordEnemy(enemyName)
				Spy:SetUnitStealthState(enemyName, false)
			end
		end
	end
end
eventFrame:SetScript("OnEvent", Spy_OnEvent)
