--!strict
--[[
	The map themes' props (Config/MapThemes), built from plain parts: what grows on the tree spots (flora) and the big
	landmarks outside the boundary wall. SceneryBuilder calls these with its own part makers, so every part counts
	towards the scenery's part budget, and each builder makes exactly Logic/MapThemeRules.FLORA_PARTS /
	LANDMARK_PARTS[kind] parts. Colours come from Config/Theme.world through UiTheme.world, so the map's palette
	recolours them.

	Flora stays inside the footprint of the tree it replaces (MapThemeRules.FLORA_RADIUS). Inside the boundary the
	central column (trunk, stick, stem, stalk) is solid like a tree trunk and no taller than a plot sign; everything
	else is decoration (no collisions, touches or raycasts). Landmarks are decoration only.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UiTheme = require(ReplicatedStorage.Shared.UiTheme)

local ThemeProps = {}

-- Part makers from SceneryBuilder: `decor` never collides, `solid` does (players bump into it).
export type Kit = {
	decor: (props: { [string]: any }) -> Part,
	solid: (props: { [string]: any }) -> Part,
	wedge: (props: { [string]: any }) -> WedgePart,
	emitter: (parent: Attachment, props: { [string]: any }) -> ParticleEmitter,
}

-- A tree spot (Logic/SceneryLayout.TreeSpot).
export type Spot = { x: number, y: number, z: number, scale: number, seed: number, outside: boolean }

-- A landmark spot with the ground height under it.
export type LandmarkSpot = { x: number, y: number, z: number, scale: number, index: number }

local UPRIGHT = CFrame.Angles(0, 0, math.rad(90))
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

local function world(key: string): Color3
	return UiTheme.world(key)
end

-- Roblox cylinders run along X: this size stands one upright (with UPRIGHT).
local function cylinderSize(height: number, diameter: number): Vector3
	return Vector3.new(height, diameter, diameter)
end

-- A frame whose X axis runs from `a` to `b` (for cylinders and long blocks between two points).
local function along(a: Vector3, b: Vector3): CFrame
	local direction = b - a
	if direction.Magnitude < 1e-6 then
		return CFrame.new(a)
	end
	local unit = direction.Unit
	if math.abs(unit.Y) > 0.999 then
		return CFrame.new((a + b) / 2) * (if unit.Y > 0 then UPRIGHT else CFrame.Angles(0, 0, -math.rad(90)))
	end
	return CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0)
end

-- Facing the map centre (front = -Z towards (0, y, 0)).
local function facingCentre(position: Vector3): CFrame
	local target = Vector3.new(0, position.Y, 0)
	if (target - position).Magnitude < 1e-3 then
		return CFrame.new(position)
	end
	return CFrame.lookAt(position, target)
end

-- One of the four candy colours, picked by `n`.
local function candy(n: number): Color3
	return world(`candy{n % 4 + 1}`)
end

local function sphereMesh(part: BasePart)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
end

local function light(parent: BasePart, color: Color3, range: number, brightness: number)
	local pointLight = Instance.new("PointLight")
	pointLight.Color = color
	pointLight.Range = range
	pointLight.Brightness = brightness
	pointLight.Shadows = false
	pointLight.Parent = parent
end

-- Flora --------------------------------------------------------------------------------------------------------------

type FloraBuilder = (base: CFrame, s: number, random: Random, spot: Spot, parent: Instance, kit: Kit) -> ()

-- The central column: solid inside the boundary (like a tree trunk), decoration outside it.
local function core(spot: Spot, kit: Kit): (props: { [string]: any }) -> Part
	return if spot.outside then kit.decor else kit.solid
end

local function tilt(random: Random): CFrame
	return CFrame.Angles(random:NextNumber(-0.25, 0.25), random:NextNumber(0, math.pi), random:NextNumber(-0.25, 0.25))
end

local PINE_TIERS = {
	{ size = Vector3.new(7, 3, 7), y = 5, color = "pine", turn = 45 },
	{ size = Vector3.new(5.2, 2.8, 5.2), y = 7.6, color = "leavesDark", turn = 0 },
	{ size = Vector3.new(3.2, 2.6, 3.2), y = 9.9, color = "pine", turn = 45 },
}

local function pine(base: CFrame, s: number, spot: Spot, parent: Instance, kit: Kit, snowy: boolean)
	core(spot, kit)({
		Name = "Trunk",
		Shape = Enum.PartType.Cylinder,
		Size = cylinderSize(4 * s, 1.2 * s),
		CFrame = base * CFrame.new(0, 2 * s, 0) * UPRIGHT,
		Color = world("treeTrunk"),
		Material = Enum.Material.Wood,
		Parent = parent,
	})
	for _, tier in PINE_TIERS do
		local frame = base * CFrame.new(0, tier.y * s, 0) * CFrame.Angles(0, math.rad(tier.turn), 0)
		kit.decor({
			Name = "Leaves",
			Size = tier.size * s,
			CFrame = frame,
			Color = world(tier.color),
			Parent = parent,
		})
		if snowy then
			-- Snow resting on each tier: a slightly smaller, flatter block on its top.
			kit.decor({
				Name = "Snow",
				Size = Vector3.new(tier.size.X * 0.82, 0.55, tier.size.Z * 0.82) * Vector3.new(s, 1, s),
				CFrame = frame * CFrame.new(0, tier.size.Y * s / 2 + 0.2, 0),
				Color = world("snow"),
				Material = Enum.Material.Snow,
				CastShadow = false,
				Parent = parent,
			})
		end
	end
end

local flora: { [string]: FloraBuilder } = {
	-- Trunk and three tilted canopy blocks (the default map's tree).
	round = function(base: CFrame, s: number, random: Random, spot: Spot, parent: Instance, kit: Kit)
		core(spot, kit)({
			Name = "Trunk",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(7 * s, 1.5 * s),
			CFrame = base * CFrame.new(0, 3.5 * s, 0) * UPRIGHT,
			Color = world("treeTrunk"),
			Material = Enum.Material.Wood,
			Parent = parent,
		})
		for _, blob in
			{
				{ size = Vector3.new(6.4, 5.6, 6.4), at = Vector3.new(0, 8.6, 0), color = "leaves" },
				{ size = Vector3.new(4.8, 4.4, 4.8), at = Vector3.new(1.2, 11, -0.8), color = "leavesDark" },
				{ size = Vector3.new(3.6, 3.4, 3.6), at = Vector3.new(-1.4, 10.4, 1.4), color = "leavesLight" },
			}
		do
			kit.decor({
				Name = "Leaves",
				Size = blob.size * s,
				CFrame = base * CFrame.new(blob.at * s) * tilt(random),
				Color = world(blob.color),
				Parent = parent,
			})
		end
	end,

	-- Trunk and three stacked tiers.
	pine = function(base: CFrame, s: number, _random: Random, spot: Spot, parent: Instance, kit: Kit)
		pine(base, s, spot, parent, kit, false)
	end,

	-- A pine with snow on every tier.
	snowyPine = function(base: CFrame, s: number, _random: Random, spot: Spot, parent: Instance, kit: Kit)
		pine(base, s, spot, parent, kit, true)
	end,

	-- A white stick and a swirled candy disc.
	lollipop = function(base: CFrame, s: number, random: Random, spot: Spot, parent: Instance, kit: Kit)
		core(spot, kit)({
			Name = "Stick",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(7.4 * s, 0.55 * s),
			CFrame = base * CFrame.new(0, 3.7 * s, 0) * UPRIGHT,
			Color = world("candyStick"),
			Parent = parent,
		})
		local n = random:NextInteger(0, 3)
		local disc = base * CFrame.new(0, 9.4 * s, 0) * CFrame.Angles(0, random:NextNumber(0, math.pi), 0)
		kit.decor({
			Name = "Candy",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(0.9 * s, 5.2 * s),
			CFrame = disc,
			Color = candy(n),
			Parent = parent,
		})
		kit.decor({
			Name = "Swirl",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(1 * s, 3.4 * s),
			CFrame = disc,
			Color = world("candyStick"),
			CastShadow = false,
			Parent = parent,
		})
		kit.decor({
			Name = "SwirlCentre",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(1.1 * s, 1.6 * s),
			CFrame = disc,
			Color = candy(n + 2),
			CastShadow = false,
			Parent = parent,
		})
	end,

	-- A short trunk under three sugar-coated gumdrops.
	gumdropTree = function(base: CFrame, s: number, random: Random, spot: Spot, parent: Instance, kit: Kit)
		core(spot, kit)({
			Name = "Trunk",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(4.4 * s, 1 * s),
			CFrame = base * CFrame.new(0, 2.2 * s, 0) * UPRIGHT,
			Color = world("treeTrunk"),
			Material = Enum.Material.Wood,
			Parent = parent,
		})
		local n = random:NextInteger(0, 3)
		for index, drop in
			{
				{ size = 4.6, y = 5.6, x = 0 },
				{ size = 3.6, y = 8.2, x = 0.3 },
				{ size = 2.6, y = 10.1, x = -0.2 },
			}
		do
			kit.decor({
				Name = "Gumdrop",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * drop.size * s,
				CFrame = base * CFrame.new(drop.x * s, drop.y * s, 0),
				Color = candy(n + index),
				Material = Enum.Material.Sand, -- sugar coating
				Parent = parent,
			})
		end
	end,

	-- A leaning two-piece trunk, four drooping fronds and coconuts.
	palm = function(base: CFrame, s: number, random: Random, spot: Spot, parent: Instance, kit: Kit)
		local lean = random:NextNumber(0.08, 0.16)
		local mid = (base * CFrame.Angles(lean, 0, 0) * CFrame.new(0, 5 * s, 0)).Position
		local top = (base * CFrame.Angles(lean * 2, 0, 0) * CFrame.new(0, 9 * s, 0)).Position
		core(spot, kit)({
			Name = "Trunk",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(5 * s, 1.2 * s),
			CFrame = along(base.Position, mid),
			Color = world("palmTrunk"),
			Material = Enum.Material.Wood,
			Parent = parent,
		})
		kit.decor({
			Name = "TrunkTop",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize((top - mid).Magnitude + 0.4 * s, 1 * s),
			CFrame = along(mid, top),
			Color = world("palmTrunk"),
			Material = Enum.Material.Wood,
			Parent = parent,
		})
		local crown = CFrame.new(top) * CFrame.Angles(0, random:NextNumber(0, math.pi * 2), 0)
		for i = 0, 3 do
			-- Each frond leaves the crown and droops outward.
			local frond = crown * CFrame.Angles(0, math.rad(i * 90), 0) * CFrame.Angles(0, 0, math.rad(-24))
			kit.decor({
				Name = "Frond",
				Size = Vector3.new(3.6 * s, 0.3 * s, 1.5 * s),
				CFrame = frond * CFrame.new(1.8 * s, 0, 0),
				Color = world("palmLeaf"),
				Parent = parent,
			})
		end
		kit.decor({
			Name = "Coconuts",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 1.3 * s,
			CFrame = CFrame.new(top - Vector3.new(0, 0.6 * s, 0)),
			Color = world("coconut"),
			Parent = parent,
		})
	end,

	-- A saguaro: a rounded column with two arms and a flower on top.
	cactus = function(base: CFrame, s: number, random: Random, spot: Spot, parent: Instance, kit: Kit)
		local frame = base * CFrame.Angles(0, random:NextNumber(0, math.pi * 2), 0)
		local green = world("cactus")
		core(spot, kit)({
			Name = "Stalk",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(7 * s, 1.7 * s),
			CFrame = frame * CFrame.new(0, 3.5 * s, 0) * UPRIGHT,
			Color = green,
			Material = Enum.Material.Grass,
			Parent = parent,
		})
		kit.decor({
			Name = "StalkTop",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 1.7 * s,
			CFrame = frame * CFrame.new(0, 7 * s, 0),
			Color = green,
			Material = Enum.Material.Grass,
			Parent = parent,
		})
		for _, arm in { { side = -1, y = 3.2, up = 2.4 }, { side = 1, y = 4.4, up = 1.8 } } do
			local elbow = frame * CFrame.new(arm.side * 2.1 * s, arm.y * s, 0)
			kit.decor({
				Name = "Arm",
				Size = Vector3.new(2.1 * s, 1 * s, 1 * s),
				CFrame = frame * CFrame.new(arm.side * 1.05 * s, arm.y * s, 0),
				Shape = Enum.PartType.Cylinder,
				Color = green,
				Material = Enum.Material.Grass,
				Parent = parent,
			})
			kit.decor({
				Name = "ArmUp",
				Shape = Enum.PartType.Cylinder,
				Size = cylinderSize(arm.up * s, 1 * s),
				CFrame = elbow * CFrame.new(0, arm.up * s / 2, 0) * UPRIGHT,
				Color = green,
				Material = Enum.Material.Grass,
				Parent = parent,
			})
		end
		kit.decor({
			Name = "Flower",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 0.9 * s,
			CFrame = frame * CFrame.new(0.2 * s, 7.8 * s, 0),
			Color = world("cactusFlower"),
			CastShadow = false,
			Parent = parent,
		})
	end,

	-- A bare trunk with three crooked branches.
	deadTree = function(base: CFrame, s: number, random: Random, spot: Spot, parent: Instance, kit: Kit)
		local wood = world("deadWood")
		core(spot, kit)({
			Name = "Trunk",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(6.5 * s, 1.1 * s),
			CFrame = base * CFrame.new(0, 3.25 * s, 0) * UPRIGHT,
			Color = wood,
			Material = Enum.Material.Wood,
			Parent = parent,
		})
		local turn = random:NextNumber(0, math.pi * 2)
		for i = 0, 2 do
			local height = (3.6 + i * 1.1) * s
			local yaw = turn + i * math.rad(125)
			local start = base * CFrame.new(0, height, 0)
			local direction = Vector3.new(math.cos(yaw), 1.1 - i * 0.15, math.sin(yaw)).Unit
			local length = (3.2 - i * 0.4) * s
			kit.decor({
				Name = "Branch",
				Shape = Enum.PartType.Cylinder,
				Size = cylinderSize(length, 0.5 * s),
				CFrame = along(start.Position, start.Position + direction * length),
				Color = wood,
				Material = Enum.Material.Wood,
				Parent = parent,
			})
		end
	end,

	-- A cluster of crystals around a glowing core (ice, obsidian with lava, amethyst...).
	crystal = function(base: CFrame, s: number, random: Random, spot: Spot, parent: Instance, kit: Kit)
		local turn = random:NextNumber(0, math.pi * 2)
		core(spot, kit)({
			Name = "CrystalCore",
			Size = Vector3.new(1.5 * s, 6.5 * s, 1.5 * s),
			CFrame = base * CFrame.Angles(0, turn, math.rad(4)) * CFrame.new(0, 3.1 * s, 0),
			Color = world("crystalGlow"),
			Material = Enum.Material.Neon,
			Parent = parent,
		})
		for i = 0, 2 do
			local yaw = turn + i * math.rad(120)
			local outward = Vector3.new(math.cos(yaw), 0, math.sin(yaw))
			local foot = base.Position + outward * 0.9 * s
			local top = foot + (outward * 0.5 + Vector3.yAxis).Unit * (3.8 + i * 0.5) * s
			kit.decor({
				Name = "Crystal",
				Size = Vector3.new((top - foot).Magnitude, 1.1 * s, 1.1 * s),
				CFrame = along(foot, top),
				Color = world("crystal"),
				Material = Enum.Material.Glass,
				Reflectance = 0.2,
				Parent = parent,
			})
		end
	end,

	-- A spotted toadstool; some glow at night (a light under every third cap inside the wall).
	mushroom = function(base: CFrame, s: number, random: Random, spot: Spot, parent: Instance, kit: Kit)
		core(spot, kit)({
			Name = "Stem",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(4.6 * s, 1.4 * s),
			CFrame = base * CFrame.new(0, 2.3 * s, 0) * UPRIGHT,
			Color = world("mushroomStem"),
			Parent = parent,
		})
		local cap = kit.decor({
			Name = "Cap",
			Size = Vector3.new(6.2 * s, 2.8 * s, 6.2 * s),
			CFrame = base * CFrame.new(0, 5 * s, 0) * CFrame.Angles(0, random:NextNumber(0, math.pi), 0),
			Color = world("mushroomCap"),
			Parent = parent,
		})
		sphereMesh(cap)
		for i = 0, 2 do
			local yaw = random:NextNumber(0, math.pi * 2) + i * 2.1
			local r = 1.6 * s
			kit.decor({
				Name = "Spot",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * 0.8 * s,
				CFrame = base * CFrame.new(math.cos(yaw) * r, 5.95 * s, math.sin(yaw) * r),
				Color = world("mushroomSpot"),
				Material = Enum.Material.Neon,
				CastShadow = false,
				Parent = parent,
			})
		end
		if not spot.outside and spot.seed % 3 == 0 then
			light(cap, world("mushroomCap"), 14, 0.9)
		end
	end,

	-- Three round shrubs.
	bush = function(base: CFrame, s: number, random: Random, _spot: Spot, parent: Instance, kit: Kit)
		for _, blob in
			{
				{ size = 3.3, at = Vector3.new(0, 1.3, 0), color = "leaves" },
				{ size = 2.6, at = Vector3.new(1.4, 1, 0.6), color = "leavesDark" },
				{ size = 2.2, at = Vector3.new(-1.2, 1.1, -0.7), color = "leavesLight" },
			}
		do
			kit.decor({
				Name = "Bush",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * blob.size * s,
				CFrame = base * CFrame.Angles(0, random:NextNumber(0, math.pi * 2), 0) * CFrame.new(blob.at * s),
				Color = world(blob.color),
				Material = Enum.Material.Grass,
				Parent = parent,
			})
		end
	end,

	-- A cherry tree: a dark trunk under three puffs of pink blossom.
	blossomTree = function(base: CFrame, s: number, random: Random, spot: Spot, parent: Instance, kit: Kit)
		core(spot, kit)({
			Name = "Trunk",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(7 * s, 1.3 * s),
			CFrame = base * CFrame.new(0, 3.5 * s, 0) * CFrame.Angles(0, 0, math.rad(4)) * UPRIGHT,
			Color = world("treeTrunk"),
			Material = Enum.Material.Wood,
			Parent = parent,
		})
		for _, puff in
			{
				{ size = Vector3.new(6.2, 4.4, 6.2), at = Vector3.new(0, 8.2, 0), color = "blossom" },
				{ size = Vector3.new(4.6, 3.6, 4.6), at = Vector3.new(1.5, 9.8, -1), color = "blossomLight" },
				{ size = Vector3.new(4.2, 3.2, 4.2), at = Vector3.new(-1.6, 9.4, 1.2), color = "blossomDark" },
			}
		do
			local blob = kit.decor({
				Name = "Blossom",
				Size = puff.size * s,
				CFrame = base * CFrame.new(puff.at * s) * CFrame.Angles(0, random:NextNumber(0, math.pi), 0),
				Color = world(puff.color),
				Material = Enum.Material.Grass,
				Parent = parent,
			})
			sphereMesh(blob)
		end
	end,

	-- Three bamboo canes of different heights and a tuft of leaves.
	bamboo = function(base: CFrame, s: number, random: Random, spot: Spot, parent: Instance, kit: Kit)
		local turn = random:NextNumber(0, math.pi * 2)
		local tops: { Vector3 } = {}
		for i, cane in { { height = 11.5, r = 0 }, { height = 9.5, r = 1.3 }, { height = 8, r = 1.2 } } do
			local yaw = turn + i * math.rad(130)
			local foot = base * CFrame.new(math.cos(yaw) * cane.r * s, 0, math.sin(yaw) * cane.r * s)
			local maker: (props: { [string]: any }) -> Part = if i == 1 then core(spot, kit) else kit.decor
			maker({
				Name = "Cane",
				Shape = Enum.PartType.Cylinder,
				Size = cylinderSize(cane.height * s, 0.7 * s),
				CFrame = foot * CFrame.new(0, cane.height * s / 2, 0) * UPRIGHT,
				Color = if i == 2 then world("bambooDark") else world("bamboo"),
				Parent = parent,
			})
			table.insert(tops, (foot * CFrame.new(0, cane.height * s, 0)).Position)
		end
		kit.decor({
			Name = "Leaves",
			Size = Vector3.new(4.4, 0.4, 2) * s,
			CFrame = CFrame.new(tops[1])
				* CFrame.Angles(math.rad(-20), turn, math.rad(14))
				* CFrame.new(1.4 * s, -0.6 * s, 0),
			Color = world("leavesLight"),
			Parent = parent,
		})
	end,

	-- A glowing alien bulb on a curly stem, with two broad leaves.
	alienPlant = function(base: CFrame, s: number, random: Random, spot: Spot, parent: Instance, kit: Kit)
		core(spot, kit)({
			Name = "Stem",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(6 * s, 0.8 * s),
			CFrame = base * CFrame.new(0, 3 * s, 0) * UPRIGHT,
			Color = world("alienStem"),
			Parent = parent,
		})
		local bulb = kit.decor({
			Name = "Bulb",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 2.8 * s,
			CFrame = base * CFrame.new(0, 7 * s, 0),
			Color = world("alienGlow"),
			Material = Enum.Material.Neon,
			CastShadow = false,
			Parent = parent,
		})
		local turn = random:NextNumber(0, math.pi)
		for _, side in { 0, math.pi } do
			local leaf = kit.decor({
				Name = "Leaf",
				Size = Vector3.new(4.2, 0.5, 1.8) * s,
				CFrame = base
					* CFrame.Angles(0, turn + side, 0)
					* CFrame.new(2 * s, 1.6 * s, 0)
					* CFrame.Angles(0, 0, math.rad(28)),
				Color = world("alienLeaf"),
				Parent = parent,
			})
			sphereMesh(leaf)
		end
		if not spot.outside and spot.seed % 3 == 0 then
			light(bulb, world("alienGlow"), 12, 1)
		end
	end,

	-- A heap of chocolate-chip boulders.
	moonRock = function(base: CFrame, s: number, random: Random, spot: Spot, parent: Instance, kit: Kit)
		for i, chunk in
			{
				{ size = Vector3.new(3.6, 2.8, 3.2), at = Vector3.new(0, 1.2, 0) },
				{ size = Vector3.new(2.4, 1.8, 2.2), at = Vector3.new(2.3, 0.8, 1) },
				{ size = Vector3.new(2, 1.5, 1.8), at = Vector3.new(-1.9, 0.6, -1.3) },
			}
		do
			local maker: (props: { [string]: any }) -> Part = if i == 1 then core(spot, kit) else kit.decor
			maker({
				Name = "Chunk",
				Size = chunk.size * s,
				CFrame = base * CFrame.new(chunk.at * s) * CFrame.Angles(
					random:NextNumber(-0.3, 0.3),
					random:NextNumber(0, math.pi),
					random:NextNumber(-0.3, 0.3)
				),
				Color = world("moonRock"),
				Material = Enum.Material.Slate,
				Parent = parent,
			})
		end
	end,

	-- A rainforest giant: a tall trunk, two broad flat canopies, a hanging vine and a mango.
	jungleTree = function(base: CFrame, s: number, random: Random, spot: Spot, parent: Instance, kit: Kit)
		core(spot, kit)({
			Name = "Trunk",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(9.5 * s, 1.4 * s),
			CFrame = base * CFrame.new(0, 4.75 * s, 0) * UPRIGHT,
			Color = world("treeTrunk"),
			Material = Enum.Material.Wood,
			Parent = parent,
		})
		for _, layer in
			{
				{ size = Vector3.new(8.6, 2.6, 8.6), at = Vector3.new(0, 9.8, 0), color = "leavesDark" },
				{ size = Vector3.new(6, 2.2, 6), at = Vector3.new(0.6, 11.6, -0.4), color = "leaves" },
			}
		do
			local canopy = kit.decor({
				Name = "Canopy",
				Size = layer.size * s,
				CFrame = base * CFrame.new(layer.at * s),
				Color = world(layer.color),
				Material = Enum.Material.Grass,
				Parent = parent,
			})
			sphereMesh(canopy)
		end
		local yaw = random:NextNumber(0, math.pi * 2)
		kit.decor({
			Name = "Vine",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(4.6 * s, 0.3 * s),
			CFrame = base * CFrame.new(math.cos(yaw) * 2.8 * s, 7.4 * s, math.sin(yaw) * 2.8 * s) * UPRIGHT,
			Color = world("vine"),
			CastShadow = false,
			Parent = parent,
		})
		kit.decor({
			Name = "Mango",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1, 1, 1) * s,
			CFrame = base * CFrame.new(-math.cos(yaw) * 1.9 * s, 8.3 * s, -math.sin(yaw) * 1.9 * s),
			Color = world("mango"),
			CastShadow = false,
			Parent = parent,
		})
	end,

	-- Four fern fronds arching out of the ground.
	fern = function(base: CFrame, s: number, random: Random, _spot: Spot, parent: Instance, kit: Kit)
		local turn = random:NextNumber(0, math.pi * 2)
		for i = 0, 3 do
			local frond = kit.decor({
				Name = "Frond",
				Size = Vector3.new(5, 0.35, 1.6) * s,
				CFrame = base
					* CFrame.Angles(0, turn + i * math.rad(90), 0)
					* CFrame.new(2.1 * s, 1.1 * s, 0)
					* CFrame.Angles(0, 0, math.rad(26)),
				Color = if i % 2 == 0 then world("leaves") else world("leavesLight"),
				Parent = parent,
			})
			sphereMesh(frond)
		end
	end,

	-- A concrete planter with a neon rim and a round little tree.
	planterTree = function(base: CFrame, s: number, _random: Random, spot: Spot, parent: Instance, kit: Kit)
		core(spot, kit)({
			Name = "Planter",
			Size = Vector3.new(3.6, 1.6, 3.6) * s,
			CFrame = base * CFrame.new(0, 0.8 * s, 0),
			Color = world("planter"),
			Material = Enum.Material.Concrete,
			Parent = parent,
		})
		kit.decor({
			Name = "Rim",
			Size = Vector3.new(3.8, 0.16, 3.8) * s,
			CFrame = base * CFrame.new(0, 1.62 * s, 0),
			Color = if spot.seed % 2 == 0 then world("neonPink") else world("neonBlue"),
			Material = Enum.Material.Neon,
			CastShadow = false,
			Parent = parent,
		})
		kit.decor({
			Name = "Trunk",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(4.6 * s, 0.6 * s),
			CFrame = base * CFrame.new(0, 3.9 * s, 0) * UPRIGHT,
			Color = world("treeTrunk"),
			Material = Enum.Material.Wood,
			Parent = parent,
		})
		kit.decor({
			Name = "Canopy",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 4.2 * s,
			CFrame = base * CFrame.new(0, 7.2 * s, 0),
			Color = world("hedge"),
			Material = Enum.Material.Grass,
			Parent = parent,
		})
	end,

	-- A street lamp with a glowing head (every third one inside the wall lights the ground).
	streetLamp = function(base: CFrame, s: number, _random: Random, spot: Spot, parent: Instance, kit: Kit)
		kit.decor({
			Name = "Foot",
			Size = Vector3.new(1.3, 0.6, 1.3) * s,
			CFrame = base * CFrame.new(0, 0.3 * s, 0),
			Color = world("streetLamp"),
			Parent = parent,
		})
		core(spot, kit)({
			Name = "Pole",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(9.4 * s, 0.45 * s),
			CFrame = base * CFrame.new(0, 4.7 * s, 0) * UPRIGHT,
			Color = world("streetLamp"),
			Material = Enum.Material.Metal,
			Parent = parent,
		})
		kit.decor({
			Name = "Arm",
			Size = Vector3.new(2.6, 0.3, 0.3) * s,
			CFrame = base * CFrame.new(1.2 * s, 9.3 * s, 0),
			Color = world("streetLamp"),
			Material = Enum.Material.Metal,
			Parent = parent,
		})
		local head = kit.decor({
			Name = "Lamp",
			Size = Vector3.new(1.4, 0.45, 0.9) * s,
			CFrame = base * CFrame.new(2.3 * s, 9.05 * s, 0),
			Color = world("lampLight"),
			Material = Enum.Material.Neon,
			CastShadow = false,
			Parent = parent,
		})
		if not spot.outside and spot.seed % 3 == 0 then
			light(head, world("lampLight"), 16, 1.2)
		end
	end,

	-- A golden trunk holding up three puffs of cloud.
	cloudTree = function(base: CFrame, s: number, _random: Random, spot: Spot, parent: Instance, kit: Kit)
		core(spot, kit)({
			Name = "Trunk",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(6.6 * s, 1.1 * s),
			CFrame = base * CFrame.new(0, 3.3 * s, 0) * UPRIGHT,
			Color = world("cloudTrunk"),
			Material = Enum.Material.Marble,
			Parent = parent,
		})
		for i, puff in
			{
				{ size = 5.4, at = Vector3.new(0, 8.4, 0) },
				{ size = 4, at = Vector3.new(1.8, 7.9, 1) },
				{ size = 3.6, at = Vector3.new(-1.6, 9.7, -0.8) },
			}
		do
			kit.decor({
				Name = "Cloud",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * puff.size * s,
				CFrame = base * CFrame.new(puff.at * s),
				Color = if i == 2 then world("cloudShade") else world("cloudPuff"),
				Material = Enum.Material.Sand,
				Parent = parent,
			})
		end
	end,

	-- A white marble column with a little cloud resting on it.
	cloudPillar = function(base: CFrame, s: number, _random: Random, spot: Spot, parent: Instance, kit: Kit)
		core(spot, kit)({
			Name = "Column",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(9 * s, 1.6 * s),
			CFrame = base * CFrame.new(0, 4.5 * s, 0) * UPRIGHT,
			Color = world("castleWall"),
			Material = Enum.Material.Marble,
			Parent = parent,
		})
		kit.decor({
			Name = "Capital",
			Size = Vector3.new(2.6, 0.8, 2.6) * s,
			CFrame = base * CFrame.new(0, 9.4 * s, 0),
			Color = world("cloudTrunk"),
			Material = Enum.Material.Marble,
			Parent = parent,
		})
		kit.decor({
			Name = "Cloud",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 3.6 * s,
			CFrame = base * CFrame.new(0, 11.2 * s, 0),
			Color = world("cloudPuff"),
			Material = Enum.Material.Sand,
			Parent = parent,
		})
	end,

	-- Branching coral in three reef colours, with a round tip.
	coral = function(base: CFrame, s: number, random: Random, spot: Spot, parent: Instance, kit: Kit)
		local first = random:NextInteger(1, 3)
		core(spot, kit)({
			Name = "Coral",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(5.4 * s, 1.2 * s),
			CFrame = base * CFrame.new(0, 2.7 * s, 0) * UPRIGHT,
			Color = world(`coral{first}`),
			Parent = parent,
		})
		kit.decor({
			Name = "Tip",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 1.5 * s,
			CFrame = base * CFrame.new(0, 5.5 * s, 0),
			Color = world(`coral{first}`),
			Parent = parent,
		})
		local turn = random:NextNumber(0, math.pi * 2)
		for i = 0, 2 do
			local yaw = turn + i * math.rad(120)
			local start = (base * CFrame.new(0, (1.8 + i * 0.9) * s, 0)).Position
			local direction = Vector3.new(math.cos(yaw), 1.3, math.sin(yaw)).Unit
			local length = (3.6 - i * 0.3) * s
			kit.decor({
				Name = "Branch",
				Shape = Enum.PartType.Cylinder,
				Size = cylinderSize(length, 0.8 * s),
				CFrame = along(start, start + direction * length),
				Color = world(`coral{(first + i) % 3 + 1}`),
				Parent = parent,
			})
		end
	end,

	-- Four kelp ribbons swaying up towards the light.
	kelp = function(base: CFrame, s: number, random: Random, spot: Spot, parent: Instance, kit: Kit)
		local turn = random:NextNumber(0, math.pi * 2)
		for i, ribbon in
			{
				{ height = 12, r = 0 },
				{ height = 10, r = 1.2 },
				{ height = 8.6, r = 1.1 },
				{ height = 7, r = 1.3 },
			}
		do
			local yaw = turn + i * math.rad(95)
			local maker: (props: { [string]: any }) -> Part = if i == 1 then core(spot, kit) else kit.decor
			maker({
				Name = "Kelp",
				Size = Vector3.new(0.5, ribbon.height, 1.4) * s,
				CFrame = base
					* CFrame.new(math.cos(yaw) * ribbon.r * s, ribbon.height * s / 2, math.sin(yaw) * ribbon.r * s)
					* CFrame.Angles(random:NextNumber(-0.12, 0.12), yaw, random:NextNumber(-0.14, 0.14)),
				Color = if i % 2 == 0 then world("kelpDark") else world("kelp"),
				Parent = parent,
			})
		end
	end,
	-- A giant strawberry on its stem, dipped in chocolate, with a white drizzle and a green calyx.
	dippedStrawberry = function(base: CFrame, s: number, random: Random, spot: Spot, parent: Instance, kit: Kit)
		local lean = base * CFrame.Angles(random:NextNumber(-0.08, 0.08), 0, random:NextNumber(-0.08, 0.08))
		core(spot, kit)({
			Name = "Stem",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(3.2 * s, 0.55 * s),
			CFrame = lean * CFrame.new(0, 1.6 * s, 0) * UPRIGHT,
			Color = world("cocoaLeafDark"),
			Parent = parent,
		})
		local berry = kit.decor({
			Name = "Strawberry",
			Size = Vector3.new(4.4, 5.4, 4.4) * s,
			CFrame = lean * CFrame.new(0, 5.8 * s, 0),
			Color = world("strawberry"),
			Parent = parent,
		})
		sphereMesh(berry)
		local dip = kit.decor({
			Name = "Chocolate",
			Size = Vector3.new(4.6, 3.6, 4.6) * s,
			CFrame = lean * CFrame.new(0, 4.4 * s, 0),
			Color = world("chocolate"),
			Reflectance = 0.08,
			Parent = parent,
		})
		sphereMesh(dip)
		local drizzle = kit.decor({
			Name = "Drizzle",
			Size = Vector3.new(4.5, 0.4, 4.5) * s,
			CFrame = lean * CFrame.new(0, 6.7 * s, 0) * CFrame.Angles(0.12, 0, 0.1),
			Color = world("whiteChocolate"),
			Parent = parent,
		})
		sphereMesh(drizzle)
		local calyx = kit.decor({
			Name = "Leaves",
			Size = Vector3.new(3.4, 0.7, 3.4) * s,
			CFrame = lean * CFrame.new(0, 8.45 * s, 0),
			Color = world("cocoaLeaf"),
			Parent = parent,
		})
		sphereMesh(calyx)
	end,

	-- A cacao tree: a round canopy and ripe cocoa pods hanging off the trunk.
	cocoaTree = function(base: CFrame, s: number, random: Random, spot: Spot, parent: Instance, kit: Kit)
		core(spot, kit)({
			Name = "Trunk",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(6.4 * s, 1.1 * s),
			CFrame = base * CFrame.new(0, 3.2 * s, 0) * UPRIGHT,
			Color = world("treeTrunk"),
			Material = Enum.Material.Wood,
			Parent = parent,
		})
		for _, blob in
			{
				{ size = Vector3.new(7, 5, 7), at = Vector3.new(0, 8.4, 0), color = "cocoaLeaf" },
				{ size = Vector3.new(5, 4, 5), at = Vector3.new(1.3, 10.4, -0.9), color = "cocoaLeafDark" },
			}
		do
			kit.decor({
				Name = "Leaves",
				Size = blob.size * s,
				CFrame = base * CFrame.new(blob.at * s) * tilt(random),
				Color = world(blob.color),
				Parent = parent,
			})
		end
		for i, pod in
			{
				{ at = Vector3.new(0.75, 3.6, 0), color = "cocoaPod" },
				{ at = Vector3.new(-0.7, 4.9, 0.3), color = "cocoaPodRipe" },
			}
		do
			local part = kit.decor({
				Name = "CocoaPod",
				Size = Vector3.new(1.2, 2.2, 1.2) * s,
				CFrame = base * CFrame.new(pod.at * s) * CFrame.Angles(0, 0, math.rad(if i == 1 then -12 else 12)),
				Color = world(pod.color),
				Parent = parent,
			})
			sphereMesh(part)
		end
	end,

	-- A paper-cone stick with a big fluffy cloud of pink and blue cotton candy.
	cottonCandyTree = function(base: CFrame, s: number, random: Random, spot: Spot, parent: Instance, kit: Kit)
		core(spot, kit)({
			Name = "Cone",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(5.2 * s, 0.75 * s),
			CFrame = base * CFrame.new(0, 2.6 * s, 0) * UPRIGHT,
			Color = world("paperCone"),
			Parent = parent,
		})
		local turn = random:NextNumber(0, math.pi * 2)
		for i, puff in
			{
				{ size = 5.2, r = 0, y = 7.2, color = "flossPink" },
				{ size = 3.8, r = 1.5, y = 8.8, color = "flossBlue" },
				{ size = 3.4, r = 1.4, y = 8.2, color = "flossLilac" },
			}
		do
			local yaw = turn + i * 2.4
			kit.decor({
				Name = "Floss",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * puff.size * s,
				CFrame = base * CFrame.new(math.cos(yaw) * puff.r * s, puff.y * s, math.sin(yaw) * puff.r * s),
				Color = world(puff.color),
				Material = Enum.Material.Fabric,
				Parent = parent,
			})
		end
	end,

	-- A bunch of party balloons tied to a post.
	balloonBunch = function(base: CFrame, s: number, random: Random, spot: Spot, parent: Instance, kit: Kit)
		core(spot, kit)({
			Name = "Post",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(4 * s, 0.6 * s),
			CFrame = base * CFrame.new(0, 2 * s, 0) * UPRIGHT,
			Color = world("bench"),
			Material = Enum.Material.Wood,
			Parent = parent,
		})
		local knot = (base * CFrame.new(0, 4 * s, 0)).Position
		local turn = random:NextNumber(0, math.pi * 2)
		for i, spec in { { r = 0, y = 10.2 }, { r = 1.7, y = 9 }, { r = 1.6, y = 8.4 } } do
			local yaw = turn + i * 2.2
			local centre = (base * CFrame.new(math.cos(yaw) * spec.r * s, spec.y * s, math.sin(yaw) * spec.r * s)).Position
			local size = 2.8 * s
			local balloon = kit.decor({
				Name = "Balloon",
				Size = Vector3.new(size, size * 1.18, size),
				CFrame = CFrame.new(centre),
				Color = world(`balloon{(i + spot.seed) % 3 + 1}`),
				Reflectance = 0.15,
				Parent = parent,
			})
			sphereMesh(balloon)
			local tie = centre - Vector3.new(0, size * 0.55, 0)
			kit.decor({
				Name = "String",
				Shape = Enum.PartType.Cylinder,
				Size = cylinderSize((tie - knot).Magnitude, 0.12),
				CFrame = along(knot, tie),
				Color = world("balloonString"),
				Parent = parent,
			})
		end
	end,

	-- A gnarled olive tree with a silvery-green canopy.
	oliveTree = function(base: CFrame, s: number, random: Random, spot: Spot, parent: Instance, kit: Kit)
		core(spot, kit)({
			Name = "Trunk",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(4.6 * s, 1.2 * s),
			CFrame = base * CFrame.new(0, 2.3 * s, 0) * CFrame.Angles(0.1, 0, 0.08) * UPRIGHT,
			Color = world("oliveTrunk"),
			Material = Enum.Material.Wood,
			Parent = parent,
		})
		for i, blob in
			{
				{ size = Vector3.new(6.2, 3.6, 6.2), at = Vector3.new(0, 6.2, 0) },
				{ size = Vector3.new(4.6, 3, 4.6), at = Vector3.new(1.7, 7.3, 1) },
				{ size = Vector3.new(4.2, 2.8, 4.2), at = Vector3.new(-1.8, 6.9, -1.2) },
			}
		do
			local canopy = kit.decor({
				Name = "Leaves",
				Size = blob.size * s,
				CFrame = base * CFrame.new(blob.at * s) * CFrame.Angles(0, random:NextNumber(0, math.pi), 0),
				Color = if i == 2 then world("oliveLeafDark") else world("oliveLeaf"),
				Parent = parent,
			})
			sphereMesh(canopy)
		end
	end,

	-- A tall, slim Italian cypress.
	cypress = function(base: CFrame, s: number, _random: Random, spot: Spot, parent: Instance, kit: Kit)
		core(spot, kit)({
			Name = "Trunk",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(2.4 * s, 0.8 * s),
			CFrame = base * CFrame.new(0, 1.2 * s, 0) * UPRIGHT,
			Color = world("treeTrunk"),
			Material = Enum.Material.Wood,
			Parent = parent,
		})
		local column = kit.decor({
			Name = "Leaves",
			Size = Vector3.new(3.4, 11, 3.4) * s,
			CFrame = base * CFrame.new(0, 7.2 * s, 0),
			Color = world("cypress"),
			Parent = parent,
		})
		sphereMesh(column)
		local tip = kit.decor({
			Name = "Leaves",
			Size = Vector3.new(2, 4.4, 2) * s,
			CFrame = base * CFrame.new(0, 12.4 * s, 0),
			Color = world("cypress"):Lerp(Color3.new(0, 0, 0), 0.12),
			Parent = parent,
		})
		sphereMesh(tip)
	end,
}

-- Builds one flora prop on a tree spot. `kind` must be a FloraKind.
function ThemeProps.flora(kind: string, spot: Spot, parent: Instance, kit: Kit)
	local random = Random.new(spot.seed)
	local base = CFrame.new(spot.x, spot.y - (if spot.outside then 0.6 else 0), spot.z)
		* CFrame.Angles(0, random:NextNumber(0, math.pi * 2), 0)
	local builder = flora[kind] or flora.round
	builder(base, spot.scale, random, spot, parent, kit)
end

-- Landmarks ----------------------------------------------------------------------------------------------------------

type LandmarkBuilder = (base: CFrame, s: number, spot: LandmarkSpot, parent: Instance, kit: Kit) -> ()

local landmarks: { [string]: LandmarkBuilder } = {
	-- A hot-air balloon drifting high above the hills.
	balloon = function(_base: CFrame, s: number, spot: LandmarkSpot, parent: Instance, kit: Kit)
		local altitude = 70 + (spot.index % 3) * 14
		local centre = CFrame.new(spot.x, spot.y + altitude * s, spot.z)
		local color = world(`balloon{spot.index % 3 + 1}`)
		kit.decor({
			Name = "Envelope",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 16 * s,
			CFrame = centre,
			Color = color,
			Parent = parent,
		})
		kit.decor({
			Name = "Skirt",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(5 * s, 7 * s),
			CFrame = centre * CFrame.new(0, -8.5 * s, 0) * UPRIGHT,
			Color = color:Lerp(Color3.new(1, 1, 1), 0.35),
			Parent = parent,
		})
		local basket = centre * CFrame.new(0, -17 * s, 0)
		kit.decor({
			Name = "Basket",
			Size = Vector3.new(3.6, 2.6, 3.6) * s,
			CFrame = basket,
			Color = world("basket"),
			Material = Enum.Material.WoodPlanks,
			Parent = parent,
		})
		for _, side in { -1, 1 } do
			local a = (basket * CFrame.new(side * 1.5 * s, 1.3 * s, 0)).Position
			local b = (centre * CFrame.new(side * 3 * s, -11 * s, 0)).Position
			kit.decor({
				Name = "Rope",
				Size = Vector3.new((b - a).Magnitude, 0.18, 0.18),
				CFrame = along(a, b),
				Color = world("basket"),
				CastShadow = false,
				Parent = parent,
			})
		end
		kit.decor({
			Name = "Burner",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 1.2 * s,
			CFrame = centre * CFrame.new(0, -12.2 * s, 0),
			Color = world("lantern"),
			Material = Enum.Material.Neon,
			CastShadow = false,
			Parent = parent,
		})
	end,

	-- A windmill with its sails turned towards the map.
	windmill = function(base: CFrame, s: number, _spot: LandmarkSpot, parent: Instance, kit: Kit)
		local height = 26 * s
		kit.decor({
			Name = "Tower",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(height, 9 * s),
			CFrame = base * CFrame.new(0, height / 2, 0) * UPRIGHT,
			Color = world("windmillTower"),
			Material = Enum.Material.Plaster,
			Parent = parent,
		})
		local roof = kit.decor({
			Name = "Roof",
			Size = Vector3.new(10.5, 9, 10.5) * s,
			CFrame = base * CFrame.new(0, height + 1.5 * s, 0),
			Color = world("windmillRoof"),
			Parent = parent,
		})
		sphereMesh(roof)
		local hub = base * CFrame.new(0, height - 2 * s, -5.2 * s)
		kit.decor({
			Name = "Hub",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(2 * s, 2.2 * s),
			CFrame = hub * CFrame.Angles(0, math.rad(90), 0),
			Color = world("hat"),
			Parent = parent,
		})
		for i = 0, 3 do
			kit.decor({
				Name = "Sail",
				Size = Vector3.new(2.6 * s, 13 * s, 0.4 * s),
				CFrame = hub * CFrame.Angles(0, 0, math.rad(i * 90 + 20)) * CFrame.new(0, 7 * s, -0.6 * s),
				Color = world("windmillBlade"),
				Material = Enum.Material.Fabric,
				Parent = parent,
			})
		end
		kit.decor({
			Name = "Door",
			Size = Vector3.new(3 * s, 5 * s, 0.4),
			CFrame = base * CFrame.new(0, 2.5 * s, -4.4 * s),
			Color = world("windmillRoof"),
			Material = Enum.Material.WoodPlanks,
			Parent = parent,
		})
	end,

	-- A lollipop as tall as a house.
	giantLollipop = function(base: CFrame, s: number, spot: LandmarkSpot, parent: Instance, kit: Kit)
		local n = spot.index
		kit.decor({
			Name = "Stick",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(40 * s, 2.6 * s),
			CFrame = base * CFrame.new(0, 20 * s, 0) * UPRIGHT,
			Color = world("candyStick"),
			Parent = parent,
		})
		local disc = base * CFrame.new(0, 50 * s, 0) * CFrame.Angles(0, math.rad(90), 0)
		kit.decor({
			Name = "Candy",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(4 * s, 30 * s),
			CFrame = disc,
			Color = candy(n),
			Parent = parent,
		})
		kit.decor({
			Name = "Swirl",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(4.4 * s, 20 * s),
			CFrame = disc,
			Color = world("candyStick"),
			CastShadow = false,
			Parent = parent,
		})
		kit.decor({
			Name = "SwirlCentre",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(4.8 * s, 9 * s),
			CFrame = disc,
			Color = candy(n + 1),
			CastShadow = false,
			Parent = parent,
		})
	end,

	-- A red-and-white candy cane with its hook.
	candyCane = function(base: CFrame, s: number, _spot: LandmarkSpot, parent: Instance, kit: Kit)
		local segment = 6 * s
		local diameter = 3.6 * s
		for i = 0, 5 do
			kit.decor({
				Name = "Cane",
				Shape = Enum.PartType.Cylinder,
				Size = cylinderSize(segment + 0.05, diameter),
				CFrame = base * CFrame.new(0, (i + 0.5) * segment, 0) * UPRIGHT,
				Color = if i % 2 == 0 then world("candy1") else world("candyStick"),
				Parent = parent,
			})
		end
		-- The hook: three pieces bending over towards the map (front, -Z).
		local top = 6 * segment
		local points = {
			Vector3.new(0, top, 0),
			Vector3.new(0, top + 3.4 * s, -1.6 * s),
			Vector3.new(0, top + 4.2 * s, -5 * s),
			Vector3.new(0, top + 2.4 * s, -8.2 * s),
		}
		for i = 1, 3 do
			local a = (base * CFrame.new(points[i])).Position
			local b = (base * CFrame.new(points[i + 1])).Position
			kit.decor({
				Name = "Hook",
				Shape = Enum.PartType.Cylinder,
				Size = cylinderSize((b - a).Magnitude + diameter * 0.5, diameter),
				CFrame = along(a, b),
				Color = if i % 2 == 1 then world("candyStick") else world("candy1"),
				Parent = parent,
			})
		end
	end,

	-- A pink cotton-candy cloud in the sky.
	cottonCloud = function(_base: CFrame, s: number, spot: LandmarkSpot, parent: Instance, kit: Kit)
		local centre = CFrame.new(spot.x, spot.y + (80 + (spot.index % 2) * 18) * s, spot.z)
		for i, puff in
			{
				{ size = 15, at = Vector3.new(0, 0, 0) },
				{ size = 11, at = Vector3.new(9, -1.5, 2) },
				{ size = 10, at = Vector3.new(-9, -2, -1) },
				{ size = 9, at = Vector3.new(4, 4, -3) },
				{ size = 8, at = Vector3.new(-4, 3.5, 4) },
			}
		do
			kit.decor({
				Name = "Cloud",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * puff.size * s,
				CFrame = centre * CFrame.new(puff.at * s),
				Color = if i % 2 == 0 then world("candyStick") else world("candy1"):Lerp(Color3.new(1, 1, 1), 0.45),
				Material = Enum.Material.Sand,
				CastShadow = false,
				Parent = parent,
			})
		end
	end,

	-- Shards of ice leaning out of the snow.
	iceSpire = function(base: CFrame, s: number, _spot: LandmarkSpot, parent: Instance, kit: Kit)
		for _, shard in
			{
				{ size = Vector3.new(8, 42, 8), at = Vector3.new(0, 20, 0), tiltX = 3, tiltZ = 0 },
				{ size = Vector3.new(6, 28, 6), at = Vector3.new(7, 12, 2), tiltX = 0, tiltZ = -14 },
				{ size = Vector3.new(5.5, 24, 5.5), at = Vector3.new(-6, 10, -3), tiltX = 6, tiltZ = 13 },
				{ size = Vector3.new(4.5, 16, 4.5), at = Vector3.new(1, 6, -7), tiltX = 16, tiltZ = 4 },
			}
		do
			kit.decor({
				Name = "IceShard",
				Size = shard.size * s,
				CFrame = base
					* CFrame.new(shard.at * s)
					* CFrame.Angles(math.rad(shard.tiltX), math.rad(45), math.rad(shard.tiltZ)),
				Color = world("ice"),
				Material = Enum.Material.Ice,
				Transparency = 0.15,
				Reflectance = 0.2,
				Parent = parent,
			})
		end
	end,

	-- A giant snowman looking at the map.
	snowman = function(base: CFrame, s: number, _spot: LandmarkSpot, parent: Instance, kit: Kit)
		local snow = world("snow")
		for _, ball in { { d = 14, y = 6.5 }, { d = 10.5, y = 16.5 }, { d = 7.5, y = 24.5 } } do
			kit.decor({
				Name = "Snowball",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * ball.d * s,
				CFrame = base * CFrame.new(0, ball.y * s, 0),
				Color = snow,
				Material = Enum.Material.Snow,
				Parent = parent,
			})
		end
		for _, side in { -1, 1 } do
			kit.decor({
				Name = "Eye",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * 1.1 * s,
				CFrame = base * CFrame.new(side * 1.4 * s, 25.6 * s, -3.3 * s),
				Color = world("hat"),
				Parent = parent,
			})
		end
		kit.decor({
			Name = "Nose",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(3.2 * s, 0.9 * s),
			CFrame = base * CFrame.new(0, 24.4 * s, -4.9 * s) * CFrame.Angles(0, math.rad(90), 0),
			Color = world("carrot"),
			Parent = parent,
		})
		kit.decor({
			Name = "HatBrim",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(0.6 * s, 8 * s),
			CFrame = base * CFrame.new(0, 28 * s, 0) * UPRIGHT,
			Color = world("hat"),
			Parent = parent,
		})
		kit.decor({
			Name = "HatTop",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(5 * s, 5.4 * s),
			CFrame = base * CFrame.new(0, 30.6 * s, 0) * UPRIGHT,
			Color = world("hat"),
			Parent = parent,
		})
		kit.decor({
			Name = "Scarf",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(1.4 * s, 8.6 * s),
			CFrame = base * CFrame.new(0, 21.2 * s, 0) * UPRIGHT,
			Color = world("candy1"),
			Material = Enum.Material.Fabric,
			Parent = parent,
		})
	end,

	-- A banded sandstone mesa.
	mesa = function(base: CFrame, s: number, spot: LandmarkSpot, parent: Instance, kit: Kit)
		local frame = base * CFrame.Angles(0, math.rad(spot.index * 37), 0)
		for _, layer in
			{
				{ size = Vector3.new(48, 12, 38), y = 6, color = "mesa" },
				{ size = Vector3.new(42, 4, 33), y = 14, color = "mesaBand" },
				{ size = Vector3.new(38, 10, 30), y = 21, color = "mesa" },
				{ size = Vector3.new(31, 4, 24), y = 28, color = "mesaBand" },
			}
		do
			kit.decor({
				Name = "Mesa",
				Size = layer.size * s,
				CFrame = frame * CFrame.new(0, layer.y * s, 0),
				Color = world(layer.color),
				Material = Enum.Material.Sandstone,
				Parent = parent,
			})
		end
	end,

	-- A saguaro taller than the plot signs could ever be.
	giantCactus = function(base: CFrame, s: number, spot: LandmarkSpot, parent: Instance, kit: Kit)
		flora.cactus(base, 4.2 * s, Random.new(spot.index), {
			x = spot.x,
			y = spot.y,
			z = spot.z,
			scale = 4.2 * s,
			seed = spot.index,
			outside = true,
		}, parent, kit)
	end,

	-- A smoking volcano with a lava-filled crater.
	volcano = function(base: CFrame, s: number, _spot: LandmarkSpot, parent: Instance, kit: Kit)
		local rock = world("lavaRock")
		for _, tier in
			{
				{ d = 84, y = 4.5 },
				{ d = 70, y = 13.5 },
				{ d = 56, y = 22.5 },
				{ d = 43, y = 31.5 },
				{ d = 31, y = 38 },
			}
		do
			kit.decor({
				Name = "Slope",
				Shape = Enum.PartType.Cylinder,
				Size = cylinderSize(9 * s, tier.d * s),
				CFrame = base * CFrame.new(0, tier.y * s, 0) * UPRIGHT,
				Color = rock,
				Material = Enum.Material.Basalt,
				Parent = parent,
			})
		end
		local crater = kit.decor({
			Name = "Crater",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(1.2 * s, 22 * s),
			CFrame = base * CFrame.new(0, 42.2 * s, 0) * UPRIGHT,
			Color = world("lava"),
			Material = Enum.Material.Neon,
			CastShadow = false,
			Parent = parent,
		})
		-- Two lava streams running down the side that faces the map.
		for _, side in { -1, 1 } do
			kit.decor({
				Name = "LavaFlow",
				Size = Vector3.new(4 * s, 0.8 * s, 40 * s),
				CFrame = base
					* CFrame.new(side * 6 * s, 24 * s, -22 * s)
					* CFrame.Angles(math.rad(-44), math.rad(side * 8), 0),
				Color = world("lava"),
				Material = Enum.Material.Neon,
				CastShadow = false,
				Parent = parent,
			})
		end
		local vent = Instance.new("Attachment")
		vent.Name = "Vent"
		vent.Parent = crater
		vent.WorldCFrame = CFrame.new(crater.Position + Vector3.new(0, 1, 0))
		kit.emitter(vent, {
			Name = "Smoke",
			Texture = SMOKE_TEXTURE,
			Color = ColorSequence.new(Color3.fromRGB(90, 80, 80), Color3.fromRGB(150, 140, 140)),
			Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 8),
				NumberSequenceKeypoint.new(1, 26),
			}),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.3),
				NumberSequenceKeypoint.new(0.7, 0.6),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Speed = NumberRange.new(10, 16),
			SpreadAngle = Vector2.new(14, 14),
			Acceleration = Vector3.new(2, 1.5, 1),
			Lifetime = NumberRange.new(6, 9),
			Rate = 4,
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-15, 15),
			EmissionDirection = Enum.NormalId.Top,
		})
		light(crater, world("lava"), 40, 2)
	end,

	-- A rock column cracked with glowing lava.
	lavaPillar = function(base: CFrame, s: number, spot: LandmarkSpot, parent: Instance, kit: Kit)
		local frame = base * CFrame.Angles(0, math.rad(spot.index * 53), 0)
		kit.decor({
			Name = "Pillar",
			Size = Vector3.new(8, 26, 8) * s,
			CFrame = frame * CFrame.new(0, 12 * s, 0) * CFrame.Angles(math.rad(6), 0, math.rad(4)),
			Color = world("lavaRock"),
			Material = Enum.Material.Basalt,
			Parent = parent,
		})
		kit.decor({
			Name = "Pillar",
			Size = Vector3.new(6, 15, 6) * s,
			CFrame = frame * CFrame.new(6 * s, 6.5 * s, 3 * s) * CFrame.Angles(0, 0, math.rad(-12)),
			Color = world("lavaRock"),
			Material = Enum.Material.Basalt,
			Parent = parent,
		})
		for _, crack in
			{
				{ at = Vector3.new(0, 14, -4.1), size = Vector3.new(1.2, 18, 0.4), turn = 8 },
				{ at = Vector3.new(4.1, 10, 0), size = Vector3.new(0.4, 14, 1.2), turn = -6 },
			}
		do
			kit.decor({
				Name = "LavaCrack",
				Size = crack.size * s,
				CFrame = frame * CFrame.new(crack.at * s) * CFrame.Angles(0, 0, math.rad(crack.turn)),
				Color = world("lava"),
				Material = Enum.Material.Neon,
				CastShadow = false,
				Parent = parent,
			})
		end
	end,

	-- A glowing toadstool as tall as a tree.
	giantMushroom = function(base: CFrame, s: number, spot: LandmarkSpot, parent: Instance, kit: Kit)
		kit.decor({
			Name = "Stem",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(26 * s, 6 * s),
			CFrame = base * CFrame.new(0, 13 * s, 0) * UPRIGHT,
			Color = world("mushroomStem"),
			Parent = parent,
		})
		kit.decor({
			Name = "Gills",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(1 * s, 24 * s),
			CFrame = base * CFrame.new(0, 25.5 * s, 0) * UPRIGHT,
			Color = world("mushroomStem"):Lerp(Color3.new(0, 0, 0), 0.35),
			Parent = parent,
		})
		local cap = kit.decor({
			Name = "Cap",
			Size = Vector3.new(30, 13, 30) * s,
			CFrame = base * CFrame.new(0, 28 * s, 0),
			Color = world("mushroomCap"),
			Parent = parent,
		})
		sphereMesh(cap)
		for i = 0, 2 do
			local yaw = math.rad(spot.index * 40 + i * 120)
			kit.decor({
				Name = "Spot",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * (4 - i * 0.5) * s,
				CFrame = base * CFrame.new(math.cos(yaw) * 8 * s, 32.6 * s, math.sin(yaw) * 8 * s),
				Color = world("mushroomSpot"),
				Material = Enum.Material.Neon,
				CastShadow = false,
				Parent = parent,
			})
		end
		light(cap, world("mushroomCap"), 36, 1.5)
	end,

	-- Paper lanterns floating up into the night sky.
	skyLantern = function(_base: CFrame, s: number, spot: LandmarkSpot, parent: Instance, kit: Kit)
		local random = Random.new(spot.index * 7 + 3)
		for _ = 1, 3 do
			local at = Vector3.new(
				spot.x + random:NextNumber(-22, 22),
				spot.y + random:NextNumber(45, 110) * s,
				spot.z + random:NextNumber(-22, 22)
			)
			local frame = CFrame.new(at)
				* CFrame.Angles(0, random:NextNumber(0, math.pi), random:NextNumber(-0.12, 0.12))
			kit.decor({
				Name = "Lantern",
				Size = Vector3.new(3.6, 4.6, 3.6) * s,
				CFrame = frame,
				Color = world("lantern"),
				Material = Enum.Material.Neon,
				Transparency = 0.1,
				CastShadow = false,
				Parent = parent,
			})
			kit.decor({
				Name = "LanternTop",
				Size = Vector3.new(3.9, 0.5, 3.9) * s,
				CFrame = frame * CFrame.new(0, 2.55 * s, 0),
				Color = world("lantern"):Lerp(Color3.new(0, 0, 0), 0.5),
				CastShadow = false,
				Parent = parent,
			})
		end
	end,

	-- A striped lighthouse with a lit lamp room.
	lighthouse = function(base: CFrame, s: number, _spot: LandmarkSpot, parent: Instance, kit: Kit)
		kit.decor({
			Name = "Base",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(4 * s, 13 * s),
			CFrame = base * CFrame.new(0, 2 * s, 0) * UPRIGHT,
			Color = world("terrainRock"),
			Material = Enum.Material.Slate,
			Parent = parent,
		})
		for i = 0, 2 do
			kit.decor({
				Name = "Tower",
				Shape = Enum.PartType.Cylinder,
				Size = cylinderSize(10 * s, (9 - i * 0.6) * s),
				CFrame = base * CFrame.new(0, (9 + i * 10) * s, 0) * UPRIGHT,
				Color = if i % 2 == 0 then world("lighthouse") else world("lighthouseStripe"),
				Parent = parent,
			})
		end
		kit.decor({
			Name = "Gallery",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(0.8 * s, 9.6 * s),
			CFrame = base * CFrame.new(0, 34.4 * s, 0) * UPRIGHT,
			Color = world("hat"),
			Parent = parent,
		})
		local lamp = kit.decor({
			Name = "Lamp",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(4 * s, 6.4 * s),
			CFrame = base * CFrame.new(0, 36.8 * s, 0) * UPRIGHT,
			Color = world("lighthouseLight"),
			Material = Enum.Material.Neon,
			CastShadow = false,
			Parent = parent,
		})
		light(lamp, world("lighthouseLight"), 30, 1.5)
		local roof = kit.decor({
			Name = "Roof",
			Size = Vector3.new(7.6, 6, 7.6) * s,
			CFrame = base * CFrame.new(0, 39.4 * s, 0),
			Color = world("lighthouseStripe"),
			Parent = parent,
		})
		sphereMesh(roof)
	end,

	-- A giant striped beach umbrella.
	beachUmbrella = function(base: CFrame, s: number, spot: LandmarkSpot, parent: Instance, kit: Kit)
		local frame = base * CFrame.Angles(math.rad(6), math.rad(spot.index * 41), 0)
		kit.decor({
			Name = "Pole",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(15 * s, 0.9 * s),
			CFrame = frame * CFrame.new(0, 7.5 * s, 0) * UPRIGHT,
			Color = world("lighthouse"),
			Parent = parent,
		})
		local first = if spot.index % 2 == 0 then "umbrella1" else "umbrella2"
		local second = if spot.index % 2 == 0 then "umbrella2" else "umbrella1"
		kit.decor({
			Name = "Canopy",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(1.4 * s, 18 * s),
			CFrame = frame * CFrame.new(0, 15 * s, 0) * UPRIGHT,
			Color = world(first),
			Material = Enum.Material.Fabric,
			Parent = parent,
		})
		kit.decor({
			Name = "CanopyRing",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(1.6 * s, 11 * s),
			CFrame = frame * CFrame.new(0, 15.2 * s, 0) * UPRIGHT,
			Color = world(second),
			Material = Enum.Material.Fabric,
			Parent = parent,
		})
		kit.decor({
			Name = "Knob",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 2.2 * s,
			CFrame = frame * CFrame.new(0, 16.4 * s, 0),
			Color = world(first),
			Parent = parent,
		})
	end,

	-- A red barn with a gable roof.
	barn = function(base: CFrame, s: number, _spot: LandmarkSpot, parent: Instance, kit: Kit)
		local width, height, depth = 30 * s, 16 * s, 22 * s
		kit.decor({
			Name = "Barn",
			Size = Vector3.new(width, height, depth),
			CFrame = base * CFrame.new(0, height / 2, 0),
			Color = world("barn"),
			Material = Enum.Material.WoodPlanks,
			Parent = parent,
		})
		for _, side in { -1, 1 } do
			-- WedgePart: the slope rises towards +Z, so each half turns to face out of its side.
			kit.wedge({
				Name = "Roof",
				Size = Vector3.new(width + 2 * s, 8 * s, depth / 2 + 1 * s),
				CFrame = base
					* CFrame.new(0, height + 4 * s, side * (depth / 4 + 0.5 * s))
					* CFrame.Angles(0, if side > 0 then math.pi else 0, 0),
				Color = world("hat"),
				Parent = parent,
			})
		end
		kit.decor({
			Name = "Door",
			Size = Vector3.new(10 * s, 11 * s, 0.6),
			CFrame = base * CFrame.new(0, 5.5 * s, -depth / 2 - 0.2),
			Color = world("barn"):Lerp(Color3.new(0, 0, 0), 0.25),
			Material = Enum.Material.WoodPlanks,
			Parent = parent,
		})
		for _, turn in { 48, -48 } do
			kit.decor({
				Name = "DoorBrace",
				Size = Vector3.new(14 * s, 0.9 * s, 0.5),
				CFrame = base * CFrame.new(0, 5.5 * s, -depth / 2 - 0.55) * CFrame.Angles(0, 0, math.rad(turn)),
				Color = world("barnTrim"),
				Parent = parent,
			})
		end
		kit.decor({
			Name = "Loft",
			Size = Vector3.new(5 * s, 4 * s, 0.6),
			CFrame = base * CFrame.new(0, 14 * s, -depth / 2 - 0.2),
			Color = world("barnTrim"),
			Parent = parent,
		})
	end,

	-- A stack of round hay bales.
	hayBales = function(base: CFrame, s: number, spot: LandmarkSpot, parent: Instance, kit: Kit)
		local frame = base * CFrame.Angles(0, math.rad(spot.index * 29), 0)
		for _, bale in
			{
				{ at = Vector3.new(-4, 3.4, 0), size = 1 },
				{ at = Vector3.new(4, 3.4, 0), size = 1 },
				{ at = Vector3.new(0, 9.2, 0), size = 0.95 },
				{ at = Vector3.new(11, 2.6, 6), size = 0.78 },
			}
		do
			kit.decor({
				Name = "HayBale",
				Shape = Enum.PartType.Cylinder,
				Size = cylinderSize(7.4 * bale.size * s, 7 * bale.size * s),
				CFrame = frame * CFrame.new(bale.at * s) * CFrame.Angles(0, math.rad(90), 0),
				Color = world("hay"),
				Material = Enum.Material.Grass,
				Parent = parent,
			})
		end
	end,

	-- A red torii gate facing the map.
	torii = function(base: CFrame, s: number, _spot: LandmarkSpot, parent: Instance, kit: Kit)
		for _, side in { -1, 1 } do
			kit.decor({
				Name = "Pillar",
				Shape = Enum.PartType.Cylinder,
				Size = cylinderSize(26 * s, 2.4 * s),
				CFrame = base * CFrame.new(side * 9 * s, 13 * s, 0) * UPRIGHT,
				Color = world("torii"),
				Parent = parent,
			})
		end
		kit.decor({
			Name = "TopBeam",
			Size = Vector3.new(28, 2, 3.2) * s,
			CFrame = base * CFrame.new(0, 27.4 * s, 0),
			Color = world("toriiDark"),
			Parent = parent,
		})
		kit.decor({
			Name = "UpperBeam",
			Size = Vector3.new(24, 1.6, 2.6) * s,
			CFrame = base * CFrame.new(0, 25.6 * s, 0),
			Color = world("torii"),
			Parent = parent,
		})
		kit.decor({
			Name = "TieBeam",
			Size = Vector3.new(21, 1.4, 1.6) * s,
			CFrame = base * CFrame.new(0, 21.2 * s, 0),
			Color = world("torii"),
			Parent = parent,
		})
		kit.decor({
			Name = "Plaque",
			Size = Vector3.new(2.6, 3.6, 0.6) * s,
			CFrame = base * CFrame.new(0, 23.4 * s, -1 * s),
			Color = world("toriiDark"),
			Parent = parent,
		})
	end,

	-- A three-tiered pagoda on a stone platform.
	pagoda = function(base: CFrame, s: number, spot: LandmarkSpot, parent: Instance, kit: Kit)
		local frame = base * CFrame.Angles(0, math.rad(spot.index * 17), 0)
		kit.decor({
			Name = "Platform",
			Size = Vector3.new(22, 2, 22) * s,
			CFrame = frame * CFrame.new(0, 1 * s, 0),
			Color = world("stoneLantern"),
			Material = Enum.Material.Slate,
			Parent = parent,
		})
		local y = 2
		for _, tier in
			{
				{ body = 15, height = 8, roof = 22 },
				{ body = 12, height = 7, roof = 18 },
				{ body = 9, height = 6, roof = 14 },
			}
		do
			kit.decor({
				Name = "Storey",
				Size = Vector3.new(tier.body, tier.height, tier.body) * s,
				CFrame = frame * CFrame.new(0, (y + tier.height / 2) * s, 0),
				Color = world("pagoda"),
				Parent = parent,
			})
			y += tier.height
			kit.decor({
				Name = "Roof",
				Size = Vector3.new(tier.roof, 1.6, tier.roof) * s,
				CFrame = frame * CFrame.new(0, (y + 0.8) * s, 0),
				Color = world("pagodaRoof"),
				Parent = parent,
			})
			y += 1.6
		end
		kit.decor({
			Name = "Spire",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(8 * s, 0.9 * s),
			CFrame = frame * CFrame.new(0, (y + 4) * s, 0) * UPRIGHT,
			Color = world("lantern"),
			Material = Enum.Material.Metal,
			Parent = parent,
		})
	end,

	-- A rocket on its launch pad, nose to the sky.
	rocket = function(base: CFrame, s: number, _spot: LandmarkSpot, parent: Instance, kit: Kit)
		kit.decor({
			Name = "Pad",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(2 * s, 24 * s),
			CFrame = base * CFrame.new(0, 1 * s, 0) * UPRIGHT,
			Color = world("launchPad"),
			Material = Enum.Material.DiamondPlate,
			Parent = parent,
		})
		kit.decor({
			Name = "Body",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(32 * s, 9 * s),
			CFrame = base * CFrame.new(0, 18 * s, 0) * UPRIGHT,
			Color = world("rocket"),
			Parent = parent,
		})
		local nose = kit.decor({
			Name = "Nose",
			Size = Vector3.new(9, 14, 9) * s,
			CFrame = base * CFrame.new(0, 34 * s, 0),
			Color = world("rocketTrim"),
			Parent = parent,
		})
		sphereMesh(nose)
		kit.decor({
			Name = "Stripe",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(2.4 * s, 9.3 * s),
			CFrame = base * CFrame.new(0, 26 * s, 0) * UPRIGHT,
			Color = world("rocketTrim"),
			Parent = parent,
		})
		kit.decor({
			Name = "Window",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(0.6 * s, 3.6 * s),
			CFrame = base * CFrame.new(0, 21 * s, -4.4 * s) * CFrame.Angles(0, math.rad(90), 0),
			Color = world("rocketWindow"),
			Material = Enum.Material.Neon,
			CastShadow = false,
			Parent = parent,
		})
		for i = 0, 2 do
			kit.decor({
				Name = "Fin",
				Size = Vector3.new(0.9, 10, 6) * s,
				CFrame = base
					* CFrame.Angles(0, math.rad(i * 120 + 30), 0)
					* CFrame.new(0, 7 * s, -6.5 * s)
					* CFrame.Angles(math.rad(-12), 0, 0),
				Color = world("rocketTrim"),
				Parent = parent,
			})
		end
	end,

	-- A ringed planet and its little moon hanging in the sky.
	planet = function(_base: CFrame, s: number, spot: LandmarkSpot, parent: Instance, kit: Kit)
		local centre = CFrame.new(spot.x, spot.y + (95 + (spot.index % 3) * 15) * s, spot.z)
			* CFrame.Angles(math.rad(18), math.rad(spot.index * 37), math.rad(-12))
		kit.decor({
			Name = "Planet",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 34 * s,
			CFrame = centre,
			Color = world("planet"),
			Parent = parent,
		})
		kit.decor({
			Name = "Ring",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(0.6 * s, 62 * s),
			CFrame = centre * UPRIGHT,
			Color = world("planetRing"),
			Transparency = 0.25,
			CastShadow = false,
			Parent = parent,
		})
		kit.decor({
			Name = "Moon",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 8 * s,
			CFrame = centre * CFrame.new(40 * s, 14 * s, 0),
			Color = world("moonRock"):Lerp(Color3.new(1, 1, 1), 0.5),
			Parent = parent,
		})
	end,

	-- A radar dish listening to the stars.
	satelliteDish = function(base: CFrame, s: number, spot: LandmarkSpot, parent: Instance, kit: Kit)
		local frame = base * CFrame.Angles(0, math.rad(spot.index * 31 - 60), 0)
		kit.decor({
			Name = "Base",
			Size = Vector3.new(7, 4, 7) * s,
			CFrame = frame * CFrame.new(0, 2 * s, 0),
			Color = world("launchPad"),
			Material = Enum.Material.DiamondPlate,
			Parent = parent,
		})
		kit.decor({
			Name = "Mast",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(10 * s, 1.8 * s),
			CFrame = frame * CFrame.new(0, 9 * s, 0) * UPRIGHT,
			Color = world("dish"),
			Material = Enum.Material.Metal,
			Parent = parent,
		})
		local face = frame * CFrame.new(0, 16 * s, 0) * CFrame.Angles(math.rad(40), 0, 0)
		local dish = kit.decor({
			Name = "Dish",
			Size = Vector3.new(16, 16, 3) * s,
			CFrame = face,
			Color = world("dish"),
			Parent = parent,
		})
		sphereMesh(dish)
		kit.decor({
			Name = "Feed",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(6 * s, 0.5 * s),
			CFrame = face * CFrame.new(0, 0, -4 * s) * CFrame.Angles(0, math.rad(90), 0),
			Color = world("launchPad"),
			Parent = parent,
		})
		kit.decor({
			Name = "Beacon",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 1.6 * s,
			CFrame = face * CFrame.new(0, 0, -7.2 * s),
			Color = world("rocketTrim"),
			Material = Enum.Material.Neon,
			CastShadow = false,
			Parent = parent,
		})
	end,

	-- A stepped temple with a shrine on top and stairs down the side facing the map.
	temple = function(base: CFrame, s: number, _spot: LandmarkSpot, parent: Instance, kit: Kit)
		for i, width in { 40, 32, 24, 16 } do
			kit.decor({
				Name = "Tier",
				Size = Vector3.new(width, 7, width) * s,
				CFrame = base * CFrame.new(0, (3.5 + (i - 1) * 7) * s, 0),
				Color = if i == 2 then world("templeMoss") else world("templeStone"),
				Material = Enum.Material.Cobblestone,
				Parent = parent,
			})
		end
		kit.decor({
			Name = "Shrine",
			Size = Vector3.new(10, 8, 10) * s,
			CFrame = base * CFrame.new(0, 32 * s, 0),
			Color = world("templeStone"):Lerp(Color3.new(0, 0, 0), 0.2),
			Material = Enum.Material.Cobblestone,
			Parent = parent,
		})
		local foot = (base * CFrame.new(0, 0, -21 * s)).Position
		local top = (base * CFrame.new(0, 28 * s, -8 * s)).Position
		kit.decor({
			Name = "Stairs",
			Size = Vector3.new((top - foot).Magnitude, 1.4 * s, 6 * s),
			CFrame = along(foot, top),
			Color = world("templeStone"):Lerp(Color3.new(1, 1, 1), 0.12),
			Material = Enum.Material.Slate,
			Parent = parent,
		})
	end,

	-- A flower as tall as a house, its head tipped towards the map.
	giantFlower = function(base: CFrame, s: number, spot: LandmarkSpot, parent: Instance, kit: Kit)
		kit.decor({
			Name = "Stem",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(30 * s, 2.2 * s),
			CFrame = base * CFrame.new(0, 15 * s, 0) * UPRIGHT,
			Color = world("vine"),
			Parent = parent,
		})
		for _, leaf in { { y = 9, side = 1 }, { y = 15, side = -1 } } do
			local blade = kit.decor({
				Name = "Leaf",
				Size = Vector3.new(14, 1, 5) * s,
				CFrame = base
					* CFrame.new(leaf.side * 6 * s, leaf.y * s, 0)
					* CFrame.Angles(0, 0, math.rad(leaf.side * 25)),
				Color = world("leaves"),
				Parent = parent,
			})
			sphereMesh(blade)
		end
		local head = base * CFrame.new(0, 31 * s, 0) * CFrame.Angles(math.rad(-30), 0, 0)
		local petalColor = world(if spot.index % 2 == 0 then "petal" else "petalAlt")
		for i = 0, 3 do
			local petal = kit.decor({
				Name = "Petal",
				Size = Vector3.new(11, 6, 2) * s,
				CFrame = head * CFrame.Angles(0, 0, math.rad(i * 90 + 45)) * CFrame.new(6 * s, 0, 0),
				Color = petalColor,
				Parent = parent,
			})
			sphereMesh(petal)
		end
		kit.decor({
			Name = "Centre",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 7 * s,
			CFrame = head * CFrame.new(0, 0, -0.6 * s),
			Color = world("flowerCentre"),
			Parent = parent,
		})
	end,

	-- A dark skyscraper with lit windows and a neon band near the top.
	skyscraper = function(base: CFrame, s: number, spot: LandmarkSpot, parent: Instance, kit: Kit)
		local height = (58 + (spot.index * 13) % 34) * s
		local width = (18 + (spot.index % 3) * 3) * s
		kit.decor({
			Name = "Tower",
			Size = Vector3.new(width, height, width),
			CFrame = base * CFrame.new(0, height / 2, 0),
			Color = world("tower"),
			Material = Enum.Material.Glass,
			Reflectance = 0.15,
			Parent = parent,
		})
		for _, side in { -1, 1 } do
			kit.decor({
				Name = "Windows",
				Size = Vector3.new(2.2 * s, height * 0.8, 0.4),
				CFrame = base * CFrame.new(side * width * 0.24, height * 0.46, -width / 2 - 0.2),
				Color = world("towerWindow"),
				Material = Enum.Material.Neon,
				CastShadow = false,
				Parent = parent,
			})
		end
		kit.decor({
			Name = "NeonBand",
			Size = Vector3.new(width + 0.6, 1.4 * s, width + 0.6),
			CFrame = base * CFrame.new(0, height - 6 * s, 0),
			Color = if spot.index % 2 == 0 then world("neonPink") else world("neonBlue"),
			Material = Enum.Material.Neon,
			CastShadow = false,
			Parent = parent,
		})
		kit.decor({
			Name = "Top",
			Size = Vector3.new(width * 0.6, 12 * s, width * 0.6),
			CFrame = base * CFrame.new(0, height + 6 * s, 0),
			Color = world("tower"),
			Material = Enum.Material.Glass,
			Reflectance = 0.15,
			Parent = parent,
		})
		kit.decor({
			Name = "Antenna",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(14 * s, 0.6 * s),
			CFrame = base * CFrame.new(0, height + 19 * s, 0) * UPRIGHT,
			Color = world("streetLamp"),
			Material = Enum.Material.Metal,
			Parent = parent,
		})
	end,

	-- A giant neon noodle-bar sign on two posts.
	neonSign = function(base: CFrame, s: number, _spot: LandmarkSpot, parent: Instance, kit: Kit)
		for _, side in { -1, 1 } do
			kit.decor({
				Name = "Post",
				Shape = Enum.PartType.Cylinder,
				Size = cylinderSize(24 * s, 1.6 * s),
				CFrame = base * CFrame.new(side * 11 * s, 12 * s, 0) * UPRIGHT,
				Color = world("streetLamp"),
				Material = Enum.Material.Metal,
				Parent = parent,
			})
		end
		kit.decor({
			Name = "Glow",
			Size = Vector3.new(32, 18, 1) * s,
			CFrame = base * CFrame.new(0, 31 * s, 0.4 * s),
			Color = world("neonPink"),
			Material = Enum.Material.Neon,
			CastShadow = false,
			Parent = parent,
		})
		kit.decor({
			Name = "Board",
			Size = Vector3.new(30, 16, 1.6) * s,
			CFrame = base * CFrame.new(0, 31 * s, -0.4 * s),
			Color = world("tower"),
			Parent = parent,
		})
		local bowl = kit.decor({
			Name = "Bowl",
			Size = Vector3.new(14, 7, 1) * s,
			CFrame = base * CFrame.new(0, 28 * s, -1.4 * s),
			Color = world("neonBlue"),
			Material = Enum.Material.Neon,
			CastShadow = false,
			Parent = parent,
		})
		sphereMesh(bowl)
		kit.decor({
			Name = "Chopsticks",
			Size = Vector3.new(0.9, 13, 0.6) * s,
			CFrame = base * CFrame.new(3 * s, 34 * s, -1.6 * s) * CFrame.Angles(0, 0, math.rad(-24)),
			Color = world("neonYellow"),
			Material = Enum.Material.Neon,
			CastShadow = false,
			Parent = parent,
		})
	end,

	-- An island floating in the sky, with a tree on its grassy top.
	floatingIsland = function(_base: CFrame, s: number, spot: LandmarkSpot, parent: Instance, kit: Kit)
		local top = CFrame.new(spot.x, spot.y + (62 + (spot.index % 3) * 12) * s, spot.z)
			* CFrame.Angles(0, math.rad(spot.index * 47), 0)
		for i, tier in { { d = 24, h = 5 }, { d = 17, h = 5 }, { d = 9, h = 5 } } do
			kit.decor({
				Name = "Rock",
				Shape = Enum.PartType.Cylinder,
				Size = cylinderSize(tier.h * s, tier.d * s),
				CFrame = top * CFrame.new(0, -(1 + (i - 0.5) * tier.h) * s, 0) * UPRIGHT,
				Color = world("islandRock"),
				Material = Enum.Material.Slate,
				Parent = parent,
			})
		end
		kit.decor({
			Name = "Grass",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(2 * s, 25 * s),
			CFrame = top * UPRIGHT,
			Color = world("islandGrass"),
			Material = Enum.Material.Grass,
			Parent = parent,
		})
		kit.decor({
			Name = "Trunk",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(8 * s, 1.6 * s),
			CFrame = top * CFrame.new(3 * s, 5 * s, 2 * s) * UPRIGHT,
			Color = world("treeTrunk"),
			Material = Enum.Material.Wood,
			Parent = parent,
		})
		kit.decor({
			Name = "Leaves",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 9 * s,
			CFrame = top * CFrame.new(3 * s, 11 * s, 2 * s),
			Color = world("islandGrass"),
			Material = Enum.Material.Grass,
			Parent = parent,
		})
	end,

	-- A castle with two round towers, sitting on a cloud.
	skyCastle = function(_base: CFrame, s: number, spot: LandmarkSpot, parent: Instance, kit: Kit)
		local position = Vector3.new(spot.x, spot.y + (70 + (spot.index % 2) * 14) * s, spot.z)
		local floor = CFrame.lookAt(position, Vector3.new(0, position.Y, 0))
		for _, puff in
			{
				{ size = Vector3.new(34, 12, 28), at = Vector3.new(0, 1, 0) },
				{ size = Vector3.new(22, 10, 18), at = Vector3.new(14, 0, 6) },
			}
		do
			local cloud = kit.decor({
				Name = "Cloud",
				Size = puff.size * s,
				CFrame = floor * CFrame.new(puff.at * s),
				Color = world("cloudPuff"),
				Material = Enum.Material.Sand,
				CastShadow = false,
				Parent = parent,
			})
			sphereMesh(cloud)
		end
		kit.decor({
			Name = "Keep",
			Size = Vector3.new(12, 14, 12) * s,
			CFrame = floor * CFrame.new(0, 13 * s, 0),
			Color = world("castleWall"),
			Material = Enum.Material.Marble,
			Parent = parent,
		})
		for _, side in { -1, 1 } do
			kit.decor({
				Name = "Tower",
				Shape = Enum.PartType.Cylinder,
				Size = cylinderSize(22 * s, 6 * s),
				CFrame = floor * CFrame.new(side * 8.5 * s, 17 * s, 0) * UPRIGHT,
				Color = world("castleWall"),
				Material = Enum.Material.Marble,
				Parent = parent,
			})
			local roof = kit.decor({
				Name = "Roof",
				Size = Vector3.new(7.4, 10, 7.4) * s,
				CFrame = floor * CFrame.new(side * 8.5 * s, 30 * s, 0),
				Color = world("castleRoof"),
				Parent = parent,
			})
			sphereMesh(roof)
		end
	end,

	-- A sunken ship, half buried and listing, its torn sail still up.
	shipwreck = function(base: CFrame, s: number, spot: LandmarkSpot, parent: Instance, kit: Kit)
		local frame = base
			* CFrame.Angles(0, math.rad(spot.index * 23 + 70), 0)
			* CFrame.Angles(math.rad(-5), 0, math.rad(17))
		kit.decor({
			Name = "Hull",
			Size = Vector3.new(14, 9, 38) * s,
			CFrame = frame * CFrame.new(0, 3 * s, 0),
			Color = world("shipWood"),
			Material = Enum.Material.WoodPlanks,
			Parent = parent,
		})
		kit.decor({
			Name = "Bow",
			Size = Vector3.new(9.9, 9, 9.9) * s,
			CFrame = frame * CFrame.new(0, 3 * s, -19 * s) * CFrame.Angles(0, math.rad(45), 0),
			Color = world("shipWood"),
			Material = Enum.Material.WoodPlanks,
			Parent = parent,
		})
		kit.decor({
			Name = "Cabin",
			Size = Vector3.new(10, 6, 9) * s,
			CFrame = frame * CFrame.new(0, 10.5 * s, 12 * s),
			Color = world("shipWood"):Lerp(Color3.new(0, 0, 0), 0.2),
			Material = Enum.Material.WoodPlanks,
			Parent = parent,
		})
		kit.decor({
			Name = "Mast",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(26 * s, 1.6 * s),
			CFrame = frame * CFrame.new(0, 20 * s, -3 * s) * UPRIGHT,
			Color = world("shipWood"),
			Material = Enum.Material.Wood,
			Parent = parent,
		})
		kit.decor({
			Name = "Sail",
			Size = Vector3.new(13, 10, 0.4) * s,
			CFrame = frame * CFrame.new(0, 24 * s, -3.6 * s) * CFrame.Angles(math.rad(6), 0, math.rad(4)),
			Color = world("shipSail"),
			Material = Enum.Material.Fabric,
			Transparency = 0.1,
			Parent = parent,
		})
		kit.decor({
			Name = "Flag",
			Size = Vector3.new(4.4, 2.6, 0.2) * s,
			CFrame = frame * CFrame.new(2.4 * s, 31.6 * s, -3 * s),
			Color = world("hat"),
			Material = Enum.Material.Fabric,
			Parent = parent,
		})
		kit.decor({
			Name = "BrokenMast",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(14 * s, 1.4 * s),
			CFrame = base * CFrame.new(16 * s, 0.6 * s, -8 * s) * CFrame.Angles(0, math.rad(spot.index * 41), 0),
			Color = world("shipWood"),
			Material = Enum.Material.Wood,
			Parent = parent,
		})
	end,

	-- A giant clam, open, with a glowing pearl.
	giantClam = function(base: CFrame, s: number, spot: LandmarkSpot, parent: Instance, kit: Kit)
		local frame = base * CFrame.Angles(0, math.rad(spot.index * 19 - 30), 0)
		local bottom = kit.decor({
			Name = "Shell",
			Size = Vector3.new(26, 8, 20) * s,
			CFrame = frame * CFrame.new(0, 3 * s, 0),
			Color = world("clam"),
			Parent = parent,
		})
		sphereMesh(bottom)
		local lid = kit.decor({
			Name = "Lid",
			Size = Vector3.new(26, 8, 20) * s,
			-- Hinged at the back (+Z), opened up towards the map.
			CFrame = frame * CFrame.new(0, 5 * s, 9 * s) * CFrame.Angles(math.rad(40), 0, 0) * CFrame.new(0, 0, -9 * s),
			Color = world("clam"),
			Parent = parent,
		})
		sphereMesh(lid)
		local mantle = kit.decor({
			Name = "Mantle",
			Size = Vector3.new(21, 3, 15) * s,
			CFrame = frame * CFrame.new(0, 5.4 * s, 0),
			Color = world("clamInner"),
			Parent = parent,
		})
		sphereMesh(mantle)
		local pearl = kit.decor({
			Name = "Pearl",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 6 * s,
			CFrame = frame * CFrame.new(0, 8.6 * s, -1 * s),
			Color = world("pearl"),
			Reflectance = 0.3,
			Parent = parent,
		})
		light(pearl, world("pearl"), 22, 1.2)
	end,
	-- A tiered chocolate fountain, chocolate pouring off every tier into a pool.
	chocolateFountain = function(base: CFrame, s: number, _spot: LandmarkSpot, parent: Instance, kit: Kit)
		local metal = world("fountainMetal")
		local chocolate = world("chocolate")
		kit.decor({
			Name = "Rim",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(2.6 * s, 32 * s),
			CFrame = base * CFrame.new(0, 1.3 * s, 0) * UPRIGHT,
			Color = metal,
			Material = Enum.Material.Metal,
			Parent = parent,
		})
		kit.decor({
			Name = "Pool",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(2.8 * s, 28.5 * s),
			CFrame = base * CFrame.new(0, 1.4 * s, 0) * UPRIGHT,
			Color = chocolate,
			Reflectance = 0.1,
			Parent = parent,
		})
		kit.decor({
			Name = "Column",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(22 * s, 2.6 * s),
			CFrame = base * CFrame.new(0, 13 * s, 0) * UPRIGHT,
			Color = metal,
			Material = Enum.Material.Metal,
			Parent = parent,
		})
		local bottom = 2.8
		for i, tier in { { d = 22, y = 8 }, { d = 15, y = 14.5 }, { d = 9, y = 20.5 } } do
			kit.decor({
				Name = "Tier",
				Shape = Enum.PartType.Cylinder,
				Size = cylinderSize(1 * s, tier.d * s),
				CFrame = base * CFrame.new(0, tier.y * s, 0) * UPRIGHT,
				Color = metal,
				Material = Enum.Material.Metal,
				Parent = parent,
			})
			local height = tier.y - 0.5 - bottom
			kit.decor({
				Name = "Cascade",
				Shape = Enum.PartType.Cylinder,
				Size = cylinderSize(height * s, (tier.d - 0.7) * s),
				CFrame = base * CFrame.new(0, (bottom + height / 2) * s, 0) * UPRIGHT,
				Color = chocolate:Lerp(world("chocolateLight"), (i - 1) * 0.15),
				Reflectance = 0.12,
				Transparency = 0.1,
				Parent = parent,
			})
			bottom = tier.y + 0.5
		end
		kit.decor({
			Name = "Crown",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 4.6 * s,
			CFrame = base * CFrame.new(0, 23.6 * s, 0),
			Color = chocolate,
			Reflectance = 0.12,
			Parent = parent,
		})
	end,

	-- A Ferris wheel: an eight-sided rim on spokes, gondolas hanging from it, on two A-frames.
	ferrisWheel = function(base: CFrame, s: number, spot: LandmarkSpot, parent: Instance, kit: Kit)
		local radius = 18 * s
		local hubAt = base * CFrame.new(0, 23 * s, 0) * CFrame.Angles(0, math.rad(spot.index * 17), 0)
		local frame = world("ferrisFrame")
		for _, side in { -1, 1 } do
			for _, lean in { -1, 1 } do
				local foot = (hubAt * CFrame.new(lean * 11 * s, -23 * s, side * 3 * s)).Position
				local top = (hubAt * CFrame.new(0, 0, side * 1.6 * s)).Position
				kit.decor({
					Name = "Leg",
					Size = Vector3.new((top - foot).Magnitude, 1.2 * s, 1.2 * s),
					CFrame = along(foot, top),
					Color = frame,
					Material = Enum.Material.Metal,
					Parent = parent,
				})
			end
		end
		kit.decor({
			Name = "Hub",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(4 * s, 3 * s),
			CFrame = hubAt * CFrame.Angles(0, math.rad(90), 0),
			Color = world("tentFlag"),
			Material = Enum.Material.Metal,
			Parent = parent,
		})
		local side = 2 * radius * math.sin(math.pi / 8) + 0.6 * s
		for i = 0, 7 do
			local angle = (i + 0.5) * math.pi / 4
			kit.decor({
				Name = "Rim",
				Size = Vector3.new(side, 1.2 * s, 1.2 * s),
				CFrame = hubAt * CFrame.Angles(0, 0, angle) * CFrame.new(0, radius * math.cos(math.pi / 8), 0),
				Color = world("ferrisRim"),
				Material = Enum.Material.Neon,
				Parent = parent,
			})
		end
		for i = 0, 3 do
			kit.decor({
				Name = "Spoke",
				Size = Vector3.new(0.6 * s, 2 * radius, 0.6 * s),
				CFrame = hubAt * CFrame.Angles(0, 0, i * math.pi / 4),
				Color = frame,
				Material = Enum.Material.Metal,
				Parent = parent,
			})
		end
		for i = 0, 3 do
			local angle = i * math.pi / 2 + math.pi / 4
			local at = (hubAt * CFrame.new(math.cos(angle) * radius, math.sin(angle) * radius, 0)).Position
			kit.decor({
				Name = "Gondola",
				Size = Vector3.new(4.4, 3.6, 3.6) * s,
				CFrame = CFrame.new(at - Vector3.new(0, 2.6 * s, 0)) * (hubAt - hubAt.Position),
				Color = candy(i + spot.index),
				Parent = parent,
			})
		end
	end,

	-- A striped circus big top with a flag.
	circusTent = function(base: CFrame, s: number, spot: LandmarkSpot, parent: Instance, kit: Kit)
		local red, white = world("tentRed"), world("tentWhite")
		kit.decor({
			Name = "Tent",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(10 * s, 24 * s),
			CFrame = base * CFrame.new(0, 5 * s, 0) * UPRIGHT,
			Color = red,
			Material = Enum.Material.Fabric,
			Parent = parent,
		})
		kit.decor({
			Name = "Trim",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(1.6 * s, 24.6 * s),
			CFrame = base * CFrame.new(0, 9.2 * s, 0) * UPRIGHT,
			Color = white,
			Material = Enum.Material.Fabric,
			Parent = parent,
		})
		-- A stepped cone of red and white bands.
		for i, tier in { { d = 27, y = 11.2 }, { d = 21, y = 13.4 }, { d = 14.5, y = 15.6 }, { d = 8, y = 17.8 } } do
			kit.decor({
				Name = "Roof",
				Shape = Enum.PartType.Cylinder,
				Size = cylinderSize(2.4 * s, tier.d * s),
				CFrame = base * CFrame.new(0, tier.y * s, 0) * UPRIGHT,
				Color = if i % 2 == 1 then white else red,
				Material = Enum.Material.Fabric,
				Parent = parent,
			})
		end
		kit.decor({
			Name = "Pole",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(5 * s, 0.6 * s),
			CFrame = base * CFrame.new(0, 21.2 * s, 0) * UPRIGHT,
			Color = world("hat"),
			Parent = parent,
		})
		kit.decor({
			Name = "Flag",
			Size = Vector3.new(3.4, 2.2, 0.2) * s,
			CFrame = base * CFrame.new(1.7 * s, 22.6 * s, 0) * CFrame.Angles(0, math.rad(spot.index * 37), 0),
			Color = world("tentFlag"),
			Material = Enum.Material.Fabric,
			Parent = parent,
		})
		kit.decor({
			Name = "Door",
			Size = Vector3.new(5.5, 7, 1) * s,
			CFrame = base * CFrame.new(0, 3.5 * s, -11.8 * s),
			Color = world("hat"),
			Parent = parent,
		})
	end,

	-- A white marble bell tower with arcaded storeys, leaning a little.
	leaningTower = function(base: CFrame, s: number, spot: LandmarkSpot, parent: Instance, kit: Kit)
		local frame = base * CFrame.Angles(0, math.rad(spot.index * 29), 0) * CFrame.Angles(0, 0, math.rad(5))
		kit.decor({
			Name = "Base",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(6 * s, 14 * s),
			CFrame = frame * CFrame.new(0, 3 * s, 0) * UPRIGHT,
			Color = world("towerMarble"),
			Material = Enum.Material.Marble,
			Parent = parent,
		})
		for i = 1, 5 do
			kit.decor({
				Name = "Storey",
				Shape = Enum.PartType.Cylinder,
				Size = cylinderSize(5.6 * s, 13 * s),
				CFrame = frame * CFrame.new(0, (6 + (i - 0.5) * 5.4) * s, 0) * UPRIGHT,
				Color = if i % 2 == 0 then world("towerShade") else world("towerMarble"),
				Material = Enum.Material.Marble,
				Parent = parent,
			})
		end
		kit.decor({
			Name = "Belfry",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(4.6 * s, 9 * s),
			CFrame = frame * CFrame.new(0, 35.3 * s, 0) * UPRIGHT,
			Color = world("towerMarble"),
			Material = Enum.Material.Marble,
			Parent = parent,
		})
		local dome = kit.decor({
			Name = "Dome",
			Size = Vector3.new(9.4, 4, 9.4) * s,
			CFrame = frame * CFrame.new(0, 37.6 * s, 0),
			Color = world("towerShade"),
			Material = Enum.Material.Marble,
			Parent = parent,
		})
		sphereMesh(dome)
	end,

	-- A big brick pizza oven on a stone base, a fire glowing in its mouth.
	pizzaOven = function(base: CFrame, size: number, _spot: LandmarkSpot, parent: Instance, kit: Kit)
		local s = size * 1.6
		kit.decor({
			Name = "OvenBase",
			Size = Vector3.new(18, 4, 16) * s,
			CFrame = base * CFrame.new(0, 2 * s, 0),
			Color = world("ovenBase"),
			Material = Enum.Material.Cobblestone,
			Parent = parent,
		})
		local dome = kit.decor({
			Name = "Dome",
			Size = Vector3.new(15, 11, 13) * s,
			CFrame = base * CFrame.new(0, 6 * s, 0.5 * s),
			Color = world("ovenDome"),
			Material = Enum.Material.Brick,
			Parent = parent,
		})
		sphereMesh(dome)
		local mouth = kit.decor({
			Name = "Mouth",
			Size = Vector3.new(5.6, 4.2, 2.4) * s,
			CFrame = base * CFrame.new(0, 6 * s, -5.7 * s),
			Color = Color3.fromRGB(42, 26, 20),
			Parent = parent,
		})
		sphereMesh(mouth)
		local fire = kit.decor({
			Name = "Fire",
			Size = Vector3.new(3.8, 2.2, 1.2) * s,
			CFrame = base * CFrame.new(0, 5.2 * s, -5.5 * s),
			Color = world("ovenFire"),
			Material = Enum.Material.Neon,
			CastShadow = false,
			Parent = parent,
		})
		sphereMesh(fire)
		light(fire, world("ovenFire"), 24, 1.6)
		kit.decor({
			Name = "Chimney",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(6 * s, 2.2 * s),
			CFrame = base * CFrame.new(3.2 * s, 12.5 * s, 2.5 * s) * UPRIGHT,
			Color = world("ovenDome"),
			Material = Enum.Material.Brick,
			Parent = parent,
		})
	end,
}

-- Builds one landmark. `kind` must be a LandmarkKind.
function ThemeProps.landmark(kind: string, spot: LandmarkSpot, parent: Instance, kit: Kit)
	local base = facingCentre(Vector3.new(spot.x, spot.y - 0.5, spot.z))
	local builder = landmarks[kind]
	if builder then
		builder(base, spot.scale, spot, parent, kit)
	end
end

return ThemeProps
