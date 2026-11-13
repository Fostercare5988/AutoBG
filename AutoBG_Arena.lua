-- -------------------------------------------------------------------------- --
-- AutoBG: Arena extras                                                        --
-- On each enemy row: a power bar (mana, rage or energy) and a strip of icons  --
-- for a few key abilities (shield, protection, freedom, stun). The drinking   --
-- alert and the low-health and death callouts to your team. Arenas only;      --
-- every part has a switch in the Arena tab. Shadow Sight lives with the       --
-- timers.                                                                     --
-- -------------------------------------------------------------------------- --

-- Needs ClassicAPI and SuperWoW loaded; AutoBG.lua says what is missing.
if type(CLASSIC_API_VERSION) ~= "number" or not SUPERWOW_VERSION then
	return
end

local Arena = {}
AutoBG_Arena = Arena

local MAX_ROWS = 5            -- the arena bracket
local SLOTS = 6               -- icons beside a row
-- The few abilities worth an icon, by name (the client names any spell ID; no IDs are
-- taken from other servers). UNVERIFIED in game: that OctoWoW names them exactly so.
local KEY_ORDER = { "Divine Shield", "Blessing of Protection", "Blessing of Freedom", "Hammer of Justice" }
local KEY = {}
for i = 1, #KEY_ORDER do KEY[KEY_ORDER[i]] = true end
-- A use stays on the row this long (UNVERIFIED: the real cooldowns are not known yet, so
-- the icon counts up from the use; it never claims "ready").
local USED_SHOW = 300
local SETTLE = 1.5            -- buffs announced this soon after first sight are the ones already on
local DRINK_QUIET = 10
local LOW_HEALTH, REARM_HEALTH = 25, 50
local ICON_DEFAULT = 18
local FONT = "Fonts\\ARIALN.TTF"
local BUFF_COLOR, ABILITY_COLOR = { 0.95, 0.78, 0.2 }, { 0.45, 0.45, 0.45 }
-- UnitPowerType: 0 mana, 1 rage, 2 focus, 3 energy.
local POWER_COLORS = { [0] = { 0.2, 0.45, 1 }, [1] = { 0.9, 0.2, 0.2 }, [2] = { 0.85, 0.5, 0.2 }, [3] = { 1, 0.9, 0.2 } }

local active = false
local units = {}              -- by GUID: { seen, used = { [name] = {id, t} }, active = { [name] = {id, t} } }
local nameCache, iconCache = {}, {}
local drinkAlerted, lowSent, deadSent = {}, {}, {}
local decorated = false
local ticker
local anchorKey, iconSize = {}, {}

local function Options() return AutoBG_ArenaOptions() or {} end

local function Unit(guid)
	local u = units[guid]
	if not u then
		u = { seen = GetTime(), used = {}, active = {} }
		units[guid] = u
	end
	return u
end

local function SpellName(id)
	local n = nameCache[id]
	if n == nil then
		n = GetSpellInfo(id) or false
		nameCache[id] = n
	end
	return n
end

local function SpellIcon(id)
	local t = iconCache[id]
	if t == nil then
		local _, _, icon = GetSpellInfo(id)
		t = icon or false
		iconCache[id] = t
	end
	return t
end

