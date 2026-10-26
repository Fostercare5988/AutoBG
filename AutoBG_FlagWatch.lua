-- -------------------------------------------------------------------------- --
-- AutoBG: Flag watch                                                         --
-- Warns when an enemy opens a flag in Arathi Basin or Alterac Valley.        --
-- -------------------------------------------------------------------------- --
-- An enemy in sight who starts an Opening cast warns at once (SuperWoW
-- UNIT_CASTEVENT START), with or without enemy frames. An opening started
-- from stealth never reaches your client as a cast: it begins while the enemy
-- is still invisible to you. What the client does see is the enemy appearing
-- out of nowhere at a flag their team does not hold and standing there, so
-- that warns too. Flag spots are learned in play, from the players who assault
-- them and from Opening casts, and saved per map in AutoBG_Settings.FlagSpots.

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
local LEARN_WINDOW = 1.5        -- an unnamed assault message this soon after one Opening came from it
local UNKNOWN_FLAG = "a flag"   -- an opening at a flag whose spot is not learned yet

local RAID_UNITS = {}
for i = 1, 40 do RAID_UNITS[i] = "raid" .. i end

local active, mapID, enemyFaction, ticker, playerGUID, cleaned
local nodeHolder = {} -- node -> faction holding it or taking it
local watch = {}      -- enemy name -> { y, x, still, fresh, dead, casting, node, warnedNode, warnedAt }
local openers = {}    -- caster GUID -> enemy name, while their Opening cast runs
local openingBySpell = {} -- spell ID -> whether it is an Opening cast
-- The last finished Opening cast seen, and how many finished in its window.
local castAt, castY, castX, castCount = 0, nil, nil, 0

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

-- Older versions could save one spot under two flags (a "was taken" message
-- right after your own Opening). Such spots cannot be trusted; drop them so
-- the flags are learned again.
local function DropMixedSpots()
	local all = AutoBG_Settings and AutoBG_Settings.FlagSpots
	if not all then return end
	for _, spots in pairs(all) do
		for node, spot in pairs(spots) do
			for other, o in pairs(spots) do
				local dy, dx = spot.y - o.y, spot.x - o.x
				if other ~= node and dy * dy + dx * dx <= SAME_SPOT_SQUARED then spot.mixed = true end
			end
		end
		for node, spot in pairs(spots) do
			if spot.mixed then spots[node] = nil end
		end
	end
end

local function ReadMap()
	local _, _, _, map = UnitPosition("player")
	mapID = map
end

-- Several samples average out where around the flag people stood. A sample far
-- from the saved spot, or on another flag's spot, cannot be this flag.
local function Learn(node, y, x)
	local spots = Spots(true)
	if not spots then return end
	for other, o in pairs(spots) do
		local dy, dx = y - o.y, x - o.x
		if other ~= node and dy * dy + dx * dx <= SAME_SPOT_SQUARED then return end
	end
	local spot = spots[node]
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
	if w then w.node, w.casting = nil, nil end
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

local function WatchEntry(name)
	local w = watch[name]
	if not w then
		w = { still = 0, warnedAt = 0 }
		watch[name] = w
	end
	return w
end

local function Warn(name, node, classToken, guid, now)
	local w = WatchEntry(name)
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
		local dead = guid and UnitIsDeadOrGhost(guid)
		-- An enemy in stealth or out of sight has no position.
		if guid and not dead then y, x, _, map = UnitPosition(guid) end
		if dead then
			w = WatchEntry(name)
			-- A ghost sends no moves, so after the spirit healer the client keeps
			-- the spot where they died until they walk. Wait for a real move.
			w.dead, w.y, w.x, w.still = true, nil, nil, 0
			if w.node then ClearWarning(name) end
		elseif y and map == mapID then
			w = WatchEntry(name)
			local node = NearestSpot(spots, y, x)
			local moved = true
			if w.y then
				local dy, dx = y - w.y, x - w.x
				moved = dy * dy + dx * dx >= STILL_SQUARED
				if moved then w.dead, w.fresh = nil, nil end
			else
				-- Just came into sight: out of stealth, unless they were dead.
				w.fresh = not w.dead
			end
			w.y, w.x = y, x
			if node and not moved and w.fresh and nodeHolder[node] ~= enemyFaction then
				w.still = w.still + 1
				if w.still >= STILL_TICKS then Warn(name, node, classToken, guid, now) end
			else
				w.still = 0
				-- A running Opening cast keeps its warning until it ends.
				if w.node and not w.casting then ClearWarning(name) end
			end
		elseif w then
			-- Gone from sight: when they come back the server sends where they are.
			w.y, w.x, w.still, w.dead = nil, nil, 0, nil
			if w.node then ClearWarning(name) end
		end
	end
