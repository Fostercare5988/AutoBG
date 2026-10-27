-- -------------------------------------------------------------------------- --
-- AutoBG: Open-World Spy Module (Consolidated from BattlegroundTargets)       --
-- Engineered natively for World of Warcraft 1.12.1 (Enhanced Engine)        --
-- Leveraging SuperWoW v2.2+, ClassicAPI v1.17.11+, NamPower                    --
-- -------------------------------------------------------------------------- --

-- Strict Engine Dependency Guard (Mandatory ClassicAPI v1.17.11+ & SuperWoW v2.2+)
local MIN_CLASSIC_API = 11711

if type(CLASSIC_API_VERSION) ~= "number" or not SUPERWOW_VERSION or
   CLASSIC_API_VERSION < MIN_CLASSIC_API then
	return
end

AutoBG_Spy = AutoBG_Spy or {}
local Spy = AutoBG_Spy
local Targets = AutoBG_Targets
local _, ns = ...
local UI = ns.UI

local MAX_SPY_ENEMIES = 20
local MAX_SPY_ROWS = 20
-- Spy's Nearby model: unseen enemies dim first and are removed only after the timeout.
local ACTIVE_WINDOW = 5
local SPY_WIDTH = 214
local FONT = "Fonts\\FRIZQT__.TTF"
-- The list uses the enemy frames' calm Arial Narrow; the stealth popup keeps FONT.
local LIST_FONT = "Fonts\\ARIALN.TTF"
local ROW_HEIGHT, ROW_STEP, TITLE_HEIGHT, LIST_TOP = 18, 19, 18, 19
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
	AutoHide = false, Timeout = 30, MaxRows = 5, Scale = 1.0, DisableInRaids = true,
}
-- Defaults are filled once per settings table; every event reads the cached one.
local spySettings
local function GetSpySettings()
	local saved = AutoBG_Settings and AutoBG_Settings.Spy
	if saved and saved == spySettings then return saved end
	if not AutoBG_Settings then AutoBG_Settings = {} end
	AutoBG_Settings.Spy = AutoBG_Settings.Spy or {}
	for key, value in pairs(SPY_DEFAULTS) do
		if AutoBG_Settings.Spy[key] == nil then AutoBG_Settings.Spy[key] = value end
	end
	spySettings = AutoBG_Settings.Spy
	return spySettings
end

function Spy:EnsureOptions()
	return GetSpySettings()
end

-- The instance type changes only behind a loading screen; it is read on world
-- and zone events, so the event path checks a cached flag.
local inRaid = false
local function UpdateInstanceState()
	local inInstance, instanceType = IsInInstance()
	inRaid = (inInstance and instanceType == "raid") and true or false
end

function Spy:IsRaidDisabled()
	return inRaid and GetSpySettings().DisableInRaids and true or false
end

-- Kill on sight, ignore and encounter statistics are saved account-wide, keyed
-- by lower-case name. Per-name answers are cached; a list change clears them.
local STATS_LIMIT, STATS_KEEP = 500, 400
local function SavedList(key)
	local opt = GetSpySettings()
	opt[key] = opt[key] or {}
	return opt[key]
end
local kosByName, ignoredByName = {}, {}
local function InList(cache, key, name)
	local hit = cache[name]
	if hit == nil then
		hit = SavedList(key)[string.lower(name)] ~= nil
		cache[name] = hit
	end
	return hit
end
function Spy:IsKoS(name) return name ~= nil and InList(kosByName, "KoS", name) end
function Spy:IsIgnored(name) return name ~= nil and InList(ignoredByName, "Ignore", name) end

local statsSize
local function NoteEncounter(name, classToken, level)
	local stats, key = SavedList("Stats"), string.lower(name)
	local entry = stats[key]
	if not entry then
		if not statsSize then
			statsSize = 0
			for _ in pairs(stats) do statsSize = statsSize + 1 end
		end
		entry = { first = time(), seen = 0 }
		stats[key] = entry
		statsSize = statsSize + 1
	end
	entry.name, entry.seen, entry.last, entry.zone = name, entry.seen + 1, time(), GetRealZoneText()
	if classToken then entry.class = classToken end
	if level and level > 0 then entry.level = level end
	if statsSize > STATS_LIMIT then
		-- Rare: drop the longest-unseen enemies, down to STATS_KEEP.
		local order = {}
		for k, v in pairs(stats) do table.insert(order, { key = k, last = v.last or 0 }) end
		table.sort(order, function(a, b) return a.last < b.last end)
		for i = 1, statsSize - STATS_KEEP do stats[order[i].key] = nil end
		statsSize = STATS_KEEP
	end
	return entry
end

local function Ago(stamp)
	local diff = math.max(0, time() - (stamp or 0))
	if diff < 3600 then return math.floor(diff / 60) .. " min ago" end
	if diff < 86400 then return math.floor(diff / 3600) .. " h ago" end
	return math.floor(diff / 86400) .. " days ago"
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

