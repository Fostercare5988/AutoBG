-- -------------------------------------------------------------------------- --
-- AutoBG: Flag watch                                                         --
-- Warns when an enemy opens a flag in Arathi Basin (only there).            --
-- -------------------------------------------------------------------------- --
-- An enemy in sight who starts an Opening cast warns at once (NamPower
-- SPELL_START_OTHER), with or without enemy frames. An opening started
-- from stealth never reaches your client as a cast: it begins while the enemy
-- is still invisible to you. What the client does see is the enemy appearing
-- out of nowhere at a flag their team does not hold and standing there, so
-- that warns too. Flag spots are learned in play from the players who assault
-- them (every Arathi Basin assault names one) and saved per map in
-- AutoBG_Settings.FlagSpots.

local Targets = AutoBG_Targets
if not Targets or not Targets.GetEnemy then return end

local FlagWatch = CreateFrame("Frame", "AutoBG_FlagWatchFrame")
AutoBG_FlagWatch = FlagWatch

local TICK = 0.25
local CAST_EVENTS = { "SPELL_START_OTHER", "SPELL_GO_OTHER", "SPELL_FAILED_OTHER" }
local NEAR_SQUARED = 10 * 10   -- a flag is opened from a few yards; spots are averages
local STILL_SQUARED = 0.5 * 0.5 -- moved under half a yard since the last check
local STILL_TICKS = 2           -- still for half a second
local SAME_SPOT_SQUARED = 15 * 15
local REPEAT = 15               -- seconds before the same enemy at the same flag warns again
local UNKNOWN_FLAG = "a flag"   -- an opening at a flag whose spot is not learned yet

local active, mapID, enemyFaction, ticker, cleaned
local nodeHolder = {} -- node -> faction holding it or taking it
local watch = {}      -- enemy name -> { y, x, still, fresh, dead, casting, node, warnedNode, warnedAt }
local openers = {}    -- caster GUID -> enemy name, while their Opening cast runs
local openingBySpell = {} -- spell ID -> whether it is an Opening cast
local AB_BASES = { ["Gold Mine"] = true, ["Lumber Mill"] = true, ["Blacksmith"] = true, ["Farm"] = true, ["Stables"] = true }

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

-- Older versions also watched Alterac Valley and learned its flags from the
-- Opening casts before an unnamed message; those spots are dropped. (That
-- learning also caused the spots saved on top of each other, which were
-- cleared before.)
local function DropOtherSpots()
	local all = AutoBG_Settings and AutoBG_Settings.FlagSpots
	if not all then return end
	for map, spots in pairs(all) do
		for node in pairs(spots) do
			if not AB_BASES[node] then spots[node] = nil end
		end
		if not next(spots) then all[map] = nil end
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

-- ClassicAPI looks through the group and every unit around you.
local function UnitForName(name)
	if name == UnitName("player") then return "player" end
	return UnitTokenFromName(name, true) or Targets.GetGUID(name)
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

-- Called by AutoBG_Timers for every Arathi Basin base message.
function FlagWatch:OnNodeMessage(node, msg, faction)
	if not active then return end
	local lower = string.lower(msg)
	local assault = string.find(lower, "claims") or string.find(lower, "assaulted") or string.find(lower, "claimed")
	local defended = string.find(lower, "defended")
	local held = defended or string.find(lower, "taken") or string.find(lower, "captured")
	if not (assault or held) then return end
	if faction then nodeHolder[node] = faction end
	-- A player named in the message stood at the flag.
	local _, _, who = string.find(msg, "^(%S+) claims")
	if not who then _, _, who = string.find(msg, "^(%S+) has assaulted") end
	if not who then _, _, who = string.find(msg, "^(%S+) has defended") end
	if who and watch[who] and watch[who].node then ClearWarning(who) end
	-- "Taken" and "captured" report a holder: nobody need be at the flag, so
	-- they teach no spot.
	if not (assault or defended) then return end
	local unit = who and UnitForName(who)
	if unit then
		local y, x, _, map = UnitPosition(unit)
		if y and map == mapID then Learn(node, y, x) end
	end
end

local function Reset()
	for name, w in pairs(watch) do
		if w.node then Targets.SetOpening(name, nil) end
		watch[name] = nil
	end
	table.wipe(nodeHolder)
	table.wipe(openers)
end

local function UpdateZone()
	local inInstance, instanceType = IsInInstance()
	local zone = string.lower(GetRealZoneText() or "")
	local want = inInstance and instanceType == "pvp"
		and string.find(zone, "arathi") and true or false
	if want == active then return end
	active = want
	Reset()
	if active then
		if not cleaned then DropOtherSpots(); cleaned = true end
		ReadMap()
		enemyFaction = UnitFactionGroup("player") == "Horde" and "Alliance" or "Horde"
		for _, name in ipairs(CAST_EVENTS) do FlagWatch:RegisterEvent(name) end
		if not ticker then ticker = C_Timer.NewTicker(TICK, Tick) end
	else
		mapID = nil
		for _, name in ipairs(CAST_EVENTS) do FlagWatch:UnregisterEvent(name) end
		if ticker then ticker:Cancel(); ticker = nil end
	end
end

FlagWatch:RegisterEvent("PLAYER_ENTERING_WORLD")
FlagWatch:RegisterEvent("ZONE_CHANGED_NEW_AREA")
FlagWatch:SetScript("OnEvent", function(p1, p2, p3, p4, p5, p6)
	local ev, a1, a2, a3
	if type(p1) == "string" then ev, a1, a2, a3 = p1, p2, p3, p4
	elseif type(p2) == "string" then ev, a1, a2, a3 = p2, p3, p4, p5
	else ev, a1, a2, a3 = event, arg1, arg2, arg3 end
	if ev == "SPELL_START_OTHER" or ev == "SPELL_GO_OTHER" or ev == "SPELL_FAILED_OTHER" then
		-- NamPower: START and GO give itemId, spellId, casterGuid; FAILED gives
		-- casterGuid, spellId. Casts arrive for everyone nearby; name each
		-- spell ID once.
		local guid, spellId = a3, a2
		if ev == "SPELL_FAILED_OTHER" then guid, spellId = a1, a2 end
		if not guid then return end
		local name = openers[guid]
		if name and ev ~= "SPELL_START_OTHER" then
			openers[guid] = nil
			ClearWarning(name)
		end
		if not spellId then return end
		local opening = openingBySpell[spellId]
		if opening == nil then
			local spell = GetSpellInfo(spellId)
			-- UNVERIFIED: test in game that flags are opened with a spell named "Opening".
			opening = spell and string.find(spell, "^Opening") and true or false
			openingBySpell[spellId] = opening
			if opening and AutoBG_FlagAlert then AutoBG_FlagAlert:LearnOpening(spellId) end
		end
		if not opening then return end
		if ev == "SPELL_START_OTHER" then OnOpeningStart(guid) end
	else
		UpdateZone()
	end
end)
