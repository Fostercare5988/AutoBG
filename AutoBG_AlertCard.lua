-- -------------------------------------------------------------------------- --
-- AutoBG: alert card                                                         --
-- The small popup that the stealth warning and the flag warning each own one --
-- of: icon, a cyan title, a class-colored name and a rim in the alert's      --
-- color. Each card has its own saved position and hides itself after a while.--
-- -------------------------------------------------------------------------- --

-- Strict Engine Dependency Guard (Mandatory ClassicAPI v1.17.11 & SuperWoW v2.2+)
local MIN_CLASSIC_API = 11711

if type(CLASSIC_API_VERSION) ~= "number" or not SUPERWOW_VERSION or
   CLASSIC_API_VERSION < MIN_CLASSIC_API then
	return
end

local _, ns = ...
local UI = ns.UI

local FONT = "Fonts\\FRIZQT__.TTF"
local SHOW_SECONDS = 4.5
local WHITE = { r = 1, g = 1, b = 1 }

local function OnDragStart(self)
	local card = self or this
	card:StartMoving()
	card.isMoving = true
end

local function OnDragStop(self)
	local card = self or this
	card:StopMovingOrSizing()
	card.isMoving = false
	if AutoBG_SavePosition then AutoBG_SavePosition(card, card:GetName()) end
end

local function OnClick(self, button)
	local card = self or this
	if card.isMoving or not card.onClick then return end
	card.onClick(card, button or arg1)
end

local function OnEnter(self)
	local card = self or this
	if not card.tooltip then return end
	GameTooltip:SetOwner(card, "ANCHOR_BOTTOM")
	for i = 1, #card.tooltip do
		GameTooltip:AddLine(card.tooltip[i], 0.75, 0.75, 0.75)
	end
	GameTooltip:Show()
end

local function OnLeave()
	GameTooltip:Hide()
end

local Card = {}

function Card:ApplyPosition()
	if AutoBG_LoadPosition then
		AutoBG_LoadPosition(self, self:GetName(), "TOP", 0, self.defaultY, "TOP")
	end
end

function Card:ResetPosition()
	if AutoBG_Settings and AutoBG_Settings.Positions then
		AutoBG_Settings.Positions[self:GetName()] = nil
	end
	self:ApplyPosition()
end

function Card:Dismiss()
	if self.timer then self.timer:Cancel(); self.timer = nil end
	self:Hide()
end

-- Fills and shows the card. persist keeps it up (previews) instead of hiding
-- it after SHOW_SECONDS.
function Card:Present(texture, title, name, color, edge, persist)
	color = color or WHITE
	self.Icon:SetTexture(texture)
	self.Title:SetText(title)
	self.Name:SetText(name)
	self.Name:SetTextColor(color.r, color.g, color.b)
	UI.Paint(self.edge, edge)
	-- Just wide enough for the longer line beside the icon.
	self:SetWidth(math.max(self.Title:GetStringWidth() or 0, self.Name:GetStringWidth() or 0) + 56)
	self:Show()

	if self.timer then self.timer:Cancel(); self.timer = nil end
	if persist then return end
	local timer
	timer = C_Timer.NewTimer(SHOW_SECONDS, function()
		if self.timer ~= timer then return end
		self.timer = nil
		self:Hide()
	end)
	self.timer = timer
end

-- name: the frame name, also the saved position key. defaultY: offset from the
-- top of the screen. onClick(card, button) handles clicks; tooltip is a list of
-- hint lines.
function ns.CreateAlertCard(name, defaultY, edge, onClick, tooltip)
	local f = CreateFrame("Button", name, UIParent)
	f:SetWidth(190)
	f:SetHeight(42)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:SetClampedToScreen(true)
	f:Hide()
	f.defaultY, f.onClick, f.tooltip = defaultY, onClick, tooltip
	for key, method in pairs(Card) do f[key] = method end

	-- ForgeUI card: soft shadow, a rim in the alert's color, the Ember surface.
	UI.Rounded(f, "BACKGROUND", 20, UI.shadowColor, 12, UI.shadow, -3)
	f.edge = UI.Rounded(f, "BORDER", 10, edge)
	UI.Rounded(f, "ARTWORK", 9, UI.surface, -1)

	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", OnDragStart)
	f:SetScript("OnDragStop", OnDragStop)
	f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	f:SetScript("OnClick", OnClick)
	f:SetScript("OnEnter", OnEnter)
	f:SetScript("OnLeave", OnLeave)

	-- Icon and text live on a child frame above the card, with their own font,
	-- so neither the card's layers nor a changed shared font can hide them.
	local content = CreateFrame("Frame", nil, f)
	content:SetAllPoints(f)
	content:SetFrameLevel(f:GetFrameLevel() + 2)
	f.Content = content

	local icon = content:CreateTexture(nil, "ARTWORK")
	icon:SetWidth(30)
	icon:SetHeight(30)
	icon:SetPoint("LEFT", f, "LEFT", 6, 0)
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	f.Icon = icon

	-- Both lines are centered in the space right of the icon.
	local title = content:CreateFontString(nil, "OVERLAY")
	title:SetFont(FONT, 10, "OUTLINE")
	title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 6, -2)
	title:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -8)
	title:SetJustifyH("CENTER")
	f.Title = title

	local nameText = content:CreateFontString(nil, "OVERLAY")
	nameText:SetFont(FONT, 12, "OUTLINE")
	nameText:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 6, 3)
	nameText:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 9)
	nameText:SetJustifyH("CENTER")
	f.Name = nameText

	f:ApplyPosition()
	return f
end
