-- -------------------------------------------------------------------------- --
-- AutoBG: Enemy Target Frames Module (Consolidated from BattlegroundTargets)  --
-- Engineered natively for World of Warcraft 1.12.1 (Enhanced Engine)        --
-- ClassicAPI v1.14.0+, SuperWoW v2.2+, UnitXP SP3, NamPower, and DXVK.     --
-- -------------------------------------------------------------------------- --

-- Strict Engine Dependency Guard (Mandatory ClassicAPI v1.14.0+ & SuperWoW v2.2+)
local MIN_CLASSIC_API = 11400

if not (CLASSIC_API_VERSION and SUPERWOW_VERSION) or 
   (type(CLASSIC_API_VERSION) == "number" and CLASSIC_API_VERSION < MIN_CLASSIC_API) then
	return
end

local MAX_ENEMIES = 40
local BRACKETS = { 10, 15, 40 }
local FONT = "Fonts\\FRIZQT__.TTF"
local BAR_TEXTURE = [[Interface\AddOns\AutoBG\Textures\barTexture.tga]]
local PROWL_TEXTURE = [[Interface\AddOns\AutoBG\Textures\prowl.tga]]
local HORDE_FLAG_TEXTURE = "Interface\\WorldStateFrame\\HordeFlag"
local ALLIANCE_FLAG_TEXTURE = "Interface\\WorldStateFrame\\AllianceFlag"
local ALLIANCE_TRINKET_TEXTURE = "Interface\\Icons\\INV_Jewelry_TrinketPVP_01"
local HORDE_TRINKET_TEXTURE = "Interface\\Icons\\INV_Jewelry_TrinketPVP_02"

local TRINKET_SPELL_IDS = {
	[52317] = 180, -- Turtle WoW PvP Trinket (Insignia of the Alliance / Horde, 3m CD)
	[23505] = 300, -- Vanilla Warrior Insignia
	[23506] = 300, -- Vanilla Paladin Insignia
	[23507] = 300, -- Vanilla Hunter Insignia
	[23508] = 300, -- Vanilla Rogue Insignia
	[23509] = 300, -- Vanilla Priest Insignia
	[23510] = 300, -- Vanilla Shaman Insignia
	[23511] = 300, -- Vanilla Mage Insignia
	[23512] = 300, -- Vanilla Warlock Insignia
	[23513] = 300, -- Vanilla Druid Insignia
}

local function GetEnemyTrinketTexture()
	local f = UnitFactionGroup("player")
	return (f == "Horde") and ALLIANCE_TRINKET_TEXTURE or HORDE_TRINKET_TEXTURE
end

AutoBG_Targets = CreateFrame("Frame", "AutoBG_TargetsCoreFrame", UIParent)
local Targets = AutoBG_Targets
BattlegroundTargets = AutoBG_Targets -- Backwards-compatibility alias

Targets.currentSize = 10
Targets.isConfig = false

local playerName = UnitName("player")
local playerFaction = UnitFactionGroup("player") == "Horde" and 0 or 1
local enemyFaction = playerFaction == 0 and 1 or 0
local activeBG = false
Targets.activeBG = false
local currentSize = 10