-- The server only shows you a stealthed enemy your detection reaches, so a
-- loaded, visible, stealthed hostile is the warning at any distance: more
-- detection (talents, gear, potions) simply finds them farther away.
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
local renderTimer, purgeTicker, OnSpyTick
local pendingObservations, spareObservations, pendingByGUID, pendingCount = {}, {}, {}, 0
for i = 1, MAX_SPY_ENEMIES do pendingObservations[i], spareObservations[i] = {}, {} end
local FlushObservations, flushingObservations, QueueObservation
local NAMEPLATE_UNITS = {}
for i = 1, 40 do NAMEPLATE_UNITS[i] = "nameplate" .. i end
local function ClearObservations()
	for i = 1, pendingCount do
		pendingObservations[i].guid, pendingObservations[i].unit = nil, nil
	end
	pendingCount = 0
	table.wipe(pendingByGUID)
end

local function StopTicker()
	if purgeTicker then purgeTicker:Cancel(); purgeTicker = nil end
end

-- Spy's sightings are registered only while the list works: not in a
-- battleground (the enemy frames give the stealth alert there), not in a raid
-- it is off in, not while switched off. Aura changes come only for the tokens
-- an enemy can be on, not for every raid or party member.
local TELEMETRY_EVENTS = {
	"UNIT_CASTEVENT", "NAME_PLATE_UNIT_ADDED", "UPDATE_MOUSEOVER_UNIT",
	"PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED",
	-- NamPower: exact stealth gain/loss and deaths by GUID (Emyrk/nampower EVENTS.md).
	"BUFF_ADDED_OTHER", "BUFF_REMOVED_OTHER", "UNIT_DIED",
}
local ENEMY_UNIT_EVENTS = { "UNIT_AURA_DELTA", "UNIT_SPELLCAST_SUCCEEDED" }
local ENEMY_UNITS = { "target", "focus", "mouseover" }
for i = 1, 40 do ENEMY_UNITS[3 + i] = "nameplate" .. i end
local telemetryFrame, telemetryOn
local function SyncTelemetry(on)
	if telemetryOn == on or not telemetryFrame then return end
	telemetryOn = on
	for i = 1, #TELEMETRY_EVENTS do
		if on then telemetryFrame:RegisterEvent(TELEMETRY_EVENTS[i]) else telemetryFrame:UnregisterEvent(TELEMETRY_EVENTS[i]) end
	end
	for i = 1, #ENEMY_UNIT_EVENTS do
		if on then telemetryFrame:RegisterUnitEvent(ENEMY_UNIT_EVENTS[i], unpack(ENEMY_UNITS))
		else telemetryFrame:UnregisterEvent(ENEMY_UNIT_EVENTS[i]) end
	end
end

local function MaintainTicker()
	local opt = GetSpySettings()
	if opt.Enabled and not Spy.isTestMode and not (Targets and Targets.activeBG) and not Spy:IsRaidDisabled() then
		if not purgeTicker then purgeTicker = C_Timer.NewTicker(1, OnSpyTick) end
		SyncTelemetry(true)
	else
		StopTicker()
		SyncTelemetry(false)
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
-- An uncached remote name reads as the client's placeholder (UNKNOWNOBJECT = "Unknown").
-- Recording it would add a second row that the real name never replaces.
local function IsPlaceholderName(name)
	return name == UNKNOWNOBJECT or name == UKNOWNBEING
end

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
	if not name or IsPlaceholderName(name) then return end
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
	["ORC"] = "Orc",
	["UNDEAD"] = "Undead",
	["SCOURGE"] = "Undead",
	["TAUREN"] = "Tauren",
	["TROLL"] = "Troll",
}

-- Spells only one race can cast, by name so every rank counts. Checked on
-- octowow.st/db, 2026-10-21: racial abilities, and priest spells taught by
-- race-only quests. Fear Ward is left out; whether only Dwarves learn it here
-- is unverified.
local RACIAL_SPELLS = {
	["Shadowmeld"] = "Night Elf",
	["Elune's Grace"] = "Night Elf",
	["Starshards"] = "Night Elf",
	["Stoneform"] = "Dwarf",
	["Escape Artist"] = "Gnome",
	["Perception"] = "Human",
	["Feedback"] = "Human",
	["Will of the Forsaken"] = "Undead",
	["Cannibalize"] = "Undead",
	["Touch of Weakness"] = "Undead",
	["Devouring Plague"] = "Undead",
	["Blood Fury"] = "Orc",
	["War Stomp"] = "Tauren",
	["Berserking"] = "Troll",
	["Hex of Weakness"] = "Troll",
	["Shadowguard"] = "Troll",
}

