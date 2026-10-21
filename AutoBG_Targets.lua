-- -------------------------------------------------------------------------- --
-- AutoBG: Enemy Target Frames Module (Consolidated from BattlegroundTargets)  --
-- Engineered natively for World of Warcraft 1.12.1 (Enhanced Engine)        --
-- ClassicAPI v1.16.0+, SuperWoW v2.2+, UnitXP SP3                            --
-- -------------------------------------------------------------------------- --

-- Strict Engine Dependency Guard (Mandatory ClassicAPI v1.16.0+ & SuperWoW v2.2+)
local MIN_CLASSIC_API = 11600

if type(CLASSIC_API_VERSION) ~= "number" or not SUPERWOW_VERSION or
   CLASSIC_API_VERSION < MIN_CLASSIC_API then
	return
end

local MAX_ENEMIES = 40
local BRACKETS = { 10, 15, 40 }
local DRAG_HEADER_HEIGHT = 18
-- Arial Narrow: the client's calm, plain sans; cast bars keep Friz Quadrata.
local FONT = "Fonts\\ARIALN.TTF"
local CAST_FONT = "Fonts\\FRIZQT__.TTF"
local RANGE_MARK_COLOR = { 0.35, 1.00, 0.45, 0.95 }
local RANGE_MARK_TEXT = string.format("|cff%02x%02x%02x", RANGE_MARK_COLOR[1] * 255, RANGE_MARK_COLOR[2] * 255, RANGE_MARK_COLOR[3] * 255)
local BAR_TEXTURE = [[Interface\AddOns\AutoBG\Textures\barTexture.tga]]
local PROWL_TEXTURE = [[Interface\AddOns\AutoBG\Textures\prowl.tga]]
local ROUNDED_MASK = [[Interface\AddOns\AutoBG\Textures\RoundedMask]]
local HORDE_FLAG_TEXTURE = "Interface\\WorldStateFrame\\HordeFlag"
local ALLIANCE_FLAG_TEXTURE = "Interface\\WorldStateFrame\\AllianceFlag"
local RAID_ICON_TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"
local CAST_WIDTH = 120
-- Enemies within 80 yards count as near, close enough to reach soon, and get a
-- thin green stripe on the row's left edge. Nothing else changes with range.
local RANGE_SQUARED = 80 * 80
local ALLIANCE_TRINKET_TEXTURE = "Interface\\Icons\\INV_Jewelry_TrinketPVP_01"
local HORDE_TRINKET_TEXTURE = "Interface\\Icons\\INV_Jewelry_TrinketPVP_02"

-- Every PvP trinket shares a three-minute cooldown on OctoWoW (confirmed in play).
-- Spell IDs and names checked on octowow.st/db, 2026-10-21.
local TRINKET_COOLDOWN = 180
local TRINKET_SPELL_IDS = {
	[52317] = true, -- Insignia (dispels all crowd control)
	[5579]  = true, -- Immune Root/Snare/Stun
	[23276] = true, -- Immune Fear/Polymorph/Stun
	[23277] = true, -- Immune Charm/Fear/Stun
	[23273] = true, -- Immune Charm/Fear/Polymorph
	[23274] = true, -- Immune Fear/Polymorph/Snare
}

local TRINKET_SPELL_NAMES = {
	["Insignia"]                    = true,
	["Immune Root/Snare/Stun"]      = true,
	["Immune Fear/Polymorph/Stun"]  = true,
	["Immune Charm/Fear/Stun"]      = true,
	["Immune Charm/Fear/Polymorph"] = true,
	["Immune Fear/Polymorph/Snare"] = true,
}

local function GetEnemyTrinketTexture()
	local f = UnitFactionGroup("player")
	return (f == "Horde") and ALLIANCE_TRINKET_TEXTURE or HORDE_TRINKET_TEXTURE
end

AutoBG_Targets = CreateFrame("Frame", "AutoBG_TargetsCoreFrame", UIParent)
local Targets = AutoBG_Targets
local _, ns = ...
local UI = ns.UI
BattlegroundTargets = AutoBG_Targets -- Backwards-compatibility alias

Targets.currentSize = 10
Targets.isConfig = false

local playerName = UnitName("player")
local playerFaction = UnitFactionGroup("player") == "Horde" and 0 or 1
local enemyFaction = playerFaction == 0 and 1 or 0
local activeBG = false
Targets.activeBG = false
local currentSize = 10

local CLASS_COLORS = AutoBG_CLASS_COLORS or {
	HUNTER  = { r = 0.67, g = 0.83, b = 0.45 },
	WARLOCK = { r = 0.58, g = 0.51, b = 0.79 },
	PRIEST  = { r = 1.00, g = 1.00, b = 1.00 },
	PALADIN = { r = 0.96, g = 0.55, b = 0.73 },
	MAGE    = { r = 0.41, g = 0.80, b = 0.94 },
	ROGUE   = { r = 1.00, g = 0.96, b = 0.41 },
	DRUID   = { r = 1.00, g = 0.49, b = 0.04 },
	SHAMAN  = { r = 0.00, g = 0.44, b = 0.87 },
	WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
}

local FALLBACK_COLOR = { r = 0.60, g = 0.60, b = 0.60 }
local CLASS_ORDER = {
	DRUID = 1,
	HUNTER = 2,
	MAGE = 3,
	PALADIN = 4,
	PRIEST = 5,
	ROGUE = 6,
	SHAMAN = 7,
	WARLOCK = 8,
	WARRIOR = 9,
}

local function ResolveClassToken(rawClass)
	if not rawClass or type(rawClass) ~= "string" then return "WARRIOR" end
	local upper = string.upper(rawClass)
	local tbl = AutoBG_CLASS_COLORS or CLASS_COLORS
	return (tbl[upper] and upper) or "WARRIOR"
end

local function GetClassColor(classToken)
	if not classToken then return FALLBACK_COLOR end
	local upper = string.upper(classToken)
	return (AutoBG_CLASS_COLORS and AutoBG_CLASS_COLORS[upper]) or CLASS_COLORS[upper] or FALLBACK_COLOR
end
Targets.ResolveClassToken = ResolveClassToken
Targets.GetClassColor = GetClassColor

-- Fixed-size roster storage (1..MAX_ENEMIES). Only 1..enemyCount is active.
local roster = {}
for i = 1, MAX_ENEMIES do
	roster[i] = { name = nil, classToken = nil, guid = nil }
end
local enemyCount = 0

-- Runtime lookup/telemetry caches
local nameToRow = {}
local unknownGUIDs = {} -- GUIDs already checked against the current roster
local nameToGUID = {}
local guidToName = {}
local shortNameToFull = {}
local healthPct = {}
local deadState = {}
local stealthedState = {}
local trinketCooldown = {}

local wipe = table.wipe

-- Telemetry caching & unit target fast lookup
local UNIT_TARGET_CACHE = {
	player = "playertarget",
	target = "targettarget",
	focus = "focustarget",
	mouseover = "mouseovertarget",
	party1 = "party1target",
	party2 = "party2target",
	party3 = "party3target",
	party4 = "party4target",
}
for i = 1, 40 do
	UNIT_TARGET_CACHE["raid" .. i] = "raid" .. i .. "target"
end

local function GetUnitTargetToken(unit)
	if not unit then return nil end
	local cached = UNIT_TARGET_CACHE[unit]
	if not cached then
		cached = unit .. "target"
		UNIT_TARGET_CACHE[unit] = cached
	end
	return cached
end

-- Cast and aura IDs, checked on octowow.st/db, 2026-10-21. Duration 0 lasts
-- until the aura is removed or the unit attacks. The frames show the spell's
-- own icon from SpellInfo; these textures are the fallback.
local STEALTH_SPELLS = {
	-- Rogue Stealth, ranks 1-4
	[1784] = { name = "Stealth", texture = "Interface\\Icons\\Ability_Stealth", duration = 0 },
	[1785] = { name = "Stealth", texture = "Interface\\Icons\\Ability_Stealth", duration = 0 },
	[1786] = { name = "Stealth", texture = "Interface\\Icons\\Ability_Stealth", duration = 0 },
	[1787] = { name = "Stealth", texture = "Interface\\Icons\\Ability_Stealth", duration = 0 },
	-- Rogue Vanish: casts 1856/1857 apply auras 11327/11329
	[1856]  = { name = "Vanish", texture = "Interface\\Icons\\Ability_Stealth", duration = 0 },
	[1857]  = { name = "Vanish", texture = "Interface\\Icons\\Ability_Stealth", duration = 0 },
	[11327] = { name = "Vanish", texture = "Interface\\Icons\\Ability_Stealth", duration = 0 },
	[11329] = { name = "Vanish", texture = "Interface\\Icons\\Ability_Stealth", duration = 0 },
	-- Druid Prowl, ranks 1-3
	[5215] = { name = "Prowl", texture = PROWL_TEXTURE, duration = 0 },
	[6783] = { name = "Prowl", texture = PROWL_TEXTURE, duration = 0 },
	[9913] = { name = "Prowl", texture = PROWL_TEXTURE, duration = 0 },
	-- Night Elf Shadowmeld
	[20580] = { name = "Shadowmeld", texture = "Interface\\Icons\\Ability_Racial_ShadowMeld", duration = 0 },
	-- Lesser Invisibility Potion, Invisibility Potion
	[3680]  = { name = "Lesser Invisibility", texture = "Interface\\Icons\\Spell_Nature_Invisibilty", duration = 15 },
	[11392] = { name = "Invisibility",        texture = "Interface\\Icons\\Spell_Nature_Invisibilty", duration = 18 },
	-- Gnomish Cloaking Device
	[4079]  = { name = "Cloaking",            texture = "Interface\\Icons\\INV_Misc_EngGizmos_04",   duration = 10 },
}

-- What the row shows instead of health while the enemy is hidden.
local STEALTH_LABELS = {
	["Stealth"]             = "|cffc7b5ffSTEALTH|r",
	["Prowl"]               = "|cffd2c2ffPROWL|r",
	["Vanish"]              = "|cffd2c2ffVANISH|r",
	["Shadowmeld"]          = "|cffc7b5ffMELD|r",
	["Invisibility"]        = "|cff00ffffINVIS POT|r",
	["Lesser Invisibility"] = "|cff00ffffINVIS POT|r",
	["Cloaking"]            = "|cff00ffffCLOAK|r",
}

local STEALTH_NAMES = {
	["Stealth"]             = STEALTH_SPELLS[1784],
	["Prowl"]               = STEALTH_SPELLS[5215],
	["Vanish"]              = STEALTH_SPELLS[11327],
	["Shadowmeld"]          = STEALTH_SPELLS[20580],
	["Invisibility"]        = STEALTH_SPELLS[11392],
	["Lesser Invisibility"] = STEALTH_SPELLS[3680],
	["Cloaking"]            = STEALTH_SPELLS[4079],
}

