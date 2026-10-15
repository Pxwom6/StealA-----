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

	The text comes from config, never from players, so it needs no filtering.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Titles = require(ReplicatedStorage.Shared.Config.Titles)
local Types = require(ReplicatedStorage.Shared.Types)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local StyleRules = require(ReplicatedStorage.Shared.Logic.StyleRules)
local Sessions = require(script.Parent.Sessions)

type Session = Sessions.Session

local Nametags = {}

Nametags.TAG_NAME = "TitleTag"
Nametags.ATTRIBUTE = "Title" -- on the Player: the title id worn, "" for none

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

-- Makes `session`'s character show the title they wear (or none), visible unless they carry a Snackling. Cheap when
-- nothing changed; safe to call any time (no character yet, no head: nothing to do).
function Nametags.refresh(session: Session)
	local character = session.player.Character
	local head = character and character:FindFirstChild("Head")
	if head == nil or not head:IsA("BasePart") then
		return
	end
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
	gui.Enabled = session.carry == nil
end

return Nametags