local CLASS_COLORS = {
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
if RAID_CLASS_COLORS then
	for k, v in pairs(RAID_CLASS_COLORS) do
		if k ~= "SHAMAN" and not CLASS_COLORS[k] then
			CLASS_COLORS[k] = v
		end
	end
end

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
	return (CLASS_COLORS[upper] and upper) or "WARRIOR"
end

local function GetClassColor(classToken)
	return CLASS_COLORS[classToken] or FALLBACK_COLOR
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

local STEALTH_SPELLS = {
	-- Rogue Stealth
	[1784] = { name = "Stealth", texture = "Interface\\Icons\\Ability_Stealth", duration = 0 },
	[1785] = { name = "Stealth", texture = "Interface\\Icons\\Ability_Stealth", duration = 0 },
	[1786] = { name = "Stealth", texture = "Interface\\Icons\\Ability_Stealth", duration = 0 },
	[1787] = { name = "Stealth", texture = "Interface\\Icons\\Ability_Stealth", duration = 0 },
	-- Rogue Vanish
	[1856] = { name = "Vanish",  texture = "Interface\\Icons\\Ability_Stealth",  duration = 0 },
	[1857] = { name = "Vanish",  texture = "Interface\\Icons\\Ability_Stealth",  duration = 0 },
	-- Druid Prowl
	[5215] = { name = "Prowl",   texture = PROWL_TEXTURE, duration = 0 },
	[6783] = { name = "Prowl",   texture = PROWL_TEXTURE, duration = 0 },
	[9913] = { name = "Prowl",   texture = PROWL_TEXTURE, duration = 0 },
	-- Night Elf Shadowmeld
	[20580] = { name = "Shadowmeld", texture = "Interface\\Icons\\Ability_Racial_ShadowMeld", duration = 0 },
	-- Invisibility Potions
	[3680]  = { name = "Lesser Invisibility", texture = "Interface\\Icons\\Spell_Nature_Invisibilty", duration = 15 },
	[11464] = { name = "Invisibility",        texture = "Interface\\Icons\\Spell_Nature_Invisibilty", duration = 18 },
	-- Gnomish Cloaking Device
	[8342]  = { name = "Cloaking",            texture = "Interface\\Icons\\INV_Misc_EngGizmos_04",   duration = 60 },
	-- Deepwood Pipe (Smoke Cloud)
	[23133] = { name = "Smoke Cloud",         texture = "Interface\\Icons\\Ability_Stealth", duration = 30 },
	[23134] = { name = "Smoke Cloud",         texture = "Interface\\Icons\\Ability_Stealth", duration = 30 },
	-- Mage Invisibility (custom/Vanilla+)
	[66]    = { name = "Invisibility",        texture = "Interface\\Icons\\Spell_Nature_Invisibilty", duration = 20 },
	[32612] = { name = "Invisibility",        texture = "Interface\\Icons\\Spell_Nature_Invisibilty", duration = 20 },
}

local STEALTH_NAMES = {
	["Stealth"]             = { name = "Stealth",             texture = "Interface\\Icons\\Ability_Stealth", duration = 0 },
	["Prowl"]               = { name = "Prowl",               texture = PROWL_TEXTURE, duration = 0 },
	["Vanish"]              = { name = "Vanish",              texture = "Interface\\Icons\\Ability_Stealth", duration = 0 },
	["Shadowmeld"]          = { name = "Shadowmeld",          texture = "Interface\\Icons\\Ability_Racial_ShadowMeld", duration = 0 },
	["Invisibility"]        = { name = "Invisibility",        texture = "Interface\\Icons\\Spell_Nature_Invisibilty", duration = 18 },
	["Lesser Invisibility"] = { name = "Lesser Invisibility", texture = "Interface\\Icons\\Spell_Nature_Invisibilty", duration = 15 },
	["Cloaking"]            = { name = "Cloaking",            texture = "Interface\\Icons\\INV_Misc_EngGizmos_04", duration = 60 },
	["Smoke Cloud"]         = { name = "Smoke Cloud",         texture = "Interface\\Icons\\Ability_Stealth", duration = 30 },
}

local function CheckIsStealthSpell(spellId)
	if not spellId then return false end
	local s = STEALTH_SPELLS[spellId]
	local spellTex = s and s.texture
	local spellName = s and s.name
	local spellDur = s and s.duration or 0

	if SpellInfo then
		local name = SpellInfo(spellId)
		if name and name ~= "" then
			spellName = spellName or name
		end
	end

	if s or (spellName and STEALTH_NAMES[spellName]) then
		local def = spellName and STEALTH_NAMES[spellName]
		local finalName = spellName or (def and def.name) or "Stealth"
		local finalTex = (def and def.texture) or spellTex or "Interface\\Icons\\Ability_Stealth"
		local finalDur = spellDur or (def and def.duration) or 0
		return true, finalName, finalTex, finalDur
	end

	return false
end

local function CheckIsStealthName(spellName)
	if not spellName then return false end
	local data = STEALTH_NAMES[spellName]
	if data then
		return true, data.name, data.texture, data.duration
	end
	return false
end
Targets.CheckIsStealthSpell = CheckIsStealthSpell
Targets.CheckIsStealthName = CheckIsStealthName

local function StripRealm(name)
	if not name then return "" end
	local p = string.find(name, "-", 1, true)
	if p then
		return string.sub(name, 1, p - 1)
	end
	return name
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
	o.pos = o.pos or {}
	o.EnableBracket = o.EnableBracket or {}
	o.IndependentPositioning = o.IndependentPositioning or {}
	o.ButtonFontSize = o.ButtonFontSize or {}
	o.ButtonScale = o.ButtonScale or {}
	o.ButtonWidth = o.ButtonWidth or {}
	o.ButtonHeight = o.ButtonHeight or {}
	o.ButtonShowHealthBar = o.ButtonShowHealthBar or {}
	o.ButtonShowHealthText = o.ButtonShowHealthText or {}
	o.ButtonHideRealm = o.ButtonHideRealm or {}
	o.ButtonSortBy = o.ButtonSortBy or {}
	o.ShowStealthIcon = o.ShowStealthIcon or {}
	o.DimStealthed = o.DimStealthed or {}
	o.ShowStealthText = o.ShowStealthText or {}
	o.ShowFlagCarrier = o.ShowFlagCarrier or {}
	o.ShowTrinket = o.ShowTrinket or {}
	if o.TrinketPos == nil then o.TrinketPos = "RIGHT" end

	for _, size in ipairs(BRACKETS) do
		if o.EnableBracket[size] == nil then o.EnableBracket[size] = true end
		if o.IndependentPositioning[size] == nil then o.IndependentPositioning[size] = false end
		if o.ButtonFontSize[size] == nil then o.ButtonFontSize[size] = 10 end
		if o.ButtonScale[size] == nil then o.ButtonScale[size] = (size == 10 and 1.10) or (size == 15 and 1.00) or 0.90 end
		if o.ButtonWidth[size] == nil then o.ButtonWidth[size] = 150 end
		if o.ButtonHeight[size] == nil then o.ButtonHeight[size] = (size == 40 and 18) or 20 end
		if o.ButtonShowHealthBar[size] == nil then o.ButtonShowHealthBar[size] = true end
		if o.ButtonShowHealthText[size] == nil then o.ButtonShowHealthText[size] = true end
		if o.ButtonHideRealm[size] == nil then o.ButtonHideRealm[size] = false end
		if o.ButtonSortBy[size] == nil then o.ButtonSortBy[size] = 1 end
		if o.ShowStealthIcon[size] == nil then o.ShowStealthIcon[size] = true end
		if o.DimStealthed[size] == nil then o.DimStealthed[size] = false end
		if o.ShowStealthText[size] == nil then o.ShowStealthText[size] = true end
		if o.ShowFlagCarrier[size] == nil then o.ShowFlagCarrier[size] = true end
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
	local o = AutoBG_Settings and AutoBG_Settings.Targets
	local size = currentSize
	local enemyCarrier = GetEnemyFlagCarrier()
	local isCarrier = enemyCarrier and (StripRealm(name) == StripRealm(enemyCarrier))

	if isCarrier and (o and o.ShowFlagCarrier and o.ShowFlagCarrier[size] ~= false) then
		btn.FlagIcon:SetTexture(GetEnemyFlagTexture())
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
	if not Targets.TargetButton then return end
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

	if stealth and not dead and (not o or o.ShowStealthIcon[size] ~= false) then
		local sName = stealth.spellName or "Stealth"
		local tex = stealth.texture
		if sName == "Prowl" or string.find(tex or "", "prowl") or string.find(tex or "", "SupriseAttack") or string.find(tex or "", "Pet_Cat") or string.find(tex or "", "Ambush") or string.find(tex or "", "CatForm") then
			tex = PROWL_TEXTURE
		elseif sName == "Vanish" or sName == "Stealth" or string.find(tex or "", "Vanish") or string.find(tex or "", "Stealth") then
			tex = "Interface\\Icons\\Ability_Stealth"
		elseif not tex or tex == "" then
			tex = "Interface\\Icons\\Ability_Stealth"
		end
		btn.StealthIcon:SetTexture(tex)
		btn.StealthIcon:SetVertexColor(1, 1, 1, 1)
		btn.StealthIcon:Show()
		btn.StealthIconBg:Show()
		btn.Name:SetPoint("LEFT", btn, "LEFT", height + 1, 0)
	else
		btn.StealthIcon:Hide()
		btn.StealthIconBg:Hide()
		btn.Name:SetPoint("LEFT", btn, "LEFT", 4, 0)
	end

	if dead then
		btn:SetAlpha(0.55)
	elseif stealth and o and o.DimStealthed and o.DimStealthed[size] then
		btn:SetAlpha(0.75)
	else
		btn:SetAlpha(1.0)
	end

	if stealth and not dead and (not o or o.ShowStealthText[size] ~= false) then
		local sName = stealth.spellName or "Stealth"
		local tag = (sName == "Prowl" and "|cffb0b0ffPROWL|r")
			or (sName == "Vanish" and "|cffb0b0ffVANISH|r")
			or (sName == "Shadowmeld" and "|cff9090ffMELD|r")
			or (sName == "Cloaking" and "|cff00ffffCLOAK|r")
			or (string.find(sName, "Invis") and "|cff00ffffINVIS|r")
			or "|cff9090ffSTEALTH|r"
		btn.HealthText:SetText(tag)
		btn.HealthText:Show()
	else
		local pct = healthPct[name] or 100
		if not o or o.ButtonShowHealthText[size] then
			btn.HealthText:SetText(dead and "|cffff4040DEAD|r" or (pct .. "%"))
			btn.HealthText:Show()
		else
			btn.HealthText:Hide()
		end
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

SetUnitStealth = function(name, isStealthed, spellName, texture, duration)
	if not name then return end
	if isStealthed then
		local entry = stealthedState[name]
		if not entry then
			entry = AcquireStealthEntry()
			stealthedState[name] = entry
		end
		entry.isStealthed = true
		entry.spellName = spellName or "Stealth"
		entry.texture = texture or "Interface\\Icons\\Ability_Stealth"
		local exp = (duration and duration > 0) and (GetTime() + duration + 0.5) or nil
		entry.expireTime = exp

		if exp and stealthWatcher and not stealthWatcher:IsShown() then
			stealthWatcher:Show()
		end
	else
		local entry = stealthedState[name]
		if entry then
			stealthedState[name] = nil
			ReleaseStealthEntry(entry)
		end
	end

	local row = nameToRow[name]
	if row then
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
	if (o and o.ShowTrinket and o.ShowTrinket[size] == false) or not name or not btn:IsShown() then
		btn.Trinket:Hide()
		return
	end

	btn.Trinket:Show()
	btn.Trinket.Icon:SetTexture(GetEnemyTrinketTexture())

	local exp = trinketCooldown[name]
	local now = GetTime()
	if exp and exp > now then
		local rem = exp - now
		btn.Trinket.Icon:SetVertexColor(0.35, 0.35, 0.35, 0.75)
		if rem >= 60 then
			local m = math.floor(rem / 60)
			local s = math.floor(rem % 60)
			btn.Trinket.Text:SetText(string.format("%d:%02d", m, s))
		else
			btn.Trinket.Text:SetText(math.floor(rem) .. "s")
		end
		btn.Trinket.Text:SetTextColor(1, 0.85, 0.20, 1)
	else
		if exp then
			trinketCooldown[name] = nil
		end
		btn.Trinket.Icon:SetVertexColor(1, 1, 1, 1)
		btn.Trinket.Text:SetText("")
	end
end

local function UpdateAllTrinketTimers()
	if not Targets.TargetButton then return end
	for i = 1, MAX_ENEMIES do
		local btn = Targets.TargetButton[i]
		if btn and btn:IsShown() and btn.targetName then
			local name = btn.targetName
			local exp = trinketCooldown[name]
			if exp then
				UpdateRowTrinketVisual(i, name)
			end
		end
	end
end

local function TriggerTrinketCooldown(name, duration)
	if not name then return end
	trinketCooldown[name] = GetTime() + (duration or 180)
	local row = nameToRow[name]
	if row then
		UpdateRowTrinketVisual(row, name)
	end
end

local function ClearAllTrinkets()
	for name in pairs(trinketCooldown) do
		trinketCooldown[name] = nil
	end
	if Targets.TargetButton then
		for i = 1, MAX_ENEMIES do
			local btn = Targets.TargetButton[i]
			if btn and btn.Trinket then
				btn.Trinket.Text:SetText("")
				btn.Trinket.Icon:SetVertexColor(1, 1, 1, 1)
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

local function UpdateRowSelectionVisual(btn)
	if not btn.targetName then return end

	local targetName = UnitExists("target") and UnitName("target") or nil
	local focusName = UnitExists("focus") and UnitName("focus") or nil

	if targetName == btn.targetName then
		SetBorderColor(btn, 1.0, 0.82, 0.20, 1.0)
		btn.Selection:Show()
	elseif focusName == btn.targetName then
		SetBorderColor(btn, 0.35, 0.75, 1.0, 1.0)
		btn.Selection:Show()
	else
		SetBorderColor(btn, 0, 0, 0, 0.80)
		btn.Selection:Hide()
	end
end

local function UpdateAllSelectionVisuals()
	if not Targets.TargetButton then return end
	for i = 1, MAX_ENEMIES do
		local btn = Targets.TargetButton[i]
		if btn and btn:IsShown() then
			UpdateRowSelectionVisual(btn)
		end
	end
end

local function MainFrame_OnMouseDown(self)
	local f = self or this or (Targets and Targets.MainFrame)
	if Targets.isConfig and f and f.StartMoving then
		f:StartMoving()
	end
end

local function MainFrame_OnMouseUp(self)
	local f = self or this or (Targets and Targets.MainFrame)
	if f and f.StopMovingOrSizing then
		f:StopMovingOrSizing()
	end
	Targets:Frame_SavePosition("AutoBG_TargetsMainFrame")
end

local function TargetButton_OnClick(self, button)
	local b = self or this
	local btn = button or arg1
	local name = b.targetName
	if not name then return end

	local guid = b.targetGUID or nameToGUID[name]
	if btn == "LeftButton" then
		if guid then
			TargetUnit(guid)
		else
			TargetByName(name, true)
		end
	elseif btn == "RightButton" then
		local isCurrentTarget = UnitExists("target") and (UnitName("target") == name)
		if isCurrentTarget then
			FocusUnit("target")
		else
			local hadPriorTarget = UnitExists("target")
			if guid then
				TargetUnit(guid)
			else
				TargetByName(name, true)
			end
			if UnitExists("target") and UnitName("target") == name then
				FocusUnit("target")
			end
			if hadPriorTarget then
				TargetLastTarget()
			else
				ClearTarget()
			end
		end
	end
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
	main:EnableMouse(Targets.isConfig and true or false)
	main:Hide()

	main:SetScript("OnMouseDown", MainFrame_OnMouseDown)
	main:SetScript("OnMouseUp", MainFrame_OnMouseUp)

	main.MoveText = main:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	main.MoveText:SetPoint("CENTER", main, "CENTER", 0, 0)
	main.MoveText:SetText("AutoBG Targets: drag to move")
	main.MoveText:SetTextColor(0.8, 0.8, 0.8, 1)

	Targets.TargetButton = {}
	for i = 1, MAX_ENEMIES do
		local btn = CreateFrame("Button", "AutoBG_TargetButton" .. i, main)
		Targets.TargetButton[i] = btn
		btn.buttonNum = i
		btn:SetWidth(150)
		btn:SetHeight(20)
		btn:Hide()

		if i == 1 then
			btn:SetPoint("TOPLEFT", main, "BOTTOMLEFT", 0, 0)
		else
			btn:SetPoint("TOPLEFT", Targets.TargetButton[i - 1], "BOTTOMLEFT", 0, 0)
		end

		btn.Background = btn:CreateTexture(nil, "BACKGROUND")
		btn.Background:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
		btn.Background:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
		btn.Background:SetTexture(0, 0, 0, 0.58)

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

		-- PvP Trinket Frame
		local trinket = CreateFrame("Frame", "AutoBG_TargetTrinket" .. i, btn)
		btn.Trinket = trinket
		trinket:SetWidth(20)
		trinket:SetHeight(20)
		trinket:Hide()

		trinket.Bg = trinket:CreateTexture(nil, "BACKGROUND")
		trinket.Bg:SetPoint("TOPLEFT", trinket, "TOPLEFT", 0, 0)
		trinket.Bg:SetPoint("BOTTOMRIGHT", trinket, "BOTTOMRIGHT", 0, 0)
		trinket.Bg:SetTexture(0, 0, 0, 0.85)

		trinket.Icon = trinket:CreateTexture(nil, "ARTWORK")
		trinket.Icon:SetPoint("TOPLEFT", trinket, "TOPLEFT", 1, -1)
		trinket.Icon:SetPoint("BOTTOMRIGHT", trinket, "BOTTOMRIGHT", -1, 1)
		trinket.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		trinket.Icon:SetTexture(GetEnemyTrinketTexture())

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

		btn.Name:SetPoint("RIGHT", btn.HealthText, "LEFT", -4, 0)

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
	end

	Targets:Frame_SetupPosition("AutoBG_TargetsMainFrame")
end

function Targets:Frame_SetupPosition(frameName)
	local frame = _G[frameName]
	if not frame then return end

	local o = AutoBG_Settings and AutoBG_Settings.Targets
	local size = currentSize
	local keyPrefix = frameName
	if frameName == "AutoBG_TargetsMainFrame" and o and o.IndependentPositioning and o.IndependentPositioning[size] then
		keyPrefix = frameName .. size
	end

	local x = o and o.pos and o.pos[keyPrefix .. "_posX"]
	local y = o and o.pos and o.pos[keyPrefix .. "_posY"]
	frame:ClearAllPoints()
	if x and y then
		frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
	else
		frame:SetPoint("CENTER", UIParent, "CENTER", 300, 50)
	end
end

function Targets:Frame_SavePosition(frameName)
	local frame = _G[frameName]
	if not frame then return end

	local o = AutoBG_Settings and AutoBG_Settings.Targets
	if not o then return end
	o.pos = o.pos or {}
	local keyPrefix = frameName
	if frameName == "AutoBG_TargetsMainFrame" and o.IndependentPositioning and o.IndependentPositioning[currentSize] then
		keyPrefix = frameName .. currentSize
	end

	o.pos[keyPrefix .. "_posX"] = frame:GetLeft()
	o.pos[keyPrefix .. "_posY"] = frame:GetTop()
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", o.pos[keyPrefix .. "_posX"], o.pos[keyPrefix .. "_posY"])
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
	Targets.MainFrame:SetScale(scale)
	Targets.MainFrame:EnableMouse(Targets.isConfig and true or false)

	for i = 1, MAX_ENEMIES do
		local btn = Targets.TargetButton[i]
		btn:SetWidth(width)
		btn:SetHeight(height)
		btn.Name:SetFont(FONT, fontSize, "")
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

local function RenderHealthForRow(index, name)
	local btn = Targets.TargetButton[index]
	local o = AutoBG_Settings and AutoBG_Settings.Targets
	local pct = healthPct[name] or 100
	local dead = deadState[name]
	local width = (o and o.ButtonWidth and o.ButtonWidth[currentSize]) or 150
	local maxWidth = width - 2

	if not o or o.ButtonShowHealthBar[currentSize] then
		btn.HealthBar:SetWidth(math.max(0.01, maxWidth * pct / 100))
		btn.HealthBar:Show()
	else
		btn.HealthBar:Hide()
	end

	if dead and stealthedState[name] then
		local entry = stealthedState[name]
		stealthedState[name] = nil
		ReleaseStealthEntry(entry)
	end

	UpdateRowStealthVisual(index, name)
	UpdateRowFlagVisual(index, name)
end

local function RenderRoster()
	local o = AutoBG_Settings and AutoBG_Settings.Targets
	if o and not o.EnableBracket[currentSize] and not Targets.isConfig then
		Targets.MainFrame:Hide()
		return
	end

	wipe(nameToRow)
	wipe(shortNameToFull)

	local displayCount = math.min(enemyCount, currentSize)
	for i = 1, displayCount do
		local fullName = roster[i].name
		local shortName = StripRealm(fullName)
		if shortNameToFull[shortName] == nil then
			shortNameToFull[shortName] = fullName
		elseif shortNameToFull[shortName] ~= fullName then
			shortNameToFull[shortName] = false
		end
	end

	for i = 1, MAX_ENEMIES do
		local btn = Targets.TargetButton[i]
		if i <= displayCount then
			local data = roster[i]
			local color = GetClassColor(data.classToken)
			local name = data.name

			btn.targetName = name
			btn.targetGUID = nameToGUID[name]
			btn.classToken = data.classToken
			nameToRow[name] = i

			btn.ClassBackground:SetTexture(color.r * 0.30, color.g * 0.30, color.b * 0.30, 1)
			btn.HealthBar:SetVertexColor(color.r, color.g, color.b, 1)

			btn.Name:SetText((o and o.ButtonHideRealm and o.ButtonHideRealm[currentSize]) and StripRealm(name) or name)
			RenderHealthForRow(i, name)
			UpdateRowSelectionVisual(btn)
			UpdateRowTrinketVisual(i, name)
			btn:Show()
		else
			btn.targetName = nil
			btn.targetGUID = nil
			if btn.StealthIcon then btn.StealthIcon:Hide() end
			if btn.StealthIconBg then btn.StealthIconBg:Hide() end
			if btn.FlagIcon then btn.FlagIcon:Hide() end
			if btn.Trinket then btn.Trinket:Hide() end
			btn:Hide()
		end
	end

	Targets.MainFrame:Show()
	Targets.MainFrame:EnableMouse(Targets.isConfig and true or false)
	Targets.MainFrame.MoveText:SetShown(Targets.isConfig and true or false)
end
Targets.RenderRoster = RenderRoster

function Targets:BattlefieldScoreUpdate(force)
	if Targets.isConfig then return end

	local inBG, bgName = DetectBattleground()
	if not inBG then
		activeBG = false
		Targets.activeBG = false
		ClearAllTrinkets()
		if AutoBG_Spy and AutoBG_Spy.OnBattlegroundChanged then
			AutoBG_Spy:OnBattlegroundChanged(false)
		end
		prevEnemyCount = -1
		ClearAllStealth()
		wipe(guidToName)
		Targets.MainFrame:Hide()
		return
	end
	activeBG = true
	Targets.activeBG = true
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

local function ObserveUnit(unit)
	if not unit or not UnitExists(unit) then return end
	local rawName = UnitName(unit)
	if not rawName then return end

	local name = nameToRow[rawName] and rawName or shortNameToFull[StripRealm(rawName)]
	if not name then return end

	if UnitGUID then
		local guid = UnitGUID(unit)
		if guid then
			nameToGUID[name] = guid
			guidToName[guid] = name
			local row = nameToRow[name]
			if row and Targets.TargetButton[row] then
				Targets.TargetButton[row].targetGUID = guid
			end
		end
	end

	local dead = (UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit)) or (UnitIsDead(unit) or UnitIsGhost(unit)) and true or false

	local curHp, maxHp = nil, nil
	if UnitXP then
		local ok1, val1 = pcall(UnitXP, "health", unit)
		local ok2, val2 = pcall(UnitXP, "maxhealth", unit)
		if ok1 and ok2 and type(val1) == "number" and type(val2) == "number" and val2 > 0 then
			curHp, maxHp = val1, val2
		end
	end
	if not curHp or not maxHp or maxHp <= 0 then
		curHp = UnitHealth(unit)
		maxHp = UnitHealthMax(unit)
	end

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
	if row then
		RenderHealthForRow(row, name)
	end