-- -------------------------------------------------------------------------- --
-- Row decoration: power bar and icon strip                                    --
-- -------------------------------------------------------------------------- --
local function Decorate()
	if decorated or not AutoBG_Targets or not AutoBG_Targets.TargetButton then return end
	decorated = true
	for i = 1, MAX_ROWS do
		local btn = AutoBG_Targets.TargetButton[i]
		if btn then
			btn.PowerBack = btn:CreateTexture(nil, "ARTWORK")
			btn.PowerBack:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 1, 1)
			btn.PowerBack:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
			btn.PowerBack:SetHeight(3)
			btn.PowerBack:SetTexture(0, 0, 0, 0.7)
			btn.PowerBar = btn:CreateTexture(nil, "OVERLAY")
			btn.PowerBar:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 1, 1)
			btn.PowerBar:SetHeight(3)
			btn.PowerBar:SetTexture(1, 1, 1, 1)
			btn.PowerBack:Hide()
			btn.PowerBar:Hide()
			local strip = CreateFrame("Frame", nil, btn)
			btn.Strip = strip
			strip:SetHeight(ICON_DEFAULT)
			strip:SetWidth(SLOTS * (ICON_DEFAULT + 1))
			strip.slots = {}
			for s = 1, SLOTS do
				local slot = CreateFrame("Frame", nil, strip)
				strip.slots[s] = slot
				slot:SetWidth(ICON_DEFAULT)
				slot:SetHeight(ICON_DEFAULT)
				if s == 1 then slot:SetPoint("LEFT", strip, "LEFT", 0, 0)
				else slot:SetPoint("LEFT", strip.slots[s - 1], "RIGHT", 1, 0) end
				slot.Border = slot:CreateTexture(nil, "BACKGROUND")
				slot.Border:SetAllPoints(slot)
				slot.Icon = slot:CreateTexture(nil, "ARTWORK")
				slot.Icon:SetPoint("TOPLEFT", slot, "TOPLEFT", 1, -1)
				slot.Icon:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -1, 1)
				slot.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
				slot.Age = slot:CreateFontString(nil, "OVERLAY")
				slot.Age:SetFont(FONT, 9, "OUTLINE")
				slot.Age:SetPoint("BOTTOM", slot, "BOTTOM", 0, 1)
				slot:Hide()
			end
			strip:Hide()
		end
	end
end

-- Icons are as tall as the row (less its edge), so they grow with the row's size setting.
local function SizeStrip(i, btn)
	local size = math.max(14, math.floor(btn:GetHeight() or 20) - 2)
	if iconSize[i] == size then return end
	iconSize[i] = size
	local strip = btn.Strip
	strip:SetHeight(size)
	strip:SetWidth(SLOTS * (size + 1))
	local font = math.max(9, math.floor(size * 0.5))
	for s = 1, SLOTS do
		local slot = strip.slots[s]
		slot:SetWidth(size)
		slot:SetHeight(size)
		slot.Age:SetFont(FONT, font, "OUTLINE")
	end
end

-- The strip sits on the right of the row, past the cast bar or trinket if they are
-- on that side; repositioned only when the layout changes.
local function PlaceStrip(i, btn)
	local o = AutoBG_Settings and AutoBG_Settings.Targets
	local castRight = o and o.CastPos == "RIGHT"
	local trinketRight = o and o.TrinketPos == "RIGHT" and o.ShowTrinket and o.ShowTrinket[5]
	local anchor = (castRight and o.ShowCastBars ~= false and btn.Cast) or (trinketRight and btn.Trinket) or btn
	SizeStrip(i, btn)
	if anchorKey[i] == anchor then return end
	anchorKey[i] = anchor
	btn.Strip:ClearAllPoints()
	btn.Strip:SetPoint("LEFT", anchor, "RIGHT", 3, 0)
end

local function AgeText(age)
	if age >= 60 then return math.floor(age / 60) .. "m" end
	return tostring(math.floor(age))
end

local function ShowSlot(slot, id, age, color)
	local icon = SpellIcon(id)
	if not icon then slot:Hide(); return false end
	slot.Icon:SetTexture(icon)
	slot.Border:SetTexture(color[1], color[2], color[3], 1)
	slot.Age:SetText(AgeText(age))
	slot:Show()
	return true
end

