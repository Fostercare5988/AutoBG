-- AutoBG for World of Warcraft 1.12.1: queues, timers, flag carriers, enemy
-- frames and Spy. Author & Maintainer: Fostercare5988.

-- Needs ClassicAPI, SuperWoW and NamPower loaded.
if type(CLASSIC_API_VERSION) ~= "number" or not SUPERWOW_VERSION or not GetNampowerVersion then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff2020AutoBG is off:|r it needs the ClassicAPI, SuperWoW and NamPower DLLs loaded. Start the game through a launcher that loads them.", 1, 0.2, 0.2)
    return
end

local addonName = "AutoBG"
local isAutoQueueing = false
local queueGeneration = 0
local inviteGeneration = {}
local notifiedQueues = {}
local invitedMaps = {}
local pendingAutoRejoin = nil
local finderTimer = nil
local notificationTimers = {}
local notificationGeneration = 0
local notificationUntil = 0
local suppressBattlefieldFrameUntil = 0
local suppressedBattlefieldBG = nil
local needsQueueAfterResurrect = false
local hasHandledEnd = false
local lastPlayedBG = nil
local rejoinWorldReady = false
local rejoinRequest = nil
local TryAutoRejoin
local FinishRejoin

local currentZoneText = ""
local currentZonePVP = false
local currentArena = false

-- The arena zones (2v2, 3v3, 5v5). The one place that names them; Timers,
-- Targets and Spy ask AutoBG_IsArenaZone. The zone names are confirmed by the
-- player (2026-11-03). UNVERIFIED: the instance type an arena reports; test
-- in the arena with /run print(GetRealZoneText(), IsInInstance()).
local ARENA_ZONES = { ["lordaeron arena"] = true, ["sunstrider court"] = true, ["blood ring"] = true }
-- The arena settings (their own tab): every arena extra has a switch. Callouts
-- speak in your team's chat, so they start off. Durations holds the buff lengths
-- measured in play (AutoBG_Arena.lua). Any other key is cleared.
local ARENA_SWITCHES = { "Scan", "Pets", "Mana", "Abilities", "Drinking", "ShadowSight" }
local ARENA_KEYS = { Callouts = true, Durations = true }
for i = 1, #ARENA_SWITCHES do ARENA_KEYS[ARENA_SWITCHES[i]] = true end
local arenaOptions -- the table filled last; asked once a second, filled once
function AutoBG_ArenaOptions()
    local s = AutoBG_Settings
    if not s then return nil end
    if s.Arena and s.Arena == arenaOptions then return arenaOptions end
    if type(s.Arena) ~= "table" then s.Arena = {} end
    local o = s.Arena
    for key in pairs(o) do
        if not ARENA_KEYS[key] then o[key] = nil end
    end
    for i = 1, #ARENA_SWITCHES do
        if o[ARENA_SWITCHES[i]] == nil then o[ARENA_SWITCHES[i]] = true end
    end
    if o.Callouts == nil then o.Callouts = false end
    arenaOptions = o
    return o
end

-- The queue status names an arena queue by the arena ("Blood Ring", confirmed in
-- game 2026-11-04), not "Arena"; this gives ARENA for it, any other map unchanged.
function AutoBG_QueueMap(map)
    if map and ARENA_ZONES[string.lower(map)] then return ARENA end
    return map
end
function AutoBG_IsArenaZone()
    local inInstance, instanceType = IsInInstance()
    -- ClassicAPI: true once an arena match's map loads (the world's Gurubashi
    -- Arena is not one). Confirmed in game: an arena reports instance type "pvp".
    -- Only inside an instance: the zone name and the arena flag can outlive the
    -- match for a moment after you leave, which stalled the rejoin.
    if not inInstance then return false end
    return IsActiveBattlefieldArena()
        or instanceType == "arena"
        or ARENA_ZONES[string.lower(GetRealZoneText() or "")] == true
end

local function UpdateZoneCache()
    currentZoneText = GetRealZoneText() or ""
    local inInstance, instanceType = IsInInstance()
    -- The zone decides, never the queue status: it can still say "active" for a
    -- moment after you left, which stalled the rejoin.
    currentArena = AutoBG_IsArenaZone() and true or false
    currentZonePVP = ((inInstance and instanceType == "pvp") or currentArena) and true or false
end

-- The battlemaster window of an arena is titled with the arena (confirmed in
-- game: "Blood Ring" for Skirmish), so it counts as ARENA.
local function ShownBattlefield()
    local shown = GetBattlefieldInfo()
    if shown and ARENA_ZONES[string.lower(shown)] then return ARENA end
    return shown
end

-- What the match you are in queues as again: the battleground, or ARENA.
local function MatchName()
    return currentArena and ARENA or currentZoneText
end

-- The side you play on in this match. OctoWoW's mixed teams put both factions
-- on each side (a teammate of the other faction showed in the enemy list,
-- 2026-11-13), so your faction is only the first guess. A player seen playing
-- for a side settles it: one of your group is on your side, one you can attack
-- on the other. Forgotten at every loading screen.
local OTHER_SIDE = { Alliance = "Horde", Horde = "Alliance" }
local matchSide
function AutoBG_MySide()
    return matchSide or UnitFactionGroup("player")
end
-- The side name plays for when it shows: yours for you and your group, the
-- other one for a player you can attack; nil for anyone else. ClassicAPI
-- finds the named player in the group or around you.
function AutoBG_SideOf(name)
    if not name then return nil end
    local mine = AutoBG_MySide()
    if name == UnitName("player") then return mine end
    local unit = UnitTokenFromName(name, true)
    if not unit and string.find(name, "-", 1, true) then
        unit = UnitTokenFromName((string.gsub(name, "-.*$", "")), true)
    end
    if not unit then return nil end
    if UnitInParty(unit) or UnitInRaid(unit) then return mine end
    if UnitIsPlayer(unit) and UnitCanAttack("player", unit) then return OTHER_SIDE[mine] end
end
-- name was seen playing for side ("Alliance" or "Horde").
function AutoBG_NoteSide(name, side)
    if not OTHER_SIDE[side] then return end
    local seen = AutoBG_SideOf(name)
    if seen then matchSide = (seen == AutoBG_MySide()) and side or OTHER_SIDE[side] end
end

function AutoBG_SavePosition(frame, name)
    if not frame or not name or not AutoBG_Settings then return end
    AutoBG_Settings.Positions = AutoBG_Settings.Positions or {}
    local point, _, relPoint, x, y = frame:GetPoint()
    if not point then
        point = "TOPLEFT"
        relPoint = "BOTTOMLEFT"
        x = frame:GetLeft()
        y = frame:GetTop()
    end
    if point and x and y then
        AutoBG_Settings.Positions[name] = { point = point, relPoint = relPoint or point, x = x, y = y }
    end
end

function AutoBG_LoadPosition(frame, name, defaultPoint, defaultX, defaultY, defaultRelPoint)
    if not frame then return end
    defaultPoint = defaultPoint or "CENTER"
    defaultRelPoint = defaultRelPoint or defaultPoint
    if AutoBG_Settings and AutoBG_Settings.Positions and AutoBG_Settings.Positions[name] then
        local pos = AutoBG_Settings.Positions[name]
        frame:ClearAllPoints()
        frame:SetPoint(pos.point or defaultPoint, UIParent, pos.relPoint or defaultRelPoint, pos.x or defaultX, pos.y or defaultY)
    else
        frame:ClearAllPoints()
        frame:SetPoint(defaultPoint, UIParent, defaultRelPoint, defaultX, defaultY)
    end
end

-- Ctrl+click announcements go to the battleground, else the raid or party,
-- else say.
function AutoBG_SendAnnouncement(text)
    if not text or text == "" then return end
    local chatType = (currentZonePVP and "BATTLEGROUND") or (IsInRaid() and "RAID")
        or (IsInGroup() and "PARTY") or "SAY"
    SendChatMessage(text, chatType)