-- Casts arrive for every player nearby; name each spell ID once.
local raceBySpell = {}
local function RaceForSpell(spellId)
	local race = raceBySpell[spellId]
	if race == nil then
		race = RACIAL_SPELLS[SpellInfo(spellId) or ""] or false
		raceBySpell[spellId] = race
	end
	return race or nil
end

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
	e.yards = nil
	e.inactive = false
	e.dead = nil
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
	if not name or name == "" or IsPlaceholderName(name) then return end
	if Spy:IsIgnored(name) then return end
	if IsGroupMember(name, guid, observedUnit) then return end
	if observedUnit and UnitIsFriend and UnitIsFriend("player", observedUnit) and not (UnitCanAttack and UnitCanAttack("player", observedUnit)) then
		return
	end

	local opt = GetSpySettings()
	if opt and not opt.Enabled then return end
	if Targets and Targets.activeBG then return end

	local now = GetTime()
	local idx = nameToTrackIndex[name]
	-- A full list makes room only from an enemy unseen for a while (a dimmed
	-- row). Pushing out someone still in view brought them straight back on
	-- top and pushed out the next one, so crowds kept the list jumping.
	local slot = activeEnemyCount + 1
	if not idx and activeEnemyCount >= MAX_SPY_ENEMIES then
		slot = 1
		for i = 2, activeEnemyCount do
			if trackedEnemies[i].lastSeen < trackedEnemies[slot].lastSeen then slot = i end
		end
		local oldest = trackedEnemies[slot]
		if not oldest.dead and now - oldest.lastSeen <= ACTIVE_WINDOW and not Spy:IsKoS(name) then return end
	end
	local contact = GetContact(name, guid)
	local recentlySeen = contact.lastSeen and now - contact.lastSeen < 120
	contact.lastSeen = now
	local isNew = false

	local e
	if not idx then
		if slot > activeEnemyCount then activeEnemyCount = slot end
		e = trackedEnemies[slot]
		if e.name then nameToTrackIndex[e.name] = nil end
		if e.guid and guidToName[e.guid] == e.name then guidToName[e.guid] = nil end
		if e.name and nameToGUID[e.name] == e.guid then nameToGUID[e.name] = nil end
		for i = slot, 2, -1 do
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
	-- Only a dead observed unit keeps the death state; any other sighting is alive.
	e.dead = (observedUnit and UnitIsDead(observedUnit)) and true or nil
	e.inactive = e.dead and true or false
	if observedUnit and guid and UnitGUID(observedUnit) == guid then e.observedGUID = guid end

	if isStealth == false and observedUnit and e.pendingUntil and now < e.pendingUntil then isStealth = nil end
	if isStealth ~= nil then
		if isStealth and not observedUnit then e.pendingUntil = now + 0.5
		else e.pendingUntil = nil end
		e.isStealthed = isStealth
		if stealthSpell then e.stealthSpell = stealthSpell end
		if not isStealth then e.wasStealthedAlerted = false end
	end

	if isNew and not recentlySeen then
		NoteEncounter(name, e.classToken, e.level)
		if Spy:IsKoS(name) then
			-- Kill on sight always warns, whatever the sound settings.
			PlaySound("RaidWarning")
			AutoBG_Print("|cffff4040Kill on sight:|r " .. e.shortName .. " is nearby.", true)
		end
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

local function RemoveEnemyAt(i)
	local e = trackedEnemies[i]
	nameToTrackIndex[e.name] = nil
	if e.guid and guidToName[e.guid] == e.name then guidToName[e.guid] = nil end
	if e.name and nameToGUID[e.name] == e.guid then nameToGUID[e.name] = nil end
	for k = i, activeEnemyCount - 1 do
		trackedEnemies[k], trackedEnemies[k + 1] = trackedEnemies[k + 1], trackedEnemies[k]
	end
	ResetEnemyEntry(trackedEnemies[activeEnemyCount])
	activeEnemyCount = activeEnemyCount - 1
	for k = i, activeEnemyCount do nameToTrackIndex[trackedEnemies[k].name] = k end
end

-- Toggle a name on the KoS or Ignore list; returns whether it is now listed.
function Spy:ToggleList(key, name)
	if not name or name == "" then return end
	local list, k = SavedList(key), string.lower(name)
	if list[k] then list[k] = nil else list[k] = name end
	table.wipe(kosByName)
	table.wipe(ignoredByName)
	local listed = list[k] ~= nil
	if key == "Ignore" and listed and nameToTrackIndex[name] then RemoveEnemyAt(nameToTrackIndex[name]) end
	Spy:RenderRows()
	return listed
end

local function PrintList(key, title)
	local names = {}
	for _, display in pairs(SavedList(key)) do table.insert(names, display) end
	table.sort(names)
	AutoBG_Print(title .. " (" .. table.getn(names) .. "): " .. (table.getn(names) > 0 and table.concat(names, ", ") or "none"), true)
end

