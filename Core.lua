-- AutoBG: battlegrounds with less clicking and more knowledge.
-- Core: the saved table and its pages, the zone, the chat voice, the side you
-- play on, unit buttons, warning cards and the distance look (gap 1).
-- Doc headings are ClassicAPI's docs/API.md; "FrameXML" is the client's own code.
if not CLASSIC_API_VERSION then error("AutoBG needs ClassicAPI.", 0) end
if not GetNampowerVersion then error("AutoBG needs NamPower.", 0) end

local _, A = ...
AutoBGDB = AutoBGDB or {} -- restored first: LoadSavedVariablesFirst
local db = AutoBGDB
A.db = db

-- Claude's choices.
A.DEFAULTS = { queueWSG = false, queueAB = false, queueAV = true, teamsWSG = "fa", teamsAB = "fa",
    queueArena = false, arenaType = "skirmish", queueOnLogin = true, popAlert = true, leave = true, rejoin = true, release = true,
    barWidth = 200, barHeight = 22, spy = true, spyRows = 10, spySounds = true }
A.SIZE_DEFAULTS = {
    [10] = { show = true, hideRealm = true, yards = true, width = 195, height = 25, text = 20 },
    [15] = { show = true, hideRealm = true, yards = true, width = 145, height = 20, text = 15 },
    [40] = { show = true, hideRealm = true, yards = true, width = 210, height = 20, text = 11 },
}
local TABLES = { sizes = true, ticks = true, spots = true, racials = true, places = true }

-- One sweep clears every key nothing owns (KNOWN_PATTERNS KP-64); the features
-- start before the window registers the pages, so the defaults are filled now.
for key in pairs(db) do
    if A.DEFAULTS[key] == nil and not TABLES[key] then db[key] = nil end
end
for key, value in pairs(A.DEFAULTS) do
    if type(db[key]) ~= type(value) then db[key] = value end
end
for key in pairs(TABLES) do
    if type(db[key]) ~= "table" then db[key] = {} end
