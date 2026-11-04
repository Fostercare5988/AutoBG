-- -------------------------------------------------------------------------- --
-- AutoBG: Arena enemy pets                                                    --
-- A small list under the arena enemy frames: each enemy pet or minion seen,   --
-- its owner and its health. Arenas only, where every bit of knowledge about   --
-- the other team is worth a few rows; battlegrounds stay quiet.               --
-- -------------------------------------------------------------------------- --

-- Needs ClassicAPI and SuperWoW loaded; AutoBG.lua says what is missing.
if type(CLASSIC_API_VERSION) ~= "number" or not SUPERWOW_VERSION then
	return
end

local Pets = {}
AutoBG_ArenaPets = Pets

local MAX_PETS = 6
local ROW_HEIGHT = 16
local FONT = "Fonts\\ARIALN.TTF"
local BAR_TEXTURE = [[Interface\AddOns\AutoBG\Textures\barTexture.tga]]

-- entries: one per owner (a new pet replaces the owner's old one), or per pet when
-- the owner is unknown. byGuid finds an entry from the pet's GUID.
local entries, byGuid, notPet = {}, {}, {}
local count = 0 -- entries held; the list keeps its own count, never # or table.remove after a removal
local frame, rows
local active = false
local renderTimer

local function ReadHealth(unit)
	local hp, maxHp = GetUnitField(unit, "health"), GetUnitField(unit, "maxHealth")
	if hp and maxHp and maxHp > 0 then return hp, maxHp end
	return UnitHealth(unit), UnitHealthMax(unit)
end

local function Enabled()
	local o = AutoBG_ArenaOptions()
	return not (o and o.Pets == false)
end

local function CreateRows()
	frame = CreateFrame("Frame", "AutoBG_ArenaPetsFrame", AutoBG_Targets.MainFrame)
	frame:SetPoint("TOPLEFT", AutoBG_Targets.MainFrame, "BOTTOMLEFT", 0, -4)
	frame:SetHeight(ROW_HEIGHT)
	rows = {}
	for i = 1, MAX_PETS do
		local row = CreateFrame("Button", "AutoBG_ArenaPet" .. i, frame)
		rows[i] = row
		row:SetHeight(ROW_HEIGHT)
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		if i == 1 then row:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
		else row:SetPoint("TOPLEFT", rows[i - 1], "BOTTOMLEFT", 0, 0) end
		row.Back = row:CreateTexture(nil, "BACKGROUND")
		row.Back:SetPoint("TOPLEFT", row, "TOPLEFT", 1, -1)
		row.Back:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -1, 1)
		row.Back:SetTexture(0.12, 0.12, 0.12, 0.9)
		row.Bar = row:CreateTexture(nil, "ARTWORK")
		row.Bar:SetPoint("TOPLEFT", row, "TOPLEFT", 1, -1)
		row.Bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 1, 1)
		row.Bar:SetTexture(BAR_TEXTURE)
		row.Name = row:CreateFontString(nil, "OVERLAY")
		row.Name:SetFont(FONT, 10, "OUTLINE")
		row.Name:SetPoint("LEFT", row, "LEFT", 5, 0)
		row.Name:SetJustifyH("LEFT")
		row.Health = row:CreateFontString(nil, "OVERLAY")
		row.Health:SetFont(FONT, 10, "OUTLINE")
		row.Health:SetPoint("RIGHT", row, "RIGHT", -4, 0)
		row:Hide()
	end
end

local function Render()
	renderTimer = nil
	if not rows and count == 0 then return end
	if not rows then CreateRows() end
	local main = AutoBG_Targets.MainFrame
	local width = main:GetWidth()
	local shown = 0
	for i = 1, MAX_PETS do
		local e, row = entries[i], rows[i]
		if e and active and Enabled() then
			shown = shown + 1
			row:SetWidth(width)
			row:Show()
			local pct = e.dead and 0 or e.pct
			row.Bar:SetWidth(math.max(1, (width - 2) * pct / 100))
			if e.dead then row.Bar:SetVertexColor(0.4, 0.4, 0.4, 1)
			elseif e.far then row.Bar:SetVertexColor(0.55, 0.35, 0.2, 1)
			else row.Bar:SetVertexColor(0.85, 0.5, 0.15, 1) end
			row.Name:SetText(e.name .. (e.owner and (" |cffaaaaaa" .. e.owner .. "|r") or ""))
			row.Health:SetText(e.dead and "dead" or (pct .. "%"))
			AutoBG_Targets.BindUnit(row, e.guid)
		else
			row:Hide()
		end
	end
	frame:SetWidth(width)
	frame:SetHeight(math.max(1, shown * ROW_HEIGHT))
	if shown > 0 then frame:Show() else frame:Hide() end
end

local function RequestRender()
	if renderTimer then return end
	renderTimer = C_Timer.NewTimer(0, Render)
end

local function Remove(e)
	byGuid[e.guid] = nil
	-- The last entry fills the gap.
	for i = 1, count do
		if entries[i] == e then entries[i] = entries[count]; entries[count] = nil; count = count - 1; return end
	end
end

-- By owner, a plain insertion sort over the entries held.
local function Sort()
	for i = 2, count do
		local e, j = entries[i], i - 1
		while j >= 1 and (entries[j].owner or "") > (e.owner or "") do
			entries[j + 1] = entries[j]
			j = j - 1
		end
		entries[j + 1] = e
	end
