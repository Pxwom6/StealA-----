--!strict
--[[
	Where the code-built scenery goes (Config/Scenery): the spawn plaza's benches, lamps, flower beds and trees, the
	trees around the bases, the tree line outside the boundary wall, and the footprints of the Snack Factory and the
	chute at the belt's ends. Also the terrain maths (hill heights) and validation of the config. Pure: no Roblox
	APIs; SceneryBuilder (server) turns this into parts and terrain.

	Coordinates are world studs (Y up). A prop's `yaw` is the direction its front faces, in degrees: (cos yaw, sin yaw)
	in (x, z), so 0 faces +X and 180 faces back along the belt.

	`validate` is what keeps the scenery out of the way of the game: nothing on a plot (or close enough to catch a
	player the server ejects from one), on the belt or the walkway, on the lobby spawn or a Halloween decoration, and
	no terrain inside the boundary.
]]

local Types = require("../Types")

type SceneryConfig = Types.SceneryConfig
type HillDef = Types.HillDef
type TreeKind = Types.TreeKind

export type Rect = { minX: number, maxX: number, minZ: number, maxZ: number }
export type Point = { x: number, z: number }

-- A prop standing on the ground, facing `yaw`.
export type Spot = { x: number, z: number, yaw: number }

export type TreeSpot = {
	x: number,
	y: number, -- ground height under the tree (hills outside the wall)
	z: number,
	scale: number,
	kind: TreeKind,
	seed: number, -- picks the canopy's tilt
	outside: boolean, -- beyond the boundary wall (out of reach)
}

export type Layout = {
	benches: { Spot },
	lamps: { Spot },
	flowerBeds: { Spot },
	trees: { TreeSpot },
}

-- The gameplay geometry the scenery stays clear of.
export type MapShape = {
	plots: { Rect },
	walkway: Rect,
	belt: Rect, -- belt + rails
	structures: { Rect }, -- Snack Factory (intake + hall) and the chute
	lobby: Point,
}

-- The parts of Config/Gameplay used here (map and belt).
export type MapConfig = {
	plotCount: number,
	plotsPerSide: number,
	plotWidth: number,
	plotDepth: number,
	plotGap: number,
	walkwayWidth: number,
	maxPodiums: number,
	lobby: Point,
}
export type BeltConfig = { length: number, width: number }

local SceneryLayout = {}

-- Footprint radii (studs) used for spacing checks.
SceneryLayout.RADIUS = {
	bench = 2.6,
	lamp = 1,
	flowerBed = 3,
	roundTree = 4.5, -- canopy, at scale 1
	pineTree = 5,
	board = 9.5, -- half a leaderboard's width
	pillar = 2,
}

-- Parts each kind of prop is built from (SceneryBuilder / MapBuilder build exactly these). Used for the part budget.
SceneryLayout.PARTS = {
	tree = 4, -- trunk + three canopy pieces
	bench = 4, -- seat, back, two legs
	lamp = 3, -- post, lantern, cap
	flowerBed = 8, -- box, soil, six flowers
	factory = 30,
	chute = 12,
	arch = 21,
	fountain = 21, -- basin, water, four spouts, pedestal, cupcake statue
	plazaGround = 6, -- paving, border, path, spawn ring and two path edges
	board = 5, -- per leaderboard: frame, header, two legs, plinth
	boundary = 12, -- four walls, four caps, four invisible barriers
	beltRails = 2,
	plotFixed = 20, -- per plot: floor tiles (9), posts (6), post caps (4), sign border (1)
	plotButtons = 3, -- per plot: lock plinth, lock ring, upgrade frame
	podium = 2, -- per podium: collar, pad ring
}

-- Snack Factory and chute footprints at the belt's ends (items appear inside the intake and vanish in the chute).
function SceneryLayout.factoryIntake(beltLength: number): Rect
	local start = -beltLength / 2
	return { minX = start - 12, maxX = start + 1, minZ = -7, maxZ = 7 }
end

function SceneryLayout.factoryHall(beltLength: number): Rect
	local start = -beltLength / 2
	return { minX = start - 38, maxX = start - 15, minZ = -16, maxZ = 16 }