-- /abg spy kos|ignore [name], /abg spy stats
function Spy:HandleCommand(text)
	local space = string.find(text, " ")
	local sub = string.lower(space and string.sub(text, 1, space - 1) or text)
	local name = space and string.gsub(string.sub(text, space + 1), "^%s*(.-)%s*$", "%1") or ""
	if sub == "kos" or sub == "ignore" then
		local key, title = (sub == "kos") and "KoS" or "Ignore", (sub == "kos") and "Kill on sight" or "Ignored"
		if name == "" then PrintList(key, title); return true end
		local listed = Spy:ToggleList(key, name)
		AutoBG_Print(name .. (listed and " added to " or " removed from ") .. string.lower(title) .. ".", true)
		return true
	elseif sub == "raid" or sub == "raids" then
		local opt = GetSpySettings()
		opt.DisableInRaids = not opt.DisableInRaids
		AutoBG_Print("Spy in raids: " .. (opt.DisableInRaids and "|cFFFF0000Disabled|r" or "|cFF00FF00Enabled|r"), true)
		if Spy.RenderRows then Spy:RenderRows() end
		if AutoBG_Options_Refresh then AutoBG_Options_Refresh() end
		return true
	elseif sub == "stats" then
		local all, total = {}, 0
		for _, v in pairs(SavedList("Stats")) do table.insert(all, v); total = total + (v.seen or 0) end
		table.sort(all, function(a, b) return (a.seen or 0) > (b.seen or 0) end)
		AutoBG_Print("Spy: " .. table.getn(all) .. " enemies met " .. total .. " times. Most often:", true)
		for i = 1, math.min(5, table.getn(all)) do
			local v = all[i]
			AutoBG_Print("  " .. v.name .. " (" .. (v.level or "??") .. " " .. (FormatClass(v.class) or "?") .. "): " .. v.seen .. " times, last " .. Ago(v.last) .. (v.zone and (" in " .. v.zone) or ""), true)
		end
		return true
	end
	return false
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

-- NamPower UNIT_DIED: dim the row now and start its removal timeout from the death.
function Spy:MarkDead(guid)
	local name = guid and guidToName[guid]
	local idx = name and nameToTrackIndex[name]
	if not idx then return end
	local e = trackedEnemies[idx]
	e.dead, e.inactive = true, true
	e.isStealthed, e.pendingUntil = false, nil
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
-- Store the window by its top-left corner so a growing list never moves its top edge.
local function AnchorSpyTopLeft(frame)
	local left, top = frame:GetLeft(), frame:GetTop()
	if not left or not top or not AutoBG_Settings then return end
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
	AutoBG_Settings.Positions = AutoBG_Settings.Positions or {}
	AutoBG_Settings.Positions["AutoBG_SpyFrame"] = { point = "TOPLEFT", relPoint = "BOTTOMLEFT", x = left, y = top }
end

local function SpyFrame_OnDragStart(self)
	local f = self or this or (Spy and Spy.Frame)
	if f and f.StartMoving then f:StartMoving() end
end

local function SpyFrame_OnDragStop(self)
	local f = self or this or (Spy and Spy.Frame)
	if f and f.StopMovingOrSizing then f:StopMovingOrSizing() end
	if f then AnchorSpyTopLeft(f) end
end

local function SpyClearBtn_OnClick(self)
	Spy:ClearHistory()
end

local function SpyRow_OnClick(self, button)
	local b = self or this
	if not b.targetName then return end
	if IsShiftKeyDown() then
		local listed = Spy:ToggleList("KoS", b.targetName)
		AutoBG_Print(b.targetName .. (listed and " added to" or " removed from") .. " kill on sight.", true)
	elseif IsControlKeyDown() then
		local name = b.targetName
		Spy:ToggleList("Ignore", name)
		AutoBG_Print(name .. " ignored. Type |cFFFFFF00/abg spy ignore " .. name .. "|r to undo.", true)
	else
		Targets.SelectEnemy(b.targetName, b.targetGUID or nameToGUID[b.targetName], button or arg1)
	end
end

local hoverTimer
local function SpyRow_OnEnter(self)
	local b = self or this
	Spy.hovered = true
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
	if b.targetYards then
		GameTooltip:AddLine("Distance: " .. b.targetYards .. " yards", 0.8, 0.8, 0.8)
	end
	if Spy:IsKoS(b.targetName) then
		GameTooltip:AddLine("Kill on sight", 1, 0.25, 0.25)
	end
	local stat = SavedList("Stats")[string.lower(b.targetName)]
	if stat and stat.seen then
		GameTooltip:AddLine("Met " .. stat.seen .. (stat.seen == 1 and " time" or " times") .. ", first " .. Ago(stat.first), 0.7, 0.7, 0.7)
	end
	if b.targetDead then
		GameTooltip:AddLine("State: Dead", 1, 0.3, 0.3)
	elseif b.targetStealth then
		GameTooltip:AddLine("State: STEALTHED (" .. (b.targetStealthSpell or "Stealth") .. ")", 0.4, 0.6, 1)
	end
	if b.targetLastSeen and b.targetLastSeen > 0 then
		local diff = math.max(0, math.floor(GetTime() - b.targetLastSeen))
		GameTooltip:AddLine("Last Seen: " .. (diff < 60 and (diff .. "s ago") or (math.floor(diff / 60) .. "m ago")), 0.7, 0.7, 0.7)
	end
	GameTooltip:AddLine("Click: target  |  Right-click: focus", 0.5, 0.5, 0.5)
	GameTooltip:AddLine("Shift-click: kill on sight  |  Ctrl-click: ignore", 0.5, 0.5, 0.5)
	GameTooltip:Show()
