-- -------------------------------------------------------------------------- --
-- AutoBG: Flag watch                                                         --
-- Warns when an enemy opens a flag in Arathi Basin or Alterac Valley.        --
-- -------------------------------------------------------------------------- --
-- An opening started from stealth never reaches your client as a cast: it
-- begins while the enemy is still invisible to you. So the watch uses what the
-- client does see: a visible enemy standing still at a flag their team does not
-- hold. Flag spots are learned in play, from the players who assault them, and
-- saved per map in AutoBG_Settings.FlagSpots.

local Targets = AutoBG_Targets
if not Targets or not Targets.GetEnemy then return end

local FlagWatch = CreateFrame("Frame", "AutoBG_FlagWatchFrame")
AutoBG_FlagWatch = FlagWatch

local TICK = 0.25
local NEAR_SQUARED = 10 * 10   -- a flag is opened from a few yards; spots are averages
local STILL_SQUARED = 0.5 * 0.5 -- moved under half a yard since the last check
local STILL_TICKS = 2           -- still for half a second
local SAME_SPOT_SQUARED = 15 * 15
local REPEAT = 15               -- seconds before the same enemy at the same flag warns again
local OWN_CAST_WINDOW = 1.5     -- an unnamed assault message this soon after your Opening was yours

local RAID_UNITS = {}
for i = 1, 40 do RAID_UNITS[i] = "raid" .. i end

local active, mapID, enemyFaction, ticker, playerGUID
local nodeHolder = {} -- node -> faction holding it or taking it
local watch = {}      -- enemy name -> { y, x, still, node, warnedNode, warnedAt }
local ownOpeningAt = 0
local openingBySpell = {} -- spell ID -> whether it is an Opening cast

local function Enabled()
	local o = AutoBG_Settings and AutoBG_Settings.Targets
	return not o or o.FlagWatch ~= false
end

local function Spots(create)
	if not AutoBG_Settings or not mapID then return nil end
	local all = AutoBG_Settings.FlagSpots
	if not all then
		if not create then return nil end
		all = {}
		AutoBG_Settings.FlagSpots = all
	end
	local spots = all[mapID]
	if not spots and create then spots = {}; all[mapID] = spots end
	return spots
end

local function ReadMap()
	local _, _, _, map = UnitPosition("player")
	mapID = map
end

-- Several samples average out where around the flag people stood. A sample far
-- from the saved spot cannot be the same flag and is ignored.
local function Learn(node, unit)
	local y, x, _, map = UnitPosition(unit)
	if not y or not map or map ~= mapID then return end
	local spots = Spots(true)
	local spot = spots and spots[node]
	if not spots then return end
	if not spot then
		spots[node] = { y = y, x = x, n = 1 }
		return
	end
	local dy, dx = y - spot.y, x - spot.x
	if dy * dy + dx * dx > SAME_SPOT_SQUARED then return end
	local n = math.min(spot.n or 1, 9)
	spot.y = (spot.y * n + y) / (n + 1)
	spot.x = (spot.x * n + x) / (n + 1)
	spot.n = n + 1
end

local function UnitForName(name)
	if name == UnitName("player") then return "player" end
	for i = 1, GetNumRaidMembers() do
		if UnitName(RAID_UNITS[i]) == name then return RAID_UNITS[i] end
	end
	return Targets.GetGUID(name)
end

local function ClearWarning(name)
	local w = watch[name]
	if w then w.node = nil end
	Targets.SetOpening(name, nil)
end

local function NearestSpot(spots, y, x)
	local best, bestSq
	for node, spot in pairs(spots) do
		local dy, dx = y - spot.y, x - spot.x
		local sq = dy * dy + dx * dx
		if sq <= NEAR_SQUARED and (not bestSq or sq < bestSq) then best, bestSq = node, sq end
	end
	return best
end

local function Warn(name, node, classToken, guid, now)
	local w = watch[name]
	if w.node == node then return end
	w.node = node
	Targets.SetOpening(name, node)
	if w.warnedNode == node and now - w.warnedAt < REPEAT then return end
	w.warnedNode, w.warnedAt = node, now
	if AutoBG_FlagAlert then AutoBG_FlagAlert:Show(name, classToken, guid, node) end
end