-- Buff events arrive for every unit nearby; classify each spell ID once.
local stealthBySpell = {}
local function CheckIsStealthSpell(spellId)
	if not spellId then return false end
	local def = stealthBySpell[spellId]
	if def == nil then
		local spellName, _, icon
		if SpellInfo then spellName, _, icon = SpellInfo(spellId) end
		local base = STEALTH_SPELLS[spellId] or STEALTH_NAMES[spellName or ""]
		def = false
		if base then
			-- Prowl keeps AutoBG's own art; everything else shows its real icon.
			local texture = base.texture
			if texture ~= PROWL_TEXTURE and icon and icon ~= "" then texture = icon end
			def = { name = base.name, texture = texture, duration = base.duration }
		end
		stealthBySpell[spellId] = def
	end
	if def then return true, def.name, def.texture, def.duration end
	return false
end

local function CheckIsStealthName(spellName)
	if not spellName then return false end
	local canonicalName = string.gsub(spellName, "%s*%(%d+%)$", "")
	local data = STEALTH_NAMES[canonicalName]
	if data then
		return true, data.name, data.texture, data.duration
	end
	return false
end
Targets.CheckIsStealthSpell = CheckIsStealthSpell
Targets.CheckIsStealthName = CheckIsStealthName

-- A missing/invisible unit is unknown, not proof that stealth ended.
local stealthAuraSlots = {}
function Targets.CheckUnitStealth(unit)
	if not unit or not UnitExists(unit) or not UnitIsVisible(unit) then return nil end
	local _, count = C_UnitAuras.GetAuraSlots(unit, "HELPFUL", nil, nil, stealthAuraSlots)
	for i = 1, count do
		-- ClassicAPI's positional sibling resolves the same opaque slot without
		-- constructing an AuraData table. Spell ID is field 10, with no rank field.
		local auraName, _, _, _, _, _, _, _, _, spellId = C_UnitAuras.UnitAuraBySlot(unit, stealthAuraSlots[i])
		if auraName == nil then return nil end -- Unavailable snapshot, not a removal.
		local found, name, texture, duration = CheckIsStealthSpell(spellId)
		if not found then found, name, texture, duration = CheckIsStealthName(auraName) end
		if found then return true, name, texture, duration end
	end
	return false
end

local function StripRealm(name)
	if not name then return "" end
	local p = string.find(name, "-", 1, true)
	if p then
		return string.sub(name, 1, p - 1)
	end
	return name
end

-- Full names are authoritative. Only an unqualified name may use the unique
-- short-name index; a different explicit realm must never resolve to this row.
local function ResolveRosterName(rawName, guid)
	if not rawName then return nil end
	if nameToRow[rawName] then return rawName end
	if string.find(rawName, "-", 1, true) then return nil end
	local known = guid and guidToName[guid]
	if known and nameToRow[known] and StripRealm(known) == rawName then return known end
	return shortNameToFull[rawName] or nil
end

local function ClassThenNameSort(a, b)
	local oa = CLASS_ORDER[a.classToken] or 99
	local ob = CLASS_ORDER[b.classToken] or 99
	if oa ~= ob then
		return oa < ob
	end
	return a.name < b.name
end

local function NameSort(a, b)
	return a.name < b.name
end

-- Allocation-free insertion sort strictly over active segment (1..enemyCount)
local function SortActiveRoster(comparator)
	for i = 2, enemyCount do
		local j = i
		while j > 1 and comparator(roster[j], roster[j - 1]) do
			roster[j], roster[j - 1] = roster[j - 1], roster[j]
			j = j - 1
		end
	end
end

-- Roster delta-detection buffers (fixed 1..MAX_ENEMIES, zero GC allocation)
local prevEnemyCount = -1
local prevSortBy = -1
local prevEnemyNames = {}
local prevEnemyClasses = {}
for i = 1, MAX_ENEMIES do
	prevEnemyNames[i] = ""
	prevEnemyClasses[i] = ""
end

local function HasRosterChanged()
	local o = AutoBG_Settings and AutoBG_Settings.Targets
	local sortBy = (o and o.ButtonSortBy and o.ButtonSortBy[currentSize]) or 1
	if sortBy ~= prevSortBy then return true end
	if enemyCount ~= prevEnemyCount then return true end
	for i = 1, enemyCount do
		if roster[i].name ~= prevEnemyNames[i] or roster[i].classToken ~= prevEnemyClasses[i] then
			return true
		end
	end
	return false
end

local function SaveRosterSnapshot()
	local o = AutoBG_Settings and AutoBG_Settings.Targets
	prevSortBy = (o and o.ButtonSortBy and o.ButtonSortBy[currentSize]) or 1
	prevEnemyCount = enemyCount
	for i = 1, enemyCount do
		prevEnemyNames[i] = roster[i].name or ""
		prevEnemyClasses[i] = roster[i].classToken or ""
	end
	for i = enemyCount + 1, MAX_ENEMIES do
		prevEnemyNames[i] = ""
		prevEnemyClasses[i] = ""
	end
end

function Targets:InvalidateRosterCache()
	prevEnemyCount = -1
	prevSortBy = -1
end

function Targets:EnsureOptions()
	if type(AutoBG_Settings) ~= "table" then
		AutoBG_Settings = {}
	end
	if type(AutoBG_Settings.Targets) ~= "table" then
		AutoBG_Settings.Targets = {}
	end

	local o = AutoBG_Settings.Targets
	-- Seed independent positions once, preserving the placement used by each bracket.
	if not o.IndependentPositionsVersion then
		if AutoBG_MigratePositions then AutoBG_MigratePositions() end
		AutoBG_Settings.Positions = AutoBG_Settings.Positions or {}
		local positions = AutoBG_Settings.Positions
		local shared = positions.AutoBG_TargetsMainFrame
		for _, size in ipairs(BRACKETS) do
			local key = "AutoBG_TargetsMainFrame" .. size
			if shared and (not positions[key] or not (o.IndependentPositioning and o.IndependentPositioning[size])) then
				positions[key] = {point=shared.point, relPoint=shared.relPoint, x=shared.x, y=shared.y}
			end
		end
		o.IndependentPositionsVersion = 1
	end
	o.pos = o.pos or {}
	o.EnableBracket = o.EnableBracket or {}
	o.IndependentPositioning = nil -- Permanent behavior; retire the saved toggle.
	o.ButtonFontSize = o.ButtonFontSize or {}
	o.ButtonScale = o.ButtonScale or {}
	o.ButtonOpacity = o.ButtonOpacity or {}
	o.ButtonWidth = o.ButtonWidth or {}
	o.ButtonHeight = o.ButtonHeight or {}
	o.ButtonShowHealthBar = nil -- Permanent behavior; retire the saved toggle.
	o.ButtonShowHealthText = o.ButtonShowHealthText or {}
	o.ButtonHideRealm = o.ButtonHideRealm or {}
	o.ButtonSortBy = o.ButtonSortBy or {}
	o.ShowStealthIcon = nil -- Permanent behavior; retire the saved toggle.
	o.DimStealthed = o.DimStealthed or {}
	o.ShowStealthText = nil -- Permanent behavior; retire the saved toggle.
	o.ShowFlagCarrier = nil -- Permanent behavior; retire the saved toggle.
	o.ShowTrinket = o.ShowTrinket or {}
	if o.StealthAlert == nil then o.StealthAlert = true end
	if o.TrinketPos == nil then o.TrinketPos = "RIGHT" end
	if o.ShowCastBars == nil then o.ShowCastBars = true end
	-- Cast bars started on the side away from the trinket; keep that for old saves.
	if o.CastPos == nil then o.CastPos = (o.TrinketPos == "LEFT") and "RIGHT" or "LEFT" end
	if o.FadeOutOfRange == nil then o.FadeOutOfRange = true end
	if o.ShowRaidIcons == nil then o.ShowRaidIcons = true end
	if o.ShowTargetCount == nil then o.ShowTargetCount = true end

	-- Migrate old default dimensions once; preserve custom layouts and positions.
	if not o.ReadabilityVersion then
		for _, size in ipairs(BRACKETS) do
			if o.ButtonFontSize[size] == 10 then o.ButtonFontSize[size] = (size == 40 and 11) or 12 end
			if o.ButtonWidth[size] == 150 then o.ButtonWidth[size] = 210 end
			if o.ButtonHeight[size] == ((size == 40 and 18) or 20) then
				o.ButtonHeight[size] = (size == 40 and 20) or 26
			end
		end
		o.ReadabilityVersion = 1
	end
	for _, size in ipairs(BRACKETS) do
		if o.EnableBracket[size] == nil then o.EnableBracket[size] = true end
		if o.ButtonFontSize[size] == nil then o.ButtonFontSize[size] = (size == 40 and 11) or 12 end
		-- Below 10 the text is too small to read; the slider starts there now.
		if o.ButtonFontSize[size] < 10 then o.ButtonFontSize[size] = 10 end
		if o.ButtonScale[size] == nil then o.ButtonScale[size] = (size == 10 and 1.10) or (size == 15 and 1.00) or 0.90 end
		if o.ButtonWidth[size] == nil then o.ButtonWidth[size] = 210 end
		if o.ButtonHeight[size] == nil then o.ButtonHeight[size] = (size == 40 and 20) or 26 end
		if o.ButtonShowHealthText[size] == nil then o.ButtonShowHealthText[size] = true end
		if o.ButtonHideRealm[size] == nil then o.ButtonHideRealm[size] = false end
		if o.ButtonSortBy[size] == nil then o.ButtonSortBy[size] = 1 end
		if o.DimStealthed[size] == nil then o.DimStealthed[size] = false end
		if o.ShowTrinket[size] == nil then o.ShowTrinket[size] = true end
	end
end

-- -------------------------------------------------------------------------- --
-- Flag Carrier Resolution (Direct Integration with AutoBG_FC Authority)      --
-- Zero duplicated regex, zero duplicate chat event registrations!            --
-- -------------------------------------------------------------------------- --
local function GetEnemyFlagCarrier()
	if Targets.isConfig then
		return "Target1-Realm"
	end
	if AutoBG_GetEnemyCarrier then
		return AutoBG_GetEnemyCarrier()
	end
	return nil
end

local function GetEnemyFlagTexture()
	if enemyFaction == 1 then
		return HORDE_FLAG_TEXTURE
	else
		return ALLIANCE_FLAG_TEXTURE
	end
end

local function UpdateRowFlagVisual(index, name)
	if not Targets.TargetButton then return end
	local btn = Targets.TargetButton[index]
	if not btn or not name then return end
	local enemyCarrier = GetEnemyFlagCarrier()
	local isCarrier = enemyCarrier and (enemyCarrier == name or ResolveRosterName(enemyCarrier) == name) and true or false
	local texture = isCarrier and GetEnemyFlagTexture() or nil
	if btn.flagCarrier == isCarrier and btn.flagTexture == texture then return end
	btn.flagCarrier, btn.flagTexture = isCarrier, texture

	if isCarrier then
		btn.FlagIcon:SetTexture(texture)
		btn.FlagIcon:Show()
		btn.HealthText:ClearAllPoints()
		btn.HealthText:SetPoint("RIGHT", btn.FlagIcon, "LEFT", -2, 0)
	else
		btn.FlagIcon:Hide()
		btn.HealthText:ClearAllPoints()
		btn.HealthText:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
	end
