-- AutoBG enemies: the other team as rows. The roster is the scoreboard,
-- corrected by what you can attack (mixed teams), plus every hostile player
-- seen; battlegrounds only (an arena is AutoArena's). Each enemy is followed by GUID
-- (### frame:RegisterGUIDEvent), so the engine drops every other unit's events
-- before Lua runs. Server numbers are octowow.st/db's (servers/octowow.md).
local _, A = ...
local db = A.db
local E = {}
A.Enemies = E
local Bars = A.Bars
local MASK = "Interface\\AddOns\\AutoBG\\Textures\\RoundedMask"

-- Stealth by aura spell ID (octowow.st/db, 2026-10-21): Stealth ranks, Vanish's
-- auras 11327/11329, Prowl ranks, Shadowmeld, the potions and the cloak.
local STEALTH = { [1784] = "STEALTH", [1785] = "STEALTH", [1786] = "STEALTH", [1787] = "STEALTH",
    [11327] = "VANISH", [11329] = "VANISH", [5215] = "PROWL", [6783] = "PROWL", [9913] = "PROWL",
    [20580] = "MELD", [3680] = "INVIS POT", [11392] = "INVIS POT", [4079] = "CLOAK" }
local TIMED = { [3680] = 15, [11392] = 18, [4079] = 10 }
-- What a hidden enemy's row says, in the old addon's colours (AutoBG 1.1.0).
local LABEL = { STEALTH = "|cffc7b5ffSTEALTH|r", PROWL = "|cffd2c2ffPROWL|r", VANISH = "|cffd2c2ffVANISH|r",
    MELD = "|cffc7b5ffMELD|r", ["INVIS POT"] = "|cff00ffffINVIS POT|r", CLOAK = "|cff00ffffCLOAK|r" }
-- The casts that hide an enemy: the stealth spells are their own auras; Vanish is
-- cast as 1856/1857 (servers/octowow.md). The cast reaches us while he is still
-- in view; his aura often does not, as he leaves view the same moment.
local HIDES = { [1856] = "VANISH", [1857] = "VANISH" }
for id, label in pairs(STEALTH) do HIDES[id] = label end
A.STEALTH = STEALTH
-- The PvP trinket (52317 Insignia, all crowd control) and the Immune effects: 3 min (confirmed in play).
local TRINKET = { [52317] = true, [5579] = true, [23273] = true, [23274] = true, [23276] = true, [23277] = true }
-- Racials and their cooldowns (octowow.st/db ?spells=-4, 2026-11-14), by race.
local RACIAL = { [20600] = 180, [20594] = 180, [20580] = 60, [20589] = 90, [20572] = 120, [7744] = 150,
    [20549] = 150, [20554] = 180, [26296] = 180, [26297] = 180 }
local RACE = { Human = 20600, Dwarf = 20594, ["Night Elf"] = 20580, NightElf = 20580, Gnome = 20589, Orc = 20572,
    Undead = 7744, Scourge = 7744, Tauren = 20549, Troll = 20554 }
-- The Enemy racials page, one switch each (AutoBGDB.racials[key], false hides it).
A.RACIALS = { { "Human", "Perception", 20600 }, { "Dwarf", "Stoneform", 20594 }, { "NightElf", "Shadowmeld", 20580 },
    { "Gnome", "Escape Artist", 20589 }, { "Orc", "Blood Fury", 20572 }, { "Undead", "Will of the Forsaken", 7744 },
    { "Tauren", "War Stomp", 20549 }, { "Troll", "Berserking", 20554 } }
local RACIAL_KEY = { [26296] = "Troll", [26297] = "Troll" }
for _, r in ipairs(A.RACIALS) do RACIAL_KEY[r[3]] = r[1] end
local ICON = {}
local function SpellIcon(id)
    if not ICON[id] then ICON[id] = select(3, GetSpellInfo(id)) or "Interface\\Icons\\INV_Misc_QuestionMark" end
    return ICON[id]
end

local roster, byName, byGUID, friendly, classes = {}, {}, {}, {}, {}
E.roster, E.byGUID = roster, byGUID
function E.ClassOf(name) return byName[name] and byName[name].class or classes[name] end
local frames, Draw, DrawRow, Rebuild = {}, nil, nil, nil
local function Size() return E.preview and E.editSize or A.zone.size or 40 end

-- Rows ------------------------------------------------------------------------
-- A cooldown's number fits inside its icon (the player, 2026-11-23: "2:54" and
-- "1:02:43" ran into each other): "3m" above a minute, "45" below, in a font
-- sized to the icon (the cooldown's own is size 16, ### CreateFrame("Cooldown")).
local Up = Enum.NumericRuleFormatRounding.Up
local SHORT = C_StringUtil.CreateNumericRuleFormatter()
SHORT:SetBreakpoints({
    { threshold = 0, step = 1, rounding = Up, format = "%d" },
    { threshold = 60, step = 1, rounding = Up, format = "%dm", components = { { div = 60, step = 1, rounding = Up } } },
})
local function Icon(r)
    local f = CreateFrame("Frame", nil, r)
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAllPoints(f)
    f.tex:SetMask(MASK)
    f.cd = CreateFrame("Cooldown", nil, f)
    f.cd:SetAllPoints(f)
    f.cd:SetSwipeTexture(MASK)
    f.cd:SetCountdownFormatter(SHORT)
    return f
end
local function IconSize(f, h)
    f:SetWidth(h)
    f:SetHeight(h)
    f.cd:GetCountdownFontString():SetFont("Fonts\\ARIALN.TTF", math.max(9, math.floor(h * 0.55)), "OUTLINE")
end
local function Row(main, i)
    local r = CreateFrame("Button", nil, main)
    A.UnitButton(r)
    r:RegisterForDrag("LeftButton")
    r:SetScript("OnDragStart", function() if not main.locked then main:StartMoving() end end)
    r:SetScript("OnDragStop", function() A.Drop(main) end)
    -- A unit button's click with no verb of its own reaches this with no arguments
    -- (ClassicAPI's chained OnClick; seen in play 2026-11-23): the frame from the
    -- closure, the button from GetMouseButtonClicked.
    r:SetScript("OnClick", function()
        local e = r.entry
        if not e then return end
        if IsControlKeyDown() and e.opening then return A.FlagWatch.Announce(e) end
        if not e.guid then A.Select(e.name, nil, GetMouseButtonClicked()) end
    end)
    r:SetScript("OnEnter", function(self)
        local e = self.entry
        if e and e.opening then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Opening " .. e.opening, 1, 0.25, 0.25)
            GameTooltip:AddLine("Ctrl-click: announce in chat", 0.75, 0.75, 0.75)
            GameTooltip:Show()
        end
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r.edge = r:CreateTexture(nil, "BACKGROUND")
    r.edge:SetPoint("TOPLEFT", r, "TOPLEFT", -2, 2)
    r.edge:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 2, -2)
    A.Surface(r, 0.75)
    r.health = CreateFrame("StatusBar", nil, r)
    r.health:SetStatusBarTexture(A.GLOSS)
    r.health:SetAllPoints(r)
    r.health:SetMinMaxValues(0, 1)
    r.stripe = r.health:CreateTexture(nil, "OVERLAY")
    r.stripe:SetTexture(0.35, 1, 0.45)
    r.stripe:SetWidth(3)
    r.stripe:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
    r.stripe:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
    r.name = A.Text(r.health, 12)
    -- A hidden enemy: the spell's own icon at the left edge, the name after it.
    r.stealthIcon = r.health:CreateTexture(nil, "OVERLAY")
    r.stealthIcon:SetPoint("LEFT", r, "LEFT", 2, 0)
    r.stealthIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    r.stealthIcon:Hide()
    r.name:SetPoint("LEFT", r, "LEFT", 6, 0)
    -- Left: the name, then the health (or DEAD, STEALTH...). Right edge: the
    -- group's target count, then the yards (player's layout, 2026-11-23).
    r.status = A.Text(r.health, 12)
    r.status:SetPoint("LEFT", r.name, "RIGHT", 6, 0)
    r.yards = A.Text(r.health, 12)
    r.yards:SetPoint("RIGHT", r, "RIGHT", -4, 0)
    r.count = A.Text(r.health, 12)
    r.count:SetPoint("RIGHT", r.yards, "LEFT", -6, 0)
    r.count:SetTextColor(1, 0.6, 0.1)
    r.mark = r.health:CreateTexture(nil, "OVERLAY")
    r.mark:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    r.mark:SetPoint("LEFT", r, "RIGHT", 3, 0)
    r.trinket, r.racial = Icon(r), Icon(r)
    r.cast = CreateFrame("StatusBar", nil, r)
    r.cast:SetStatusBarTexture(A.GLOSS)
    A.Surface(r.cast, 0.7)
    r.cast.text = A.Text(r.cast, 11)
    r.cast.text:SetPoint("LEFT", r.cast, "LEFT", 3, 0)
    r.cast.icon = r.cast:CreateTexture(nil, "ARTWORK")
    r.cast.icon:SetPoint("RIGHT", r.cast, "LEFT", -1, 0)
    -- The cast bar and its icon target the caster too (a heal, an Opening at a
    -- flag): left targets, right focuses, Ctrl-click announces an Opening.
    r.castButton = CreateFrame("Button", nil, r.cast)
    r.castButton:SetPoint("TOPLEFT", r.cast.icon, "TOPLEFT", 0, 0)
    r.castButton:SetPoint("BOTTOMRIGHT", r.cast, "BOTTOMRIGHT", 0, 0)
    A.UnitButton(r.castButton)
    r.castButton:SetScript("OnClick", function()
        local e = r.entry
        if e and IsControlKeyDown() and e.opening then A.FlagWatch.Announce(e) end
    end)
    r.cast.span = C_DurationUtil.CreateDuration()
    r.cast:Hide()
    r.wave = C_DurationUtil.CreateDuration()
    r.clock = C_DurationUtil.CreateDurationTextBinding()
    r.clock:SetFontString(r.status)
    r.clock:SetDuration(r.wave)
    main.rows[i] = r
    return r
end

local function Layout(key)
    local main, s = frames[key], db.sizes[key]
    local h = s.height
    main:SetWidth(s.width)
    for i, r in ipairs(main.rows) do
        r:SetWidth(s.width)
        r:SetHeight(h)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", main, "TOPLEFT", 0, -18 - (i - 1) * (h + 3))
        for _, fs in ipairs({ r.name, r.status, r.count }) do fs:SetFont("Fonts\\ARIALN.TTF", s.text, "OUTLINE") end
        A.YardFont(r.yards, s.text + 2)
        r.cast.text:SetFont("Fonts\\ARIALN.TTF", math.max(8, s.text - 3), "OUTLINE")
        r.mark:SetWidth(h)
        r.mark:SetHeight(h)
        IconSize(r.trinket, h)
        r.stealthIcon:SetWidth(h - 4)
        r.stealthIcon:SetHeight(h - 4)
        r.stealthTex = 0 -- the name is placed again at the next draw
        r.trinket:SetPoint("RIGHT", r, "LEFT", -3, 0)
        IconSize(r.racial, h)
        r.racial:SetPoint("RIGHT", r.trinket, "LEFT", -2, 0)
        r.cast:SetWidth(s.width * 0.75)
        r.cast:SetHeight(h)
        r.cast:SetPoint("RIGHT", r.racial, "LEFT", -3, 0)
        r.cast.icon:SetWidth(h)
        r.cast.icon:SetHeight(h)
    end
end
for _, key in ipairs({ 10, 15, 40 }) do
    local main = CreateFrame("Frame", "AutoBG_TargetsMainFrame" .. key, UIParent)
    main:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -260, -200)
    main:SetHeight(18)
    A.Movable(main)
    main.title = A.Text(main, 13)
    main.title:SetPoint("TOPLEFT", main, "TOPLEFT", 0, 0)
    main.rows, main.key = {}, key
    main:Hide()
    frames[key] = main
    Layout(key)
end

-- One row from its entry: what changed is redrawn by the same function.
local GOLD, BLUE = { 1, 0.82, 0 }, { 0.25, 0.6, 1 }
-- Built once: a redraw on every health change makes no strings or tables.
local PCT, NUM = A.PCT, {}
for i = 0, 100 do NUM[i] = tostring(i) end
local REMAINING = Enum.DurationTextBindingProperty.RemainingDuration
local DEAD = { [true] = { { property = REMAINING, formatter = Bars.GUESS } },
    [false] = { { property = REMAINING, formatter = Bars.PLAIN } } }
-- A stealthed enemy out of view: how long since he was last seen ("STEALTH 12s"),
-- and how far you are from where that was ("~18 yd", lilac: a place, not him).
local Down = Enum.NumericRuleFormatRounding.Down
local AGO = C_StringUtil.CreateNumericRuleFormatter()
AGO:SetBreakpoints({
    { threshold = 0, step = 1, rounding = Down, format = "%ds" },
    { threshold = 60, step = 1, rounding = Down, format = "%dm", components = { { div = 60, step = 1, rounding = Down } } },
})
local SINCE = { { property = Enum.DurationTextBindingProperty.ElapsedDuration, formatter = AGO } }
local HIDDEN = {}
for key, text in pairs(LABEL) do HIDDEN[key] = text .. " {}" end
local LAST_TEXT = {}
local function LastText(n)
    if not LAST_TEXT[n] then LAST_TEXT[n] = "|cffb59cff~" .. n .. " yd|r" end
    return LAST_TEXT[n]
end
local TRINKET_ICON = { Horde = "Interface\\Icons\\INV_Jewelry_TrinketPVP_02", Alliance = "Interface\\Icons\\INV_Jewelry_TrinketPVP_01" }
local function RowOf(e)
    local r = e.row
    return r and r.entry == e and r or nil
end
local function Edge(e, r)
    local edge = e.guid and (e.guid == E.target and GOLD or e.guid == E.focus and BLUE)
    if edge then r.edge:SetTexture(edge[1], edge[2], edge[3]); r.edge:Show() else r.edge:Hide() end
end
DrawRow = function(e)
    local r = RowOf(e)
    if not r then return end
    local s = db.sizes[frames[Size()].key]
    local cc = e.class and RAID_CLASS_COLORS[e.class]
    local hidden = e.stealth and not e.dead
    r.health:SetStatusBarColor(cc and cc.r or 0.5, cc and cc.g or 0.5, cc and cc.b or 0.5)
    r.health:SetValue(e.dead and 0 or e.hp)
    -- Not dimmed: the icon and the label say it (the player, 2026-11-23).
    local icon = hidden and e.stealthSpell and SpellIcon(e.stealthSpell) or nil
    if r.stealthTex ~= icon then
        r.stealthTex = icon
        r.stealthIcon:SetTexture(icon)
        r.stealthIcon:SetShown(icon and true or false)
        r.name:ClearAllPoints()
        r.name:SetPoint("LEFT", r, "LEFT", icon and s.height or 6, 0)
    end
    e.short = e.short or A.StripRealm(e.name)
    r.name:SetText(s.hideRealm and e.short or e.name)
    local wave, guessed = A.NextWave()
    if e.dead and wave and not e.sample then
        r.wave:SetTimeSpan(GetTime(), wave)
        r.clock:SetTextFormat("DEAD {}", DEAD[guessed and true or false])
        r.clock:SetEnabled(true)
    elseif hidden and e.hiddenAt and not e.visible then
        r.status:SetText(LABEL[e.stealth] or e.stealth)
        r.wave:SetTimeSpan(e.hiddenAt, e.hiddenAt + 3600)
        r.clock:SetTextFormat(HIDDEN[e.stealth] or e.stealth .. " {}", SINCE)
        r.clock:SetEnabled(true)
    else
        r.clock:SetEnabled(false)
        r.status:SetText(e.dead and "DEAD" or e.feign and "|cffffd100FEIGN|r" or e.opening and "|cffff4040OPENING|r" or hidden and (LABEL[e.stealth] or e.stealth)
            or PCT[math.floor(e.hp * 100 + 0.5)] or "")
    end
    r.count:SetText(e.count and e.count > 0 and NUM[e.count] or "")
    r.yards:SetText(s.yards and not e.dead and (e.visible and A.YardText(e.yards, e.blocked)
        or not e.visible and e.lastYards and LastText(e.lastYards)) or "")
    r.stripe:SetShown(e.inRange and e.visible and true or false)
    if e.mark then SetRaidTargetIconTexture(r.mark, e.mark); r.mark:Show() else r.mark:Hide() end
    Edge(e, r)
    r.trinket.tex:SetTexture(TRINKET_ICON[A.OTHER[A.MySide()]] or TRINKET_ICON.Horde)
    -- A sweep is written when a use starts or the row shows another enemy.
    if r.trinketAt ~= e.trinketAt then
        r.trinketAt = e.trinketAt
        if e.trinketAt then r.trinket.cd:SetCooldown(e.trinketAt, 180) else r.trinket.cd:Clear() end
    end
    local racial = e.racial or (e.race and RACE[e.race])
    if racial and db.racials[RACIAL_KEY[racial]] == false then racial = nil end
    r.racial:SetShown(racial and true or false)
    if racial then r.racial.tex:SetTexture(SpellIcon(racial)) end
    -- A racial switched off has no sweep either.
    local racialAt = racial and e.racialAt or nil
    if r.racialAt ~= racialAt then
        r.racialAt = racialAt
        if racialAt then r.racial.cd:SetCooldown(racialAt, RACIAL[racial]) else r.racial.cd:Clear() end
    end
    if e.castTo and e.castTo > GetTime() and e.visible and not e.dead then
        r.cast.span:SetTimeSpan(e.castFrom, e.castTo)
        r.cast:SetTimerDuration(r.cast.span, Enum.StatusBarInterpolation.Immediate,
            e.channel and Enum.StatusBarTimerDirection.RemainingTime or Enum.StatusBarTimerDirection.ElapsedTime)
        if e.castLocked then r.cast:SetStatusBarColor(0.55, 0.55, 0.55)
        elseif e.channel then r.cast:SetStatusBarColor(0.3, 0.55, 1)
        else r.cast:SetStatusBarColor(1, 0.55, 0.1) end
        r.cast.text:SetText(e.castName)
        r.cast.icon:SetTexture(e.castIcon)
        r.cast:Show()
    else
        r.cast:Hide()
    end
    -- Bound again only when the row shows another unit, not on every redraw.
    local unit = not e.sample and e.guid or nil
    if r.bound ~= unit then
        r.bound = unit
        A.Bind(r, unit)
        A.Bind(r.castButton, unit)
    end
end

function E.Refresh(e) DrawRow(e) end

-- The frame of the size being played: rows in class, then name order.
local function ByClass(a, b)
    if (a.class or "") ~= (b.class or "") then return (a.class or "") < (b.class or "") end
    return a.name < b.name
end
local function Title()
    local main = frames[Size()]
    if not main then return end
    local alive, near = 0, 0
    for _, e in ipairs(roster) do
        if not e.dead then alive = alive + 1 end
        if e.inRange and e.visible then near = near + 1 end
    end
    main.title:SetText("Enemies " .. alive .. "/" .. #roster .. (near > 0 and "   |cff59ff72" .. near .. " in range|r" or ""))
end
E.Title = Title
Draw = function()
    E.dirty = nil
    local key = Size()
    for k, main in pairs(frames) do
        if k ~= key then main:Hide() end
    end
    local main = key and frames[key]
    if not main then return end
    table.sort(roster, ByClass)
    for i = 1, math.max(#roster, #main.rows) do
        local e, r = roster[i], main.rows[i]
        if e and not r then r = Row(main, i); Layout(key) end
        if r then r.entry = e end
        if e then e.row = r; DrawRow(e); r:Show() elseif r then r:Hide() end
    end
    main:SetHeight(18 + #roster * (db.sizes[key].height + 3))
    main:SetShown(db.sizes[key].show and #roster > 0)
    Title()
end
local function Redraw()
    if not E.dirty then E.dirty = C_Timer.NewTimer(0, Draw) end
end
function E.Layout()
    for key in pairs(frames) do Layout(key) end
    Draw()
end

-- The roster -----------------------------------------------------------------
local watch, units = CreateFrame("Frame"), CreateFrame("Frame")
local FOLLOW = { "UNIT_HEALTH", "UNIT_AURA_DELTA", "UNIT_VISIBILITY_CHANGED", "UNIT_SPELLCAST_START",
    "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_SUCCEEDED" }
local guids, regTimer = {}, nil
local function Register()
    regTimer = nil
    for i = #guids, 1, -1 do guids[i] = nil end
    for _, e in ipairs(roster) do
        if e.guid then guids[#guids + 1] = e.guid end
    end
    for _, ev in ipairs(FOLLOW) do
        if #guids > 0 then watch:RegisterGUIDEvent(ev, unpack(guids)) else watch:UnregisterGUIDEvent(ev) end
    end
end
local function Reregister()
    if not regTimer then regTimer = C_Timer.NewTimer(0, Register) end
end
local function Add(name)
    local e = { name = name, hp = 1, class = classes[name] }
    roster[#roster + 1] = e
    byName[name] = e
    Redraw()
    return e
end
local function Remove(name)
    local e = byName[name]
    if not e then return end
    byName[name] = nil
    if e.guid then byGUID[e.guid] = nil end
    for i = 1, #roster do
        if roster[i] == e then
            for j = i, #roster do roster[j] = roster[j + 1] end
            break
        end
    end
    Reregister()
    Redraw()
end

-- GAP: no event when the other team's roster changes; the scoreboard is asked on
-- our own events. A DLL should fire when the battleground's player list changes.
local asked = false
-- The window's tabs filter the list by faction (WorldStateFrame.lua:650): every row is asked for.
function E.AskScores()
    SetBattlefieldScoreFaction(nil)
    RequestBattlefieldScoreData()
end
local function RequestScores()
    if asked or not A.zone.pvp then return end
    asked = true
    C_Timer.After(1, function() asked = false; E.AskScores() end)
end
-- The scoreboard: 9 returns, the class an English name (KP-39; WorldStateFrame.lua:477).
local listed, Sight = {}, nil
local function ReadScores()
    if E.preview then return end
    local enemy = A.MySide() == "Horde" and 1 or 0
    local me = UnitName("player")
    table.wipe(listed)
    for i = 1, GetNumBattlefieldScores() do
        local name, _, _, _, _, faction, _, race, class = GetBattlefieldScore(i)
        if name and name ~= "" then
            classes[name] = class and string.upper(class) or nil
            if faction == enemy and name ~= me and not A.InGroup(name) and not friendly[name] then
                local e = byName[name] or Add(name)
                e.class, e.race, e.scored = classes[name], e.race or race, true
                listed[name] = true
                -- In view already: his GUID, so the row follows him.
                if not e.guid then
                    local unit = A.Token(name)
                    if unit and UnitIsPlayer(unit) then Sight(unit) end
                end
            end
        end
    end
    for i = #roster, 1, -1 do
        local e = roster[i]
        if e.scored and not listed[e.name] and not e.seen then Remove(e.name) end
    end
    Redraw()
end

-- Where an enemy who can hide was last in view (### UnitPosition(unit), the
-- C_PlayerInfo one: SuperWoW's global has another shape). Kept a minute.
local POS, LAST_FOR = C_PlayerInfo.UnitPosition, 60
local function Spot(e, unit)
    local y, x = POS(unit)
    if y then e.lastX, e.lastY = x, y end
end
local InView
-- Gap 1's look: the 80-yard stripe and the yards, a text written only when the
-- whole yard changes; the yards to a hidden enemy's last spot.
local function Range()
    local changed, aged = false, false
    local show = db.sizes[frames[Size()].key].yards
    local now, py, px = GetTime(), nil, nil
    for _, e in ipairs(roster) do
        if e.sample then
        elseif e.visible then
            if e.guid and e.stealth then Spot(e, e.guid) end
        elseif e.lastX and e.hiddenAt then
            local n
            if now - e.hiddenAt < LAST_FOR then
                if not py then py, px = POS("player") end
                if py then
                    local dx, dy = px - e.lastX, py - e.lastY
                    n = math.floor(math.sqrt(dx * dx + dy * dy) + 0.5)
                end
            else
                e.lastX, aged = nil, true
            end
            if n ~= e.lastYards then
                e.lastYards = n
                local r = show and RowOf(e)
                if r then r.yards:SetText(n and LastText(n) or "") end
            end
        end
        local yards = e.visible and e.guid and A.Yards(e.guid)
        if e.sample then yards = e.yards end -- the preview's made-up distance stays
        local n = yards and math.floor(yards + 0.5) or nil
        local near = n and n <= 80 or nil
        local blocked = e.blocked or false
        if not n or e.sample then blocked = false
        elseif A.lookTick % 5 == 0 or e.blocked == nil then blocked = A.Blocked(e.guid) end
        if near ~= e.inRange then e.inRange = near; changed = true; DrawRow(e) end
        if n ~= e.yards or blocked ~= e.blocked then
            e.yards, e.blocked = n, blocked
            local r = show and not e.dead and e.visible and RowOf(e)
            if r then r.yards:SetText(A.YardText(n, blocked)) end
        end
    end
    if changed then Title() end
    if aged then InView() end
end
InView = function()
    local now = GetTime()
    for _, e in ipairs(roster) do
        if e.visible or e.lastX and e.hiddenAt and now - e.hiddenAt < LAST_FOR then
            return A.WatchDistance("enemies", Range)
        end
    end
    A.WatchDistance("enemies", nil)
end

local function Health(e)
    local g = e.guid
    local max = UnitHealthMax(g)
    if max and max > 0 then e.hp = UnitHealth(g) / max end
    -- A hunter feigning death is alive (### UnitIsFeignDeath(unit); UNVERIFIED on
    -- OctoWoW): FEIGN on his row, no wave countdown, still counted.
    local feign = UnitIsFeignDeath(g) and true or nil
    local dead = not feign and UnitIsDeadOrGhost(g) and true or nil
    if dead == e.dead and feign == e.feign then
        local r = RowOf(e)
        if r then
            r.health:SetValue(e.dead and 0 or e.hp)
            if not (e.dead or e.feign or e.opening or e.stealth) then r.status:SetText(PCT[math.floor(e.hp * 100 + 0.5)] or "") end
        end
        return
    end
    e.feign = feign
    if dead and not e.dead then
        e.dead, e.castTo, e.stealth, e.hiddenAt, e.lastX, e.lastYards = true, nil, nil, nil, nil, nil
        E.WaveMoved()
    elseif not dead and e.dead then
        e.dead = nil
    end
    DrawRow(e)
    Title()
end
local AllAuras
local function Learn(e, guid)
    if e.guid then byGUID[e.guid] = nil end
    e.guid, byGUID[guid] = guid, e
    e.visible = UnitIsVisible(guid) and true or nil
    if e.visible then Health(e); AllAuras(e) end
    e.mark = GetRaidTargetIndex(guid)
    A.Carriers.Learn(e.name, guid)
    Reregister()
    InView()
    DrawRow(e)
end
-- A unit seen through a token: a hostile player joins, a teammate of the other
-- faction leaves (mixed teams).
Sight = function(unit)
    if not UnitExists(unit) then return end
    if not UnitIsPlayer(unit) then return end
    local name = UnitName(unit)
    if not name or name == UNKNOWNOBJECT then return end
    -- A corpse or a ghost cannot be attacked either: only a living player who
    -- cannot be attacked is a teammate (a killed carrier left the frames until he
    -- was seen alive again, 2026-11-24).
    if not UnitCanAttack("player", unit) then
        if byName[name] and not UnitIsDeadOrGhost(unit) then friendly[name] = true; Remove(name) end
        return
    end
    friendly[name] = nil
    local e = byName[name]
    if not e then
        e = Add(name)
        RequestScores()
    end
    e.seen = true
    e.class = e.class or select(2, UnitClass(unit))
    e.race = e.race or select(2, UnitRace(unit))
    local guid = UnitGUID(unit)
    if guid and e.guid ~= guid then Learn(e, guid) end
end
E.Sight = Sight
-- Following by GUID -------------------------------------------------------------
local function Stealth(e, label, id, seconds, spell)
    e.stealth, e.stealthID, e.stealthSpell, e.stealthSeen = label, id, spell or e.stealthSpell, GetTime()
    if e.stealthTimer then e.stealthTimer:Cancel(); e.stealthTimer = nil end
    if seconds then
        e.stealthTimer = C_Timer.NewTimer(seconds, function() e.stealthTimer = nil; e.stealth = nil; DrawRow(e) end)
    end
    if e.visible and e.guid then Spot(e, e.guid) end
    DrawRow(e)
    if e.visible then A.StealthWarn(e.name, e.guid, label, e.class, true) end
end
local function Unstealth(e)
    if e.stealthTimer then e.stealthTimer:Cancel(); e.stealthTimer = nil end
    e.stealth, e.stealthID, e.stealthSpell = nil, nil, nil
    DrawRow(e)
end
local function Trinket(e)
    local now = GetTime()
    if e.trinketAt and now - e.trinketAt < 5 then return end -- the aura and the cast report one use
    e.trinketAt = now
    DrawRow(e)
end
-- Coming into view: the auras read once.
local slots = {}
AllAuras = function(e)
    local found, foundID
    C_UnitAuras.GetAuraSlots(e.guid, "HELPFUL", nil, nil, slots)
    for i = 1, slots.n do
        local spell, _, _, _, _, _, instance = select(10, C_UnitAuras.UnitAuraBySlot(e.guid, slots[i]))
        if STEALTH[spell] then found, foundID = spell, instance end
        if spell then A.Carriers.Aura(e.name, e.guid, spell, instance) end
    end
    if found then Stealth(e, STEALTH[found], foundID, TIMED[found], found)
    elseif e.stealth then Unstealth(e) end
end
local buf = {}
local function Auras(e, info)
    if info.isFullUpdate then return AllAuras(e) end
    local added, removed = info.addedAuraInstanceIDs, info.removedAuraInstanceIDs
    for i = 1, added and #added or 0 do
        local a = C_UnitAuras.GetAuraDataByAuraInstanceID(e.guid, added[i], buf)
        if a then
            if STEALTH[a.spellId] then Stealth(e, STEALTH[a.spellId], added[i], TIMED[a.spellId], a.spellId) end
            if TRINKET[a.spellId] then Trinket(e) end
            A.Carriers.Aura(e.name, e.guid, a.spellId, added[i])
        end
    end
    for i = 1, removed and #removed or 0 do
        if removed[i] == e.stealthID then Unstealth(e) end
    end
    -- Hidden by a cast whose aura never reached us: an aura going is the time to look.
    if removed and e.stealth and not e.stealthID then AllAuras(e) end
end
local function CastEnd(e)
    e.castTimer = nil
    DrawRow(e)
end
local function Cast(e, channel)
    local name, icon, start, finish, locked, _
    if channel then
        name, _, icon, start, finish, _, locked = C_Spell.UnitChannelInfo(e.guid)
    else
        name, _, icon, start, finish, _, _, locked = C_Spell.UnitCastingInfo(e.guid)
    end
    if not (name and start and finish) then return end
    e.castName, e.castIcon, e.castFrom, e.castTo, e.channel, e.castLocked = name, icon, start / 1000, finish / 1000, channel, locked
    if not channel and string.find(name, "^Opening") then A.FlagWatch.Opening(e) end
    -- A cast with no stop leaves at its end.
    if e.castTimer then e.castTimer:Cancel() end
    e.castDone = e.castDone or function() CastEnd(e) end
    e.castTimer = C_Timer.NewTimer(math.max(0, e.castTo - GetTime()) + 0.1, e.castDone)
    DrawRow(e)
end
local function StopCast(e)
    e.castTo = nil
    if e.opening then A.FlagWatch.Stopped(e) end
    DrawRow(e)
end

local HANDLE = {
    UNIT_HEALTH = Health,
    UNIT_AURA_DELTA = Auras,
    UNIT_VISIBILITY_CHANGED = function(e, visible)
        e.visible = visible and true or nil
        if visible then
            e.hiddenAt, e.lastYards = nil, nil
            Health(e)
            AllAuras(e)
            A.FlagWatch.Appeared(e)
            DrawRow(e)
        else
            e.castTo, e.inRange, e.yards = nil, nil, nil
            if e.guid then Spot(e, e.guid) end
            if e.stealth and not e.dead then e.hiddenAt = GetTime() end
            A.FlagWatch.Gone(e)
            DrawRow(e)
        end
        InView()
        Title()
    end,
    UNIT_SPELLCAST_START = function(e) Cast(e, false) end,
    UNIT_SPELLCAST_CHANNEL_START = function(e) Cast(e, true) end,
    UNIT_SPELLCAST_STOP = StopCast,
    UNIT_SPELLCAST_INTERRUPTED = StopCast,
    UNIT_SPELLCAST_CHANNEL_STOP = StopCast,
    UNIT_SPELLCAST_SUCCEEDED = function(e, _, spell)
        if HIDES[spell] then Stealth(e, HIDES[spell], e.stealthID, TIMED[spell], spell) end
        if TRINKET[spell] then Trinket(e) end
        if RACIAL[spell] then e.racial, e.racialAt = spell, GetTime(); DrawRow(e) end
    end,
}
watch:SetScript("OnEvent", function(_, event, guid, a2, a3)
    local e = byGUID[guid]
    if e then HANDLE[event](e, a2, a3) end
end)

-- The dead: back at the wave unless the body still lies in view; a guessed wave
-- revives nobody.
local waveTimer
local function AtWave()
    waveTimer = nil
    for _, e in ipairs(roster) do
        if e.dead and not E.guessedWave and not (e.guid and UnitIsVisible(e.guid)) then
            e.dead, e.hp = nil, 1
            DrawRow(e)
        end
    end
    E.WaveMoved()
    Title()
end
function E.WaveMoved()
    if waveTimer then waveTimer:Cancel(); waveTimer = nil end
    local at, guessed = A.NextWave()
    local any = false
    for _, e in ipairs(roster) do
        if e.dead then any = true; DrawRow(e) end
    end
    if any and at then
        E.guessedWave = guessed
        waveTimer = C_Timer.NewTimer(at - GetTime(), AtWave)
    end
end

-- Who your group targets: one count per frame.
local GROUP, TARGET = {}, {}
for i = 1, 4 do GROUP[#GROUP + 1] = "party" .. i end
for i = 1, 40 do GROUP[#GROUP + 1] = "raid" .. i end
for i, u in ipairs(GROUP) do TARGET[u] = u .. "target" end
local counts, countTimer = {}, nil
local function Count()
    countTimer = nil
    table.wipe(counts)
    local raid = GetNumRaidMembers() > 0
    for i = raid and 5 or 1, raid and #GROUP or 4 do
        local g = UnitGUID(TARGET[GROUP[i]])
        if g then counts[g] = (counts[g] or 0) + 1 end
    end
    local mine = UnitGUID("target")
    if mine and not raid then counts[mine] = (counts[mine] or 0) + 1 end
    for _, e in ipairs(roster) do
        local n = e.guid and counts[e.guid] or 0
        if n ~= (e.count or 0) then e.count = n; DrawRow(e) end
    end
end
local function Recount()
    if not countTimer then countTimer = C_Timer.NewTimer(0, Count) end
end
local function Selection()
    E.target, E.focus = UnitGUID("target"), UnitGUID("focus")
    for _, e in ipairs(roster) do
        local r = RowOf(e)
        if r then Edge(e, r) end
    end
end

units:SetScript("OnEvent", function(_, event, a1)
    if event == "UPDATE_BATTLEFIELD_SCORE" then
        ReadScores()
        A.Queue.CheckEnd()
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        Sight(a1)
    elseif event == "PLAYER_TARGET_CHANGED" then
        Sight("target")
        Selection()
        Recount()
    elseif event == "PLAYER_FOCUS_CHANGED" then
        Sight("focus")
        Selection()
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        Sight("mouseover")
    elseif event == "UNIT_TARGET" then
        Sight(TARGET[a1] or a1)
        Recount()
    elseif event == "UNIT_VISIBILITY_CHANGED" then
        Recount()
    elseif event == "RAID_TARGET_UPDATE" then
        for _, e in ipairs(roster) do
            if e.guid then e.mark = GetRaidTargetIndex(e.guid); DrawRow(e) end
        end
    elseif event == "GROUP_ROSTER_UPDATE" then
        for i = #roster, 1, -1 do
            if A.InGroup(roster[i].name) then Remove(roster[i].name) end
        end
        RequestScores()
        Recount()
    elseif event == "PLAYER_IN_COMBAT_CHANGED" then
        for _, main in pairs(frames) do main.locked = a1 and true or nil end
    end
end)
local TOKENS = { "UPDATE_BATTLEFIELD_SCORE", "NAME_PLATE_UNIT_ADDED", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED",
    "UPDATE_MOUSEOVER_UNIT", "RAID_TARGET_UPDATE", "GROUP_ROSTER_UPDATE", "PLAYER_IN_COMBAT_CHANGED" }

-- The scoreboard's names in class colour, the realm left off. The stock update
-- writes every name each time it runs (WorldStateFrame.lua:493), so each is
-- written again after it; the coloured text is made once per name.
local colored, regions = {}, {}
hooksecurefunc("WorldStateScoreFrame_Update", function()
    A.Queue.CheckEnd()
    local offset = FauxScrollFrame_GetOffset(WorldStateScoreScrollFrame)
    for i = 1, MAX_WORLDSTATE_SCORE_BUTTONS do
        local name, _, _, _, _, _, _, _, class = GetBattlefieldScore(offset + i)
        regions[i] = regions[i] or _G["WorldStateScoreButton" .. i .. "NameButtonName"]
        if name and name ~= "" and regions[i] then
            local text = colored[name]
            if not text then
                local cc = class and RAID_CLASS_COLORS[string.upper(class)]
                text = A.StripRealm(name)
                if cc then
                    text = string.format("|cff%02x%02x%02x%s|r", cc.r * 255, cc.g * 255, cc.b * 255, text)
                    colored[name] = text
                end
            end
            regions[i]:SetText(text)
        end
    end
end)

-- A match begins and ends at a loading screen.
local function Reset()
    for i = #roster, 1, -1 do roster[i] = nil end
    for _, t in ipairs({ byName, byGUID, friendly, classes, colored, counts }) do
        table.wipe(t)
    end
    if waveTimer then waveTimer:Cancel(); waveTimer = nil end
end
-- What the zone needs: the token events and the scoreboard in a match, the
-- registrations always. Set up again when the zone is read anew, never reset
-- in the middle of a match (only a loading screen does that).
local setFor
A.OnZone(function(fresh)
    local on = A.zone.pvp and not A.zone.arena
    local state = on and "bg" or "none"
    if fresh then Reset() elseif state == setFor then return end
    setFor = state
    for _, ev in ipairs(TOKENS) do
        if on then units:RegisterEvent(ev) else units:UnregisterEvent(ev) end
    end
    if on then
        units:RegisterUnitEvent("UNIT_TARGET", unpack(GROUP))
        units:RegisterUnitEvent("UNIT_VISIBILITY_CHANGED", unpack(GROUP))
        E.AskScores()
    else
        units:UnregisterEvent("UNIT_TARGET")
        units:UnregisterEvent("UNIT_VISIBILITY_CHANGED")
    end
    Register()
    InView()
    Draw()
end)

-- The preview: made-up enemies on the frame of the size the page edits.
local SAMPLES = { { "Brightblade", "WARRIOR", nil, "Human" }, { "Morwenna", "PRIEST", nil, "Undead" },
    { "Thandril-NZ", "ROGUE", "STEALTH", "NightElf" }, { "Ashka", "MAGE", nil, "Gnome" }, { "Durnhal", "PALADIN", nil, "Dwarf" },
    { "Velyra", "DRUID", nil, "NightElf" }, { "Korvash", "HUNTER", nil, "Orc" }, { "Syl", "WARLOCK", nil, "Undead" },
    { "Grimtusk", "SHAMAN", nil, "Tauren" }, { "Elowen", "PRIEST", nil, "Human" } }
E.editSize = 10
function E.Preview(on)
    E.preview = on
    Reset()
    if on then
        local n = math.min(E.editSize, 40)
        for i = 1, n do
            local s = SAMPLES[(i - 1) % #SAMPLES + 1]
            local e = Add(i > #SAMPLES and s[1] .. i or s[1])
            e.class, e.stealth, e.race, e.sample, e.hp = s[2], s[3], s[4], true, 1 - (i % 4) * 0.2
            e.stealthSpell = s[3] and 1787 or nil
            e.dead, e.count, e.inRange, e.visible = i == 4 or nil, i == 2 and 3 or nil, i < 6 or nil, true
            e.yards = 14 + i * 13
        end
    end
    Draw()
end