local function Tick()
	if not Enabled() then return end
	if not mapID then ReadMap() end
	local spots = Spots()
	if not spots or not next(spots) then return end
	local now = GetTime()
	for i = 1, Targets.EnemyCount() do
		local name, guid, classToken = Targets.GetEnemy(i)
		local w = name and watch[name]
		local y, x, map
		-- An enemy in stealth or out of sight has no position.
		if guid and not UnitIsDeadOrGhost(guid) then y, x, _, map = UnitPosition(guid) end
		if y and map == mapID then
			if not w then
				w = { still = 0, warnedAt = 0 }
				watch[name] = w
			end
			local node = NearestSpot(spots, y, x)
			local moved = true
			if w.y then
				local dy, dx = y - w.y, x - w.x
				moved = dy * dy + dx * dx >= STILL_SQUARED
			end
			w.y, w.x = y, x
			if node and not moved and nodeHolder[node] ~= enemyFaction then
				w.still = w.still + 1
				if w.still >= STILL_TICKS then Warn(name, node, classToken, guid, now) end
			else
				w.still = 0
				if w.node then ClearWarning(name) end
			end
		elseif w then
			w.y, w.x, w.still = nil, nil, 0
			if w.node then ClearWarning(name) end
		end
	end
end

-- Called by AutoBG_Timers for every Arathi Basin and Alterac Valley node message.
function FlagWatch:OnNodeMessage(node, msg, faction)
	if not active then return end
	local lower = string.lower(msg)
	local assault = string.find(lower, "claims") or string.find(lower, "assaulted") or string.find(lower, "claimed") or string.find(lower, "under attack")
	local held = string.find(lower, "taken") or string.find(lower, "defended") or string.find(lower, "captured") or string.find(lower, "destroyed")
	if not (assault or held) then return end
	if faction then nodeHolder[node] = faction end
	-- A player named in the message stood at the flag.
	local _, _, who = string.find(msg, "^(%S+) claims")
	if not who then _, _, who = string.find(msg, "^(%S+) has assaulted") end
	if not who then _, _, who = string.find(msg, "^(%S+) has defended") end
	local unit = who and UnitForName(who)
	-- Alterac Valley names nobody; your own Opening just before it is yours.
	if not unit and not who and GetTime() - ownOpeningAt <= OWN_CAST_WINDOW then unit = "player" end
	if unit then Learn(node, unit) end
	if who and watch[who] and watch[who].node then ClearWarning(who) end
end

local function Reset()
	for name, w in pairs(watch) do
		if w.node then Targets.SetOpening(name, nil) end
		watch[name] = nil
	end
	for node in pairs(nodeHolder) do nodeHolder[node] = nil end
	ownOpeningAt = 0
end

local function UpdateZone()
	local inInstance, instanceType = IsInInstance()
	local zone = string.lower(GetRealZoneText() or "")
	local want = inInstance and instanceType == "pvp"
		and (string.find(zone, "arathi") or string.find(zone, "alterac")) and true or false
	if want == active then return end
	active = want
	Reset()
	if active then
		ReadMap()
		playerGUID = UnitGUID("player")
		enemyFaction = UnitFactionGroup("player") == "Horde" and "Alliance" or "Horde"
		FlagWatch:RegisterEvent("UNIT_CASTEVENT")
		if not ticker then ticker = C_Timer.NewTicker(TICK, Tick) end
	else
		mapID = nil
		FlagWatch:UnregisterEvent("UNIT_CASTEVENT")
		if ticker then ticker:Cancel(); ticker = nil end
	end
end

FlagWatch:RegisterEvent("PLAYER_ENTERING_WORLD")
FlagWatch:RegisterEvent("ZONE_CHANGED_NEW_AREA")
FlagWatch:SetScript("OnEvent", function(p1, p2, p3, p4, p5, p6)
	local ev, a1, a3, a4
	if type(p1) == "string" then ev, a1, a3, a4 = p1, p2, p4, p5
	elseif type(p2) == "string" then ev, a1, a3, a4 = p2, p3, p5, p6
	else ev, a1, a3, a4 = event, arg1, arg3, arg4 end
	if ev == "UNIT_CASTEVENT" then
		-- SuperWoW: caster GUID, target GUID, event type, spell ID. Casts arrive
		-- for everyone nearby; name each spell ID once.
		if not a4 then return end
		local opening = openingBySpell[a4]
		if opening == nil then
			local spell = SpellInfo(a4)
			-- UNVERIFIED: test in game that flags are opened with a spell named "Opening".
			opening = spell and string.find(spell, "^Opening") and true or false
			openingBySpell[a4] = opening
			if opening and AutoBG_FlagAlert then AutoBG_FlagAlert:LearnOpening(a4) end
		end
		if opening and a1 == playerGUID and a3 == "CAST" then ownOpeningAt = GetTime() end
	else
		UpdateZone()
	end
end)
