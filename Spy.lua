-- AutoBG Spy: the enemy players around you in the open world, newest on top,
-- and the stealth warnings outside arenas. It rests in battlegrounds, arenas and
-- raids. Sightings: tokens (plates, target, mouseover, focus) and, for the far
-- ones, NamPower's SPELL_GO_OTHER and BUFF_ADDED_OTHER (EVENTS.md); then by GUID.
local _, A = ...
local db = A.db
local S = {}
A.Spy = S
local KEEP, DIM, FORGET = 20, 5, 30
local list, byGUID, notEnemy = {}, {}, {}

-- The stealth card stands while you see a hidden enemy and goes when you no
-- longer do (the player, 2026-11-27: "often I play with no sound or my attention
-- is elsewhere... make the popup go away if we cant see the enemy, and make it
-- appear WHENEVER we see them"). Seeing is the game showing him to you: any
-- distance, any wall. With several, the newest seen is on the card and the next
-- takes his place when he goes. His yards follow on the card. A click targets
-- him. The sound when one is newly seen: always in a battleground, elsewhere with
-- Warning sounds. AutoArena's card follows the same rule.
local card = A.Card("AutoBG_SpyAlertWindow", -180)
local STEALTH_ICON = { STEALTH = "Ability_Stealth", VANISH = "Ability_Vanish", PROWL = "Ability_Ambush",
    MELD = "Ability_Ambush", ["INVIS POT"] = "INV_Potion_25", CLOAK = "INV_Misc_Cape_18" }
local function Colored(name, class)
    local cc = class and RAID_CLASS_COLORS[class]
    return (cc and string.format("|cff%02x%02x%02x", cc.r * 255, cc.g * 255, cc.b * 255) or "") .. A.StripRealm(name) .. "|r"
end
local seen, onCard = {}, nil
local function Line(e)
    local yards = e.guid and A.Yards(e.guid)
    return Colored(e.name, e.class) .. " is stealthed " .. (yards and math.floor(yards + 0.5) .. " yd away" or "nearby")
end
local function Hold(e)
    onCard = e
    if not e then return card:Hide() end
    e.onCardAs = e.stealth
    card:Warn("|cffff4040" .. e.stealth .. "|r", Line(e), "Interface\\Icons\\" .. (STEALTH_ICON[e.stealth] or "Ability_Stealth"),
        e.name, e.guid, A.StripRealm(e.name) .. " is stealthed near me", true)
    -- Sap on click, a Rogue's choice (the player, 2026-11-27: off by default, as
    -- other classes cannot Sap): cast on his GUID, your target kept
    -- (### frame:SetAttribute, verb "spell", C_Spell.CastAtUnit).
    if e.guid and db.sapClick and select(2, UnitClass("player")) == "ROGUE" then
        card:SetAttribute("type1", "spell")
        card:SetAttribute("spell1", "Sap")
    end
end
-- The switch changed: the card on screen follows it.
function A.SapClick() if onCard then Hold(onCard) end end
-- Called on every change of an entry's stealth, view or death.
function A.Detect(e, inBG)
    local on = not e.sample and e.stealth and e.visible and not e.dead and true or nil
    if on == e.detected then
        if on and onCard == e and e.onCardAs ~= e.stealth then Hold(e) end -- Stealth became Vanish
        return
    end
    e.detected = on
    if on then
        seen[#seen + 1] = e
        Hold(e)
        if inBG or db.spySounds then PlaySound("RaidWarning") end
    else
        -- Shifted by hand: table.remove stops shrinking a table grown by
        -- t[#t + 1] on Lua 5.0 (wowlua.py, seen in play).
        for i = #seen, 1, -1 do
            if seen[i] == e then
                for j = i, #seen do seen[j] = seen[j + 1] end
            end
        end
        if onCard == e then Hold(seen[#seen]) end
    end
end
-- His yards on the card, written when the whole yard changes (the distance look).
function A.DetectYards(e)
    if onCard == e then card.line:SetText(Line(e)) end
end
-- An entry that leaves its list leaves the card.
function A.Undetect(e)
    e.stealth = nil
    A.Detect(e)
end

-- The list ---------------------------------------------------------------------
local f = CreateFrame("Frame", "AutoBG_SpyFrame", UIParent)
f:SetWidth(200)
f:SetPoint("RIGHT", UIParent, "RIGHT", -40, 120)
A.Movable(f)
A.Surface(f, 0.5)
f.title = A.Text(f, 13)
f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -4)
local close = CreateFrame("Button", nil, f)
close:SetWidth(16)
close:SetHeight(16)
close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
close.text = A.Text(close, 14)
close.text:SetPoint("CENTER", close, "CENTER", 0, 0)
close.text:SetText("x")
f:Hide()
local rows, hovered, Draw = {}, false, nil

local function Tooltip(row)
    local e = row.entry
    if not e then return end
    GameTooltip:SetOwner(row, "ANCHOR_LEFT")
    GameTooltip:SetText(e.name, 1, 1, 1)
    GameTooltip:AddLine("Level " .. (e.level > 0 and e.level or "??") .. " " .. (e.race or "") .. " " .. (e.className or ""), 0.9, 0.9, 0.9)
    GameTooltip:AddLine(math.floor(e.hp * 100 + 0.5) .. "% health" .. (e.yards and ", " .. math.floor(e.yards + 0.5) .. " yards" or ""), 0.9, 0.9, 0.9)
    if e.stealth then GameTooltip:AddLine(e.stealth, 1, 0.25, 0.25) end
    GameTooltip:AddLine(e.visible and "In view" or "Seen " .. math.floor(GetTime() - e.seen) .. " s ago", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end
local function Row(i)
    local r = CreateFrame("Button", nil, f)
    A.UnitButton(r)
    r:SetWidth(194)
    r:SetHeight(18)
    r:SetPoint("TOPLEFT", f, "TOPLEFT", 3, -20 - (i - 1) * 20)
    r.health = CreateFrame("StatusBar", nil, r)
    r.health:SetStatusBarTexture(A.GLOSS)
    r.health:SetAllPoints(r)
    r.health:SetMinMaxValues(0, 1)
    A.Surface(r, 0.7)
    r.name = A.Text(r.health, 12)
    r.name:SetPoint("LEFT", r, "LEFT", 4, 0)
    r.yards = A.Text(r.health, 11)
    r.yards:SetPoint("RIGHT", r, "RIGHT", -4, 0)
    -- A unit button's click with no verb of its own reaches this with no arguments
    -- (ClassicAPI's chained OnClick; seen in play 2026-11-23): the frame from the
    -- closure, the button from GetMouseButtonClicked.
    r:SetScript("OnClick", function()
        if r.entry and not r.entry.sample then A.Select(r.entry.name, r.entry.guid, GetMouseButtonClicked()) end
    end)
    r:SetScript("OnEnter", function(self) hovered = true; Tooltip(self) end)
    r:SetScript("OnLeave", function()
        hovered = false
        GameTooltip:Hide()
        if S.pending then Draw() end
    end)
    rows[i] = r
    return r
end

local function DrawEntry(r, e)
    local cc = e.class and RAID_CLASS_COLORS[e.class]
    r.entry, e.row = e, r
    r.health:SetStatusBarColor(cc and cc.r or 0.5, cc and cc.g or 0.5, cc and cc.b or 0.5)
    r.health:SetValue(e.hp)
    r.name:SetText(e.label)
    r.yards:SetText(e.visible and A.YardText(e.yards, e.blocked, true) or "")
    r:SetAlpha((e.visible or GetTime() - e.seen < DIM) and 1 or 0.45)
    A.Bind(r, not e.sample and e.guid or nil)
end
-- The list holds still under the mouse: a redraw waits for it to leave.
Draw = function()
    if hovered then S.pending = true; return end
    S.pending = nil
    local shown = math.min(#list, db.spyRows)
    for i = 1, math.max(shown, #rows) do
        local r = rows[i] or Row(i)
        if i <= shown then DrawEntry(r, list[i]); r:Show() else r.entry = nil; r:Hide() end
    end
    f.title:SetText("Spy  " .. #list)
    f:SetHeight(24 + shown * 20)
    f:SetShown(#list > 0 and S.active or S.preview or false)
end
local function Clear()
    for i = #list, 1, -1 do A.Undetect(list[i]); byGUID[list[i].guid or ""] = nil; list[i] = nil end
    S.Follow()
    Draw()
end
close:SetScript("OnClick", Clear)

-- Following by GUID; expiry is one timer at the next dim or forget.
local watch = CreateFrame("Frame")
local FOLLOW = { "UNIT_HEALTH", "UNIT_VISIBILITY_CHANGED", "UNIT_AURA_DELTA" }
local guids, expiry = {}, nil
local function Look()
    for i = 1, math.min(#list, db.spyRows) do
        local e = list[i]
        if e.visible then
            e.yards = A.Yards(e.guid)
            if A.lookTick % 5 == 0 or e.blocked == nil then e.blocked = A.Blocked(e.guid) end
            local n = e.yards and math.floor(e.yards + 0.5)
            if n ~= e.shownYards or e.blocked ~= e.shownBlocked then
                e.shownYards, e.shownBlocked = n, e.blocked
                local r = e.row
                if r and r.entry == e then r.yards:SetText(A.YardText(e.yards, e.blocked, true)) end
                if e.detected then A.DetectYards(e) end
            end
        end
    end
end
local Expire
local function Schedule()
    if expiry then expiry:Cancel(); expiry = nil end
    local now, soonest = GetTime(), nil
    local visible = false
    for _, e in ipairs(list) do
        if e.visible then
            visible = true
        else
            local at = now - e.seen < DIM and e.seen + DIM or e.seen + FORGET
            if not soonest or at < soonest then soonest = at end
        end
    end
    if soonest then expiry = C_Timer.NewTimer(math.max(0, soonest - now) + 0.05, Expire) end
    A.WatchDistance("spy", visible and Look or nil)
end
Expire = function()
    expiry = nil
    local now = GetTime()
    for i = #list, 1, -1 do
        local e = list[i]
        if not e.visible and now - e.seen >= FORGET then
            byGUID[e.guid] = nil
            for j = i, #list do list[j] = list[j + 1] end
        end
    end
    S.Follow()
    Draw()
end
function S.Follow()
    for i = #guids, 1, -1 do guids[i] = nil end
    for i, e in ipairs(list) do guids[i] = e.guid end
    for _, ev in ipairs(FOLLOW) do
        if #guids > 0 and S.active then watch:RegisterGUIDEvent(ev, unpack(guids)) else watch:UnregisterGUIDEvent(ev) end
    end
    Schedule()
end
local buf, slots = {}, {}
-- His hiding aura now, read whole: a stealth heard far away is not trusted.
local function Hidden(e, guid)
    e.stealth, e.stealthID = nil, nil
    C_UnitAuras.GetAuraSlots(guid, "HELPFUL", nil, nil, slots)
    for i = 1, slots.n do
        local spell, _, _, _, _, _, instance = select(10, C_UnitAuras.UnitAuraBySlot(guid, slots[i]))
        if A.STEALTH[spell] then e.stealth, e.stealthID = A.STEALTH[spell], instance end
    end
end
watch:SetScript("OnEvent", function(_, event, guid, a2)
    local e = byGUID[guid]
    if not e then return end
    if event == "UNIT_HEALTH" then
        -- Only that row's bar: health is the busiest event and changes nothing else.
        local max = UnitHealthMax(guid)
        if max and max > 0 then e.hp = UnitHealth(guid) / max end
        if e.row and e.row.entry == e then e.row.health:SetValue(e.hp) end
        return
    elseif event == "UNIT_VISIBILITY_CHANGED" then
        e.visible, e.seen = a2 and true or nil, GetTime()
        if a2 then Hidden(e, guid) else e.yards = nil end
        A.Detect(e, false)
        Schedule()
    elseif event == "UNIT_AURA_DELTA" then
        local added = a2.addedAuraInstanceIDs
        for i = 1, added and #added or 0 do
            local a = C_UnitAuras.GetAuraDataByAuraInstanceID(guid, added[i], buf)
            if a and A.STEALTH[a.spellId] then
                e.stealth, e.stealthID = A.STEALTH[a.spellId], added[i]
            end
        end
        local removed = a2.removedAuraInstanceIDs
        for i = 1, removed and #removed or 0 do
            if removed[i] == e.stealthID then e.stealth, e.stealthID = nil, nil end
        end
        A.Detect(e, false)
        return
    end
    Draw()
end)

-- A sighting: an attackable player, not of your group. A full list makes room
-- only from someone unseen a while.
local function See(unit, guid)
    if not (UnitIsPlayer(unit) and UnitCanAttack("player", unit)) then return false end
    local name = UnitName(unit)
    if not name or name == UNKNOWNOBJECT or A.InGroup(name) then return false end
    guid = guid or UnitGUID(unit)
    local e = byGUID[guid]
    local now = GetTime()
    local fresh = not e
    if fresh then
        if #list >= KEEP then
            local last = list[#list]
            if last.visible or now - last.seen < DIM then return true end
            byGUID[last.guid], list[#list] = nil, nil
        end
        e = { guid = guid }
        byGUID[guid] = e
        for j = #list, 1, -1 do list[j + 1] = list[j] end
        list[1] = e
        if db.spySounds then PlaySound("MapPing") end
    end
    local level = UnitLevel(unit) or 0
    if e.name ~= name or e.level ~= level then e.label = (level > 0 and level or "??") .. "  " .. A.StripRealm(name) end
    e.name, e.level, e.race = name, level, UnitRace(unit)
    e.className, e.class = UnitClass(unit)
    local max = UnitHealthMax(unit)
    e.hp = max and max > 0 and UnitHealth(unit) / max or 1
    e.seen, e.visible = now, UnitIsVisible(guid) and true or nil
    if fresh then S.Follow() else Schedule() end
    Draw()
    return true
end

-- Plates that wait: a name not cached yet, or a player not attackable yet,
-- read again on their own UNIT_NAME_UPDATE or UNIT_FLAGS (### Unit tokens (nameplateN)).
-- UNVERIFIED: that a stranger's PvP flag change fires UNIT_FLAGS on his plate.
local plates, waiting, tokens = CreateFrame("Frame"), {}, {}
local function Waiting()
    for i = #tokens, 1, -1 do tokens[i] = nil end
    for token in pairs(waiting) do tokens[#tokens + 1] = token end
    for _, ev in ipairs({ "UNIT_NAME_UPDATE", "UNIT_FLAGS" }) do
        if #tokens > 0 then plates:RegisterUnitEvent(ev, unpack(tokens)) else plates:UnregisterEvent(ev) end
    end
end
local function Plate(token)
    if See(token) then
        if waiting[token] then waiting[token] = nil; Waiting() end
    elseif UnitIsPlayer(token) and not waiting[token]
        and (UnitName(token) == UNKNOWNOBJECT or UnitFactionGroup(token) ~= UnitFactionGroup("player")) then
        waiting[token] = true
        Waiting()
    end
end
local SIGHT = { "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT",
    "PLAYER_FOCUS_CHANGED", "SPELL_GO_OTHER", "BUFF_ADDED_OTHER" }
-- A far caster or aura: players only (a player GUID starts 0x00000000), one look
-- per GUID. A dead enemy cannot be attacked but is still one: looked at again.
local function Far(guid)
    if byGUID[guid] or notEnemy[guid] or not string.find(guid, "^0x00000000") then return end
    if not See(guid, guid) and UnitExists(guid) and not UnitIsDeadOrGhost(guid) then notEnemy[guid] = true end
end
plates:SetScript("OnEvent", function(_, event, a1, a2, a3, _, _, _, a7)
    if event == "NAME_PLATE_UNIT_ADDED" or event == "UNIT_NAME_UPDATE" or event == "UNIT_FLAGS" then
        Plate(a1)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        if waiting[a1] then waiting[a1] = nil; Waiting() end
    elseif event == "PLAYER_TARGET_CHANGED" then
        See("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        See("mouseover")
    elseif event == "PLAYER_FOCUS_CHANGED" then
        See("focus")
    elseif event == "SPELL_GO_OTHER" then
        Far(a3)
    elseif event == "BUFF_ADDED_OTHER" then
        -- Only a newly added stealth aura (state 0).
        if a7 == 0 and A.STEALTH[a3] then
            Far(a1)
            local e = byGUID[a1]
            if e and UnitIsVisible(a1) then e.visible = true; Hidden(e, a1); A.Detect(e, false) end
        end
    end
end)

-- Spy works in the open world with its switch on.
function S.Sync()
    S.active = db.spy and not A.zone.pvp and not A.zone.raid or false
    -- NamPower sends SPELL_GO_OTHER only with this switch on (EVENTS.md, default 0).
    if S.active and GetCVar("NP_EnableSpellGoEvents") ~= "1" then SetCVar("NP_EnableSpellGoEvents", "1") end
    for _, ev in ipairs(SIGHT) do
        if S.active then plates:RegisterEvent(ev) else plates:UnregisterEvent(ev) end
    end
    table.wipe(waiting)
    table.wipe(notEnemy)
    Waiting()
    if not S.active then Clear() else S.Follow(); Draw() end
end
A.On("PLAYER_ENTERING_WORLD", S.Sync)
A.On("ZONE_CHANGED_NEW_AREA", S.Sync)
function S.Layout() Draw() end

function S.Preview(on)
    S.preview = on
    if on then
        Clear()
        for i, s in ipairs({ { "Leuka", "PALADIN", 60 }, { "Zoe", "ROGUE", 58 }, { "Caelwynn-NZ", "MAGE", 60 } }) do
            list[i] = { sample = true, name = s[1], label = s[3] .. "  " .. A.StripRealm(s[1]), class = s[2], level = s[3],
                hp = 1 - i * 0.2, seen = GetTime(), visible = i < 3, yards = 20 * i }
        end
        Draw()
        card:Warn("|cffff4040STEALTH|r", Colored("Zoe", "ROGUE") .. " is stealthed 40 yd away",
            "Interface\\Icons\\Ability_Stealth", "Zoe")
    else
        for i = #list, 1, -1 do list[i] = nil end
        S.Sync()
    end
end