end

local function Known(name)
	return name and name ~= UNKNOWNOBJECT and name ~= UKNOWNBEING
end

-- Keep an entry true to the unit: a pet can be renamed (or still be uncached when
-- first seen), its owner can resolve late, and the owner, a player seen only through
-- the pet, is handed to the enemy frames until they list that player.
local function Identify(e)
	local changed = false
	local name = UnitName(e.guid)
	if Known(name) and name ~= e.name then e.name, changed = name, true end
	if not e.ownerGuid then
		local g = UnitOwnerGUID(e.guid)
		if g then
			for i = 1, count do
				if entries[i] ~= e and entries[i].ownerGuid == g then Remove(entries[i]); break end
			end
			e.ownerGuid, changed = g, true
		end
	end
	if e.ownerGuid then
		if not e.ownerSeen and string.sub(e.ownerGuid, 1, 6) == "0x0000" then
			e.ownerSeen = AutoBG_Targets.ObserveGUID(e.ownerGuid)
		end
		local owner = UnitName(e.ownerGuid)
		if Known(owner) then
			owner = AutoBG_Targets.StripRealm(owner)
			if owner ~= e.owner then e.owner, changed = owner, true end
		end
	end
	if changed then Sort(); RequestRender() end
end

-- Learn or refresh one GUID. Players and everything already rejected are skipped
-- cheaply; a pet is any attackable minion that is not a totem.
local function Observe(guid)
	if not active or type(guid) ~= "string" or notPet[guid] then return end
	local e = byGuid[guid]
	if not e then
		if string.sub(guid, 1, 6) == "0x0000" then notPet[guid] = true; return end
		if not UnitExists(guid) then return end
		if not UnitIsMinion(guid) or not UnitCanAttack("player", guid) or UnitCreatureType(guid) == "Totem" then
			notPet[guid] = true
			return
		end
		-- A new pet replaces its owner's old one.
		local ownerGuid = UnitOwnerGUID(guid)
		if ownerGuid then
			for i = 1, count do
				if entries[i].ownerGuid == ownerGuid then Remove(entries[i]); break end
			end
		end
		if count >= MAX_PETS then return end
		local name = UnitName(guid)
		e = { guid = guid, name = Known(name) and name or "Pet", ownerGuid = ownerGuid, pct = 100 }
		byGuid[guid] = e
		count = count + 1
		entries[count] = e
		Identify(e)
	elseif not e.ownerSeen or not e.owner or e.name == "Pet" then
		Identify(e)
	end
	local hp, maxHp = ReadHealth(guid)
	local pct = (maxHp and maxHp > 0 and hp) and math.floor(hp / maxHp * 100 + 0.5) or e.pct
	local dead = (hp and hp <= 0) and true or false
	if e.pct ~= pct or e.dead ~= dead or e.far then
		e.pct, e.dead, e.far = pct, dead, false
		RequestRender()
	end
	if not e.rendered then e.rendered = true; RequestRender() end
end

-- Once a second: a pet seen again is refreshed (a rename shows), one out of sight
-- is dimmed with its last health kept. An entry Observe removed is skipped over.
local function Refresh()
	local i = 1
	while i <= count do
		local e = entries[i]
		if UnitExists(e.guid) then
			Identify(e)
			Observe(e.guid)
		elseif not e.far and not e.dead then
			e.far = true
			RequestRender()
		end
		if entries[i] == e then i = i + 1 end
	end
end

local EVENTS = { "UNIT_HEALTH_GUID", "UNIT_CASTEVENT", "UNIT_DIED", "NAME_PLATE_UNIT_ADDED",
	"PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT" }
local listener = CreateFrame("Frame", "AutoBG_ArenaPetsListener")
local ticker
listener:SetScript("OnEvent", function()
	local ev = event
	if ev == "UNIT_HEALTH_GUID" or ev == "UNIT_DIED" then Observe(arg1)
	elseif ev == "UNIT_CASTEVENT" then Observe(arg1)
	elseif ev == "NAME_PLATE_UNIT_ADDED" then Observe(arg1 and UnitGUID(arg1))
	elseif ev == "PLAYER_TARGET_CHANGED" then Observe(UnitGUID("target"))
	elseif ev == "UPDATE_MOUSEOVER_UNIT" then Observe(UnitGUID("mouseover"))
	end
end)

-- Targets tells this module when an arena starts and ends.
function Pets.SetActive(on)
	on = on and true or false
	if on == active then return end
	active = on
	for i = 1, #EVENTS do
		if on then listener:RegisterEvent(EVENTS[i]) else listener:UnregisterEvent(EVENTS[i]) end
	end
	if on then
		if not ticker then ticker = C_Timer.NewTicker(1, Refresh) end
	else
		if ticker then ticker:Cancel(); ticker = nil end
		table.wipe(entries); table.wipe(byGuid); table.wipe(notPet)
		count = 0
		RequestRender()
	end
end

-- Settings changed (the switch in the options).
function Pets.Refresh() RequestRender() end

-- The once-a-second pass, and the entries held, for tests.
Pets.Tick = Refresh
function Pets.Count() return count end