end

local function SpyRow_OnLeave(self)
	GameTooltip:Hide()
	Spy.hovered = false
	-- Moving to the next row enters it at once; reorder only once the mouse has left.
	if hoverTimer then hoverTimer:Cancel() end
	hoverTimer = C_Timer.NewTimer(0.4, function()
		hoverTimer = nil
		if not Spy.hovered then Spy:RenderRows() end
	end)
end

function Spy:CreateFrames()
	if Spy.Frame then return end

	local f = CreateFrame("Frame", "AutoBG_SpyFrame", UIParent)
	f:SetWidth(SPY_WIDTH)
	f:SetHeight(40)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:SetClampedToScreen(true)
	f:Hide()

	-- Modern Spy layout: a solid title bar, class-colored rows straight under it.
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", SpyFrame_OnDragStart)
	f:SetScript("OnDragStop", SpyFrame_OnDragStop)

	local titleBar = f:CreateTexture(nil, "BACKGROUND")
	titleBar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
	titleBar:SetHeight(TITLE_HEIGHT)
	titleBar:SetTexture(UI.track[1], UI.track[2], UI.track[3], 0.95)
	f.TitleBar = titleBar
	local accent = f:CreateTexture(nil, "BORDER")
	accent:SetPoint("BOTTOMLEFT", titleBar, "BOTTOMLEFT", 0, 0)
	accent:SetPoint("BOTTOMRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)
	accent:SetHeight(1)
	accent:SetTexture(UI.accent[1], UI.accent[2], UI.accent[3], 0.6)

	local title = f:CreateFontString(nil, "ARTWORK")
	title:SetFont(LIST_FONT, 12, "")
	title:SetTextColor(UI.heading[1], UI.heading[2], UI.heading[3])
	title:SetPoint("LEFT", titleBar, "LEFT", 6, 0)
	title:SetText("Nearby")
	f.Title = title

	-- Clear Button (X)
	local clearBtn = CreateFrame("Button", nil, f)
	clearBtn:SetWidth(14)
	clearBtn:SetHeight(14)
	clearBtn:SetPoint("RIGHT", titleBar, "RIGHT", -3, 0)
	local clearText = clearBtn:CreateFontString(nil, "ARTWORK")
	clearText:SetFont(LIST_FONT, 12, "")
	clearText:SetTextColor(UI.hint[1], UI.hint[2], UI.hint[3])
	clearText:SetPoint("CENTER", 0, 0)
	clearText:SetText("x")
	clearBtn:SetScript("OnClick", SpyClearBtn_OnClick)

	-- Pre-allocated Rows
	f.rows = {}
	for i = 1, MAX_SPY_ROWS do
		local btn = CreateFrame("Button", "AutoBG_SpyRow" .. i, f)
		btn:SetWidth(SPY_WIDTH)
		btn:SetHeight(ROW_HEIGHT)
		btn:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -LIST_TOP - (i - 1) * ROW_STEP)

		-- Missing health shows as a dim tint of the class color, like enemy frames.
		local bg = btn:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetTexture(0.15, 0.15, 0.15, 1)
		btn.Bg = bg

		-- Status Bar (Class Colored)
		local sb = btn:CreateTexture(nil, "BORDER")
		sb:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
		sb:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
		sb:SetWidth(SPY_WIDTH)
		sb:SetTexture(BAR_TEXTURE)
		btn.StatusBar = sb

		-- Icon (Class or Stealth)
		local icon = btn:CreateTexture(nil, "ARTWORK")
		icon:SetWidth(ROW_HEIGHT - 2)
		icon:SetHeight(ROW_HEIGHT - 2)
		icon:SetPoint("LEFT", btn, "LEFT", 2, 0)
		icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		btn.Icon = icon

		-- Name and level/class are the two columns. Health, race, stealth name
		-- and observation age remain in the tooltip, rather than crowding rows.
		local details = btn:CreateFontString(nil, "OVERLAY")
		details:SetFont(LIST_FONT, 12, "OUTLINE")
		details:SetPoint("RIGHT", btn, "RIGHT", -3, 0)
		details:SetWidth(65)
		details:SetJustifyH("RIGHT")
		btn.Details = details

		local yards = btn:CreateFontString(nil, "OVERLAY")
		yards:SetFont(LIST_FONT, 12, "OUTLINE")
		yards:SetPoint("RIGHT", details, "LEFT", -4, 0)
		yards:SetWidth(30)
		yards:SetJustifyH("RIGHT")
		yards:SetTextColor(0.85, 0.85, 0.85)
		btn.Yards = yards

		local nameText = btn:CreateFontString(nil, "OVERLAY")
		nameText:SetFont(LIST_FONT, 13, "OUTLINE")
		nameText:SetPoint("LEFT", icon, "RIGHT", 3, 0)
		nameText:SetPoint("RIGHT", yards, "LEFT", -3, 0)
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

