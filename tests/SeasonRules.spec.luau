--!strict
local T = require("./TestKit")
local SeasonRules = require("../src/shared/Logic/SeasonRules")
local Seasons = require("../src/shared/Config/Seasons")
local Gameplay = require("../src/shared/Config/Gameplay")
local LiveOps = require("../src/shared/Config/LiveOps")
local Types = require("../src/shared/Types")

-- The real map, built the way MapBuilder lays it out (plots on both sides of the belt, entrances facing it).
-- SeasonService passes the same shape from the plots MapBuilder actually built.
local MAP = Gameplay.map
local FLOOR_TOP = 0.4
local WALKWAY_TOP = 0.2

type Rect = { minX: number, maxX: number, minZ: number, maxZ: number }

local function realMap(): (SeasonRules.MapShape, { Rect })
	local entrances: { SeasonRules.Entrance } = {}
	local rects: { Rect } = {}
	local spanX = MAP.plotsPerSide * MAP.plotWidth + (MAP.plotsPerSide - 1) * MAP.plotGap
	for index = 1, MAP.plotCount do
		local north = index <= MAP.plotsPerSide
		local column = (index - 1) % MAP.plotsPerSide
		local x = -spanX / 2 + MAP.plotWidth / 2 + column * (MAP.plotWidth + MAP.plotGap)
		local sign = if north then 1 else -1
		local z = sign * (MAP.walkwayWidth + MAP.plotDepth / 2)
		-- the entrance faces the belt: out of the plot is towards z = 0
		table.insert(entrances, { x = x, z = z - sign * MAP.plotDepth / 2, outX = 0, outZ = -sign })
		table.insert(rects, {
			minX = x - MAP.plotWidth / 2,
			maxX = x + MAP.plotWidth / 2,
			minZ = z - MAP.plotDepth / 2,
			maxZ = z + MAP.plotDepth / 2,
		})
	end
	return {
		entrances = entrances,
		entranceWidth = MAP.entranceWidth,
		plotWidth = MAP.plotWidth,
		groundY = WALKWAY_TOP,
		wallTopY = FLOOR_TOP + MAP.wallHeight,
		beltLength = Gameplay.belt.length,
		beltWidth = Gameplay.belt.width,
		walkwayWidth = MAP.walkwayWidth,
	},
		rects
end

local function theme(): Types.SeasonTheme
	return Seasons.themes[Seasons.eventThemes.Halloween2026]
end

local function cloneConfig(): Types.SeasonsConfig
	local halloween = theme()
	local copy = table.clone(halloween)
	copy.decorations = table.clone(halloween.decorations)
	copy.palette = table.clone(halloween.palette)
	return {
		eventThemes = table.clone(Seasons.eventThemes),
		themes = { halloween = copy },
		maxParts = Seasons.maxParts,
		transitionSeconds = Seasons.transitionSeconds,
	}
end

T.describe("SeasonRules.activeTheme", function()
	local config = cloneConfig()
	local winter = table.clone(theme())
	winter.priority = 5
	config.themes.winter = winter
	config.eventThemes.Winter = "winter"
	config.eventThemes.HalloweenEncore = "halloween"

	T.it("is off when no themed event runs", function()
		T.expect((SeasonRules.activeTheme(config, {}))).toBeNil()
		T.expect((SeasonRules.activeTheme(config, { HalloweenLuck2026 = true, LaunchWeekendLuck = true }))).toBeNil()
		T.expect((SeasonRules.activeTheme(config, { Halloween2026 = false }))).toBeNil()
	end)
	T.it("turns on the theme of the active event", function()
		local themeId, eventId = SeasonRules.activeTheme(config, { Halloween2026 = true, HalloweenLuck2026 = true })
		T.expect(themeId).toBe("halloween")
		T.expect(eventId).toBe("Halloween2026")
	end)
	T.it("picks the highest priority, then the alphabetically first event", function()
		T.expect((SeasonRules.activeTheme(config, { Halloween2026 = true, Winter = true }))).toBe("winter")
		local _, eventId = SeasonRules.activeTheme(config, { HalloweenEncore = true, Halloween2026 = true })
		T.expect(eventId).toBe("Halloween2026")
	end)
	T.it("finds the theme of an event for its colours", function()
		T.expect(SeasonRules.themeForEvent(Seasons, "Halloween2026")).toBe(theme())
		T.expect(SeasonRules.themeForEvent(Seasons, "Nope")).toBeNil()
		T.expect(SeasonRules.themeForEvent(Seasons, nil)).toBeNil()
	end)
end)

