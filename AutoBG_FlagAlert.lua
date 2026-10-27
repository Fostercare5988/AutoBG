-- -------------------------------------------------------------------------- --
-- AutoBG: flag alert                                                         --
-- The warning for an enemy opening a flag in Arathi Basin.                  --
-- It has its own card, apart from the stealth warning, so each can sit where --
-- the player wants it and one never hides the other.                         --
-- -------------------------------------------------------------------------- --

local _, ns = ...
local Targets = AutoBG_Targets
if not Targets or not ns.CreateAlertCard then return end

AutoBG_FlagAlert = {}
local FlagAlert = AutoBG_FlagAlert

local EDGE = { 1.0, 0.25, 0.25, 0.95 }
-- Shown until the client has seen one Opening cast and can name its icon.
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local card

-- The Opening spell is learned from the first Opening cast seen in Arathi
-- Basin (AutoBG_FlagWatch) and saved, so the icon comes from
-- the client and no spell ID is hardcoded.
function FlagAlert:LearnOpening(spellId)
	if spellId and AutoBG_Settings then AutoBG_Settings.OpeningSpell = spellId end
end

local function OpeningIcon()
	local id = AutoBG_Settings and AutoBG_Settings.OpeningSpell
	if not id then return UNKNOWN_ICON end
	local _, _, icon = SpellInfo(id)
	return icon or UNKNOWN_ICON
end

-- Tells the battleground who is opening which flag (Ctrl+left-click here or on
-- an enemy frame marked OPENING).
function FlagAlert:Announce(name, node)
	if name and node then AutoBG_SendAnnouncement(name .. " is opening " .. node) end
end

-- Left-click targets the enemy, right-click focuses them.
local function OnClick(f, button)
	if button == "LeftButton" and IsControlKeyDown() and f.node then
		FlagAlert:Announce(f.targetName, f.node)
		return
	end
	Targets.SelectEnemy(f.targetName, f.targetGUID, button)
end

local function Card()
	if not card then
		card = ns.CreateAlertCard("AutoBG_FlagAlertFrame", -190, EDGE, OnClick,
			{ "Click: target  |  Right-click: focus", "Ctrl-click: announce in chat" })
	end
	return card
end

local function Present(name, classToken, guid, node, persist)
	local f = Card()
	f.targetName, f.targetGUID, f.node = name, guid, node
	f:Present(OpeningIcon(), "|cff00ffffOpening " .. node .. "|r", name,
		classToken and Targets.GetClassColor(classToken), EDGE, persist)
end

function FlagAlert:Show(name, classToken, guid, node)
	if FlagAlert.isPreview then return end
	Present(name, classToken, guid, node)
	-- Its own sound: the stealth warning plays RaidWarning.
	PlaySound("igPVPUpdate")
end

-- The preview keeps a sample warning up so it can be dragged into place.
function FlagAlert:SetPreview(on)
	FlagAlert.isPreview = on and true or false
	if on then
		Present("Shadowstalker", "ROGUE", nil, "Blacksmith", true)
	elseif card then
		card:Dismiss()
	end
end

function FlagAlert:ResetPosition()
	if card then card:ResetPosition()
	elseif AutoBG_Settings and AutoBG_Settings.Positions then
		AutoBG_Settings.Positions["AutoBG_FlagAlertFrame"] = nil
	end
end