end

function Targets:OnCarrierChanged()
	if not Targets.TargetButton or not Targets.MainFrame:IsShown() then return end
	for i = 1, MAX_ENEMIES do
		local btn = Targets.TargetButton[i]
		if btn and btn:IsShown() and btn.targetName then
			UpdateRowFlagVisual(i, btn.targetName)
		end
	end
end

local function UpdateRowStealthVisual(index, name)
	if not Targets.TargetButton then return end
	local btn = Targets.TargetButton[index]
	if not btn or not name then return end
	local o = AutoBG_Settings and AutoBG_Settings.Targets
	local size = currentSize
	local stealth = stealthedState[name]
	local dead = deadState[name]
	local height = (o and o.ButtonHeight and o.ButtonHeight[size]) or 20

	local tex
	if stealth and not dead then
		tex = (stealth.spellName == "Prowl" and PROWL_TEXTURE) or stealth.texture
		if not tex or tex == "" then tex = "Interface\\Icons\\Ability_Stealth" end
	end
	tex = tex or false
	if btn.stealthTexture ~= tex then
		btn.stealthTexture = tex
		if tex then
			btn.StealthIcon:SetTexture(tex)
			btn.StealthIcon:SetVertexColor(1, 1, 1, 1)
			btn.StealthIcon:Show()
			btn.StealthIconBg:Show()
		else
			btn.StealthIcon:Hide()
			btn.StealthIconBg:Hide()
		end
	end
	-- Stealth icon at the left edge, then the raid icon, then the name.
	local inset = tex and (height + 1) or 4
	if btn.raidIndex then
		if btn.raidInset ~= inset then
			btn.raidInset = inset
			btn.RaidIcon:ClearAllPoints()
			btn.RaidIcon:SetPoint("LEFT", btn, "LEFT", inset, 0)
		end
		inset = inset + height - 4
	end
	if btn.nameInset ~= inset then
		btn.nameInset = inset
		btn.Name:SetPoint("LEFT", btn, "LEFT", inset, 0)
	end

	local alpha
	if dead then
		alpha = 0.55
	elseif stealth and o and o.DimStealthed and o.DimStealthed[size] then
		alpha = 0.75
	else
		alpha = 1.0
	end
	if btn.visualAlpha ~= alpha then btn.visualAlpha = alpha; btn:SetAlpha(alpha) end

	local near = (btn.inRange and not dead) and true or false
	if btn.markShown ~= near then
		btn.markShown = near
		if near then btn.RangeMark:Show() else btn.RangeMark:Hide() end
	end

	local text, showText
	if stealth and not dead then
		text = STEALTH_LABELS[stealth.spellName or ""] or STEALTH_LABELS.Stealth
		showText = true
	else
		local pct = healthPct[name] or 100
		if not o or o.ButtonShowHealthText[size] then
			text = dead and "|cffff4040DEAD|r" or (pct .. "%")
			showText = true
		else
			showText = false
		end
	end
	if showText and btn.healthTextValue ~= text then
		btn.healthTextValue = text
		btn.HealthText:SetText(text)
	end
	if btn.healthTextShown ~= showText then
		btn.healthTextShown = showText
		if showText then btn.HealthText:Show() else btn.HealthText:Hide() end
	end
end

-- Stealth entry pool & zero-allocation timer watcher
local stealthEntryPool = {}
local function ReleaseStealthEntry(entry)
	if not entry then return end
	entry.isStealthed = false
	entry.spellName = nil
	entry.texture = nil
	entry.expireTime = nil
	entry.alerted = nil
	entry.observedGUID = nil
	entry.pendingUntil = nil
	table.insert(stealthEntryPool, entry)
end

local function AcquireStealthEntry()
	local entry = table.remove(stealthEntryPool)
	if not entry then
		entry = { isStealthed = false, spellName = nil, texture = nil, expireTime = nil }
	end
	return entry
end

local SetUnitStealth -- forward declaration

local stealthWatcher = CreateFrame("Frame", "AutoBG_TargetsStealthWatcher", UIParent)
stealthWatcher:Hide()
local stealthWatcherElapsed = 0

local function StealthWatcher_OnUpdate(arg1_param, arg2_param)
	local dt = (type(arg1_param) == "number" and arg1_param) or (type(arg2_param) == "number" and arg2_param) or arg1 or 0
	stealthWatcherElapsed = stealthWatcherElapsed + dt
	if stealthWatcherElapsed < 0.25 then return end
	stealthWatcherElapsed = 0

	local now = GetTime()
	local hasExpiring = false
	for name, entry in pairs(stealthedState) do
		if entry and entry.expireTime then
			if now >= entry.expireTime then
				SetUnitStealth(name, false)
			else
				hasExpiring = true
			end
		end
	end
	if not hasExpiring then
		stealthWatcher:Hide()
	end
end
stealthWatcher:SetScript("OnUpdate", StealthWatcher_OnUpdate)

SetUnitStealth = function(name, isStealthed, spellName, texture, duration, observedUnit, fromRecheck)
	if not name then return end
	local visualChanged = false
	if isStealthed then
		local entry = stealthedState[name]
		local firstObservation = not entry
		if not entry then
			entry = AcquireStealthEntry()
			stealthedState[name] = entry
		end
		local nextSpell = spellName or "Stealth"
		local nextTexture = texture or "Interface\\Icons\\Ability_Stealth"
		local spellChanged = entry.spellName ~= nextSpell
		visualChanged = firstObservation or spellChanged or entry.texture ~= nextTexture
		entry.isStealthed = true
		-- SPELL_GO can precede the aura descriptor update. Give that update one
		-- short settling window; explicit fades, attacks and death still clear now.
		if not fromRecheck then
			if observedUnit then entry.pendingUntil = nil
			else
				entry.pendingUntil = GetTime() + 0.5
				-- A new successful stealth cast/gain supersedes an old death flag.
				visualChanged = visualChanged or deadState[name] == true
				deadState[name] = false
			end
		end
		entry.spellName = nextSpell
		entry.texture = nextTexture
		local exp = (duration and duration > 0) and (GetTime() + duration + 0.5) or nil
		if firstObservation or spellChanged then
			entry.expireTime = exp
		end

		if observedUnit and UnitGUID then entry.observedGUID = UnitGUID(observedUnit) end
		if not entry.alerted and not Targets.isConfig and AutoBG_Spy then
			local guid = nameToGUID[name] or entry.observedGUID
			entry.alerted = AutoBG_Spy:NotifyStealth(name, entry.spellName, nil, guid, true, entry.observedGUID) and true or false
		end

		if exp and stealthWatcher and not stealthWatcher:IsShown() then
			stealthWatcher:Show()
		end
	else
		local entry = stealthedState[name]
		if observedUnit and entry and entry.pendingUntil and GetTime() < entry.pendingUntil then return end
		if entry then
			stealthedState[name] = nil
			ReleaseStealthEntry(entry)
			visualChanged = true
		end
	end

	local row = nameToRow[name]
	if row and visualChanged and Targets.MainFrame:IsShown() then
		UpdateRowStealthVisual(row, name)
	end
end

local function ClearAllStealth()
	for name, entry in pairs(stealthedState) do
		ReleaseStealthEntry(entry)
		stealthedState[name] = nil
	end
	if stealthWatcher then
		stealthWatcher:Hide()
	end
end

local function UpdateRowTrinketVisual(index, name)
	local btn = Targets.TargetButton and Targets.TargetButton[index]
	if not btn or not btn.Trinket then return end

	local o = AutoBG_Settings and AutoBG_Settings.Targets
	local size = currentSize
	local exp = name and trinketCooldown[name]
	local now = GetTime()
	if exp and exp <= now then trinketCooldown[name] = nil; exp = nil end
	if (o and o.ShowTrinket and o.ShowTrinket[size] == false) or not name then
		if btn.trinketShown ~= false then btn.Trinket:Hide(); btn.trinketShown = false end
		return
	end

	if btn.trinketShown ~= true then btn.Trinket:Show(); btn.trinketShown = true end
	local texture = GetEnemyTrinketTexture()
	if btn.trinketTexture ~= texture then
		btn.trinketTexture = texture
		btn.Trinket.Icon:SetTexture(texture)
	end

	if exp and exp > now then
		local rem = exp - now
		local seconds = math.floor(rem)
		if btn.trinketSeconds ~= seconds then
			btn.trinketSeconds = seconds
			if rem >= 60 then
				local m = math.floor(rem / 60)
				local s = seconds % 60
				btn.Trinket.Text:SetText(string.format("%d:%02d", m, s))
			else
				btn.Trinket.Text:SetText(seconds .. "s")
			end
		end
		if btn.trinketCooling ~= true then
			btn.trinketCooling = true
			btn.Trinket.Icon:SetVertexColor(0.35, 0.35, 0.35, 0.75)
			btn.Trinket.Text:SetTextColor(1, 0.85, 0.20, 1)
		end
	else
		if btn.trinketCooling ~= false then
			btn.trinketCooling = false
			btn.trinketSeconds = nil
			btn.Trinket.Icon:SetVertexColor(1, 1, 1, 1)
			btn.Trinket.Text:SetText("")
		end
	end
end

-- -------------------------------------------------------------------------- --
-- Enemy cast bars                                                            --
-- -------------------------------------------------------------------------- --
local CAST_COLOR = { 1.0, 0.70, 0.0 }
local CHANNEL_COLOR = { 0.40, 0.75, 1.0 }
local LOCKED_COLOR = { 0.60, 0.60, 0.60 }

local function StopCast(btn)
	local cast = btn and btn.Cast
	if not cast or not cast.active then return end
	cast.active, cast.guid, cast.spell, cast.preview, cast.fromEvent = nil, nil, nil, nil, nil
	cast:Hide()
end

-- ClassicAPI times remote casts from the server's cast packet and clears them
-- on interrupt, so it is the authority; the cast event is only the cue to ask.
local function ReadCast(guid)
	-- The cache can hold a name before its timings, so a cast without both
	-- times is treated as no cast.
	local name, _, texture, startMs, endMs, _, _, locked = C_Spell.UnitCastingInfo(guid)
	if name and startMs and endMs then return name, texture, startMs, endMs, false, locked end
	name, _, texture, startMs, endMs, _, locked = C_Spell.UnitChannelInfo(guid)
	if name and startMs and endMs then return name, texture, startMs, endMs, true, locked end
end

local function ShowCast(btn, guid, spell, texture, startMs, endMs, channel, locked)
	local cast = btn.Cast
	cast.active, cast.guid = true, guid
	cast.startMs, cast.endMs, cast.channel = startMs, endMs, channel
	cast.nextCheck = GetTime() + 0.2
	if cast.spell ~= spell then
		cast.spell = spell
		cast.Text:SetText(spell)
	end
	cast.Icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
	local c = locked and LOCKED_COLOR or (channel and CHANNEL_COLOR) or CAST_COLOR
	cast.Bar:SetVertexColor(c[1], c[2], c[3], 1)
	cast:Show()