end

-- An enemy in sight started opening a flag: warn now, naming the flag when its
-- spot is known.
local function OnOpeningStart(guid)
	if not Enabled() or not Targets.EnemyByGUID then return end
	local name, classToken = Targets.EnemyByGUID(guid)
	if not name then return end
	if not mapID then ReadMap() end
	local y, x, _, map = UnitPosition(guid)
	local spots = Spots()
	local node = y and map == mapID and spots and NearestSpot(spots, y, x)
	openers[guid] = name
	Warn(name, node or UNKNOWN_FLAG, classToken, guid, GetTime())
	watch[name].casting = true
end

-- A finished Opening, anyone's, is where the next assault message's flag stands.
local function OnOpeningDone(guid)
	local now = GetTime()
	local y, x, _, map = UnitPosition(guid == playerGUID and "player" or guid)
	if y and map == mapID then
		if now - castAt > LEARN_WINDOW then castCount = 0 end
		castAt, castY, castX, castCount = now, y, x, castCount + 1
	end
end

-- Called by AutoBG_Timers for every Arathi Basin and Alterac Valley node message.
function FlagWatch:OnNodeMessage(node, msg, faction)
	if not active then return end
	local lower = string.lower(msg)
	local assault = string.find(lower, "claims") or string.find(lower, "assaulted") or string.find(lower, "claimed") or string.find(lower, "under attack")
	local defended = string.find(lower, "defended")
	local held = defended or string.find(lower, "taken") or string.find(lower, "captured") or string.find(lower, "destroyed")
	if not (assault or held) then return end
	if faction then nodeHolder[node] = faction end
	-- A player named in the message stood at the flag.
	local _, _, who = string.find(msg, "^(%S+) claims")
	if not who then _, _, who = string.find(msg, "^(%S+) has assaulted") end
	if not who then _, _, who = string.find(msg, "^(%S+) has defended") end
	if who and watch[who] and watch[who].node then ClearWarning(who) end
	-- "Taken", "captured" and "destroyed" report a holder: nobody need be at
	-- the flag, so they teach no spot.
	if not (assault or defended) then return end
	local unit = who and UnitForName(who)
	if unit then
		local y, x, _, map = UnitPosition(unit)
		if y and map == mapID then Learn(node, y, x) end
	elseif not who and castCount == 1 and GetTime() - castAt <= LEARN_WINDOW then
		-- Alterac Valley names nobody; a lone Opening just before it was this flag.
		Learn(node, castY, castX)
		castCount = 0
	end
end

local function Reset()
	for name, w in pairs(watch) do
		if w.node then Targets.SetOpening(name, nil) end
		watch[name] = nil
	end
	for node in pairs(nodeHolder) do nodeHolder[node] = nil end
	for guid in pairs(openers) do openers[guid] = nil end
	castAt, castCount = 0, 0
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
		if not cleaned then DropMixedSpots(); cleaned = true end
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
		if not a1 then return end
		local name = openers[a1]
		if name and (a3 == "CAST" or a3 == "FAIL") then
			openers[a1] = nil
			ClearWarning(name)
		end
		if not a4 then return end
		local opening = openingBySpell[a4]
		if opening == nil then
			local spell = SpellInfo(a4)
			-- UNVERIFIED: test in game that flags are opened with a spell named "Opening".
			opening = spell and string.find(spell, "^Opening") and true or false
			openingBySpell[a4] = opening
			if opening and AutoBG_FlagAlert then AutoBG_FlagAlert:LearnOpening(a4) end
		end
		if not opening then return end
		if a3 == "START" then OnOpeningStart(a1)
		elseif a3 == "CAST" then OnOpeningDone(a1) end
	else
		UpdateZone()
	end
end)