-- Stealth warning look per kind: icon and rim color. Shapes repaint by table,
-- so these stay fixed.
local ALERT_LOOK = {
	Stealth      = { texture = "Interface\\Icons\\Ability_Stealth", edge = { 0.2, 0.8, 1.0, 0.95 } },
	Prowl        = { texture = PROWL_TEXTURE, edge = { 1.0, 0.5, 0.0, 0.95 } },
	Shadowmeld   = { texture = "Interface\\Icons\\Ability_Racial_ShadowMeld", edge = { 0.7, 0.4, 0.9, 0.95 } },
	Vanish       = { texture = "Interface\\Icons\\Ability_Stealth", edge = { 0.3, 0.9, 1.0, 0.95 } },
	Invisibility = { texture = "Interface\\Icons\\Spell_Nature_Invisibilty", edge = { 0.5, 0.8, 1.0, 0.95 } },
	Cloaking     = { texture = "Interface\\Icons\\INV_Misc_EngGizmos_04", edge = { 0.9, 0.9, 0.2, 0.95 } },
}

-- Left-click targets the stealthed enemy, right-click focuses them.
local function AlertWindow_OnClick(card, button)
	Targets.SelectEnemy(card.targetName, card.targetGUID, button)
end

function Spy:CreateAlertWindow()
	if Spy.AlertWindow then return end
	Spy.AlertWindow = ns.CreateAlertCard("AutoBG_SpyAlertWindow", -140, ALERT_LOOK.Stealth.edge,
		AlertWindow_OnClick, { "Click: target  |  Right-click: focus" })
end

function Spy:HideAlert()
	if Spy.AlertWindow then Spy.AlertWindow:Dismiss() end
end

function Spy:ResetAlertPosition()
	if Spy.AlertWindow then Spy.AlertWindow:ResetPosition()
	elseif AutoBG_Settings and AutoBG_Settings.Positions then
		AutoBG_Settings.Positions["AutoBG_SpyAlertWindow"] = nil
	end
end

function Spy:ShowAlert(spellName, enemyName, classToken, guid)
	if Spy:IsRaidDisabled() then return end
	Spy:CreateAlertWindow()
	local kind = spellName or "Stealth"
	if string.find(kind, "Invis") then kind = "Invisibility" end
	if not ALERT_LOOK[kind] then kind = "Stealth" end
	local look = ALERT_LOOK[kind]
	local w = Spy.AlertWindow
	w.targetName = enemyName or "Unknown"
	w.targetGUID = guid
	local color = classToken and Targets.GetClassColor(classToken)
	w:Present(look.texture, "|cff00ffff" .. kind .. "|r", w.targetName, color, look.edge, Spy.isTestMode)
end

function Spy:ApplyPosition()
	if Spy.AlertWindow then Spy.AlertWindow:ApplyPosition() end
	if not Spy.Frame then return end
	if AutoBG_LoadPosition then
		AutoBG_LoadPosition(Spy.Frame, "AutoBG_SpyFrame", "TOPLEFT", 100, -200, "TOPLEFT")
		-- Older saves may use a center or bottom anchor; convert them once.
		local pos = AutoBG_Settings and AutoBG_Settings.Positions and AutoBG_Settings.Positions["AutoBG_SpyFrame"]
		if pos and pos.point ~= "TOPLEFT" then AnchorSpyTopLeft(Spy.Frame) end
	else
		Spy.Frame:ClearAllPoints()
		Spy.Frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 100, -200)
	end
end

function Spy:SavePosition()
	if Spy.Frame then AnchorSpyTopLeft(Spy.Frame) end
end

