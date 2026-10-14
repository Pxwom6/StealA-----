--!strict
--[[
	Everything around the gameplay geometry (MapBuilder.build calls it at server start, MapBuilder.restyle when the map
	theme changes): the terrain outside the boundary (grass, hills, rocks, a lake), the boundary wall, the spawn plaza
	(the "Steal a Snackling" archway, a fountain with a giant cupcake Snackling, benches, lamps, flower beds), the Snack
	Factory on the belt's west end (items appear in its intake), the chute on its east end, what grows on the tree
	spots, and the map theme's landmarks outside the wall. Positions come from Logic/SceneryLayout (Config/Scenery),
	colours from Config/Theme.world with the current map's palette on top (UiTheme.world), the theme's flora and
	landmarks from server/Services/ThemeProps, and the lighting from WorldLighting. No external assets: parts, terrain
	and textures that ship with Roblox only.

	The terrain's shape is filled once; a new map only recolours it (Terrain:SetMaterialColor, water colour), which is
	instant and costs no replication of voxels.

	Nothing here changes how the game plays. Decoration is anchored with CanCollide / CanTouch / CanQuery off; the few
	solid pieces (boundary wall and its invisible barrier, the factory and chute bodies, archway pillars, fountain,
	benches, flower boxes, tree trunks) stand outside the plots, off the walkway and the belt, and none can be climbed
	higher than the plot signs (CI: tests/SceneryLayout.spec.luau). Terrain stays outside the boundary wall.

	Client-side animation (belt chevrons, the factory cog) and the "Reduce effects" setting live in WorldFxController.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Gameplay = require(ReplicatedStorage.Shared.Config.Gameplay)
local Scenery = require(ReplicatedStorage.Shared.Config.Scenery)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local Types = require(ReplicatedStorage.Shared.Types)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local MapThemeRules = require(ReplicatedStorage.Shared.Logic.MapThemeRules)
local SceneryLayout = require(ReplicatedStorage.Shared.Logic.SceneryLayout)
local ThemeProps = require(script.Parent.ThemeProps)

local SceneryBuilder = {}

local SPARKLE_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

-- The plaza paving stands a tenth of a stud above the path and walkway (0.2), so where they meet no two surfaces
-- share a plane (no flicker).
local PLAZA_TOP = 0.3

local partCount = 0

local function world(key: string): Color3
	return UiTheme.world(key)
end

local function newPart(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		(p :: any)[key] = value
	end
	partCount += 1
	return p
end

-- Decoration: never collides, never touched, invisible to raycasts and spatial queries.
local function decor(props: { [string]: any }): Part
	local p = newPart(props)
	p.CanCollide = false
	p.CanQuery = false
	return p
end

-- A solid prop players bump into (or stand on, when low).
local function solid(props: { [string]: any }): Part
	return newPart(props)
end

-- A vertical cylinder part (Roblox cylinders run along X): `height` tall, `diameter` across, centre at `cframe`.
local function cylinderSize(height: number, diameter: number): Vector3
	return Vector3.new(height, diameter, diameter)
end
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90))

local function yawFrame(x: number, y: number, z: number, yawDegrees: number): CFrame
	local position = Vector3.new(x, y, z)
	local a = math.rad(yawDegrees)
	return CFrame.lookAt(position, position + Vector3.new(math.cos(a), 0, math.sin(a)))
end

local function signText(target: BasePart, face: Enum.NormalId, text: string, pixelsPerStud: number)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixelsPerStud
	gui.LightInfluence = 0
	gui.Parent = target
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(0.92, 0.8)
	label.Position = UDim2.fromScale(0.04, 0.1)
	label.BackgroundTransparency = 1
	label.FontFace = UiTheme.displayFont
	label.TextScaled = true
	label.TextColor3 = UiTheme.palette("text")
	label.Text = text
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4
	stroke.Color = UiTheme.palette("stroke")
	stroke.Parent = label
end

local function emitter(parent: Attachment, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.LightInfluence = 0
	for key, value in props do
		(e :: any)[key] = value
	end
	e.Parent = parent
	return e
end

-- Terrain ----------------------------------------------------------------------------------------------------------

-- The terrain's colours and water for this map (instant: no voxels change).
local function paintTerrain(theme: Types.MapThemeDef)
	local terrain = workspace.Terrain
	terrain:SetMaterialColor(Enum.Material.Grass, world("terrainGrass"))
	terrain:SetMaterialColor(Enum.Material.Sand, world("terrainSand"))
	terrain:SetMaterialColor(Enum.Material.Rock, world("terrainRock"))
	terrain.WaterColor = world("terrainWater")
	terrain.WaterTransparency = theme.water.transparency
	terrain.WaterReflectance = theme.water.reflectance
	terrain.WaterWaveSize = 0.08
	terrain.WaterWaveSpeed = 6
end

-- The terrain's shape: grass all round the boundary, hills, rocks and the lake. Once per server.
local function fillTerrain()
	local terrain = workspace.Terrain
	local T = Scenery.terrain
	local b = Scenery.boundary

	-- Flat grass all around the boundary, starting under the wall's outer half (the play area keeps its Ground part).
	local edge = b.wallThickness / 2
	local e, depth = T.extent, T.depth
	local function slab(minX: number, maxX: number, minZ: number, maxZ: number)
		if maxX <= minX or maxZ <= minZ then
			return
		end
		terrain:FillBlock(
			CFrame.new((minX + maxX) / 2, -depth / 2, (minZ + maxZ) / 2),
			Vector3.new(maxX - minX, depth, maxZ - minZ),
			Enum.Material.Grass
		)
	end
	slab(-e, b.minX - edge, -e, e)
	slab(b.maxX + edge, e, -e, e)
	slab(b.minX - edge, b.maxX + edge, b.maxZ + edge, e)
	slab(b.minX - edge, b.maxX + edge, -e, b.minZ - edge)

	for _, hill in T.hills do
		terrain:FillBall(Vector3.new(hill.x, hill.height - hill.radius, hill.z), hill.radius, Enum.Material.Grass)
		-- Only the cap above ground is seen; the rest of the ball (down to ~y -130) would just be voxels every client
		-- downloads and keeps in memory. Clear everything under the ground slab.
		local below = 2 * hill.radius
		terrain:FillBlock(
			CFrame.new(hill.x, -depth - below / 2, hill.z),
			Vector3.new(2 * hill.radius + 4, below, 2 * hill.radius + 4),
			Enum.Material.Air
		)
	end
	for _, rock in T.rocks do
		terrain:FillBall(Vector3.new(rock.x, -rock.radius * 0.35, rock.z), rock.radius, Enum.Material.Rock)
	end
	local lake = T.lake
	if lake then
		-- Sandy beach ring, then the basin (sand floor), then water up to a stud below the grass.
		terrain:FillCylinder(CFrame.new(lake.x, -0.5, lake.z), 1, lake.radius + 6, Enum.Material.Sand)
		terrain:FillCylinder(CFrame.new(lake.x, -lake.depth / 2, lake.z), lake.depth, lake.radius, Enum.Material.Air)
		terrain:FillCylinder(CFrame.new(lake.x, -lake.depth - 1, lake.z), 2, lake.radius, Enum.Material.Sand)
		terrain:FillCylinder(
			CFrame.new(lake.x, -(lake.depth + 1) / 2, lake.z),
			lake.depth - 1,
			lake.radius,
			Enum.Material.Water
		)
	end
end

-- Boundary ---------------------------------------------------------------------------------------------------------

-- A low stone wall with a slate cap on the play area's edge, and an invisible barrier above it (transparent parts
-- don't block the camera), so the view reaches the hills but nobody jumps out.
local function buildBoundary(parent: Instance, theme: Types.MapThemeDef)
	local b = Scenery.boundary
	local wallMaterial = (Enum.Material :: any)[theme.boundaryMaterial] or Enum.Material.Cobblestone
	local t = b.wallThickness
	local cx, cz = (b.minX + b.maxX) / 2, (b.minZ + b.maxZ) / 2
	local width, depth = b.maxX - b.minX, b.maxZ - b.minZ
	local sides = {
		{ name = "North", size = Vector2.new(width + t, t), at = Vector2.new(cx, b.maxZ) },
		{ name = "South", size = Vector2.new(width + t, t), at = Vector2.new(cx, b.minZ) },
		{ name = "East", size = Vector2.new(t, depth - t), at = Vector2.new(b.maxX, cz) },
		{ name = "West", size = Vector2.new(t, depth - t), at = Vector2.new(b.minX, cz) },
	}
	for _, side in sides do
		solid({
			Name = side.name .. "Wall",
			Size = Vector3.new(side.size.X, b.wallHeight, side.size.Y),
			CFrame = CFrame.new(side.at.X, b.wallHeight / 2, side.at.Y),
			Color = world("stoneWall"),
			Material = wallMaterial,
			Parent = parent,
		})
		decor({
			Name = side.name .. "WallCap",
			Size = Vector3.new(side.size.X + 0.4, 0.4, side.size.Y + 0.4),
			CFrame = CFrame.new(side.at.X, b.wallHeight + 0.2, side.at.Y),
			Color = world("wallCap"),
			Material = Enum.Material.Slate,
			Parent = parent,
		})
		solid({
			Name = side.name .. "Barrier",
			Size = Vector3.new(side.size.X, b.barrierHeight, side.size.Y),
			CFrame = CFrame.new(side.at.X, b.barrierHeight / 2, side.at.Y),
			Transparency = 1,
			CastShadow = false,
			Parent = parent,
		})
	end
end

-- Trees ------------------------------------------------------------------------------------------------------------

-- Part makers for ThemeProps: same rules (and part count) as everything else here.
local function wedge(props: { [string]: any }): WedgePart
	local w = Instance.new("WedgePart")
	w.Anchored = true
	w.CanCollide = false
	w.CanTouch = false
	w.CanQuery = false
	w.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		(w :: any)[key] = value
	end
	partCount += 1
	return w
end

local kit: ThemeProps.Kit

-- What grows on a tree spot on this map (a round tree, a lollipop, a palm...): ThemeProps builds it.
local function buildTree(tree: SceneryLayout.TreeSpot, theme: Types.MapThemeDef, parent: Instance)
	ThemeProps.flora(MapThemeRules.floraFor(theme, tree.kind), tree, parent, kit)
end

-- Spawn plaza ------------------------------------------------------------------------------------------------------

-- Height of the ground a plaza prop stands on: the paving, or the grass around it.
local function groundAt(x: number, z: number): number
	local P = Scenery.plaza
	return if math.sqrt((x - P.x) ^ 2 + (z - P.z) ^ 2) < P.radius then PLAZA_TOP else 0
end

local function buildBench(spot: SceneryLayout.Spot, parent: Instance)
	local frame = yawFrame(spot.x, groundAt(spot.x, spot.z), spot.z, spot.yaw)
	solid({
		Name = "BenchSeat",
		Size = Vector3.new(4.4, 0.35, 1.5),
		CFrame = frame * CFrame.new(0, 1.45, 0),
		Color = world("bench"),
		Material = Enum.Material.WoodPlanks,
		Parent = parent,
	})
	solid({
		Name = "BenchBack",
		Size = Vector3.new(4.4, 1.3, 0.3),
		CFrame = frame * CFrame.new(0, 2.3, 0.65) * CFrame.Angles(math.rad(10), 0, 0), -- leans back
		Color = world("bench"),
		Material = Enum.Material.WoodPlanks,
		Parent = parent,
	})
	for _, side in { -1, 1 } do
		decor({
			Name = "BenchLeg",
			Size = Vector3.new(0.35, 1.3, 1.3),
			CFrame = frame * CFrame.new(side * 1.8, 0.65, 0),
			Color = world("benchLeg"),
			Material = Enum.Material.Metal,
			CastShadow = false,
			Parent = parent,
		})
	end
end

local function buildLamp(spot: SceneryLayout.Spot, parent: Instance)
	local base = CFrame.new(spot.x, groundAt(spot.x, spot.z), spot.z)
	decor({
		Name = "LampPost",
		Shape = Enum.PartType.Cylinder,
		Size = cylinderSize(8, 0.5),
		CFrame = base * CFrame.new(0, 4, 0) * UPRIGHT,
		Color = world("lampPost"),
		Material = Enum.Material.Metal,
		Parent = parent,
	})
	local lantern = decor({
		Name = "Lantern",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 1.5,
		CFrame = base * CFrame.new(0, 8.6, 0),
		Color = world("lampLight"),
		Material = Enum.Material.Neon,
		CastShadow = false,
		Parent = parent,
	})
	decor({
		Name = "LampCap",
		Shape = Enum.PartType.Cylinder,
		Size = cylinderSize(0.35, 1.8),
		CFrame = base * CFrame.new(0, 9.45, 0) * UPRIGHT,
		Color = world("lampPost"),
		Material = Enum.Material.Metal,
		Parent = parent,
	})
	local light = Instance.new("PointLight")
	light.Color = world("lampLight")
	light.Range = 14
	light.Brightness = 0.8
	light.Shadows = false
	light.Parent = lantern
end

local function buildFlowerBed(spot: SceneryLayout.Spot, parent: Instance)
	local frame = yawFrame(spot.x, groundAt(spot.x, spot.z), spot.z, spot.yaw)
	solid({
		Name = "FlowerBox",
		Size = Vector3.new(5, 1, 2.4),
		CFrame = frame * CFrame.new(0, 0.5, 0),
		Color = world("flowerBed"),
		Material = Enum.Material.WoodPlanks,
		Parent = parent,
	})
	decor({
		Name = "Soil",
		Size = Vector3.new(4.6, 0.1, 2),
		CFrame = frame * CFrame.new(0, 1.02, 0),
		Color = world("soil"),
		Material = Enum.Material.Ground,
		CastShadow = false,
		Parent = parent,
	})
	local colors = { "flower1", "flower2", "flower3", "flower4" }
	local index = 0
	for row = -1, 1, 2 do
		for column = -1, 1 do
			index += 1
			decor({
				Name = "Flower",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * (if index % 2 == 0 then 0.9 else 1.1),
				CFrame = frame * CFrame.new(column * 1.5, 1.45 + (index % 3) * 0.12, row * 0.5),
				Color = world(colors[(index + math.floor(spot.x)) % #colors + 1]),
				CastShadow = false,
				Parent = parent,
			})
		end
	end
end

-- The giant cupcake Snackling on the fountain's pedestal, facing back along the belt (-X), like the spawn.
local function buildStatue(top: CFrame, parent: Instance)
	solid({
		Name = "StatueWrapper",
		Shape = Enum.PartType.Cylinder,
		Size = cylinderSize(3.4, 6),
		CFrame = top * CFrame.new(0, 1.7, 0) * UPRIGHT,
		Color = world("statueWrapper"),
		Material = Enum.Material.Plastic,
		Parent = parent,
	})
	solid({
		Name = "StatueCake",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 6.4,
		CFrame = top * CFrame.new(0, 3.4, 0),
		Color = world("statueCake"),
		Parent = parent,
	})
	for _, layer in
		{
			{ size = Vector3.new(5.6, 2.2, 5.6), y = 6 },
			{ size = Vector3.new(4, 2, 4), y = 7.4 },
			{
				size = Vector3.new(2.4, 1.6, 2.4),
				y = 8.5,
			},
		}
	do
		local frosting = decor({
			Name = "Frosting",
			Size = layer.size,
			CFrame = top * CFrame.new(0, layer.y, 0),
			Color = world("statueFrosting"),
			Parent = parent,
		})
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = frosting
	end
	decor({
		Name = "Cherry",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 1.6,
		CFrame = top * CFrame.new(0, 9.6, 0),
		Color = world("statueCherry"),
		Parent = parent,
	})
	-- Sprinkles on the frosting.
	local sprinkleColors = { "flower1", "flower2", "flower3", "chute" }
	for i, color in sprinkleColors do
		local a = math.rad(i * 90 + 20)
		decor({
			Name = "Sprinkle",
			Size = Vector3.new(0.7, 0.22, 0.22),
			CFrame = top * CFrame.new(math.cos(a) * 2.2, 6.75, math.sin(a) * 2.2) * CFrame.Angles(0, a + 0.6, 0.3),
			Color = world(color),
			Material = Enum.Material.Neon,
			CastShadow = false,
			Parent = parent,
		})
	end
	-- Face on the wrapper's -X side.
	for _, side in { -1, 1 } do
		decor({
			Name = "Eye",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 0.95,
			CFrame = top * CFrame.new(-2.9, 2.3, side * 0.95),
			Color = world("statueEye"),
			CastShadow = false,
			Parent = parent,
		})
		decor({
			Name = "EyeShine",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 0.32,
			CFrame = top * CFrame.new(-3.3, 2.5, side * 0.95 - 0.15),
			Color = Color3.new(1, 1, 1),
			Material = Enum.Material.Neon,
			CastShadow = false,
			Parent = parent,
		})
	end
	decor({
		Name = "Smile",
		Size = Vector3.new(0.25, 0.25, 1.1),
		CFrame = top * CFrame.new(-3.02, 1.35, 0),
		Color = world("statueEye"),
		CastShadow = false,
		Parent = parent,
	})
end

local function buildFountain(parent: Instance)
	local P = Scenery.plaza
	local center = CFrame.new(P.x, 0, P.z)
	local basinHeight = 1.4
	solid({
		Name = "FountainBasin",
		Shape = Enum.PartType.Cylinder,
		Size = cylinderSize(basinHeight, P.fountainRadius * 2),
		CFrame = center * CFrame.new(0, basinHeight / 2, 0) * UPRIGHT,
		Color = world("fountain"),
		Material = Enum.Material.Marble,
		Parent = parent,
	})
	decor({
		Name = "FountainWater",
		Shape = Enum.PartType.Cylinder,
		Size = cylinderSize(0.2, P.fountainRadius * 2 - 1.4),
		CFrame = center * CFrame.new(0, basinHeight + 0.05, 0) * UPRIGHT,
		Color = world("water"),
		Material = Enum.Material.Glass,
		Transparency = 0.3,
		Reflectance = 0.15,
		CastShadow = false,
		Parent = parent,
	})
	local pedestalTop = basinHeight + 3.6
	solid({
		Name = "FountainPedestal",
		Shape = Enum.PartType.Cylinder,
		Size = cylinderSize(3.6, 4.6),
		CFrame = center * CFrame.new(0, basinHeight + 1.8, 0) * UPRIGHT,
		Color = world("fountain"),
		Material = Enum.Material.Marble,
		Parent = parent,
	})
	-- Four spouts on the rim, arcing water in towards the statue.
	for i = 0, 3 do
		local a = math.rad(45 + i * 90)
		local r = P.fountainRadius - 1.6
		local spout = decor({
			Name = "Spout",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(1, 0.8),
			CFrame = center * CFrame.new(math.cos(a) * r, basinHeight + 0.5, math.sin(a) * r) * UPRIGHT,
			Color = world("fountain"),
			Material = Enum.Material.Marble,
			Parent = parent,
		})
		local nozzle = Instance.new("Attachment")
		nozzle.Name = "Nozzle"
		nozzle.Parent = spout
		-- The spout part is rotated (UPRIGHT), so set the nozzle's world frame: its +Y (where the spray goes) points
		-- up and in towards the statue.
		local position = Vector3.new(P.x + math.cos(a) * r, basinHeight + 1.05, P.z + math.sin(a) * r)
		local inward = Vector3.new(-math.cos(a), 0, -math.sin(a))
		local direction = (Vector3.yAxis * 2 + inward).Unit
		nozzle.WorldCFrame = CFrame.lookAt(position, position + direction) * CFrame.Angles(math.rad(-90), 0, 0)
		emitter(nozzle, {
			Name = "Spray",
			Texture = SPARKLE_TEXTURE,
			Color = ColorSequence.new(Color3.fromRGB(220, 245, 255), world("water")),
			LightEmission = 0.4,
			Size = NumberSequence.new(0.35, 0.12),
			Transparency = NumberSequence.new(0.1, 0.6),
			Speed = NumberRange.new(12, 13), -- arcs about 2 studs high onto the pedestal
			SpreadAngle = Vector2.new(4, 4),
			Acceleration = Vector3.new(0, -34, 0),
			Lifetime = NumberRange.new(0.8, 0.95),
			Rate = 24,
			EmissionDirection = Enum.NormalId.Top,
		})
	end
	buildStatue(center * CFrame.new(0, pedestalTop, 0), parent)
end

local function buildArch(parent: Instance)
	local P = Scenery.plaza
	local pillarHeight = 18
	for _, side in { -1, 1 } do
		local base = CFrame.new(P.archX, 0, side * P.archSpan / 2)
		solid({
			Name = "ArchPlinth",
			Size = Vector3.new(5, 1.2, 5),
			CFrame = base * CFrame.new(0, 0.6, 0),
			Color = world("plazaBorder"),
			Material = Enum.Material.Slate,
			Parent = parent,
		})
		solid({
			Name = "ArchPillar",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(pillarHeight, 3.6),
			CFrame = base * CFrame.new(0, pillarHeight / 2, 0) * UPRIGHT,
			Color = world("archPillar"),
			Parent = parent,
		})
		for band = 1, 4 do
			decor({
				Name = "ArchStripe",
				Shape = Enum.PartType.Cylinder,
				Size = cylinderSize(1.2, 3.8),
				CFrame = base
					* CFrame.new(0, band * 4 - 1, 0)
					* CFrame.Angles(0, math.rad(band * 35), 0)
					* CFrame.Angles(math.rad(16), 0, 0)
					* UPRIGHT,
				Color = world("archStripe"),
				CastShadow = false,
				Parent = parent,
			})
		end
		decor({
			Name = "ArchTopper",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 4.4,
			CFrame = base * CFrame.new(0, pillarHeight + 9, 0), -- sits on the title board
			Color = world("archStripe"),
			Parent = parent,
		})
	end
	-- The title board across the pillar tops, readable from the belt (-X) and from the plaza (+X).
	local boardFrame = CFrame.new(P.archX, pillarHeight + 3.5, 0)
	local span = P.archSpan + 5
	local board = decor({
		Name = "ArchSign",
		Size = Vector3.new(2.4, 7, span),
		CFrame = boardFrame,
		Color = world("archSign"),
		Parent = parent,
	})
	decor({
		Name = "ArchSignBorder",
		Size = Vector3.new(1.6, 8, span + 1.4),
		CFrame = boardFrame,
		Color = world("archPillar"),
		Parent = parent,
	})
	for _, side in { -1, 1 } do
		decor({
			Name = "ArchKnob",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 3,
			CFrame = boardFrame * CFrame.new(0, 0, side * (span / 2 + 0.9)),
			Color = world("archStripe"),
			Parent = parent,
		})
	end
	signText(board, Enum.NormalId.Left, Theme.gameTitle, 30)
	signText(board, Enum.NormalId.Right, Theme.gameTitle, 30)
end

local function buildPlazaGround(parent: Instance)
	local P = Scenery.plaza
	decor({
		Name = "PlazaBorder",
		Shape = Enum.PartType.Cylinder,
		Size = cylinderSize(0.16, P.radius * 2 + 3),
		CFrame = CFrame.new(P.x, 0.08, P.z) * UPRIGHT,
		Color = world("plazaBorder"),
		Material = Enum.Material.Slate,
		CastShadow = false,
		Parent = parent,
	})
	solid({
		Name = "PlazaPaving",
		Shape = Enum.PartType.Cylinder,
		Size = cylinderSize(PLAZA_TOP, P.radius * 2),
		CFrame = CFrame.new(P.x, PLAZA_TOP / 2, P.z) * UPRIGHT,
		Color = world("plaza"),
		Material = Enum.Material.Pavement,
		CastShadow = false,
		Parent = parent,
	})
	-- The path from the walkway's end, under the archway, onto the paving.
	local walkwayEnd = SceneryLayout.walkwayHalfLength(Gameplay.map)
	local pathEnd = P.x - P.radius + 3
	local length = pathEnd - walkwayEnd
	local pathTop = 0.2 -- as high as the walkway
	solid({
		Name = "PlazaPath",
		Size = Vector3.new(length, pathTop, P.pathWidth),
		CFrame = CFrame.new(walkwayEnd + length / 2, pathTop / 2, P.z),
		Color = world("path"),
		Material = Enum.Material.Pavement,
		CastShadow = false,
		Parent = parent,
	})
	for _, side in { -1, 1 } do
		decor({
			Name = "PathEdge", -- a low kerb, under the paving's height where they overlap
			Size = Vector3.new(length, 0.26, 0.6),
			CFrame = CFrame.new(walkwayEnd + length / 2, 0.13, P.z + side * (P.pathWidth / 2 + 0.3)),
			Color = world("plazaBorder"),
			Material = Enum.Material.Slate,
			CastShadow = false,
			Parent = parent,
		})
	end
	local lobby = Gameplay.map.lobby
	decor({
		Name = "SpawnRing",
		Shape = Enum.PartType.Cylinder,
		Size = cylinderSize(0.1, 12),
		CFrame = CFrame.new(lobby.x, PLAZA_TOP + 0.03, lobby.z) * UPRIGHT,
		Color = world("spawnRing"),
		Material = Enum.Material.Neon,
		Transparency = 0.35,
		CastShadow = false,
		Parent = parent,
	})
end

-- Snack Factory and chute ------------------------------------------------------------------------------------------

local function flaps(x: number, z0: number, z1: number, top: number, bottom: number, count: number, parent: Instance)
	local width = (z1 - z0) / count
	for i = 0, count - 1 do
		decor({
			Name = "Flap",
			Size = Vector3.new(0.15, top - bottom, width - 0.12),
			CFrame = CFrame.new(x, (top + bottom) / 2, z0 + (i + 0.5) * width),
			Color = if i % 2 == 0 then world("flap") else Color3.new(1, 1, 1),
			Transparency = 0.2,
			CastShadow = false,
			Parent = parent,
		})
	end
end

local function buildFactory(parent: Instance)
	local L = Gameplay.belt.length
	local intake = SceneryLayout.factoryIntake(L)
	local hall = SceneryLayout.factoryHall(L)
	local beltHalf = Gameplay.belt.width / 2 + 0.8 -- belt + rails
	local intakeHeight = 7
	local ix = (intake.minX + intake.maxX) / 2
	local intakeLength = intake.maxX - intake.minX

	-- Intake: two side walls hugging the rails, a roof, and flaps over the opening the items come out of.
	for _, side in { -1, 1 } do
		local wallDepth = intake.maxZ - beltHalf
		solid({
			Name = "IntakeWall",
			Size = Vector3.new(intakeLength, intakeHeight, wallDepth),
			CFrame = CFrame.new(ix, intakeHeight / 2, side * (beltHalf + wallDepth / 2)),
			Color = world("factoryWall"),
			Material = Enum.Material.Brick,
			Parent = parent,
		})
	end
	solid({
		Name = "IntakeRoof",
		Size = Vector3.new(intakeLength, 2, intake.maxZ - intake.minZ),
		CFrame = CFrame.new(ix, intakeHeight + 1, 0),
		Color = world("factoryRoof"),
		Parent = parent,
	})
	decor({
		Name = "IntakeTrim",
		Size = Vector3.new(0.3, 2.2, intake.maxZ - intake.minZ + 0.4),
		CFrame = CFrame.new(intake.maxX + 0.15, intakeHeight + 1, 0),
		Color = world("factoryTrim"),
		Parent = parent,
	})
	flaps(intake.maxX - 0.2, -beltHalf, beltHalf, intakeHeight, Gameplay.belt.surfaceY + 0.2, 5, parent)
	local sign = decor({
		Name = "FactorySign",
		Size = Vector3.new(0.6, 3.6, 18),
		CFrame = CFrame.new(intake.maxX + 0.3, intakeHeight + 4.2, 0),
		Color = world("factoryRoof"),
		Parent = parent,
	})
	signText(sign, Enum.NormalId.Right, Theme.text.factorySign, 30)

	-- Hall: a brick block with a saw-tooth roof, lit windows, a door and a smoking chimney.
	local hallHeight = 14
	local hx, hz = (hall.minX + hall.maxX) / 2, (hall.minZ + hall.maxZ) / 2
	local hallLength, hallDepth = hall.maxX - hall.minX, hall.maxZ - hall.minZ
	solid({
		Name = "FactoryHall",
		Size = Vector3.new(hallLength, hallHeight, hallDepth),
		CFrame = CFrame.new(hx, hallHeight / 2, hz),
		Color = world("factoryWall"),
		Material = Enum.Material.Brick,
		Parent = parent,
	})
	local teeth = 3
	for i = 0, teeth - 1 do
		local wedge = Instance.new("WedgePart")
		wedge.Name = "SawRoof"
		wedge.Anchored = true
		wedge.CanCollide = false
		wedge.CanTouch = false
		wedge.CanQuery = false
		wedge.Material = Enum.Material.SmoothPlastic
		wedge.Color = world("factoryRoof")
		wedge.Size = Vector3.new(hallLength, 4, hallDepth / teeth)
		wedge.CFrame = CFrame.new(hx, hallHeight + 2, hall.minZ + (i + 0.5) * hallDepth / teeth)
		wedge.Parent = parent
		partCount += 1
	end
	for _, z in { -12, -4, 4, 12 } do
		decor({
			Name = "Window",
			Size = Vector3.new(0.2, 3, 4),
			CFrame = CFrame.new(hall.maxX + 0.1, 11.5, z),
			Color = world("factoryWindow"),
			Material = Enum.Material.Neon,
			Transparency = 0.15,
			CastShadow = false,
			Parent = parent,
		})
	end
	decor({
		Name = "Door",
		Size = Vector3.new(0.3, 6, 4),
		CFrame = CFrame.new(hall.maxX + 0.15, 3, -11.5),
		Color = world("factoryRoof"),
		Parent = parent,
	})
	local chimneyX, chimneyZ = hall.minX + 7, hall.minZ + 8
	local chimneyHeight = 18
	decor({
		Name = "Chimney",
		Shape = Enum.PartType.Cylinder,
		Size = cylinderSize(chimneyHeight, 4.4),
		CFrame = CFrame.new(chimneyX, hallHeight + chimneyHeight / 2, chimneyZ) * UPRIGHT,
		Color = world("chimney"),
		Material = Enum.Material.Brick,
		Parent = parent,
	})
	local chimneyTop = decor({
		Name = "ChimneyBand",
		Shape = Enum.PartType.Cylinder,
		Size = cylinderSize(1.2, 5),
		CFrame = CFrame.new(chimneyX, hallHeight + chimneyHeight - 0.6, chimneyZ) * UPRIGHT,
		Color = world("factoryTrim"),
		Parent = parent,
	})
	local smokeOut = Instance.new("Attachment")
	smokeOut.Name = "SmokeOut"
	smokeOut.Parent = chimneyTop
	smokeOut.WorldCFrame = CFrame.new(chimneyX, hallHeight + chimneyHeight + 0.2, chimneyZ)
	emitter(smokeOut, {
		Name = "Smoke",
		Texture = SMOKE_TEXTURE,
		Color = ColorSequence.new(Color3.fromRGB(245, 245, 250), Color3.fromRGB(200, 205, 215)),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 2.2),
			NumberSequenceKeypoint.new(1, 7),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(0.7, 0.6),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Speed = NumberRange.new(4, 6),
		SpreadAngle = Vector2.new(12, 12),
		Acceleration = Vector3.new(1.5, 1.2, 0.6), -- drifts with the breeze
		Lifetime = NumberRange.new(4, 6),
		Rate = 5,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-20, 20),
		EmissionDirection = Enum.NormalId.Top,
	})

	-- A big cog on the intake's north wall (spun by WorldFxController).
	local cog = Instance.new("Model")
	cog.Name = "Cog"
	local cogCenter = CFrame.new(ix, 4.2, intake.maxZ + 0.4) * CFrame.Angles(0, math.rad(90), 0)
	local disc = decor({
		Name = "CogDisc",
		Shape = Enum.PartType.Cylinder,
		Size = cylinderSize(0.8, 6),
		CFrame = cogCenter,
		Color = world("factoryCog"),
		Material = Enum.Material.Metal,
		Parent = cog,
	})
	decor({
		Name = "CogHub",
		Shape = Enum.PartType.Cylinder,
		Size = cylinderSize(1.2, 2),
		CFrame = cogCenter,
		Color = world("factoryRoof"),
		Material = Enum.Material.Metal,
		Parent = cog,
	})
	for i = 0, 5 do
		decor({
			Name = "CogTooth",
			Size = Vector3.new(0.8, 1.3, 1.4),
			CFrame = cogCenter * CFrame.Angles(math.rad(i * 60), 0, 0) * CFrame.new(0, 3.3, 0),
			Color = world("factoryCog"),
			Material = Enum.Material.Metal,
			Parent = cog,
		})
	end
	cog.PrimaryPart = disc
	cog:SetAttribute("SpinSpeed", 0.8) -- radians per second, around the disc's axis
	cog.Parent = parent
end

local function buildChute(parent: Instance)
	local rect = SceneryLayout.chute(Gameplay.belt.length)
	local beltHalf = Gameplay.belt.width / 2 + 0.8
	local height = 7
	local cx = (rect.minX + rect.maxX) / 2
	local length = rect.maxX - rect.minX
	for _, side in { -1, 1 } do
		local wallDepth = rect.maxZ - beltHalf
		solid({
			Name = "ChuteWall",
			Size = Vector3.new(length, height, wallDepth),
			CFrame = CFrame.new(cx, height / 2, side * (beltHalf + wallDepth / 2)),
			Color = world("chute"),
			Parent = parent,
		})
	end
	solid({
		Name = "ChuteBack",
		Size = Vector3.new(1.2, height, beltHalf * 2),
		CFrame = CFrame.new(rect.maxX - 0.6, height / 2, 0),
		Color = world("chute"),
		Parent = parent,
	})
	solid({
		Name = "ChuteRoof",
		Size = Vector3.new(length, 1.4, rect.maxZ - rect.minZ),
		CFrame = CFrame.new(cx, height + 0.7, 0),
		Color = world("factoryRoof"),
		Parent = parent,
	})
	decor({
		Name = "ChuteTrim",
		Size = Vector3.new(0.3, 1.6, rect.maxZ - rect.minZ + 0.4),
		CFrame = CFrame.new(rect.minX - 0.15, height + 0.7, 0),
		Color = world("factoryTrim"),
		Parent = parent,
	})
	flaps(rect.minX + 0.2, -beltHalf, beltHalf, height, Gameplay.belt.surfaceY + 0.2, 4, parent)
	local sign = decor({
		Name = "ChuteSign",
		Size = Vector3.new(0.6, 3, 13),
		CFrame = CFrame.new(rect.minX - 0.3, height + 3, 0),
		Color = world("factoryRoof"),
		Parent = parent,
	})
	signText(sign, Enum.NormalId.Left, Theme.text.chuteSign, 30)
	for _, side in { -1, 1 } do
		local warning = decor({
			Name = "WarningLight",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 1.2,
			CFrame = CFrame.new(rect.minX - 0.2, height + 1.9, side * (rect.maxZ - 0.6)),
			Color = world("archStripe"),
			Material = Enum.Material.Neon,
			CastShadow = false,
			Parent = parent,
		})
		warning:SetAttribute("Blink", true)
	end
end

-- Everything but the terrain, in a new Scenery folder under `map`. Returns how many parts it created.
local function buildScenery(map: Instance, theme: Types.MapThemeDef): number
	partCount = 0
	kit = { decor = decor, solid = solid, wedge = wedge, emitter = emitter }
	local folder = Instance.new("Folder")
	folder.Name = "Scenery"

	local boundary = Instance.new("Folder")
	boundary.Name = "Boundary"
	boundary.Parent = folder
	buildBoundary(boundary, theme)

	local plaza = Instance.new("Folder")
	plaza.Name = "Plaza"
	plaza.Parent = folder
	buildPlazaGround(plaza)
	buildArch(plaza)
	buildFountain(plaza)
	local layout = SceneryLayout.layout(Scenery)
	for _, spot in layout.benches do
		buildBench(spot, plaza)
	end
	for _, spot in layout.lamps do
		buildLamp(spot, plaza)
	end
	for _, spot in layout.flowerBeds do
		buildFlowerBed(spot, plaza)
	end

	local factory = Instance.new("Folder")
	factory.Name = "SnackFactory"
	factory.Parent = folder
	buildFactory(factory)
	local chute = Instance.new("Folder")
	chute.Name = "Chute"
	chute.Parent = folder
	buildChute(chute)

	local trees = Instance.new("Folder")
	trees.Name = "Trees"
	trees.Parent = folder
	for _, tree in layout.trees do
		buildTree(tree, theme, trees)
	end

	-- The map's landmarks, well outside the wall.
	local landmarks = Instance.new("Folder")
	landmarks.Name = "Landmarks"
	landmarks.Parent = folder
	for index, spot in Scenery.landmarkSpots do
		local kind = MapThemeRules.landmarkFor(theme, index)
		if kind then
			ThemeProps.landmark(kind, {
				x = spot.x,
				y = SceneryLayout.groundHeight(Scenery.terrain, spot.x, spot.z),
				z = spot.z,
				scale = spot.scale or 1,
				index = index,
			}, landmarks, kit)
		end
	end

	folder:SetAttribute("MapTheme", theme.displayName)
	local old = map:FindFirstChild("Scenery")
	if old then
		old:Destroy()
	end
	folder.Parent = map
	return partCount
end

-- Builds everything around the gameplay geometry under workspace.Map.Scenery, terrain included, for this map theme.
-- Returns how many parts it created.
function SceneryBuilder.build(map: Instance, theme: Types.MapThemeDef): number
	fillTerrain()
	paintTerrain(theme)
	return buildScenery(map, theme)
end

-- Rebuilds the scenery for another map theme (the terrain only changes colour). Returns how many parts it created.
function SceneryBuilder.restyle(map: Instance, theme: Types.MapThemeDef): number
	paintTerrain(theme)
	return buildScenery(map, theme)
end

-- Config problems on this map (logged at start; CI fails on them too).
function SceneryBuilder.validate(): { string }
	return SceneryLayout.validate(Scenery, Gameplay.map, Gameplay.belt, {})
end

return SceneryBuilder