end

local defaultSettings = {
    NotifySound = true, FlashTaskbar = true, ChatMessages = true,
    AutoAccept = false, AutoAcceptDelay = 0, AutoLeave = true,
    AutoRejoin = false, AutoQueueLogin = false, ScoreColor = true,
    AutoRelease = true, ABTimers = true,
    AVTimers = true, RessTimer = true, QueueTimers = true,
    FCFrame = true, WSGTimers = true,
    LastPlayedBG = nil,
    Positions = {}, SkipIfAFK = true,
    AutoQueue_WSG = true, AutoQueue_AB = true, AutoQueue_AV = true,
    -- Which row Warsong and Arathi join: "xf" Cross-Faction, "fx" Factioned,
    -- "fa" First Available. Alterac Valley has no mixed teams (2026-11-04).
    QueueMode_WSG = "xf", QueueMode_AB = "xf",
    -- Arena queued with them: ArenaType 0 Skirmish, 1-3 Rated 2v2/3v3/5v5.
    AutoQueue_Arena = false, ArenaType = 0,
    StartTimer = true,
    -- Countdown look
    ObjectiveWidth = 225, ObjectiveHeight = 25, ObjectiveScale = 1, ObjectiveOpacity = 0.9,
}
-- Saved keys that are not settings: each module's own table and what AutoBG
-- learned in play. A new one is a line here; anything else is cleared on load.
local SAVED_TABLES = {
    Targets = true, Spy = true, Arena = true, -- the modules' settings
    LastPlayedBG = true,                      -- quick queue, rejoin
    FlagSpots = true, OpeningSpell = true,    -- the flag watch (AutoBG_FlagWatch.lua)
    ABTicks = true,                           -- Arathi Basin ticks (AutoBG_Timers.lua)
}

