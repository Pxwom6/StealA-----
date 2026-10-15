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

-- A hexagonal prism (a honeycomb cell) `height` tall on `frame` (its bottom centre), corners `radius` from its middle,
-- from three blocks turned 60° apart: each block is the hexagon between two opposite corners, so together they fill
-- it exactly. `first` makes the first block (core() for a flora's solid column), kit.decor the other two. A neighbour
-- sharing a flat side stands radius * sqrt(3) away along the frame's Z axis, turned by a multiple of 60°.
local HEX_FLAT = math.sqrt(3)
local function hexPrism(
	frame: CFrame,
	radius: number,
	height: number,
	props: { [string]: any },
	first: (props: { [string]: any }) -> Part,
	kit: Kit
)
	for i = 0, 2 do
		local block = table.clone(props)
		block.Size = Vector3.new(radius, height, radius * HEX_FLAT)
		block.CFrame = frame * CFrame.Angles(0, math.rad(i * 60), 0) * CFrame.new(0, height / 2, 0)
		local make: (props: { [string]: any }) -> Part = if i == 0 then first else kit.decor
		make(block)
	end
end

-- A soft plume rising from `at` (steam off broth and hot springs, smoke from chimneys and smokers), on an attachment
-- under `parent`.
local function plume(parent: BasePart, at: Vector3, color: Color3, size: number, rate: number, kit: Kit)
	local attachment = Instance.new("Attachment")
	attachment.Name = "Plume"
	attachment.Parent = parent
	attachment.WorldCFrame = CFrame.new(at)
	kit.emitter(attachment, {
		Name = "Plume",
		Texture = SMOKE_TEXTURE,
		Color = ColorSequence.new(color),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, size * 0.4),
			NumberSequenceKeypoint.new(1, size),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.45),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Speed = NumberRange.new(3, 5),
		SpreadAngle = Vector2.new(14, 14),
		Acceleration = Vector3.new(0.6, 0.8, 0.2),
		Lifetime = NumberRange.new(3, 5),
		Rate = rate,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-20, 20),
		EmissionDirection = Enum.NormalId.Top,
	})
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
	-- A wooden stick crusted with chunks of rock candy in three colours.
	rockCandyStick = function(base: CFrame, s: number, random: Random, spot: Spot, parent: Instance, kit: Kit)
		core(spot, kit)({
			Name = "Stick",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(7 * s, 0.5 * s),
			CFrame = base * CFrame.new(0, 3.5 * s, 0) * UPRIGHT,
			Color = world("candyStickWood"),
			Material = Enum.Material.Wood,
			Parent = parent,
		})
		local first = random:NextInteger(0, 2)
		for i, chunk in
			{
				{ size = Vector3.new(2.4, 2.8, 2.4), y = 6.6, turn = 0.4 },
				{ size = Vector3.new(2, 2.4, 2), y = 8.6, turn = 1.3 },
				{ size = Vector3.new(1.8, 2.2, 1.8), y = 4.9, turn = 2.2 },
			}
		do
			local crystal = kit.decor({
				Name = "RockCandy",
				Size = chunk.size * s,
				CFrame = base
					* CFrame.new(0, chunk.y * s, 0)
					* CFrame.Angles(random:NextNumber(-0.3, 0.3), chunk.turn, random:NextNumber(0.5, 0.9)),
				Color = world(`rockCandy{(first + i) % 3 + 1}`),
				Material = Enum.Material.Glass,
				Transparency = 0.2,
				Parent = parent,
			})
			crystal.Reflectance = 0.15
		end
	end,

	-- A lemon tree: a round canopy dotted with lemons.
	lemonTree = function(base: CFrame, s: number, random: Random, spot: Spot, parent: Instance, kit: Kit)
		core(spot, kit)({
			Name = "Trunk",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(5.4 * s, 1.1 * s),
			CFrame = base * CFrame.new(0, 2.7 * s, 0) * UPRIGHT,
			Color = world("treeTrunk"),
			Material = Enum.Material.Wood,
			Parent = parent,
		})
		local canopy = kit.decor({
			Name = "Leaves",
			Size = Vector3.new(6.6, 5.4, 6.6) * s,
			CFrame = base * CFrame.new(0, 8 * s, 0),
			Color = world("lemonLeaf"),
			Parent = parent,
		})
		sphereMesh(canopy)
		local top = kit.decor({
			Name = "Leaves",
			Size = Vector3.new(4.4, 3.6, 4.4) * s,
			CFrame = base * CFrame.new(1 * s, 10.2 * s, -0.6 * s),
			Color = world("lemonLeaf"):Lerp(Color3.new(0, 0, 0), 0.12),
			Parent = parent,
		})
		sphereMesh(top)
		local turn = random:NextNumber(0, math.pi * 2)
		for i = 0, 2 do
			local yaw = turn + i * 2.1
			local lemon = kit.decor({
				Name = "Lemon",
				Size = Vector3.new(1.2, 1.5, 1.2) * s,
				CFrame = base
					* CFrame.new(math.cos(yaw) * 3.4 * s, (6.8 + i * 0.8) * s, math.sin(yaw) * 3.4 * s)
					* CFrame.Angles(0, yaw, 0.3),
				Color = world("lemon"),
				Parent = parent,
			})
			sphereMesh(lemon)
		end
	end,

	-- A swamp tree with pink bubblegum moss hanging from its branches.
	gumTree = function(base: CFrame, s: number, random: Random, spot: Spot, parent: Instance, kit: Kit)
		core(spot, kit)({
			Name = "Trunk",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(6.6 * s, 1.3 * s),
			CFrame = base * CFrame.new(0, 3.3 * s, 0) * UPRIGHT,
			Color = world("swampTrunk"),
			Material = Enum.Material.Wood,
			Parent = parent,
		})
		local canopy = kit.decor({
			Name = "Leaves",
			Size = Vector3.new(7.6, 3.4, 7.6) * s,
			CFrame = base * CFrame.new(0, 8.2 * s, 0),
			Color = world("swampLeaf"),
			Parent = parent,
		})
		sphereMesh(canopy)
		local turn = random:NextNumber(0, math.pi * 2)
		for i = 0, 1 do
			local yaw = turn + i * math.pi
			local moss = kit.decor({
				Name = "Moss",
				Size = Vector3.new(1.4, 4.6, 1.1) * s,
				CFrame = base * CFrame.new(math.cos(yaw) * 2.6 * s, 5.8 * s, math.sin(yaw) * 2.6 * s),
				Color = if i == 0 then world("gumPink") else world("gumPinkLight"),
				Material = Enum.Material.Fabric,
				Parent = parent,
			})
			sphereMesh(moss)
		end
	end,

	-- A stalk blowing three glossy bubblegum bubbles.
	bubblePlant = function(base: CFrame, s: number, random: Random, spot: Spot, parent: Instance, kit: Kit)
		core(spot, kit)({
			Name = "Stalk",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(5 * s, 0.6 * s),
			CFrame = base * CFrame.new(0, 2.5 * s, 0) * UPRIGHT,
			Color = world("swampLeaf"),
			Parent = parent,
		})
		local turn = random:NextNumber(0, math.pi * 2)
		for i, bubble in { { d = 3.6, r = 0, y = 6.6 }, { d = 2.4, r = 1.5, y = 8.6 }, { d = 1.7, r = 1.2, y = 5.3 } } do
			local yaw = turn + i * 2.3
			local part = kit.decor({
				Name = "Bubble",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * bubble.d * s,
				CFrame = base * CFrame.new(math.cos(yaw) * bubble.r * s, bubble.y * s, math.sin(yaw) * bubble.r * s),
				Color = if i == 2 then world("gumPinkLight") else world("gumPink"),
				Material = Enum.Material.Glass,
				Transparency = 0.25,
				Parent = parent,
			})
			part.Reflectance = 0.2
		end
	end,

	-- A tree of popcorn: a trunk under a heap of popped kernels, butter melting on top.
	popcornTree = function(base: CFrame, s: number, random: Random, spot: Spot, parent: Instance, kit: Kit)
		core(spot, kit)({
			Name = "Trunk",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(5.2 * s, 1.2 * s),
			CFrame = base * CFrame.new(0, 2.6 * s, 0) * UPRIGHT,
			Color = world("treeTrunk"),
			Material = Enum.Material.Wood,
			Parent = parent,
		})
		for _, puff in
			{
				{ at = Vector3.new(0, 7.6, 0), d = 4.6 },
				{ at = Vector3.new(2.1, 6.6, 0.6), d = 3.4 },
				{ at = Vector3.new(-1.9, 6.8, 1.1), d = 3.3 },
				{ at = Vector3.new(0.4, 6.4, -2.1), d = 3.2 },
				{ at = Vector3.new(-0.6, 9.8, -0.4), d = 3 },
			}
		do
			kit.decor({
				Name = "Popcorn",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * puff.d * s,
				CFrame = base * CFrame.new(puff.at * s) * tilt(random),
				Color = world("popcorn"),
				Parent = parent,
			})
		end
		kit.decor({
			Name = "Butter",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 1.7 * s,
			CFrame = base * CFrame.new(0.4 * s, 11 * s, -0.7 * s),
			Color = world("butter"),
			Parent = parent,
		})
	end,

	-- A tall corn stalk: two stalk sections, three long leaves arching out, and a cob in its husk.
	cornStalk = function(base: CFrame, s: number, random: Random, spot: Spot, parent: Instance, kit: Kit)
		core(spot, kit)({
			Name = "Stalk",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(5.4 * s, 0.8 * s),
			CFrame = base * CFrame.new(0, 2.7 * s, 0) * UPRIGHT,
			Color = world("cornStalk"),
			Parent = parent,
		})
		kit.decor({
			Name = "Stalk",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(6.4 * s, 0.6 * s),
			CFrame = base * CFrame.new(0, 8.3 * s, 0) * UPRIGHT,
			Color = world("cornStalk"),
			Parent = parent,
		})
		for i = 0, 2 do
			local yaw = i * 2.1 + random:NextNumber(-0.3, 0.3)
			kit.decor({
				Name = "Leaf",
				Size = Vector3.new(0.3, 5.5, 1.1) * s,
				CFrame = base
					* CFrame.Angles(0, yaw, 0)
					* CFrame.new(1.6 * s, (4.6 + i * 2.2) * s, 0)
					* CFrame.Angles(0, 0, math.rad(-50)),
				Color = world("cornLeaf"),
				Parent = parent,
			})
		end
		local cobAt = base
			* CFrame.Angles(0, random:NextNumber(0, math.pi * 2), 0)
			* CFrame.new(0.9 * s, 7.4 * s, 0)
			* CFrame.Angles(0, 0, math.rad(-20))
		local cob = kit.decor({
			Name = "Cob",
			Size = Vector3.new(1.1, 2.6, 1.1) * s,
			CFrame = cobAt,
			Color = world("cornCob"),
			Parent = parent,
		})
		sphereMesh(cob)
		local husk = kit.decor({
			Name = "Husk",
			Size = Vector3.new(1.3, 1.6, 1.3) * s,
			CFrame = cobAt * CFrame.new(0, -0.9 * s, 0),
			Color = world("cornLeaf"),
			Parent = parent,
		})
		sphereMesh(husk)
	end,

	-- A clipped topiary: two hedge balls on a stem, a ribbon round where they meet, and a rose on top.
	topiary = function(base: CFrame, s: number, _random: Random, spot: Spot, parent: Instance, kit: Kit)
		core(spot, kit)({
			Name = "Stem",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(5 * s, 0.7 * s),
			CFrame = base * CFrame.new(0, 2.5 * s, 0) * UPRIGHT,
			Color = world("treeTrunk"),
			Material = Enum.Material.Wood,
			Parent = parent,
		})
		kit.decor({
			Name = "Hedge",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 5.2 * s,
			CFrame = base * CFrame.new(0, 6.6 * s, 0),
			Color = world("hedge"),
			Material = Enum.Material.Grass,
			Parent = parent,
		})
		kit.decor({
			Name = "Hedge",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 3.6 * s,
			CFrame = base * CFrame.new(0, 10.3 * s, 0),
			Color = world("hedgeLight"),
			Material = Enum.Material.Grass,
			Parent = parent,
		})
		kit.decor({
			Name = "Ribbon",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(0.5 * s, 3.2 * s),
			CFrame = base * CFrame.new(0, 8.75 * s, 0) * UPRIGHT,
			Color = world("flower1"),
			Material = Enum.Material.Fabric,
			Parent = parent,
		})
		kit.decor({
			Name = "Rose",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 1.2 * s,
			CFrame = base * CFrame.new(0, 12.2 * s, 0),
			Color = world("flower2"),
			Parent = parent,
		})
	end,

	-- A cone topiary in a terracotta pot: three hedge tiers shrinking to a round tip.
	coneTopiary = function(base: CFrame, s: number, _random: Random, spot: Spot, parent: Instance, kit: Kit)
		core(spot, kit)({
			Name = "Pot",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(2.6 * s, 3 * s),
			CFrame = base * CFrame.new(0, 1.3 * s, 0) * UPRIGHT,
			Color = world("terracotta"),
			Material = Enum.Material.Sandstone,
			Parent = parent,
		})
		for i, tier in { { d = 4.4, h = 3, y = 4 }, { d = 3.4, h = 2.8, y = 6.7 }, { d = 2.2, h = 2.6, y = 9.2 } } do
			kit.decor({
				Name = "Hedge",
				Shape = Enum.PartType.Cylinder,
				Size = cylinderSize(tier.h * s, tier.d * s),
				CFrame = base * CFrame.new(0, tier.y * s, 0) * UPRIGHT,
				Color = if i % 2 == 1 then world("hedge") else world("hedgeLight"),
				Material = Enum.Material.Grass,
				Parent = parent,
			})
		end
		kit.decor({
			Name = "Hedge",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 1.5 * s,
			CFrame = base * CFrame.new(0, 11 * s, 0),
			Color = world("hedgeLight"),
			Material = Enum.Material.Grass,
			Parent = parent,
		})
	end,

	-- A blueberry bush: two leafy mounds dotted with fat blueberries.
	blueberryBush = function(base: CFrame, s: number, random: Random, _spot: Spot, parent: Instance, kit: Kit)
		local turn = CFrame.Angles(0, random:NextNumber(0, math.pi * 2), 0)
		kit.decor({
			Name = "Bush",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 5.2 * s,
			CFrame = base * turn * CFrame.new(0, 2.3 * s, 0),
			Color = world("berryBush"),
			Material = Enum.Material.Grass,
			Parent = parent,
		})
		kit.decor({
			Name = "Bush",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 3.6 * s,
			CFrame = base * turn * CFrame.new(2 * s, 1.6 * s, 0.4 * s),
			Color = world("berryBush"):Lerp(Color3.new(0, 0, 0), 0.12),
			Material = Enum.Material.Grass,
			Parent = parent,
		})
		for i = 0, 3 do
			local yaw = i * 1.6 + random:NextNumber(-0.2, 0.2)
			local up = 0.35 + (i % 2) * 0.35
			kit.decor({
				Name = "Blueberry",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * 1.2 * s,
				-- on the big mound's surface
				CFrame = base
					* turn
					* CFrame.new(0, 2.3 * s, 0)
					* CFrame.Angles(0, yaw, 0)
					* CFrame.Angles(up, 0, 0)
					* CFrame.new(0, 0, -2.55 * s),
				Color = world("blueberry"),
				Parent = parent,
			})
		end
	end,

	-- A giant fork stuck in the ground, tines up, leaning a little.
	giantFork = function(base: CFrame, s: number, random: Random, spot: Spot, parent: Instance, kit: Kit)
		local lean = base * CFrame.Angles(random:NextNumber(-0.12, 0.12), 0, random:NextNumber(-0.12, 0.12))
		local metal = world("fork")
		core(spot, kit)({
			Name = "Handle",
			Size = Vector3.new(1, 6, 0.5) * s,
			CFrame = lean * CFrame.new(0, 3 * s, 0),
			Color = metal,
			Material = Enum.Material.Metal,
			Parent = parent,
		})
		kit.decor({
			Name = "Neck",
			Size = Vector3.new(0.8, 2.4, 0.4) * s,
			CFrame = lean * CFrame.new(0, 7.1 * s, 0),
			Color = metal,
			Material = Enum.Material.Metal,
			Parent = parent,
		})
		kit.decor({
			Name = "Head",
			Size = Vector3.new(2.4, 1.4, 0.5) * s,
			CFrame = lean * CFrame.new(0, 8.9 * s, 0),
			Color = metal,
			Material = Enum.Material.Metal,
			Parent = parent,
		})
		for i = 0, 3 do
			kit.decor({
				Name = "Tine",
				Size = Vector3.new(0.36, 3.2, 0.4) * s,
				CFrame = lean * CFrame.new((-0.9 + i * 0.6) * s, 11.1 * s, 0),
				Color = metal,
				Material = Enum.Material.Metal,
				Parent = parent,
			})
		end
	end,

	-- A giant daisy: a stem and a leaf, three long petals crossed into a six-petalled head tipped to one side, and a
	-- domed golden middle. Every third one is pink.
	giantDaisy = function(base: CFrame, s: number, random: Random, spot: Spot, parent: Instance, kit: Kit)
		core(spot, kit)({
			Name = "Stem",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(9.4 * s, 0.8 * s),
			CFrame = base * CFrame.new(0, 4.7 * s, 0) * UPRIGHT,
			Color = world("flowerStem"),
			Parent = parent,
		})
		local leaf = kit.decor({
			Name = "Leaf",
			Size = Vector3.new(4, 0.4, 1.6) * s,
			CFrame = base * CFrame.new(1.8 * s, 3.2 * s, 0) * CFrame.Angles(0, 0, math.rad(28)),
			Color = world("flowerStem"),
			Parent = parent,
		})
		sphereMesh(leaf)
		local head = base * CFrame.new(0, 9.6 * s, 0) * CFrame.Angles(math.rad(random:NextNumber(14, 24)), 0, 0)
		local petalColor = if spot.seed % 3 == 0 then world("daisyPink") else world("daisy")
		for i = 0, 2 do
			local petal = kit.decor({
				Name = "Petals",
				Size = Vector3.new(7.8, 0.4, 1.9) * s,
				CFrame = head * CFrame.Angles(0, math.rad(i * 60 + 15), 0),
				Color = petalColor,
				Parent = parent,
			})
			sphereMesh(petal)
		end
		local middle = kit.decor({
			Name = "FlowerMiddle",
			Size = Vector3.new(2.9, 1.2, 2.9) * s,
			CFrame = head * CFrame.new(0, 0.3 * s, 0),
			Color = world("daisyCentre"),
			Material = Enum.Material.Sand,
			Parent = parent,
		})
		sphereMesh(middle)
	end,

	-- Honeycomb cells grown up like basalt columns: a tall one (its first block is the solid core) and a short one beside
	-- it with honey pooled on top, and a drip running down the tall one's far side.
	honeycombColumn = function(base: CFrame, s: number, random: Random, spot: Spot, parent: Instance, kit: Kit)
		local radius = 1.7 * s
		local tall = (6.6 + random:NextNumber(0, 0.8)) * s
		hexPrism(base, radius, tall, {
			Name = "Honeycomb",
			Color = world("honeycomb"),
			Parent = parent,
		}, core(spot, kit), kit)
		local turn = CFrame.Angles(0, math.rad(random:NextInteger(0, 5) * 60), 0)
		local side = base * turn * CFrame.new(0, 0, radius * HEX_FLAT)
		local short = (3.4 + random:NextNumber(0, 0.9)) * s
		hexPrism(side, radius, short, {
			Name = "Honeycomb",
			Color = world("honeycombDark"),
			Parent = parent,
		}, kit.decor, kit)
		local pool = kit.decor({
			Name = "Honey",
			Size = Vector3.new(2.6, 0.8, 2.6) * s,
			CFrame = side * CFrame.new(0, short, 0),
			Color = world("honey"),
			Parent = parent,
		})
		sphereMesh(pool)
		pool.Reflectance = 0.2
		local drip = kit.decor({
			Name = "Drip",
			Size = Vector3.new(0.9, 3, 0.6) * s,
			CFrame = base * turn * CFrame.new(0, tall - 1.3 * s, -(radius * HEX_FLAT / 2 + 0.1 * s)),
			Color = world("honey"),
			Parent = parent,
		})
		sphereMesh(drip)
		drip.Reflectance = 0.2
	end,

	-- A gingerbread cookie cut like a Christmas tree, standing on a gingerbread stump and turned to face the middle of
	-- the map: a biscuit triangle with a smaller, thicker triangle of green icing through it, so both faces show icing
	-- inside a biscuit rim, and a gumdrop on its tip.
	cookieTree = function(base: CFrame, s: number, _random: Random, spot: Spot, parent: Instance, kit: Kit)
		core(spot, kit)({
			Name = "Stump",
			Size = Vector3.new(1.6, 2.2, 1.2) * s,
			CFrame = base * CFrame.new(0, 1.1 * s, 0),
			Color = world("gingerbread"),
			Material = Enum.Material.Sand,
			Parent = parent,
		})
		local height, width = 10 * s, 8 * s
		local middle = facingCentre(base.Position) * CFrame.new(0, 2 * s + height / 2, 0)
		-- the icing is the same triangle shrunk around its incentre, so its rim is the same width on all three sides
		local slant = math.sqrt((width / 2) ^ 2 + height ^ 2)
		local inradius = (width * height / 2) / ((width + 2 * slant) / 2)
		local k = (inradius - 0.65 * s) / inradius
		for _, layer in
			{
				{ k = 1, lift = 0, thickness = 0.8, color = "gingerbread" },
				{ k = k, lift = (1 - k) * inradius - (1 - k) * height / 2, thickness = 1.3, color = "cookieIcing" },
			}
		do
			local h, w = height * layer.k, width * layer.k
			for _, turn in { 0, math.pi } do
				-- each half is a wedge across the cookie's face: its tall back on the middle line, sloping to the edge
				kit.wedge({
					Name = if layer.k == 1 then "Cookie" else "Icing",
					Size = Vector3.new(layer.thickness * s, h, w / 2),
					CFrame = middle
						* CFrame.new(0, layer.lift, 0)
						* CFrame.Angles(0, math.rad(90) + turn, 0)
						* CFrame.new(0, 0, -w / 4),
					Color = world(layer.color),
					Material = Enum.Material.Sand,
					Parent = parent,
				})
			end
		end
		kit.decor({
			Name = "Gumdrop",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 1.9 * s,
			CFrame = middle * CFrame.new(0, height / 2 + 0.2 * s, 0),
			Color = candy(spot.seed),
			Material = Enum.Material.Sand,
			Parent = parent,
		})
	end,

	-- A candy-cane lamp post: a white cane with two red bands, its hook bending over a glowing lantern (every third one
	-- inside the wall lights the ground).
	candyCaneLamp = function(base: CFrame, s: number, _random: Random, spot: Spot, parent: Instance, kit: Kit)
		local height, diameter = 7.4 * s, 0.6 * s
		core(spot, kit)({
			Name = "Cane",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(height, diameter),
			CFrame = base * CFrame.new(0, height / 2, 0) * UPRIGHT,
			Color = world("candyStick"),
			Parent = parent,
		})
		for _, y in { 2.4, 4.8 } do
			kit.decor({
				Name = "Stripe",
				Shape = Enum.PartType.Cylinder,
				Size = cylinderSize(0.9 * s, diameter + 0.1 * s),
				CFrame = base * CFrame.new(0, y * s, 0) * UPRIGHT,
				Color = world("candy1"),
				Parent = parent,
			})
		end
		local points = {
			Vector3.new(0, height - 0.2 * s, 0),
			Vector3.new(0.9 * s, height + 1 * s, 0),
			Vector3.new(1.9 * s, height + 0.3 * s, 0),
		}
		for i = 1, 2 do
			local a = (base * CFrame.new(points[i])).Position
			local b = (base * CFrame.new(points[i + 1])).Position
			kit.decor({
				Name = "Hook",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new((b - a).Magnitude + diameter * 0.5, diameter, diameter),
				CFrame = along(a, b),
				Color = if i == 1 then world("candy1") else world("candyStick"),
				Parent = parent,
			})
		end
		local lantern = kit.decor({
			Name = "Lantern",
			Size = Vector3.new(1, 1.3, 1) * s,
			CFrame = base * CFrame.new(1.9 * s, height - 0.7 * s, 0),
			Color = world("lampLight"),
			Material = Enum.Material.Neon,
			CastShadow = false,
			Parent = parent,
		})
		sphereMesh(lantern)
		if not spot.outside and spot.seed % 3 == 0 then
			light(lantern, world("lampLight"), 16, 1.2)
		end
	end,

	-- A Japanese maple: a slim dark trunk under a wide, lopsided canopy of three clumps of red and orange leaves.
	mapleTree = function(base: CFrame, s: number, random: Random, spot: Spot, parent: Instance, kit: Kit)
		core(spot, kit)({
			Name = "Trunk",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(6.8 * s, 0.9 * s),
			CFrame = base * CFrame.new(0, 3.4 * s, 0) * UPRIGHT,
			Color = world("mapleTrunk"),
			Material = Enum.Material.Wood,
			Parent = parent,
		})
		for _, clump in
			{
				{ size = Vector3.new(6, 3.6, 5.6), at = Vector3.new(-1.2, 7.4, 0.6), color = "mapleRed" },
				{ size = Vector3.new(5.6, 3.4, 5.2), at = Vector3.new(1.4, 8.6, -0.8), color = "mapleOrange" },
				{ size = Vector3.new(4.6, 3.2, 4.4), at = Vector3.new(-0.2, 10.6, 0.2), color = "mapleRed" },
			}
		do
			local leaves = kit.decor({
				Name = "Leaves",
				Size = clump.size * s,
				CFrame = base * CFrame.new(clump.at * s) * CFrame.Angles(0, random:NextNumber(0, math.pi), 0),
				Color = world(clump.color),
				Parent = parent,
			})
			sphereMesh(leaves)
		end
	end,

	-- A bunch of three giant spring onions, white at the root and green above, leaning a little apart (the first
	-- root is the solid core).
	springOnion = function(base: CFrame, s: number, random: Random, spot: Spot, parent: Instance, kit: Kit)
		for i = 0, 2 do
			local grow = random:NextNumber(0.85, 1.1)
			local stalk = base
				* CFrame.Angles(0, i * 2.1 + random:NextNumber(-0.25, 0.25), 0)
				* CFrame.new(0, 0, -0.6 * s)
				* CFrame.Angles(-math.rad(random:NextNumber(5, 9)), 0, 0)
			local make: (props: { [string]: any }) -> Part = if i == 0 then core(spot, kit) else kit.decor
			make({
				Name = "Root",
				Shape = Enum.PartType.Cylinder,
				Size = cylinderSize(3.6 * s, 1.15 * s),
				CFrame = stalk * CFrame.new(0, 1.8 * s, 0) * UPRIGHT,
				Color = world("onionWhite"),
				Parent = parent,
			})
			kit.decor({
				Name = "Stalk",
				Shape = Enum.PartType.Cylinder,
				Size = cylinderSize(8 * grow * s, 0.95 * s),
				CFrame = stalk * CFrame.new(0, (3.5 + 4 * grow) * s, 0) * UPRIGHT,
				Color = world("onionGreen"),
				Parent = parent,
			})
		end
	end,

	-- A chili pepper plant: a short woody stem under two leafy mounds, three red chilies hanging below the leaves.
	chiliPlant = function(base: CFrame, s: number, random: Random, spot: Spot, parent: Instance, kit: Kit)
		core(spot, kit)({
			Name = "Stem",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(4.6 * s, 0.8 * s),
			CFrame = base * CFrame.new(0, 2.3 * s, 0) * UPRIGHT,
			Color = world("treeTrunk"),
			Material = Enum.Material.Wood,
			Parent = parent,
		})
		for _, mound in
			{
				{ size = Vector3.new(6.4, 4.2, 6.4), at = Vector3.new(0, 6.2, 0), shade = 0 },
				{ size = Vector3.new(4.4, 3.2, 4.4), at = Vector3.new(0.6, 8.3, -0.4), shade = 0.12 },
			}
		do
			local leaves = kit.decor({
				Name = "Leaves",
				Size = mound.size * s,
				CFrame = base * CFrame.new(mound.at * s),
				Color = world("chiliLeaf"):Lerp(Color3.new(1, 1, 1), mound.shade),
				Material = Enum.Material.Grass,
				Parent = parent,
			})
			sphereMesh(leaves)
		end
		for i = 0, 2 do
			local chili = kit.decor({
				Name = "Chili",
				Size = Vector3.new(0.9, 3, 0.9) * s,
				CFrame = base
					* CFrame.Angles(0, i * 2.1 + random:NextNumber(-0.3, 0.3), 0)
					* CFrame.new(0, 4.6 * s, -2.9 * s)
					* CFrame.Angles(math.rad(14), 0, 0),
				Color = world("chiliRed"),
				Parent = parent,
			})
			sphereMesh(chili)
		end
	end,

	-- A giant kebab stuck in the ground: chunks of grilled meat, red pepper, onion and green pepper on a wooden skewer
	-- (the skewer is the solid core).
	kebab = function(base: CFrame, s: number, random: Random, spot: Spot, parent: Instance, kit: Kit)
		core(spot, kit)({
			Name = "Skewer",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(9 * s, 0.35 * s),
			CFrame = base * CFrame.new(0, 4.5 * s, 0) * UPRIGHT,
			Color = world("skewerWood"),
			Material = Enum.Material.Wood,
			Parent = parent,
		})
		for i, piece in
			{
				{ y = 2.4, size = Vector3.new(2.2, 1.9, 2.2), color = "meat" },
				{ y = 3.9, size = Vector3.new(2.4, 0.9, 2), color = "chiliRed" },
				{ y = 5.1, size = Vector3.new(1, 2.4, 2.4), color = "onion" },
				{ y = 6.3, size = Vector3.new(2.4, 0.9, 2), color = "pepperGreen" },
				{ y = 7.7, size = Vector3.new(2.1, 1.8, 2.1), color = "meat" },
			}
		do
			kit.decor({
				Name = "Kebab",
				Shape = if piece.color == "onion" then Enum.PartType.Cylinder else Enum.PartType.Block,
				Size = piece.size * s,
				CFrame = base
					* CFrame.new(0, piece.y * s, 0)
					* CFrame.Angles(0, math.rad(i * 37) + random:NextNumber(-0.2, 0.2), 0)
					* (if piece.color == "onion" then UPRIGHT else CFrame.identity),
				Color = world(piece.color),
				Material = if piece.color == "meat" then Enum.Material.Pebble else Enum.Material.SmoothPlastic,
				Parent = parent,
			})
		end
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
	-- A giant geode split open towards the map, glowing crystals inside.
	geode = function(base: CFrame, s: number, spot: LandmarkSpot, parent: Instance, kit: Kit)
		local frame = base * CFrame.Angles(0, math.rad(spot.index * 13 - 20), 0)
		local rock = kit.decor({
			Name = "Rock",
			Size = Vector3.new(30, 24, 26) * s,
			CFrame = frame * CFrame.new(0, 9 * s, 2 * s),
			Color = world("geodeRock"),
			Material = Enum.Material.Slate,
			Parent = parent,
		})
		sphereMesh(rock)
		local inside = kit.decor({
			Name = "Hollow",
			Size = Vector3.new(22, 17, 8) * s,
			CFrame = frame * CFrame.new(0, 10 * s, -9.6 * s),
			Color = world("geodeInner"),
			Material = Enum.Material.Glass,
			Parent = parent,
		})
		sphereMesh(inside)
		for i, shard in
			{
				{ at = Vector3.new(-5, 8, -12), size = Vector3.new(3, 8, 3), roll = -20 },
				{ at = Vector3.new(0, 12, -12.5), size = Vector3.new(3.4, 10, 3.4), roll = 5 },
				{ at = Vector3.new(5, 8.5, -12), size = Vector3.new(2.8, 7, 2.8), roll = 24 },
				{ at = Vector3.new(-2.5, 4.6, -12.4), size = Vector3.new(2.4, 5, 2.4), roll = -40 },
				{ at = Vector3.new(3, 14.6, -11.8), size = Vector3.new(2.2, 5, 2.2), roll = 150 },
			}
		do
			local crystal = kit.decor({
				Name = "Crystal",
				Size = shard.size * s,
				CFrame = frame
					* CFrame.new(shard.at * s)
					* CFrame.Angles(math.rad(-30), math.rad(45), math.rad(shard.roll)),
				Color = world(`rockCandy{i % 3 + 1}`),
				Material = Enum.Material.Neon,
				Transparency = 0.15,
				Parent = parent,
			})
			if i == 2 then
				light(crystal, world("geodeInner"), 30, 1.4)
			end
		end
	end,

	-- A lemonade stand under a striped awning, a giant jug on its counter.
	lemonadeStand = function(base: CFrame, size: number, spot: LandmarkSpot, parent: Instance, kit: Kit)
		local s = size * 1.5
		local frame = base * CFrame.Angles(0, math.rad(spot.index * 11 - 15), 0)
		kit.decor({
			Name = "Counter",
			Size = Vector3.new(16, 6, 7) * s,
			CFrame = frame * CFrame.new(0, 3 * s, 0),
			Color = world("standWood"),
			Material = Enum.Material.WoodPlanks,
			Parent = parent,
		})
		for _, side in { -1, 1 } do
			kit.decor({
				Name = "Post",
				Shape = Enum.PartType.Cylinder,
				Size = cylinderSize(8 * s, 0.7 * s),
				CFrame = frame * CFrame.new(side * 7.4 * s, 10 * s, 2.6 * s) * UPRIGHT,
				Color = world("awning2"),
				Parent = parent,
			})
		end
		for i = 0, 3 do
			kit.decor({
				Name = "Awning",
				Size = Vector3.new(4.2, 0.4, 9) * s,
				CFrame = frame
					* CFrame.new((-6.3 + i * 4.2) * s, 13.6 * s, -0.4 * s)
					* CFrame.Angles(math.rad(-18), 0, 0),
				Color = if i % 2 == 0 then world("awning1") else world("awning2"),
				Material = Enum.Material.Fabric,
				Parent = parent,
			})
		end
		kit.decor({
			Name = "Jug",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(4.4 * s, 3.4 * s),
			CFrame = frame * CFrame.new(-3.4 * s, 8.2 * s, 0) * UPRIGHT,
			Color = world("lemonade"),
			Material = Enum.Material.Glass,
			Transparency = 0.2,
			Parent = parent,
		})
		kit.decor({
			Name = "Lemon",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 2 * s,
			CFrame = frame * CFrame.new(2.6 * s, 7 * s, -0.6 * s),
			Color = world("lemon"),
			Parent = parent,
		})
	end,

	-- A giant lemon slice standing on its rind, leaning back.
	giantLemonSlice = function(base: CFrame, s: number, spot: LandmarkSpot, parent: Instance, kit: Kit)
		local frame = base
			* CFrame.new(0, 12 * s, 0)
			* CFrame.Angles(0, math.rad(spot.index * 23 - 40), 0)
			* CFrame.Angles(math.rad(-14), 0, 0)
		-- the slice's faces look along its front (-Z): a cylinder along Z
		local flat = CFrame.Angles(0, math.rad(90), 0)
		for _, layer in
			{
				{ name = "Rind", d = 30, h = 3, color = "lemonRind" },
				{ name = "Pith", d = 28, h = 3.3, color = "lemonPith" },
				{ name = "Flesh", d = 25.5, h = 3.6, color = "lemonFlesh" },
			}
		do
			kit.decor({
				Name = layer.name,
				Shape = Enum.PartType.Cylinder,
				Size = cylinderSize(layer.h * s, layer.d * s),
				CFrame = frame * flat,
				Color = world(layer.color),
				Parent = parent,
			})
		end
		for i = 0, 3 do
			kit.decor({
				Name = "Segment",
				Size = Vector3.new(0.6 * s, 25 * s, 3.8 * s),
				CFrame = frame * CFrame.Angles(0, 0, i * math.pi / 4),
				Color = world("lemonPith"),
				Parent = parent,
			})
		end
	end,

	-- A bayou shack on stilts, its window lit.
	stiltHouse = function(base: CFrame, s: number, spot: LandmarkSpot, parent: Instance, kit: Kit)
		local frame = base * CFrame.Angles(0, math.rad(spot.index * 17 - 25), 0)
		for _, corner in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
			kit.decor({
				Name = "Stilt",
				Shape = Enum.PartType.Cylinder,
				Size = cylinderSize(9 * s, 1.2 * s),
				CFrame = frame * CFrame.new(corner[1] * 9 * s, 4.5 * s, corner[2] * 7 * s) * UPRIGHT,
				Color = world("swampTrunk"),
				Material = Enum.Material.Wood,
				Parent = parent,
			})
		end
		kit.decor({
			Name = "Deck",
			Size = Vector3.new(22, 1, 18) * s,
			CFrame = frame * CFrame.new(0, 9.5 * s, 0),
			Color = world("shackWood"),
			Material = Enum.Material.WoodPlanks,
			Parent = parent,
		})
		kit.decor({
			Name = "Shack",
			Size = Vector3.new(15, 9, 11) * s,
			CFrame = frame * CFrame.new(0, 14.5 * s, 1.5 * s),
			Color = world("shackWood"),
			Material = Enum.Material.WoodPlanks,
			Parent = parent,
		})
		for _, side in { -1, 1 } do
			kit.wedge({
				Name = "Roof",
				Size = Vector3.new(17, 5, 6.5) * s,
				-- the tall face of each half meets the other at the ridge
				CFrame = frame
					* CFrame.new(0, 21.5 * s, (1.5 + side * 3.25) * s)
					* CFrame.Angles(0, if side == 1 then math.pi else 0, 0),
				Color = world("shackRoof"),
				Material = Enum.Material.WoodPlanks,
				Parent = parent,
			})
		end
		kit.decor({
			Name = "Door",
			Size = Vector3.new(3.4, 6, 0.6) * s,
			CFrame = frame * CFrame.new(-3.5 * s, 13 * s, -4.1 * s),
			Color = world("swampTrunk"),
			Parent = parent,
		})
		local window = kit.decor({
			Name = "Window",
			Size = Vector3.new(3.4, 3, 0.5) * s,
			CFrame = frame * CFrame.new(3.6 * s, 15 * s, -4.1 * s),
			Color = world("shackWindow"),
			Material = Enum.Material.Neon,
			CastShadow = false,
			Parent = parent,
		})
		light(window, world("shackWindow"), 18, 1.2)
	end,

	-- A huge bubblegum bubble floating above the swamp, with a shine.
	giantBubble = function(_base: CFrame, s: number, spot: LandmarkSpot, parent: Instance, kit: Kit)
		local diameter = (20 + (spot.index % 3) * 5) * s
		local centre = CFrame.new(spot.x, spot.y + (26 + (spot.index % 2) * 14) * s, spot.z)
		local bubble = kit.decor({
			Name = "Bubble",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * diameter,
			CFrame = centre,
			Color = world("gumPink"),
			Material = Enum.Material.Glass,
			Transparency = 0.3,
			CastShadow = false,
			Parent = parent,
		})
		bubble.Reflectance = 0.2
		kit.decor({
			Name = "Shine",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * diameter * 0.18,
			CFrame = centre * CFrame.new(-diameter * 0.22, diameter * 0.26, -diameter * 0.22),
			Color = Color3.new(1, 1, 1),
			Material = Enum.Material.Neon,
			Transparency = 0.2,
			CastShadow = false,
			Parent = parent,
		})
	end,

	-- A drive-in movie screen on two legs, a marquee on top, showing a sunny hill (it glows at night).
	cinemaScreen = function(base: CFrame, s: number, spot: LandmarkSpot, parent: Instance, kit: Kit)
		local frame = base * CFrame.Angles(0, math.rad(spot.index * 7 - 10), 0)
		for _, side in { -1, 1 } do
			kit.decor({
				Name = "Leg",
				Size = Vector3.new(2.4, 22, 2.4) * s,
				CFrame = frame * CFrame.new(side * 20 * s, 11 * s, 1.5 * s),
				Color = world("screenFrame"),
				Parent = parent,
			})
		end
		kit.decor({
			Name = "ScreenFrame",
			Size = Vector3.new(50, 28, 1.6) * s,
			CFrame = frame * CFrame.new(0, 34 * s, 0),
			Color = world("screenFrame"),
			Parent = parent,
		})
		local screen = kit.decor({
			Name = "Screen",
			Size = Vector3.new(46, 24, 0.6) * s,
			CFrame = frame * CFrame.new(0, 34 * s, -0.9 * s),
			Color = world("screen"),
			Material = Enum.Material.Neon,
			CastShadow = false,
			Parent = parent,
		})
		kit.decor({
			Name = "PictureHill",
			Size = Vector3.new(46, 6, 0.4) * s,
			CFrame = frame * CFrame.new(0, 25 * s, -1.25 * s),
			Color = world("cornLeaf"),
			Material = Enum.Material.Neon,
			CastShadow = false,
			Parent = parent,
		})
		kit.decor({
			Name = "PictureSun",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 6 * s,
			CFrame = frame * CFrame.new(13 * s, 39 * s, -1.4 * s),
			Color = world("butter"),
			Material = Enum.Material.Neon,
			CastShadow = false,
			Parent = parent,
		})
		kit.decor({
			Name = "Marquee",
			Size = Vector3.new(30, 4, 2) * s,
			CFrame = frame * CFrame.new(0, 50 * s, 0),
			Color = world("bucketRed"),
			Parent = parent,
		})
		light(screen, world("screen"), 50, 1)
	end,

	-- A giant striped popcorn bucket, popcorn heaped over its rim.
	popcornBucket = function(base: CFrame, s: number, spot: LandmarkSpot, parent: Instance, kit: Kit)
		local frame = base * CFrame.Angles(0, math.rad(spot.index * 29), 0)
		local h, d = 22 * s, 16 * s
		kit.decor({
			Name = "Bucket",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(h, d),
			CFrame = frame * CFrame.new(0, h / 2, 0) * UPRIGHT,
			Color = world("bucketWhite"),
			Parent = parent,
		})
		for i = 0, 3 do
			kit.decor({
				Name = "Stripe",
				Size = Vector3.new(3.6 * s, h - 0.4 * s, 0.8 * s),
				CFrame = frame
					* CFrame.Angles(0, i * math.pi / 2 + math.pi / 4, 0)
					* CFrame.new(0, h / 2, -(d / 2 - 0.2 * s)),
				Color = world("bucketRed"),
				Parent = parent,
			})
		end
		kit.decor({
			Name = "Rim",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(1.6 * s, d + 1.2 * s),
			CFrame = frame * CFrame.new(0, h, 0) * UPRIGHT,
			Color = world("bucketRed"),
			Parent = parent,
		})
		for i, puff in
			{
				{ at = Vector3.new(0, 3.5, 0), d = 10 },
				{ at = Vector3.new(4.6, 1.6, 1.2), d = 6.5 },
				{ at = Vector3.new(-4.4, 1.8, 1.8), d = 6.5 },
				{ at = Vector3.new(1.4, 1.5, -4.6), d = 6 },
				{ at = Vector3.new(-2.2, 1.4, 4.4), d = 6 },
				{ at = Vector3.new(-1.2, 7.4, -0.8), d = 5 },
			}
		do
			kit.decor({
				Name = "Popcorn",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * puff.d * s,
				CFrame = frame * CFrame.new(0, h, 0) * CFrame.new(puff.at * s),
				Color = if i == 6 then world("butter") else world("popcorn"),
				Parent = parent,
			})
		end
	end,

	-- A giant soda cup with a white band, a domed lid and a straw.
	sodaCup = function(base: CFrame, s: number, spot: LandmarkSpot, parent: Instance, kit: Kit)
		local frame = base * CFrame.Angles(0, math.rad(spot.index * 41), 0)
		local h, d = 24 * s, 13 * s
		kit.decor({
			Name = "Cup",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(h, d),
			CFrame = frame * CFrame.new(0, h / 2, 0) * UPRIGHT,
			Color = world("soda"),
			Parent = parent,
		})
		kit.decor({
			Name = "Band",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(5 * s, d + 0.4 * s),
			CFrame = frame * CFrame.new(0, h * 0.55, 0) * UPRIGHT,
			Color = world("bucketWhite"),
			Parent = parent,
		})
		kit.decor({
			Name = "Lid",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(1.4 * s, d + 1 * s),
			CFrame = frame * CFrame.new(0, h + 0.5 * s, 0) * UPRIGHT,
			Color = world("sodaLid"),
			Parent = parent,
		})
		kit.decor({
			Name = "LidDome",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(1.6 * s, d * 0.6),
			CFrame = frame * CFrame.new(0, h + 1.8 * s, 0) * UPRIGHT,
			Color = world("sodaLid"),
			Parent = parent,
		})
		local from = (frame * CFrame.new(0.8 * s, h + 1 * s, 0)).Position
		local to = (frame * CFrame.new(3.6 * s, h + 14 * s, 0.6 * s)).Position
		kit.decor({
			Name = "Straw",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new((to - from).Magnitude, 1.3 * s, 1.3 * s),
			CFrame = along(from, to),
			Color = world("straw"),
			Parent = parent,
		})
	end,

	-- A giant porcelain teapot, side-on to the map: a painted band, a lid and knob, a spout puffing steam and a
	-- handle.
	giantTeapot = function(base: CFrame, s: number, spot: LandmarkSpot, parent: Instance, kit: Kit)
		local frame = base * CFrame.Angles(0, math.rad(spot.index * 13 + 70), 0)
		local porcelain = world("porcelain")
		local pot = kit.decor({
			Name = "Pot",
			Size = Vector3.new(24, 18, 24) * s,
			CFrame = frame * CFrame.new(0, 9 * s, 0),
			Color = porcelain,
			Parent = parent,
		})
		sphereMesh(pot)
		kit.decor({
			Name = "Band",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(2.4 * s, 24.4 * s),
			CFrame = frame * CFrame.new(0, 9 * s, 0) * UPRIGHT,
			Color = world("porcelainBlue"),
			Parent = parent,
		})
		local lid = kit.decor({
			Name = "Lid",
			Size = Vector3.new(14, 5, 14) * s,
			CFrame = frame * CFrame.new(0, 17.3 * s, 0),
			Color = porcelain,
			Parent = parent,
		})
		sphereMesh(lid)
		kit.decor({
			Name = "Knob",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 3 * s,
			CFrame = frame * CFrame.new(0, 20.4 * s, 0),
			Color = world("gold"),
			Parent = parent,
		})
		local spout = {
			frame * CFrame.new(10 * s, 7 * s, 0),
			frame * CFrame.new(15.5 * s, 12 * s, 0),
			frame * CFrame.new(18.5 * s, 16.5 * s, 0),
		}
		for i = 1, 2 do
			local a, b = spout[i].Position, spout[i + 1].Position
			kit.decor({
				Name = "Spout",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new((b - a).Magnitude + 1 * s, (3.6 - i) * s, (3.6 - i) * s),
				CFrame = along(a, b),
				Color = porcelain,
				Parent = parent,
			})
		end
		for _, bar in
			{
				{ Vector3.new(-10, 14, 0), Vector3.new(-15.5, 13, 0) },
				{ Vector3.new(-15.5, 13.5, 0), Vector3.new(-15.5, 5, 0) },
				{ Vector3.new(-15.5, 5.5, 0), Vector3.new(-10.5, 4.2, 0) },
			}
		do
			local a, b = (frame * CFrame.new(bar[1] * s)).Position, (frame * CFrame.new(bar[2] * s)).Position
			kit.decor({
				Name = "Handle",
				Size = Vector3.new((b - a).Magnitude + 1.6 * s, 1.8 * s, 1.8 * s),
				CFrame = along(a, b),
				Color = porcelain,
				Parent = parent,
			})
		end
		local steam = Instance.new("Attachment")
		steam.Name = "Steam"
		steam.Parent = pot
		steam.WorldCFrame = CFrame.new(spout[3].Position + Vector3.new(0, 1 * s, 0))
		kit.emitter(steam, {
			Name = "Steam",
			Texture = SMOKE_TEXTURE,
			Color = ColorSequence.new(Color3.fromRGB(255, 255, 255)),
			Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 2),
				NumberSequenceKeypoint.new(1, 7),
			}),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.4),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Speed = NumberRange.new(4, 6),
			SpreadAngle = Vector2.new(12, 12),
			Acceleration = Vector3.new(0.5, 1, 0),
			Lifetime = NumberRange.new(2.5, 4),
			Rate = 3,
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-20, 20),
			EmissionDirection = Enum.NormalId.Top,
		})
	end,

	-- A giant teacup on its saucer, full of tea, with a painted band, a gold rim and a handle.
	teacup = function(base: CFrame, s: number, spot: LandmarkSpot, parent: Instance, kit: Kit)
		local frame = base * CFrame.Angles(0, math.rad(spot.index * 31 + 90), 0)
		local porcelain = world("porcelain")
		for _, disc in
			{
				{ name = "Saucer", h = 1.6, d = 30, y = 0.8, color = porcelain },
				{ name = "SaucerRim", h = 0.6, d = 30.6, y = 1.3, color = world("porcelainBlue") },
				{ name = "Cup", h = 13, d = 20, y = 8.1, color = porcelain },
				{ name = "CupBand", h = 2, d = 20.4, y = 11.5, color = world("porcelainBlue") },
				{ name = "Rim", h = 0.6, d = 20.6, y = 14.4, color = world("gold") },
				{ name = "Tea", h = 0.3, d = 19, y = 14.7, color = world("tea") },
			}
		do
			kit.decor({
				Name = disc.name,
				Shape = Enum.PartType.Cylinder,
				Size = cylinderSize(disc.h * s, disc.d * s),
				CFrame = frame * CFrame.new(0, disc.y * s, 0) * UPRIGHT,
				Color = disc.color,
				Parent = parent,
			})
		end
		for _, bar in
			{
				{ Vector3.new(9.5, 12, 0), Vector3.new(14, 10.5, 0) },
				{ Vector3.new(14, 11, 0), Vector3.new(10.5, 5, 0) },
			}
		do
			local a, b = (frame * CFrame.new(bar[1] * s)).Position, (frame * CFrame.new(bar[2] * s)).Position
			kit.decor({
				Name = "Handle",
				Size = Vector3.new((b - a).Magnitude + 1.4 * s, 1.6 * s, 1.6 * s),
				CFrame = along(a, b),
				Color = porcelain,
				Parent = parent,
			})
		end
	end,

	-- A three-tier cake stand: a gold pole through three porcelain plates, cakes and macarons on them.
	cakeStand = function(base: CFrame, s: number, spot: LandmarkSpot, parent: Instance, kit: Kit)
		local frame = base * CFrame.Angles(0, math.rad(spot.index * 19), 0)
		local gold = world("gold")
		kit.decor({
			Name = "Pole",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(30 * s, 1.6 * s),
			CFrame = frame * CFrame.new(0, 15 * s, 0) * UPRIGHT,
			Color = gold,
			Material = Enum.Material.Metal,
			Parent = parent,
		})
		for _, plate in { { d = 26, y = 4 }, { d = 19, y = 13 }, { d = 12, y = 22 } } do
			kit.decor({
				Name = "Plate",
				Shape = Enum.PartType.Cylinder,
				Size = cylinderSize(0.8 * s, plate.d * s),
				CFrame = frame * CFrame.new(0, plate.y * s, 0) * UPRIGHT,
				Color = world("porcelain"),
				Parent = parent,
			})
		end
		for _, cake in
			{
				{ at = Vector3.new(7, 6.2, 0), size = Vector3.new(3.6, 6, 6), color = "cake1" },
				{ at = Vector3.new(-7, 6.2, 0), size = Vector3.new(3.6, 6, 6), color = "cake2" },
			}
		do
			kit.decor({
				Name = "Cake",
				Shape = Enum.PartType.Cylinder,
				Size = cake.size * s,
				CFrame = frame * CFrame.new(cake.at * s) * UPRIGHT,
				Color = world(cake.color),
				Parent = parent,
			})
		end
		for _, macaron in { { x = 5, color = "cake2" }, { x = -5, color = "cake1" } } do
			local part = kit.decor({
				Name = "Macaron",
				Size = Vector3.new(4.4, 2.8, 4.4) * s,
				CFrame = frame * CFrame.new(macaron.x * s, 14.8 * s, 0),
				Color = world(macaron.color),
				Parent = parent,
			})
			sphereMesh(part)
		end
		kit.decor({
			Name = "Cake",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(4 * s, 7 * s),
			CFrame = frame * CFrame.new(0, 24.4 * s, 0) * UPRIGHT,
			Color = world("cake1"),
			Parent = parent,
		})
		kit.decor({
			Name = "Cherry",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 1.8 * s,
			CFrame = frame * CFrame.new(0, 27.2 * s, 0),
			Color = world("strawberry"),
			Parent = parent,
		})
		kit.decor({
			Name = "Finial",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 2.4 * s,
			CFrame = frame * CFrame.new(0, 30.4 * s, 0),
			Color = gold,
			Material = Enum.Material.Metal,
			Parent = parent,
		})
	end,

	-- A tumble of giant sugar cubes.
	sugarCubes = function(base: CFrame, s: number, spot: LandmarkSpot, parent: Instance, kit: Kit)
		local frame = base * CFrame.Angles(0, math.rad(spot.index * 23), 0)
		for _, cube in
			{
				{ at = Vector3.new(-5, 4.5, 0), turn = 8 },
				{ at = Vector3.new(5, 4.5, 1), turn = -14 },
				{ at = Vector3.new(0.5, 4.5, 9), turn = 26 },
				{ at = Vector3.new(0, 13.4, 1.5), turn = 21 },
				{ at = Vector3.new(9.5, 3.4, -8), turn = 40, tip = true },
			}
		do
			kit.decor({
				Name = "SugarCube",
				Size = Vector3.one * 9 * s,
				CFrame = frame
					* CFrame.new(cube.at * s)
					* CFrame.Angles(if cube.tip then math.rad(25) else 0, math.rad(cube.turn), 0),
				Color = world("sugar"),
				Material = Enum.Material.Sand,
				Parent = parent,
			})
		end
	end,

	-- A towering stack of pancakes, butter melting on top and syrup running down the sides.
	pancakeStack = function(base: CFrame, s: number, spot: LandmarkSpot, parent: Instance, kit: Kit)
		local frame = base * CFrame.Angles(0, math.rad(spot.index * 37), 0)
		local top = 0
		for i = 0, 5 do
			local d = (30 - i * 0.7) * s
			local wobble = Vector3.new(math.sin(i * 1.9) * 0.8, 0, math.cos(i * 2.3) * 0.8) * s
			top = (1.8 + i * 3.5) * s
			kit.decor({
				Name = "Pancake",
				Shape = Enum.PartType.Cylinder,
				Size = cylinderSize(3.6 * s, d),
				CFrame = frame * CFrame.new(wobble + Vector3.new(0, top, 0)) * UPRIGHT,
				Color = if i % 2 == 0 then world("pancake") else world("pancakeEdge"),
				Parent = parent,
			})
		end
		local syrupTop = top + 1.9 * s
		local syrup = world("syrup")
		local pool = kit.decor({
			Name = "Syrup",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(0.6 * s, 26 * s),
			CFrame = frame * CFrame.new(0, syrupTop, 0) * UPRIGHT,
			Color = syrup,
			Parent = parent,
		})
		pool.Reflectance = 0.2
		kit.decor({
			Name = "Butter",
			Size = Vector3.new(9, 4, 9) * s,
			CFrame = frame * CFrame.new(0, syrupTop + 2 * s, 0) * CFrame.Angles(0, math.rad(20), 0),
			Color = world("butter"),
			Parent = parent,
		})
		-- runs of syrup down the side, from the pool on top
		for i = 0, 2 do
			local yaw = i * 2.2 + 0.4
			local length = (7 + i * 2.5) * s
			local drip = kit.decor({
				Name = "Drip",
				Size = Vector3.new(3.2 * s, length, 1.4 * s),
				CFrame = frame * CFrame.Angles(0, yaw, 0) * CFrame.new(0, syrupTop - length / 2 + 0.4 * s, -13.3 * s),
				Color = syrup,
				Parent = parent,
			})
			sphereMesh(drip)
			drip.Reflectance = 0.2
		end
	end,

	-- A giant syrup bottle: an amber glass body with a label, a shoulder, a neck and a red cap.
	syrupBottle = function(base: CFrame, s: number, spot: LandmarkSpot, parent: Instance, kit: Kit)
		local frame = base * CFrame.Angles(0, math.rad(spot.index * 43), 0)
		local syrup = world("syrup")
		for _, piece in
			{
				{ name = "Bottle", h = 20, d = 12, y = 10, color = syrup, glass = true },
				{ name = "Label", h = 8, d = 12.4, y = 9, color = world("cream"), glass = false },
				{ name = "Neck", h = 5, d = 5, y = 26, color = syrup, glass = true },
				{ name = "Cap", h = 3, d = 6, y = 29.5, color = world("bucketRed"), glass = false },
			}
		do
			kit.decor({
				Name = piece.name,
				Shape = Enum.PartType.Cylinder,
				Size = cylinderSize(piece.h * s, piece.d * s),
				CFrame = frame * CFrame.new(0, piece.y * s, 0) * UPRIGHT,
				Color = piece.color,
				Material = if piece.glass then Enum.Material.Glass else Enum.Material.SmoothPlastic,
				Transparency = if piece.glass then 0.15 else 0,
				Parent = parent,
			})
		end
		kit.decor({
			Name = "Shoulder",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 12 * s,
			CFrame = frame * CFrame.new(0, 20 * s, 0),
			Color = syrup,
			Material = Enum.Material.Glass,
			Transparency = 0.15,
			Parent = parent,
		})
	end,

	-- A stack of square waffles, each turned a little, topped with whipped cream and a strawberry.
	waffleTower = function(base: CFrame, s: number, spot: LandmarkSpot, parent: Instance, kit: Kit)
		local frame = base * CFrame.Angles(0, math.rad(spot.index * 17), 0)
		for i, waffle in { { w = 18, y = 1.6 }, { w = 16, y = 4.8 }, { w = 14, y = 8 } } do
			kit.decor({
				Name = "Waffle",
				Size = Vector3.new(waffle.w, 3.2, waffle.w) * s,
				CFrame = frame * CFrame.new(0, waffle.y * s, 0) * CFrame.Angles(0, math.rad(i * 15), 0),
				Color = world("waffle"),
				Material = Enum.Material.DiamondPlate,
				Parent = parent,
			})
		end
		local cream = kit.decor({
			Name = "Cream",
			Size = Vector3.new(9, 5, 9) * s,
			CFrame = frame * CFrame.new(0, 11.4 * s, 0),
			Color = world("cream"),
			Parent = parent,
		})
		sphereMesh(cream)
		local berry = kit.decor({
			Name = "Strawberry",
			Size = Vector3.new(4, 5, 4) * s,
			CFrame = frame * CFrame.new(0.4 * s, 15.2 * s, 0) * CFrame.Angles(0, 0, math.rad(12)),
			Color = world("strawberry"),
			Parent = parent,
		})
		sphereMesh(berry)
	end,

	-- A giant slab of honeycomb standing on its edge with its cells facing the map: seven hexagonal cells in a flower,
	-- wax and honey-filled ones at different depths, honey dripping from the two lowest.
	honeycombSlab = function(base: CFrame, s: number, spot: LandmarkSpot, parent: Instance, kit: Kit)
		local frame = base * CFrame.Angles(0, math.rad((spot.index % 3 - 1) * 12), 0)
		local radius = 6 * s
		local step = radius * HEX_FLAT
		local middle = frame * CFrame.new(0, step * 1.5, 0)
		-- the middle cell (no angle), then the six round it
		local cells: { { angle: number?, length: number, color: string } } = {
			{ angle = nil, length = 9, color = "honey" },
			{ angle = 30, length = 12, color = "honeycomb" },
			{ angle = 90, length = 10, color = "honeycombDark" },
			{ angle = 150, length = 12, color = "honeycomb" },
			{ angle = 210, length = 8, color = "honey" },
			{ angle = 270, length = 11, color = "honeycombDark" },
			{ angle = 330, length = 8, color = "honey" },
		}
		for i, cell in cells do
			local offset = if cell.angle
				then Vector3.new(math.cos(math.rad(cell.angle)) * step, math.sin(math.rad(cell.angle)) * step, 0)
				else Vector3.zero
			-- each cell is a prism lying along the frame's Z axis: its back flush with the slab's back, its front
			-- (a hexagon facing the map) as far forward as its length
			local back = middle * CFrame.new(offset + Vector3.new(0, 0, 6 * s)) * CFrame.Angles(-math.rad(90), 0, 0)
			hexPrism(back, radius, cell.length * s, {
				Name = if cell.color == "honey" then "Honey" else "Honeycomb",
				Color = world(cell.color),
				Reflectance = if cell.color == "honey" then 0.2 else 0,
				Parent = parent,
			}, kit.decor, kit)
			if i == 5 or i == 7 then
				-- honey running out of the lowest two honey cells and down their fronts
				local drip = kit.decor({
					Name = "Drip",
					Size = Vector3.new(2.6, 7, 1.2) * s,
					CFrame = middle * CFrame.new(
						offset + Vector3.new(1 * s, -step / 2 + 2.4 * s, 6 * s - cell.length * s - 0.3 * s)
					),
					Color = world("honey"),
					Parent = parent,
				})
				sphereMesh(drip)
				drip.Reflectance = 0.2
			end
		end
	end,

	-- A giant bumblebee hovering over the hills and looking at the map: a striped body, a black head with big eyes, two
	-- glassy wings, antennae and a little stinger.
	giantBee = function(base: CFrame, s: number, spot: LandmarkSpot, parent: Instance, kit: Kit)
		local altitude = (34 + (spot.index % 3) * 9) * s
		local body = base * CFrame.new(0, altitude, 0) * CFrame.Angles(math.rad(6), 0, 0)
		local yellow, black = world("beeYellow"), world("beeBlack")
		local bodyPart = kit.decor({
			Name = "BeeBody",
			Size = Vector3.new(10, 10, 15) * s,
			CFrame = body,
			Color = yellow,
			Parent = parent,
		})
		sphereMesh(bodyPart)
		-- two black bands round the body (cylinders along it, a little wider than the body where they sit)
		for _, band in { { z = 0.8, length = 2.2 }, { z = 4.2, length = 1.6 } } do
			local r = 5 * math.sqrt(1 - (band.z / 7.5) ^ 2)
			kit.decor({
				Name = "BeeStripe",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(band.length, 2 * r + 0.3, 2 * r + 0.3) * s,
				CFrame = body * CFrame.new(0, 0, band.z * s) * CFrame.Angles(0, math.rad(90), 0),
				Color = black,
				Parent = parent,
			})
		end
		local head = body * CFrame.new(0, 0.6 * s, -9 * s)
		kit.decor({
			Name = "BeeHead",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 7 * s,
			CFrame = head,
			Color = black,
			Parent = parent,
		})
		for _, side in { -1, 1 } do
			kit.decor({
				Name = "BeeEye",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * 3 * s,
				CFrame = head * CFrame.new(side * 1.6 * s, 0.8 * s, -2.5 * s),
				Color = world("daisy"),
				Parent = parent,
			})
			kit.decor({
				Name = "BeePupil",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * 1.5 * s,
				CFrame = head * CFrame.new(side * 1.7 * s, 0.8 * s, -3.8 * s),
				Color = black,
				Parent = parent,
			})
			local wing = kit.decor({
				Name = "BeeWing",
				Size = Vector3.new(8, 0.5, 5.5) * s,
				CFrame = body * CFrame.new(side * 5 * s, 4.6 * s, 1 * s) * CFrame.Angles(0, 0, math.rad(side * 24)),
				Color = world("beeWing"),
				Transparency = 0.3,
				CastShadow = false,
				Parent = parent,
			})
			sphereMesh(wing)
			local a = (head * CFrame.new(side * 1.2 * s, 3 * s, -0.8 * s)).Position
			local b = (head * CFrame.new(side * 2.4 * s, 6.6 * s, -2.6 * s)).Position
			kit.decor({
				Name = "BeeAntenna",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new((b - a).Magnitude, 0.5 * s, 0.5 * s),
				CFrame = along(a, b),
				Color = black,
				Parent = parent,
			})
		end
		local stinger = kit.decor({
			Name = "BeeStinger",
			Size = Vector3.new(1.4, 1.4, 3.2) * s,
			CFrame = body * CFrame.new(0, -0.4 * s, 8.2 * s),
			Color = black,
			Parent = parent,
		})
		sphereMesh(stinger)
	end,

	-- A giant straw beehive (a skep): four woven rings stacked into a dome on a wooden stand, a dark doorway at the
	-- bottom facing the map, honey running out of it.
	beeSkep = function(base: CFrame, s: number, _spot: LandmarkSpot, parent: Instance, kit: Kit)
		kit.decor({
			Name = "SkepStand",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(2 * s, 28 * s),
			CFrame = base * CFrame.new(0, 1 * s, 0) * UPRIGHT,
			Color = world("treeTrunk"),
			Material = Enum.Material.WoodPlanks,
			Parent = parent,
		})
		for i, ring in { { d = 24, y = 4.2 }, { d = 22, y = 8.4 }, { d = 18.5, y = 12.4 }, { d = 13.5, y = 16 } } do
			kit.decor({
				Name = "Skep",
				Shape = Enum.PartType.Cylinder,
				Size = cylinderSize(4.6 * s, ring.d * s),
				CFrame = base * CFrame.new(0, ring.y * s, 0) * UPRIGHT,
				Color = if i % 2 == 1 then world("skep") else world("skepDark"),
				Material = Enum.Material.Fabric,
				Parent = parent,
			})
		end
		kit.decor({
			Name = "Skep",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 10 * s,
			CFrame = base * CFrame.new(0, 18.4 * s, 0),
			Color = world("skep"),
			Material = Enum.Material.Fabric,
			Parent = parent,
		})
		local door = kit.decor({
			Name = "SkepDoor",
			Size = Vector3.new(6, 7, 2.4) * s,
			CFrame = base * CFrame.new(0, 2.6 * s, -11.4 * s),
			Color = world("beeBlack"),
			Parent = parent,
		})
		sphereMesh(door)
		local honey = kit.decor({
			Name = "Honey",
			Size = Vector3.new(4.4, 1.2, 5) * s,
			CFrame = base * CFrame.new(0, 2.2 * s, -13.2 * s),
			Color = world("honey"),
			Parent = parent,
		})
		sphereMesh(honey)
		honey.Reflectance = 0.2
	end,

	-- A giant clay honey pot tied with twine, honey overflowing its neck and running down, a wooden dipper leaning in it.
	honeyPot = function(base: CFrame, s: number, spot: LandmarkSpot, parent: Instance, kit: Kit)
		local frame = base * CFrame.Angles(0, math.rad(spot.index * 29), 0)
		local pot = kit.decor({
			Name = "Pot",
			Size = Vector3.new(22, 18, 22) * s,
			CFrame = frame * CFrame.new(0, 9 * s, 0),
			Color = world("honeyPot"),
			Parent = parent,
		})
		sphereMesh(pot)
		kit.decor({
			Name = "Twine",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(2 * s, 22.3 * s),
			CFrame = frame * CFrame.new(0, 9 * s, 0) * UPRIGHT,
			Color = world("skepDark"),
			Material = Enum.Material.Fabric,
			Parent = parent,
		})
		kit.decor({
			Name = "Neck",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(3.4 * s, 13 * s),
			CFrame = frame * CFrame.new(0, 18 * s, 0) * UPRIGHT,
			Color = world("honeyPot"),
			Parent = parent,
		})
		local honey = kit.decor({
			Name = "Honey",
			Size = Vector3.new(13.6, 4, 13.6) * s,
			CFrame = frame * CFrame.new(0, 19.8 * s, 0),
			Color = world("honey"),
			Parent = parent,
		})
		sphereMesh(honey)
		honey.Reflectance = 0.2
		for _, drip in { { yaw = 0, length = 7 }, { yaw = 50, length = 5 } } do
			local part = kit.decor({
				Name = "Drip",
				Size = Vector3.new(2.6, drip.length, 1.6) * s,
				CFrame = frame
					* CFrame.Angles(0, math.rad(drip.yaw), 0)
					* CFrame.new(0, (19 - drip.length / 2) * s, -6.8 * s),
				Color = world("honey"),
				Parent = parent,
			})
			sphereMesh(part)
			part.Reflectance = 0.2
		end
		local a = (frame * CFrame.new(2 * s, 18 * s, 1 * s)).Position
		local b = (frame * CFrame.new(8 * s, 31 * s, 4 * s)).Position
		kit.decor({
			Name = "Dipper",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new((b - a).Magnitude, 1.3 * s, 1.3 * s),
			CFrame = along(a, b),
			Color = world("treeTrunk"),
			Material = Enum.Material.Wood,
			Parent = parent,
		})
		kit.decor({
			Name = "DipperKnob",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 2.2 * s,
			CFrame = CFrame.new(b),
			Color = world("treeTrunk"),
			Material = Enum.Material.Wood,
			Parent = parent,
		})
	end,

	-- A gingerbread cottage: biscuit walls, a gable roof with icing along both eaves and gumdrops on the ridge, a candy
	-- door, two windows glowing warm and a chimney puffing smoke. Its door faces the map.
	gingerbreadHouse = function(base: CFrame, s: number, spot: LandmarkSpot, parent: Instance, kit: Kit)
		local frame = base * CFrame.Angles(0, math.rad((spot.index % 3 - 1) * 16), 0)
		local biscuit = world("gingerbread")
		kit.decor({
			Name = "Walls",
			Size = Vector3.new(22, 14, 16) * s,
			CFrame = frame * CFrame.new(0, 7 * s, 0),
			Color = biscuit,
			Material = Enum.Material.Sand,
			Parent = parent,
		})
		for _, turn in { 0, math.pi } do
			-- each slope is a wedge: its tall back face on the ridge, sloping down to the eave
			local slope = frame * CFrame.new(0, 18 * s, 0) * CFrame.Angles(0, turn, 0)
			kit.wedge({
				Name = "Roof",
				Size = Vector3.new(24, 8, 9.6) * s,
				CFrame = slope * CFrame.new(0, 0, -4.8 * s),
				Color = world("gingerbreadDark"),
				Material = Enum.Material.Sand,
				Parent = parent,
			})
			local icing = kit.decor({
				Name = "Icing",
				Size = Vector3.new(24.6, 1.6, 1.8) * s,
				CFrame = slope * CFrame.new(0, -3.8 * s, -9.4 * s),
				Color = world("icing"),
				Parent = parent,
			})
			sphereMesh(icing)
		end
		for i = 0, 2 do
			kit.decor({
				Name = "Gumdrop",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * 3.6 * s,
				CFrame = frame * CFrame.new((i - 1) * 7.5 * s, 22.2 * s, 0),
				Color = candy(spot.index + i),
				Material = Enum.Material.Sand,
				Parent = parent,
			})
		end
		kit.decor({
			Name = "Door",
			Size = Vector3.new(4.6, 7.4, 0.6) * s,
			CFrame = frame * CFrame.new(0, 3.7 * s, -8.1 * s),
			Color = candy(spot.index + 3),
			Parent = parent,
		})
		for _, side in { -1, 1 } do
			kit.decor({
				Name = "WindowIcing",
				Size = Vector3.new(5, 5, 0.3) * s,
				CFrame = frame * CFrame.new(side * 6.6 * s, 8.2 * s, -8.05 * s),
				Color = world("icing"),
				Parent = parent,
			})
			local window = kit.decor({
				Name = "Window",
				Size = Vector3.new(3.8, 3.8, 0.4) * s,
				CFrame = frame * CFrame.new(side * 6.6 * s, 8.2 * s, -8.15 * s),
				Color = world("cottageWindow"),
				Material = Enum.Material.Neon,
				CastShadow = false,
				Parent = parent,
			})
			if side == 1 then
				light(window, world("cottageWindow"), 22, 1.4)
			end
		end
		local chimney = kit.decor({
			Name = "Chimney",
			Size = Vector3.new(2.8, 7, 2.8) * s,
			CFrame = frame * CFrame.new(6.5 * s, 20.5 * s, 3.4 * s),
			Color = world("gingerbreadDark"),
			Material = Enum.Material.Sand,
			Parent = parent,
		})
		plume(chimney, (frame * CFrame.new(6.5 * s, 24.6 * s, 3.4 * s)).Position, world("icing"), 6 * s, 2, kit)
	end,

	-- A giant gingerbread man waving at the map: a biscuit head, body, arms and legs, icing eyes, smile and cuffs, and
	-- three gumdrop buttons.
	gingerbreadMan = function(base: CFrame, s: number, spot: LandmarkSpot, parent: Instance, kit: Kit)
		local frame = base * CFrame.Angles(0, math.rad((spot.index % 2) * 14 - 7), 0)
		local biscuit = world("gingerbread")
		local depth = 3.2
		local function piece(name: string, size: Vector3, at: CFrame, color: Color3, material: Enum.Material?)
			local part = kit.decor({
				Name = name,
				Size = size * s,
				CFrame = frame * at,
				Color = color,
				Material = material or Enum.Material.SmoothPlastic,
				Parent = parent,
			})
			sphereMesh(part)
		end
		piece("Head", Vector3.new(10, 10, depth), CFrame.new(0, 31 * s, 0), biscuit, Enum.Material.Sand)
		piece("Body", Vector3.new(13, 15.5, depth), CFrame.new(0, 19.5 * s, 0), biscuit, Enum.Material.Sand)
		for _, side in { -1, 1 } do
			piece(
				"Leg",
				Vector3.new(5.6, 13, depth),
				CFrame.new(side * 3.6 * s, 7.4 * s, 0) * CFrame.Angles(0, 0, math.rad(side * 14)),
				biscuit,
				Enum.Material.Sand
			)
			-- the right arm waves, the left one hangs
			local angle = if side == 1 then 38 else -22
			local arm = CFrame.new(side * 9 * s, (23 + side * 1.5) * s, 0) * CFrame.Angles(0, 0, math.rad(angle))
			piece("Arm", Vector3.new(12, 4.8, depth), arm, biscuit, Enum.Material.Sand)
			piece("Cuff", Vector3.new(0.8, 4.6, depth + 0.4), arm * CFrame.new(side * 3.6 * s, 0, 0), world("icing"))
			piece("Eye", Vector3.new(1.7, 1.9, 1), CFrame.new(side * 2.1 * s, 32.2 * s, -1.6 * s), world("icing"))
		end
		piece("Smile", Vector3.new(4.6, 1, 1), CFrame.new(0, 28.6 * s, -1.6 * s), world("icing"))
		for i = 0, 2 do
			kit.decor({
				Name = "Button",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * 2.2 * s,
				CFrame = frame * CFrame.new(0, (23.4 - i * 3.6) * s, -1.6 * s),
				Color = candy(spot.index + i),
				Material = Enum.Material.Sand,
				Parent = parent,
			})
		end
	end,

	-- A round gingerbread cottage under a giant sugared gumdrop for a roof: biscuit walls, a ring of white icing where the
	-- roof sits with three drips running off it, a candy door, two warm windows and a chimney puffing smoke.
	gumdropCottage = function(base: CFrame, s: number, spot: LandmarkSpot, parent: Instance, kit: Kit)
		local frame = base * CFrame.Angles(0, math.rad((spot.index % 3 - 1) * 20), 0)
		-- the walls are exactly as wide as the gumdrop, so its lower half stays hidden inside them
		kit.decor({
			Name = "Walls",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(13 * s, 22 * s),
			CFrame = frame * CFrame.new(0, 6.5 * s, 0) * UPRIGHT,
			Color = world("gingerbread"),
			Material = Enum.Material.Sand,
			Parent = parent,
		})
		local roof = kit.decor({
			Name = "GumdropRoof",
			Size = Vector3.new(22, 22, 22) * s,
			CFrame = frame * CFrame.new(0, 13 * s, 0),
			Color = candy(spot.index + 1),
			Material = Enum.Material.Sand,
			Parent = parent,
		})
		sphereMesh(roof)
		kit.decor({
			Name = "Icing",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(1.8 * s, 22.8 * s),
			CFrame = frame * CFrame.new(0, 13.2 * s, 0) * UPRIGHT,
			Color = world("icing"),
			Parent = parent,
		})
		for _, angle in { -38, 0, 38 } do
			local drip = kit.decor({
				Name = "Icing",
				Size = Vector3.new(1.8, 3.6, 1.2) * s,
				CFrame = frame * CFrame.Angles(0, math.rad(angle), 0) * CFrame.new(0, 11.7 * s, -11.2 * s),
				Color = world("icing"),
				Parent = parent,
			})
			sphereMesh(drip)
		end
		kit.decor({
			Name = "Door",
			Size = Vector3.new(4.4, 7.2, 1.2) * s,
			CFrame = frame * CFrame.new(0, 3.6 * s, -10.8 * s),
			Color = candy(spot.index + 2),
			Parent = parent,
		})
		for _, side in { -1, 1 } do
			local window = kit.decor({
				Name = "Window",
				Size = Vector3.new(3.2, 3.2, 0.8) * s,
				CFrame = frame * CFrame.Angles(0, math.rad(side * 42), 0) * CFrame.new(0, 7.6 * s, -10.9 * s),
				Color = world("cottageWindow"),
				Material = Enum.Material.Neon,
				CastShadow = false,
				Parent = parent,
			})
			if side == 1 then
				light(window, world("cottageWindow"), 22, 1.4)
			end
		end
		local chimney = kit.decor({
			Name = "Chimney",
			Size = Vector3.new(2.6, 6, 2.6) * s,
			CFrame = frame * CFrame.new(5 * s, 22 * s, 3 * s),
			Color = world("gingerbreadDark"),
			Material = Enum.Material.Sand,
			Parent = parent,
		})
		plume(chimney, (frame * CFrame.new(5 * s, 25.4 * s, 3 * s)).Position, world("icing"), 6 * s, 2, kit)
	end,

	-- A heap of giant sugared gumdrops in candy colours.
	gumdrops = function(base: CFrame, s: number, spot: LandmarkSpot, parent: Instance, kit: Kit)
		local frame = base * CFrame.Angles(0, math.rad(spot.index * 31), 0)
		for i, drop in
			{
				{ at = Vector3.new(0, 5, 0), d = 16, h = 15 },
				{ at = Vector3.new(11, 3.2, 4), d = 12, h = 10 },
				{ at = Vector3.new(-10.5, 2.8, 5), d = 11, h = 9 },
				{ at = Vector3.new(3, 2.8, -10.5), d = 11, h = 9 },
				{ at = Vector3.new(-2.5, 13.5, 1.5), d = 9, h = 8 },
			}
		do
			local gumdrop = kit.decor({
				Name = "Gumdrop",
				Size = Vector3.new(drop.d, drop.h, drop.d) * s,
				CFrame = frame * CFrame.new(drop.at * s),
				Color = candy(spot.index + i),
				Material = Enum.Material.Sand,
				Parent = parent,
			})
			sphereMesh(gumdrop)
		end
	end,

	-- A giant bowl of ramen, steaming: a red bowl with a white band, golden broth, noodles lifted on a pair of
	-- chopsticks and a nest of them in the broth, half an egg, naruto, chashu and a sheet of nori.
	ramenBowl = function(base: CFrame, s: number, spot: LandmarkSpot, parent: Instance, kit: Kit)
		local frame = base * CFrame.Angles(0, math.rad(spot.index * 17), 0)
		local top = 16 -- the broth's surface
		for _, disc in
			{
				{ name = "BowlFoot", h = 2.4, d = 14, y = 1.2, color = "ramenBowl" },
				{ name = "Bowl", h = 8, d = 32, y = 12, color = "ramenBowl" },
				{ name = "BowlBand", h = 2.2, d = 32.4, y = 13, color = "bowlBand" },
				{ name = "Broth", h = 0.4, d = 30.8, y = top - 0.3, color = "broth" },
			}
		do
			local part = kit.decor({
				Name = disc.name,
				Shape = Enum.PartType.Cylinder,
				Size = cylinderSize(disc.h * s, disc.d * s),
				CFrame = frame * CFrame.new(0, disc.y * s, 0) * UPRIGHT,
				Color = world(disc.color),
				Parent = parent,
			})
			if disc.name == "Broth" then
				part.Reflectance = 0.15
				plume(part, (frame * CFrame.new(0, (top + 1) * s, 0)).Position, world("eggWhite"), 12 * s, 3, kit)
			end
		end
		-- the bowl's rounded bottom: an ellipsoid whose upper half hides inside the straight wall above it
		local bottom = kit.decor({
			Name = "Bowl",
			Size = Vector3.new(31.6, 14, 31.6) * s,
			CFrame = frame * CFrame.new(0, 8.4 * s, 0),
			Color = world("ramenBowl"),
			Parent = parent,
		})
		sphereMesh(bottom)
		local nest = kit.decor({
			Name = "Noodles",
			Size = Vector3.new(14, 2.4, 10) * s,
			CFrame = frame * CFrame.new(-3 * s, (top + 0.3) * s, 2 * s) * CFrame.Angles(0, math.rad(20), 0),
			Color = world("noodle"),
			Material = Enum.Material.Pebble,
			Parent = parent,
		})
		sphereMesh(nest)
		local egg = kit.decor({
			Name = "Egg",
			Size = Vector3.new(8, 3.4, 6) * s,
			CFrame = frame * CFrame.new(7 * s, (top + 0.5) * s, 5 * s) * CFrame.Angles(0, math.rad(-30), 0),
			Color = world("eggWhite"),
			Parent = parent,
		})
		sphereMesh(egg)
		local yolk = kit.decor({
			Name = "Yolk",
			Size = Vector3.new(4.2, 1.2, 3.2) * s,
			CFrame = frame * CFrame.new(7 * s, (top + 2) * s, 5 * s) * CFrame.Angles(0, math.rad(-30), 0),
			Color = world("yolk"),
			Parent = parent,
		})
		sphereMesh(yolk)
		for _, slice in
			{
				{ name = "Naruto", d = 6.4, at = Vector3.new(-8, top + 0.6, -6), color = "eggWhite" },
				{ name = "NarutoSwirl", d = 3.2, at = Vector3.new(-8, top + 0.75, -6), color = "narutoPink" },
				{ name = "Chashu", d = 8, at = Vector3.new(4, top + 0.5, -8), color = "chashu" },
			}
		do
			kit.decor({
				Name = slice.name,
				Shape = Enum.PartType.Cylinder,
				Size = cylinderSize(1 * s, slice.d * s),
				CFrame = frame * CFrame.new(slice.at * s) * UPRIGHT,
				Color = world(slice.color),
				Parent = parent,
			})
		end
		kit.decor({
			Name = "Nori",
			Size = Vector3.new(7, 10, 0.4) * s,
			CFrame = frame * CFrame.new(-2 * s, (top + 2.8) * s, 13.6 * s) * CFrame.Angles(math.rad(-14), 0, 0),
			Color = world("nori"),
			Parent = parent,
		})
		-- chopsticks lifting noodles out of the broth: tips over the bowl, handles out past the rim
		local tip = Vector3.new(3, top + 9, -1)
		for _, offset in { -0.7, 0.7 } do
			local a = (frame * CFrame.new((tip + Vector3.new(0, 0, offset)) * s)).Position
			local b = (frame * CFrame.new(Vector3.new(21, top + 17, -6 + offset) * s)).Position
			kit.decor({
				Name = "Chopstick",
				Size = Vector3.new((a - b).Magnitude, 0.9 * s, 0.9 * s),
				CFrame = along(a, b),
				Color = world("chopstick"),
				Parent = parent,
			})
		end
		for i, strand in { -1.1, 0, 1.1 } do
			local a = (frame * CFrame.new((tip + Vector3.new(strand * 0.6, -0.5, strand * 0.4)) * s)).Position
			local b = (frame * CFrame.new(Vector3.new(tip.X + strand * 1.4 + (i - 2) * 0.6, top, strand * 1.6) * s)).Position
			kit.decor({
				Name = "Noodle",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new((a - b).Magnitude, 0.8 * s, 0.8 * s),
				CFrame = along(a, b),
				Color = world("noodle"),
				Parent = parent,
			})
		end
	end,

	-- A steaming hot spring: a wide pool of milky turquoise water ringed with dark boulders, and a paper lantern glowing
	-- on a post beside it.
	hotSpring = function(base: CFrame, size: number, spot: LandmarkSpot, parent: Instance, kit: Kit)
		local s = size * 1.4
		local frame = base * CFrame.Angles(0, math.rad(spot.index * 37), 0)
		local water = kit.decor({
			Name = "SpringWater",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(1.4 * s, 26 * s),
			CFrame = frame * CFrame.new(0, 1 * s, 0) * UPRIGHT,
			Color = world("springWater"),
			Parent = parent,
		})
		water.Reflectance = 0.3
		plume(water, (frame * CFrame.new(0, 2.5 * s, 0)).Position, Color3.new(1, 1, 1), 16 * s, 5, kit)
		for i = 0, 6 do
			local d = (5 + (i * 7) % 4) * s
			kit.decor({
				Name = "Boulder",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * d,
				CFrame = frame * CFrame.Angles(0, math.rad(i * 360 / 7), 0) * CFrame.new(0, d * 0.22, -13.6 * s),
				Color = world("springRock"),
				Material = Enum.Material.Slate,
				Parent = parent,
			})
		end
		kit.decor({
			Name = "LanternPost",
			Size = Vector3.new(1.2, 9.6, 1.2) * s,
			CFrame = frame * CFrame.new(-17 * s, 4.8 * s, -7 * s),
			Color = world("cartWood"),
			Material = Enum.Material.Wood,
			Parent = parent,
		})
		local lantern = kit.decor({
			Name = "PaperLantern",
			Size = Vector3.new(4.4, 5.6, 4.4) * s,
			CFrame = frame * CFrame.new(-17 * s, 12.4 * s, -7 * s),
			Color = world("paperLantern"),
			Material = Enum.Material.Neon,
			CastShadow = false,
			Parent = parent,
		})
		sphereMesh(lantern)
		light(lantern, world("paperLantern"), 26, 1.4)
		kit.decor({
			Name = "LanternCap",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(0.8 * s, 2.6 * s),
			CFrame = frame * CFrame.new(-17 * s, 15.2 * s, -7 * s) * UPRIGHT,
			Color = world("nori"),
			Parent = parent,
		})
	end,

	-- A ramen cart (a yatai): a wooden counter on two big wheels, a roof on two posts, an indigo noren curtain, two red
	-- paper lanterns and a stock pot steaming on the counter.
	ramenCart = function(base: CFrame, size: number, spot: LandmarkSpot, parent: Instance, kit: Kit)
		local s = size * 1.4
		local frame = base * CFrame.Angles(0, math.rad((spot.index % 3 - 1) * 12), 0)
		local wood = world("cartWood")
		kit.decor({
			Name = "Counter",
			Size = Vector3.new(18, 7, 8) * s,
			CFrame = frame * CFrame.new(0, 5.5 * s, 0),
			Color = wood,
			Material = Enum.Material.WoodPlanks,
			Parent = parent,
		})
		for _, side in { -1, 1 } do
			kit.decor({
				Name = "Wheel",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(1.2, 8, 8) * s,
				CFrame = frame * CFrame.new(5 * s, 4 * s, side * 4.7 * s) * CFrame.Angles(0, math.rad(90), 0),
				Color = wood:Lerp(Color3.new(0, 0, 0), 0.35),
				Material = Enum.Material.Wood,
				Parent = parent,
			})
			kit.decor({
				Name = "Post",
				Size = Vector3.new(0.8, 10, 0.8) * s,
				CFrame = frame * CFrame.new(side * 8.4 * s, 14 * s, 0),
				Color = wood,
				Material = Enum.Material.Wood,
				Parent = parent,
			})
			local lantern = kit.decor({
				Name = "PaperLantern",
				Size = Vector3.new(3, 4, 3) * s,
				CFrame = frame * CFrame.new(side * 10.4 * s, 16.2 * s, -5.2 * s),
				Color = world("paperLantern"),
				Material = Enum.Material.Neon,
				CastShadow = false,
				Parent = parent,
			})
			sphereMesh(lantern)
			if side == 1 then
				light(lantern, world("paperLantern"), 20, 1.2)
			end
		end
		kit.decor({
			Name = "Roof",
			Size = Vector3.new(23, 1.4, 12) * s,
			CFrame = frame * CFrame.new(0, 19.6 * s, -0.6 * s),
			Color = wood:Lerp(Color3.new(0, 0, 0), 0.2),
			Material = Enum.Material.WoodPlanks,
			Parent = parent,
		})
		for i = -1, 1 do
			kit.decor({
				Name = "Noren",
				Size = Vector3.new(5.6, 3.6, 0.2) * s,
				CFrame = frame * CFrame.new(i * 6 * s, 17.1 * s, -6.2 * s),
				Color = world("noren"),
				Material = Enum.Material.Fabric,
				Parent = parent,
			})
		end
		local pot = kit.decor({
			Name = "StockPot",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(3.6 * s, 4.4 * s),
			CFrame = frame * CFrame.new(-4.5 * s, 10.8 * s, 0) * UPRIGHT,
			Color = world("smokerMetal"):Lerp(Color3.new(1, 1, 1), 0.55),
			Material = Enum.Material.Metal,
			Parent = parent,
		})
		plume(pot, (frame * CFrame.new(-4.5 * s, 13 * s, 0)).Position, Color3.new(1, 1, 1), 5 * s, 3, kit)
	end,

	-- A water tower on stilts whose tank is a giant squeeze bottle of ketchup or mustard: four legs, two cross braces, a
	-- platform, the bottle with a white label, a domed shoulder, a cap and its nozzle.
	sauceTower = function(base: CFrame, s: number, spot: LandmarkSpot, parent: Instance, kit: Kit)
		local frame = base * CFrame.Angles(0, math.rad(spot.index * 13), 0)
		local sauce = if spot.index % 2 == 0 then world("ketchup") else world("mustard")
		local leg = world("towerLeg")
		for _, corner in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
			kit.decor({
				Name = "Leg",
				Size = Vector3.new(1.6, 24, 1.6) * s,
				CFrame = frame * CFrame.new(corner[1] * 7 * s, 12 * s, corner[2] * 7 * s),
				Color = leg,
				Material = Enum.Material.WoodPlanks,
				Parent = parent,
			})
		end
		for _, brace in
			{
				{ Vector3.new(-7, 2, -7), Vector3.new(7, 22, -7) },
				{ Vector3.new(7, 2, -7), Vector3.new(7, 22, 7) },
			}
		do
			local a, b = (frame * CFrame.new(brace[1] * s)).Position, (frame * CFrame.new(brace[2] * s)).Position
			kit.decor({
				Name = "Brace",
				Size = Vector3.new((b - a).Magnitude, 1 * s, 1 * s),
				CFrame = along(a, b),
				Color = leg,
				Material = Enum.Material.WoodPlanks,
				Parent = parent,
			})
		end
		for _, disc in
			{
				{ name = "Platform", h = 1.4, d = 19, y = 24.7, color = leg },
				{ name = "Bottle", h = 20, d = 16, y = 35.4, color = sauce },
				{ name = "Label", h = 7, d = 16.4, y = 34, color = world("bucketWhite") },
				{ name = "Cap", h = 4, d = 6, y = 54.6, color = world("bucketWhite") },
				{ name = "Nozzle", h = 4.6, d = 2.4, y = 58.9, color = sauce },
			}
		do
			kit.decor({
				Name = disc.name,
				Shape = Enum.PartType.Cylinder,
				Size = cylinderSize(disc.h * s, disc.d * s),
				CFrame = frame * CFrame.new(0, disc.y * s, 0) * UPRIGHT,
				Color = disc.color,
				Parent = parent,
			})
		end
		kit.decor({
			Name = "Shoulder",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 16 * s,
			CFrame = frame * CFrame.new(0, 45.4 * s, 0),
			Color = sauce,
			Parent = parent,
		})
	end,

	-- A barrel smoker on legs: a black drum on its side, a firebox at one end glowing through its vent, a chimney
	-- puffing smoke at the other.
	smoker = function(base: CFrame, size: number, spot: LandmarkSpot, parent: Instance, kit: Kit)
		local s = size * 1.5
		local frame = base * CFrame.Angles(0, math.rad((spot.index % 3 - 1) * 14), 0)
		local metal = world("smokerMetal")
		kit.decor({
			Name = "Drum",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(24, 12, 12) * s,
			CFrame = frame * CFrame.new(0, 10 * s, 0),
			Color = metal,
			Material = Enum.Material.Metal,
			Parent = parent,
		})
		kit.decor({
			Name = "Firebox",
			Size = Vector3.new(8, 8, 9) * s,
			CFrame = frame * CFrame.new(-15 * s, 8 * s, 0),
			Color = metal,
			Material = Enum.Material.Metal,
			Parent = parent,
		})
		local vent = kit.decor({
			Name = "FireVent",
			Size = Vector3.new(5, 1.4, 0.3) * s,
			CFrame = frame * CFrame.new(-15 * s, 6.4 * s, -4.6 * s),
			Color = world("fireGlow"),
			Material = Enum.Material.Neon,
			CastShadow = false,
			Parent = parent,
		})
		light(vent, world("fireGlow"), 22, 1.6)
		local chimney = kit.decor({
			Name = "Chimney",
			Shape = Enum.PartType.Cylinder,
			Size = cylinderSize(12 * s, 2.6 * s),
			CFrame = frame * CFrame.new(10 * s, 20 * s, 0) * UPRIGHT,
			Color = metal,
			Material = Enum.Material.Metal,
			Parent = parent,
		})
		plume(chimney, (frame * CFrame.new(10 * s, 26.5 * s, 0)).Position, world("campStone"), 9 * s, 3, kit)
		for _, corner in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
			kit.decor({
				Name = "Leg",
				Size = Vector3.new(1.2, 5.6, 1.2) * s,
				CFrame = frame * CFrame.new(corner[1] * 9 * s, 2.6 * s, corner[2] * 4 * s),
				Color = world("towerLeg"),
				Material = Enum.Material.Metal,
				Parent = parent,
			})
		end
	end,

	-- A big campfire: a ring of stones, three crossed logs, flames glowing orange and yellow (sparks rising), and a
	-- sausage and a marshmallow roasting on sticks.
	campfire = function(base: CFrame, size: number, spot: LandmarkSpot, parent: Instance, kit: Kit)
		local s = size * 1.5
		local frame = base * CFrame.Angles(0, math.rad(spot.index * 41), 0)
		for i = 0, 4 do
			kit.decor({
				Name = "Stone",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * 4.6 * s,
				CFrame = frame * CFrame.Angles(0, math.rad(i * 72), 0) * CFrame.new(0, 1.2 * s, -8.5 * s),
				Color = world("campStone"),
				Material = Enum.Material.Slate,
				Parent = parent,
			})
		end
		for i = 0, 2 do
			kit.decor({
				Name = "Log",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(13, 2.2, 2.2) * s,
				CFrame = frame * CFrame.new(0, (1.3 + i * 0.9) * s, 0) * CFrame.Angles(0, math.rad(i * 60), 0),
				Color = world("firewood"),
				Material = Enum.Material.Wood,
				Parent = parent,
			})
		end
		local flame = kit.decor({
			Name = "Flame",
			Size = Vector3.new(6.4, 11, 6.4) * s,
			CFrame = frame * CFrame.new(0, 7 * s, 0),
			Color = world("fireGlow"),
			Material = Enum.Material.Neon,
			Transparency = 0.15,
			CastShadow = false,
			Parent = parent,
		})
		sphereMesh(flame)
		local flameCore = kit.decor({
			Name = "FlameCore",
			Size = Vector3.new(3.6, 7, 3.6) * s,
			CFrame = frame * CFrame.new(0, 5.6 * s, 0),
			Color = world("flameCore"),
			Material = Enum.Material.Neon,
			CastShadow = false,
			Parent = parent,
		})
		sphereMesh(flameCore)
		light(flame, world("fireGlow"), 40, 2)
		local sparks = Instance.new("Attachment")
		sparks.Name = "Sparks"
		sparks.Parent = flame
		sparks.WorldCFrame = CFrame.new((frame * CFrame.new(0, 11 * s, 0)).Position)
		kit.emitter(sparks, {
			Name = "Sparks",
			Texture = "rbxasset://textures/particles/sparkles_main.dds",
			Color = ColorSequence.new(Color3.fromRGB(255, 200, 90), Color3.fromRGB(255, 90, 30)),
			LightEmission = 1,
			Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.5),
				NumberSequenceKeypoint.new(1, 0.1),
			}),
			Speed = NumberRange.new(4, 8),
			SpreadAngle = Vector2.new(25, 25),
			Acceleration = Vector3.new(0.5, 2, 0.3),
			Lifetime = NumberRange.new(1.5, 2.5),
			Rate = 6,
			EmissionDirection = Enum.NormalId.Top,
		})
		for _, roast in
			{
				{ from = Vector3.new(14, 2, 6), to = Vector3.new(3.5, 6, 1.5), treat = "sausage" },
				{ from = Vector3.new(-13, 2, 7), to = Vector3.new(-3, 5.5, 2), treat = "marshmallow" },
			}
		do
			local a, b = (frame * CFrame.new(roast.from * s)).Position, (frame * CFrame.new(roast.to * s)).Position
			kit.decor({
				Name = "RoastingStick",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new((b - a).Magnitude, 0.5 * s, 0.5 * s),
				CFrame = along(a, b),
				Color = world("skewerWood"),
				Material = Enum.Material.Wood,
				Parent = parent,
			})
			local treat = kit.decor({
				Name = if roast.treat == "sausage" then "Sausage" else "Marshmallow",
				Size = if roast.treat == "sausage"
					then Vector3.new(4.6, 1.8, 1.8) * s
					else Vector3.new(2.2, 2.4, 2.2) * s,
				CFrame = along(a, b) * CFrame.new((b - a).Magnitude / 2, 0, 0),
				Color = world(roast.treat),
				Parent = parent,
			})
			if roast.treat == "sausage" then
				sphereMesh(treat)
			end
		end
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