end

-- fallbackSpell/fallbackMs come from UNIT_CASTEVENT (duration in ms) in case
-- the event arrives before ClassicAPI has cached the cast.
local function RefreshCast(row, fallbackSpell, fallbackMs, fallbackChannel)
	local btn = Targets.TargetButton and Targets.TargetButton[row]
	if not btn or not btn:IsShown() then return end
	local o = AutoBG_Settings and AutoBG_Settings.Targets
	local guid = btn.targetName and nameToGUID[btn.targetName]
	if (o and o.ShowCastBars == false) or not guid then StopCast(btn); return end
	local spell, texture, startMs, endMs, channel, locked = ReadCast(guid)
	local fromEvent
	if not spell and fallbackSpell and fallbackMs and fallbackMs > 0 then
		local name, _, icon = SpellInfo(fallbackSpell)
		if name then
			spell, texture, channel, fromEvent = name, icon, fallbackChannel, true
			startMs = GetTime() * 1000
			endMs = startMs + fallbackMs
		end
	end
	if spell and endMs and endMs > GetTime() * 1000 then
		ShowCast(btn, guid, spell, texture, startMs, endMs, channel, locked)
		btn.Cast.fromEvent = fromEvent
	else
		StopCast(btn)
	end
end

-- Animation only: the bar moves every frame while a cast is showing.
local function Cast_OnUpdate(self)
	local cast = self or this
	local btn = cast.owner
	local now = GetTime()
	local nowMs = now * 1000
	if cast.preview then
		if nowMs >= cast.endMs then
			local span = cast.endMs - cast.startMs
			cast.startMs, cast.endMs = nowMs, nowMs + span
		end
	elseif now >= cast.nextCheck then
		cast.nextCheck = now + 0.2
		local guid = btn.targetName and nameToGUID[btn.targetName]
		if guid ~= cast.guid then StopCast(btn); return end
		local spell, texture, startMs, endMs, channel, locked = ReadCast(guid)
		if spell then
			if spell ~= cast.spell or startMs ~= cast.startMs then
				ShowCast(btn, guid, spell, texture, startMs, endMs, channel, locked)
			end
			cast.endMs, cast.fromEvent = endMs, nil -- pushback moves the end
		elseif not cast.fromEvent then
			StopCast(btn)
			return
		end
	end
	if not cast.endMs or not cast.startMs or nowMs >= cast.endMs then StopCast(btn); return end
	local span = cast.endMs - cast.startMs
	local pct = span > 0 and (nowMs - cast.startMs) / span or 1
	if cast.channel then pct = 1 - pct end
	if pct < 0 then pct = 0 elseif pct > 1 then pct = 1 end
	local width = math.max(1, math.floor((cast.barMax or 1) * pct + 0.5))
	if cast.barWidth ~= width then
		cast.barWidth = width
		cast.Bar:SetWidth(width)
	end
end

local function ClearAllCasts()
	if not Targets.TargetButton then return end
	for i = 1, MAX_ENEMIES do StopCast(Targets.TargetButton[i]) end
end

-- -------------------------------------------------------------------------- --
-- Range, raid icons and group targets                                        --
-- -------------------------------------------------------------------------- --
local previewStatus = {} -- row -> { far, raid, count } while previewing
local RAID_TARGET_TOKENS, PARTY_TARGET_TOKENS = {}, {}
for i = 1, 40 do RAID_TARGET_TOKENS[i] = "raid" .. i .. "target" end
for i = 1, 4 do PARTY_TARGET_TOKENS[i] = "party" .. i .. "target" end
local groupTargets = {}

local function CountTarget(token)
	local guid = UnitGUID(token)
	if guid then groupTargets[guid] = (groupTargets[guid] or 0) + 1 end
end

-- How many of your group (you included) target each enemy GUID.
local function CountGroupTargets()
	wipe(groupTargets)
	local raid = GetNumRaidMembers()
	if raid > 0 then
		for i = 1, raid do CountTarget(RAID_TARGET_TOKENS[i]) end
	else
		CountTarget("target")
		for i = 1, GetNumPartyMembers() do CountTarget(PARTY_TARGET_TOKENS[i]) end
	end
end

-- Runs on the half-second ticker and when targets or raid icons change.
local function UpdateRowStatus()
	if not Targets.TargetButton or not Targets.MainFrame:IsShown() then return end
	local o = AutoBG_Settings and AutoBG_Settings.Targets
	local fade = not o or o.FadeOutOfRange ~= false
	local icons = not o or o.ShowRaidIcons ~= false
	local counts = not o or o.ShowTargetCount ~= false
	if counts and not Targets.isConfig then CountGroupTargets() end
	local rangeChanged = false
	for i = 1, math.min(enemyCount, currentSize) do
		local btn = Targets.TargetButton[i]
		local name = btn.targetName
		if name and btn:IsShown() then
			local near, raidIndex, count
			if Targets.isConfig then
				local sample = previewStatus[i]
				near = not (sample and sample.far)
				if sample then raidIndex, count = sample.raid, sample.count end
			else
				local guid = nameToGUID[name]
				if guid then
					local distanceSquared, checked = UnitDistanceSquared(guid)
					near = checked and distanceSquared <= RANGE_SQUARED
					raidIndex = GetRaidTargetIndex(guid)
					count = groupTargets[guid]
				end
				-- An enemy not seen near you yet is unknown: no mark.
			end
			near = (fade and near) and true or nil
			raidIndex = icons and raidIndex or nil
			count = counts and count or nil
			local changed = false
			if btn.raidIndex ~= raidIndex then
				btn.raidIndex = raidIndex
				if raidIndex then
					SetRaidTargetIconTexture(btn.RaidIcon, raidIndex)
					btn.RaidIcon:Show()
				else
					btn.RaidIcon:Hide()
				end
				btn.nameInset, btn.raidInset = nil, nil
				changed = true
			end
			if btn.inRange ~= near then
				btn.inRange = near
				changed, rangeChanged = true, true
			end
			if changed then UpdateRowStealthVisual(i, name) end
			if btn.targetCount ~= count then
				btn.targetCount = count
				btn.TargetCount:SetText(count and tostring(count) or "")
			end
		end
	end
	if rangeChanged and Targets.RefreshHeader then Targets.RefreshHeader() end
end
Targets.UpdateRowStatus = UpdateRowStatus

local function UpdateObservedTimers()
	if not (activeBG or Targets.isConfig) then return end
	if not Targets.TargetButton then return end
	UpdateRowStatus()
	if not next(stealthedState) and not next(trinketCooldown) then return end
	local now = GetTime()
	for i = 1, math.min(enemyCount, currentSize) do
		local btn = Targets.TargetButton[i]
		if btn and btn:IsShown() and btn.targetName then
			local name = btn.targetName
			local stealth = stealthedState[name]
			if not Targets.isConfig and stealth and stealth.pendingUntil and now >= stealth.pendingUntil then
				stealth.pendingUntil = nil
				local guid = nameToGUID[name] or btn.targetGUID
				local found, spell, texture, duration = Targets.CheckUnitStealth(guid)
				-- Reconcile the cast label without promoting a remote cast into a
				-- directly observed popup candidate or starting another settling loop.
				if found ~= nil then SetUnitStealth(name, found, spell, texture, duration, nil, true) end
				stealth = stealthedState[name]
			end
			if not Targets.isConfig and stealth and not stealth.alerted and AutoBG_Spy then
				local guid = nameToGUID[name] or stealth.observedGUID or btn.targetGUID
				stealth.alerted = AutoBG_Spy:NotifyStealth(name, stealth.spellName, btn.classToken, guid, true, stealth.observedGUID) and true or false
			end
			local exp = trinketCooldown[name]
			if exp then
				if Targets.MainFrame:IsShown() then UpdateRowTrinketVisual(i, name)
				elseif exp <= now then trinketCooldown[name] = nil end
			end
		end
	end
end

local scoreboardTicker, observedTicker
local function AutoScoreboardTicker()
	if activeBG and not Targets.isConfig then RequestBattlefieldScoreData() end
end

-- ClassicAPI handles own their callbacks. Retain them only while their feature
-- needs work; a preview animates local rows without polling the scoreboard.
local function SyncTargetTimers()
	if activeBG and not Targets.isConfig then
		if not scoreboardTicker then scoreboardTicker = C_Timer.NewTicker(3.0, AutoScoreboardTicker) end
	elseif scoreboardTicker then
		scoreboardTicker:Cancel()
		scoreboardTicker = nil
	end
	if activeBG or Targets.isConfig then
		if not observedTicker then observedTicker = C_Timer.NewTicker(0.5, UpdateObservedTimers) end
	elseif observedTicker then
		observedTicker:Cancel()
		observedTicker = nil
	end
end

-- By spell ID, with SuperWoW SpellInfo names as the fallback for unlisted ranks.
local function IsTrinketSpell(spellId)
	if not spellId then return false end
	if TRINKET_SPELL_IDS[spellId] then return true end
	local sName = SpellInfo and SpellInfo(spellId)
	return sName and TRINKET_SPELL_NAMES[sName] and true or false
end

local function TriggerTrinketCooldown(name)
	if not name then return end
	local now = GetTime()
	-- CAST and BUFF_ADDED_OTHER observations describe the same use.
	if trinketCooldown[name] and trinketCooldown[name] > now then return end
	trinketCooldown[name] = now + TRINKET_COOLDOWN
	local row = nameToRow[name]
	if row and Targets.MainFrame:IsShown() then
		UpdateRowTrinketVisual(row, name)
	end
end

local function ClearAllTrinkets()
	wipe(trinketCooldown)
	if Targets.TargetButton then
		for i = 1, MAX_ENEMIES do
			local btn = Targets.TargetButton[i]
			if btn and btn.Trinket then
				btn.Trinket.Text:SetText("")
				btn.Trinket.Icon:SetVertexColor(1, 1, 1, 1)
				btn.trinketCooling = false
				btn.trinketSeconds = nil
			end
		end
	end
end

local function CreateLine(parent, layer)
	local t = parent:CreateTexture(nil, layer or "OVERLAY")
	t:SetTexture(1, 1, 1, 1)
	return t
end

local function SetBorderColor(btn, r, g, b, a)
	btn.BorderTop:SetTexture(r, g, b, a)
	btn.BorderBottom:SetTexture(r, g, b, a)
	btn.BorderLeft:SetTexture(r, g, b, a)
	btn.BorderRight:SetTexture(r, g, b, a)
end

local function MatchesSelection(btn, name, guid)
	if guid and btn.targetGUID then return guid == btn.targetGUID end
	if not name then return false end
	return name == btn.targetName or ResolveRosterName(name) == btn.targetName
end

