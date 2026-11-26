-- AutoBG objectives: base, tower, mine and flag timers, the game start, the
-- spirit healer wave and the Arathi Basin estimate. The numbers are OctoWoW's,
-- confirmed in play (servers/octowow.md): a base 60 s, an Alterac tower,
-- bunker or graveyard 5 min, a mine 5 min from "has taken", a Warsong flag back
-- 23 s after a capture.
local _, A = ...
local db = A.db
local O = {}
A.Objectives = O
local Bars = A.Bars
local NODES = "Interface\\AddOns\\AutoBG\\Textures\\Nodes\\"
A.COLORS = { Alliance = { 0.2, 0.45, 1 }, Horde = { 0.9, 0.15, 0.15 } }
local OTHER = A.OTHER

-- Each base and its picture.
local AB = { ["Gold Mine"] = "GoldMine", ["Lumber Mill"] = "LumberMill", Blacksmith = "Blacksmith", Farm = "Farm", Stables = "Stables" }
local AB_SHORT = { mine = "Gold Mine", mill = "Lumber Mill", smith = "Blacksmith", stable = "Stables", farm = "Farm" }
local AV = {}
for _, n in ipairs({ "Iceblood Tower", "Tower Point", "East Frostwolf Tower", "West Frostwolf Tower", "Stonehearth Bunker",
    "Icewing Bunker", "Dun Baldar North Bunker", "Dun Baldar South Bunker" }) do AV[n] = "Tower" end
for _, n in ipairs({ "Frostwolf Relief Hut", "Snowfall Graveyard", "Stormpike Graveyard", "Iceblood Graveyard",
    "Frostwolf Graveyard", "Stonehearth Graveyard", "Stormpike Aid Station" }) do AV[n] = "Grave" end
AV["Irondeep Mine"], AV["Coldtooth Mine"] = "Mine", "Mine"
function A.NodeIcon(node, faction)
    local kind = AB[node] or AV[node]
    return kind and NODES .. kind .. "_" .. (faction or "Neutral")
end

local start = Bars.Group("AutoBG_StartTimerFrame", 1, 0, -60)
local wave = Bars.Group("AutoBG_RespawnFrame", 1, 0, -100, { 0.85, 0.85, 0.5 })
local abBars = Bars.Group("AutoBG_NodeFrame", 5, 220, -100)
local avBars = Bars.Group("AutoBG_AVNodeFrame", 10, 220, -150)
local wsgBars = Bars.Group("AutoBG_WSGFlagFrame", 2, -110, -150)
O.abBars = abBars
A.owner = {} -- base -> the side that holds or assaults it (the flag watch)

local function Find(lower, list, short)
    for node in pairs(list) do
        if string.find(lower, string.lower(node), 1, true) then return node end
    end
    for word, node in pairs(short or {}) do
        if string.find(lower, word, 1, true) then return node end
    end
end

-- Seconds in a start line: "1 minute until the battle ... begins", "begins in 30 seconds".
local WORDS = { one = 1, two = 2, fifteen = 15, thirty = 30 }
local function Countdown(lower)
    local n, unit = string.match(lower, "(%w+)%s+(m)inute")
    if not n then n, unit = string.match(lower, "(%w+)%s+(s)econd") end
    n = n and (tonumber(n) or WORDS[n])
    return n and (unit == "m" and n * 60 or n)
end