end

function SceneryLayout.chute(beltLength: number): Rect
	local finish = beltLength / 2
	return { minX = finish - 1, maxX = finish + 9, minZ = -6.5, maxZ = 6.5 }
end

-- Plot rectangles, the same maths as MapBuilder.plotOrigin (plots on both sides of the belt, entrances facing it).
function SceneryLayout.plotRects(map: MapConfig): { Rect }
	local rects: { Rect } = {}
	local spanX = map.plotsPerSide * map.plotWidth + (map.plotsPerSide - 1) * map.plotGap
	for index = 1, map.plotCount do
		local north = index <= map.plotsPerSide
		local column = (index - 1) % map.plotsPerSide
		local x = -spanX / 2 + map.plotWidth / 2 + column * (map.plotWidth + map.plotGap)
		local z = (if north then 1 else -1) * (map.walkwayWidth + map.plotDepth / 2)
		table.insert(rects, {
			minX = x - map.plotWidth / 2,
			maxX = x + map.plotWidth / 2,
			minZ = z - map.plotDepth / 2,
			maxZ = z + map.plotDepth / 2,
		})
	end
	return rects
end

-- Half the walkway's length along X (MapBuilder: the plot row plus 30 studs at each end).
function SceneryLayout.walkwayHalfLength(map: MapConfig): number
	return (map.plotsPerSide * map.plotWidth + (map.plotsPerSide - 1) * map.plotGap + 60) / 2
end

function SceneryLayout.mapShape(map: MapConfig, belt: BeltConfig): MapShape
	local walkX = SceneryLayout.walkwayHalfLength(map)
	return {
		plots = SceneryLayout.plotRects(map),
		walkway = { minX = -walkX, maxX = walkX, minZ = -map.walkwayWidth, maxZ = map.walkwayWidth },
		belt = {
			minX = -belt.length / 2 - 6,
			maxX = belt.length / 2 + 6,
			minZ = -belt.width / 2 - 0.8,
			maxZ = belt.width / 2 + 0.8,
		},
		structures = {
			SceneryLayout.factoryIntake(belt.length),
			SceneryLayout.factoryHall(belt.length),
			SceneryLayout.chute(belt.length),
		},
		lobby = map.lobby,
	}
end

-- Distance from a point to a rectangle (0 inside it).
function SceneryLayout.rectDistance(rect: Rect, x: number, z: number): number
	local dx = math.max(rect.minX - x, 0, x - rect.maxX)
	local dz = math.max(rect.minZ - z, 0, z - rect.maxZ)
	return math.sqrt(dx * dx + dz * dz)
end

-- How far inside a rectangle a point is (negative when outside).
function SceneryLayout.inset(rect: Rect, x: number, z: number): number
	return math.min(x - rect.minX, rect.maxX - x, z - rect.minZ, rect.maxZ - z)
end

-- Where a hill meets the ground (y = 0): the radius of its footprint.
function SceneryLayout.hillFootprint(hill: HillDef): number
	local sunk = hill.radius - hill.height
	return math.sqrt(math.max(0, hill.radius * hill.radius - sunk * sunk))
end

-- Terrain height at (x, z): 0 on the flat grass, higher on a hill.
function SceneryLayout.groundHeight(terrain: Types.SceneryTerrain, x: number, z: number): number
	local best = 0
	for _, hill in terrain.hills do
		local d2 = (x - hill.x) ^ 2 + (z - hill.z) ^ 2
		if d2 < hill.radius * hill.radius then
			best = math.max(best, hill.height - hill.radius + math.sqrt(hill.radius * hill.radius - d2))
		end
	end
	return best
end

local function polar(cx: number, cz: number, radius: number, degrees: number): (number, number)
	local a = math.rad(degrees)
	return cx + radius * math.cos(a), cz + radius * math.sin(a)
end

-- Park-Miller generator: the same layout on every server and in tests.
local function generator(seed: number): () -> number
	local state = math.floor(seed) % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	return function(): number
		state = (state * 16807) % 2147483647
		return (state - 1) / 2147483646
	end