-- Per key ability, gold while it is on the unit (the seconds left once that length has
-- been measured in play, else the seconds since it began), grey after it was used (the
-- seconds since).
local function FillStrip(btn, u, o, now)
	local strip = btn.Strip
	local shown = 0
	local durations = o.Durations
	for i = 1, #KEY_ORDER do
		if shown >= SLOTS then break end
		local name = KEY_ORDER[i]
		local on, used = u.active[name], u.used[name]
		local ok = false
		if on then
			local length = durations and durations[on.id]
			ok = ShowSlot(strip.slots[shown + 1], on.id, length and math.max(0, length - (now - on.t)) or (now - on.t), BUFF_COLOR)
		elseif used and now - used.t <= USED_SHOW then
			ok = ShowSlot(strip.slots[shown + 1], used.id, now - used.t, ABILITY_COLOR)
		end
		if ok then shown = shown + 1 end
	end
	for s = shown + 1, SLOTS do strip.slots[s]:Hide() end
	if shown > 0 then strip:Show() else strip:Hide() end
end

local function UpdatePower(btn, guid, o)
	if not o.Mana or not UnitExists(guid) then
		if not o.Mana then btn.PowerBack:Hide(); btn.PowerBar:Hide() end
		return
	end
	local cur, max = UnitMana(guid), UnitManaMax(guid)
	if not max or max <= 0 then btn.PowerBack:Hide(); btn.PowerBar:Hide(); return end
	local c = POWER_COLORS[UnitPowerType(guid) or 0] or POWER_COLORS[0]
	btn.PowerBar:SetTexture(c[1], c[2], c[3], 1)
	btn.PowerBar:SetWidth(math.max(1, (btn:GetWidth() - 2) * math.min(1, (cur or 0) / max)))
	btn.PowerBack:Show()
	btn.PowerBar:Show()
end

local function Tick()
	if not active then return end
	Decorate()
	local o = Options()
	local now = GetTime()
	for i = 1, MAX_ROWS do
		local btn = AutoBG_Targets.TargetButton and AutoBG_Targets.TargetButton[i]
		if btn and btn.Strip then
			local name, guid = AutoBG_Targets.GetEnemy(i)
			if name and guid then
				UpdatePower(btn, guid, o)
				local u = units[guid]
				if u and o.Abilities then
					PlaceStrip(i, btn)
					FillStrip(btn, u, o, now)
				else
					btn.Strip:Hide()
				end
			else
				btn.PowerBack:Hide(); btn.PowerBar:Hide(); btn.Strip:Hide()
			end
		end
	end
end

-- -------------------------------------------------------------------------- --
-- What the enemy does                                                         --
-- -------------------------------------------------------------------------- --
local function EnemyName(guid)
	return guid and AutoBG_Targets.EnemyByGUID(guid)
end

local function OnCast(guid, kind, spellId)
	if kind ~= "CAST" or not spellId or not Options().Abilities then return end
	local name = SpellName(spellId)
	if not (name and KEY[name]) or not EnemyName(guid) then return end
	Unit(guid).used[name] = { id = spellId, t = GetTime() }
end

local function Chat(text)
	local channel = (GetNumRaidMembers() > 0 and "RAID") or (GetNumPartyMembers() > 0 and "PARTY")
	if channel then SendChatMessage(text, channel) end
end

local function OnBuff(guid, spellId, state, added)
	if not spellId then return end
	local o = Options()
	-- Shadow Sight: anyone, either side (see AutoBG_Timers).
	if added and state == 0 and o.ShadowSight and SpellName(spellId) == "Shadow Sight" and AutoBG_Timers_ShadowSight then
		local mine = guid == UnitGUID("player")
		AutoBG_Timers_ShadowSight(mine and "You" or (UnitName(guid) or "Someone"), not mine and UnitCanAttack("player", guid))
	end
	local key = o.Abilities and SpellName(spellId)
	if not (key and KEY[key]) then key = nil end
	if not (key or o.Drinking) then return end
	local name = EnemyName(guid)
	if not name then return end
	local u, now = Unit(guid), GetTime()
	if not added then
		-- The longest a key buff was seen to last is its length (an early cancel is
		-- shorter), kept per spell ID: the ranks of a blessing last differently.
		local on = key and u.active[key]
		if on then
			local lengths = o.Durations
			if not lengths then lengths = {}; o.Durations = lengths end
			if now - on.t > (lengths[on.id] or 0) then lengths[on.id] = now - on.t end
			u.active[key] = nil
		end
		return
	end
	if state ~= 0 or now - u.seen < SETTLE then return end
	if key then u.active[key] = { id = spellId, t = now } end
	if o.Drinking then
		local spell = SpellName(spellId)
		if spell and string.find(string.lower(spell), "drink", 1, true) and (not drinkAlerted[guid] or now - drinkAlerted[guid] > DRINK_QUIET) then
			drinkAlerted[guid] = now
			UIErrorsFrame:AddMessage(AutoBG_Targets.StripRealm(name) .. " is drinking!", 0.4, 0.8, 1, 1, 3)
			PlaySound("RaidWarning")
		end
	end