-- Older position keys are moved into Positions on load (AutoBG_MigratePositions).
function Spy:ResetPosition()
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
-- Shows one tracked enemy on one row; unchanged values are not rewritten.
local function FillRow(row, data)
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
	row.targetDead = data.dead
	local inactive = data.inactive and true or false
	if row.inactive ~= inactive then
		row.inactive = inactive
		row:SetAlpha(inactive and 0.45 or 1)
	end

	if classChanged then
		local color = Targets.GetClassColor(data.classToken)
		row.StatusBar:SetVertexColor(color.r, color.g, color.b, 1)
		row.Bg:SetTexture(0.12 + color.r * 0.30, 0.12 + color.g * 0.30, 0.12 + color.b * 0.30, 1)
	end
	if nameChanged then row.NameText:SetText(data.shortName or data.name) end
	local pct = data.dead and 0 or (data.healthPct or 100)
	if row.barPct ~= pct then
		row.barPct = pct
		row.StatusBar:SetWidth(math.max(0.01, (SPY_WIDTH) * pct / 100))
	end
	row.targetYards = data.yards
	local yardsText = data.yards and (data.yards .. "y") or ""
	if row.yardsText ~= yardsText then row.yardsText = yardsText; row.Yards:SetText(yardsText) end
	local kos = Spy:IsKoS(data.name)
	if row.kos ~= kos then
		row.kos = kos
		if kos then row.NameText:SetTextColor(1, 0.3, 0.3) else row.NameText:SetTextColor(1, 1, 1) end
	end
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