end

function Targets:EnableConfigMode(size)
	Targets.isConfig = true
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
		if e.classToken == "ROGUE" then
			if i % 2 == 1 then
				SetUnitStealth(e.name, true, "Stealth", "Interface\\Icons\\Ability_Stealth", 0)
			else
				SetUnitStealth(e.name, true, "Vanish", "Interface\\Icons\\Ability_Stealth", 0)
			end
		elseif e.classToken == "DRUID" and (i % 2 == 0) then
			SetUnitStealth(e.name, true, "Prowl", PROWL_TEXTURE, 0)
		elseif i == 3 then
			SetUnitStealth(e.name, true, "Invisibility", "Interface\\Icons\\Spell_Nature_Invisibilty", 0)
		end
	end
	for i = currentSize + 1, MAX_ENEMIES do
		local e = roster[i]
		e.name = nil
		e.classToken = nil
		e.guid = nil
	end
	RenderRoster()
end

function Targets:DisableConfigMode()
	Targets.isConfig = false
	prevEnemyCount = -1
	ClearAllStealth()
	ClearAllTrinkets()
	for i = 1, MAX_ENEMIES do
		local btn = Targets.TargetButton[i]
		if btn then
			btn.targetName = nil
			btn.targetGUID = nil
			if btn.StealthIcon then btn.StealthIcon:Hide() end
			if btn.StealthIconBg then btn.StealthIconBg:Hide() end
			if btn.FlagIcon then btn.FlagIcon:Hide() end
			btn:Hide()
		end
	end
	if activeBG then
		Targets:BattlefieldScoreUpdate(true)
	else
		Targets.MainFrame:Hide()
	end
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
	if o and o.pos then
		local frameName = "AutoBG_TargetsMainFrame"
		o.pos[frameName .. "_posX"] = nil
		o.pos[frameName .. "_posY"] = nil
		for _, sz in ipairs(BRACKETS) do
			o.pos[frameName .. sz .. "_posX"] = nil
			o.pos[frameName .. sz .. "_posY"] = nil
		end
	end
	Targets:Frame_SetupPosition("AutoBG_TargetsMainFrame")
