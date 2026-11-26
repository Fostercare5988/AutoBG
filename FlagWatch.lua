-- AutoBG flag watch, Arathi Basin only: an enemy in sight starting an Opening
-- cast, or one who comes out of stealth at a flag his side does not hold and
-- stands there. Flag spots are learned from the assault and defend lines.
-- Positions: ### UnitPosition(unit), the C_PlayerInfo form. It returns posY first;
-- the spots are saved as x, y (the old addon's, read the same way).
local _, A = ...
local db = A.db
local FW = {}
A.FlagWatch = FW
local card = A.Card("AutoBG_FlagAlert", -230)
local marked, ticker, warned = {}, nil, {}

local function Spots()
    if A.zone.match ~= "Arathi Basin" then return nil end
    local id = A.zone.mapID or 529
    db.spots[id] = db.spots[id] or {}
    return db.spots[id]
end
local function Pos(unit)
    local y, x = C_PlayerInfo.UnitPosition(unit)
    return x, y
end
local function Nearest(spots, x, y, within)
    local best, bestD
    for node, p in pairs(spots) do
        local d = (p.x - x) * (p.x - x) + (p.y - y) * (p.y - y)
        if d <= within * within and (not bestD or d < bestD) then best, bestD = node, d end
    end
    return best
end

local function Warn(e, node)
    e.opening = node
    A.Enemies.Refresh(e)
    local key = e.name .. node
    if warned[key] and GetTime() - warned[key] < 8 then return end
    warned[key] = GetTime()
    local where = node == "a flag" and node or "the " .. node
    card:Warn("Flag: " .. node, A.StripRealm(e.name) .. " is opening " .. where,
        A.NodeIcon(node, A.OTHER[A.MySide()]) or "Interface\\Icons\\INV_BannerPVP_01", e.name, e.guid,
        A.StripRealm(e.name) .. " is opening " .. where)
    PlaySound("igPVPUpdate")
end
function FW.Announce(e)
    if e.opening then A.Announce(A.StripRealm(e.name) .. " is opening " .. (e.opening == "a flag" and e.opening or "the " .. e.opening)) end
end

-- A visible Opening cast: the nearest learned spot within 10 yards names the base.
function FW.Opening(e)
    local spots = Spots()
    if not spots then return end
    local x, y = Pos(e.guid)
    Warn(e, x and Nearest(spots, x, y, 10) or "a flag")
end
local function Unmark(e)
    marked[e] = nil
    if e.opening then e.opening = nil; A.Enemies.Refresh(e) end
    if not next(marked) and ticker then ticker:Cancel(); ticker = nil end
end
function FW.Stopped(e) Unmark(e) end
function FW.Gone(e) Unmark(e) end

-- Out of stealth at a flag: still there half a second later (moved under half a
-- yard) warns; then one look each 0.5 s until he moves, dies, leaves view or is named.
local function Check()
    for e, m in pairs(marked) do
        local x, y = Pos(e.guid)
        if e.dead or not e.visible or not x or (x - m.x) * (x - m.x) + (y - m.y) * (y - m.y) > 0.25 then
            Unmark(e)
        elseif not m.warned then
            m.warned = true
            Warn(e, m.node)
        end
    end
end
function FW.Appeared(e)
    local spots = Spots()
    if not spots then return end
    local x, y = Pos(e.guid)
    local node = x and Nearest(spots, x, y, 10)
    if not node or A.owner[node] == A.OTHER[A.MySide()] then return end
    marked[e] = { node = node, x = x, y = y }
    if not ticker then ticker = C_Timer.NewTicker(0.5, Check) end
end

-- Spots from the lines that name a player at a flag ("taken" names nobody):
-- the average of up to 10 places, refused within 15 yards of another base.
function FW.Line(node, lower, player)
    if not player then return end
    for e in pairs(marked) do
        if e.name == player or e.short == player then Unmark(e) end
    end
    if not (string.find(lower, "claims", 1, true) or string.find(lower, "assaulted", 1, true) or string.find(lower, "defended", 1, true)) then return end
    local spots = Spots()
    local unit = player == UnitName("player") and "player" or A.Token(player)
    local x, y
    if unit then x, y = Pos(unit) end
    if not (spots and x) then return end
    local other = Nearest(spots, x, y, 15)
    if other and other ~= node then return end
    local p = spots[node]
    if not p then
        spots[node] = { x = x, y = y, n = 1 }
    elseif p.n < 10 then
        p.x, p.y, p.n = (p.x * p.n + x) / (p.n + 1), (p.y * p.n + y) / (p.n + 1), p.n + 1
    end
end

A.On("PLAYER_ENTERING_WORLD", function()
    table.wipe(marked)
    if ticker then ticker:Cancel(); ticker = nil end
    card:Hide()
end)
function FW.Preview(on)
    if on then card:Warn("Flag: Stables", "Thandril is opening the Stables", A.NodeIcon("Stables", "Horde")) end
end
