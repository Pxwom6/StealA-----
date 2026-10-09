--!strict
--[[
	Builds the whole map at server start: ground, the central conveyor, 8 base plots facing it (podiums, collect
	pads, lock button, podium-upgrade pad, entrance barrier, force-field dome, owner sign) and two leaderboard
	boards. Geometry comes from Config/Gameplay.map, colours from Config/Theme.world — so a new map layout is
	mostly a data change.

	Plot local space: origin at floor centre, local -Z (the CFrame LookVector) points at the belt / entrance.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Gameplay = require(ReplicatedStorage.Shared.Config.Gameplay)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local BeltMath = require(ReplicatedStorage.Shared.Logic.BeltMath)
local StealRules = require(ReplicatedStorage.Shared.Logic.StealRules)

export type PodiumRefs = {
	index: number,
	model: Model,
	base: BasePart,
	pad: BasePart,
	standCFrame: CFrame, -- where a creature's feet go, facing the aisle
	padPosition: Vector3,
}

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
	trims: { BasePart },
	walls: { BasePart },
}

export type World = {
	plots: { PlotRefs },
	belt: BeltMath.Belt,
	beltSurfaceY: number,
	leaderboards: { cash: BasePart, steals: BasePart },
	lobbySpawn: CFrame,
	groundY: number, -- world Y of the top of the ground
}

local MAP = Gameplay.map
local FLOOR_TOP = 0.4
local PODIUM_HEIGHT = 1.4

local MapBuilder = {}

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

local function surfaceText(target: BasePart, face: Enum.NormalId, text: string, color: Color3): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = target
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.FontFace = UiTheme.displayFont
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = text
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = UiTheme.palette("stroke")
	stroke.Parent = label
	return label
end

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

local function buildPlot(index: number, parent: Instance): PlotRefs
	local origin = MapBuilder.plotOrigin(index)
	local w, d, h = MAP.plotWidth, MAP.plotDepth, MAP.wallHeight
	local plotColor = UiTheme.plotColor(index)

	local model = Instance.new("Model")
	model.Name = `Plot{index}`
	model:SetAttribute("PlotIndex", index)
	model:SetAttribute("OwnerUserId", 0)
	model:SetAttribute("OwnerName", "")
	model:SetAttribute("LockedUntil", 0)
	model:SetAttribute("GraceUntil", 0)
	model:SetAttribute("Capacity", 0)
	model:SetAttribute("NextPodiumCost", -1)

	local floor = part({
		Name = "Floor",
		Size = Vector3.new(w, FLOOR_TOP, d),
		CFrame = origin * CFrame.new(0, FLOOR_TOP / 2, 0),
		Color = plotColor:Lerp(Color3.new(1, 1, 1), 0.55),
		Parent = model,
	})
	floor:SetAttribute("Kind", "Floor")

	-- Walls (front wall has an entrance gap facing the belt)
	local walls: { BasePart } = {}
	local trims: { BasePart } = {}
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
			Color = UiTheme.world("wall"),
			Material = Enum.Material.SmoothPlastic,
			Parent = model,
		})
		table.insert(trims, trim)
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

	-- Owner sign above the entrance
	local sign = part({
		Name = "Sign",
		Size = Vector3.new(MAP.entranceWidth + 6, 4.4, 0.8),
		CFrame = origin * CFrame.new(0, FLOOR_TOP + h + 3, -d / 2 + 0.5),
		Color = plotColor,
		Parent = model,
	})
	local signLabel = surfaceText(sign, Enum.NormalId.Front, Theme.text.freePlotSign, UiTheme.palette("text"))
	signLabel.Size = UDim2.fromScale(1, 0.62)
	local signIncome = surfaceText(sign, Enum.NormalId.Front, "", UiTheme.palette("cash"))
	signIncome.Size = UDim2.fromScale(1, 0.38)
	signIncome.Position = UDim2.fromScale(0, 0.62)

	-- Podiums
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
		local padLocal = localPos + Vector3.new(towardAisle * 6.4, FLOOR_TOP + 0.15, 0)
		local pad: BasePart = part({
			Name = "Pad",
			Size = Vector3.new(4.2, 0.3, 4.2),
			CFrame = origin * CFrame.new(padLocal),
			Color = UiTheme.world("collectPad"),
			Material = Enum.Material.Neon,
			Transparency = 1,
			CanCollide = false,
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
		})
	end

	-- Lock button just inside the entrance
	local lockButton = part({
		Name = "LockButton",
		Size = Vector3.new(1.2, 4, 4),
		CFrame = origin * CFrame.new(0, FLOOR_TOP + 0.6, -d / 2 + 7) * CFrame.Angles(0, 0, math.rad(90)),
		Shape = Enum.PartType.Cylinder,
		Color = UiTheme.world("lockButton"),
		Material = Enum.Material.Neon,
		Parent = model,
	})

	-- Podium upgrade pad at the back wall
	local upgradePad = part({
		Name = "UpgradePad",
		Size = Vector3.new(6, 0.4, 4),
		CFrame = origin * CFrame.new(0, FLOOR_TOP + 0.2, d / 2 - 4),
		Color = UiTheme.world("upgradePad"),
		Material = Enum.Material.Neon,
		Parent = model,
	})

	model.PrimaryPart = floor
	model.Parent = parent

	local position = origin.Position
	local spawnLocal = Vector3.new(0, FLOOR_TOP + 3, -d / 2 + 14)
	local spawnPosition = (origin * CFrame.new(spawnLocal)).Position
	local entranceDirection = origin.LookVector
	return {
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
		trims = trims,
		walls = walls,
	}