end

function SceneryLayout.canopyRadius(kind: TreeKind, scale: number): number
	return (if kind == "pine" then SceneryLayout.RADIUS.pineTree else SceneryLayout.RADIUS.roundTree) * scale
end

-- Trees in a ring just outside the boundary wall, skipping the lake and the terrain's edge.
local function treeLine(config: SceneryConfig): { TreeSpot }
	local trees: { TreeSpot } = {}
	local b = config.boundary
	local width, depth = b.maxX - b.minX, b.maxZ - b.minZ
	local perimeter = 2 * (width + depth)
	local line = config.treeLine
	local random = generator(line.seed)
	local lake = config.terrain.lake
	for i = 0, line.count - 1 do
		local t = (i + 0.2 + 0.6 * random()) / line.count * perimeter
		local distance = line.minDistance + (line.maxDistance - line.minDistance) * random()
		local kind: TreeKind = if random() < 0.5 then "pine" else "round"
		local scale = 0.95 + 0.5 * random()
		local x, z
		if t < width then -- south edge, west to east
			x, z = b.minX + t, b.minZ - distance
		elseif t < width + depth then -- east edge
			x, z = b.maxX + distance, b.minZ + (t - width)
		elseif t < 2 * width + depth then -- north edge, east to west
			x, z = b.maxX - (t - width - depth), b.maxZ + distance
		else -- west edge
			x, z = b.minX - distance, b.maxZ - (t - 2 * width - depth)
		end
		local canopy = SceneryLayout.canopyRadius(kind, scale)
		local inLake = lake ~= nil and math.sqrt((x - lake.x) ^ 2 + (z - lake.z) ^ 2) < lake.radius + canopy + 8
		local extent = config.terrain.extent - canopy - 4
		if not inLake and math.abs(x) < extent and math.abs(z) < extent then
			table.insert(trees, {
				x = x,
				y = SceneryLayout.groundHeight(config.terrain, x, z),
				z = z,
				scale = scale,
				kind = kind,
				seed = line.seed * 1000 + i,
				outside = true,
			})
		end
	end
	return trees
end

-- Every prop's position. Deterministic: the same config always gives the same layout.
function SceneryLayout.layout(config: SceneryConfig): Layout
	local plaza = config.plaza
	local benches: { Spot } = {}
	for _, angle in plaza.benchAngles do
		local x, z = polar(plaza.x, plaza.z, plaza.benchRadius, angle)
		table.insert(benches, { x = x, z = z, yaw = angle + 180 }) -- facing the fountain
	end
	local lamps: { Spot } = {}
	for _, angle in plaza.lampAngles do
		local x, z = polar(plaza.x, plaza.z, plaza.lampRadius, angle)
		table.insert(lamps, { x = x, z = z, yaw = angle + 180 })
	end
	local beds: { Spot } = {}
	for _, angle in plaza.flowerAngles do
		local x, z = polar(plaza.x, plaza.z, plaza.flowerRadius, angle)
		table.insert(beds, { x = x, z = z, yaw = angle + 180 })
	end
	for _, bed in plaza.extraFlowerBeds do
		table.insert(beds, { x = bed.x, z = bed.z, yaw = bed.yaw })
	end

	local trees: { TreeSpot } = {}
	for index, def in config.trees do
		table.insert(trees, {
			x = def.x,
			y = 0,
			z = def.z,
			scale = def.scale or 1,
			kind = def.kind or "round",
			seed = index,
			outside = false,
		})
	end
	for index, angle in plaza.treeAngles do
		local x, z = polar(plaza.x, plaza.z, plaza.treeRadius, angle)
		table.insert(trees, {
			x = x,
			y = 0,
			z = z,
			scale = if index % 3 == 0 then 1.15 else 1,
			kind = if index % 2 == 0 then "pine" else "round",
			seed = 500 + index,
			outside = false,
		})
	end
	for _, tree in treeLine(config) do
		table.insert(trees, tree)
	end

	return { benches = benches, lamps = lamps, flowerBeds = beds, trees = trees }
end

