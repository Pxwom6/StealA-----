--!strict
--[[
	Builds the whole map at server start: ground, the central conveyor, 8 base plots facing it (podiums, collect
	pads, lock button, podium-upgrade pad, entrance barrier, force-field dome, owner sign), the two leaderboard boards
	and the lobby spawn; then SceneryBuilder adds the lighting and everything around them (spawn plaza, Snack Factory,
	chute, trees, boundary wall, terrain). Geometry comes from Config/Gameplay.map, colours from Config/Theme.world —
	so a new map layout is mostly a data change.

	The gameplay geometry is a contract the services rely on (DECISIONS.md #3): the names and attributes (Plot{n},
	Podiums/Podium{i}/Base|Pad, LockButton, UpgradePad, Barrier, Dome, Sign, LobbySpawn), the plot rectangles, floor
	heights, entrance positions, podium / pad / button positions and the belt line. Everything added for looks (floor
	tiles, posts, podium collars, pad rings, belt chevrons, board frames...) is decoration: anchored, CanCollide /
	CanTouch / CanQuery off, in each plot's "Decor" folder or next to what it decorates, and never higher than the
	plot sign players can already stand on.

	A base's cosmetic surfaces (the floor's checker tiles, the aisle rug, the wall tops and corner caps) are painted by
	MapBuilder.paintPlot: the plot's own colours (Classic), VIP's gold, or a base skin (Config/Skins). Nothing else
	about a plot ever changes colour, and a map change (restyle) never repaints them.

	Plot local space: origin at floor centre, local -Z (the CFrame LookVector) points at the belt / entrance.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Gameplay = require(ReplicatedStorage.Shared.Config.Gameplay)
local MapThemes = require(ReplicatedStorage.Shared.Config.MapThemes)
local Scenery = require(ReplicatedStorage.Shared.Config.Scenery)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local Types = require(ReplicatedStorage.Shared.Types)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local CreatureVisuals = require(ReplicatedStorage.Shared.CreatureVisuals)
local BeltMath = require(ReplicatedStorage.Shared.Logic.BeltMath)
local NewsLayout = require(ReplicatedStorage.Shared.Logic.NewsLayout)
local SceneryLayout = require(ReplicatedStorage.Shared.Logic.SceneryLayout)
local StealRules = require(ReplicatedStorage.Shared.Logic.StealRules)
local StyleRules = require(ReplicatedStorage.Shared.Logic.StyleRules)
local SceneryBuilder = require(script.Parent.SceneryBuilder)
local WorldLighting = require(script.Parent.WorldLighting)

export type PodiumRefs = {
	index: number,
	model: Model,
	base: BasePart,
	pad: BasePart,
	standCFrame: CFrame, -- where a creature's feet go, facing the aisle
	padPosition: Vector3,
	collar: BasePart, -- decoration that follows the podium's active state (MapBuilder.setPodiumActive)
	ring: BasePart,
}

-- A floor tile, and where it lies: `row` 0 at the entrance end, `side` 1 or 2 of the aisle (StyleRules.tileIndex).
export type PlotTile = { part: BasePart, row: number, side: number }

export type PlotRefs = {
	index: number,
	model: Model,
	origin: CFrame,
	rect: StealRules.Rect,
	spawnCFrame: CFrame,
	exitPosition: Vector3, -- just outside the entrance (where ejected visitors land)
	floorY: number, -- world Y of the top of the plot floor
	podiums: { PodiumRefs },
	lockButton: BasePart,
	upgradePad: BasePart,
	barrier: BasePart,
	dome: BasePart,
	sign: BasePart,
	signLabel: TextLabel,
	signIncome: TextLabel,
	signAvatar: ImageLabel, -- the owner's headshot (MapBuilder.setSignOwner)
	-- The cosmetic surfaces a base skin paints (MapBuilder.paintPlot): floor tiles, the aisle rug, the wall tops (solid)
	-- and the corner posts' caps (decoration).
	tiles: { PlotTile },
	rug: BasePart,
	wallTrims: { BasePart },
	caps: { BasePart },
	walls: { BasePart },
	accent: Color3, -- this plot's colour (Theme.plotColors)
}

export type World = {
	plots: { PlotRefs },
	belt: BeltMath.Belt,
	beltSurfaceY: number,
	leaderboards: { cash: BasePart, steals: BasePart },
	newsBoard: BasePart, -- the What's New board's panel (NewsService writes the newest update on it)
	lobbySpawn: CFrame,
	groundY: number, -- world Y of the top of the ground
	walkwayY: number, -- world Y of the top of the walkway between the plots and the belt
}

local MAP = Gameplay.map
local FLOOR_TOP = 0.4
local WALKWAY_TOP = 0.2
local PODIUM_HEIGHT = 1.4
-- Collect pads: a small glowing square right beside each podium on the aisle side, with a thin ring of the plot's
-- colour around it (Gameplay.collect.padRange is sized to it). They were 4.2 studs with a 6.4 ring, 6.4 from the
-- podium centre, which made each side of a base read as one block of neon tiles (DECISIONS.md #27).
local PAD_SIZE = 2.8
local PAD_RING = 3.8
local PAD_OFFSET = 4.6 -- podium centre to pad centre: the podium's half width (2.5), a 0.7 gap, half the pad
local LOBBY_TOP = 0.3 -- the spawn plaza's paving (SceneryBuilder)
local SIGN_PIXELS_PER_STUD = 40
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

local MapBuilder = {}

local decorCount = 0

-- Parts outside the scenery whose colour (and for the ground and walkway, material) follows the map theme.
type Painted = { part: BasePart, key: string, material: ("ground" | "walkway")? }
local painted: { Painted } = {}
local mapFolder: Folder? = nil

local function paint(part: BasePart, key: string, material: ("ground" | "walkway")?)
	part:SetAttribute("Paint", key)
	table.insert(painted, { part = part, key = key, material = material })
end

local function materialNamed(name: string, fallback: Enum.Material): Enum.Material
	return (Enum.Material :: any)[name] or fallback
end

-- Applies the theme's colours and materials to the painted parts.
local function repaint(theme: Types.MapThemeDef)
	for _, entry in painted do
		entry.part.Color = UiTheme.world(entry.key)
		if entry.material == "ground" then
			entry.part.Material = materialNamed(theme.groundMaterial, Enum.Material.Grass)
		elseif entry.material == "walkway" then
			entry.part.Material = materialNamed(theme.walkwayMaterial, Enum.Material.SmoothPlastic)
		end
	end
end

-- The theme to build with: its palette goes on top of Config/Theme.world first.
local function useTheme(themeId: string): Types.MapThemeDef
	local theme = MapThemes.themes[themeId] or MapThemes.themes[MapThemes.order[1]]
	UiTheme.setWorldOverrides(theme.palette)
	return theme
end

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		(p :: any)[key] = value
	end
	return p
end

-- Decoration: looks only. Never collides, never touched, invisible to raycasts and spatial queries.
local function decor(props: { [string]: any }): Part
	local p = part(props)
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	decorCount += 1
	return p
end

local function textLabel(props: { [string]: any }): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.FontFace = UiTheme.displayFont
	label.TextScaled = true
	for key, value in props do
		(label :: any)[key] = value
	end
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = UiTheme.palette("stroke")
	stroke.Parent = label
	return label
end

-- Roblox cylinders run along X: this size and rotation stand one upright.
local function cylinderSize(height: number, diameter: number): Vector3
	return Vector3.new(height, diameter, diameter)
end
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90))