end

function Targets:CopySettings(sourceSize, destinationSize)
	local o = AutoBG_Settings and AutoBG_Settings.Targets
	if not o then return end
	o.ButtonFontSize[destinationSize] = o.ButtonFontSize[sourceSize]
	o.ButtonScale[destinationSize] = o.ButtonScale[sourceSize]
	o.ButtonWidth[destinationSize] = o.ButtonWidth[sourceSize]
	o.ButtonHeight[destinationSize] = o.ButtonHeight[sourceSize]
	o.ButtonShowHealthBar[destinationSize] = o.ButtonShowHealthBar[sourceSize]
	o.ButtonShowHealthText[destinationSize] = o.ButtonShowHealthText[sourceSize]
	o.ButtonHideRealm[destinationSize] = o.ButtonHideRealm[sourceSize]
	o.ButtonSortBy[destinationSize] = o.ButtonSortBy[sourceSize]
	o.ShowStealthIcon[destinationSize] = o.ShowStealthIcon[sourceSize]
	o.DimStealthed[destinationSize] = o.DimStealthed[sourceSize]
	o.ShowStealthText[destinationSize] = o.ShowStealthText[sourceSize]
	o.ShowFlagCarrier[destinationSize] = o.ShowFlagCarrier[sourceSize]
	o.ShowTrinket[destinationSize] = o.ShowTrinket[sourceSize]
	o.IndependentPositioning[destinationSize] = o.IndependentPositioning[sourceSize]