local function UpdateRowSelectionVisual(btn, targetName, targetGUID, focusName, focusGUID)
	if not btn.targetName then return end

	local isTarget = MatchesSelection(btn, targetName, targetGUID)
	local isFocus = MatchesSelection(btn, focusName, focusGUID)
	local selection = isTarget and "TARGET" or isFocus and "FOCUS" or "NONE"
	if btn.selectionState == selection then return end
	btn.selectionState = selection

	if isTarget then
		SetBorderColor(btn, 1.0, 0.82, 0.20, 1.0)
		btn.Selection:Show()
	elseif isFocus then
		SetBorderColor(btn, 0.35, 0.75, 1.0, 1.0)
		btn.Selection:Show()
	else
		SetBorderColor(btn, 0, 0, 0, 0.80)
		btn.Selection:Hide()
	end
end

local function UpdateAllSelectionVisuals()
	if not Targets.TargetButton or not Targets.MainFrame:IsShown() then return end
	-- One coherent snapshot per redraw, rather than four object checks and
	-- duplicate name/GUID reads for every enemy row.
	local targetName, targetGUID, focusName, focusGUID
	if UnitExists("target") then targetName, targetGUID = UnitName("target"), UnitGUID("target") end
	if UnitExists("focus") then focusName, focusGUID = UnitName("focus"), UnitGUID("focus") end
	for i = 1, MAX_ENEMIES do
		local btn = Targets.TargetButton[i]
		if btn and btn:IsShown() then
			UpdateRowSelectionVisual(btn, targetName, targetGUID, focusName, focusGUID)
		end
	end
end

local function MainFrame_OnMouseDown(self)
	local f = Targets.MainFrame
	if f and f.StartMoving then
		f:StartMoving()
	end
end

local function MainFrame_OnMouseUp(self)
	local f = Targets.MainFrame
	if f and f.StopMovingOrSizing then
		f:StopMovingOrSizing()
	end
	Targets:Frame_SavePosition("AutoBG_TargetsMainFrame")
end

-- Validate cached identity before selecting it. A departed object must not
-- prevent a fresh exact-name lookup, and an unrelated object must never be used.
function Targets.SelectEnemy(name, guid, button)
	if not name then return end
	local cleanName = StripRealm(name)
	local loadedName = guid and UnitExists(guid) and UnitName(guid)
	local validGUID = loadedName and StripRealm(loadedName) == cleanName
	if validGUID and string.find(name, "-", 1, true) and string.find(loadedName, "-", 1, true) then
		validGUID = loadedName == name
	end
	if button == "RightButton" then
		if validGUID then FocusUnit(guid)
		else
			TargetByName(cleanName, true)
			local selected = UnitName("target")
			local validTarget = selected and StripRealm(selected) == cleanName
			if validTarget and string.find(name, "-", 1, true) and string.find(selected, "-", 1, true) then
				validTarget = selected == name
			end
			if UnitExists("target") and validTarget then FocusUnit("target") end
		end
	else
		if validGUID then TargetUnit(guid) else TargetByName(cleanName, true) end
	end
end

local function TargetButton_OnClick(self, button)
	local b = self or this
	Targets.SelectEnemy(b.targetName, b.targetGUID or nameToGUID[b.targetName], button or arg1)
end

local function TargetButton_OnEnter(self)
	local b = self or this
	local guid = b.targetGUID or (b.targetName and nameToGUID[b.targetName])
	if guid and type(guid) == "string" and string.sub(guid, 1, 2) == "0x" and SetMouseoverUnit then
		pcall(SetMouseoverUnit, guid)
	end
end

local function TargetButton_OnLeave(self)
	if SetMouseoverUnit then
		pcall(SetMouseoverUnit)
	end
end

local function Cast_OnClick(self, button)
	local c = self or this
	TargetButton_OnClick(c.owner, button or arg1)
end

local function Cast_OnEnter(self)
	local c = self or this
	TargetButton_OnEnter(c.owner)
end

function Targets:CreateFrames()
	if Targets.MainFrame then return end

	local main = CreateFrame("Frame", "AutoBG_TargetsMainFrame", UIParent)
	Targets.MainFrame = main
	BattlegroundTargets_MainFrame = main -- Compatibility alias
	main:SetWidth(150)
	main:SetHeight(20)
	main:SetMovable(true)
	main:SetClampedToScreen(true)
	main:EnableMouse(false)
	main:Hide()

	local header = CreateFrame("Frame", nil, main)
	main.DragHeader = header
	header:SetPoint("TOPLEFT", main, "TOPLEFT", 0, 0)
	header:SetPoint("TOPRIGHT", main, "TOPRIGHT", 0, 0)
	header:SetHeight(DRAG_HEADER_HEIGHT)
	-- UpdateHeader enables dragging out of combat.
	header:EnableMouse(false)
	header:RegisterForDrag("LeftButton")
	header:SetScript("OnDragStart", MainFrame_OnMouseDown)
	header:SetScript("OnDragStop", MainFrame_OnMouseUp)
	-- No background: the header is just a label above the rows.
	main.MoveText = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	main.MoveText:SetPoint("CENTER", header, "CENTER", 0, 1)
	main.MoveText:SetFont(FONT, 12, "OUTLINE")
	header:Show()

	Targets.TargetButton = {}
	for i = 1, MAX_ENEMIES do
		local btn = CreateFrame("Button", "AutoBG_TargetButton" .. i, main)
		Targets.TargetButton[i] = btn
		btn.buttonNum = i
		btn:SetWidth(150)
		btn:SetHeight(20)
		btn:Hide()

		if i == 1 then
			btn:SetPoint("TOPLEFT", main, "TOPLEFT", 0, -DRAG_HEADER_HEIGHT)
		else
			btn:SetPoint("TOPLEFT", Targets.TargetButton[i - 1], "BOTTOMLEFT", 0, 0)
		end

		btn.Background = btn:CreateTexture(nil, "BACKGROUND")
		btn.Background:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
		btn.Background:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
		btn.Background:SetTexture(0.15, 0.19, 0.25, 0.95)

		btn.ClassBackground = btn:CreateTexture(nil, "BORDER")
		btn.ClassBackground:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
		btn.ClassBackground:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
		btn.ClassBackground:SetTexture(0, 0, 0, 1)

		btn.HealthBar = btn:CreateTexture(nil, "ARTWORK")
		btn.HealthBar:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
		btn.HealthBar:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 1, 1)
		btn.HealthBar:SetWidth(148)

		btn.Selection = btn:CreateTexture(nil, "ARTWORK")
		btn.Selection:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
		btn.Selection:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
		btn.Selection:SetTexture(1, 1, 1, 0.08)
		btn.Selection:Hide()

		-- In range (80 yards): a thin green stripe on the left edge.
		btn.RangeMark = btn:CreateTexture(nil, "OVERLAY")
		btn.RangeMark:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
		btn.RangeMark:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 1, 1)
		btn.RangeMark:SetWidth(3)
		btn.RangeMark:SetTexture(RANGE_MARK_COLOR[1], RANGE_MARK_COLOR[2], RANGE_MARK_COLOR[3], RANGE_MARK_COLOR[4])
		btn.RangeMark:Hide()

		btn.StealthIconBg = btn:CreateTexture(nil, "ARTWORK")
		btn.StealthIconBg:SetPoint("LEFT", btn, "LEFT", 1, 0)
		btn.StealthIconBg:SetTexture(0, 0, 0, 1)
		btn.StealthIconBg:Hide()

		btn.StealthIcon = btn:CreateTexture(nil, "OVERLAY")
		btn.StealthIcon:SetPoint("LEFT", btn, "LEFT", 2, 0)
		btn.StealthIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		btn.StealthIcon:Hide()

		btn.FlagIcon = btn:CreateTexture(nil, "OVERLAY")
		btn.FlagIcon:SetPoint("RIGHT", btn, "RIGHT", -2, 0)
		btn.FlagIcon:Hide()

		btn.RaidIcon = btn:CreateTexture(nil, "OVERLAY")
		btn.RaidIcon:SetTexture(RAID_ICON_TEXTURE)
		btn.RaidIcon:Hide()

		-- Cast bar beside the row; clicking it selects the caster like the row does.
		local cast = CreateFrame("Button", "AutoBG_TargetCast" .. i, btn)
		btn.Cast = cast
		cast.owner = btn
		cast:SetFrameLevel(btn:GetFrameLevel() + 3)
		cast:Hide()
		cast.Bg = cast:CreateTexture(nil, "BACKGROUND")
		cast.Bg:SetAllPoints(cast)
		cast.Bg:SetTexture(0, 0, 0, 0.75)
		cast.Icon = cast:CreateTexture(nil, "ARTWORK")
		cast.Icon:SetPoint("TOPLEFT", cast, "TOPLEFT", 1, -1)
		cast.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		cast.Bar = cast:CreateTexture(nil, "ARTWORK")
		cast.Bar:SetPoint("TOPLEFT", cast.Icon, "TOPRIGHT", 1, 0)
		cast.Bar:SetPoint("BOTTOMLEFT", cast.Icon, "BOTTOMRIGHT", 1, 0)
		cast.Bar:SetTexture(BAR_TEXTURE)
		cast.Text = cast:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		cast.Text:SetPoint("LEFT", cast.Icon, "RIGHT", 3, 0)
		cast.Text:SetPoint("RIGHT", cast, "RIGHT", -2, 0)
		cast.Text:SetJustifyH("LEFT")
		cast:SetScript("OnUpdate", Cast_OnUpdate)
		cast:EnableMouse(true)
		cast:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		cast:SetScript("OnClick", Cast_OnClick)
		cast:SetScript("OnEnter", Cast_OnEnter)
		cast:SetScript("OnLeave", TargetButton_OnLeave)

		-- PvP Trinket Frame
		local trinket = CreateFrame("Frame", "AutoBG_TargetTrinket" .. i, btn)
		btn.Trinket = trinket
		trinket:SetFrameLevel(btn:GetFrameLevel() + 3)
		trinket:SetWidth(20)
		trinket:SetHeight(20)
		trinket:Hide()

		-- ClassicAPI's mask clips the icon to a softly rounded square.
		trinket.Icon = trinket:CreateTexture(nil, "ARTWORK")
		trinket.Icon:SetAllPoints(trinket)
		trinket.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		trinket.Icon:SetTexture(GetEnemyTrinketTexture())
		trinket.Icon:SetMask(ROUNDED_MASK)

		trinket.Text = trinket:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		trinket.Text:SetPoint("CENTER", trinket, "CENTER", 0, 0)
		trinket.Text:SetFont(FONT, 9, "OUTLINE")
		trinket.Text:SetTextColor(1, 0.85, 0.2, 1)

		btn.Name = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		btn.Name:SetPoint("LEFT", btn, "LEFT", 4, 0)
		btn.Name:SetJustifyH("LEFT")
		btn.Name:SetFont(FONT, 10, "")
		btn.Name:SetTextColor(1, 1, 1, 1)

		btn.HealthText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		btn.HealthText:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
		btn.HealthText:SetJustifyH("RIGHT")
		btn.HealthText:SetFont(FONT, 10, "OUTLINE")
		btn.HealthText:SetTextColor(1, 1, 1, 0.90)

		-- How many of your group target this enemy, just left of the health text.
		btn.TargetCount = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		btn.TargetCount:SetPoint("RIGHT", btn.HealthText, "LEFT", -3, 0)
		btn.TargetCount:SetTextColor(UI.heading[1], UI.heading[2], UI.heading[3])

		btn.Name:SetPoint("RIGHT", btn.TargetCount, "LEFT", -3, 0)

		btn.BorderTop = CreateLine(btn, "OVERLAY")
		btn.BorderTop:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
		btn.BorderTop:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0)
		btn.BorderTop:SetHeight(1)

		btn.BorderBottom = CreateLine(btn, "OVERLAY")
		btn.BorderBottom:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
		btn.BorderBottom:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
		btn.BorderBottom:SetHeight(1)

		btn.BorderLeft = CreateLine(btn, "OVERLAY")
		btn.BorderLeft:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
		btn.BorderLeft:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
		btn.BorderLeft:SetWidth(1)

		btn.BorderRight = CreateLine(btn, "OVERLAY")
		btn.BorderRight:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0)
		btn.BorderRight:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
		btn.BorderRight:SetWidth(1)

		SetBorderColor(btn, 0, 0, 0, 0.80)

		btn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
		btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		btn:SetScript("OnClick", TargetButton_OnClick)
		btn:SetScript("OnEnter", TargetButton_OnEnter)
		btn:SetScript("OnLeave", TargetButton_OnLeave)
	end

	Targets:Frame_SetupPosition("AutoBG_TargetsMainFrame")
