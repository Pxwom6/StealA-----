--!strict
--[[
	The title over each player's head (Config/Titles): one BillboardGui per character, "TitleTag" on its Head, built by
	the server so every client sees the same thing with no code of its own. It is rebuilt only when the title changes
	(the player attribute "Title", written by StyleService) or the character respawns, and otherwise left alone.

	Readable and out of the way, like Roblox's own names: pixel-sized (the same size on screen near or far), hidden
	beyond Titles.nametag.maxDistance, drawn over the world (AlwaysOnTop) with a dark outline and no lighting, just above
	the head under Roblox's name. It is hidden while its wearer carries a Snackling (the loot sits on their head and the
	THIEF! marker floats over it: StealService calls refresh when a carry starts and ends), and from the wearer
	themself (PlayerToHideFrom): nothing over your own character in the middle of your screen, where the prompts are.

	Bounty Hunt (BountyService) puts its 🎯 BOUNTY marker in the title's place over the target (the player attribute
	"Bounty": "on", or "resting" for a while after a claim: dimmed, with a 💤), larger and seen from much further away,
	so hunters can find them across the map, plus a gold outline round their character (a Highlight, seen through
	nothing). Like the title, the marker hides while they carry (StealService's THIEF! marker says BOUNTY instead) and
	from the target themself; the outline shows to everyone, the target too.

	The text comes from config, never from players, so it needs no filtering.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local Titles = require(ReplicatedStorage.Shared.Config.Titles)
local Types = require(ReplicatedStorage.Shared.Types)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local StyleRules = require(ReplicatedStorage.Shared.Logic.StyleRules)
local Sessions = require(script.Parent.Sessions)

type Session = Sessions.Session

local Nametags = {}

Nametags.TAG_NAME = "TitleTag"
Nametags.ATTRIBUTE = "Title" -- on the Player: the title id worn, "" for none
Nametags.BOUNTY_TAG = "BountyTag"
Nametags.BOUNTY_GLOW = "BountyGlow"
Nametags.BOUNTY_ATTRIBUTE = "Bounty" -- on the Player: "on" | "resting" | nil (BountyService)

-- The bounty marker: bigger than a title and readable from across the map.
local BOUNTY_SIZE = Vector2.new(170, 36)
local BOUNTY_MAX_DISTANCE = 450

local function build(head: BasePart, def: Types.TitleDef, player: Player): BillboardGui
	local cfg = Titles.nametag
	local gui = Instance.new("BillboardGui")
	gui.Name = Nametags.TAG_NAME
	gui.Size = UDim2.fromOffset(cfg.width, cfg.height)
	gui.StudsOffsetWorldSpace = Vector3.new(0, head.Size.Y / 2 + cfg.offset, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = cfg.maxDistance
	gui.LightInfluence = 0
	gui.PlayerToHideFrom = player
	gui:SetAttribute("TitleId", def.id)
	local label = Instance.new("TextLabel")
	label.Name = "Title"
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(6, 2) -- StyleLayout.spec measures every title in this box
	label.Size = UDim2.new(1, -12, 1, -4)
	label.FontFace = UiTheme.displayFont
	label.TextScaled = true
	label.Text = `{def.icon} {def.text}`
	label.TextColor3 = UiTheme.color(def.color)
	label.Parent = gui
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = cfg.maxTextSize
	limit.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = UiTheme.palette("stroke")
	stroke.Parent = label
	gui.Parent = head
	return gui
end

local function buildBounty(head: BasePart, player: Player, state: string): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = Nametags.BOUNTY_TAG
	gui.Size = UDim2.fromOffset(BOUNTY_SIZE.X, BOUNTY_SIZE.Y)
	gui.StudsOffsetWorldSpace = Vector3.new(0, head.Size.Y / 2 + Titles.nametag.offset + 0.4, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = BOUNTY_MAX_DISTANCE
	gui.LightInfluence = 0
	gui.PlayerToHideFrom = player
	gui:SetAttribute("State", state)
	local label = Instance.new("TextLabel")
	label.Name = "Bounty"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.FontFace = UiTheme.displayFont
	label.TextScaled = true
	label.Text = if state == "on" then Theme.text.bountyMarker else Theme.text.bountyMarkerResting
	label.TextColor3 = UiTheme.world(if state == "on" then "bounty" else "bountyResting")
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = UiTheme.palette("stroke")
	stroke.Parent = label
	gui.Parent = head
	return gui
end

-- The bounty's marker and outline on `character` for `state` ("on" | "resting" | nil: none).
local function refreshBounty(character: Model, head: BasePart, session: Session, state: string?)
	local existing = head:FindFirstChild(Nametags.BOUNTY_TAG)
	if existing and (state == nil or not existing:IsA("BillboardGui") or existing:GetAttribute("State") ~= state) then
		existing:Destroy()
		existing = nil
	end
	local glow = character:FindFirstChild(Nametags.BOUNTY_GLOW)
	if state == nil then
		if glow then
			glow:Destroy()
		end
		return
	end
	local gui = if existing and existing:IsA("BillboardGui") then existing else buildBounty(head, session.player, state)
	gui.Enabled = session.carry == nil
	local highlight = if glow and glow:IsA("Highlight") then glow else nil
	if highlight == nil then
		local created = Instance.new("Highlight")
		created.Name = Nametags.BOUNTY_GLOW
		created.DepthMode = Enum.HighlightDepthMode.Occluded
		created.Parent = character
		highlight = created
	end
	local outline = highlight :: Highlight
	local color = UiTheme.world(if state == "on" then "bounty" else "bountyResting")
	outline.FillColor = color
	outline.OutlineColor = color
	outline.FillTransparency = if state == "on" then 0.82 else 1
	outline.OutlineTransparency = if state == "on" then 0.1 else 0.5
end

-- Makes `session`'s character show the title they wear (or none), visible unless they carry a Snackling, or the
-- bounty in its place while Bounty Hunt has one on them. Cheap when nothing changed; safe to call any time (no
-- character yet, no head: nothing to do).
function Nametags.refresh(session: Session)
	local character = session.player.Character
	local head = character and character:FindFirstChild("Head")
	if character == nil or head == nil or not head:IsA("BasePart") then
		return
	end
	local bounty = session.player:GetAttribute(Nametags.BOUNTY_ATTRIBUTE)
	local bountyState = if bounty == "on" or bounty == "resting" then bounty else nil
	refreshBounty(character, head, session, bountyState)
	local id = session.player:GetAttribute(Nametags.ATTRIBUTE)
	local def = if type(id) == "string" and id ~= "" then StyleRules.titleById(Titles, id) else nil
	local existing = head:FindFirstChild(Nametags.TAG_NAME)
	if existing and (def == nil or not existing:IsA("BillboardGui") or existing:GetAttribute("TitleId") ~= def.id) then
		existing:Destroy()
		existing = nil
	end
	if def == nil then
		return
	end
	local gui = if existing and existing:IsA("BillboardGui") then existing else build(head, def, session.player)
	gui.Enabled = session.carry == nil and bountyState == nil
end

return Nametags