end

local function buildBelt(parent: Instance): (BeltMath.Belt, number)
	local cfg = Gameplay.belt
	local beltModel = Instance.new("Model")
	beltModel.Name = "Conveyor"
	local surfaceY = cfg.surfaceY
	part({
		Name = "Belt",
		Size = Vector3.new(cfg.length + 12, surfaceY, cfg.width),
		CFrame = CFrame.new(0, surfaceY / 2, 0),
		Color = UiTheme.world("belt"),
		Material = Enum.Material.DiamondPlate,
		Parent = beltModel,
	})
	for _, side in { -1, 1 } do
		part({
			Name = "Rail",
			Size = Vector3.new(cfg.length + 12, surfaceY + 0.6, 0.8),
			CFrame = CFrame.new(0, (surfaceY + 0.6) / 2, side * (cfg.width / 2 + 0.4)),
			Color = UiTheme.world("beltTrim"),
			Parent = beltModel,
		})
	end
	-- Arches at both ends
	for _, endSide in { -1, 1 } do
		local x = endSide * (cfg.length / 2 + 4)
		for _, side in { -1, 1 } do
			part({
				Name = "Pillar",
				Size = Vector3.new(2, 12, 2),
				CFrame = CFrame.new(x, 6, side * (cfg.width / 2 + 2)),
				Color = UiTheme.world("beltTrim"),
				Parent = beltModel,
			})
		end
		local beam = part({
			Name = "ArchBeam",
			Size = Vector3.new(2.4, 3.2, cfg.width + 6),
			CFrame = CFrame.new(x, 13, 0),
			Color = UiTheme.palette("primary"),
			Parent = beltModel,
		})
		local face = if endSide < 0 then Enum.NormalId.Right else Enum.NormalId.Left
		surfaceText(beam, face, Theme.gameTitle, UiTheme.palette("text"))
	end
	beltModel.Parent = parent
	return BeltMath.centered(cfg.length, cfg.travelSeconds), surfaceY
end

local function buildLeaderboard(name: string, title: string, cframe: CFrame, parent: Instance): BasePart
	local board = part({
		Name = name,
		Size = Vector3.new(18, 22, 1),
		CFrame = cframe,
		Color = UiTheme.palette("panel"),
		Parent = parent,
	})
	part({
		Name = name .. "Post",
		Size = Vector3.new(1.5, 4, 1.5),
		CFrame = cframe * CFrame.new(0, -13, 0),
		Color = UiTheme.palette("panelLight"),
		Parent = parent,
	})
	board:SetAttribute("Title", title)
	return board
end

local function setupLighting()
	Lighting.ClockTime = 14
	Lighting.Brightness = 2.2
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 150, 160)
	Lighting.Ambient = Color3.fromRGB(90, 90, 100)
	Lighting.GlobalShadows = true
end

function MapBuilder.build(): World
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

	setupLighting()

	local map = Instance.new("Folder")
	map.Name = "Map"

	part({
		Name = "Ground",
		Size = Vector3.new(800, 4, 800),
		CFrame = CFrame.new(0, -2, 0),
		Color = UiTheme.world("ground"),
		Material = Enum.Material.Grass,
		Parent = map,
	})
	local walkwaySpan = MAP.plotsPerSide * MAP.plotWidth + (MAP.plotsPerSide - 1) * MAP.plotGap + 60
	part({
		Name = "Walkway",
		Size = Vector3.new(walkwaySpan, 0.2, MAP.walkwayWidth * 2),
		CFrame = CFrame.new(0, 0.1, 0),
		Color = UiTheme.world("walkway"),
		Parent = map,
	})

	local belt, beltSurfaceY = buildBelt(map)

	local plotsFolder = Instance.new("Folder")
	plotsFolder.Name = "Plots"
	plotsFolder.Parent = map
	local plots: { PlotRefs } = {}
	for i = 1, MAP.plotCount do
		table.insert(plots, buildPlot(i, plotsFolder))
	end

	local boardX = Gameplay.belt.length / 2 + 22
	local cashBoard = buildLeaderboard(
		"CashBoard",
		"Top Cash/sec",
		CFrame.lookAt(Vector3.new(-boardX, 15, 0), Vector3.new(0, 15, 0)),
		map
	)
	local stealsBoard = buildLeaderboard(
		"StealsBoard",
		"Top Thieves",
		CFrame.lookAt(Vector3.new(boardX, 15, 0), Vector3.new(0, 15, 0)),
		map
	)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Size = Vector3.new(8, 0.4, 8)
	spawn.CFrame = CFrame.new(0, 0.2, MAP.walkwayWidth - 8)
	spawn.Color = UiTheme.world("lobby")
	spawn.Transparency = 0.2
	spawn.Duration = 0
	spawn.Parent = map

	map.Parent = workspace
	return {
		plots = plots,
		belt = belt,
		beltSurfaceY = beltSurfaceY,
		leaderboards = { cash = cashBoard, steals = stealsBoard },
		lobbySpawn = spawn.CFrame + Vector3.new(0, 3, 0),
		groundY = 0,
	}
end

return MapBuilder