end

function Targets:Frame_SetupPosition(frameName)
	local frame = _G[frameName] or (Targets and Targets.MainFrame)
	if not frame then return end

	local o = AutoBG_Settings and AutoBG_Settings.Targets
	local size = currentSize
	local keyPrefix = frameName
	if frameName == "AutoBG_TargetsMainFrame" then
		keyPrefix = frameName .. size
	end

	if AutoBG_LoadPosition then
		AutoBG_LoadPosition(frame, keyPrefix, "CENTER", 300, 50, "CENTER")
	else
		frame:ClearAllPoints()
		frame:SetPoint("CENTER", UIParent, "CENTER", 300, 50)
	end
end

function Targets:Frame_SavePosition(frameName)
	local frame = _G[frameName] or (Targets and Targets.MainFrame)
	if not frame then return end

	local o = AutoBG_Settings and AutoBG_Settings.Targets
	local keyPrefix = frameName
	if frameName == "AutoBG_TargetsMainFrame" then
		keyPrefix = frameName .. currentSize
	end

	if AutoBG_SavePosition then
		AutoBG_SavePosition(frame, keyPrefix)
	end
end

function Targets:SetupButtonLayout(size)
	size = size or currentSize
	currentSize = size
	Targets.currentSize = size

	if not Targets.TargetButton then
		Targets:CreateFrames()
	end

	local o = AutoBG_Settings and AutoBG_Settings.Targets
	local width = (o and o.ButtonWidth and o.ButtonWidth[size]) or 150
	local height = (o and o.ButtonHeight and o.ButtonHeight[size]) or 20
	local fontSize = (o and o.ButtonFontSize and o.ButtonFontSize[size]) or 10
	local scale = (o and o.ButtonScale and o.ButtonScale[size]) or 1.0

	Targets.MainFrame:SetWidth(width)
	Targets.MainFrame:SetHeight(DRAG_HEADER_HEIGHT + math.max(1, math.min(enemyCount, size)) * height)
	Targets.MainFrame:SetScale(scale)
	Targets.MainFrame:SetAlpha((o and o.ButtonOpacity and o.ButtonOpacity[size]) or 1)
	Targets.MainFrame:EnableMouse(false)

	for i = 1, MAX_ENEMIES do
		local btn = Targets.TargetButton[i]
		btn:SetWidth(width)
		btn:SetHeight(height)
		btn.Name:SetFont(FONT, fontSize, "OUTLINE")
		btn.HealthText:SetFont(FONT, fontSize, "OUTLINE")
		if btn.StealthIconBg then
			btn.StealthIconBg:SetWidth(height - 2)
			btn.StealthIconBg:SetHeight(height - 2)
		end
		if btn.StealthIcon then
			btn.StealthIcon:SetWidth(height - 4)
			btn.StealthIcon:SetHeight(height - 4)
		end
		if btn.FlagIcon then
			btn.FlagIcon:SetWidth(height - 2)
			btn.FlagIcon:SetHeight(height - 2)
		end
		if btn.Trinket then
			local tPos = (o and o.TrinketPos) or "RIGHT"
			btn.Trinket:ClearAllPoints()
			if tPos == "LEFT" then
				btn.Trinket:SetPoint("RIGHT", btn, "LEFT", -3, 0)
			else
				btn.Trinket:SetPoint("LEFT", btn, "RIGHT", 3, 0)
			end
			btn.Trinket:SetWidth(height)
			btn.Trinket:SetHeight(height)
			local tFontSize = math.max(7, math.floor(height * 0.45))
			btn.Trinket.Text:SetFont(FONT, tFontSize, "OUTLINE")
			btn.Trinket.Icon:SetTexture(GetEnemyTrinketTexture())
		end
		btn.RaidIcon:SetWidth(height - 6)
		btn.RaidIcon:SetHeight(height - 6)
		btn.nameInset, btn.raidInset = nil, nil
		btn.TargetCount:SetFont(FONT, fontSize, "OUTLINE")
		local cast = btn.Cast
		cast:ClearAllPoints()
		-- On the trinket's side, the cast bar sits just outside the trinket.
		local castSide = (o and o.CastPos) or "LEFT"
		local anchor = btn
		if castSide == ((o and o.TrinketPos) or "RIGHT") and o and o.ShowTrinket and o.ShowTrinket[size] then
			anchor = btn.Trinket
		end
		if castSide == "RIGHT" then
			cast:SetPoint("LEFT", anchor, "RIGHT", 3, 0)
		else
			cast:SetPoint("RIGHT", anchor, "LEFT", -3, 0)
		end
		cast:SetWidth(CAST_WIDTH)
		cast:SetHeight(height)
		cast.Icon:SetWidth(height - 2)
		cast.Icon:SetHeight(height - 2)
		cast.barMax = CAST_WIDTH - (height - 2) - 3
		cast.barWidth = nil
		cast.Text:SetFont(CAST_FONT, math.max(8, fontSize - 2), "OUTLINE")
		btn.HealthBar:SetTexture(BAR_TEXTURE)
	end

	Targets:Frame_SetupPosition("AutoBG_TargetsMainFrame")
end

local function GetBracketSize(bgName)
	if not bgName then return currentSize end
	if string.find(bgName, "Warsong") then
		return 10
	elseif string.find(bgName, "Arathi") or string.find(bgName, "Thorn") then
		return 15
	elseif string.find(bgName, "Alterac") then
		return 40
	end
	return currentSize
end

local function DetectBattleground()
	local maxQueues = MAX_BATTLEFIELD_QUEUES or 3
	for i = 1, maxQueues do
		local status, mapName = GetBattlefieldStatus(i)
		if status == "active" then
			return true, mapName
		end
	end
	return false, nil
end

-- In a match the header counts living enemies. It drags out of combat and
-- locks in combat, so a misclick cannot move the list mid-fight. While any
-- enemy is in range it also says how many, in the stripe's green, so the
-- stripe explains itself.
local function UpdateHeader()
	local main = Targets.MainFrame
	if not main then return end
	local text, color
	local total, alive, near = math.min(enemyCount, currentSize), 0, 0
	for i = 1, total do
		local btn = Targets.TargetButton and Targets.TargetButton[i]
		if not deadState[roster[i].name] then
			alive = alive + 1
			if btn and btn.inRange then near = near + 1 end
		end
	end
	if Targets.isConfig then
		text, color = "Drag to move", UI.heading
	else
		text, color = "Enemies " .. alive .. "/" .. total, UI.hint
	end
	if near > 0 then text = text .. "  " .. RANGE_MARK_TEXT .. near .. " in range|r" end
	local drag = (Targets.isConfig or not UnitAffectingCombat("player")) and true or false
	if main.headerDrag ~= drag then
		main.headerDrag = drag
		main.DragHeader:EnableMouse(drag)
	end
	if main.headerText == text then return end
	main.headerText = text
	main.MoveText:SetText(text)
	main.MoveText:SetTextColor(color[1], color[2], color[3])
end
Targets.RefreshHeader = UpdateHeader

local function RenderHealthForRow(index, name)
	local btn = Targets.TargetButton[index]
	local o = AutoBG_Settings and AutoBG_Settings.Targets
	local pct = healthPct[name] or 100
	local dead = deadState[name]
	local width = (o and o.ButtonWidth and o.ButtonWidth[currentSize]) or 150
	local maxWidth = width - 2

	local barWidth = math.max(0.01, maxWidth * pct / 100)
	if btn.healthBarWidth ~= barWidth then
		btn.healthBarWidth = barWidth
		btn.HealthBar:SetWidth(barWidth)
	end
	btn.HealthBar:Show()

	if dead and stealthedState[name] then
		local entry = stealthedState[name]
		stealthedState[name] = nil
		ReleaseStealthEntry(entry)
	end

	UpdateRowStealthVisual(index, name)
	UpdateRowFlagVisual(index, name)
	UpdateHeader()
end