end

Targets:RegisterEvent("PLAYER_LOGIN")
Targets:RegisterEvent("PLAYER_ENTERING_WORLD")
Targets:RegisterEvent("ZONE_CHANGED_NEW_AREA")
Targets:RegisterEvent("UPDATE_BATTLEFIELD_STATUS")
Targets:RegisterEvent("UPDATE_BATTLEFIELD_SCORE")
Targets:RegisterEvent("UNIT_HEALTH")
Targets:RegisterEvent("UNIT_HEALTH_FREQUENT")
Targets:RegisterEvent("UNIT_TARGET")
Targets:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
Targets:RegisterEvent("PLAYER_TARGET_CHANGED")
Targets:RegisterEvent("PLAYER_FOCUS_CHANGED")
Targets:RegisterEvent("NAME_PLATE_UNIT_ADDED")
Targets:RegisterEvent("UNIT_NAME_UPDATE")
Targets:RegisterEvent("UNIT_CASTEVENT")
Targets:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_BUFFS")
Targets:RegisterEvent("CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF")
Targets:RegisterEvent("CHAT_MSG_SPELL_AURA_GONE_OTHER")
Targets:RegisterEvent("CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE")
Targets:RegisterEvent("CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS")

local function Targets_OnEvent(arg1_param, arg2_param, arg3_param, arg4_param, arg5_param)
	local ev = (type(arg1_param) == "string" and arg1_param) or arg2_param or event
	local a1 = (type(arg1_param) == "string" and (arg2_param or arg1)) or arg3_param or arg1
	local a2 = (type(arg1_param) == "string" and (arg3_param or arg2)) or arg4_param or arg2
	local a3 = (type(arg1_param) == "string" and (arg4_param or arg3)) or arg5_param or arg3
	local a4 = (type(arg1_param) == "string" and arg5_param) or arg4

	if ev == "PLAYER_LOGIN" then
		Targets:EnsureOptions()
		Targets:CreateFrames()
		Targets:SetupButtonLayout(currentSize)

	elseif ev == "PLAYER_ENTERING_WORLD" or ev == "ZONE_CHANGED_NEW_AREA" or ev == "UPDATE_BATTLEFIELD_STATUS" then
		prevEnemyCount = -1
		Targets:OnCarrierChanged()
		RequestBattlefieldScoreData()
		Targets:BattlefieldScoreUpdate()

	elseif ev == "UPDATE_BATTLEFIELD_SCORE" then
		Targets:BattlefieldScoreUpdate()

	elseif ev == "UNIT_HEALTH" or ev == "UNIT_HEALTH_FREQUENT" then
		ObserveUnit(a1)

	elseif ev == "UNIT_TARGET" then
		if a1 then ObserveUnit(GetUnitTargetToken(a1)) end

	elseif ev == "UPDATE_MOUSEOVER_UNIT" then
		ObserveUnit("mouseover")

	elseif ev == "PLAYER_TARGET_CHANGED" then
		ObserveUnit("target")
		UpdateAllSelectionVisuals()

	elseif ev == "PLAYER_FOCUS_CHANGED" then
		ObserveUnit("focus")
		UpdateAllSelectionVisuals()

	elseif ev == "NAME_PLATE_UNIT_ADDED" or ev == "UNIT_NAME_UPDATE" then
		ObserveUnit(a1)

	elseif ev == "UNIT_CASTEVENT" then
		local casterGUID = a1
		local eventType = a3
		local spellId = a4
		if not casterGUID then return end

		local rawName = UnitName(casterGUID) or guidToName[casterGUID]
		if not rawName then return end
		local name = nameToRow[rawName] and rawName or shortNameToFull[StripRealm(rawName)]
		if not name then return end

		guidToName[casterGUID] = name
		nameToGUID[name] = casterGUID
		local row = nameToRow[name]
		if row and Targets.TargetButton[row] then
			Targets.TargetButton[row].targetGUID = casterGUID
		end

		if eventType == "CAST" then
			local trinketDur = TRINKET_SPELL_IDS[spellId]
			if trinketDur then
				TriggerTrinketCooldown(name, trinketDur)
			end

			local isStealth, sName, sTex, sDur = CheckIsStealthSpell(spellId)
			if isStealth then
				SetUnitStealth(name, true, sName, sTex, sDur)
			elseif stealthedState[name] then
				SetUnitStealth(name, false)
			end
		elseif eventType == "START" or eventType == "CHANNEL" or eventType == "MAINHAND" or eventType == "OFFHAND" then
			if stealthedState[name] then
				SetUnitStealth(name, false)
			end
		end

	elseif ev == "CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_BUFFS" then
		if a1 then
			local _, _, enemyName, buffName = string.find(a1, "^(.-) gains (.-)%.$")
			if enemyName and buffName and CheckIsStealthName(buffName) then
				local name = nameToRow[enemyName] and enemyName or shortNameToFull[enemyName]
				if name then
					local data = STEALTH_NAMES[buffName]
					SetUnitStealth(name, true, data.name, data.texture, data.duration)
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
				local name = nameToRow[enemyName] and enemyName or shortNameToFull[enemyName]
				if name then
					if string.find(spellName, "Insignia") or string.find(spellName, "PvP Trinket") then
						TriggerTrinketCooldown(name, 180)
					elseif CheckIsStealthName(spellName) then
						local data = STEALTH_NAMES[spellName]
						SetUnitStealth(name, true, data.name, data.texture, data.duration)
					end
				end
			end
		end

	elseif ev == "CHAT_MSG_SPELL_AURA_GONE_OTHER" then
		if a1 then
			local _, _, buffName, enemyName = string.find(a1, "^(.-) fades from (.-)%.$")
			if buffName and enemyName and CheckIsStealthName(buffName) then
				local name = nameToRow[enemyName] and enemyName or shortNameToFull[enemyName]
				if name and stealthedState[name] then
					SetUnitStealth(name, false)
				end
			end
		end

	elseif ev == "CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE" then
		if a1 then
			local _, _, enemyName = string.find(a1, "^(.-)'s ")
			if enemyName then
				local name = nameToRow[enemyName] and enemyName or shortNameToFull[enemyName]
				if name and stealthedState[name] then
					SetUnitStealth(name, false)
				end
			end
		end

	elseif ev == "CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS" then
		if a1 then
			local _, _, enemyName = string.find(a1, "^(.-) hits ")
			if not enemyName then _, _, enemyName = string.find(a1, "^(.-) crits ") end
			if not enemyName then _, _, enemyName = string.find(a1, "^(.-) misses ") end
			if not enemyName then _, _, enemyName = string.find(a1, "^(.-) attacks%.") end
			if enemyName then
				local name = nameToRow[enemyName] and enemyName or shortNameToFull[enemyName]
				if name and stealthedState[name] then
					SetUnitStealth(name, false)
				end
			end
		end
	end
end
Targets:SetScript("OnEvent", Targets_OnEvent)

-- Scoreboard poller
local function AutoScoreboardTicker()
	if activeBG and not Targets.isConfig then
		RequestBattlefieldScoreData()
	end
end

if C_Timer and C_Timer.NewTicker then
	C_Timer.NewTicker(3.0, AutoScoreboardTicker)
	C_Timer.NewTicker(0.5, UpdateAllTrinketTimers)
end
