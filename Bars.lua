-- AutoBG bars: the timer rows every countdown uses. A row drains by itself
-- (### statusBar:SetTimerDuration), its clock is a duration text binding
-- (### C_DurationUtil.CreateDurationTextBinding), and a group wakes once, at its
-- soonest end (### C_Timer.NewTimer). Ctrl-click announces a row.
local _, A = ...
local db = A.db
local Bars = {}
A.Bars = Bars
A.GLOSS = "Interface\\AddOns\\AutoBG\\Textures\\Gloss"
local Up = Enum.NumericRuleFormatRounding.Up
local Down = Enum.NumericRuleFormatRounding.Down

-- Clocks: "21", "1:51"; the last ten seconds in gold; "~" for a guess.
local function Clock(prefix, gold)
    local f = C_StringUtil.CreateNumericRuleFormatter()
    f:SetBreakpoints({
        { threshold = 0, step = 1, rounding = Up, format = (gold and "|cffffd100" or "") .. prefix .. "%d" .. (gold and "|r" or "") },
        { threshold = 10, step = 1, rounding = Up, format = prefix .. "%d" },
        { threshold = 60, step = 1, rounding = Up, format = prefix .. "%d:%02d",
          components = { { div = 60, step = 1, rounding = Down }, { mod = 60, step = 1, rounding = Down } } },
    })
    return f
end
Bars.CLOCK, Bars.GUESS, Bars.PLAIN = Clock("", true), Clock("~", true), Clock("", false)
local ELAPSED = { { property = Enum.DurationTextBindingProperty.ElapsedDuration, formatter = Bars.PLAIN } }

local groups = {}
local function Row(g, i)
    local r = CreateFrame("Button", nil, g)
    r:RegisterForClicks("LeftButtonUp")
    r:RegisterForDrag("LeftButton")
    r:SetScript("OnDragStart", function() if not g.locked then g:StartMoving() end end)
    r:SetScript("OnDragStop", function() A.Drop(g) end)
    r:SetScript("OnClick", function(self)
        local item = self.item
        if item and item.say and IsControlKeyDown() then
            A.Announce(item.say .. " " .. Bars.PLAIN:FormatNumber(math.max(0, item.finish - GetTime())))
        end
    end)
    A.Surface(r, 0.7)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
    r.bar = CreateFrame("StatusBar", nil, r)
    r.bar:SetStatusBarTexture(A.GLOSS)
    r.bar:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 1, 0)
    r.bar:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, 0)
    r.clock = A.Text(r.bar, 12)
    r.clock:SetPoint("RIGHT", r.bar, "RIGHT", -4, 0)
    -- The label ends where the clock begins, cut short rather than run under it
    -- (the player, 2026-11-23: "Arathi Basin (First Available)").
    r.label = A.Text(r.bar, 12)
    r.label:SetPoint("LEFT", r.bar, "LEFT", 4, 0)
    r.label:SetPoint("RIGHT", r.clock, "LEFT", -4, 0)
    r.label:SetJustifyH("LEFT")
    r.span, r.fill = C_DurationUtil.CreateDuration(), C_DurationUtil.CreateDuration()
    r.text = C_DurationUtil.CreateDurationTextBinding()
    r.text:SetFontString(r.clock)
    r.text:SetDuration(r.span)
    g.rows[i] = r
    return r
end

local function Size(g)
    local w, h = db.barWidth, db.barHeight
    g:SetWidth(w)
    for i, r in ipairs(g.rows) do
        r:SetWidth(w)
        r:SetHeight(h)
        r.icon:SetWidth(h)
        r.icon:SetHeight(h)
        r.label:SetFont("Fonts\\ARIALN.TTF", math.floor(h * 0.55 + 0.5), "OUTLINE")
        r.clock:SetFont("Fonts\\ARIALN.TTF", math.floor(h * 0.6 + 0.5), "OUTLINE")
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", g, "TOPLEFT", 0, -(i - 1) * (h + 2))
    end
end

local function Soonest(a, b)
    if a.up ~= b.up then return b.up end
    return a.finish < b.finish
end
local Draw
local function Wake(g)
    g.wake = nil
    local now = GetTime()
    for key, item in pairs(g.items) do
        if not item.up and item.finish <= now + 0.01 then
            g.items[key] = nil
            if item.onEnd then item.onEnd(item) end
        end
    end
    Draw(g)
end
Draw = function(g)
    local list = g.list
    for i = #list, 1, -1 do list[i] = nil end
    for _, item in pairs(g.items) do list[#list + 1] = item end
    table.sort(list, Soonest)
    local h = db.barHeight
    for i = 1, math.max(#list, #g.rows) do
        local item = list[i]
        local r = g.rows[i] or (item and i <= g.max and Row(g, i))
        if r and item and i <= g.max then
            r.item = item
            r.icon:SetTexture(item.icon)
            r.label:SetText(item.label)
            local c = item.color or g.color
            r.bar:SetStatusBarColor(c[1], c[2], c[3])
            if item.up then
                r.span:SetTimeSpan(item.start, item.start + 36000)
                r.text:SetTextFormat("{}", ELAPSED)
                r.fill:SetTimeSpan(item.start, item.start + (item.estimate > 0 and item.estimate or 600))
                r.bar:SetTimerDuration(r.fill, Enum.StatusBarInterpolation.Immediate, Enum.StatusBarTimerDirection.ElapsedTime)
            else
                r.span:SetTimeSpan(item.start, item.finish)
                r.text:SetFormatter(item.guess and Bars.GUESS or Bars.CLOCK)
                r.bar:SetTimerDuration(r.span, Enum.StatusBarInterpolation.Immediate, Enum.StatusBarTimerDirection.RemainingTime)
            end
            r.text:SetEnabled(true)
            r:Show()
        elseif r then
            r.item = nil
            r.text:SetEnabled(false)
            r:Hide()
        end
    end
    if g.sized ~= #g.rows then g.sized = #g.rows; Size(g) end
    g:SetHeight(math.max(1, math.min(#list, g.max)) * (h + 2))
    g:SetShown(#list > 0)
    if g.wake then g.wake:Cancel(); g.wake = nil end
    local first = list[1]
    if first and not first.up then
        g.wake = C_Timer.NewTimer(math.max(0, first.finish - GetTime()), g.onWake)
    end
end

-- A group of rows: a named frame the player can drag.
function Bars.Group(name, max, x, y, color)
    local g = CreateFrame("Frame", name, UIParent)
    g:SetPoint("TOP", UIParent, "TOP", x, y)
    g:SetWidth(db.barWidth)
    g:SetHeight(1)
    A.Movable(g)
    g.rows, g.items, g.list, g.max = {}, {}, {}, max
    g.color = color or { 0.9, 0.6, 0.2 }
    g.onWake = function() Wake(g) end
    g:Hide()
    groups[#groups + 1] = g
    -- A row that counts down: `seconds` from now (or the item's own start).
    function g:Start(key, label, seconds, icon, opts)
        local item = self.items[key] or {}
        local now = GetTime()
        item.label, item.icon, item.up = label, icon, nil
        item.start, item.finish = now, now + seconds
        item.color, item.say, item.guess, item.onEnd, item.faction = nil, nil, nil, nil, nil
        for k, v in pairs(opts or {}) do item[k] = v end
        self.items[key] = item
        Draw(self)
        return item
    end
    -- A row that counts up from `start` toward an estimate (a queue).
    function g:Up(key, label, start, estimate, icon)
        local item = self.items[key] or {}
        item.label, item.icon, item.up, item.start, item.finish = label, icon, true, start, start
        item.estimate, item.say, item.color = estimate, nil, nil
        self.items[key] = item
        Draw(self)
    end
    function g:Stop(key)
        if self.items[key] then self.items[key] = nil; Draw(self) end
    end
    function g:Clear()
        table.wipe(self.items)
        Draw(self)
    end
    return g
end

-- Width and height from the Frames page.
function Bars.Resize()
    for _, g in ipairs(groups) do Size(g); Draw(g) end
end