function MapBuilder.plotOrigin(index: number): CFrame
	local north = index <= MAP.plotsPerSide
	local column = (index - 1) % MAP.plotsPerSide
	local spanX = MAP.plotsPerSide * MAP.plotWidth + (MAP.plotsPerSide - 1) * MAP.plotGap
	local x = -spanX / 2 + MAP.plotWidth / 2 + column * (MAP.plotWidth + MAP.plotGap)
	local z = (if north then 1 else -1) * (MAP.walkwayWidth + MAP.plotDepth / 2)
	local cf = CFrame.new(x, 0, z)
	if not north then
		cf *= CFrame.Angles(0, math.pi, 0)
	end
	return cf
end

-- Local position of podium `i` (1-based). Podiums fill two columns from the entrance backwards.
function MapBuilder.podiumLocal(i: number): Vector3
	local column = (i - 1) % MAP.podiumColumns
	local row = (i - 1) // MAP.podiumColumns
	local x = if column == 0 then -MAP.podiumColumnOffset else MAP.podiumColumnOffset
	local z = -MAP.plotDepth / 2 + MAP.podiumFirstRowOffset + row * MAP.podiumRowSpacing
	return Vector3.new(x, 0, z)
end

-- Shows a podium as usable (within the owner's capacity) or locked: the base, its collar, the collect pad and the
-- pad's glow ring. PlotService calls this whenever capacity or ownership changes.
function MapBuilder.setPodiumActive(podium: PodiumRefs, active: boolean, accent: Color3)
	podium.base.Color = if active then UiTheme.world("podium") else UiTheme.world("lockedPodium")
	podium.base.Transparency = if active then 0 else 0.6
	podium.collar.Color = if active then accent else UiTheme.world("lockedPodium")
	podium.collar.Transparency = if active then 0 else 0.6
	podium.pad.Transparency = if active then 0.15 else 1
	podium.ring.Transparency = if active then 0.45 else 1
end

-- The owner's avatar headshot on the plot sign (userId > 0), or none for a free plot (Studio test players have no
-- avatar: their sign just shows the name). The name and income texts are set by PlotService.
function MapBuilder.setSignOwner(plot: PlotRefs, userId: number)
	local avatarFrame = plot.signAvatar.Parent
	local textArea = plot.signLabel.Parent
	local showAvatar = userId > 0
	plot.signAvatar.Image = if showAvatar then `rbxthumb://type=AvatarHeadShot&id={userId}&w=150&h=150` else ""
	if avatarFrame and avatarFrame:IsA("GuiObject") then
		avatarFrame.Visible = showAvatar
	end
	if textArea and textArea:IsA("GuiObject") then
		local inset = if showAvatar then 4.4 * SIGN_PIXELS_PER_STUD + 6 else 16
		textArea.Position = UDim2.fromOffset(inset, 0)
		textArea.Size = UDim2.new(1, -inset - 16, 1, 0)
	end
	local alignment = if showAvatar then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center
	plot.signLabel.TextXAlignment = alignment
	plot.signIncome.TextXAlignment = alignment
end