end

local function OnHealth(guid)
	if not Options().Callouts then return end
	local name = EnemyName(guid)
	if not name then return end
	local hp, maxHp = GetUnitField(guid, "health"), GetUnitField(guid, "maxHealth")
	if not hp or not maxHp or maxHp <= 0 or hp <= 0 then return end
	local pct = hp / maxHp * 100
	if pct >= REARM_HEALTH then lowSent[guid] = nil; deadSent[guid] = nil
	elseif pct <= LOW_HEALTH and not lowSent[guid] then
		lowSent[guid] = true
		Chat(AutoBG_Targets.StripRealm(name) .. " is LOW (" .. math.floor(pct + 0.5) .. "%)")
	end
end

local function OnDied(guid)
	if not Options().Callouts or deadSent[guid] then return end
	local name = EnemyName(guid)
	if not name then return end
	deadSent[guid] = true
	Chat(AutoBG_Targets.StripRealm(name) .. " is DEAD")
end

local EVENTS = { "UNIT_CASTEVENT", "BUFF_ADDED_OTHER", "BUFF_REMOVED_OTHER", "BUFF_ADDED_SELF",
	"UNIT_HEALTH_GUID", "UNIT_DIED" }
local listener = CreateFrame("Frame", "AutoBG_ArenaListener")
listener:SetScript("OnEvent", function()
	local ev = event
	if ev == "UNIT_CASTEVENT" then OnCast(arg1, arg3, arg4)
	elseif ev == "BUFF_ADDED_OTHER" or ev == "BUFF_ADDED_SELF" then OnBuff(arg1, arg3, arg7, true)
	elseif ev == "BUFF_REMOVED_OTHER" then OnBuff(arg1, arg3, arg7, false)
	elseif ev == "UNIT_HEALTH_GUID" then OnHealth(arg1)
	elseif ev == "UNIT_DIED" then OnDied(arg1)
	end
end)

-- Targets tells this module when an arena starts and ends.
function Arena.SetActive(on)
	on = on and true or false
	if on == active then return end
	active = on
	for i = 1, #EVENTS do
		if on then listener:RegisterEvent(EVENTS[i]) else listener:UnregisterEvent(EVENTS[i]) end
	end
	if on then
		if not ticker then ticker = C_Timer.NewTicker(0.5, Tick) end
	else
		if ticker then ticker:Cancel(); ticker = nil end
		table.wipe(units); table.wipe(drinkAlerted); table.wipe(lowSent); table.wipe(deadSent)
		table.wipe(anchorKey); table.wipe(iconSize)
		if decorated then
			for i = 1, MAX_ROWS do
				local btn = AutoBG_Targets.TargetButton[i]
				if btn and btn.Strip then btn.PowerBack:Hide(); btn.PowerBar:Hide(); btn.Strip:Hide() end
			end
		end
	end
end

-- A switch changed in the Arena tab.
function Arena.Refresh()
	table.wipe(anchorKey); table.wipe(iconSize)
	Tick()
end

function Arena.Tick() Tick() end