local function RenderRoster()
	local o = AutoBG_Settings and AutoBG_Settings.Targets
	wipe(nameToRow)
	wipe(unknownGUIDs)
	wipe(shortNameToFull)

	local displayCount = math.min(enemyCount, currentSize)
	for i = 1, displayCount do
		local fullName = roster[i].name
		local btn = Targets.TargetButton[i]
		btn.targetName, btn.targetGUID, btn.classToken = fullName, nameToGUID[fullName], roster[i].classToken
		nameToRow[fullName] = i
		local shortName = StripRealm(fullName)
		if shortNameToFull[shortName] == nil then
			shortNameToFull[shortName] = fullName
		elseif shortNameToFull[shortName] ~= fullName then
			shortNameToFull[shortName] = false
		end
	end
	for i = displayCount + 1, MAX_ENEMIES do
		local btn = Targets.TargetButton[i]
		btn.targetName, btn.targetGUID, btn.classToken = nil, nil, nil
	end
	-- Hidden rows still need current identities for their Spy integration.
	for name in pairs(nameToGUID) do if not nameToRow[name] then nameToGUID[name] = nil end end
	for guid, name in pairs(guidToName) do
		if not nameToRow[name] or nameToGUID[name] ~= guid then guidToName[guid] = nil end
	end
	for name in pairs(healthPct) do if not nameToRow[name] then healthPct[name] = nil end end
	for name in pairs(deadState) do if not nameToRow[name] then deadState[name] = nil end end
	for name in pairs(trinketCooldown) do if not nameToRow[name] then trinketCooldown[name] = nil end end
	for name, entry in pairs(stealthedState) do
		if not nameToRow[name] then stealthedState[name] = nil; ReleaseStealthEntry(entry) end
	end
	if o and not o.EnableBracket[currentSize] and not Targets.isConfig then
		Targets.MainFrame:Hide()
		return
	end
	local height = (o and o.ButtonHeight[currentSize]) or 20
	Targets.MainFrame:SetHeight(DRAG_HEADER_HEIGHT + math.max(1, displayCount) * height)

	for i = 1, MAX_ENEMIES do
		local btn = Targets.TargetButton[i]
		if i <= displayCount then
			local data = roster[i]
			local color = GetClassColor(data.classToken)
			local name = data.name


			btn.ClassBackground:SetTexture(0.12 + color.r * 0.30, 0.12 + color.g * 0.30, 0.12 + color.b * 0.30, 1)
			btn.HealthBar:SetVertexColor(color.r, color.g, color.b, 1)

			btn.Name:SetText((o and o.ButtonHideRealm and o.ButtonHideRealm[currentSize]) and StripRealm(name) or name)
			-- A row that now shows a different enemy drops the old enemy's cast.
			if btn.castOwner ~= name then
				btn.castOwner = name
				StopCast(btn)
			end
			btn:Show()
			RenderHealthForRow(i, name)
			UpdateRowTrinketVisual(i, name)
		else
			btn.targetName = nil
			btn.targetGUID = nil
			btn.stealthTexture = nil
			btn.flagCarrier = nil
			if btn.StealthIcon then btn.StealthIcon:Hide() end
			if btn.StealthIconBg then btn.StealthIconBg:Hide() end
			if btn.FlagIcon then btn.FlagIcon:Hide() end
			if btn.Trinket then btn.Trinket:Hide() end
			btn.trinketShown = false
			btn.castOwner = nil
			StopCast(btn)
			btn:Hide()
		end
	end
	Targets.MainFrame:Show()
	UpdateAllSelectionVisuals()
	Targets.MainFrame:EnableMouse(false)
	Targets.MainFrame.DragHeader:Show()
	UpdateHeader()
	UpdateRowStatus()
end
Targets.RenderRoster = RenderRoster

function Targets:BattlefieldScoreUpdate(force)
	if Targets.isConfig then return end

	local inBG, bgName = DetectBattleground()
	if not inBG then
		local wasActive = activeBG
		activeBG = false
		Targets.activeBG = false
		SyncTargetTimers()
		if AutoBG_Spy and AutoBG_Spy.OnBattlegroundChanged then
			AutoBG_Spy:OnBattlegroundChanged(false)
		end
		if not wasActive and enemyCount == 0 then Targets.MainFrame:Hide(); return end
		ClearAllTrinkets()
		ClearAllCasts()
		prevEnemyCount = -1
		enemyCount = 0
		ClearAllStealth()
		wipe(guidToName)
		wipe(unknownGUIDs)
		wipe(nameToGUID)
		wipe(nameToRow)
		wipe(shortNameToFull)
		wipe(healthPct)
		wipe(deadState)
		Targets.MainFrame:Hide()
		return
	end
	activeBG = true
	Targets.activeBG = true
	SyncTargetTimers()
	if AutoBG_Spy and AutoBG_Spy.OnBattlegroundChanged then
		AutoBG_Spy:OnBattlegroundChanged(true)
	end

	local size = GetBracketSize(bgName)
	if size ~= currentSize then
		prevEnemyCount = -1
		Targets:SetupButtonLayout(size)
	end

	local numScores = GetNumBattlefieldScores()
	for i = 1, numScores do
		local name, _, _, _, _, faction = GetBattlefieldScore(i)
		if name and StripRealm(name) == playerName then
			enemyFaction = faction == 0 and 1 or 0
			break
		end
	end

	enemyCount = 0
	for i = 1, numScores do
		local name, _, _, _, _, faction, _, _, class, classToken = GetBattlefieldScore(i)
		if name and StripRealm(name) ~= playerName and faction == enemyFaction and enemyCount < MAX_ENEMIES then
			enemyCount = enemyCount + 1
			local e = roster[enemyCount]
			e.name = name
			local rawClass = (type(classToken) == "string" and classToken) or (type(class) == "string" and class)
			e.classToken = ResolveClassToken(rawClass)
			e.guid = nameToGUID[name]
		end
	end

	for i = enemyCount + 1, MAX_ENEMIES do
		local e = roster[i]
		e.name = nil
		e.classToken = nil
		e.guid = nil
	end

	local o = AutoBG_Settings and AutoBG_Settings.Targets
	if o and o.ButtonSortBy and o.ButtonSortBy[currentSize] == 2 then
		SortActiveRoster(NameSort)
	else
		SortActiveRoster(ClassThenNameSort)
	end

	if not force and not HasRosterChanged() then return end
	SaveRosterSnapshot()

	RenderRoster()
end

-- NamPower GetUnitField reads the health fields directly; UnitHealth covers the rest.
local function ReadHealth(unit)
	if GetUnitField then
		local hp, maxHp = GetUnitField(unit, "health"), GetUnitField(unit, "maxHealth")
		if hp and maxHp and maxHp > 0 then return hp, maxHp end
	end
	return UnitHealth(unit), UnitHealthMax(unit)
end

local function SetObservedHealth(name, curHp, maxHp, dead)
	local pct = 100
	if maxHp and maxHp > 0 and curHp then
		pct = math.floor((curHp / maxHp) * 100 + 0.5)
	end
	if dead or (curHp and curHp <= 0) then
		pct = 0
	end

	if healthPct[name] == pct and deadState[name] == dead then return end
	healthPct[name] = pct
	deadState[name] = dead

	local row = nameToRow[name]
	if row and Targets.MainFrame:IsShown() then
		RenderHealthForRow(row, name)
	end
end

-- Learn an enemy from its GUID alone (SuperWoW GUID units), once per roster.
local function RosterNameForGUID(guid)
	if not guid then return nil end
	local name = guidToName[guid]
	if name or unknownGUIDs[guid] then return name end
	-- Player GUIDs start with 0x0000; creatures and pets never match the roster.
	local rawName = string.sub(guid, 1, 6) == "0x0000" and UnitName(guid)
	-- An uncached name reads as UNKNOWNOBJECT; ask again on the next event instead of forgetting the GUID.
	if rawName == UNKNOWNOBJECT or rawName == UKNOWNBEING then return nil end
	name = rawName and ResolveRosterName(rawName, guid)
	if not name then unknownGUIDs[guid] = true; return nil end
	guidToName[guid], nameToGUID[name] = name, guid
	local row = nameToRow[name]
	if row and Targets.TargetButton[row] then Targets.TargetButton[row].targetGUID = guid end
	return name
end

local function ObserveUnit(unit, scanAuras)
	if not unit or not UnitExists(unit) or not UnitIsPlayer(unit) then return end
	local rawName = UnitName(unit)
	if not rawName then return end

	local guid = UnitGUID(unit)
	local name = ResolveRosterName(rawName, guid)
	if not name then return end

	if guid then
		nameToGUID[name] = guid
		guidToName[guid] = name
		local row = nameToRow[name]
		if row and Targets.TargetButton[row] then
			Targets.TargetButton[row].targetGUID = guid
		end
	end

	if scanAuras ~= false then
		local found, spell, texture, duration = Targets.CheckUnitStealth(unit)
		if found ~= nil then SetUnitStealth(name, found, spell, texture, duration, unit) end
	end

	-- Keep last observed health/death when the object is no longer visible.
	-- Cached/empty descriptors must not erase a newer stealth cast.
	if not UnitIsVisible(unit) then return end
	local dead = (UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit)) or (UnitIsDead(unit) or UnitIsGhost(unit)) and true or false
	local curHp, maxHp = ReadHealth(unit)
	SetObservedHealth(name, curHp, maxHp, dead)
end