-- Paints a base's cosmetic surfaces: `look` (a base skin's, Config/Skins) or nil for the plot's own colours (Classic:
-- a checker of the shared neutrals blended with the plot's colour, a rug of it, white trims), with VIP's gold where
-- StyleRules.trimSources says (all the trims on a Classic base, the corner caps under any other skin). A rainbow
-- skin's trims are tagged CreatureVisuals.RAINBOW_TAG, so every client cycles their hue (MutationFxController, off with
-- Reduce effects); each trim's RestColor attribute is the colour a client puts back when that stops. Walls, the sign,
-- podiums, pads and buttons are never touched, and neither is anything here by a map change.
function MapBuilder.paintPlot(plot: PlotRefs, look: Types.SkinLook?, vip: boolean)
	local accent = plot.accent
	local light = UiTheme.world("plotTileLight"):Lerp(accent, 0.18)
	local dark = UiTheme.world("plotTileDark"):Lerp(accent, 0.32)
	for _, tile in plot.tiles do
		if look then
			tile.part.Color = UiTheme.color(look.tiles[StyleRules.tileIndex(tile.row, tile.side, #look.tiles)])
			tile.part.Material = materialNamed(look.tileMaterial, Enum.Material.CeramicTiles)
		else
			tile.part.Color = if StyleRules.tileIndex(tile.row, tile.side, 2) == 1 then light else dark
			tile.part.Material = Enum.Material.CeramicTiles
		end
	end
	plot.rug.Color = if look then UiTheme.color(look.rug) else accent:Lerp(WHITE, 0.15)
	plot.rug.Material = if look then materialNamed(look.rugMaterial, Enum.Material.Fabric) else Enum.Material.Fabric

	local wallSource, capSource = StyleRules.trimSources(look, vip)
	local count = #plot.wallTrims + #plot.caps
	local function paintTrim(trim: BasePart, source: StyleRules.TrimSource, order: number)
		local color, material, rainbow = UiTheme.world("wall"), Enum.Material.SmoothPlastic, false
		if source == "skin" and look then
			color = UiTheme.color(look.trim)
			material = materialNamed(look.trimMaterial, Enum.Material.SmoothPlastic)
			rainbow = look.rainbow == true
		elseif source == "vip" then
			color, material = UiTheme.world("vipTrim"), Enum.Material.Neon
		end
		trim:SetAttribute("RestColor", color)
		if rainbow then
			trim:SetAttribute("HueOffset", order / count) -- the colours chase each other round the base
			CollectionService:AddTag(trim, CreatureVisuals.RAINBOW_TAG)
		elseif CollectionService:HasTag(trim, CreatureVisuals.RAINBOW_TAG) then
			CollectionService:RemoveTag(trim, CreatureVisuals.RAINBOW_TAG)
		end
		trim.Color = color
		trim.Material = material
	end
	for i, trim in plot.wallTrims do
		paintTrim(trim, wallSource, i - 1)
	end
	for i, cap in plot.caps do
		paintTrim(cap, capSource, #plot.wallTrims + i - 1)
	end
end

-- The owner sign's face: avatar circle on the left, name and cash/sec on the right.
local function buildSignGui(sign: BasePart, accent: Color3): (TextLabel, TextLabel, ImageLabel)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "OwnerSign"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = SIGN_PIXELS_PER_STUD
	gui.LightInfluence = 0
	gui.Parent = sign

	local avatarSize = sign.Size.Y * SIGN_PIXELS_PER_STUD - 28
	local avatarFrame = Instance.new("Frame")
	avatarFrame.Name = "AvatarFrame"
	avatarFrame.AnchorPoint = Vector2.new(0, 0.5)
	avatarFrame.Position = UDim2.new(0, 16, 0.5, 0)
	avatarFrame.Size = UDim2.fromOffset(avatarSize, avatarSize)
	avatarFrame.BackgroundColor3 = accent:Lerp(WHITE, 0.7)
	avatarFrame.Visible = false
	avatarFrame.Parent = gui
	local frameCorner = Instance.new("UICorner")
	frameCorner.CornerRadius = UDim.new(0.5, 0)
	frameCorner.Parent = avatarFrame
	local frameStroke = Instance.new("UIStroke")
	frameStroke.Thickness = 6
	frameStroke.Color = UiTheme.palette("stroke")
	frameStroke.Parent = avatarFrame
	local avatar = Instance.new("ImageLabel")
	avatar.Name = "Avatar"
	avatar.Size = UDim2.fromScale(1, 1)
	avatar.BackgroundTransparency = 1
	avatar.Image = ""
	avatar.ScaleType = Enum.ScaleType.Crop
	avatar.Parent = avatarFrame
	local avatarCorner = Instance.new("UICorner")
	avatarCorner.CornerRadius = UDim.new(0.5, 0)
	avatarCorner.Parent = avatar

	local textArea = Instance.new("Frame")
	textArea.Name = "Text"
	textArea.BackgroundTransparency = 1
	textArea.Position = UDim2.fromOffset(16, 0)
	textArea.Size = UDim2.new(1, -32, 1, 0)
	textArea.Parent = gui
	local signLabel = textLabel({
		Name = "Owner",
		Size = UDim2.fromScale(1, 0.6),
		Position = UDim2.fromScale(0, 0.04),
		TextColor3 = UiTheme.palette("text"),
		Text = Theme.text.freePlotSign,
		Parent = textArea,
	})
	local signIncome = textLabel({
		Name = "Income",
		Size = UDim2.fromScale(1, 0.34),
		Position = UDim2.fromScale(0, 0.62),
		TextColor3 = UiTheme.palette("cash"),
		Text = "",
		Parent = textArea,
	})
	return signLabel, signIncome, avatar
end

local function buildPlot(index: number, parent: Instance): PlotRefs
	local origin = MapBuilder.plotOrigin(index)
	local w, d, h = MAP.plotWidth, MAP.plotDepth, MAP.wallHeight
	local plotColor = UiTheme.plotColor(index)
	local postColor = plotColor:Lerp(BLACK, 0.35)

	local model = Instance.new("Model")
	model.Name = `Plot{index}`
	model:SetAttribute("PlotIndex", index)
	model:SetAttribute("OwnerUserId", 0)
	model:SetAttribute("OwnerName", "")
	model:SetAttribute("LockedUntil", 0)
	model:SetAttribute("GraceUntil", 0)
	model:SetAttribute("Capacity", 0)
	model:SetAttribute("NextPodiumCost", -1)

	local decorFolder = Instance.new("Folder")
	decorFolder.Name = "Decor"
	decorFolder.Parent = model

	-- The floor is the (invisible) collider; what you see is a rug down the aisle and checker tiles either side, at
	-- exactly the floor's height (no surface sits on another, so nothing flickers).
	local floor = part({
		Name = "Floor",
		Size = Vector3.new(w, FLOOR_TOP, d),
		CFrame = origin * CFrame.new(0, FLOOR_TOP / 2, 0),
		Color = plotColor:Lerp(WHITE, 0.55),
		Material = Enum.Material.CeramicTiles, -- footstep sounds
		Transparency = 1,
		Parent = model,
	})
	floor:SetAttribute("Kind", "Floor")
	-- Colours and materials of the rug, tiles, trims and caps come from MapBuilder.paintPlot (below).
	local aisle = MAP.entranceWidth / 2
	local rug = decor({
		Name = "Rug",
		Size = Vector3.new(aisle * 2, FLOOR_TOP, d),
		CFrame = origin * CFrame.new(0, FLOOR_TOP / 2, 0),
		CastShadow = false,
		Parent = decorFolder,
	})
	local sideWidth = w / 2 - aisle
	local rows = 4
	local tiles: { PlotTile } = {}
	for sideIndex, side in { -1, 1 } do
		for row = 0, rows - 1 do
			local tile = decor({
				Name = "Tile",
				Size = Vector3.new(sideWidth, FLOOR_TOP, d / rows),
				CFrame = origin
					* CFrame.new(side * (aisle + sideWidth / 2), FLOOR_TOP / 2, -d / 2 + (row + 0.5) * d / rows),
				CastShadow = false,
				Parent = decorFolder,
			})
			table.insert(tiles, { part = tile, row = row, side = sideIndex })
		end
	end

	-- Walls (front wall has an entrance gap facing the belt)
	local walls: { BasePart } = {}
	local wallTrims: { BasePart } = {}
	local wallY = FLOOR_TOP + h / 2
	local function wall(name: string, size: Vector3, localPos: Vector3)
		local wallPart = part({
			Name = name,
			Size = size,
			CFrame = origin * CFrame.new(localPos),
			Color = plotColor,
			Parent = model,
		})
		table.insert(walls, wallPart)
		local trim = part({
			Name = name .. "Trim",
			Size = Vector3.new(size.X + 0.2, 0.5, size.Z + 0.2),
			CFrame = origin * CFrame.new(localPos + Vector3.new(0, size.Y / 2 + 0.25, 0)),
			Parent = model,
		})
		table.insert(wallTrims, trim)
	end
	wall("LeftWall", Vector3.new(1, h, d), Vector3.new(-w / 2 + 0.5, wallY, 0))
	wall("RightWall", Vector3.new(1, h, d), Vector3.new(w / 2 - 0.5, wallY, 0))
	wall("BackWall", Vector3.new(w, h, 1), Vector3.new(0, wallY, d / 2 - 0.5))
	local segment = (w - MAP.entranceWidth) / 2
	wall(
		"FrontWallL",
		Vector3.new(segment, h, 1),
		Vector3.new(-(MAP.entranceWidth / 2 + segment / 2), wallY, -d / 2 + 0.5)
	)
	wall(
		"FrontWallR",
		Vector3.new(segment, h, 1),
		Vector3.new(MAP.entranceWidth / 2 + segment / 2, wallY, -d / 2 + 0.5)
	)

	-- Corner posts with caps (the caps are trim: VIP gilds them with the rest, and keeps them gold under a skin), and
	-- gate posts holding the sign.
	local postHeight = h + 0.9
	local caps: { BasePart } = {}
	for _, corner in { Vector2.new(-1, -1), Vector2.new(1, -1), Vector2.new(-1, 1), Vector2.new(1, 1) } do
		local at = Vector3.new(corner.X * (w / 2 - 0.5), 0, corner.Y * (d / 2 - 0.5))
		decor({
			Name = "Post",
			Size = Vector3.new(1.8, postHeight, 1.8),
			CFrame = origin * CFrame.new(at + Vector3.new(0, FLOOR_TOP + postHeight / 2, 0)),
			Color = postColor,
			Parent = decorFolder,
		})
		table.insert(
			caps,
			decor({
				Name = "PostCap",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * 1.6,
				CFrame = origin * CFrame.new(at + Vector3.new(0, FLOOR_TOP + postHeight + 0.5, 0)),
				Parent = decorFolder,
			})
		)
	end
	local signY = FLOOR_TOP + h + 3
	local signSize = Vector3.new(MAP.entranceWidth + 6, 4.4, 0.8)
	local signBottom = signY - signSize.Y / 2
	for _, side in { -1, 1 } do
		decor({
			Name = "GatePost",
			Size = Vector3.new(1.6, signBottom - FLOOR_TOP, 1.6),
			CFrame = origin
				* CFrame.new(side * (MAP.entranceWidth / 2 + 0.8), (FLOOR_TOP + signBottom) / 2, -d / 2 + 0.5),
			Color = postColor,
			Parent = decorFolder,
		})
	end

	-- Entrance barrier (collidable only while locked; the owner's client disables it locally)
	local barrier = part({
		Name = "Barrier",
		Size = Vector3.new(MAP.entranceWidth, h + 4, 1),
		CFrame = origin * CFrame.new(0, FLOOR_TOP + (h + 4) / 2, -d / 2 + 0.5),
		Color = UiTheme.world("lockField"),
		Material = Enum.Material.ForceField,
		Transparency = 1,
		CanCollide = false,
		CastShadow = false,
		Parent = model,
	})

	-- Force-field dome over the whole plot (visual only; the server ejects visitors while locked)
	local dome = part({
		Name = "Dome",
		Size = Vector3.new(w + 2, h + 10, d + 2),
		CFrame = origin * CFrame.new(0, FLOOR_TOP + (h + 10) / 2, 0),
		Color = UiTheme.world("lockField"),
		Material = Enum.Material.ForceField,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Parent = model,
	})

	-- Owner sign above the entrance (same size and place as always: players can stand on it), framed in white.
	local sign = part({
		Name = "Sign",
		Size = signSize,
		CFrame = origin * CFrame.new(0, signY, -d / 2 + 0.5),
		Color = plotColor,
		Parent = model,
	})
	decor({
		Name = "SignBorder",
		Size = Vector3.new(signSize.X + 0.8, signSize.Y + 0.8, 0.5),
		CFrame = sign.CFrame * CFrame.new(0, 0, signSize.Z / 2 + 0.25),
		Color = UiTheme.world("signBorder"),
		Parent = decorFolder,
	})
	local signLabel, signIncome, signAvatar = buildSignGui(sign, plotColor)

	-- Podiums: a pedestal with a coloured collar, and a glowing ring under the collect pad.
	local podiumsFolder = Instance.new("Folder")
	podiumsFolder.Name = "Podiums"
	podiumsFolder.Parent = model
	local podiums: { PodiumRefs } = {}
	for i = 1, MAP.maxPodiums do
		local localPos = MapBuilder.podiumLocal(i)
		local column = (i - 1) % MAP.podiumColumns
		local towardAisle = if column == 0 then 1 else -1
		local podiumModel = Instance.new("Model")
		podiumModel.Name = `Podium{i}`
		podiumModel:SetAttribute("PodiumIndex", i)
		podiumModel:SetAttribute("PlotIndex", index)
		podiumModel:SetAttribute("Active", false)
		podiumModel:SetAttribute("CreatureId", "")
		podiumModel:SetAttribute("Stored", 0)
		podiumModel:SetAttribute("Income", 0)
		podiumModel:SetAttribute("BeingStolen", false)

		local base: BasePart = part({
			Name = "Base",
			Size = Vector3.new(5, PODIUM_HEIGHT, 5),
			CFrame = origin * CFrame.new(localPos + Vector3.new(0, FLOOR_TOP + PODIUM_HEIGHT / 2, 0)),
			Color = UiTheme.world("lockedPodium"),
			Transparency = 0.6,
			Parent = podiumModel,
		})
		-- Just below the base's top edge, so the top a creature stands on stays the base's own.
		local collar: BasePart = decor({
			Name = "Collar",
			Size = Vector3.new(5.6, 0.35, 5.6),
			CFrame = origin * CFrame.new(localPos + Vector3.new(0, FLOOR_TOP + PODIUM_HEIGHT - 0.225, 0)),
			Color = UiTheme.world("lockedPodium"),
			Transparency = 0.6,
			CastShadow = false,
			Parent = podiumModel,
		})
		local padLocal = localPos + Vector3.new(towardAisle * PAD_OFFSET, FLOOR_TOP + 0.15, 0)
		local pad: BasePart = part({
			Name = "Pad",
			Size = Vector3.new(PAD_SIZE, 0.3, PAD_SIZE),
			CFrame = origin * CFrame.new(padLocal),
			Color = UiTheme.world("collectPad"),
			Material = Enum.Material.Neon,
			Transparency = 1,
			CanCollide = false,
			Parent = podiumModel,
		})
		local ring: BasePart = decor({
			Name = "PadRing",
			Size = cylinderSize(0.2, PAD_RING),
			CFrame = origin * CFrame.new(padLocal.X, FLOOR_TOP + 0.1, padLocal.Z) * UPRIGHT,
			Color = plotColor,
			Material = Enum.Material.Neon,
			Transparency = 1,
			CastShadow = false,
			Parent = podiumModel,
		})
		local standPosition = (origin * CFrame.new(localPos + Vector3.new(0, FLOOR_TOP + PODIUM_HEIGHT + 0.1, 0))).Position
		local facing = (origin * CFrame.new(localPos + Vector3.new(towardAisle, FLOOR_TOP + PODIUM_HEIGHT + 0.1, 0))).Position
		podiumModel.PrimaryPart = base
		podiumModel.Parent = podiumsFolder
		table.insert(podiums, {
			index = i,
			model = podiumModel,
			base = base,
			pad = pad,
			standCFrame = CFrame.lookAt(standPosition, facing),
			padPosition = pad.Position,
			collar = collar,
			ring = ring,
		})
	end

	-- Lock button just inside the entrance, on a dark plinth with a glowing ring.
	local lockCFrame = origin * CFrame.new(0, FLOOR_TOP + 0.6, -d / 2 + 7)
	local lockButton = part({
		Name = "LockButton",
		Size = Vector3.new(1.2, 4, 4),
		CFrame = lockCFrame * CFrame.Angles(0, 0, math.rad(90)),
		Shape = Enum.PartType.Cylinder,
		Color = UiTheme.world("lockButton"),
		Material = Enum.Material.Neon,
		Parent = model,
	})
	decor({
		Name = "LockPlinth",
		Size = cylinderSize(0.3, 5.8),
		CFrame = origin * CFrame.new(0, FLOOR_TOP + 0.15, -d / 2 + 7) * UPRIGHT,
		Color = UiTheme.world("lockPlinth"),
		CastShadow = false,
		Parent = decorFolder,
	})
	decor({
		Name = "LockRing",
		Size = cylinderSize(0.1, 7),
		CFrame = origin * CFrame.new(0, FLOOR_TOP + 0.05, -d / 2 + 7) * UPRIGHT,
		Color = UiTheme.world("lockField"),
		Material = Enum.Material.Neon,
		Transparency = 0.35,
		CastShadow = false,
		Parent = decorFolder,
	})

	-- Podium upgrade pad at the back wall, framed, with a big "+" on it.
	local upgradePad = part({
		Name = "UpgradePad",
		Size = Vector3.new(6, 0.4, 4),
		CFrame = origin * CFrame.new(0, FLOOR_TOP + 0.2, d / 2 - 4),
		Color = UiTheme.world("upgradePad"),
		Material = Enum.Material.Neon,
		Parent = model,
	})
	decor({
		Name = "UpgradeFrame",
		Size = Vector3.new(7.2, 0.3, 5.2),
		CFrame = origin * CFrame.new(0, FLOOR_TOP + 0.15, d / 2 - 4),
		Color = UiTheme.world("upgradeFrame"),
		CastShadow = false,
		Parent = decorFolder,
	})
	local plusGui = Instance.new("SurfaceGui")
	plusGui.Name = "Plus"
	plusGui.Face = Enum.NormalId.Top
	plusGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	plusGui.PixelsPerStud = 25
	plusGui.LightInfluence = 0
	plusGui.Parent = upgradePad
	textLabel({ Size = UDim2.fromScale(1, 1), Text = "+", TextColor3 = WHITE, Parent = plusGui })

	model.PrimaryPart = floor
	model.Parent = parent

	local position = origin.Position
	local spawnLocal = Vector3.new(0, FLOOR_TOP + 3, -d / 2 + 14)
	local spawnPosition = (origin * CFrame.new(spawnLocal)).Position
	local entranceDirection = origin.LookVector
	local refs: PlotRefs = {
		index = index,
		model = model,
		origin = origin,
		rect = {
			minX = position.X - w / 2,
			maxX = position.X + w / 2,
			minZ = position.Z - d / 2,
			maxZ = position.Z + d / 2,
		},
		spawnCFrame = CFrame.lookAt(spawnPosition, spawnPosition + entranceDirection),
		exitPosition = (origin * CFrame.new(0, FLOOR_TOP + 3, -d / 2 - 6)).Position,
		floorY = origin.Position.Y + FLOOR_TOP,
		podiums = podiums,
		lockButton = lockButton,
		upgradePad = upgradePad,
		barrier = barrier,
		dome = dome,
		sign = sign,
		signLabel = signLabel,
		signIncome = signIncome,
		signAvatar = signAvatar,
		tiles = tiles,
		rug = rug,
		wallTrims = wallTrims,
		caps = caps,
		walls = walls,
		accent = plotColor,
	}
	MapBuilder.paintPlot(refs, nil, false)
	return refs
end

local function buildBelt(parent: Instance): (BeltMath.Belt, number)
	local cfg = Gameplay.belt
	local beltModel = Instance.new("Model")
	beltModel.Name = "Conveyor"
	local surfaceY = cfg.surfaceY
	local beltLength = cfg.length + 12
	part({
		Name = "Belt",
		Size = Vector3.new(beltLength, surfaceY, cfg.width),
		CFrame = CFrame.new(0, surfaceY / 2, 0),
		Color = UiTheme.world("belt"),
		Material = Enum.Material.DiamondPlate,
		Parent = beltModel,
	})
	for _, side in { -1, 1 } do
		part({
			Name = "Rail",
			Size = Vector3.new(beltLength, surfaceY + 0.6, 0.8),
			CFrame = CFrame.new(0, (surfaceY + 0.6) / 2, side * (cfg.width / 2 + 0.4)),
			Color = UiTheme.world("beltTrim"),
			Parent = beltModel,
		})
		-- A rounded bumper along the top of each rail.
		decor({
			Name = "RailBumper",
			Size = Vector3.new(beltLength, 0.7, 0.7),
			Shape = Enum.PartType.Cylinder,
			CFrame = CFrame.new(0, surfaceY + 0.75, side * (cfg.width / 2 + 0.4)),
			Color = UiTheme.world("beltBumper"),
			CastShadow = false,
			Parent = beltModel,
		})
	end

	-- Chevrons on the belt pointing the way items travel (+X). WorldFxController slides them along at belt speed;
	-- the ends of the belt are hidden inside the factory intake and the chute, so they wrap around unseen.
	local chevrons = Instance.new("Folder")
	chevrons.Name = "Chevrons"
	local spacing = Scenery.chevronSpacing
	local count = math.ceil(beltLength / spacing)
	chevrons:SetAttribute("Spacing", spacing)
	chevrons:SetAttribute("Speed", cfg.length / cfg.travelSeconds)
	for i = 0, count - 1 do
		local tipX = -beltLength / 2 + i * spacing + 2
		for _, arm in { 1, -1 } do
			decor({
				Name = "Chevron",
				Size = Vector3.new(2.9, 0.06, 0.55),
				CFrame = CFrame.new(tipX - 1, surfaceY + 0.03, arm * 1) * CFrame.Angles(0, math.rad(arm * 45), 0),
				Color = UiTheme.world("beltChevron"),
				Transparency = 0.15,
				CastShadow = false,
				Parent = chevrons,
			})
		end
	end
	chevrons.Parent = beltModel
	beltModel.Parent = parent
	return BeltMath.centered(cfg.length, cfg.travelSeconds), surfaceY
end

-- A leaderboard on two legs with a gold frame and a header bar. The board's front faces the map centre;
-- LeaderboardService draws the rows on it.
local function buildLeaderboard(name: string, title: string, cframe: CFrame, parent: Instance): BasePart
	local boardSize = Vector3.new(18, 22, 1)
	local board = part({
		Name = name,
		Size = boardSize,
		CFrame = cframe,
		Color = UiTheme.palette("panel"),
		Parent = parent,
	})
	board:SetAttribute("Title", title)
	paint(
		decor({
			Name = name .. "Frame",
			Size = Vector3.new(boardSize.X + 1.2, boardSize.Y + 1.2, 0.6),
			CFrame = cframe * CFrame.new(0, 0, boardSize.Z / 2 + 0.2),
			Color = UiTheme.world("boardFrame"),
			Parent = parent,
		}),
		"boardFrame"
	)
	decor({
		Name = name .. "Header",
		Size = Vector3.new(boardSize.X + 2, 1.6, 2.4),
		CFrame = cframe * CFrame.new(0, boardSize.Y / 2 + 1.1, 0.3),
		Color = UiTheme.palette("primary"),
		Parent = parent,
	})
	local bottom = cframe.Position.Y - boardSize.Y / 2
	for _, side in { -1, 1 } do
		paint(
			decor({
				Name = name .. "Leg",
				Size = Vector3.new(1.4, bottom + 6, 1.4),
				CFrame = cframe * CFrame.new(side * 6.5, -boardSize.Y / 2 - (bottom - 6) / 2, 1.1),
				Color = UiTheme.world("boardPost"),
				Material = Enum.Material.Metal,
				Parent = parent,
			}),
			"boardPost"
		)
	end
	paint(
		decor({
			Name = name .. "Plinth",
			Size = Vector3.new(boardSize.X + 2, 1, 3.4),
			CFrame = cframe * CFrame.new(0, -cframe.Position.Y + 0.5, 1.1),
			Color = UiTheme.world("stoneWall"),
			Material = Enum.Material.Slate,
			Parent = parent,
		}),
		"stoneWall"
	)
	return board
end

-- The What's New board on the spawn plaza (Config/Scenery.plaza.newsBoard, placed by SceneryLayout and checked with
-- the rest of the scenery): a dark panel in a frame on two legs, facing the fountain. NewsService writes the newest
-- update on the panel's front. Built here, outside the Scenery folder, so a map change never rebuilds it; its frame and
-- legs follow the map's colours like the leaderboards'. The panel is solid (sheer, nothing to climb), the rest is
-- decoration.
local function buildNewsBoard(parent: Instance): BasePart
	local spot = SceneryLayout.layout(Scenery).newsBoard
	local B = NewsLayout.BOARD
	local middle = Vector3.new(spot.x, B.lift + B.h / 2, spot.z)
	local yaw = math.rad(spot.yaw)
	local cframe = CFrame.lookAt(middle, middle + Vector3.new(math.cos(yaw), 0, math.sin(yaw)))
	local panel = part({
		Name = "NewsBoard",
		Size = Vector3.new(B.w, B.h, 0.6),
		CFrame = cframe,
		Color = UiTheme.palette("panel"),
		CanTouch = false,
		Parent = parent,
	})
	paint(
		decor({
			Name = "NewsBoardFrame",
			Size = Vector3.new(B.w + 1, B.h + 1, 0.4),
			CFrame = cframe * CFrame.new(0, 0, 0.45),
			Color = UiTheme.world("boardFrame"),
			Parent = parent,
		}),
		"boardFrame"
	)
	local legHeight = B.lift + B.h / 2 -- from the ground to the panel's middle, behind it
	for _, side in { -1, 1 } do
		paint(
			decor({
				Name = "NewsBoardLeg",
				Size = Vector3.new(0.9, legHeight, 0.9),
				CFrame = cframe * CFrame.new(side * (B.w / 2 - 1.6), -legHeight / 2, 1.1),
				Color = UiTheme.world("boardPost"),
				Material = Enum.Material.Metal,
				Parent = parent,
			}),
			"boardPost"
		)
	end
	return panel
end

-- Builds the map dressed as map theme `themeId` (Config/MapThemes; an unknown id builds the first theme).
function MapBuilder.build(themeId: string): World
	local started = os.clock()
	local theme = useTheme(themeId)
	painted = {}
	-- Remove the template's baseplate / spawn so the generated map is the only geometry.
	for _, name in { "Baseplate", "SpawnLocation" } do
		local existing = workspace:FindFirstChild(name)
		if existing and existing:IsA("BasePart") then
			existing:Destroy()
		end
	end
	local old = workspace:FindFirstChild("Map")
	if old then
		old:Destroy()
	end

	WorldLighting.setBase(theme.lighting, 0)
	decorCount = 0

	local map = Instance.new("Folder")
	map.Name = "Map"
	mapFolder = map

	-- The ground under the play area (the boundary wall stands on its edge; terrain carries on outside it).
	local boundary = Scenery.boundary
	paint(
		part({
			Name = "Ground",
			Size = Vector3.new(boundary.maxX - boundary.minX, 4, boundary.maxZ - boundary.minZ),
			CFrame = CFrame.new((boundary.minX + boundary.maxX) / 2, -2, (boundary.minZ + boundary.maxZ) / 2),
			Color = UiTheme.world("ground"),
			Material = Enum.Material.Grass,
			Parent = map,
		}),
		"ground",
		"ground"
	)
	local walkwaySpan = MAP.plotsPerSide * MAP.plotWidth + (MAP.plotsPerSide - 1) * MAP.plotGap + 60
	paint(
		part({
			Name = "Walkway",
			Size = Vector3.new(walkwaySpan, WALKWAY_TOP, MAP.walkwayWidth * 2),
			CFrame = CFrame.new(0, WALKWAY_TOP / 2, 0),
			Color = UiTheme.world("walkway"),
			Parent = map,
		}),
		"walkway",
		"walkway"
	)

	local belt, beltSurfaceY = buildBelt(map)

	local plotsFolder = Instance.new("Folder")
	plotsFolder.Name = "Plots"
	plotsFolder.Parent = map
	local plots: { PlotRefs } = {}
	for i = 1, MAP.plotCount do
		table.insert(plots, buildPlot(i, plotsFolder))
	end

	-- The leaderboards flank the archway onto the spawn plaza, facing the map.
	local plaza = Scenery.plaza
	local function boardFrame(z: number): CFrame
		local position = Vector3.new(plaza.boardX, 15, z)
		return CFrame.lookAt(position, Vector3.new(0, 15, 0))
	end
	local cashBoard = buildLeaderboard("CashBoard", Theme.text.leaderboardCash, boardFrame(-plaza.boardZ), map)
	local stealsBoard = buildLeaderboard("StealsBoard", Theme.text.leaderboardSteals, boardFrame(plaza.boardZ), map)
	local newsBoard = buildNewsBoard(map)

	-- Players appear on the plaza (for a moment, until their base is assigned), facing back along the belt.
	local lobby = MAP.lobby
	local spawnPosition = Vector3.new(lobby.x, LOBBY_TOP, lobby.z)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Size = Vector3.new(8, 0.4, 8)
	spawn.CFrame = CFrame.lookAt(spawnPosition, spawnPosition - Vector3.xAxis)
	spawn.Color = UiTheme.world("lobby")
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Transparency = 0.2
	spawn.Duration = 0
	spawn.Parent = map
	paint(spawn, "lobby")
	repaint(theme)

	local sceneryParts = SceneryBuilder.build(map, theme)
	for _, problem in SceneryBuilder.validate() do
		warn(`[Scenery] config problem: {problem}`)
	end
	local extraParts = decorCount + sceneryParts
	if extraParts > Scenery.partBudget then
		warn(`[Scenery] {extraParts} decoration parts, over the budget of {Scenery.partBudget}`)
	end

	map.Parent = workspace
	print(
		string.format(
			"[MapBuilder] map built in %.0f ms (%d decoration parts, %s)",
			(os.clock() - started) * 1000,
			extraParts,
			theme.displayName
		)
	)
	return {
		plots = plots,
		belt = belt,
		beltSurfaceY = beltSurfaceY,
		leaderboards = { cash = cashBoard, steals = stealsBoard },
		newsBoard = newsBoard,
		lobbySpawn = spawn.CFrame + Vector3.new(0, 3, 0),
		groundY = 0,
		walkwayY = WALKWAY_TOP,
	}
end

-- Dresses the built map as another map theme: its colours and materials, the scenery rebuilt (trees, landmarks,
-- boundary, plaza, factory) and the lighting fading over `seconds`. Gameplay parts are never touched. Returns how many
-- scenery parts it built.
function MapBuilder.restyle(themeId: string, seconds: number): number
	local map = mapFolder
	assert(map, "MapBuilder.restyle before MapBuilder.build")
	local started = os.clock()
	local theme = useTheme(themeId)
	repaint(theme)
	local sceneryParts = SceneryBuilder.restyle(map, theme)
	WorldLighting.setBase(theme.lighting, seconds)
	if decorCount + sceneryParts > Scenery.partBudget then
		warn(
			`[Scenery] {theme.displayName}: {decorCount + sceneryParts} parts, over the budget of {Scenery.partBudget}`
		)
	end
	print(
		string.format(
			"[MapBuilder] restyled as %s in %.0f ms (%d scenery parts)",
			theme.displayName,
			(os.clock() - started) * 1000,
			sceneryParts
		)
	)
	return sceneryParts
end

return MapBuilder
