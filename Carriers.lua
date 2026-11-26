-- AutoBG carriers: both Warsong Gulch flag carriers, from the server's lines
-- (KNOWN_PATTERNS KP-37: "The Horde flag was picked up by X!" makes X a carrier
-- for the Alliance), then followed by GUID (### frame:RegisterGUIDEvent).
local _, A = ...
local C = {}
A.Carriers = C
local carrier = {} -- side -> { name, guid }
local cards = {}
local frame = CreateFrame("Frame")
local EVENTS = { "UNIT_HEALTH", "UNIT_AURA_DELTA", "UNIT_VISIBILITY_CHANGED" }
local ASSAULT = { "Focused Assault", "Brutal Assault" } -- the stacking debuffs on a carrier

local function Card(side, x)
    local c = CreateFrame("Button", "AutoBG_" .. side .. "FC", UIParent)
    c:SetWidth(170)
    c:SetHeight(30)
    c:SetPoint("TOP", UIParent, "TOP", x, -120)
    A.Movable(c)
    A.UnitButton(c)
    A.Surface(c, 0.7)
    c.health = CreateFrame("StatusBar", nil, c)
    c.health:SetStatusBarTexture(A.GLOSS)
    c.health:SetPoint("TOPLEFT", c, "TOPLEFT", 1, -1)
    c.health:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -1, 1)
    c.health:SetMinMaxValues(0, 1)
    local color = A.COLORS[side]
    c.health:SetStatusBarColor(color[1] * 0.6, color[2] * 0.6, color[3] * 0.6)
    c.name = A.Text(c.health, 13)
    c.name:SetPoint("LEFT", c.health, "LEFT", 4, 0)
    c.info = A.Text(c.health, 12)
    c.info:SetPoint("RIGHT", c.health, "RIGHT", -4, 0)
    -- A unit button's click with no verb of its own reaches this with no arguments
    -- (ClassicAPI's chained OnClick; seen in play 2026-11-23): the frame from the
    -- closure, the button from GetMouseButtonClicked.
    c:SetScript("OnClick", function() A.Select(c.who, nil, GetMouseButtonClicked()) end)
    c:Hide()
    cards[side] = c
    return c
end
Card("Alliance", -100)
Card("Horde", 100)

local function Health(c, guid)
    local hp, max = guid and UnitHealth(guid) or 0, guid and UnitHealthMax(guid) or 0
    c.health:SetValue(max > 0 and hp / max or 1)
end
local STACKS = {}
local function Info(c, k)
    local n = k.stacks or 0
    if n > 0 and not STACKS[n] then STACKS[n] = "|cffff7733" .. n .. "x|r  " end
    c.info:SetText((STACKS[n] or "") .. A.YardText(k.guid and A.Yards(k.guid), k.blocked))
end
local function Stacks(k)
    k.stacks = 0
    for _, name in ipairs(ASSAULT) do
        local aura = k.guid and C_UnitAuras.GetAuraDataBySpellName(k.guid, name, "HARMFUL")
        if aura then k.stacks = aura.applications end
    end
end
local function Draw(side)
    local c, k = cards[side], carrier[side]
    if not k then
        A.Bind(c, nil)
        return c:Hide()
    end
    local guid = k.guid
    local class = A.Enemies.ClassOf(k.name) or (guid and UnitExists(guid) and select(2, UnitClass(guid)))
    local cc = class and RAID_CLASS_COLORS[class]
    c.name:SetText((cc and string.format("|cff%02x%02x%02x", cc.r * 255, cc.g * 255, cc.b * 255) or "") .. A.StripRealm(k.name))
    Health(c, guid)
    Info(c, k)
    c.who = k.name
    A.Bind(c, guid)
    c:Show()
end

-- Ten times a second: drawn again only when the yard or the line of sight changes.
local function Look()
    for side, k in pairs(carrier) do
        if k.guid and UnitIsVisible(k.guid) then
            local y = A.Yards(k.guid)
            local n = y and math.floor(y + 0.5)
            if A.lookTick % 5 == 0 or k.blocked == nil then k.blocked = A.Blocked(k.guid) end
            if n ~= k.yards or k.blocked ~= k.drawnBlocked then
                k.yards, k.drawnBlocked = n, k.blocked
                Info(cards[side], k)
            end
        end
    end
end
local list = {}
local function Follow()
    for i = #list, 1, -1 do list[i] = nil end
    local seen = false
    for _, k in pairs(carrier) do
        if k.guid then
            list[#list + 1] = k.guid
            seen = seen or UnitIsVisible(k.guid)
        end
    end
    for _, e in ipairs(EVENTS) do
        if #list > 0 then frame:RegisterGUIDEvent(e, unpack(list)) else frame:UnregisterGUIDEvent(e) end
    end
    A.WatchDistance("carriers", seen and Look or nil)
end
local Clear
frame:SetScript("OnEvent", function(_, event, guid, info)
    for side, k in pairs(carrier) do
        if k.guid == guid then
            local removed = event == "UNIT_AURA_DELTA" and k.aura and info and info.removedAuraInstanceIDs
            for i = 1, removed and #removed or 0 do
                if removed[i] == k.aura then return Clear(side) end
            end
            if event == "UNIT_HEALTH" then Health(cards[side], guid)
            elseif event == "UNIT_AURA_DELTA" then Stacks(k); Info(cards[side], k)
            else Draw(side) end
        end
    end
    if event == "UNIT_VISIBILITY_CHANGED" then Follow() end
end)

local function Set(side, name, guid)
    name = string.gsub(name, "^%s*(.-)%s*$", "%1")
    A.NoteSide(name, side)
    local token = not guid and A.Token(name)
    carrier[side] = { name = name, guid = guid or token and UnitGUID(token) }
    Stacks(carrier[side])
    Follow()
    Draw(side)
end
Clear = function(side)
    carrier[side] = nil
    Follow()
    Draw(side)
end

-- The flag a carrier wears (octowow.st/db, 2026-11-23): 23333 Warsong Flag is
-- the Horde flag, so its carrier plays for the Alliance; 23335 Silverwing Flag
-- the Alliance flag. It names a carrier the lines never did (you came in after
-- the pickup): one of your group at once, an enemy once a token shows him.
local FLAG_AURA = { [23333] = "Alliance", [23335] = "Horde" }
function C.Aura(name, guid, spellId, instance)
    local side = FLAG_AURA[spellId]
    if not (side and name and A.zone.match == "Warsong Gulch") then return end
    local k = carrier[side]
    if not (k and k.name == name and k.guid == guid) then Set(side, name, guid) end
    carrier[side].aura = instance
end
local group, slots, buf = CreateFrame("Frame"), {}, {}
local function Scan(unit)
    if not UnitExists(unit) then return end
    C_UnitAuras.GetAuraSlots(unit, "HELPFUL", nil, nil, slots)
    for i = 1, slots.n do
        local spell, _, _, _, _, _, instance = select(10, C_UnitAuras.UnitAuraBySlot(unit, slots[i]))
        if FLAG_AURA[spell] then C.Aura(UnitName(unit), UnitGUID(unit), spell, instance) end
    end
end
C.Scan = Scan
local GROUP = { "player" }
for i = 1, 40 do GROUP[#GROUP + 1] = "raid" .. i end
group:SetScript("OnEvent", function(_, event, unit, info)
    if event == "GROUP_ROSTER_UPDATE" or info and info.isFullUpdate then
        if event == "GROUP_ROSTER_UPDATE" then for _, u in ipairs(GROUP) do Scan(u) end else Scan(unit) end
        return
    end
    local added = info and info.addedAuraInstanceIDs
    for i = 1, added and #added or 0 do
        local a = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, added[i], buf)
        if a and FLAG_AURA[a.spellId] then C.Aura(UnitName(unit), UnitGUID(unit), a.spellId, added[i]) end
    end
end)
-- The enemies' roster tells of a GUID it learned.
function C.Learn(name, guid)
    for side, k in pairs(carrier) do
        if k.name == name and k.guid ~= guid then k.guid = guid; Stacks(k); Follow(); Draw(side) end
    end
end

-- The lines, Horde flag first: its carrier plays for the Alliance.
local FLAGS = { Alliance = { "[Hh]orde [Ff]lag", "[Ww]arsong [Ff]lag" }, Horde = { "[Aa]lliance [Ff]lag", "[Ss]ilverwing [Ff]lag" } }
function C.Line(msg)
    if string.find(msg, "placed at their bases", 1, true) then
        Clear("Alliance")
        return Clear("Horde")
    end
    for side, names in pairs(FLAGS) do
        for _, flag in ipairs(names) do
            local who = string.match(msg, flag .. " was picked up by ([^!%.]+)")
            if who then return Set(side, who) end
            if string.find(msg, flag .. " was dropped") or string.find(msg, flag .. " was returned")
                or string.find(msg, flag .. " was captured") or string.find(msg, "captured the " .. flag) then
                return Clear(side)
            end
        end
    end
end

-- /abg efc: the carrier of the other side.
function C.TargetEnemy()
    local k = carrier[A.OTHER[A.MySide()]]
    if not (k and A.Select(k.name, k.guid)) then A.Print("No enemy flag carrier is known.") end
end

A.On("PLAYER_ENTERING_WORLD", function()
    if carrier.Alliance or carrier.Horde then
        carrier.Alliance, carrier.Horde = nil, nil
        Follow()
        Draw("Alliance")
        Draw("Horde")
    end
    -- In Warsong Gulch your group's auras are followed; a carrier among them shows now.
    if A.zone.match == "Warsong Gulch" then
        group:RegisterUnitEvent("UNIT_AURA_DELTA", unpack(GROUP))
        group:RegisterEvent("GROUP_ROSTER_UPDATE")
        for _, u in ipairs(GROUP) do Scan(u) end
    else
        group:UnregisterAllEvents()
    end
end)

function C.Preview(on)
    for side, name in pairs({ Alliance = "Brightblade", Horde = "Gruktar" }) do
        if on then
            cards[side].name:SetText(name)
            cards[side].health:SetValue(0.7)
            cards[side].info:SetText("|cffff7733" .. "3x|r  " .. A.YardText(side == "Horde" and 24 or 71))
            cards[side]:Show()
        else
            Draw(side)
        end
    end
end
