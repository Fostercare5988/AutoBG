-- AutoBG pages: three pages in ClassicAPI's Settings window (AddOn Options, or
-- /abg), in play order (CLASSICAPI_MASTER_REFERENCE "Settings window"), the
-- frame preview and the slash words.
local _, A = ...
local db = A.db
local E = A.Enemies

-- The preview: every frame with samples, to drag; it ends when the window closes.
function A.Preview(on)
    if A.previewing == on then return end
    A.previewing = on
    A.Objectives.Preview(on)
    A.Carriers.Preview(on)
    A.FlagWatch.Preview(on)
    A.Spy.Preview(on)
    E.Preview(on)
end
if SettingsPanel then SettingsPanel:HookScript("OnHide", function() A.Preview(false) end) end

local SIZES = { ["10"] = 10, ["15"] = 15, ["40"] = 40 }
-- In a match the Frames page edits the size being played.
A.On("PLAYER_ENTERING_WORLD", function() if A.zone.size then E.editSize = A.zone.size end end)
local category
SettingsRegistrar:AddRegistrant(function()
    local layout
    category, layout = Settings.RegisterVerticalLayoutCategory("AutoBG")
    local function Section(lay, text) lay:AddInitializer(CreateSettingsListSectionHeaderInitializer(text)) end
    local function Setting(cat, key, label)
        return Settings.RegisterAddOnSetting(cat, "AutoBG_" .. key, key, db, type(A.DEFAULTS[key]), label, A.DEFAULTS[key])
    end
    local function Switch(cat, key, label, tip, parent)
        local row = Settings.CreateCheckbox(cat, Setting(cat, key, label), tip)
        if parent then row:SetParentInitializer(parent, function() return db[parent.key] end) end
        row.key = key
        return row
    end
    local function Slider(cat, setting, lo, hi, step, tip, parent, predicate)
        local options = Settings.CreateSliderOptions(lo, hi, step)
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
        local row = Settings.CreateSlider(cat, setting, options, tip)
        if parent then row:SetParentInitializer(parent, predicate) end
        return row
    end
    local function Teams()
        local c = Settings.CreateControlTextContainer()
        c:Add("xf", "Mixed", "Cross-Faction teams.")
        c:Add("fx", "Own faction", "Factioned teams.")
        c:Add("fa", "Any", "First Available.")
        return c:GetData()
    end
    local function Button(lay, name, text, fn, tip)
        lay:AddInitializer(CreateSettingsButtonInitializer(name, text, fn, tip, true))
    end

    -- One row each where the window allows it (a battleground and its teams, the
    -- login switch and Queue now), so the page fits without scrolling.
    Section(layout, "Queue")
    for _, bg in ipairs({ { "WSG", "Warsong Gulch" }, { "AB", "Arathi Basin" } }) do
        layout:AddInitializer(CreateSettingsCheckboxDropdownInitializer(
            Setting(category, "queue" .. bg[1], bg[2]), bg[2], "Queue for " .. bg[2] .. " with Queue now and at login.",
            Setting(category, "teams" .. bg[1], "Teams"), Teams, "Teams",
            "Mixed teams, your own faction, or the first that starts. A choice the server does not list gives Any."))
    end
    Switch(category, "queueAV", "Alterac Valley", "Queue for Alterac Valley with Queue now and at login.")
    layout:AddInitializer(CreateSettingsCheckboxDropdownInitializer(
        Setting(category, "queueArena", "Arena"), "Arena", "Queue for an arena with Queue now and at login.",
        Setting(category, "arenaType", "Type"), function()
            local c = Settings.CreateControlTextContainer()
            for _, t in ipairs(A.ARENA_TYPES) do c:Add(t[1], t[3]) end
            return c:GetData()
        end, "Type", "Skirmish, or a rated match with your arena team."))
    layout:AddInitializer(CreateSettingsCheckboxWithButtonInitializer(Setting(category, "queueOnLogin", "Queue at login"),
        "Queue now", function() A.Queue.QueueAll() end, nil, false,
        "Ticked: once per session at login, outside a battleground. Queue now: everything ticked above."))
    Button(layout, "Leave queues", "Leave", function() A.Queue.LeaveQueues() end, "Leave every queue you are in.")
    Switch(category, "popAlert", "Sound and flash when it pops", "The ready-check sound three times and the taskbar flash. The chat line always shows.")
    Section(layout, "The match")
    Switch(category, "release", "Release spirit when you die", "In a battleground, not in an arena, and not with a Soulstone or Reincarnation ready.")
    Switch(category, "leave", "Leave when it ends", "Stops your cast and leaves; off to stay for the scoreboard.")
    Switch(category, "rejoin", "Queue again after leaving", "The same battleground with its teams, or the arena type picked above. Three tries.")
    Settings.RegisterAddOnCategory(category)

    local function Preview(lay)
        Button(lay, "Preview frames", "Preview", function() A.Preview(not A.previewing) end,
            "Every frame with samples, to drag into place. In a battleground the places are that battleground's; outside, they go to every battleground where you have not moved the frame. It ends when this window closes.")
    end

    -- Timer bars.
    local bars, bl = Settings.RegisterVerticalLayoutSubcategory(category, "Timer bars")
    for _, key in ipairs({ "barWidth", "barHeight" }) do
        local setting = Setting(bars, key, key == "barWidth" and "Width" or "Height")
        setting:SetValueChangedCallback(A.Bars.Resize)
        Slider(bars, setting, key == "barWidth" and 120 or 14, key == "barWidth" and 320 or 36, 1)
    end
    Preview(bl)

    -- Enemy frames: each size through one dropdown, then the racials they show
    -- (the player, 2026-11-23: racial switches on a page of their own did not say
    -- what they change).
    local frames, fl = Settings.RegisterVerticalLayoutSubcategory(category, "Enemy frames")
    Preview(fl)
    Section(fl, "Layout")
    local proxies = {}
    local size = Settings.RegisterProxySetting(frames, "AutoBG_size", Settings.VarType.String, "Size", "10",
        function() for k, v in pairs(SIZES) do if v == E.editSize then return k end end end,
        function(v) E.editSize = SIZES[v] or 10 end)
    size:SetValueChangedCallback(function()
        for _, p in ipairs(proxies) do p:NotifyUpdate() end
        if A.previewing then E.Preview(true) end
    end)
    Settings.CreateDropdown(frames, size, function()
        local c = Settings.CreateControlTextContainer()
        c:Add("10", "10 v 10")
        c:Add("15", "15 v 15")
        c:Add("40", "40 v 40")
        return c:GetData()
    end, "The frame the rows below change. In a match, the size being played.")
    local function Proxy(key, label, kind)
        local p = Settings.RegisterProxySetting(frames, "AutoBG_size_" .. key, kind, label,
            function() return A.SIZE_DEFAULTS[E.editSize][key] end,
            function() return db.sizes[E.editSize][key] end,
            function(v) db.sizes[E.editSize][key] = v end)
        p:SetValueChangedCallback(E.Layout)
        proxies[#proxies + 1] = p
        return p
    end
    local show = Settings.CreateCheckbox(frames, Proxy("show", "Show", Settings.VarType.Boolean), "Show the enemy frame at this size.")
    local shown = function() return db.sizes[E.editSize].show end
    Settings.CreateCheckbox(frames, Proxy("hideRealm", "Hide realm names", Settings.VarType.Boolean),
        "Thandril, not Thandril-NZ."):SetParentInitializer(show, shown)
    Settings.CreateCheckbox(frames, Proxy("yards", "Distance in yards", Settings.VarType.Boolean),
        "How far each enemy in view is: green to 30 yards, gold to 60, orange beyond; grey when a wall or hill is between you."):SetParentInitializer(show, shown)
    Slider(frames, Proxy("width", "Width", Settings.VarType.Number), 100, 320, 1, nil, show, shown)
    Slider(frames, Proxy("height", "Height", Settings.VarType.Number), 14, 48, 1, nil, show, shown)
    Slider(frames, Proxy("text", "Text size", Settings.VarType.Number), 8, 28, 1, nil, show, shown)
    Section(fl, "Racial cooldowns")
    for _, r in ipairs(A.RACIALS) do
        local setting = Settings.RegisterAddOnSetting(frames, "AutoBG_racial_" .. r[1], r[1], db.racials,
            Settings.VarType.Boolean, r[2] .. " (" .. string.gsub(r[1], "(%l)(%u)", "%1 %2") .. ")", true)
        setting:SetValueChangedCallback(E.Layout)
        Settings.CreateCheckbox(frames, setting, "Its icon and cooldown beside the trinket on every enemy row.")
    end

    -- Spy and arena.
    local spy, sl = Settings.RegisterVerticalLayoutSubcategory(category, "Spy")
    local list = Switch(spy, "spy", "Spy list", "The enemy players around you in the open world, newest on top. Rests in battlegrounds, arenas and raids.")
    Settings.GetSetting("AutoBG_spy"):SetValueChangedCallback(function() A.Spy.Sync() end)
    local rows = Setting(spy, "spyRows", "Rows shown")
    rows:SetValueChangedCallback(function() A.Spy.Layout() end)
    Slider(spy, rows, 3, 20, 1, nil, list, function() return db.spy end)
    Switch(spy, "spySounds", "Warning sounds", "The stealth warning's sound and a ping for each new enemy.", list)
end)

SLASH_AUTOBG1 = "/abg"
SlashCmdList.AUTOBG = function(msg)
    local word, rest = string.match(string.lower(msg or ""), "^(%S*)%s*(.-)$")
    if word == "q" then
        -- A short word or the start of the name: "ab", "arathi".
        local only
        for map, bg in pairs(A.BG) do
            if bg.word and (bg.word == rest or #rest >= 3 and string.find(string.lower(map), rest, 1, true) == 1) then only = map end
        end
        if rest ~= "" and not only then return A.Print("Queue words: wsg, ab, av, arena.") end
        A.Queue.QueueAll(only)
    elseif word == "leave" then
        A.Queue.LeaveQueues()
    elseif word == "efc" then
        A.Carriers.TargetEnemy()
    elseif category then
        Settings.OpenToCategory(category:GetID())
    end
end
