-- AutoBG queue: the picked battlegrounds queued one by one, the battlemaster
-- window answered and hidden, pops rung, the match left, queued again and the
-- spirit released. The queue request is OctoWoW's own (JoinBattlegroundQueue,
-- FrameXML Minimap.lua:155), the team rows its reserved instance numbers
-- (BattlefieldFrame.lua:20-22), arenas Turtle_ArenaUI.lua (JoinArenaQueue: 0 is
-- Skirmish, answered by the battlemaster window; 1-3 Rated 2v2, 3v3, 5v5, answered
-- by the TW_ARENA addon message S2C_QUEUE_SUCCESS or S2C_ERROR).
local _, A = ...
local db = A.db
local Q = {}
A.Queue = Q

local ICONS = "Interface\\Icons\\"
A.BG = {
    ["Warsong Gulch"] = { queue = "Warsong", word = "wsg", pick = "queueWSG", teams = "teamsWSG", size = 10, icon = ICONS .. "INV_Misc_Rune_07" },
    ["Arathi Basin"] = { queue = "Arathi", word = "ab", pick = "queueAB", teams = "teamsAB", size = 15, icon = ICONS .. "INV_Jewelry_Amulet_07" },
    ["Alterac Valley"] = { queue = "Alterac", word = "av", pick = "queueAV", size = 40, icon = ICONS .. "INV_Jewelry_Necklace_21" },
    ["Thorn Gorge"] = { queue = "ThornGorge", size = 15, icon = ICONS .. "INV_Jewelry_Talisman_04" },
    Arena = { arena = true, word = "arena", pick = "queueArena", size = "arena", icon = ICONS .. "Ability_DualWield" },
}
local ORDER = { "Warsong Gulch", "Arathi Basin", "Alterac Valley", "Arena" }
-- The arena types: JoinArenaQueue's number and the name said in chat.
A.ARENA_TYPES = { { "skirmish", 0, "Skirmish" }, { "2v2", 1, "Rated 2v2" }, { "3v3", 2, "Rated 3v3" }, { "5v5", 3, "Rated 5v5" } }
local function ArenaType()
    for _, t in ipairs(A.ARENA_TYPES) do
        if t[1] == db.arenaType then return t[2], t[3] end
    end
    return 0, "Skirmish"
end
local TEAMS = { xf = "Mixed", fx = "Own faction", fa = "Any" }
local ROWS = { xf = "OCTO_BG_ROW_XF_ID", fx = "OCTO_BG_ROW_FX_ID" }

-- An arena queue and window are named by the arena ("Blood Ring", 2026-11-04),
-- or ARENA (servers/octowow.md).
local function Map(name)
    local lower = name and string.lower(name)
    if lower and (A.ARENAS[lower] or lower == "arena") then return "Arena" end
    return name
end