end
for size in pairs(db.sizes) do
    if A.SIZE_DEFAULTS[size] == nil then db.sizes[size] = nil end -- a size that is no more (the arena's moved to AutoArena)
end
for size, defaults in pairs(A.SIZE_DEFAULTS) do
    local s = type(db.sizes[size]) == "table" and db.sizes[size] or {}
    db.sizes[size] = s
    for key, value in pairs(defaults) do
        if type(s[key]) ~= type(value) then s[key] = value end
    end
end

-- The chat voice: "AutoBG" in orange, a short sentence, names in gold.
function A.Print(text) DEFAULT_CHAT_FRAME:AddMessage("|cffff9e38AutoBG|r " .. text) end
function A.Gold(text) return "|cffffd100" .. text .. "|r" end
function A.Announce(text)
    local channel = "SAY"
    if A.zone.pvp and not A.zone.arena then channel = "BATTLEGROUND"
    elseif GetNumRaidMembers() > 0 then channel = "RAID"
    elseif GetNumPartyMembers() > 0 then channel = "PARTY" end
    SendChatMessage(text, channel)
end
function A.StripRealm(name) return (string.gsub(name, "%-.*$", "")) end

-- Events the modules share. One listener's error does not stop the others.
local hub, lists = CreateFrame("Frame"), {}
function A.On(event, fn)
    if not lists[event] then lists[event] = {}; hub:RegisterEvent(event) end
    local list = lists[event]
    list[#list + 1] = fn
end
hub:SetScript("OnEvent", function(_, event, a1, a2, a3, a4)
    local list = lists[event]
    for i = 1, #list do
        local ok, err = pcall(list[i], a1, a2, a3, a4)
        if not ok then geterrorhandler()(err) end
    end
end)

-- The zone: a battleground, an arena (the three zone names, confirmed by the
-- player 2026-11-03).
local ARENAS = { ["lordaeron arena"] = true, ["sunstrider court"] = true, ["blood ring"] = true }
A.ARENAS = ARENAS
A.zone = { pvp = false, arena = false, name = "" }
local function ReadZone(_, isLogin)
    local z = A.zone
    local name, kind, _, _, _, _, _, mapID = GetInstanceInfo()
    local inside = IsInInstance()
    -- Sunstrider Court is no instance on OctoWoW (IsInInstance false, IsActiveBattlefieldArena
    -- false there, the player 2026-11-24; Lordaeron Arena is both): its name alone is enough.
    z.arena = (inside and IsActiveBattlefieldArena() or ARENAS[string.lower(GetRealZoneText() or "")]) and true or false
    z.pvp = z.arena or (inside and kind == "pvp") or false
    z.raid = inside and kind == "raid" or false
    z.name, z.mapID = GetRealZoneText() or name or "", mapID
    z.bg = z.pvp and not z.arena and A.BG[z.name] or nil
    -- The battleground you are in, or nil. The zone text can still name the
    -- battleground just after you leave it (seen 2026-11-23: the Arathi estimate
    -- in Orgrimmar), so a check for one battleground asks this, not the name.
    z.match = z.pvp and not z.arena and z.name or nil
    z.size = z.bg and z.bg.size or nil -- an arena's frames are AutoArena's
end
A.On("PLAYER_ENTERING_WORLD", ReadZone)
A.On("ZONE_CHANGED_NEW_AREA", ReadZone)
-- Work that depends on the zone runs after ReadZone on both events, with `fresh`
-- true at a loading screen: the zone text can lag it, and a match read late must
-- not stay unwatched. -- UNVERIFIED: that it lags on OctoWoW; ReadZone already runs on both.
function A.OnZone(fn)
    A.On("PLAYER_ENTERING_WORLD", function() fn(true) end)
    A.On("ZONE_CHANGED_NEW_AREA", function() fn(false) end)
end

-- The side you play on. Mixed teams put both factions on each side, so your
-- faction is only the first guess; a player seen playing for a side settles
-- it: one of your group is on your side, one you can attack on the other.
local OTHER = { Alliance = "Horde", Horde = "Alliance" }
A.OTHER = OTHER
local side
A.On("PLAYER_ENTERING_WORLD", function() side = nil end)
function A.MySide() return side or UnitFactionGroup("player") end
-- Unit functions take a group member's name (### Unit tokens (names)).
function A.InGroup(name)
    return UnitInRaid(name) or UnitInParty(name) or (string.find(name, "-", 1, true)
        and (UnitInRaid(A.StripRealm(name)) or UnitInParty(A.StripRealm(name)))) or false
end
function A.Token(name)
    return UnitTokenFromName(name, true)
        or (string.find(name, "-", 1, true) and UnitTokenFromName(A.StripRealm(name), true)) or nil
end
function A.SideOf(name)
    if name == UnitName("player") or A.InGroup(name) then return A.MySide() end
    local unit = A.Token(name)
    if unit and UnitIsPlayer(unit) and UnitCanAttack("player", unit) then return OTHER[A.MySide()] end
end
function A.NoteSide(name, playsFor)
    local seen = name and OTHER[playsFor] and A.SideOf(name)
    if seen then side = (seen == A.MySide()) and playsFor or OTHER[playsFor] end
end

-- Unit buttons (### frame:SetAttribute ... unit-frame mouseover): left targets
-- (or casts the cursor's spell), right focuses, hover is the mouseover. Ctrl and
-- Shift carry a verb the window does not know, so they reach OnClick.
function A.UnitButton(b)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetAttribute("ctrl-type1", "own")
    b:SetAttribute("shift-type1", "own")
end
function A.Bind(b, guid)
    b:SetAttribute("unit", guid)
    b:SetAttribute("type1", guid and "target" or nil)
    b:SetAttribute("type2", guid and "focus" or nil)
end
-- A name with no GUID yet: one off-screen unit button selects it.
local selector
function A.Select(name, guid, button)
    local unit = guid and UnitExists(guid) and guid or (name and A.Token(name))
    if not unit then return false end
    if not selector then
        selector = CreateFrame("Button", "AutoBG_Selector", UIParent)
        selector:SetWidth(1)
        selector:SetHeight(1)
        selector:SetPoint("BOTTOMRIGHT", UIParent, "TOPLEFT", -10, 10)
        A.UnitButton(selector)
        selector:SetAttribute("type1", "target")
        selector:SetAttribute("type2", "focus")
    end
    selector:SetAttribute("unit", unit)
    selector:Click(button == "RightButton" and "RightButton" or "LeftButton")
    selector:SetAttribute("unit", nil)
    return true
end

-- Places: every frame has one in each battleground and one outside them, which
-- a battleground where it was never moved uses (the player, 2026-11-26: Warsong,
-- Arathi and Alterac each their own, never moved again). AutoBG keeps them, as
-- x, y from UIParent's top left (layout-cache.txt's form), so the client does
-- not (### frame:SetDontSavePosition). Nothing reads a position at login (KP-66):
-- a place is read only when a drag ends.
local movables = {}
local function Where() return A.zone.match or "world" end
function A.Place(f)
    local name, here, world = f:GetName(), db.places[Where()], db.places.world
    local p = here and here[name] or world and world[name]
    if not p then return end
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", p[1], p[2])
end
function A.Drop(f)
    f:StopMovingOrSizing()
    f:SetUserPlaced(false)
    local x, y = f:GetLeft(), f:GetTop()
    if not x then return end
    local where = Where()
    db.places[where] = db.places[where] or {}
    db.places[where][f:GetName()] = { x, y - UIParent:GetTop() }
    A.Place(f)
end
-- A movable frame of ours, dragged with the left button, placed where this
-- battleground has it each time it shows and at each zone.
function A.Movable(f)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetDontSavePosition(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) if not self.locked then self:StartMoving() end end)
    f:SetScript("OnDragStop", A.Drop)
    f:HookScript("OnShow", A.Place)
    movables[#movables + 1] = f
    A.Place(f)
end
A.OnZone(function() for i = 1, #movables do A.Place(movables[i]) end end)
function A.Surface(f, alpha)
    local back = f:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints(f)
    back:SetTexture(0, 0, 0, alpha or 0.6)
    return back
end
function A.Text(parent, size, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFont("Fonts\\ARIALN.TTF", size, "OUTLINE")
    return fs
end

-- Health as text, built once: a redraw on every health change makes no strings.
A.PCT = {}
for i = 0, 100 do A.PCT[i] = i .. "%" end

-- A warning card: icon, title and text; hides after 4.5 s. A click selects the
-- enemy, Ctrl-click announces.
function A.Card(name, y)
    local c = CreateFrame("Button", name, UIParent)
    c:SetWidth(240)
    c:SetHeight(44)
    c:SetPoint("TOP", UIParent, "TOP", 0, y)
    c:SetFrameStrata("HIGH")
    A.Movable(c)
    A.UnitButton(c)
    A.Surface(c, 0.75)
    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetWidth(36)
    c.icon:SetHeight(36)
    c.icon:SetPoint("LEFT", c, "LEFT", 4, 0)
    c.title = A.Text(c, 15)
    c.title:SetPoint("TOPLEFT", c.icon, "TOPRIGHT", 6, -2)
    c.line = A.Text(c, 12)
    c.line:SetPoint("BOTTOMLEFT", c.icon, "BOTTOMRIGHT", 6, 2)
    -- A unit button's click with no verb of its own reaches this with no arguments
    -- (ClassicAPI's chained OnClick; seen in play 2026-11-23): the frame from the
    -- closure, the button from GetMouseButtonClicked.
    c:SetScript("OnClick", function()
        if IsControlKeyDown() then
            if c.say then A.Announce(c.say) end
        else
            A.Select(c.who, c.guid, GetMouseButtonClicked())
        end
    end)
    c:Hide()
    function c:Warn(title, text, icon, who, guid, say)
        self.title:SetText(title)
        self.line:SetText(text)
        self.icon:SetTexture(icon)
        self.who, self.guid, self.say = who, guid, say
        A.Bind(self, guid)
        self:Show()
        if self.timer then self.timer:Cancel() end
        self.timer = C_Timer.NewTimer(4.5, function() self.timer = nil; self:Hide() end)
    end
    return c
end

-- GAP: no event when a unit's distance changes (UNIT_DISTANCE_CHECK_UPDATE is
-- for your group, at 250 yards); a DLL should give a distance threshold event
-- for a unit or GUID. One look ten times a second, so the yards move smoothly
-- (the player, 2026-11-23: "clunky" at twice a second), and only while an owner
-- has someone in view (### UnitDistanceSquared(unit)). A.lookTick counts the
-- looks; the line of sight, a ray through the world, is read every fifth.
local looks, ticker = {}, nil
A.lookTick = 0
local function Look()
    A.lookTick = A.lookTick + 1
    for _, fn in pairs(looks) do fn() end
end
function A.WatchDistance(owner, fn)
    looks[owner] = fn
    if next(looks) and not ticker then
        ticker = C_Timer.NewTicker(0.1, Look)
    elseif not next(looks) and ticker then
        ticker:Cancel()
        ticker = nil
    end
end
function A.Yards(unit)
    local d, known = UnitDistanceSquared(unit)
    if known then return math.sqrt(d) end
end
-- "24 yd", each text made once (it is written twice a second for every enemy,
-- carrier and Spy row in view). The battleground frames: white to 150 yards,
-- orange beyond (the player, 2026-11-27). Spy's list: green to 30, gold to 60,
-- orange beyond. Grey when a wall or hill is between you (line of sight, as the
-- Nampower Spy colours its distances).
local YARD_TEXT, YARD_BLOCKED = { [false] = {}, [true] = {} }, {}
function A.YardText(yards, blocked, spy)
    if not yards then return "" end
    local n = math.floor(yards + 0.5)
    local cache = blocked and YARD_BLOCKED or YARD_TEXT[spy and true or false]
    local text = cache[n]
    if not text then
        local color = blocked and "|cff808080" or spy and (n <= 30 and "|cff59ff72" or n <= 60 and "|cffffd100" or "|cffff7733")
            or (n <= 150 and "|cffffffff" or "|cffff7733")
        text = color .. n .. " yd|r"
        if n <= 300 then cache[n] = text end
    end
    return text
end
-- The yards on the battleground frames: two sizes over the text, bold.
function A.YardFont(fs, size)
    fs:SetFont("Fonts\\ARIALN.TTF", size, "THICKOUTLINE")
    return fs
end
-- UnitXP's line of sight (dllmain.cpp "inSight": true, false, or nil when it
-- cannot tell). UNVERIFIED: that UnitXP takes a GUID for the unit, as the
-- Nampower Spy calls it; an answer of nil leaves the yards in their colour.
function A.Blocked(unit)
    return UnitXP and UnitXP("inSight", "player", unit) == false or false
end
