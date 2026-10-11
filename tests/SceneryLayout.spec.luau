--!strict
local T = require("./TestKit")
local SceneryLayout = require("../src/shared/Logic/SceneryLayout")
local SeasonRules = require("../src/shared/Logic/SeasonRules")
local Scenery = require("../src/shared/Config/Scenery")
local Seasons = require("../src/shared/Config/Seasons")
local Gameplay = require("../src/shared/Config/Gameplay")
local Types = require("../src/shared/Types")

local MAP = Gameplay.map
local BELT = Gameplay.belt
local FLOOR_TOP = 0.4
local WALKWAY_TOP = 0.2

-- Every Halloween decoration on the real map (the same shape SeasonService builds it on).
local function halloweenProps(): { SceneryLayout.Point }
	local entrances: { SeasonRules.Entrance } = {}
	for index, rect in SceneryLayout.plotRects(MAP) do
		local north = index <= MAP.plotsPerSide
		local x = (rect.minX + rect.maxX) / 2
		table.insert(entrances, {
			x = x,
			z = if north then rect.minZ else rect.maxZ,
			outX = 0,
			outZ = if north then -1 else 1,
		})
	end
	local shape: SeasonRules.MapShape = {
		entrances = entrances,
		entranceWidth = MAP.entranceWidth,
		plotWidth = MAP.plotWidth,
		groundY = WALKWAY_TOP,
		wallTopY = FLOOR_TOP + MAP.wallHeight,
		beltLength = BELT.length,
		beltWidth = BELT.width,
		walkwayWidth = MAP.walkwayWidth,
	}
	local points: { SceneryLayout.Point } = {}
	for _, theme in Seasons.themes do
		for _, prop in SeasonRules.layout(theme.decorations, theme.palette, shape) do
			table.insert(points, { x = prop.x, z = prop.z })
		end
	end
	return points
end

local function clone(): Types.SceneryConfig
	local copy = table.clone(Scenery)
	copy.plaza = table.clone(Scenery.plaza)
	copy.terrain = table.clone(Scenery.terrain)
	copy.boundary = table.clone(Scenery.boundary)
	copy.lighting = table.clone(Scenery.lighting)
	copy.trees = table.clone(Scenery.trees)
	return copy
end

