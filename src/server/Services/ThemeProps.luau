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