-- Each battleground: its icon on the queue bar and the type OctoWoW's queue
-- request takes (JoinBattlegroundQueue, the client's own minimap menu).
local BATTLEGROUNDS = {
    ["Warsong Gulch"]  = { icon = "Interface\\Icons\\INV_Misc_Rune_07", queue = "Warsong" },
    ["Arathi Basin"]   = { icon = "Interface\\Icons\\INV_Jewelry_Amulet_07", queue = "Arathi" },
    ["Alterac Valley"] = { icon = "Interface\\Icons\\INV_Jewelry_Necklace_21", queue = "Alterac" },
    ["Thorn Gorge"]    = { icon = "Interface\\Icons\\INV_Jewelry_Talisman_04", queue = "ThornGorge" },
    -- Arenas queue through JoinArenaQueue (Turtle_ArenaUI.lua); the icon is
    -- OctoWoW's own battleground finder button.
    [ARENA]            = { icon = "Interface\\Icons\\Ability_DualWield", arena = true },
}
local ARENA_TYPES = { [0] = "Skirmish", [1] = "Rated 2v2", [2] = "Rated 3v3", [3] = "Rated 5v5" }

function AutoBG_GetBGIcon(name)
    local bg = name and BATTLEGROUNDS[name]
    return bg and bg.icon
end

function AutoBG_CancelAllQueues()
    queueGeneration = queueGeneration + 1
    suppressBattlefieldFrameUntil = 0
    isAutoQueueing = false
    pendingAutoRejoin = nil
    needsQueueAfterResurrect = false
    hasHandledEnd = false
    AutoBG_StopNotificationSound()
    FinishRejoin()
    local cancelled = 0
    for i = 1, MAX_BATTLEFIELD_QUEUES do
        inviteGeneration[i] = (inviteGeneration[i] or 0) + 1
        notifiedQueues[i] = false
        invitedMaps[i] = nil
        local status, map = GetBattlefieldStatus(i)
        map = AutoBG_QueueMap(map)
        if status and status ~= "none" and status ~= "active" then
            -- The client's Leave Queue: LeaveArenaQueue for the arena queue, else
            -- AcceptBattlefieldPort with a nil flag (0 is true in Lua).
            if map == ARENA then LeaveArenaQueue() else AcceptBattlefieldPort(i) end
            cancelled = cancelled + 1
        end
    end
    if cancelled > 0 then
        AutoBG_Print("Cancelled " .. cancelled .. " active battleground queue(s).", true)
    else
        AutoBG_Print("No active queues found to cancel.", true)
    end
end

-- ClassicAPI UnitIsAFK reads the player's AFK flag directly; no chat parsing needed.
function AutoBG_IsPlayerAFK()
    return UnitIsAFK("player") and true or false
end

function AutoBG_Print(msg, force)
    if (force or (AutoBG_Settings and AutoBG_Settings.ChatMessages)) and DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00AutoBG:|r " .. msg)
    end
end

-- ClassicAPI 1.17.7: flashes until the game window has focus; nothing while it has.
local function FlashTaskbar()
    if AutoBG_Settings and AutoBG_Settings.FlashTaskbar then FlashClientIcon() end
end

-- Class colors, Shaman in blue (the 1.12 table has it pink).
AutoBG_CLASS_COLORS = {
    HUNTER  = { r = 0.67, g = 0.83, b = 0.45, hex = "|cffabd473" },
    WARLOCK = { r = 0.58, g = 0.51, b = 0.79, hex = "|cff9482c9" },
    PRIEST  = { r = 1.00, g = 1.00, b = 1.00, hex = "|cffffffff" },
    PALADIN = { r = 0.96, g = 0.55, b = 0.73, hex = "|cfff58cba" },
    MAGE    = { r = 0.41, g = 0.80, b = 0.94, hex = "|cff69ccf0" },
    ROGUE   = { r = 1.00, g = 0.96, b = 0.41, hex = "|cfffff569" },
    DRUID   = { r = 1.00, g = 0.49, b = 0.04, hex = "|cffff7d0a" },
    SHAMAN  = { r = 0.00, g = 0.44, b = 0.87, hex = "|cff0070de" },
    WARRIOR = { r = 0.78, g = 0.61, b = 0.43, hex = "|cffc79c6e" },
}

function AutoBG_GetClassColor(classOrToken)
    if not classOrToken then return nil end
    local token = string.upper(classOrToken)
    local entry = AutoBG_CLASS_COLORS[token]
    return entry and entry.hex, token
end


-- ClassicAPI's player cache knows you, your group (in range or not), players
-- near you and everyone met this session; an enemy never seen near you is
-- only on the scoreboard.
function AutoBG_FindPlayerClass(playerName)
    if not playerName or playerName == "" then return nil end
    local clean = string.gsub(playerName, "-.*$", "")
    clean = string.gsub(clean, "^%s*(.-)%s*$", "%1")
    if UnitName("player") == clean then
        local _, token = UnitClass("player"); return token
    end
    local _, token = C_PlayerCache.GetPlayerInfoByName(clean)
    if token then return token end

    for i = 1, GetNumBattlefieldScores() do
        local name, _, _, _, _, _, _, _, locClass, classToken = GetBattlefieldScore(i)
        if name and string.gsub(name, "-.*$", "") == clean then
            return classToken or locClass
        end
    end
    return nil
end

local function IsPlayerDeadOrGhost()
    return UnitIsDeadOrGhost("player")
end

-- StaticPopup_Hide hides every dialog of the kind (StaticPopup.lua).
local function DismissBattlefieldPopups()
    StaticPopup_Hide("CONFIRM_BATTLEFIELD_ENTRY")
end

-- Deserter Debuff Engine & Lifecycle Tracking
local hadDeserterDebuff = false

local function FormatDeserterRemaining(sec)
    if not sec or sec <= 0 then return "" end
    local m = math.floor(sec / 60)
    local s = sec % 60
    if m > 0 then
        return string.format(" (%dm %02ds remaining)", m, s)
    else
        return string.format(" (%ds remaining)", s)
    end
end

function AutoBG_HasDeserter()
    -- One ClassicAPI lookup by name, then by spell ID, instead of building every aura.
    -- The ID is the 1.12 one, in no OctoWoW source.
    -- UNVERIFIED: test in game: /run print(GetSpellInfo(26013)) prints Deserter.
    local aura = C_UnitAuras.GetAuraDataBySpellName("player", "Deserter", "HARMFUL")
        or C_UnitAuras.GetPlayerAuraBySpellID(26013)
    if not aura then return false, 0 end
    local remaining = 0
    if aura.expirationTime and aura.expirationTime > 0 then
        remaining = math.max(0, math.floor(aura.expirationTime - GetTime()))
    end
    return true, remaining
end

-- Battlefield window suppression belongs to the active queue request.

local function AutoBG_HideBattlefieldWindow()
    if BattlefieldFrame and BattlefieldFrame:IsShown() then
        HideUIPanel(BattlefieldFrame)
        BattlefieldFrame:Hide()
    end
    CloseBattlefield()
    CloseDropDownMenus()
end

BattlefieldFrame:HookScript("OnShow", function()
    if GetTime() < suppressBattlefieldFrameUntil and ShownBattlefield() == suppressedBattlefieldBG then
        AutoBG_HideBattlefieldWindow()
    end
end)

function AutoBG_StopNotificationSound()
    notificationGeneration = notificationGeneration + 1
    notificationUntil = 0
    for i = 1, 2 do
        if notificationTimers[i] then notificationTimers[i]:Cancel(); notificationTimers[i] = nil end
    end
end

function AutoBG_PlayNotificationSound(isAutomatic)
    if isAutomatic and not (AutoBG_Settings and AutoBG_Settings.NotifySound) then return end
    if GetTime() < notificationUntil then return end
    AutoBG_StopNotificationSound()
    notificationUntil = GetTime() + 1.7
    local generation = notificationGeneration
    PlaySound("ReadyCheck")
    for i = 1, 2 do
        local index = i
        notificationTimers[index] = C_Timer.NewTimer(index * 0.8, function()
            if generation ~= notificationGeneration then return end
            notificationTimers[index] = nil
            if isAutomatic and not (AutoBG_Settings and AutoBG_Settings.NotifySound) then
                AutoBG_StopNotificationSound()
                return
            end
            PlaySound("ReadyCheck")
        end)
    end
end

-- The full name of a battleground from its name, an abbreviation or a word of it.
local function FullBattlegroundName(text)
    if not text then return "Warsong Gulch" end
    if BATTLEGROUNDS[text] then return text end
    local lower = string.lower(text)
    if lower == "arena" then return ARENA
    elseif string.find(lower, "arathi") or lower == "ab" then return "Arathi Basin"
    elseif string.find(lower, "alterac") or lower == "av" then return "Alterac Valley"
    elseif string.find(lower, "thorn") or string.find(lower, "gorge") or lower == "tg" then return "Thorn Gorge"
    elseif string.find(lower, "warsong") or lower == "wsg" then return "Warsong Gulch" end
    return text
end

function AutoBG_TriggerBattlegroundFinder(bgName, isRejoin, isBatchRequest)
    if not isRejoin and not isBatchRequest then
        queueGeneration = queueGeneration + 1
        isAutoQueueing = false
        hasHandledEnd = false
        FinishRejoin()
    end
    local hasDeserter, remaining = AutoBG_HasDeserter()
    if hasDeserter then
        pendingAutoRejoin = nil
        isAutoQueueing = false
        AutoBG_Print("Cannot queue for |cFFFFFF00" .. (bgName or "battleground") .. "|r: You have the |cFFFF5555Deserter|r debuff" .. FormatDeserterRemaining(remaining) .. ". Type |cFFFFFF00/abg q all|r once Deserter expires.", true)
        return
    end

    local cleanName = FullBattlegroundName(bgName)
    local bg = BATTLEGROUNDS[cleanName]
    if not bg then
        pendingAutoRejoin = nil
        AutoBG_Print("No queue for |cFFFFFF00" .. cleanName .. "|r.", true)
        return
    end
    if finderTimer then finderTimer:Cancel(); finderTimer = nil end
    pendingAutoRejoin = cleanName
    suppressBattlefieldFrameUntil = 0
    if not isRejoin then
        local generation = queueGeneration
        local timer
        timer = C_Timer.NewTimer(4, function()
            if finderTimer ~= timer or generation ~= queueGeneration then return end
            finderTimer = nil
            if pendingAutoRejoin == cleanName then pendingAutoRejoin = nil end
        end)
        finderTimer = timer
    end
    if bg.arena then
        -- Skirmish asks the server like a battleground does; a rated queue starts at once.
        -- Skirmish answers with BATTLEFIELDS_SHOW (window titled with the arena zone).
        AutoBG_Print("Queueing |cFFFFFF00" .. ARENA_TYPES[AutoBG_Settings.ArenaType] .. "|r arena...")
        JoinArenaQueue(AutoBG_Settings.ArenaType)
        return
    end
    -- The server answers with the battlemaster list (BATTLEFIELDS_SHOW), where
    -- the request is joined.
    JoinBattlegroundQueue(bg.queue)
end


-- Multi-BG auto-queue with reusable queue buffers.
local hasQueuedOnLogin = false
local queueQueueBuffer = {}

function AutoBG_GetSelectedBGs()
    local list = {}
    if AutoBG_Settings then
        if AutoBG_Settings.AutoQueue_WSG ~= false then table.insert(list, "Warsong Gulch") end
        if AutoBG_Settings.AutoQueue_AB ~= false then table.insert(list, "Arathi Basin") end
        if AutoBG_Settings.AutoQueue_AV ~= false then table.insert(list, "Alterac Valley") end
        if AutoBG_Settings.AutoQueue_Arena then table.insert(list, ARENA) end
    end
    return list
end

function AutoBG_QueueAllBGs()
    if isAutoQueueing or currentZonePVP then return end
    local hasDeserter, remaining = AutoBG_HasDeserter()
    if hasDeserter then
        AutoBG_Print("Cannot queue: You have the |cFFFF5555Deserter|r debuff" .. FormatDeserterRemaining(remaining) .. ". Type |cFFFFFF00/abg q all|r once Deserter expires.", true)
        return
    end
    if (AutoBG_Settings and AutoBG_Settings.SkipIfAFK ~= false) and AutoBG_IsPlayerAFK() then
        AutoBG_Print("Auto-Queue skipped: You are tagged as |cFFFF5555AFK|r.")
        return
    end
    if IsPlayerDeadOrGhost() then
        needsQueueAfterResurrect = true
        AutoBG_Print("Cannot queue for battlegrounds while dead. Will auto-queue once resurrected.")
        return
    end

    table.wipe(queueQueueBuffer)
    local total = 0
    local bgsToQueue = AutoBG_GetSelectedBGs()
    if #bgsToQueue == 0 then
        AutoBG_Print("Select at least one battleground in Auto-Queue options.", true)
        return
    end

    for i = 1, #bgsToQueue do
        local bg = bgsToQueue[i]
        local alreadyQueued = false
        for q = 1, MAX_BATTLEFIELD_QUEUES do
            local status, mapName = GetBattlefieldStatus(q)
            mapName = AutoBG_QueueMap(mapName)
            if status and status ~= "none" and mapName and string.find(string.lower(mapName), string.lower(bg)) then
                alreadyQueued = true; break
            end
        end
        if not alreadyQueued then
            total = total + 1
            queueQueueBuffer[total] = bg
        end
    end

    if total == 0 then
        AutoBG_Print("Already queued for all selected Battlegrounds.")
        return
    end

    queueGeneration = queueGeneration + 1
    local generation = queueGeneration
    hasHandledEnd = false
    FinishRejoin()
    isAutoQueueing = true
    local idx = 1

    local function StepQueue()
        if generation ~= queueGeneration or not isAutoQueueing then return end
        if currentZonePVP then isAutoQueueing = false; return end
        local hasDes, rem = AutoBG_HasDeserter()
        if hasDes then
            isAutoQueueing = false
            AutoBG_Print("Auto-Queue halted: You have the |cFFFF5555Deserter|r debuff" .. FormatDeserterRemaining(rem) .. ". Type |cFFFFFF00/abg q all|r once Deserter expires.", true)
            return
        end
        if (AutoBG_Settings and AutoBG_Settings.SkipIfAFK ~= false) and AutoBG_IsPlayerAFK() then
            isAutoQueueing = false
            AutoBG_Print("Auto-Queue paused: You are tagged as |cFFFF5555AFK|r.")
            return
        end
        if IsPlayerDeadOrGhost() then
            isAutoQueueing = false; needsQueueAfterResurrect = true
            AutoBG_Print("Auto-Queue paused (player dead/ghost). Will resume upon resurrection.")
            return
        end
        if idx > total then
            isAutoQueueing = false; AutoBG_Print("Queue requests finished. Check the battleground queue status.")
            return
        end
        -- The client holds three queues; the server refuses a fourth.
        local used = 0
        for q = 1, MAX_BATTLEFIELD_QUEUES do
            if GetBattlefieldStatus(q) ~= "none" then used = used + 1 end
        end
        if used >= MAX_BATTLEFIELD_QUEUES then
            isAutoQueueing = false
            AutoBG_Print("All " .. MAX_BATTLEFIELD_QUEUES .. " queues are in use: |cFFFFFF00" .. queueQueueBuffer[idx] .. "|r and later choices were not queued.", true)
            return
        end
        local currentBG = queueQueueBuffer[idx]
        idx = idx + 1
        AutoBG_Print("Auto-queuing for |cFFFFFF00" .. currentBG .. "|r (" .. (idx - 1) .. "/" .. total .. ")...")
        AutoBG_TriggerBattlegroundFinder(currentBG, false, true)
        C_Timer.After(2.2, StepQueue)
    end
    StepQueue()
end

-- Macro Target Button
local quickQueueBtn = CreateFrame("Button", "AutoBG_QuickQueueButton", UIParent)
quickQueueBtn:SetScript("OnClick", function()
    local bg = (AutoBG_Settings and AutoBG_Settings.LastPlayedBG) or lastPlayedBG or "Warsong Gulch"
    AutoBG_Print("Quick-queue triggered for |cFFFFFF00" .. bg .. "|r...")
    AutoBG_TriggerBattlegroundFinder(bg)
end)

FinishRejoin = function()
    if finderTimer then finderTimer:Cancel(); finderTimer = nil end
    if rejoinRequest then
        if rejoinRequest.timer then rejoinRequest.timer:Cancel() end
        suppressBattlefieldFrameUntil = 0
    end
    rejoinRequest = nil
    hasHandledEnd = false
    pendingAutoRejoin = nil
end

local function BeginRejoin(bg)
    if rejoinRequest and rejoinRequest.timer then rejoinRequest.timer:Cancel() end
    rejoinRequest = nil
    pendingAutoRejoin = nil
    if AutoBG_Settings and AutoBG_Settings.AutoRejoin and bg then
        local cleanName = FullBattlegroundName(bg)
        rejoinRequest = { bg = cleanName, generation = queueGeneration, attempts = 0, phase = "world" }
        pendingAutoRejoin = cleanName
    end
end

local function ScheduleRejoin(request, delay)
    if request ~= rejoinRequest or request.generation ~= queueGeneration or request.timer then return end
    local timer
    timer = C_Timer.NewTimer(delay, function()
        if request ~= rejoinRequest or request.generation ~= queueGeneration or request.timer ~= timer then return end
        request.timer = nil
        if rejoinWorldReady and request.phase == "world" then request.phase = "ready" end
        TryAutoRejoin()
    end)
    request.timer = timer
end

local function WaitForRejoinReady(request)
    if GetTime() >= request.readyDeadline then
        FinishRejoin()
        AutoBG_Print("Auto-Rejoin stopped: the player or battleground status is not ready. Use /abg q to retry.", true)
    else
        ScheduleRejoin(request, 0.05)
    end
end

local function PrepareBattlefieldExit()
    -- NamPower also clears its queued casts through this native API.
    SpellStopCasting()
    SpellStopTargeting()
    ClearTarget()
end

local function HandleMatchEnd()
    if hasHandledEnd then return end
    UpdateZoneCache()
    if not currentZonePVP then return end
    hasHandledEnd = true
    rejoinWorldReady = false
    local match = MatchName()
    if match ~= "" then
        lastPlayedBG = match
        if AutoBG_Settings then AutoBG_Settings.LastPlayedBG = match end
    end
    BeginRejoin(lastPlayedBG)

    FlashTaskbar()

    if AutoBG_Settings and AutoBG_Settings.AutoLeave then
        if UnitExists("player") then PrepareBattlefieldExit() end
        local finishedBG = currentZoneText
        local generation = queueGeneration
        C_Timer.After(0.3, function()
            UpdateZoneCache()
            if generation ~= queueGeneration or not hasHandledEnd or not currentZonePVP or
               currentZoneText ~= finishedBG or not UnitExists("player") or
               not (AutoBG_Settings and AutoBG_Settings.AutoLeave) then return end
            -- A cast may have been queued again during the exit delay.
            PrepareBattlefieldExit()
            LeaveBattlefield()
            AutoBG_Print("Auto-left |cFFFFFF00" .. (lastPlayedBG or "battleground") .. "|r.")
        end)
    end
end

local function IsQueuedFor(bg)
    for i = 1, MAX_BATTLEFIELD_QUEUES do
        local status, map = GetBattlefieldStatus(i)
        if (status == "queued" or status == "confirm") and AutoBG_QueueMap(map) == bg then return true end
    end
    return false
end

TryAutoRejoin = function()
    if not hasHandledEnd then return end
    if currentZonePVP or not rejoinWorldReady then return end
    if not (AutoBG_Settings and AutoBG_Settings.AutoRejoin) then FinishRejoin(); return end
    if not rejoinRequest then BeginRejoin(lastPlayedBG) end
    local request = rejoinRequest
    if not request or request.generation ~= queueGeneration then return end
    request.readyDeadline = request.readyDeadline or GetTime() + 5.0
    if request.phase == "world" then
        -- NewTimer(0) runs on an engine tick, outside the world-load event.
        ScheduleRejoin(request, 0)
        return
    end
    if not UnitExists("player") then WaitForRejoinReady(request); return end
    if IsQueuedFor(request.bg) then FinishRejoin(); return end
    if request.deadline and GetTime() < request.deadline then
        ScheduleRejoin(request, request.deadline - GetTime())
        return
    end
    if request.attempts >= 3 then
        FinishRejoin()
        AutoBG_Print("Auto-Rejoin could not confirm the queue after three attempts. Use /abg q to retry.", true)
        return
    end
    for i = 1, MAX_BATTLEFIELD_QUEUES do
        if GetBattlefieldStatus(i) == "active" then WaitForRejoinReady(request); return end
    end
    if IsPlayerDeadOrGhost() then WaitForRejoinReady(request); return end
    local hasDeserter, remaining = AutoBG_HasDeserter()
    if hasDeserter then
        FinishRejoin()
        AutoBG_Print("Auto-Rejoin halted: You have the |cFFFF5555Deserter|r debuff" .. FormatDeserterRemaining(remaining) .. ".", true)
        return
    end
    if (AutoBG_Settings.SkipIfAFK ~= false) and AutoBG_IsPlayerAFK() then
        AutoBG_Print("Auto-Rejoin paused: You are tagged as |cFFFF5555AFK|r.")
        FinishRejoin()
        return
    end
    request.attempts = request.attempts + 1
    request.phase = "list"
    -- The server confirms an arena queue more slowly than a battleground.
    local wait = request.bg == ARENA and 4 or 1.5
    request.deadline = GetTime() + wait
    pendingAutoRejoin = request.bg
    AutoBG_TriggerBattlegroundFinder(request.bg, true)
    ScheduleRejoin(request, wait)
end

-- Ensure Auto-Rejoin target is captured regardless of how the player leaves the battleground
hooksecurefunc("LeaveBattlefield", function()
    if currentZonePVP then
        local departedBG = MatchName()
        UpdateZoneCache()
        if currentZonePVP then departedBG = MatchName() end
        if departedBG ~= "" then
            lastPlayedBG = departedBG
            if AutoBG_Settings then AutoBG_Settings.LastPlayedBG = departedBG end
        end
        hasHandledEnd = true
        rejoinWorldReady = false
        BeginRejoin(lastPlayedBG)
    end
end)

-- ProcessBattlefieldQueue owns accepting. Blizzard may show the entry popup after it
-- accepted the same queue (data = queue index), so only hide that popup here.
hooksecurefunc("StaticPopup_Show", function(which, text_arg1, text_arg2, data)
    if which == "CONFIRM_BATTLEFIELD_ENTRY" and notifiedQueues[data or 1] == "accepted" then
        DismissBattlefieldPopups()
    end
end)


local frame = CreateFrame("Frame", "AutoBGFrame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("UPDATE_BATTLEFIELD_STATUS")
frame:RegisterEvent("BATTLEFIELDS_SHOW")
frame:RegisterEvent("PLAYER_DEAD")
frame:RegisterEvent("PLAYER_ALIVE")
frame:RegisterEvent("PLAYER_UNGHOST")
frame:RegisterEvent("UI_ERROR_MESSAGE")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_LEAVING_WORLD")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
-- The match-end lines matter only inside a battleground.
local MATCH_CHAT = { "CHAT_MSG_BG_SYSTEM_NEUTRAL", "CHAT_MSG_BG_SYSTEM_ALLIANCE", "CHAT_MSG_BG_SYSTEM_HORDE", "CHAT_MSG_SYSTEM" }
local matchChatOn = false
local function SyncMatchChat()
    if matchChatOn == currentZonePVP then return end
    matchChatOn = currentZonePVP
    for i = 1, #MATCH_CHAT do
        if matchChatOn then frame:RegisterEvent(MATCH_CHAT[i]) else frame:UnregisterEvent(MATCH_CHAT[i]) end
    end
end
-- Only your own auras matter (the Deserter debuff); other units never reach Lua.
-- ClassicAPI 1.17.10 UNIT_AURA_DELTA says what changed, so refreshes cost nothing.
frame:RegisterUnitEvent("UNIT_AURA_DELTA", "player")

-- An invite runs out after about 80 seconds (measured in play: one ran out at
-- 79s, 2026-10-21), so the enter delay tops out at 78, a second to spare. A
-- saved longer delay is clamped on load. Each enter also comes a second before
-- its own invite runs out: the client knows how long it has left
-- (GetBattlefieldPortExpiration in ms, as BattlefieldFrame.lua shows it), which
-- is less after a reload or a loading screen. An invite that still ends before
-- the scheduled enter is reported.
AutoBG_MAX_ENTER_DELAY = 78
local inviteStart, enterDelay = {}, {}

-- The minimap's Leave Queue calls AcceptBattlefieldPort(id) with no accept:
-- the player left, so a scheduled enter is off and nothing ran out.
hooksecurefunc("AcceptBattlefieldPort", function(id, accept)
    if not accept and notifiedQueues[id] == true then notifiedQueues[id] = "left" end
end)

local function ReportMissedEnter(id)
    local started, delay = inviteStart[id], enterDelay[id] or 0
    if not (started and notifiedQueues[id] == true and AutoBG_Settings.AutoAccept and delay > 0) then return end
    local lasted = math.floor(GetTime() - started)
    AutoBG_Print("The invite for |cFFFFFF00" .. (invitedMaps[id] or "Battleground") .. "|r ended after |cFFFFFF00"
        .. lasted .. "s|r, before Auto-Enter at |cFFFFFF00" .. delay .. "s|r. Lower the enter delay if it ran out.", true)
end

local function ProcessBattlefieldQueue(id)
    local status, mapName = GetBattlefieldStatus(id)
    if status == "confirm" then
        if invitedMaps[id] ~= mapName then
            inviteGeneration[id] = (inviteGeneration[id] or 0) + 1
            notifiedQueues[id] = false
            invitedMaps[id] = mapName
        end
        if not notifiedQueues[id] then
            inviteGeneration[id] = (inviteGeneration[id] or 0) + 1
            local generation = inviteGeneration[id]
            notifiedQueues[id] = true
            inviteStart[id] = GetTime()
            if AutoBG_Settings.AutoAccept then
                if (AutoBG_Settings.SkipIfAFK ~= false) and AutoBG_IsPlayerAFK() then
                    AutoBG_Print("Queue popped for |cFFFFFF00" .. (mapName or "Battleground") .. "|r, but Auto-Enter is paused because you are |cFFFF5555AFK|r!")
                    if AutoBG_Settings.NotifySound then AutoBG_PlayNotificationSound(true) end
                    FlashTaskbar()
                    return
                end
                local delay = math.max(0, math.min(AutoBG_Settings.AutoAcceptDelay or 0, AutoBG_MAX_ENTER_DELAY))
                local left = GetBattlefieldPortExpiration(id) / 1000
                if left > 0 then delay = math.max(0, math.min(delay, math.floor(left) - 1)) end
                enterDelay[id] = delay
                local qId, bg = id, mapName or "Battleground"
                if delay <= 0 then
                    notifiedQueues[qId] = "accepted"
                    AcceptBattlefieldPort(qId, 1)
                    DismissBattlefieldPopups()
                    AutoBG_Print("Instant Auto-Accepted |cFFFFFF00" .. bg .. "|r!")
                else
                    AutoBG_Print("Queue popped for |cFFFFFF00" .. bg .. "|r! Entering in |cFFFFFF00" .. delay .. "s|r...")
                    C_Timer.After(delay, function()
                        if inviteGeneration[qId] ~= generation or notifiedQueues[qId] ~= true or not AutoBG_Settings.AutoAccept then return end
                        local currentStatus, currentMap = GetBattlefieldStatus(qId)
                        if currentStatus ~= "confirm" or currentMap ~= mapName then return end
                        if (AutoBG_Settings.SkipIfAFK ~= false) and AutoBG_IsPlayerAFK() then
                            AutoBG_Print("Auto-Enter cancelled: Player became |cFFFF5555AFK|r!")
                            return
                        end
                        if GetBattlefieldStatus(qId) == "confirm" then
                            notifiedQueues[qId] = "accepted"
                            AcceptBattlefieldPort(qId, 1)
                            DismissBattlefieldPopups()
                            AutoBG_Print("Auto-Entered |cFFFFFF00" .. bg .. "|r after |cFFFFFF00" .. delay .. "s|r delay!")
                        end
                    end)
                end
            end
            if AutoBG_Settings.NotifySound then AutoBG_PlayNotificationSound(true) end
            FlashTaskbar()
            if not AutoBG_Settings.AutoAccept then
                AutoBG_Print("Queue is ready for |cFFFFFF00" .. (mapName or "Battleground") .. "|r! (Queue #" .. id .. ")")
            end
        end
    else
        if status ~= "active" then ReportMissedEnter(id) end
        inviteStart[id], enterDelay[id] = nil, nil
        inviteGeneration[id] = (inviteGeneration[id] or 0) + 1
        notifiedQueues[id] = false
        invitedMaps[id] = nil
        if status == "active" then
            if mapName and mapName ~= "" then lastPlayedBG = mapName end
            if GetBattlefieldWinner() then HandleMatchEnd() end
        end
    end
end

-- OctoWoW lists Cross-Faction and Factioned as reserved instance numbers after
-- First Available (BattlefieldFrame.lua, OCTO_BG_ROW_XF_ID / OCTO_BG_ROW_FX_ID).
-- The player picks the row per battleground (QueueMode_WSG, QueueMode_AB; default
-- Cross-Faction). A row the list lacks falls back to First Available (0).
local QUEUE_MODE_KEY = { ["Warsong Gulch"] = "QueueMode_WSG", ["Arathi Basin"] = "QueueMode_AB" }
local QUEUE_MODE_ROW = { xf = "OCTO_BG_ROW_XF_ID", fx = "OCTO_BG_ROW_FX_ID" }
local QUEUE_MODE_LABEL = { xf = "Cross-Faction", fx = "Factioned", fa = "First Available" }
local function QueueMode(bgTitle)
    local key = QUEUE_MODE_KEY[bgTitle]
    local mode = key and AutoBG_Settings and AutoBG_Settings[key]
    if mode == "fa" or mode == "fx" then return mode end
    return "xf"
end
local function QueueRow(bgTitle)
    local want = QUEUE_MODE_ROW[QueueMode(bgTitle)]
    if not want then return 0 end
    local id = _G[want]
    for k = 1, GetNumBattlefields() do
        if GetBattlefieldInstanceInfo(k) == id then return k end
    end
    return 0
end

frame:SetScript("OnEvent", function()
    local ev, a1, a2 = event, arg1, arg2

    if ev == "ADDON_LOADED" and a1 == addonName then
        if not AutoBG_Settings then AutoBG_Settings = defaultSettings
        else
            for k, v in pairs(defaultSettings) do
                if AutoBG_Settings[k] == nil then AutoBG_Settings[k] = v end
            end
        end
        -- A saved key nothing owns goes (KNOWN_PATTERNS KP-64), so a retired
        -- setting needs no line of its own: AutoBG owns its defaults and these.
        for key in pairs(AutoBG_Settings) do
            if defaultSettings[key] == nil and not SAVED_TABLES[key] then AutoBG_Settings[key] = nil end
        end
        -- Older/manual SavedVariables must not break queue comparisons or sliders.
        if not ARENA_TYPES[AutoBG_Settings.ArenaType] then AutoBG_Settings.ArenaType = 0 end
        local delay = tonumber(AutoBG_Settings.AutoAcceptDelay) or 0
        if delay ~= delay then delay = 0 end
        AutoBG_Settings.AutoAcceptDelay = math.max(0, math.min(AutoBG_MAX_ENTER_DELAY, math.floor(delay)))

        AutoBG_Targets:EnsureOptions()
        AutoBG_Spy:EnsureOptions()

        UpdateZoneCache()
        SyncMatchChat()
        AutoBG_Print("v1.0.0 loaded. Type |cFFFFFF00/abg|r or |cFFFFFF00/bgt|r for options.", true)

    elseif ev == "PLAYER_LEAVING_WORLD" then
        rejoinWorldReady = false
        if rejoinRequest then
            if rejoinRequest.timer then rejoinRequest.timer:Cancel(); rejoinRequest.timer = nil end
            rejoinRequest.phase = "world"
            rejoinRequest.deadline = nil
            rejoinRequest.readyDeadline = nil
        end

    elseif ev == "PLAYER_ENTERING_WORLD" or ev == "ZONE_CHANGED_NEW_AREA" then
        if ev == "PLAYER_ENTERING_WORLD" then matchSide = nil end
        local wasInBattleground = currentZonePVP
        UpdateZoneCache()
        SyncMatchChat()

        if currentZonePVP then
            local match = MatchName()
            if match ~= "" then
                lastPlayedBG = match
                if AutoBG_Settings then AutoBG_Settings.LastPlayedBG = match end
            end
            if not wasInBattleground then
                FinishRejoin()
                rejoinWorldReady = false
            end
        else
            -- ZONE_CHANGED_NEW_AREA too: the world can load while the old zone still
            -- reads as the arena, and the rejoin must not wait for a second load.
            rejoinWorldReady = true
            if hasHandledEnd and AutoBG_Settings and AutoBG_Settings.AutoRejoin then
                TryAutoRejoin()
            elseif UnitExists("player") then
                if hasHandledEnd then FinishRejoin() end
                local hasDes, rem = AutoBG_HasDeserter()
                if hasDes then
                    FinishRejoin()
                    if not hadDeserterDebuff then
                        hadDeserterDebuff = true
                        AutoBG_Print("Auto-Rejoin / Auto-Queue halted: You have the |cFFFF5555Deserter|r debuff" .. FormatDeserterRemaining(rem) .. ". Type |cFFFFFF00/abg q all|r once Deserter expires.", true)
                    end
                    return
                end
                if AutoBG_Settings and AutoBG_Settings.AutoQueueLogin and not hasQueuedOnLogin then
                    if (AutoBG_Settings.SkipIfAFK ~= false) and AutoBG_IsPlayerAFK() then
                        AutoBG_Print("Auto-Queue on login skipped: You are tagged as |cFFFF5555AFK|r.")
                    elseif IsPlayerDeadOrGhost() then
                        needsQueueAfterResurrect = true
                    else
                        hasQueuedOnLogin = true
                        local generation = queueGeneration
                        C_Timer.After(3.0, function()
                            if generation ~= queueGeneration or not (AutoBG_Settings and AutoBG_Settings.AutoQueueLogin) then return end
                            local currDes, currRem = AutoBG_HasDeserter()
                            if currDes then
                                AutoBG_Print("Auto-Queue on login halted: You have the |cFFFF5555Deserter|r debuff" .. FormatDeserterRemaining(currRem) .. ". Type |cFFFFFF00/abg q all|r once Deserter expires.", true)
                                return
                            end
                            if (AutoBG_Settings.SkipIfAFK ~= false) and AutoBG_IsPlayerAFK() then
                                AutoBG_Print("Auto-Queue on login skipped: You are tagged as |cFFFF5555AFK|r.")
                                return
                            end
                            if not IsPlayerDeadOrGhost() then AutoBG_QueueAllBGs()
                            else needsQueueAfterResurrect = true; hasQueuedOnLogin = false end
                        end)
                    end
                end
            end
        end

    elseif ev == "BATTLEFIELDS_SHOW" then
        local request = rejoinRequest
        if request and (currentZonePVP or not rejoinWorldReady) then return end
        if request and not (AutoBG_Settings and AutoBG_Settings.AutoRejoin) then
            FinishRejoin()
            return
        end
        if request then
            if not UnitExists("player") or IsPlayerDeadOrGhost() or
               (request.phase ~= "list" and request.phase ~= "queue") then return end
            local shownBG = ShownBattlefield()
            if shownBG ~= request.bg then return end
            if AutoBG_HasDeserter() then FinishRejoin(); return end
            if request.phase == "queue" then AutoBG_HideBattlefieldWindow(); return end
        end
        -- List replies can arrive after a later manual or batch request.
        if pendingAutoRejoin and ShownBattlefield() ~= pendingAutoRejoin then return end
        if pendingAutoRejoin or isAutoQueueing then
            if (AutoBG_Settings.SkipIfAFK ~= false) and AutoBG_IsPlayerAFK() then
                AutoBG_Print("Auto-Queue / Auto-Rejoin skipped: You are tagged as |cFFFF5555AFK|r.")
                FinishRejoin()
                isAutoQueueing = false
                return
            end
            local bgTitle = pendingAutoRejoin or ShownBattlefield() or "Battleground"
            if request then
                -- A list reply is not confirmation; submit once and await status.
                request.phase = "queue"
                request.deadline = GetTime() + (request.bg == ARENA and 4 or 1.5)
            end
            local row = QueueRow(bgTitle)
            SetSelectedBattlefield(row)
            JoinBattlefield(row)

            -- For 4 s the OnShow hook hides the window again if the server reopens it.
            suppressBattlefieldFrameUntil = GetTime() + 4.0
            suppressedBattlefieldBG = bgTitle
            AutoBG_HideBattlefieldWindow()

            AutoBG_Print("Queue requested for |cFFFFFF00" .. bgTitle .. "|r (" .. (row > 0 and QUEUE_MODE_LABEL[QueueMode(bgTitle)] or "First Available") .. ").")
            pendingAutoRejoin = nil
            if not rejoinRequest then hasHandledEnd = false end
        elseif GetTime() < suppressBattlefieldFrameUntil and ShownBattlefield() == suppressedBattlefieldBG then
            AutoBG_HideBattlefieldWindow()
        end

    elseif ev == "CHAT_MSG_BG_SYSTEM_NEUTRAL" or ev == "CHAT_MSG_BG_SYSTEM_ALLIANCE" or ev == "CHAT_MSG_BG_SYSTEM_HORDE" or ev == "CHAT_MSG_SYSTEM" then
        if currentZonePVP and GetBattlefieldWinner() then HandleMatchEnd() end

    elseif ev == "UPDATE_BATTLEFIELD_STATUS" then
        if not AutoBG_Settings then return end
        for i = 1, MAX_BATTLEFIELD_QUEUES do ProcessBattlefieldQueue(i) end
        TryAutoRejoin()

    elseif ev == "PLAYER_DEAD" then
        -- Never in an arena: the dead stay until it ends.
        if AutoBG_Settings and AutoBG_Settings.AutoRelease and currentZonePVP and not currentArena then
            if not HasSoulstone() then
                RepopMe()
                StaticPopup_Hide("DEATH")
            else
                AutoBG_Print("Self-resurrection available. Preserving spirit.")
            end
        end

    elseif ev == "PLAYER_ALIVE" or ev == "PLAYER_UNGHOST" then
        if needsQueueAfterResurrect and not IsPlayerDeadOrGhost() then
            needsQueueAfterResurrect = false; hasQueuedOnLogin = true
            local generation = queueGeneration
            C_Timer.After(2.0, function()
                if generation ~= queueGeneration then return end
                if not IsPlayerDeadOrGhost() then
                    AutoBG_Print("Resurrection detected! Initiating Battleground Auto-Queue...")
                    AutoBG_QueueAllBGs()
                end
            end)
        end

    elseif ev == "UI_ERROR_MESSAGE" then
        local lower = isAutoQueueing and a1 and string.lower(a1)
        if lower and (string.find(lower, "cannot queue") or string.find(lower, "while dead")) then
            do
                isAutoQueueing = false
                FinishRejoin()
                needsQueueAfterResurrect = IsPlayerDeadOrGhost() and true or false
                if needsQueueAfterResurrect then
                    AutoBG_Print("Auto-Queue paused (cannot queue while dead). Will auto-queue once resurrected.")
                else
                    AutoBG_Print("Auto-Queue stopped: " .. a1)
                end
            end
        end

    elseif ev == "UNIT_AURA_DELTA" then
        -- A refresh only (a2 lists updated IDs alone) cannot add or remove Deserter.
        if a2 and not (a2.isFullUpdate or a2.addedAuraInstanceIDs or a2.removedAuraInstanceIDs) then return end
        local hasDes, rem = AutoBG_HasDeserter()
        if hasDes then
            if not hadDeserterDebuff then
                hadDeserterDebuff = true
                AutoBG_Print("You have received the |cFFFF5555Deserter|r debuff" .. FormatDeserterRemaining(rem) .. ". Auto-Queue is paused. Type |cFFFFFF00/abg q all|r once Deserter expires.", true)
            end
        elseif hadDeserterDebuff then
            hadDeserterDebuff = false
            AutoBG_Print("Your |cFF00FF00Deserter|r debuff has expired! You can now queue for battlegrounds by typing |cFFFFFF00/abg q all|r.", true)
            if AutoBG_Settings and AutoBG_Settings.NotifySound then
                PlaySound("ReadyCheck")
            end
            FlashTaskbar()
        end
    end
end)

-- Scoreboard Hook (Rule B10)
hooksecurefunc("WorldStateScoreFrame_Update", function()
    if currentZonePVP and GetBattlefieldWinner() then
        HandleMatchEnd()
    end
    if not AutoBG_Settings or not AutoBG_Settings.ScoreColor then return end

    local offset = FauxScrollFrame_GetOffset(WorldStateScoreScrollFrame)
    for i = 1, MAX_WORLDSTATE_SCORE_BUTTONS do
        local name, _, _, _, _, faction, _, _, class, classToken = GetBattlefieldScore(offset + i)
        if name and name ~= "" then
            -- WorldStateScoreTemplate: $parentNameButton > $parentName.
            local nameText = _G["WorldStateScoreButton" .. i .. "NameButtonName"]
            if nameText then
                local clean = string.gsub(string.gsub(name, "-.*$", ""), "^%s*(.-)%s*$", "%1")
                local color = AutoBG_GetClassColor(classToken or class)
                if color then
                    nameText:SetText(color .. clean .. "|r")
                else
                    nameText:SetText(clean)
                    if faction == 0 then nameText:SetTextColor(1.0, 0.1, 0.1) else nameText:SetTextColor(0.0, 0.68, 1.0) end
                end
            end
        end
    end
end)


-- Data-Driven Slash Command Dispatcher (Replaces 150 lines of repetitive if/elseif chains)
local function RefreshBattlegroundDisplays()
    if AutoBG_Timers_UpdateVisibility then AutoBG_Timers_UpdateVisibility() end
    if AutoBG_FC_UpdateVisibility then AutoBG_FC_UpdateVisibility() end
end

local toggleCommands = {
    s = { key = "NotifySound", label = "Loud Sound Notification" },
    sound = { key = "NotifySound", label = "Loud Sound Notification" },
    f = { key = "FlashTaskbar", label = "Taskbar Flashing" },
    flash = { key = "FlashTaskbar", label = "Taskbar Flashing" },
    msg = { key = "ChatMessages", label = "Chat Notifications" },
    chat = { key = "ChatMessages", label = "Chat Notifications" },
    a = { key = "AutoAccept", label = "Auto-Accept Queue Pop" },
    accept = { key = "AutoAccept", label = "Auto-Accept Queue Pop" },
    j = { key = "AutoRejoin", label = "Auto-Rejoin BG on Exit" },
    autorejoin = { key = "AutoRejoin", label = "Auto-Rejoin BG on Exit" },
    l = { key = "AutoLeave", label = "Auto-Leave BG on End" },
    leave = { key = "AutoLeave", label = "Auto-Leave BG on End" },
    c = { key = "ScoreColor", label = "Scoreboard Class Colors" },
    color = { key = "ScoreColor", label = "Scoreboard Class Colors" },
    r = { key = "AutoRelease", label = "Auto-Release Spirit" },
    release = { key = "AutoRelease", label = "Auto-Release Spirit" },
    start = { key = "StartTimer", label = "Game Start Timer" },
    starttimer = { key = "StartTimer", label = "Game Start Timer" },
}

SLASH_AUTOBG1 = "/abg"
SLASH_AUTOBG2 = "/autobg"
SlashCmdList["AUTOBG"] = function(msg)
    local raw = (msg and string.gsub(msg, "^%s*(.-)%s*$", "%1")) or ""
    local space = string.find(raw, " ")
    local cmd = string.lower(space and string.sub(raw, 1, space - 1) or raw)
    local arg = string.lower(space and string.gsub(string.sub(raw, space + 1), "^%s*(.-)%s*$", "%1") or "")

    if cmd == "targets" or cmd == "target" or cmd == "bgt" or cmd == "frames" then
        if AutoBG_OpenOptions then AutoBG_OpenOptions("targets") end
        return
    elseif cmd == "spy" then
        -- /abg spy kos|ignore [name], /abg spy stats; names keep their case.
        local rest = space and string.gsub(string.sub(raw, space + 1), "^%s*(.-)%s*$", "%1") or ""
        if rest ~= "" and AutoBG_Spy and AutoBG_Spy.HandleCommand and AutoBG_Spy:HandleCommand(rest) then return end
        if AutoBG_OpenOptions then AutoBG_OpenOptions("spy") end
        return
    elseif cmd == "timers" or cmd == "timer" or cmd == "fc" then
        if AutoBG_OpenOptions then AutoBG_OpenOptions("timers") end
        return
    elseif cmd == "aq" or cmd == "autoqueue" then
        if arg == "cancel" or arg == "drop" then
            AutoBG_CancelAllQueues()
        elseif arg == "now" or arg == "join" or arg == "all" then
            AutoBG_QueueAllBGs()
        elseif AutoBG_OpenOptions then
            AutoBG_OpenOptions("general")
        end
        return
    elseif cmd == "cancel" or cmd == "drop" then
        AutoBG_CancelAllQueues()
        return
    elseif cmd == "test" or cmd == "t" then
        if AutoBG_SetPreview then
            local on = not AutoBG_IsPreviewActive()
            AutoBG_SetPreview(on)
            AutoBG_Print("Test mode is now " .. (on and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r"), true)
        end
        return
    end

    if toggleCommands[cmd] then
        local entry = toggleCommands[cmd]
        AutoBG_Settings[entry.key] = not AutoBG_Settings[entry.key]
        if entry.key == "NotifySound" and not AutoBG_Settings.NotifySound then AutoBG_StopNotificationSound() end
        if entry.key == "StartTimer" then
            RefreshBattlegroundDisplays()
        end
        AutoBG_Print(entry.label .. " is now " .. (AutoBG_Settings[entry.key] and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r"), true)
        if AutoBG_Options_Refresh then AutoBG_Options_Refresh() end
        return
    end

    if cmd == "q" or cmd == "queue" or cmd == "join" or cmd == "rejoin" then
        local hasDeserter, remaining = AutoBG_HasDeserter()
        if hasDeserter then
            AutoBG_Print("Cannot queue: You have the |cFFFF5555Deserter|r debuff" .. FormatDeserterRemaining(remaining) .. ". Type |cFFFFFF00/abg q all|r once Deserter expires.", true)
            return
        end
        if arg == "all" or arg == "3" or arg == "bg" or arg == "bgs" or arg == "" then AutoBG_QueueAllBGs(); return end
        if arg == "cancel" or arg == "drop" then AutoBG_CancelAllQueues(); return end
        local target = (arg == "arena" and ARENA) or (string.find(arg, "wsg") and "Warsong Gulch") or (string.find(arg, "ab") and "Arathi Basin") or (string.find(arg, "av") and "Alterac Valley") or (string.find(arg, "tg") and "Thorn Gorge") or (AutoBG_Settings and AutoBG_Settings.LastPlayedBG) or lastPlayedBG
        if target then
            if AutoBG_Settings then AutoBG_Settings.LastPlayedBG = target end
            AutoBG_Print("Quick-queue triggered for |cFFFFFF00" .. target .. "|r...", true)
            AutoBG_TriggerBattlegroundFinder(target)
        else
            AutoBG_Print("No previous BG recorded. Opening the battleground menu...", true)
            TWMiniMapBattlefieldFrame:Click()
        end
    elseif cmd == "delay" or cmd == "acceptdelay" then
        local val = tonumber(arg)
        if val then
            AutoBG_Settings.AutoAcceptDelay = math.max(0, math.min(AutoBG_MAX_ENTER_DELAY, math.floor(val)))
            AutoBG_Print("Auto-Accept Enter Delay set to |cFFFFFF00" .. (AutoBG_Settings.AutoAcceptDelay == 0 and "Instant (0s)" or (AutoBG_Settings.AutoAcceptDelay .. "s")) .. "|r", true)
            if AutoBG_Options_Refresh then AutoBG_Options_Refresh() end
        else
            AutoBG_Print("Current Auto-Accept Enter Delay: |cFFFFFF00" .. ((AutoBG_Settings.AutoAcceptDelay or 0) == 0 and "Instant (0s)" or (AutoBG_Settings.AutoAcceptDelay .. "s")) .. "|r", true)
        end
    elseif cmd == "efc" or cmd == "tar" then
        if AutoBG_TargetCarrier then AutoBG_TargetCarrier("enemy") end
    elseif cmd == "ffc" then
        if AutoBG_TargetCarrier then AutoBG_TargetCarrier("friendly") end
    elseif cmd == "arena" then
        AutoBG_OpenOptions("arena")
    elseif cmd == "focus" then
        if AutoBG_FocusCarrier then AutoBG_FocusCarrier("enemy") end
    elseif cmd == "reset" then
        AutoBG_Settings = nil; AutoBG_Print("Settings reset to default. Reloading UI...", true); ReloadUI()
    elseif cmd == "help" then
        AutoBG_Print("|cFF00FF00AutoBG Commands:|r /abg, /abg aq [now|cancel], /abg q [ab|wsg|av|tg|arena|all], /abg cancel, /abg targets, /abg arena, /abg spy, /abg spy kos|ignore [name], /abg spy stats, /abg spy raids, /abg a, /abg delay <sec>, /abg l, /abg j, /abg r, /abg c, /abg efc, /abg ffc, /abg focus, /abg test, /abg reset", true)
    else
        AutoBG_OpenOptions("general")
    end
end

-- /bgt: enemy frames and Spy shortcuts.
SLASH_BATTLEGROUNDTARGETS1 = "/bgt"
SlashCmdList["BATTLEGROUNDTARGETS"] = function(msg)
    local raw = (msg and string.gsub(msg, "^%s*(.-)%s*$", "%1")) or ""
    local space = string.find(raw, " ")
    local cmd = string.lower(space and string.sub(raw, 1, space - 1) or raw)
    local arg = string.lower(space and string.gsub(string.sub(raw, space + 1), "^%s*(.-)%s*$", "%1") or "")

    if cmd == "test" then
        if AutoBG_Targets and AutoBG_Targets.ToggleTestMode then
            local sz = tonumber(arg)
            AutoBG_Targets:ToggleTestMode(sz)
            AutoBG_Print("Enemy frames preview " .. (AutoBG_Targets.isConfig and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r"), true)
        end
    elseif cmd == "spy" then
        if AutoBG_Spy and AutoBG_Spy.ToggleTestMode then
            AutoBG_Spy:ToggleTestMode()
            AutoBG_Print("Spy radar preview " .. (AutoBG_Spy.isTestMode and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r"), true)
        end
    elseif cmd == "reset" then
        if AutoBG_Targets and AutoBG_Targets.ResetPosition then
            AutoBG_Targets:ResetPosition()
        end
        if AutoBG_Spy and AutoBG_Spy.ResetPosition then
            AutoBG_Spy:ResetPosition()
        end
        AutoBG_Print("Enemy frames and Spy positions reset to defaults.", true)
    elseif cmd == "help" then
        AutoBG_Print("|cFF00FF00AutoBG enemy frames:|r /bgt, /bgt test [10|15|40], /bgt spy, /bgt reset", true)
    else
        AutoBG_OpenOptions("targets")
    end
end