-- Deserter by name: 26013 is in no OctoWoW source (### C_UnitAuras.GetAuraDataBySpellName).
local function Deserter()
    local aura = C_UnitAuras.GetAuraDataBySpellName("player", "Deserter", "HARMFUL")
    if not aura then return nil end
    local left = aura.expirationTime and aura.expirationTime > 0 and math.floor(aura.expirationTime - GetTime()) or 0
    return "|cffff5555Deserter|r" .. (left > 0 and string.format(" (%d:%02d left)", math.floor(left / 60), left % 60) or "")
end
-- Why nothing is queued now, or nil.
local function Blocked()
    local deserter = Deserter()
    if deserter then return deserter end
    if UnitIsAFK("player") then return "you are AFK" end
end

local function Pop()
    if not db.popAlert then return end
    PlaySound("ReadyCheck")
    C_Timer.After(0.8, function() PlaySound("ReadyCheck") end)
    C_Timer.After(1.6, function() PlaySound("ReadyCheck") end)
    FlashClientIcon()
end

local function Held(map)
    for i = 1, MAX_BATTLEFIELD_QUEUES do
        local status, name = GetBattlefieldStatus(i)
        if status ~= "none" and Map(name) == map then return true end
    end
end
local function Used()
    local n = 0
    for i = 1, MAX_BATTLEFIELD_QUEUES do
        if GetBattlefieldStatus(i) ~= "none" then n = n + 1 end
    end
    return n
end

-- One request: the server answers with BATTLEFIELDS_SHOW, where it is joined; a
-- rated arena with an addon message, heard only while it is awaited.
local pending, pendingUntil, hideUntil, rated = nil, 0, 0, nil
local frame = CreateFrame("Frame")
local function Request(map)
    pending, pendingUntil = map, GetTime() + 4
    if not A.BG[map].arena then return JoinBattlegroundQueue(A.BG[map].queue) end
    local kind, label = ArenaType()
    if kind > 0 then
        pending, rated = nil, label
        frame:RegisterEvent("CHAT_MSG_ADDON")
        C_Timer.After(5, function() if rated == label then rated = nil; frame:UnregisterEvent("CHAT_MSG_ADDON") end end)
    end
    JoinArenaQueue(kind)
end
local function Hide()
    if BattlefieldFrame:IsShown() then HideUIPanel(BattlefieldFrame) end
    CloseBattlefield()
end
BattlefieldFrame:HookScript("OnShow", function() if GetTime() < hideUntil then Hide() end end)
local function Row(map)
    local mode = A.BG[map].teams and db[A.BG[map].teams]
    local id = ROWS[mode] and _G[ROWS[mode]]
    for k = 1, id and GetNumBattlefields() or 0 do
        if GetBattlefieldInstanceInfo(k) == id then return k, TEAMS[mode] end
    end
    return 0, TEAMS.fa
end
frame:RegisterEvent("BATTLEFIELDS_SHOW")
frame:RegisterEvent("UPDATE_BATTLEFIELD_STATUS")
frame:RegisterUnitEvent("UNIT_AURA_DELTA", "player")

-- Queue for everything picked, one request every 2.2 s.
local list, nextIndex, step, afterAlive = {}, 1, nil, false
local function Stop()
    if step then step:Cancel(); step = nil end
    frame:UnregisterEvent("UI_ERROR_MESSAGE")
end
local function Step()
    step = nil
    local why = Blocked()
    if A.zone.pvp or why or UnitIsDeadOrGhost("player") then
        if why then A.Print("Queueing stopped: " .. why .. ".") end
        if UnitIsDeadOrGhost("player") then afterAlive = true end
        return Stop()
    end
    local map = list[nextIndex]
    if not map then return Stop() end
    nextIndex = nextIndex + 1
    if Used() >= MAX_BATTLEFIELD_QUEUES then
        A.Print("All three queues are taken: " .. A.Gold(map) .. " was not queued.")
        return Stop()
    end
    Request(map)
    step = C_Timer.NewTimer(2.2, Step)
end
function Q.QueueAll(only, quiet)
    if A.zone.pvp then return end
    local why = Blocked()
    if why then return A.Print("Not queueing: " .. why .. ".") end
    if UnitIsDeadOrGhost("player") then
        afterAlive = true
        return A.Print("You are dead: queueing once you are alive again.")
    end
    Stop()
    for i = #list, 1, -1 do list[i] = nil end
    nextIndex = 1
    for _, map in ipairs(ORDER) do
        if (only and only == map or not only and db[A.BG[map].pick]) and not Held(map) then list[#list + 1] = map end
    end
    if #list == 0 then
        if quiet then return end
        return A.Print(only and "Already in that queue." or "Nothing to queue: pick a battleground (/abg).")
    end
    frame:RegisterEvent("UI_ERROR_MESSAGE")
    Step()
end

function Q.LeaveQueues()
    Stop()
    Q.rejoin = nil
    local n = 0
    for i = 1, MAX_BATTLEFIELD_QUEUES do
        local status, name = GetBattlefieldStatus(i)
        if status == "queued" or status == "confirm" then
            if Map(name) == "Arena" then LeaveArenaQueue() else AcceptBattlefieldPort(i) end
            n = n + 1
        end
    end
    A.Print(n > 0 and ("Left " .. n .. (n == 1 and " queue." or " queues.")) or "You are in no queue.")
end

-- The end of a match: casts stopped, then left 0.3 s later.
local ended, last = false, nil
local function Exit()
    SpellStopCasting()
    SpellStopTargeting()
    ClearTarget()
end
function Q.CheckEnd()
    if ended or not A.zone.pvp or not GetBattlefieldWinner() then return end
    ended, last = true, A.zone.arena and "Arena" or A.zone.name
    Q.rejoin = db.rejoin and A.BG[last] and { map = last, tries = 0 } or nil
    FlashClientIcon()
    if not db.leave then return end
    Exit()
    local zone = A.zone.name
    C_Timer.After(0.3, function()
        if not A.zone.pvp or A.zone.name ~= zone or not db.leave then return end
        Exit()
        LeaveBattlefield()
        A.Print("Left " .. A.Gold(last) .. ".")
    end)
end
-- However the match is left, it is the one to queue again.
hooksecurefunc("LeaveBattlefield", function()
    if not A.zone.pvp then return end
    ended, last = true, A.zone.arena and "Arena" or A.zone.name
    Q.rejoin = db.rejoin and A.BG[last] and { map = last, tries = 0 } or nil
end)

-- Queue again after the loading screen: three tries.
local function Rejoin()
    local r = Q.rejoin
    if not r or A.zone.pvp then return end
    if Held(r.map) then Q.rejoin = nil; return end
    local why = Blocked()
    if why then
        Q.rejoin = nil
        return A.Print("Not queueing again: " .. why .. ".")
    end
    if UnitIsDeadOrGhost("player") then return end -- PLAYER_ALIVE tries again
    if r.tries >= 3 then
        Q.rejoin = nil
        return A.Print("Could not queue again after three tries. /abg q tries again.")
    end
    r.tries = r.tries + 1
    Request(r.map)
    C_Timer.After(r.map == "Arena" and 4 or 2, Rejoin)
end

-- A queue's title: the battleground, and the teams only when picked (the
-- server's own name, "Arathi Basin (First Available)", is too long for a bar).
local function Title(map, instance)
    if instance and instance ~= 0 and instance == _G.OCTO_BG_ROW_XF_ID then return map .. " - Mixed" end
    if instance and instance ~= 0 and instance == _G.OCTO_BG_ROW_FX_ID then return map .. " - Own faction" end
    return map
end

-- The queue bars: a queue counts up toward its estimate, a pop counts down its invite.
-- Made at load, not at the first queue: the client puts back a dragged frame's
-- place (layout-cache.txt) only for frames that exist when it loads the layout.
local bars, rung = A.Bars.Group("AutoBG_QueueFrame", 3, -220, -100, { 0.3, 0.55, 0.9 }), {}
local function DrawQueues()
    for i = 1, MAX_BATTLEFIELD_QUEUES do
        local status, name, instance = GetBattlefieldStatus(i)
        local map = Map(name)
        local icon = map and A.BG[map] and A.BG[map].icon
        if status == "queued" then
            local title = Title(map, instance)
            bars:Up(i, title, GetTime() - GetBattlefieldTimeWaited(i) / 1000, GetBattlefieldEstimatedWaitTime(i) / 1000, icon)
        elseif status == "confirm" then
            -- The client's time left, which a reload resets to 0: then about 80 s, a guess.
            local left = GetBattlefieldPortExpiration(i) / 1000
            local item = bars.items[i]
            if not (item and item.enter) then
                bars:Start(i, map .. ": enter", left > 0 and left or 80, icon, { enter = true, guess = left <= 0 })
            end
        else
            bars:Stop(i)
        end
        if status == "confirm" and rung[i] ~= name then
            rung[i] = name
            Pop()
            A.Print(A.Gold(map) .. " is ready.")
        elseif status ~= "confirm" then
            rung[i] = nil
        end
    end
end

frame:SetScript("OnEvent", function(_, event, a1, a2)
    if event == "UPDATE_BATTLEFIELD_STATUS" then
        DrawQueues()
        Q.CheckEnd()
    elseif event == "BATTLEFIELDS_SHOW" then
        local shown = Map(GetBattlefieldInfo())
        if pending and shown == pending and GetTime() < pendingUntil then
            local k, team = Row(pending)
            SetSelectedBattlefield(k)
            JoinBattlefield(k)
            hideUntil = GetTime() + 4
            Hide()
            local kind = A.BG[pending].teams and team or A.BG[pending].arena and select(2, ArenaType())
            A.Print("Queued for " .. A.Gold(pending) .. (kind and " (" .. kind .. ")" or "") .. ".")
            pending = nil
        elseif GetTime() < hideUntil then
            Hide()
        end
    elseif event == "CHAT_MSG_ADDON" then
        if a1 ~= "TW_ARENA" or not rated then return end
        local what, why = string.match(a2 or "", "^([^;]*);?([^;]*)")
        if what == "S2C_QUEUE_SUCCESS" then
            A.Print("Queued for " .. A.Gold("Arena") .. " (" .. rated .. ").")
        elseif what == "S2C_ERROR" then
            A.Print(rated .. " not queued" .. (why ~= "" and ": " .. why or "") .. ".")
        else
            return
        end
        rated = nil
        frame:UnregisterEvent("CHAT_MSG_ADDON")
    elseif event == "UI_ERROR_MESSAGE" then
        local message = type(a2) == "string" and a2 or tostring(a1)
        local text = string.lower(message)
        if string.find(text, "cannot queue") or string.find(text, "while dead") then
            Stop()
            A.Print("Queueing stopped: " .. message .. ".")
        end
    elseif event == "UNIT_AURA_DELTA" then
        -- A refresh only cannot add or remove Deserter.
        if a2 and not (a2.isFullUpdate or a2.addedAuraInstanceIDs or a2.removedAuraInstanceIDs) then return end
        local deserter = Deserter()
        if deserter and not Q.deserter then
            A.Print(deserter .. ": no queueing until it ends.")
        elseif Q.deserter and not deserter then
            A.Print("Deserter is gone: you can queue again (/abg q).")
            Pop()
        end
        Q.deserter = deserter and true or nil
    end
end)

A.On("PLAYER_ENTERING_WORLD", function()
    Q.deserter = Deserter() and true or nil
    if A.zone.pvp then
        ended = false
        return
    end
    DrawQueues()
    if Q.rejoin then
        C_Timer.After(1.5, Rejoin)
    elseif db.queueOnLogin and not Q.loginDone then
        Q.loginDone = true
        -- Quiet when nothing is picked: a line at every login says nothing new.
        C_Timer.After(3, function() if db.queueOnLogin then Q.QueueAll(nil, true) end end)
    end
end)
local function Alive()
    if UnitIsDeadOrGhost("player") then return end
    if afterAlive then
        afterAlive = false
        C_Timer.After(2, function() Q.QueueAll() end)
    end
    if Q.rejoin then C_Timer.After(2, Rejoin) end
end
A.On("PLAYER_ALIVE", Alive)
A.On("PLAYER_UNGHOST", Alive)
-- Release in a battleground, never in an arena, not with a Soulstone or Reincarnation ready.
A.On("PLAYER_DEAD", function()
    if not (db.release and A.zone.pvp and not A.zone.arena) then return end
    if HasSoulstone() then return A.Print("Not releasing: you can resurrect yourself.") end
    RepopMe()
    StaticPopup_Hide("DEATH")
end)