-- How many parts the scenery adds on top of the gameplay geometry (the layout's props plus fixed structures and the
-- plot decorations). CI keeps it under `partBudget`.
function SceneryLayout.partEstimate(config: SceneryConfig, layout: Layout, map: MapConfig, belt: BeltConfig): number
	local P = SceneryLayout.PARTS
	local beltPartLength = belt.length + 12
	local chevrons = 2 * math.ceil(beltPartLength / config.chevronSpacing)
	return #layout.trees * P.tree
		+ #layout.benches * P.bench
		+ #layout.lamps * P.lamp
		+ #layout.flowerBeds * P.flowerBed
		+ P.factory
		+ P.chute
		+ P.arch
		+ P.fountain
		+ P.plazaGround
		+ 2 * P.board
		+ P.boundary
		+ P.beltRails
		+ chevrons
		+ map.plotCount * (P.plotFixed + P.plotButtons + map.maxPodiums * P.podium)
end

-- Problems with Config/Scenery on this map (an empty list means valid). `avoid` lists decorations that must stay
-- clear (the Halloween props from Logic/SeasonRules).
function SceneryLayout.validate(config: SceneryConfig, map: MapConfig, belt: BeltConfig, avoid: { Point }): { string }
	local problems: { string } = {}
	local function problem(message: string)
		table.insert(problems, message)
	end
	local function range(value: number, low: number, high: number, what: string)
		if not (value >= low and value <= high) then
			problem(`{what} must be between {low} and {high}`)
		end
	end
	local function round(n: number): number
		return math.floor(n * 10 + 0.5) / 10
	end

	local shape = SceneryLayout.mapShape(map, belt)
	local boundary: Rect = config.boundary
	local plaza = config.plaza
	local R = SceneryLayout.RADIUS

	-- The boundary holds the whole game with room to spare.
	local function enclosed(rect: Rect, what: string)
		for _, corner in { { rect.minX, rect.minZ }, { rect.maxX, rect.maxZ } } do
			if SceneryLayout.inset(boundary, corner[1], corner[2]) < 6 then
				problem(`{what} reaches the boundary wall`)
				return
			end
		end
	end
	for index, rect in shape.plots do
		enclosed(rect, `plot {index}`)
	end
	enclosed(shape.walkway, "the walkway")
	for _, rect in shape.structures do
		enclosed(rect, "the factory / chute")
	end
	if SceneryLayout.inset(boundary, plaza.x, plaza.z) < plaza.radius + 6 then
		problem("the plaza reaches the boundary wall")
	end

	-- Lobby spawn: on the plaza paving, clear of the fountain and of Halloween decorations.
	local lobby = shape.lobby
	local lobbyFromCentre = math.sqrt((lobby.x - plaza.x) ^ 2 + (lobby.z - plaza.z) ^ 2)
	if lobbyFromCentre > plaza.radius - 5 or lobbyFromCentre < plaza.fountainRadius + 5 then
		problem("the lobby spawn must stand on the plaza paving, clear of the fountain")
	end

	-- The archway spans the path between the walkway's end and the plaza; the boards flank it.
	if plaza.archX < shape.walkway.maxX + 3 or plaza.archX > plaza.x - plaza.radius - 3 then
		problem("archX must lie between the walkway's end and the plaza")
	end
	if plaza.archSpan / 2 < plaza.pathWidth / 2 + R.pillar + 1 then
		problem("archSpan must leave the path clear of the pillars")
	end
	if plaza.boardZ - R.board < plaza.archSpan / 2 + R.pillar + 2 then
		problem("the leaderboards overlap the archway")
	end
	if plaza.boardX + 2 > plaza.x - plaza.radius or plaza.boardX - 2 < shape.walkway.maxX - R.board then
		problem("boardX must lie between the walkway's end and the plaza")
	end
	if SceneryLayout.rectDistance(shape.walkway, plaza.boardX, plaza.boardZ - R.board) < 2 then
		problem("the leaderboards touch the walkway")
	end

	-- Everything with a footprint, for the shared checks below.
	type Item = { what: string, x: number, z: number, radius: number }
	local items: { Item } = {}
	local layout = SceneryLayout.layout(config)
	for i, spot in layout.benches do
		table.insert(items, { what = `bench {i}`, x = spot.x, z = spot.z, radius = R.bench })
	end
	for i, spot in layout.lamps do
		table.insert(items, { what = `lamp {i}`, x = spot.x, z = spot.z, radius = R.lamp })
	end
	for i, spot in layout.flowerBeds do
		table.insert(items, { what = `flower bed {i}`, x = spot.x, z = spot.z, radius = R.flowerBed })
	end
	for i, tree in layout.trees do
		if not tree.outside then
			local canopy = SceneryLayout.canopyRadius(tree.kind, tree.scale)
			table.insert(items, { what = `tree {i}`, x = tree.x, z = tree.z, radius = canopy })
		end
	end
	-- Fixed pieces other items must not overlap (not checked against each other).
	local fixed: { Item } = {
		{ what = "the fountain", x = plaza.x, z = plaza.z, radius = plaza.fountainRadius },
		{ what = "an arch pillar", x = plaza.archX, z = plaza.archSpan / 2, radius = R.pillar },
		{ what = "an arch pillar", x = plaza.archX, z = -plaza.archSpan / 2, radius = R.pillar },
		{ what = "a leaderboard", x = plaza.boardX, z = plaza.boardZ, radius = R.board },
		{ what = "a leaderboard", x = plaza.boardX, z = -plaza.boardZ, radius = R.board },
		{ what = "the lobby spawn", x = lobby.x, z = lobby.z, radius = 5 },
	}

	for _, item in items do
		local label = `{item.what} at ({round(item.x)}, {round(item.z)})`
		if SceneryLayout.inset(boundary, item.x, item.z) < item.radius + 1.5 then
			problem(`{label} reaches the boundary wall`)
		end
		for index, rect in shape.plots do
			-- 8 studs: the server ejects visitors 3 studs outside a plot's side.
			if SceneryLayout.rectDistance(rect, item.x, item.z) < math.max(8, item.radius + 3) then
				problem(`{label} is too close to plot {index}`)
			end
		end
		if SceneryLayout.rectDistance(shape.walkway, item.x, item.z) < item.radius + 1 then
			problem(`{label} is on the walkway`)
		end
		if SceneryLayout.rectDistance(shape.belt, item.x, item.z) < item.radius + 1 then
			problem(`{label} is on the belt`)
		end
		for _, rect in shape.structures do
			if SceneryLayout.rectDistance(rect, item.x, item.z) < item.radius + 1 then
				problem(`{label} overlaps the factory / chute`)
			end
		end
		-- The path from the walkway through the archway onto the plaza stays clear.
		if
			item.x > shape.walkway.maxX
			and item.x < plaza.x
			and math.abs(item.z - plaza.z) < plaza.pathWidth / 2 + item.radius
		then
			problem(`{label} blocks the path to the plaza`)
		end
		for _, other in fixed do
			if math.sqrt((item.x - other.x) ^ 2 + (item.z - other.z) ^ 2) < item.radius + other.radius + 1 then
				problem(`{label} overlaps {other.what}`)
			end
		end
		for _, point in avoid do
			if math.sqrt((item.x - point.x) ^ 2 + (item.z - point.z) ^ 2) < item.radius + 2 then
				problem(`{label} overlaps a seasonal decoration`)
			end
		end
	end
	for i = 1, #items do
		for j = i + 1, #items do
			local a, b = items[i], items[j]
			if math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2) < (a.radius + b.radius) * 0.8 then
				problem(`{a.what} and {b.what} overlap`)
			end
		end
	end
	for _, point in avoid do
		if math.sqrt((point.x - lobby.x) ^ 2 + (point.z - lobby.z) ^ 2) < 6 then
			problem("a seasonal decoration sits on the lobby spawn")
		end
		if SceneryLayout.rectDistance(shape.structures[1], point.x, point.z) < 1.5 then
			problem("a seasonal decoration overlaps the factory intake")
		end
		if SceneryLayout.rectDistance(shape.structures[2], point.x, point.z) < 1.5 then
			problem("a seasonal decoration overlaps the factory hall")
		end
		if SceneryLayout.rectDistance(shape.structures[3], point.x, point.z) < 1.5 then
			problem("a seasonal decoration overlaps the chute")
		end
	end

	-- Outside the wall: trees, terrain.
	local terrain = config.terrain
	for i, tree in layout.trees do
		if tree.outside then
			local canopy = SceneryLayout.canopyRadius(tree.kind, tree.scale)
			if SceneryLayout.rectDistance(boundary, tree.x, tree.z) < canopy + 2 then
				problem(`tree line tree {i} touches the boundary wall`)
			end
		end
	end
	for i, hill in terrain.hills do
		local footprint = SceneryLayout.hillFootprint(hill)
		if not (hill.height > 0 and hill.height <= hill.radius * 2) then
			problem(`hill {i} needs 0 < height <= 2 x radius`)
		end
		if SceneryLayout.rectDistance(boundary, hill.x, hill.z) < footprint + 10 then
			problem(`hill {i} reaches inside the boundary`)
		end
		if math.max(math.abs(hill.x), math.abs(hill.z)) + footprint > terrain.extent then
			problem(`hill {i} runs off the terrain`)
		end
	end
	for i, rock in terrain.rocks do
		if SceneryLayout.rectDistance(boundary, rock.x, rock.z) < rock.radius + 4 then
			problem(`rock {i} is too close to the boundary`)
		end
	end
	local lake = terrain.lake
	if lake then
		if SceneryLayout.rectDistance(boundary, lake.x, lake.z) < lake.radius + 16 then
			problem("the lake reaches the boundary")
		end
		if math.max(math.abs(lake.x), math.abs(lake.z)) + lake.radius + 8 > terrain.extent then
			problem("the lake runs off the terrain")
		end
		for i, hill in terrain.hills do
			local gap = math.sqrt((hill.x - lake.x) ^ 2 + (hill.z - lake.z) ^ 2)
			if gap < SceneryLayout.hillFootprint(hill) + lake.radius + 8 then
				problem(`hill {i} overlaps the lake`)
			end
		end
	end
	if not (terrain.depth >= 4) then
		problem("terrain.depth must be at least 4")
	end

	-- Lighting stays in Roblox's ranges.
	local lighting = config.lighting
	range(lighting.clockTime, 0, 24, "lighting.clockTime")
	range(lighting.brightness, 0, 10, "lighting.brightness")
	range(lighting.environmentDiffuseScale, 0, 1, "lighting.environmentDiffuseScale")
	range(lighting.environmentSpecularScale, 0, 1, "lighting.environmentSpecularScale")
	range(lighting.shadowSoftness, 0, 1, "lighting.shadowSoftness")
	range(lighting.atmosphere.density, 0, 1, "lighting.atmosphere.density")
	range(lighting.atmosphere.offset, 0, 1, "lighting.atmosphere.offset")
	range(lighting.colorCorrection.saturation, -1, 1, "lighting.colorCorrection.saturation")
	range(lighting.colorCorrection.contrast, -1, 1, "lighting.colorCorrection.contrast")
	range(lighting.clouds.cover, 0, 1, "lighting.clouds.cover")
	range(lighting.clouds.density, 0, 1, "lighting.clouds.density")
	for _, hex in
		{
			lighting.ambient,
			lighting.outdoorAmbient,
			lighting.colorShiftTop,
			lighting.colorShiftBottom,
			lighting.atmosphere.color,
			lighting.atmosphere.decay,
			lighting.colorCorrection.tint,
			lighting.clouds.color,
		}
	do
		if string.match(hex, "^#%x%x%x%x%x%x$") == nil then
			problem(`lighting colour {hex} must be #RRGGBB`)
		end
	end

	if not (config.chevronSpacing >= 4) then
		problem("chevronSpacing must be at least 4")
	end
	local parts = SceneryLayout.partEstimate(config, layout, map, belt)
	if parts > config.partBudget then
		problem(`the scenery builds about {parts} parts, over the budget of {config.partBudget}`)
	end
	return problems
end

return SceneryLayout