function Spy:RenderRows()
	if renderTimer then renderTimer:Cancel(); renderTimer = nil end
	if FlushObservations then FlushObservations() end
	MaintainTicker()
	if not Spy.Frame then return end
	local f, opt = Spy.Frame, GetSpySettings()
	if not opt.Enabled or (Targets and Targets.activeBG) or Spy:IsRaidDisabled() then
		f:Hide()
		if not (Targets and Targets.activeBG) then Spy:HideAlert() end
		return
	end

	-- Under the mouse the rows hold their order, so a click hits the name you
	-- aimed at. Shown enemies still update; one who left dims, newcomers wait.
	if Spy.hovered and f:IsShown() and (f.shownCount or 0) > 0 then
		for i = 1, f.shownCount do
			local row = f.rows[i]
			local idx = row.targetName and nameToTrackIndex[row.targetName]
			if idx then FillRow(row, trackedEnemies[idx])
			elseif not row.inactive then row.inactive = true; row:SetAlpha(0.45) end
		end
		return
	end

	local count = Spy.isTestMode and 3 or activeEnemyCount
	local maxRows = math.max(3, math.min(MAX_SPY_ROWS, math.floor(tonumber(opt.MaxRows) or 5)))
	local visibleCount = math.min(count, maxRows)
	local title = "Nearby  |cffffffff" .. count .. "|r"
	if count > visibleCount then title = title .. "  |cff999999(" .. visibleCount .. " shown)|r" end
	if f.Title:GetText() ~= title then f.Title:SetText(title) end
	-- Fixed width; the top edge is anchored, so only the bottom edge moves.
	local width, height = SPY_WIDTH, count == 0 and TITLE_HEIGHT or LIST_TOP + visibleCount * ROW_STEP - 1
	if f:GetWidth() ~= width then f:SetWidth(width) end
	if f:GetHeight() ~= height then f:SetHeight(height) end

	for i = 1, visibleCount do FillRow(f.rows[i], trackedEnemies[i]) end
	f.shownCount = visibleCount
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
	if not opt.Enabled or (Targets and Targets.activeBG) or Spy:IsRaidDisabled() then
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
		-- A loaded, visible enemy is still nearby even when it raises no new events.
		local visible = e.guid and UnitExists(e.guid) and UnitIsVisible(e.guid)
		if visible then
			-- A visible, living unit was resurrected; a corpse keeps its death time.
			if e.dead and not UnitIsDead(e.guid) then e.dead = nil end
			if not e.dead then e.lastSeen = now end
			local hp, maxHp = UnitHealth(e.guid), UnitHealthMax(e.guid)
			if maxHp and maxHp > 0 then
				local pct = math.floor(hp / maxHp * 100 + 0.5)
				if e.healthPct ~= pct then e.healthPct = pct; changed = true end
			end
		end
		-- ClassicAPI distance; an enemy out of sight has no distance.
		local yards
		if visible and UnitDistanceSquared then
			local d2, checked = UnitDistanceSquared(e.guid)
			if checked and d2 then yards = math.floor(math.sqrt(d2) + 0.5) end
		end
		if e.yards ~= yards then e.yards = yards; changed = true end
		if (now - e.lastSeen) > timeout then
			RemoveEnemyAt(i)
			changed = true
		else
			local inactive = e.dead or (now - e.lastSeen) > ACTIVE_WINDOW
			if e.inactive ~= inactive then e.inactive = inactive; changed = true end
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

	-- Spy's nameplate scanner: ClassicAPI nameplateN slots find enemies who stand
	-- still and raise no events. Slots can be vacant, so check all of them.
	for slot = 1, 40 do
		local unit = NAMEPLATE_UNITS[slot]
		if UnitExists(unit) and UnitIsPlayer(unit) then
			local guid = UnitGUID(unit)
			if guid and not guidToName[guid] then QueueObservation(unit) end
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
		{ name = "Shadowstalker", classToken = "ROGUE", race = "Night Elf", level = 60, healthPct = 82, isStealthed = true, stealthSpell = "Stealth", lastSeen = now - 2, yards = 8 },
		{ name = "Frostweaver", classToken = "MAGE", race = "Gnome", level = 60, healthPct = 100, isStealthed = false, lastSeen = now - 9, yards = 27 },
		{ name = "Ironbreaker", classToken = "WARRIOR", race = "Dwarf", level = 58, healthPct = 65, isStealthed = false, lastSeen = now - 22, yards = 46 },
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
		e.yards = m.yards
		e.guid = nil
	end

	Spy:RenderRows()
	-- Preview the warning as it plays outside BGs, sound included.
	if GetSpySettings().SoundAlert then Spy:PlayStealthDetectedSound() end
	Spy:ShowAlert("Stealth", "Shadowstalker", "ROGUE", nil)
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
		MaintainTicker()
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
	if not name or IsPlaceholderName(name) or IsGroupMember(name, expectedGUID, unit) then return end
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
QueueObservation = function(unit)
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
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
-- Sightings start on; MaintainTicker turns them off where Spy does not work.
telemetryFrame = eventFrame
SyncTelemetry(true)

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
	if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
		-- A loading screen starts a fresh list; a new area keeps it unless it is a
		-- raid where Spy is off. Subzone changes never touch the list.
		local wasDisabled = Spy:IsRaidDisabled()
		UpdateInstanceState()
		if event == "PLAYER_ENTERING_WORLD" then
			Spy:ClearHistory()
			UpdateGroupRoster()
		elseif Spy:IsRaidDisabled() and not wasDisabled then
			Spy:ClearHistory()
		else
			Spy:RenderRows()
		end
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
	if not opt or not opt.Enabled or Spy.isTestMode or Spy:IsRaidDisabled() then return end

	if event == "UNIT_CASTEVENT" or event == "UNIT_SPELLCAST_SUCCEEDED" then
		local modern = event == "UNIT_SPELLCAST_SUCCEEDED"
		local casterGUID = arg1
		if modern then casterGUID = UnitGUID(arg1) end
		local eventType = modern and "CAST" or arg3
		local spellId = modern and arg3 or arg4
		if not casterGUID then return end
		if type(casterGUID) == "string" and string.sub(casterGUID, 1, 6) ~= "0x0000" then return end

		local rawName = guidToName[casterGUID] or UnitName(casterGUID)
		if IsPlaceholderName(rawName) then return end
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

		if not detectedRace and spellId and eventType == "CAST" then
			detectedRace = RaceForSpell(spellId)
		end

		if eventType == "CAST" and Targets and Targets.CheckIsStealthSpell then
			local isS, spell, tex = Targets.CheckIsStealthSpell(spellId)
			if isS then
				isStealth = true
				sName = spell
			end
		end

		if rawName then
			Spy:RecordEnemy(rawName, classToken, level, casterGUID, nil, isStealth, sName, detectedRace)
			if eventType == "MAINHAND" or eventType == "OFFHAND" then
				Spy:SetUnitStealthState(rawName, false)
			end
		end

	elseif event == "BUFF_ADDED_OTHER" or event == "BUFF_REMOVED_OTHER" then
		-- arg1 = guid, arg3 = spell ID; filter by spell before any unit lookup.
		local isStealth, sName = Targets.CheckIsStealthSpell(arg3)
		if not isStealth or not arg1 then return end
		local name = guidToName[arg1] or UnitName(arg1)
		if not name or IsPlaceholderName(name) then return end
		if event == "BUFF_REMOVED_OTHER" then
			Spy:SetUnitStealthState(name, false)
		elseif IsHostilePlayer(arg1, name) then
			local _, classToken = UnitClass(arg1)
			Spy:RecordEnemy(name, classToken, UnitLevel(arg1), arg1, nil, true, sName, nil, arg1)
		end

	elseif event == "UNIT_DIED" then
		Spy:MarkDead(arg1)

	elseif event == "NAME_PLATE_UNIT_ADDED" then
		QueueObservation(arg1)

	elseif event == "PLAYER_TARGET_CHANGED" or event == "UPDATE_MOUSEOVER_UNIT" or event == "PLAYER_FOCUS_CHANGED" then
		local unit = event == "PLAYER_TARGET_CHANGED" and "target" or (event == "PLAYER_FOCUS_CHANGED" and "focus" or "mouseover")
		QueueObservation(unit)

	elseif event == "UNIT_AURA_DELTA" then
		-- ClassicAPI 1.17.10: a refresh alone (only updated IDs) never starts or
		-- ends stealth; the second-by-second check keeps a shown enemy current.
		if arg2 and not (arg2.isFullUpdate or arg2.addedAuraInstanceIDs or arg2.removedAuraInstanceIDs) then return end
		QueueObservation(arg1)
	end
end
eventFrame:SetScript("OnEvent", Spy_OnEvent)