-- GAP: no battleground objective event; the server's English lines are read for
-- the base, the side, the player and the moment. A DLL should give an objective
-- event (node, state, side, player) or the map POI state with its time left.
local function ReadLine(msg, event)
    local lower = string.lower(msg)
    local zone = A.zone.match
    local player = string.match(msg, "^(%S+) claims") or string.match(msg, "^(%S+) has assaulted")
        or string.match(msg, "^(%S+) has defended")
    if player then lower = string.sub(lower, #player + 1) end -- "Hordeling has assaulted the Farm!"
    local faction = string.find(lower, "horde", 1, true) and "Horde" or string.find(lower, "alliance", 1, true) and "Alliance"
        or event == "CHAT_MSG_BG_SYSTEM_HORDE" and "Horde" or event == "CHAT_MSG_BG_SYSTEM_ALLIANCE" and "Alliance"
        or player and (A.SideOf(player) or OTHER[A.MySide()])
    if player and faction and not string.find(lower, "defended", 1, true) then A.NoteSide(player, faction) end

    local secs = (string.find(lower, "begin", 1, true) or string.find(lower, "start", 1, true)) and Countdown(lower)
    if secs then
        start:Start("start", "Game starts", secs, "Interface\\Icons\\INV_Misc_PocketWatch_01", { say = "Game starts in" })
    elseif string.find(lower, "begun", 1, true) or string.find(lower, "let the battle begin", 1, true) then
        start:Stop("start")
    end

    if zone == "Arathi Basin" then
        local node = Find(lower, AB, AB_SHORT)
        if not node then return end
        if A.FlagWatch then A.FlagWatch.Line(node, lower, player) end
        if string.find(lower, "claims", 1, true) or string.find(lower, "assaulted", 1, true) then
            A.owner[node] = faction
            abBars:Start(node, node, 60, A.NodeIcon(node, faction), { faction = faction, color = A.COLORS[faction],
                say = node .. " (" .. (faction or "?") .. ") captured in" })
        elseif string.find(lower, "taken", 1, true) or string.find(lower, "defended", 1, true) or string.find(lower, "captured", 1, true) then
            A.owner[node] = faction
            abBars:Stop(node)
        end
        O.Estimate()
    elseif zone == "Alterac Valley" then
        local node = Find(lower, AV)
        if not node then return end
        local opts = { color = A.COLORS[faction], faction = faction, say = node .. " (" .. (faction or "?") .. ")" .. (AV[node] == "Mine" and " in" or " captured in") }
        if AV[node] == "Mine" then
            if string.find(lower, "has taken", 1, true) then avBars:Start(node, node, 300, A.NodeIcon(node, faction), opts) end
        elseif string.find(lower, "claims", 1, true) or string.find(lower, "assaulted", 1, true) or string.find(lower, "under attack", 1, true) then
            avBars:Start(node, node, 300, A.NodeIcon(node, faction), opts)
        elseif string.find(lower, "taken", 1, true) or string.find(lower, "defended", 1, true) or string.find(lower, "destroyed", 1, true) or string.find(lower, "captured", 1, true) then
            avBars:Stop(node)
        end
    elseif zone == "Warsong Gulch" then
        for _, flag in ipairs({ "Alliance", "Horde" }) do
            if string.find(lower, "captured the " .. string.lower(flag) .. " flag", 1, true) then
                wsgBars:Start(flag, flag .. " flag", 23, "Interface\\Icons\\INV_BannerPVP_0" .. (flag == "Horde" and 1 or 2),
                    { color = A.COLORS[flag], say = flag .. " flag back in" })
            end
        end
        A.Carriers.Line(msg)
    end
end

-- The spirit healer wave: one for the whole battleground, every 30 s or so
-- (as on MaNGOS cores, whose clock starts when the battleground is made, not
-- when you enter; UNVERIFIED on OctoWoW). Nothing shows until a wave is seen.
-- Exact: the server's own countdown while you stand dead at a healer (as the
-- stock popup reads it). Rough ("~"): a dead group member alive again, which
-- may lag or be a priest's resurrection; it never moves an exact wave. Exact
-- readings measure the period, so a server whose wave comes a little late each
-- time is followed. Not used: 22012 Spirit Heal seen cast by spirit guides
-- (each guide channels 22011 on a 30 s rhythm of its own; in play 2026-11-23 it
-- put the bar 16 s off the server's countdown), and 24171 Resurrection Impact
-- Visual (cast on ghosts, whom the living do not see).
local W = {}
local function NewMatch() W.at, W.exact, W.first, W.period = nil, false, nil, 30 end
NewMatch()
function A.NextWave()
    if not W.at then return nil end
    return W.at + W.period * math.floor((GetTime() - W.at) / W.period + 1), not W.exact
end
local function ShowWave()
    if not (A.zone.pvp and not A.zone.arena and W.at) then return wave:Clear() end
    local at, guessed = A.NextWave()
    wave:Start("wave", "Spirit healer", at - GetTime(), "Interface\\Icons\\Spell_Holy_Resurrection",
        { guess = guessed, onEnd = ShowWave, say = "Ress in" })
end
function A.WaveSeen(at, exact)
    if not (A.zone.pvp and not A.zone.arena) or (W.exact and not exact) then return end
    if exact then
        local k = W.first and math.floor((at - W.first) / W.period + 0.5) or 0
        if not W.first or k > 0 and math.abs(at - (W.first + k * W.period)) > 1.5 then
            W.first, W.period = at, 30 -- the first, or one that disagrees: measure again from here
        elseif k > 0 then
            W.period = (at - W.first) / k
        end
    end
    if exact and not W.exact then A.Objectives.RoughDone() end
    W.at, W.exact = at, exact
    ShowWave()
    A.Enemies.WaveMoved()
end
-- UNVERIFIED: whole seconds or not; a reading of 0 (the answer not in yet) is read again once.
local function ReadHealer(again)
    local left = GetAreaSpiritHealerTime()
    if left and left > 0 then A.WaveSeen(GetTime() + left, true)
    elseif not again then C_Timer.After(0.5, function() ReadHealer(true) end) end
end

-- The Arathi Basin estimate: who wins and when if the bases stay as they are and
-- the assaults under way succeed; the ticks are learned per base count.
-- UNVERIFIED: the vanilla ticks stand in, marked "~", for a count not seen.
local VANILLA = { { gain = 10, every = 12 }, { gain = 10, every = 9 }, { gain = 10, every = 6 }, { gain = 10, every = 3 }, { gain = 30, every = 1 } }
local function Rate(bases)
    local t = db.ticks[bases] or VANILLA[bases]
    return t and t.gain / t.every or 0
end
local function Finish(res, rate) return rate > 0 and (2000 - res) / rate or 1e9 end
local seen = { {}, {} }
local function Learn(s, res, bases, now)
    if s.bases ~= bases then s.bases, s.since = bases, now end
    if s.res == res then return end
    local gain, every = s.res and res - s.res, s.at and now - s.at
    if gain and gain > 0 and every >= 1 and every <= 30 and bases > 0 and s.since <= s.at then
        local t = db.ticks[bases]
        if t and t.gain == gain then
            -- A late tick moves the average a little instead of replacing it.
            t.every = math.floor((t.every * t.n + every) / (t.n + 1) * 100 + 0.5) / 100
            t.n = math.min(t.n + 1, 10)
        else
            db.ticks[bases] = { gain = gain, every = math.floor(every + 0.5), n = 1 }
        end
    end
    s.res, s.at = res, now
end

-- The estimate, small as the old one the players liked (2026-11-23): the verdict
-- and its clock over the bases to hold or take, in gold; the final scores in
-- their own column, Alliance blue over Horde red as the score display stacks them.
local est = CreateFrame("Button", "AutoBG_ABProjectionFrame", UIParent)
est:SetWidth(126)
est:SetHeight(34)
est:SetPoint("TOP", UIParent, "TOP", -160, -25)
A.Movable(est)
local edge = est:CreateTexture(nil, "BACKGROUND")
edge:SetAllPoints(est)
edge:SetTexture(0, 0, 0, 0.85)
local back = est:CreateTexture(nil, "BORDER")
back:SetPoint("TOPLEFT", est, "TOPLEFT", 1, -1)
back:SetPoint("BOTTOMRIGHT", est, "BOTTOMRIGHT", -1, 1)
back:SetTexture(0.06, 0.06, 0.07, 0.8)
est.verdict = A.Text(est, 14)
est.verdict:SetPoint("LEFT", est, "LEFT", 6, 7)
est.advice = A.Text(est, 13)
est.advice:SetPoint("LEFT", est, "LEFT", 6, -8)
est.advice:SetTextColor(1, 0.82, 0)
local rule = est:CreateTexture(nil, "ARTWORK")
rule:SetTexture(1, 1, 1, 0.12)
rule:SetWidth(1)
rule:SetPoint("TOP", est, "TOPRIGHT", -41, -5)
rule:SetPoint("BOTTOM", est, "BOTTOMRIGHT", -41, 5)
est.side = {}
for i, faction in ipairs({ "Alliance", "Horde" }) do
    local fs = A.Text(est, 13)
    fs:SetPoint("RIGHT", est, "RIGHT", -6, i == 1 and 7 or -8)
    fs:SetTextColor(faction == "Alliance" and 0.38 or 1, faction == "Alliance" and 0.69 or 0.38, faction == "Alliance" and 1 or 0.38)
    est.side[faction] = fs
end
est:SetScript("OnEnter", function()
    GameTooltip:SetOwner(est, "ANCHOR_RIGHT")
    GameTooltip:SetText("Arathi Basin estimate", 1, 1, 1)
    GameTooltip:AddLine("Who wins and when, if the bases stay as they are and the assaults under way succeed.", 0.9, 0.9, 0.9, 1)
    GameTooltip:AddLine("Right: the final scores, Alliance in blue, Horde in red.", 0.9, 0.9, 0.9, 1)
    GameTooltip:AddLine("~ : a tick not seen yet in play, so a guess.", 0.9, 0.9, 0.9, 1)
    GameTooltip:AddLine("Ctrl-click: announce in chat", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end)
est:SetScript("OnLeave", function() GameTooltip:Hide() end)
est.span = C_DurationUtil.CreateDuration()
est.clock = C_DurationUtil.CreateDurationTextBinding()
est.clock:SetFontString(est.verdict)
est.clock:SetDuration(est.span)
est:Hide()
local REMAINING = Enum.DurationTextBindingProperty.RemainingDuration
-- Ctrl-click: "Win in 03:45", "Loss in about 03:45" while a tick is a guess,
-- "Too close to call at 03:45" (the old addon's words, which players know).
est:SetScript("OnClick", function()
    if not (IsControlKeyDown() and est.word) then return end
    local left = math.floor(est.span:GetRemainingDuration())
    local clock = (est.guess and "about " or "") .. string.format("%02d:%02d", math.floor(left / 60), left % 60)
    A.Announce(est.word == "Tie" and "Too close to call at " .. clock or est.word .. " in " .. clock)
end)

-- The verdict word, its end, the final scores and the advice.
local function Card(word, guess, eta, fa, fh, advice)
    est.word, est.guess = word, guess
    est.span:SetTimeSpan(GetTime(), GetTime() + eta)
    est.clock:SetTextFormat((word == "Tie" and "|cffffd100" or word == "Win" and "|cff59ff72" or "|cffff5555") .. word .. "|r {}",
        { { property = REMAINING, formatter = guess and Bars.GUESS or Bars.PLAIN } })
    est.clock:SetEnabled(true)
    est.side.Alliance:SetText(tostring(fa))
    est.side.Horde:SetText(tostring(fh))
    est.advice:SetText(advice)
    est:Show()
end

local caps, res, bases = {}, {}, {}
local function ByTime(a, b) return a.finish < b.finish end
local function Estimate()
    O.pending = nil
    -- A wake asked for just before a loading screen can come after it.
    if A.zone.match ~= "Arathi Basin" then return est:Hide() end
    res[1], res[2], bases[1], bases[2] = nil, nil, 0, 0
    for i = 1, GetNumWorldStateUI() do
        local _, text = GetWorldStateUIInfo(i) -- state, text, icon... (WorldStateFrame.lua:39)
        local r = text and string.match(text, "(%d+)%s*/%s*2000")
        if r then
            res[#res + 1] = tonumber(r)
            bases[#res] = tonumber(string.match(text, "Bases:%s*(%d+)") or 0)
        end
    end
    local a, h = res[1], res[2]
    if not (a and h) then return est:Hide() end
    local now = GetTime()
    Learn(seen[1], a, bases[1], now)
    Learn(seen[2], h, bases[2], now)
    for i = #caps, 1, -1 do caps[i] = nil end
    for _, item in pairs(abBars.items) do
        if item.faction and item.finish > now then caps[#caps + 1] = item end
    end
    table.sort(caps, ByTime)
    local t, ab, hb = 0, bases[1], bases[2]
    for _, cap in ipairs(caps) do
        local ar, hr, dt = Rate(ab), Rate(hb), cap.finish - now - t
        if Finish(a, ar) <= dt or Finish(h, hr) <= dt then break end
        a, h, t = a + ar * dt, h + hr * dt, cap.finish - now
        if cap.faction == "Alliance" then ab = math.min(5 - hb, ab + 1) else hb = math.min(5 - ab, hb + 1) end
    end
    local ar, hr = Rate(ab), Rate(hb)
    local ta, th = t + Finish(a, ar), t + Finish(h, hr)
    if ta >= 1e9 and th >= 1e9 then return est:Hide() end
    local mine = A.MySide()
    local eta = math.min(ta, th)
    local winner = ta <= th and "Alliance" or "Horde"
    local fa = winner == "Alliance" and 2000 or math.floor(math.min(2000, a + ar * (eta - t)) / 10) * 10
    local fh = winner == "Horde" and 2000 or math.floor(math.min(2000, h + hr * (eta - t)) / 10) * 10
    local tie = math.abs(ta - th) <= 12
    local win = not tie and winner == mine
    local myRes, theirRes = res[mine == "Alliance" and 1 or 2], res[mine == "Alliance" and 2 or 1]
    local need = 5
    for b = 1, 5 do
        if Finish(myRes, Rate(b)) < Finish(theirRes, Rate(5 - b)) then need = b; break end
    end
    local guess = (bases[1] > 0 and not db.ticks[bases[1]]) or (bases[2] > 0 and not db.ticks[bases[2]])
    Card(tie and "Tie" or win and "Win" or "Loss", guess, eta, fa, fh,
        tie and "Too close" or (win and "Hold " or "Need ") .. need .. (need == 1 and " base" or " bases"))
end
-- One estimate per frame, however many world states change in it.
function O.Estimate()
    if O.pending or A.zone.match ~= "Arathi Basin" then return end
    O.pending = C_Timer.NewTimer(0, Estimate)
end

-- Chat lines, world states and the healers are listened to only inside a battleground.
local MATCH = { "CHAT_MSG_BG_SYSTEM_NEUTRAL", "CHAT_MSG_BG_SYSTEM_ALLIANCE", "CHAT_MSG_BG_SYSTEM_HORDE", "CHAT_MSG_SYSTEM",
    "CHAT_MSG_MONSTER_YELL", "CHAT_MSG_RAID_BOSS_EMOTE", "CHAT_MSG_MONSTER_EMOTE", "AREA_SPIRIT_HEALER_IN_RANGE",
    "UPDATE_WORLD_STATES", "PLAYER_UNGHOST", "GROUP_ROSTER_UPDATE" }
local RAID = {}
for i = 1, 40 do RAID[i] = "raid" .. i end
-- The group's dead: back alive is a rough wave, about half a second after it
-- (MaNGOS cores revive 0.5 s after the wave; UNVERIFIED on OctoWoW).
local f, dead = CreateFrame("Frame"), {}
local function CountDead()
    table.wipe(dead)
    for i = 1, 40 do
        if UnitIsDeadOrGhost(RAID[i]) then dead[RAID[i]] = true end
    end
end
f:SetScript("OnEvent", function(_, event, a1)
    if event == "UPDATE_WORLD_STATES" then
        O.Estimate()
    elseif event == "AREA_SPIRIT_HEALER_IN_RANGE" then
        ReadHealer()
    elseif event == "UNIT_HEALTH" then
        local now = UnitIsDeadOrGhost(a1) and true or nil
        if dead[a1] and not now then A.WaveSeen(GetTime() - 0.5, false) end
        dead[a1] = now
    elseif event == "PLAYER_UNGHOST" then
        A.WaveSeen(GetTime() - 0.5, false) -- your own corpse run looks the same: rough
    elseif event == "GROUP_ROSTER_UPDATE" then
        CountDead()
    else
        ReadLine(a1 or "", event)
        if event ~= "CHAT_MSG_MONSTER_YELL" then A.Queue.CheckEnd() end
    end
end)

-- The raid's health is listened to for the rough wave only, until an exact one.
function O.RoughDone() f:UnregisterEvent("UNIT_HEALTH") end

A.On("PLAYER_ENTERING_WORLD", function()
    local bg = A.zone.pvp and not A.zone.arena
    for _, e in ipairs(MATCH) do
        if bg then f:RegisterEvent(e) else f:UnregisterEvent(e) end
    end
    if bg then
        f:RegisterUnitEvent("UNIT_HEALTH", unpack(RAID))
    else
        f:UnregisterEvent("UNIT_HEALTH")
    end
    CountDead()
    table.wipe(A.owner)
    seen[1], seen[2] = {}, {}
    for _, g in ipairs({ start, abBars, avBars, wsgBars }) do g:Clear() end
    if O.pending then O.pending:Cancel(); O.pending = nil end
    est:Hide()
    O.Estimate() -- a reload inside Arathi Basin shows it at once
    NewMatch()
    ShowWave()
end)

-- Samples for the frame preview.
function O.Preview(on)
    if not on then
        for _, g in ipairs({ start, wave, abBars, avBars, wsgBars }) do g:Clear() end
        est:Hide()
        return ShowWave()
    end
    start:Start("start", "Game starts", 45, "Interface\\Icons\\INV_Misc_PocketWatch_01")
    wave:Start("wave", "Spirit healer", 21, "Interface\\Icons\\Spell_Holy_Resurrection", { guess = true })
    abBars:Start("Blacksmith", "Blacksmith", 31, A.NodeIcon("Blacksmith", "Horde"), { color = A.COLORS.Horde })
    abBars:Start("Lumber Mill", "Lumber Mill", 52, A.NodeIcon("Lumber Mill", "Alliance"), { color = A.COLORS.Alliance })
    avBars:Start("Stonehearth Bunker", "Stonehearth Bunker", 179, A.NodeIcon("Stonehearth Bunker", "Horde"), { color = A.COLORS.Horde })
    wsgBars:Start("Alliance", "Alliance flag", 11, "Interface\\Icons\\INV_BannerPVP_02", { color = A.COLORS.Alliance })
    Card("Win", false, 225, 2000, 1730, "Hold 3 bases")
end