function Targets:EnableConfigMode(size)
	Targets.isConfig = true
	SyncTargetTimers()
	prevEnemyCount = -1
	currentSize = size or currentSize
	Targets.currentSize = currentSize
	Targets:CreateFrames()
	Targets:SetupButtonLayout(currentSize)

	ClearAllStealth()
	ClearAllTrinkets()
	enemyCount = currentSize
	local classes = { "WARRIOR", "PRIEST", "MAGE", "DRUID", "HUNTER", "ROGUE", "SHAMAN", "PALADIN", "WARLOCK" }
	local now = GetTime()
	for i = 1, currentSize do
		local e = roster[i]
		e.name = "Target" .. i .. "-Realm"
		e.classToken = classes[((i - 1) % #classes) + 1]
		e.guid = nil
		healthPct[e.name] = 100 - ((i * 7) % 85)
		deadState[e.name] = false
		if i == 1 then
			trinketCooldown[e.name] = now + 145 -- 2:25 preview
		elseif i == 2 then
			trinketCooldown[e.name] = now + 38  -- 38s preview
		elseif i == 4 then
			trinketCooldown[e.name] = now + 88  -- 1:28 preview
		end
		-- Samples go through the same lookup as a real match: Stealth, Vanish,
		-- Prowl, Invisibility Potion, Gnomish Cloaking Device.
		local sample = (e.classToken == "ROGUE" and (i % 2 == 1 and 1787 or 1857))
			or (e.classToken == "DRUID" and i % 2 == 0 and 9913)
			or (i == 3 and 11392) or (i == 5 and 4079)
		if sample then
			local _, sName, sTex = CheckIsStealthSpell(sample)
			SetUnitStealth(e.name, true, sName, sTex, 0)
		end
	end
	for i = currentSize + 1, MAX_ENEMIES do
		local e = roster[i]
		e.name = nil
		e.classToken = nil
		e.guid = nil
	end
	-- Sample row status: a skull three of you are on, a marked mage, two far away.
	wipe(previewStatus)
	previewStatus[1] = { raid = 8, count = 3 }
	previewStatus[2] = { count = 1 }
	previewStatus[3] = { raid = 7 }
	previewStatus[6] = { far = true }
	previewStatus[7] = { far = true }
	RenderRoster()
	-- Sample casts that loop: the priest's heal and the mage's channel.
	local o = AutoBG_Settings and AutoBG_Settings.Targets
	if not (o and o.ShowCastBars == false) then
		local nowMs = GetTime() * 1000
		local heal, channel = Targets.TargetButton[2], Targets.TargetButton[3]
		ShowCast(heal, nil, "Flash Heal", "Interface\\Icons\\Spell_Holy_FlashHeal", nowMs, nowMs + 1500, false, false)
		heal.Cast.preview = true
		ShowCast(channel, nil, "Arcane Missiles", "Interface\\Icons\\Spell_Nature_StarFall", nowMs, nowMs + 5000, true, false)
		channel.Cast.preview = true
	end
end

-- Re-applies the cast bar, range, raid icon and target count switches.
function Targets:ApplyRowFeatures()
	local o = AutoBG_Settings and AutoBG_Settings.Targets
	if o and o.ShowCastBars == false then ClearAllCasts() end
	if Targets.isConfig then
		Targets:EnableConfigMode(currentSize)
	else
		UpdateRowStatus()
	end
end

function Targets:DisableConfigMode()
	Targets.isConfig = false
	prevEnemyCount = -1
	ClearAllStealth()
	ClearAllTrinkets()
	ClearAllCasts()
	wipe(previewStatus)
	for i = 1, MAX_ENEMIES do
		local btn = Targets.TargetButton[i]
		if btn then
			btn.targetName = nil
			btn.targetGUID = nil
			btn.stealthTexture = nil
			btn.flagCarrier = nil
			if btn.StealthIcon then btn.StealthIcon:Hide() end
			if btn.StealthIconBg then btn.StealthIconBg:Hide() end
			if btn.FlagIcon then btn.FlagIcon:Hide() end
			btn:Hide()
		end
	end
	-- The instance can change while preview events are suppressed.
	Targets:BattlefieldScoreUpdate(true)
end

function Targets:ToggleTestMode(size)
	if Targets.isConfig then
		Targets:DisableConfigMode()
	else
		Targets:EnableConfigMode(size or currentSize or 10)
	end
end

function Targets:ResetPosition(bracket)
	local o = AutoBG_Settings and AutoBG_Settings.Targets
	local frameName = "AutoBG_TargetsMainFrame"
	local positions = AutoBG_Settings and AutoBG_Settings.Positions

	if bracket then
		local key = frameName .. bracket
		if positions then positions[key] = nil end
		if o and o.pos then
			o.pos[key .. "_posX"] = nil
			o.pos[key .. "_posY"] = nil
		end

	else
		if positions then
			positions[frameName] = nil
			for _, sz in ipairs(BRACKETS) do
				positions[frameName .. sz] = nil
			end
		end
		if o and o.pos then
			o.pos[frameName .. "_posX"] = nil
			o.pos[frameName .. "_posY"] = nil
			for _, sz in ipairs(BRACKETS) do
				o.pos[frameName .. sz .. "_posX"] = nil
				o.pos[frameName .. sz .. "_posY"] = nil
			end
		end
	end
	Targets:Frame_SetupPosition("AutoBG_TargetsMainFrame")
end

function Targets:CopySettings(sourceSize, destinationSize)
	local o = AutoBG_Settings and AutoBG_Settings.Targets
	if not o then return end
	o.ButtonFontSize[destinationSize] = o.ButtonFontSize[sourceSize]
	o.ButtonScale[destinationSize] = o.ButtonScale[sourceSize]
	o.ButtonOpacity[destinationSize] = o.ButtonOpacity[sourceSize]
	o.ButtonWidth[destinationSize] = o.ButtonWidth[sourceSize]
	o.ButtonHeight[destinationSize] = o.ButtonHeight[sourceSize]
	o.ButtonShowHealthText[destinationSize] = o.ButtonShowHealthText[sourceSize]
	o.ButtonHideRealm[destinationSize] = o.ButtonHideRealm[sourceSize]
	o.ButtonSortBy[destinationSize] = o.ButtonSortBy[sourceSize]
	o.DimStealthed[destinationSize] = o.DimStealthed[sourceSize]
	o.ShowTrinket[destinationSize] = o.ShowTrinket[sourceSize]
end

Targets:RegisterEvent("PLAYER_LOGIN")
Targets:RegisterEvent("PLAYER_ENTERING_WORLD")
Targets:RegisterEvent("ZONE_CHANGED_NEW_AREA")
Targets:RegisterEvent("UPDATE_BATTLEFIELD_STATUS")
Targets:RegisterEvent("UPDATE_BATTLEFIELD_SCORE")
Targets:RegisterEvent("UNIT_AURA")
Targets:RegisterEvent("UNIT_HEALTH")
Targets:RegisterEvent("UNIT_TARGET")
Targets:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
Targets:RegisterEvent("PLAYER_TARGET_CHANGED")
Targets:RegisterEvent("PLAYER_FOCUS_CHANGED")
Targets:RegisterEvent("RAID_TARGET_UPDATE")
Targets:RegisterEvent("NAME_PLATE_UNIT_ADDED")
Targets:RegisterEvent("UNIT_NAME_UPDATE")
Targets:RegisterEvent("UNIT_CASTEVENT")
Targets:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
-- NamPower GUID events: health, death and buffs for every loaded enemy, not only
-- those on a target/mouseover/nameplate token (Emyrk/nampower EVENTS.md).
Targets:RegisterEvent("UNIT_HEALTH_GUID")
Targets:RegisterEvent("UNIT_DIED")
Targets:RegisterEvent("PLAYER_REGEN_DISABLED")
Targets:RegisterEvent("PLAYER_REGEN_ENABLED")
Targets:RegisterEvent("BUFF_ADDED_OTHER")
Targets:RegisterEvent("BUFF_REMOVED_OTHER")

local TARGETS_LIFECYCLE_EVENTS = {
	PLAYER_LOGIN = true,
	PLAYER_ENTERING_WORLD = true,
	ZONE_CHANGED_NEW_AREA = true,
	UPDATE_BATTLEFIELD_STATUS = true,
	UPDATE_BATTLEFIELD_SCORE = true,
}

local function Targets_OnEvent(arg1_param, arg2_param, arg3_param, arg4_param, arg5_param, arg6_param, arg7_param)
	local ev, a1, a2, a3, a4, a5
	if type(arg1_param) == "string" then
		ev, a1, a2, a3, a4, a5 = arg1_param, arg2_param, arg3_param, arg4_param, arg5_param, arg6_param
	elseif type(arg2_param) == "string" then
		ev, a1, a2, a3, a4, a5 = arg2_param, arg3_param, arg4_param, arg5_param, arg6_param, arg7_param
	else
		ev, a1, a2, a3, a4, a5 = event, arg1, arg2, arg3, arg4, arg5
	end
	if not (activeBG or Targets.isConfig) and not TARGETS_LIFECYCLE_EVENTS[ev] then
		return
	end

	if ev == "PLAYER_LOGIN" then
		playerName = StripRealm(UnitName("player"))
		playerFaction = UnitFactionGroup("player") == "Horde" and 0 or 1
		enemyFaction = playerFaction == 0 and 1 or 0
		Targets:EnsureOptions()
		Targets:CreateFrames()
		Targets:SetupButtonLayout(currentSize)

	elseif ev == "PLAYER_ENTERING_WORLD" or ev == "ZONE_CHANGED_NEW_AREA" or ev == "UPDATE_BATTLEFIELD_STATUS" then
		prevEnemyCount = -1
		Targets:OnCarrierChanged()
		RequestBattlefieldScoreData()
		Targets:BattlefieldScoreUpdate()

	elseif ev == "PLAYER_REGEN_DISABLED" or ev == "PLAYER_REGEN_ENABLED" then
		UpdateHeader()

	elseif ev == "UPDATE_BATTLEFIELD_SCORE" then
		Targets:BattlefieldScoreUpdate()

	elseif ev == "UNIT_HEALTH" then
		ObserveUnit(a1, false)

	elseif ev == "UNIT_AURA" then
		ObserveUnit(a1)

	elseif ev == "UNIT_TARGET" then
		if a1 then ObserveUnit(GetUnitTargetToken(a1)) end

	elseif ev == "UPDATE_MOUSEOVER_UNIT" then
		ObserveUnit("mouseover")

	elseif ev == "PLAYER_TARGET_CHANGED" then
		ObserveUnit("target")
		UpdateAllSelectionVisuals()
		UpdateRowStatus()

	elseif ev == "RAID_TARGET_UPDATE" then
		UpdateRowStatus()

	elseif ev == "PLAYER_FOCUS_CHANGED" then
		ObserveUnit("focus")
		UpdateAllSelectionVisuals()

	elseif ev == "NAME_PLATE_UNIT_ADDED" or ev == "UNIT_NAME_UPDATE" then
		ObserveUnit(a1)

	elseif ev == "UNIT_HEALTH_GUID" then
		-- arg1 = guid. Fires for every unit the client tracks; only roster GUIDs matter.
		local name = RosterNameForGUID(a1)
		if name and nameToRow[name] then
			local curHp, maxHp = ReadHealth(a1)
			SetObservedHealth(name, curHp, maxHp, (curHp or 0) <= 0)
		end

	elseif ev == "UNIT_DIED" then
		local name = RosterNameForGUID(a1)
		if name and nameToRow[name] then SetObservedHealth(name, 0, 100, true) end

	elseif ev == "BUFF_ADDED_OTHER" or ev == "BUFF_REMOVED_OTHER" then
		-- arg1 = guid, arg3 = spell ID. The aura itself is authoritative, so no settling wait.
		local name = RosterNameForGUID(a1)
		if not name then return end
		-- PvP trinkets apply their immunity aura on use ("X gains Immune ..." in the combat log).
		if ev == "BUFF_ADDED_OTHER" and IsTrinketSpell(a3) then TriggerTrinketCooldown(name) end
		local isStealth, sName, sTex, sDur = CheckIsStealthSpell(a3)
		if isStealth then
			if ev == "BUFF_ADDED_OTHER" then
				SetUnitStealth(name, true, sName, sTex, sDur, a1)
			elseif stealthedState[name] then
				SetUnitStealth(name, false)
			end
		end

	elseif ev == "UNIT_CASTEVENT" or ev == "UNIT_SPELLCAST_SUCCEEDED" then
		local modern = ev == "UNIT_SPELLCAST_SUCCEEDED"
		local casterGUID = a1
		if modern then casterGUID = UnitGUID(a1) end
		local eventType = modern and "CAST" or a3
		local spellId = modern and a3 or a4
		if not casterGUID then return end

		local rawName = UnitName(casterGUID) or guidToName[casterGUID]
		if not rawName then return end
		local name = ResolveRosterName(rawName, casterGUID)
		if not name then return end

		guidToName[casterGUID] = name
		nameToGUID[name] = casterGUID
		local row = nameToRow[name]
		if row and Targets.TargetButton[row] then
			Targets.TargetButton[row].targetGUID = casterGUID
		end

		if eventType == "CAST" then
			if IsTrinketSpell(spellId) then
				TriggerTrinketCooldown(name)
			end

			local isStealth, sName, sTex, sDur = CheckIsStealthSpell(spellId)
			if isStealth then
				SetUnitStealth(name, true, sName, sTex, sDur)
			end
		elseif eventType == "MAINHAND" or eventType == "OFFHAND" then
			if stealthedState[name] then
				SetUnitStealth(name, false)
			end
		end

		-- Cast bars: START/CHANNEL begin a cast, CAST ends it, FAIL means it was
		-- interrupted or cancelled. a5 is the cast duration in milliseconds.
		if row and not modern then
			if eventType == "FAIL" then
				StopCast(Targets.TargetButton[row])
			elseif eventType == "START" or eventType == "CHANNEL" then
				RefreshCast(row, spellId, a5, eventType == "CHANNEL")
			elseif eventType == "CAST" then
				RefreshCast(row)
			end
		end
	end
end
Targets:SetScript("OnEvent", Targets_OnEvent)