T.describe("SeasonRules.layout (Halloween on the real map)", function()
	local map, rects = realMap()
	local halloween = theme()
	local props = SeasonRules.layout(halloween.decorations, halloween.palette, map)

	T.it("stays within the part budget", function()
		T.expect(SeasonRules.partCount(props)).toBeAtMost(Seasons.maxParts)
		T.expect(SeasonRules.partCount(props)).toBeLessThan(250)
	end)
	T.it("places the configured number of each prop", function()
		local counts: { [string]: number } = {}
		for _, prop in props do
			counts[prop.kind] = (counts[prop.kind] or 0) + 1
		end
		local d = halloween.decorations
		T.expect(counts.pumpkin)
			.toBe((d.pumpkinsPerPlot :: number) * MAP.plotCount + 2 * (d.beltPumpkinsPerSide :: number))
		T.expect(counts.bulb).toBe((d.bulbsPerPlot :: number) * MAP.plotCount)
		T.expect(counts.lamp).toBe(2 * (MAP.plotsPerSide - 1))
		T.expect(counts.bat).toBe(d.bats)
		T.expect(counts.ghost).toBe(d.ghosts)
	end)
	T.it("never puts anything inside a plot, on the belt or on the lobby spawn", function()
		local lobby = MAP.lobby -- the spawn plaza (Config/Scenery); MapBuilder puts LobbySpawn there
		for _, prop in props do
			for _, rect in rects do
				local inside = prop.x > rect.minX - 0.5
					and prop.x < rect.maxX + 0.5
					and prop.z > rect.minZ - 0.5
					and prop.z < rect.maxZ + 0.5
				if inside then
					error(`{prop.kind} at ({prop.x}, {prop.z}) is inside a plot`)
				end
			end
			if prop.y < 12 then
				T.expect(math.abs(prop.z)).toBeGreaterThan(Gameplay.belt.width / 2 + 0.8)
			end
			T.expect(math.sqrt((prop.x - lobby.x) ^ 2 + (prop.z - lobby.z) ^ 2)).toBeGreaterThan(6)
			T.expect(prop.faceX ^ 2 + prop.faceZ ^ 2).toBeNear(1, 1e-9)
		end
	end)
	T.it("faces every pumpkin and bulb towards the walkway and alternates bulb colours", function()
		local previous: string? = nil
		for _, prop in props do
			if prop.kind == "bulb" then
				T.expect(prop.color ~= nil).toBe(true)
				T.expect(prop.color ~= previous or #halloween.palette.bulbs == 1).toBe(true)
				previous = prop.color
				-- bulbs hang just under the wall top
				T.expect(prop.y).toBeLessThan(FLOOR_TOP + MAP.wallHeight)
				T.expect(prop.y).toBeGreaterThan(FLOOR_TOP + MAP.wallHeight - 2)
			end
			if prop.kind == "pumpkin" or prop.kind == "bulb" then
				-- the walkway runs between the belt rails and the plot fronts: props at the plots face the belt
				-- (towards z = 0), props at the belt face away from it
				local atBelt = math.abs(prop.z) < MAP.walkwayWidth / 2
				if atBelt then
					T.expect(prop.faceZ * prop.z).toBeGreaterThan(0)
				else
					T.expect(prop.faceZ * prop.z).toBeLessThan(0)
				end
			end
		end
	end)
	T.it("is deterministic", function()
		T.expect(SeasonRules.layout(halloween.decorations, halloween.palette, map)).toEqual(props)
	end)
	T.it("builds nothing for an empty theme", function()
		T.expect(#SeasonRules.layout({}, { bulbs = {} }, map)).toBe(0)
	end)
end)

T.describe("SeasonRules.validate", function()
	local map = realMap()
	T.it("accepts the shipped config", function()
		local problems = SeasonRules.validate(Seasons, map)
		if #problems > 0 then
			print(table.concat(problems, "\n"))
		end
		T.expect(#problems).toBe(0)
	end)
	T.it("every themed event is a configured LiveOps event", function()
		for eventId in Seasons.eventThemes do
			local found = false
			for _, event in LiveOps.events do
				found = found or event.id == eventId
			end
			if not found then
				error(`Config/Seasons maps {eventId}, which is not in Config/LiveOps events`)
			end
		end
	end)
	T.it("reports broken themes", function()
		local function problemsWith(edit: (Types.SeasonsConfig, Types.SeasonTheme) -> ()): number
			local config = cloneConfig()
			edit(config, config.themes.halloween)
			return #SeasonRules.validate(config, map)
		end
		T.expect(problemsWith(function(config)
			config.eventThemes.Other = "missing"
		end)).toBe(1)
		T.expect(problemsWith(function(_, t)
			t.accentColor = "orange"
		end)).toBe(1)
		T.expect(problemsWith(function(_, t)
			t.palette.bulbs = { "#FF8C1A", "purple" }
		end)).toBe(1)
		T.expect(problemsWith(function(_, t)
			t.decorations.bats = 1.5
		end)).toBe(1)
		T.expect(problemsWith(function(_, t)
			t.decorations.bulbsPerPlot = 200 -- 1,600 bulbs: over the part budget
		end)).toBe(1)
		T.expect(problemsWith(function(config)
			config.transitionSeconds = -1
		end)).toBe(1)
		T.expect(problemsWith(function(_, t)
			local lighting = table.clone(t.lighting :: Types.SeasonLighting)
			lighting.clockTime = 25
			lighting.atmosphere = table.clone(lighting.atmosphere)
			lighting.atmosphere.density = 2
			t.lighting = lighting
		end)).toBe(2)
		T.expect(problemsWith(function(_, t)
			t.lighting = nil -- decorations only: fine
		end)).toBe(0)
	end)
end)

return nil