T.describe("SceneryLayout map shape", function()
	T.it("matches MapBuilder's plot rectangles", function()
		local rects = SceneryLayout.plotRects(MAP)
		T.expect(#rects).toBe(MAP.plotCount)
		-- plot 1: north-west, plot 5: south-west (the same column)
		T.expect(rects[1].minX).toBe(-127)
		T.expect(rects[1].minZ).toBe(MAP.walkwayWidth)
		T.expect(rects[1].maxZ).toBe(MAP.walkwayWidth + MAP.plotDepth)
		T.expect(rects[5].maxZ).toBe(-MAP.walkwayWidth)
		T.expect(rects[4].maxX).toBe(127)
	end)
	T.it("puts the factory intake around the belt's start and the chute around its end", function()
		local intake = SceneryLayout.factoryIntake(BELT.length)
		local chute = SceneryLayout.chute(BELT.length)
		-- items appear at x = -length/2 and vanish at +length/2: both inside a housing
		T.expect(-BELT.length / 2 > intake.minX and -BELT.length / 2 < intake.maxX).toBe(true)
		T.expect(BELT.length / 2 > chute.minX and BELT.length / 2 < chute.maxX).toBe(true)
		-- the belt fits through both openings
		T.expect(intake.maxZ).toBeGreaterThan(BELT.width / 2 + 0.8)
		T.expect(chute.maxZ).toBeGreaterThan(BELT.width / 2 + 0.8)
	end)
end)

T.describe("Config/Scenery", function()
	T.it("passes validation on the real map, clear of every Halloween decoration", function()
		local problems = SceneryLayout.validate(Scenery, MAP, BELT, halloweenProps())
		if #problems > 0 then
			error(table.concat(problems, "\n"))
		end
	end)
	T.it("keeps the lobby spawn on the plaza and every Halloween prop off it", function()
		local lobby = MAP.lobby
		local fromPlaza = math.sqrt((lobby.x - Scenery.plaza.x) ^ 2 + (lobby.z - Scenery.plaza.z) ^ 2)
		T.expect(fromPlaza).toBeLessThan(Scenery.plaza.radius)
		for _, point in halloweenProps() do
			T.expect(math.sqrt((point.x - lobby.x) ^ 2 + (point.z - lobby.z) ^ 2)).toBeGreaterThan(6)
		end
	end)
	T.it("stays under the part budget", function()
		local layout = SceneryLayout.layout(Scenery)
		local parts = SceneryLayout.partEstimate(Scenery, layout, MAP, BELT)
		T.expect(parts).toBeAtMost(Scenery.partBudget)
		T.expect(parts).toBeAtMost(1500)
	end)
	T.it("is deterministic", function()
		T.expect(SceneryLayout.layout(Scenery)).toEqual(SceneryLayout.layout(Scenery))
	end)
	T.it("puts a tree line outside the wall, standing on the terrain", function()
		local outside = 0
		for _, tree in SceneryLayout.layout(Scenery).trees do
			if tree.outside then
				outside += 1
				T.expect(SceneryLayout.inset(Scenery.boundary, tree.x, tree.z)).toBeLessThan(0)
				T.expect(tree.y).toBeNear(SceneryLayout.groundHeight(Scenery.terrain, tree.x, tree.z), 1e-9)
			else
				T.expect(tree.y).toBe(0)
			end
		end
		T.expect(outside).toBeGreaterThan(Scenery.treeLine.count * 0.7)
	end)
end)

T.describe("SceneryLayout terrain maths", function()
	local hill: Types.HillDef = { x = 0, z = 0, radius = 100, height = 40 }
	T.it("finds where a hill meets the ground", function()
		T.expect(SceneryLayout.hillFootprint(hill)).toBeNear(80, 1e-9) -- 100^2 - 60^2 = 80^2
	end)
	T.it("measures ground height on and off hills", function()
		local terrain: Types.SceneryTerrain = { extent = 500, depth = 12, hills = { hill }, rocks = {}, lake = nil }
		T.expect(SceneryLayout.groundHeight(terrain, 0, 0)).toBeNear(40, 1e-9)
		T.expect(SceneryLayout.groundHeight(terrain, 80, 0)).toBeNear(0, 1e-9)
		T.expect(SceneryLayout.groundHeight(terrain, 300, 0)).toBe(0)
		T.expect(SceneryLayout.groundHeight(terrain, 40, 0)).toBeGreaterThan(0)
	end)
	T.it("measures distances to rectangles", function()
		local rect = { minX = 0, maxX = 10, minZ = 0, maxZ = 10 }
		T.expect(SceneryLayout.rectDistance(rect, 5, 5)).toBe(0)
		T.expect(SceneryLayout.rectDistance(rect, 13, 14)).toBeNear(5, 1e-9)
		T.expect(SceneryLayout.inset(rect, 2, 5)).toBe(2)
		T.expect(SceneryLayout.inset(rect, -3, 5)).toBe(-3)
	end)
end)

T.describe("SceneryLayout.validate catches", function()
	local avoid = halloweenProps()
	local function problemsWith(edit: (Types.SceneryConfig) -> ()): { string }
		local config = clone()
		edit(config)
		return SceneryLayout.validate(config, MAP, BELT, avoid)
	end
	T.it("a tree on a plot or on the walkway", function()
		T.expect(#problemsWith(function(c)
			table.insert(c.trees, { x = -99, z = 60 })
		end)).toBeGreaterThan(0)
		T.expect(#problemsWith(function(c)
			table.insert(c.trees, { x = 20, z = 12 })
		end)).toBeGreaterThan(0)
	end)
	T.it("a prop right behind a plot, where ejected visitors land", function()
		T.expect(#problemsWith(function(c)
			table.insert(c.trees, { x = -99, z = 106, scale = 0.5 })
		end)).toBeGreaterThan(0)
	end)
	T.it("a hill reaching inside the boundary", function()
		T.expect(#problemsWith(function(c)
			c.terrain.hills = table.clone(c.terrain.hills)
			-- footprint radius 80: from z = 200 it reaches z = 120, inside the wall at z = 136
			table.insert(c.terrain.hills, { x = 0, z = 200, radius = 100, height = 40 })
		end)).toBeGreaterThan(0)
	end)
	T.it("a boundary too small for the plaza", function()
		T.expect(#problemsWith(function(c)
			c.boundary.maxX = 200
		end)).toBeGreaterThan(0)
	end)
	T.it("a bench on the lobby spawn or on the path", function()
		T.expect(#problemsWith(function(c)
			c.plaza.benchAngles = { 180 } -- right on the path, by the spawn
		end)).toBeGreaterThan(0)
	end)
	T.it("too many trees for the part budget", function()
		T.expect(#problemsWith(function(c)
			c.treeLine = { count = 400, minDistance = 14, maxDistance = 40, seed = 1 }
		end)).toBeGreaterThan(0)
	end)
	T.it("bad lighting values", function()
		T.expect(#problemsWith(function(c)
			c.lighting.clockTime = 30
		end)).toBe(1)
	end)
end)

return nil
