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

local function theme(eventId: string?): Types.SeasonTheme
	return Seasons.themes[Seasons.eventThemes[eventId or "Halloween2026"]]
end

-- A copy of the shipped config whose themes (decorations and palettes) can be edited freely.
local function cloneConfig(): Types.SeasonsConfig
	local themes: { [string]: Types.SeasonTheme } = {}
	for id, original in Seasons.themes do
		local copy = table.clone(original)
		copy.decorations = table.clone(original.decorations)
		copy.palette = table.clone(original.palette)
		themes[id] = copy
	end
	return {
		eventThemes = table.clone(Seasons.eventThemes),
		themes = themes,
		maxParts = Seasons.maxParts,
		transitionSeconds = Seasons.transitionSeconds,
	}
end

-- Every prop of `props` of each kind.
local function countKinds(props: { SeasonRules.Prop }): { [string]: number }
	local counts: { [string]: number } = {}
	for _, prop in props do
		counts[prop.kind] = (counts[prop.kind] or 0) + 1
	end
	return counts
end

-- The checks every theme's layout must pass on the real map: nothing inside a plot, on the belt or on the lobby
-- spawn, and every prop facing a horizontal unit direction.
local function expectClearOfGameplay(props: { SeasonRules.Prop }, rects: { Rect })
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
		local counts = countKinds(props)
		local d = halloween.decorations
		T.expect(counts.pumpkin)
			.toBe((d.pumpkinsPerPlot :: number) * MAP.plotCount + 2 * (d.beltPumpkinsPerSide :: number))
		T.expect(counts.bulb).toBe((d.bulbsPerPlot :: number) * MAP.plotCount)
		T.expect(counts.lamp).toBe(2 * (MAP.plotsPerSide - 1))
		T.expect(counts.bat).toBe(d.bats)
		T.expect(counts.ghost).toBe(d.ghosts)
	end)
	T.it("never puts anything inside a plot, on the belt or on the lobby spawn", function()
		expectClearOfGameplay(props, rects)
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
	T.it("keeps the Halloween layout of earlier releases (220 parts)", function()
		T.expect(SeasonRules.partCount(props)).toBe(220)
	end)
end)

T.describe("SeasonRules.layout (Winter on the real map)", function()
	local map, rects = realMap()
	local winter = theme("Winter2026")
	local d = winter.decorations
	local props = SeasonRules.layout(d, winter.palette, map)
	local counts = countKinds(props)

	T.it("is switched on by Winter2026 and snows", function()
		T.expect((SeasonRules.activeTheme(Seasons, { Winter2026 = true, WinterLuck2026 = true }))).toBe("winter")
		T.expect(winter.weather).toBe("snow")
	end)
	T.it("stays within the part budget", function()
		T.expect(SeasonRules.partCount(props)).toBeAtMost(Seasons.maxParts)
		T.expect(SeasonRules.partCount(props)).toBe(380)
	end)
	T.it("places the configured number of each prop, and nothing from Halloween", function()
		T.expect(counts.present)
			.toBe((d.presentsPerPlot :: number) * MAP.plotCount + 2 * (d.beltPresentsPerSide :: number))
		T.expect(counts.bulb).toBe((d.bulbsPerPlot :: number) * MAP.plotCount)
		T.expect(counts.tree).toBe(2 * (MAP.plotsPerSide - 1))
		T.expect(counts.snowman).toBe(d.snowmen)
		T.expect(counts.snowflake).toBe(d.snowflakes)
		T.expect(counts.snowPile).toBe((d.snowPilesPerPlot :: number) * MAP.plotCount)
		for _, kind in { "pumpkin", "lamp", "bat", "ghost" } do
			T.expect(counts[kind]).toBeNil()
		end
	end)
	T.it("never puts anything inside a plot, on the belt or on the lobby spawn", function()
		expectClearOfGameplay(props, rects)
	end)
	T.it("wraps presents in cycling colours and ribbons, turned a little each", function()
		local wraps: { [string]: boolean } = {}
		local turned = 0
		for _, prop in props do
			if prop.kind == "present" then
				T.expect(table.find(winter.palette.presents :: { string }, prop.color :: string) ~= nil).toBe(true)
				T.expect(table.find(winter.palette.ribbons :: { string }, prop.color2 :: string) ~= nil).toBe(true)
				wraps[prop.color :: string] = true
				if math.abs(prop.faceX) > 1e-6 then
					turned += 1
				end
			end
		end
		local distinct = 0
		for _ in wraps do
			distinct += 1
		end
		T.expect(distinct).toBe(#(winter.palette.presents :: { string }))
		T.expect(turned).toBeGreaterThan(0)
	end)
	T.it("stands the trees in the grass between bases, behind the plot fronts", function()
		for _, prop in props do
			if prop.kind == "tree" then
				-- further from the belt than the plot fronts, and clear of both neighbouring plots' walls
				T.expect(math.abs(prop.z)).toBeGreaterThan(MAP.walkwayWidth + 3)
				for _, rect in rects do
					if prop.z > rect.minZ and prop.z < rect.maxZ then
						local gap = math.min(math.abs(prop.x - rect.minX), math.abs(prop.x - rect.maxX))
						T.expect(gap).toBeGreaterThan(MAP.plotGap / 2 - 0.5)
					end
				end
			end
		end
	end)
	T.it("hangs the snowflakes above head height and stands the snowmen past the belt ends", function()
		for _, prop in props do
			if prop.kind == "snowflake" then
				T.expect(prop.y).toBeGreaterThan(15)
				T.expect(math.abs(prop.z)).toBeLessThan(MAP.walkwayWidth)
			elseif prop.kind == "snowman" then
				T.expect(math.abs(prop.x)).toBeGreaterThan(Gameplay.belt.length / 2)
				T.expect(prop.y).toBe(map.groundY)
				T.expect(prop.faceX * prop.x).toBeLessThan(0) -- looking back at the belt
			end
		end
	end)
	T.it("puts the snowdrifts against the front walls, near their ends", function()
		for _, prop in props do
			if prop.kind == "snowPile" then
				T.expect(math.abs(prop.z)).toBeLessThan(MAP.walkwayWidth)
				T.expect(math.abs(prop.z)).toBeGreaterThan(MAP.walkwayWidth - 2)
			end
		end
	end)
	T.it("never stacks two props on the same spot", function()
		for i, a in props do
			for j = i + 1, #props do
				local b = props[j]
				local apart = math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2)
				if apart < 1.5 then
					error(`{a.kind} and {b.kind} share the spot ({a.x}, {a.y}, {a.z})`)
				end
			end
		end
	end)
	T.it("lets pumpkins and presents share a theme without overlapping", function()
		local both = table.clone(d)
		both.pumpkinsPerPlot = 2
		both.beltPumpkinsPerSide = 2
		both.ghosts = 2
		local mixed = SeasonRules.layout(both, winter.palette, map)
		local mixedCounts = countKinds(mixed)
		T.expect(mixedCounts.pumpkin).toBe(2 * MAP.plotCount + 4)
		T.expect(mixedCounts.present).toBe(counts.present)
		T.expect(mixedCounts.ghost).toBe(2)
		T.expect(mixedCounts.snowman).toBe(counts.snowman)
		for i, a in mixed do
			for j = i + 1, #mixed do
				local b = mixed[j]
				T.expect(math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2)).toBeGreaterThan(1.5)
			end
		end
	end)
end)

T.describe("SeasonRules.layout (Valentine's on the real map)", function()
	local map, rects = realMap()
	local valentine = theme("Valentine2027")
	local d = valentine.decorations
	local props = SeasonRules.layout(d, valentine.palette, map)
	local counts = countKinds(props)

	T.it("is switched on by Valentine2027 and drops petals", function()
		T.expect((SeasonRules.activeTheme(Seasons, { Valentine2027 = true, ValentineLuck2027 = true })))
			.toBe("valentine")
		T.expect(valentine.weather).toBe("petals")
	end)
	T.it("stays within the part budget", function()
		T.expect(SeasonRules.partCount(props)).toBeAtMost(Seasons.maxParts)
		T.expect(SeasonRules.partCount(props)).toBe(280)
	end)
	T.it("places the configured number of each prop, and nothing from the other seasons", function()
		T.expect(counts.rosePot).toBe((d.rosesPerPlot :: number) * MAP.plotCount + 2 * (d.beltRosesPerSide :: number))
		T.expect(counts.bulb).toBe((d.bulbsPerPlot :: number) * MAP.plotCount)
		T.expect(counts.lamp).toBe(2 * (MAP.plotsPerSide - 1))
		T.expect(counts.heartBalloon).toBe(d.heartBalloons)
		T.expect(counts.giantHeart).toBe(d.giantHearts)
		for _, kind in { "pumpkin", "present", "tree", "snowman", "snowflake", "snowPile", "bat", "ghost" } do
			T.expect(counts[kind]).toBeNil()
		end
	end)
	T.it("never puts anything inside a plot, on the belt or on the lobby spawn", function()
		expectClearOfGameplay(props, rects)
	end)
	T.it("colours the roses and balloons from their lists, facing the walkway", function()
		for _, prop in props do
			if prop.kind == "rosePot" then
				T.expect(table.find(valentine.palette.roses :: { string }, prop.color :: string) ~= nil).toBe(true)
				T.expect(table.find(valentine.palette.roses :: { string }, prop.color2 :: string) ~= nil).toBe(true)
				local atBelt = math.abs(prop.z) < MAP.walkwayWidth / 2
				if atBelt then
					T.expect(prop.faceZ * prop.z).toBeGreaterThan(0)
				else
					T.expect(prop.faceZ * prop.z).toBeLessThan(0)
				end
			elseif prop.kind == "heartBalloon" then
				T.expect(table.find(valentine.palette.balloons :: { string }, prop.color :: string) ~= nil).toBe(true)
				-- above head height, over the walkway, facing across the belt
				T.expect(prop.y).toBeGreaterThan(10)
				T.expect(math.abs(prop.z)).toBeLessThan(MAP.walkwayWidth)
				T.expect(prop.faceZ * prop.z).toBeLessThan(0)
			end
		end
	end)
	T.it("stands the giant hearts past the belt ends, clear of the factory and the chute", function()
		for _, prop in props do
			if prop.kind == "giantHeart" then
				T.expect(math.abs(prop.x)).toBeGreaterThan(Gameplay.belt.length / 2)
				T.expect(prop.y).toBe(map.groundY)
				T.expect(prop.faceX * prop.x).toBeLessThan(0) -- looking back at the belt
				-- the heart is 6.5 studs wide, across the walkway: its near edge stays clear of the factory intake
				-- and the chute (|z| up to 7)
				T.expect(math.abs(prop.z) - 3.25).toBeGreaterThan(7)
			end
		end
	end)
	T.it("never stacks two props on the same spot", function()
		for i, a in props do
			for j = i + 1, #props do
				local b = props[j]
				local apart = math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2)
				if apart < 1.5 then
					error(`{a.kind} and {b.kind} share the spot ({a.x}, {a.y}, {a.z})`)
				end
			end
		end
	end)
	T.it("shares the spots with every other prop without overlapping", function()
		local everything = table.clone(d)
		everything.pumpkinsPerPlot = 1
		everything.presentsPerPlot = 1
		everything.beltPumpkinsPerSide = 1
		everything.beltPresentsPerSide = 1
		everything.snowmen = 4
		everything.bats = 6
		everything.snowflakes = 8
		local mixed = SeasonRules.layout(everything, valentine.palette, map)
		local mixedCounts = countKinds(mixed)
		T.expect(mixedCounts.rosePot).toBe(counts.rosePot)
		T.expect(mixedCounts.giantHeart).toBe(counts.giantHeart)
		T.expect(mixedCounts.snowman).toBe(4)
		for i, a in mixed do
			for j = i + 1, #mixed do
				local b = mixed[j]
				T.expect(math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2)).toBeGreaterThan(1.5)
			end
		end
	end)
end)

T.describe("SeasonRules.layout (Easter on the real map)", function()
	local map, rects = realMap()
	local spring = theme("Easter2027")
	local d = spring.decorations
	local props = SeasonRules.layout(d, spring.palette, map)
	local counts = countKinds(props)

	T.it("is switched on by Easter2027 and drops blossom", function()
		T.expect((SeasonRules.activeTheme(Seasons, { Easter2027 = true, EasterLuck2027 = true }))).toBe("spring")
		T.expect(spring.weather).toBe("blossoms")
	end)
	T.it("stays within the part budget", function()
		T.expect(SeasonRules.partCount(props)).toBeAtMost(Seasons.maxParts)
		T.expect(SeasonRules.partCount(props)).toBe(330)
	end)
	T.it("places the configured number of each prop, and nothing from the other seasons", function()
		T.expect(counts.easterEgg).toBe((d.eggsPerPlot :: number) * MAP.plotCount + 2 * (d.beltEggsPerSide :: number))
		T.expect(counts.bulb).toBe((d.bulbsPerPlot :: number) * MAP.plotCount)
		T.expect(counts.lamp).toBe(2 * (MAP.plotsPerSide - 1))
		T.expect(counts.blossomTree).toBe(2 * (MAP.plotsPerSide - 1))
		T.expect(counts.butterfly).toBe(d.butterflies)
		T.expect(counts.chocolateBunny).toBe(d.chocolateBunnies)
		for _, kind in
			{
				"pumpkin",
				"present",
				"tree",
				"snowman",
				"snowflake",
				"snowPile",
				"bat",
				"ghost",
				"rosePot",
				"heartBalloon",
				"giantHeart",
			}
		do
			T.expect(counts[kind]).toBeNil()
		end
	end)
	T.it("never puts anything inside a plot, on the belt or on the lobby spawn", function()
		expectClearOfGameplay(props, rects)
	end)
	T.it("paints each egg in two different colours from its lists, facing about the walkway", function()
		for _, prop in props do
			if prop.kind == "easterEgg" then
				T.expect(table.find(spring.palette.eggs :: { string }, prop.color :: string) ~= nil).toBe(true)
				T.expect(table.find(spring.palette.eggStripes :: { string }, prop.color2 :: string) ~= nil).toBe(true)
				T.expect(prop.color ~= prop.color2).toBe(true)
				local atBelt = math.abs(prop.z) < MAP.walkwayWidth / 2
				if atBelt then
					T.expect(prop.faceZ * prop.z).toBeGreaterThan(0)
					T.expect(prop.scale).toBe(0.7)
				else
					-- turned a little each, but still looking out at the walkway
					T.expect(prop.faceZ * prop.z).toBeLessThan(0)
					T.expect(math.abs(prop.faceZ)).toBeGreaterThan(0.9)
					T.expect(prop.scale).toBe(1)
				end
			end
		end
	end)
	T.it("stands the blossom trees in the grass between bases, in two colours each", function()
		for _, prop in props do
			if prop.kind == "blossomTree" then
				T.expect(math.abs(prop.z)).toBeGreaterThan(MAP.walkwayWidth + 3)
				for _, rect in rects do
					if prop.z > rect.minZ and prop.z < rect.maxZ then
						-- its blossom reaches 4.3 studs out from the trunk
						local gap = math.min(math.abs(prop.x - rect.minX), math.abs(prop.x - rect.maxX))
						T.expect(gap).toBeGreaterThan(4.5)
					end
				end
				T.expect(table.find(spring.palette.blossoms :: { string }, prop.color :: string) ~= nil).toBe(true)
				T.expect(prop.color ~= prop.color2).toBe(true)
			end
		end
	end)
	T.it("hovers the butterflies above head height over the walkway, below the balloons' height", function()
		for _, prop in props do
			if prop.kind == "butterfly" then
				T.expect(prop.y).toBeGreaterThan(8)
				T.expect(prop.y).toBeLessThan(12)
				T.expect(math.abs(prop.z)).toBeLessThan(MAP.walkwayWidth - 4)
				T.expect(math.abs(prop.z)).toBeGreaterThan(Gameplay.belt.width / 2 + 3)
				T.expect(table.find(spring.palette.butterflies :: { string }, prop.color :: string) ~= nil).toBe(true)
			end
		end
	end)
	T.it("sits the chocolate bunnies past the belt ends, clear of the factory and the chute", function()
		for _, prop in props do
			if prop.kind == "chocolateBunny" then
				T.expect(math.abs(prop.x)).toBeGreaterThan(Gameplay.belt.length / 2)
				T.expect(prop.y).toBe(map.groundY)
				T.expect(prop.faceX * prop.x).toBeLessThan(0) -- looking back at the belt
				-- the bunny is 3.4 studs wide at scale 1: its near side stays clear of the factory intake and the chute
				T.expect(math.abs(prop.z) - 1.7 * prop.scale).toBeGreaterThan(7)
			end
		end
	end)
	T.it("never stacks two props on the same spot", function()
		for i, a in props do
			for j = i + 1, #props do
				local b = props[j]
				local apart = math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2)
				if apart < 1.5 then
					error(`{a.kind} and {b.kind} share the spot ({a.x}, {a.y}, {a.z})`)
				end
			end
		end
	end)
	T.it("shares the spots with every other prop without overlapping", function()
		local everything = table.clone(d)
		everything.pumpkinsPerPlot = 1
		everything.presentsPerPlot = 1
		everything.rosesPerPlot = 1
		everything.beltPumpkinsPerSide = 1
		everything.beltPresentsPerSide = 1
		everything.beltRosesPerSide = 1
		everything.treesBetweenPlots = true
		everything.snowmen = 4
		everything.giantHearts = 4
		everything.bats = 6
		everything.snowflakes = 8
		everything.heartBalloons = 10
		local mixed = SeasonRules.layout(everything, spring.palette, map)
		local mixedCounts = countKinds(mixed)
		T.expect(mixedCounts.easterEgg).toBe(counts.easterEgg)
		T.expect(mixedCounts.blossomTree).toBe(counts.blossomTree)
		T.expect(mixedCounts.chocolateBunny).toBe(counts.chocolateBunny)
		T.expect(mixedCounts.tree).toBe(counts.blossomTree)
		for i, a in mixed do
			for j = i + 1, #mixed do
				local b = mixed[j]
				T.expect(math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2)).toBeGreaterThan(1.5)
			end
		end
		-- with decorated trees there too, the blossom trees stand further back
		for _, prop in mixed do
			if prop.kind == "blossomTree" then
				T.expect(math.abs(prop.z)).toBeGreaterThan(MAP.walkwayWidth + 12)
			end
		end
	end)
end)

T.describe("SeasonRules.layout (Harvest Feast on the real map)", function()
	local map, rects = realMap()
	local harvest = theme("Harvest2026")
	local d = harvest.decorations
	local props = SeasonRules.layout(d, harvest.palette, map)
	local counts = countKinds(props)
	local function apart(a: SeasonRules.Prop, b: SeasonRules.Prop): number
		return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2)
	end

	T.it("is switched on by Harvest2026 and drops autumn leaves", function()
		T.expect((SeasonRules.activeTheme(Seasons, { Harvest2026 = true, HarvestLuck2026 = true }))).toBe("harvest")
		T.expect(harvest.weather).toBe("leaves")
	end)
	T.it("stays within the part budget", function()
		T.expect(SeasonRules.partCount(props)).toBeAtMost(Seasons.maxParts)
		T.expect(SeasonRules.partCount(props)).toBe(386)
	end)
	T.it("places the configured number of each prop, and nothing from the other seasons", function()
		T.expect(counts.pumpkin).toBe((d.pumpkinsPerPlot :: number) * MAP.plotCount)
		T.expect(counts.hayBale).toBe((d.hayBalesPerPlot :: number) * MAP.plotCount)
		T.expect(counts.bulb).toBe((d.bulbsPerPlot :: number) * MAP.plotCount)
		T.expect(counts.lamp).toBe(2 * (MAP.plotsPerSide - 1))
		T.expect(counts.scarecrow).toBe(2 * (MAP.plotsPerSide - 1))
		T.expect(counts.cornucopia).toBe(2 * (d.beltCornucopiasPerSide :: number))
		T.expect(counts.cornStalk).toBe(d.cornStalks)
		for _, kind in
			{
				"present",
				"tree",
				"snowman",
				"snowflake",
				"snowPile",
				"bat",
				"ghost",
				"rosePot",
				"heartBalloon",
				"giantHeart",
				"easterEgg",
				"chocolateBunny",
				"blossomTree",
				"butterfly",
			}
		do
			T.expect(counts[kind]).toBeNil()
		end
	end)
	T.it("never puts anything inside a plot, on the belt or on the lobby spawn", function()
		expectClearOfGameplay(props, rects)
	end)
	T.it("carves no faces into its pumpkins: without a face colour they are plain harvest ones", function()
		T.expect(harvest.palette.pumpkinFace).toBeNil()
		local paletteKeys = SeasonRules.PALETTE_KEYS :: { [any]: { string } }
		T.expect(table.find(paletteKeys.pumpkin, "pumpkinFace")).toBeNil()
		-- Halloween's keep their glowing faces
		T.expect(theme().palette.pumpkinFace ~= nil).toBe(true)
	end)
	T.it("sets pumpkins beside the entrances and hay bales beyond them, looking out at the walkway", function()
		for _, prop in props do
			if prop.kind == "pumpkin" or prop.kind == "hayBale" then
				T.expect(math.abs(prop.z)).toBeLessThan(MAP.walkwayWidth)
				T.expect(math.abs(prop.z)).toBeGreaterThan(MAP.walkwayWidth - 3)
				T.expect(prop.faceZ * prop.z).toBeLessThan(0)
				T.expect(math.abs(prop.faceZ)).toBeGreaterThan(0.98) -- bales a little crooked, never sideways
			end
		end
		-- a bale (3.4 studs long) never touches a pumpkin (2.8 across)
		for _, bale in props do
			if bale.kind == "hayBale" then
				for _, pumpkin in props do
					if pumpkin.kind == "pumpkin" then
						T.expect(apart(bale, pumpkin)).toBeGreaterThan(1.7 + 1.4 + 0.5)
					end
				end
			end
		end
	end)
	T.it("stands the scarecrows in the grass between bases, their arms clear of the walls", function()
		for _, prop in props do
			if prop.kind == "scarecrow" then
				T.expect(math.abs(prop.z)).toBeGreaterThan(MAP.walkwayWidth + 3)
				T.expect(prop.faceZ * prop.z).toBeLessThan(0) -- looking out at the walkway
				for _, rect in rects do
					if prop.z > rect.minZ and prop.z < rect.maxZ then
						-- its straw hands reach 3.2 studs out at scale 1
						local gap = math.min(math.abs(prop.x - rect.minX), math.abs(prop.x - rect.maxX))
						T.expect(gap).toBeGreaterThan(3.2 * prop.scale + 1)
					end
				end
			end
		end
	end)
	T.it("lays cornucopias along both belt rails, spilling the harvest towards the walkway", function()
		for _, prop in props do
			if prop.kind == "cornucopia" then
				T.expect(math.abs(prop.z)).toBeLessThan(MAP.walkwayWidth / 2)
				T.expect(prop.faceZ * prop.z).toBeGreaterThan(0)
				T.expect(prop.faceX).toBe(0)
				-- its woven lip is 2.2 studs across at scale 1: the belt side stays clear of the belt
				T.expect(math.abs(prop.z) - 1.11 * prop.scale).toBeGreaterThan(Gameplay.belt.width / 2 + 0.5)
			end
		end
	end)
	T.it("stands the giant corn stalks past the belt ends, clear of the factory and the chute", function()
		for _, prop in props do
			if prop.kind == "cornStalk" then
				T.expect(math.abs(prop.x)).toBeGreaterThan(Gameplay.belt.length / 2)
				T.expect(prop.y).toBe(map.groundY)
				T.expect(prop.faceX * prop.x).toBeLessThan(0) -- looking back at the belt
				-- its leaves reach 3.55 studs out at scale 1: the nearest stays clear of the factory intake and the
				-- chute (|z| up to 7)
				T.expect(math.abs(prop.z) - 3.55 * prop.scale).toBeGreaterThan(7)
			end
		end
	end)
	T.it("never stacks two props on the same spot", function()
		for i, a in props do
			for j = i + 1, #props do
				local b = props[j]
				if apart(a, b) < 1.5 then
					error(`{a.kind} and {b.kind} share the spot ({a.x}, {a.y}, {a.z})`)
				end
			end
		end
	end)
	T.it("shares the spots with every other prop without overlapping", function()
		local everything = table.clone(d)
		everything.presentsPerPlot = 1
		everything.rosesPerPlot = 1
		everything.eggsPerPlot = 1
		everything.snowPilesPerPlot = 2
		everything.beltPumpkinsPerSide = 1
		everything.beltPresentsPerSide = 1
		everything.beltRosesPerSide = 1
		everything.beltEggsPerSide = 1
		everything.treesBetweenPlots = true
		everything.blossomTreesBetweenPlots = true
		everything.snowmen = 4
		everything.giantHearts = 4
		everything.chocolateBunnies = 4
		everything.ghosts = 4
		everything.bats = 6
		everything.snowflakes = 8
		everything.heartBalloons = 10
		everything.butterflies = 12
		local mixed = SeasonRules.layout(everything, harvest.palette, map)
		local mixedCounts = countKinds(mixed)
		for _, kind in { "pumpkin", "hayBale", "scarecrow", "cornucopia", "cornStalk" } do
			T.expect(mixedCounts[kind] >= counts[kind]).toBe(true)
		end
		T.expect(mixedCounts.hayBale).toBe(counts.hayBale)
		T.expect(mixedCounts.cornStalk).toBe(counts.cornStalk)
		for i, a in mixed do
			for j = i + 1, #mixed do
				T.expect(apart(a, mixed[j])).toBeGreaterThan(1.5)
			end
		end
		-- with decorated trees and blossom trees there too, the scarecrows stand behind both
		for _, prop in mixed do
			if prop.kind == "scarecrow" then
				T.expect(math.abs(prop.z)).toBeGreaterThan(MAP.walkwayWidth + 22)
			end
		end
	end)
end)

-- The nearest side wall of a plot beside `prop` on its side of the belt (the plots' fronts are at |z| = walkwayWidth).
local function sideWallGap(prop: SeasonRules.Prop, rects: { Rect }): number
	local nearest = math.huge
	for _, rect in rects do
		if (rect.minZ > 0) == (prop.z > 0) then
			nearest = math.min(nearest, math.abs(prop.x - rect.minX), math.abs(prop.x - rect.maxX))
		end
	end
	return nearest
end

-- Every other theme's props switched on beside `d`'s own (a theme is only data, so any mix must work).
local function withEverything(d: Types.SeasonDecorations): Types.SeasonDecorations
	local everything = table.clone(d)
	for key, value in
		{
			pumpkinsPerPlot = 1,
			presentsPerPlot = 1,
			rosesPerPlot = 1,
			eggsPerPlot = 1,
			hayBalesPerPlot = 1,
			cloverPatchesPerPlot = 1,
			swimRingsPerPlot = 1,
			beachBallsPerPlot = 1,
			snowPilesPerPlot = 2,
			bulbsPerPlot = 8,
			pennantsPerPlot = 12,
			beltPumpkinsPerSide = 1,
			beltPresentsPerSide = 1,
			beltRosesPerSide = 1,
			beltEggsPerSide = 1,
			beltCornucopiasPerSide = 1,
			beltPotsOfGoldPerSide = 1,
			beltBeachBallsPerSide = 1,
			snowmen = 4,
			giantHearts = 4,
			chocolateBunnies = 4,
			cornStalks = 4,
			sandcastles = 4,
			shamrocks = 4,
			ghosts = 4,
			bats = 6,
			snowflakes = 8,
			heartBalloons = 10,
			butterflies = 12,
		} :: { [string]: number }
	do
		if (everything :: any)[key] == nil then
			(everything :: any)[key] = value
		end
	end
	for _, key in
		{
			"lampsBetweenPlots",
			"treesBetweenPlots",
			"blossomTreesBetweenPlots",
			"scarecrowsBetweenPlots",
			"umbrellasBetweenPlots",
			"rainbowsBetweenPlots",
		}
	do
		(everything :: any)[key] = true
	end
	return everything
end

-- No two props of a layout on the same spot. Bunting hangs under a front wall's string lights, so a pennant may
-- come closer to a bulb, as long as it hangs clearly below it.
local function expectNoSharedSpots(props: { SeasonRules.Prop })
	for i, a in props do
		for j = i + 1, #props do
			local b = props[j]
			local apart = math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2)
			if (a.kind == "bulb" and b.kind == "pennant") or (a.kind == "pennant" and b.kind == "bulb") then
				local bulb, pennant = if a.kind == "bulb" then a else b, if a.kind == "bulb" then b else a
				if apart < 1.5 and bulb.y - pennant.y < 0.6 then
					error(`a pennant at ({pennant.x}, {pennant.y}, {pennant.z}) hangs into a string light`)
				end
			elseif apart < 1.5 then
				error(`{a.kind} and {b.kind} share the spot ({a.x}, {a.y}, {a.z})`)
			end
		end
	end
end

T.describe("SeasonRules.layout (Lucky Clover on the real map)", function()
	local map, rects = realMap()
	local clover = theme("StPatrick2027")
	local d = clover.decorations
	local props = SeasonRules.layout(d, clover.palette, map)
	local counts = countKinds(props)

	T.it("is switched on by StPatrick2027 (its luck weekend too) and drifts clover leaves", function()
		T.expect((SeasonRules.activeTheme(Seasons, { StPatrick2027 = true, StPatrickLuck2027 = true }))).toBe("clover")
		T.expect((SeasonRules.activeTheme(Seasons, { StPatrickLuck2027 = true }))).toBeNil()
		T.expect(clover.weather).toBe("clovers")
	end)
	T.it("stays within the part budget", function()
		T.expect(SeasonRules.partCount(props)).toBeAtMost(Seasons.maxParts)
		T.expect(SeasonRules.partCount(props)).toBe(398)
	end)
	T.it("places the configured number of each prop, and nothing from the other seasons", function()
		local gapCount = 2 * (MAP.plotsPerSide - 1)
		T.expect(counts.cloverPatch).toBe((d.cloverPatchesPerPlot :: number) * MAP.plotCount)
		T.expect(counts.bulb).toBe((d.bulbsPerPlot :: number) * MAP.plotCount)
		T.expect(counts.rainbow).toBe(gapCount)
		-- one at every rainbow's foot, and the little ones along the belt
		T.expect(counts.potOfGold).toBe(gapCount + 2 * (d.beltPotsOfGoldPerSide :: number))
		T.expect(counts.shamrock).toBe(d.shamrocks)
		local own = { cloverPatch = true, bulb = true, rainbow = true, potOfGold = true, shamrock = true }
		for kind in counts do
			if not own[kind] then
				error(`Lucky Clover places a {kind}`)
			end
		end
	end)
	T.it("never puts anything inside a plot, on the belt or on the lobby spawn", function()
		expectClearOfGameplay(props, rects)
	end)
	T.it("arches a rainbow over every grass gap between two bases, clear of both walls, facing the walkway", function()
		for _, prop in props do
			if prop.kind == "rainbow" then
				T.expect(math.abs(prop.z)).toBeGreaterThan(MAP.walkwayWidth + 3)
				T.expect(prop.faceZ * prop.z).toBeLessThan(0)
				T.expect(prop.y).toBe(map.groundY)
				-- its outer band reaches RAINBOW_RADIUS out either side of its middle
				T.expect(sideWallGap(prop, rects)).toBeGreaterThan(SeasonRules.RAINBOW_RADIUS * prop.scale + 1)
			end
		end
	end)
	T.it("stands a pot of gold at the right foot of every rainbow, a step in front of it", function()
		for _, rainbow in props do
			if rainbow.kind == "rainbow" then
				-- a frame facing (faceX, faceZ) has its right at (-faceZ, faceX)
				local footX = rainbow.x - rainbow.faceZ * SeasonRules.RAINBOW_FOOT * rainbow.scale
				local footZ = rainbow.z + rainbow.faceX * SeasonRules.RAINBOW_FOOT * rainbow.scale
				local found = 0
				for _, pot in props do
					if
						pot.kind == "potOfGold"
						and (pot.z > 0) == (rainbow.z > 0)
						and math.abs(pot.x - footX) < 0.01
					then
						found += 1
						T.expect(math.abs(pot.z - footZ)).toBeNear(1.2, 1e-9)
						T.expect(math.abs(pot.z)).toBeLessThan(math.abs(rainbow.z)) -- in front, towards the walkway
						T.expect(pot.faceZ).toBe(rainbow.faceZ)
						-- the cauldron is 2.5 studs across at scale 1
						T.expect(sideWallGap(pot, rects)).toBeGreaterThan(1.25 * pot.scale + 0.5)
					end
				end
				T.expect(found).toBe(1)
			end
		end
	end)
	T.it("sets the clover patches beside the entrances, looking out at the walkway", function()
		for _, prop in props do
			if prop.kind == "cloverPatch" then
				T.expect(math.abs(prop.z)).toBeLessThan(MAP.walkwayWidth)
				T.expect(math.abs(prop.z)).toBeGreaterThan(MAP.walkwayWidth - 3)
				T.expect(prop.faceZ * prop.z).toBeLessThan(0)
				T.expect(math.abs(prop.faceZ)).toBeGreaterThan(0.8) -- each clover turned its own way, never sideways
			end
		end
	end)
	T.it("lines little pots of gold along both belt rails, clear of the belt", function()
		local onRails = 0
		for _, prop in props do
			if prop.kind == "potOfGold" and math.abs(prop.z) < MAP.walkwayWidth / 2 then
				onRails += 1
				T.expect(prop.faceZ * prop.z).toBeGreaterThan(0)
				T.expect(prop.faceX).toBe(0)
				T.expect(prop.scale).toBeLessThan(1)
				T.expect(math.abs(prop.z) - 1.25 * prop.scale).toBeGreaterThan(Gameplay.belt.width / 2 + 0.5)
			end
		end
		T.expect(onRails).toBe(2 * (d.beltPotsOfGoldPerSide :: number))
	end)
	T.it("stands the giant shamrocks past the belt ends, clear of the factory and the chute", function()
		for _, prop in props do
			if prop.kind == "shamrock" then
				T.expect(math.abs(prop.x)).toBeGreaterThan(Gameplay.belt.length / 2)
				T.expect(prop.y).toBe(map.groundY)
				T.expect(prop.faceX * prop.x).toBeLessThan(0) -- looking back at the belt
				-- its leaves reach 3.15 studs out at scale 1: the nearest stays clear of the factory intake and the
				-- chute (|z| up to 7)
				T.expect(math.abs(prop.z) - 3.15 * prop.scale).toBeGreaterThan(7)
			end
		end
	end)
	T.it("never stacks two props on the same spot", function()
		expectNoSharedSpots(props)
	end)
	T.it("shares the spots with every other prop without overlapping", function()
		local mixed = SeasonRules.layout(withEverything(d), clover.palette, map)
		local mixedCounts = countKinds(mixed)
		T.expect(mixedCounts.cloverPatch).toBe(counts.cloverPatch)
		T.expect(mixedCounts.rainbow).toBe(counts.rainbow)
		T.expect(mixedCounts.shamrock).toBe(counts.shamrock)
		expectNoSharedSpots(mixed)
		expectClearOfGameplay(mixed, rects)
		-- with decorated trees, blossom trees and scarecrows there too, the rainbows arch behind all three, still
		-- inside the plots' depth
		for _, prop in mixed do
			if prop.kind == "rainbow" then
				T.expect(math.abs(prop.z)).toBeGreaterThan(MAP.walkwayWidth + 32)
				T.expect(math.abs(prop.z)).toBeLessThan(MAP.walkwayWidth + MAP.plotDepth - SeasonRules.RAINBOW_RADIUS)
			end
		end
	end)
end)

T.describe("SeasonRules.layout (Summer Splash on the real map)", function()
	local map, rects = realMap()
	local summer = theme("Summer2027")
	local d = summer.decorations
	local props = SeasonRules.layout(d, summer.palette, map)
	local counts = countKinds(props)

	T.it("is switched on by Summer2027 (its cash weekend too) and sparkles with spray", function()
		T.expect((SeasonRules.activeTheme(Seasons, { Summer2027 = true, SplashCash2027 = true }))).toBe("summer")
		T.expect((SeasonRules.activeTheme(Seasons, { SplashCash2027 = true }))).toBeNil()
		T.expect(summer.weather).toBe("spray")
	end)
	T.it("stays within the part budget", function()
		T.expect(SeasonRules.partCount(props)).toBeAtMost(Seasons.maxParts)
		T.expect(SeasonRules.partCount(props)).toBe(330)
	end)
	T.it("places the configured number of each prop, and nothing from the other seasons", function()
		T.expect(counts.swimRing).toBe((d.swimRingsPerPlot :: number) * MAP.plotCount)
		T.expect(counts.beachBall)
			.toBe((d.beachBallsPerPlot :: number) * MAP.plotCount + 2 * (d.beltBeachBallsPerSide :: number))
		T.expect(counts.pennant).toBe((d.pennantsPerPlot :: number) * MAP.plotCount)
		T.expect(counts.beachUmbrella).toBe(2 * (MAP.plotsPerSide - 1))
		T.expect(counts.sandcastle).toBe(d.sandcastles)
		local own = { swimRing = true, beachBall = true, pennant = true, beachUmbrella = true, sandcastle = true }
		for kind in counts do
			if not own[kind] then
				error(`Summer Splash places a {kind}`)
			end
		end
	end)
	T.it("never puts anything inside a plot, on the belt or on the lobby spawn", function()
		expectClearOfGameplay(props, rects)
	end)
	T.it("opens a beach umbrella at the walkway between every two bases, its canopy clear of both walls", function()
		for _, prop in props do
			if prop.kind == "beachUmbrella" then
				T.expect(math.abs(prop.z)).toBeLessThan(MAP.walkwayWidth)
				T.expect(math.abs(prop.z)).toBeGreaterThan(MAP.walkwayWidth - 3)
				T.expect(prop.faceZ * prop.z).toBeLessThan(0)
				-- the canopy (and the band round its rim) is 7.96 studs across at scale 1
				T.expect(sideWallGap(prop, rects)).toBeGreaterThan(3.98 * prop.scale + 1)
				T.expect(table.find(summer.palette.umbrellas :: { string }, prop.color :: string) ~= nil).toBe(true)
				T.expect(prop.color ~= prop.color2).toBe(true) -- a towel of another colour under it
			end
		end
	end)
	T.it("leans a swim ring on the wall beside every entrance, clear of the entrance", function()
		for _, prop in props do
			if prop.kind == "swimRing" then
				T.expect(math.abs(prop.z)).toBeLessThan(MAP.walkwayWidth)
				T.expect(math.abs(prop.z)).toBeGreaterThan(MAP.walkwayWidth - 1.5)
				T.expect(prop.faceZ * prop.z).toBeLessThan(0)
				T.expect(table.find(summer.palette.rings :: { string }, prop.color :: string) ~= nil).toBe(true)
				-- the ring is 3.55 studs across at scale 1: it stays beside the entrance, not in it
				local entranceGap = math.huge
				for _, entrance in map.entrances do
					if (entrance.z > 0) == (prop.z > 0) then
						entranceGap = math.min(entranceGap, math.abs(prop.x - entrance.x))
					end
				end
				T.expect(entranceGap - 1.78 * prop.scale).toBeGreaterThan(MAP.entranceWidth / 2)
			end
		end
	end)
	T.it(
		"rolls a beach ball beside every entrance and rests the rest along the belt rails, clear of the belt",
		function()
			local onRails = 0
			for _, prop in props do
				if prop.kind == "beachBall" then
					T.expect(table.find(summer.palette.ballPanels :: { string }, prop.color :: string) ~= nil)
						.toBe(true)
					if math.abs(prop.z) < MAP.walkwayWidth / 2 then
						onRails += 1
						T.expect(prop.scale).toBeLessThan(1)
						-- the ball is 2 studs across at scale 1
						T.expect(math.abs(prop.z) - prop.scale).toBeGreaterThan(Gameplay.belt.width / 2 + 0.5)
					else
						T.expect(math.abs(prop.z)).toBeGreaterThan(MAP.walkwayWidth - 3)
						T.expect(prop.scale).toBe(1)
					end
				end
			end
			T.expect(onRails).toBe(2 * (d.beltBeachBallsPerSide :: number))
		end
	)
	T.it("hangs bunting along both halves of every front wall, below its top, in cycling colours", function()
		local perPlot: { [number]: number } = {}
		local colors: { [string]: boolean } = {}
		for _, prop in props do
			if prop.kind == "pennant" then
				T.expect(math.abs(prop.z)).toBeNear(MAP.walkwayWidth - 0.5, 1e-9)
				T.expect(prop.y).toBeLessThan(map.wallTopY - 1)
				-- it hangs 1.3 studs below its top edge: the whole flag stays on the wall
				T.expect(prop.y - 1.3).toBeGreaterThan(FLOOR_TOP + 1)
				T.expect(prop.faceZ * prop.z).toBeLessThan(0)
				local found = false
				for index, entrance in map.entrances do
					local lateral = math.abs(prop.x - entrance.x)
					if (entrance.z > 0) == (prop.z > 0) and lateral < MAP.plotWidth / 2 then
						T.expect(lateral).toBeGreaterThan(MAP.entranceWidth / 2 + 0.5) -- never across the entrance
						perPlot[index] = (perPlot[index] or 0) + 1
						found = true
					end
				end
				T.expect(found).toBe(true)
				colors[prop.color :: string] = true
			end
		end
		for index = 1, MAP.plotCount do
			T.expect(perPlot[index]).toBe(d.pennantsPerPlot)
		end
		for _, color in summer.palette.pennants :: { string } do
			T.expect(colors[color]).toBe(true)
		end
	end)
	T.it("builds the sandcastles past the belt ends, clear of the factory and the chute", function()
		for _, prop in props do
			if prop.kind == "sandcastle" then
				T.expect(math.abs(prop.x)).toBeGreaterThan(Gameplay.belt.length / 2)
				T.expect(prop.y).toBe(map.groundY)
				T.expect(prop.faceX * prop.x).toBeLessThan(0) -- looking back at the belt
				-- its mound is 7.2 studs across at scale 1 (the bucket and spade lie in front of the castle, inside
				-- that): the near side stays clear of the factory intake and the chute (|z| up to 7)
				T.expect(math.abs(prop.z) - 3.6 * prop.scale).toBeGreaterThan(7)
			end
		end
	end)
	T.it("never stacks two props on the same spot", function()
		expectNoSharedSpots(props)
	end)
	T.it("shares the spots with every other prop without overlapping", function()
		local mixed = SeasonRules.layout(withEverything(d), summer.palette, map)
		local mixedCounts = countKinds(mixed)
		T.expect(mixedCounts.swimRing).toBe(counts.swimRing)
		T.expect(mixedCounts.pennant).toBe(counts.pennant)
		T.expect(mixedCounts.beachUmbrella).toBe(counts.beachUmbrella)
		T.expect(mixedCounts.sandcastle).toBe(counts.sandcastle)
		expectNoSharedSpots(mixed)
		expectClearOfGameplay(mixed, rects)
		-- with lamps at the walkway too, the umbrellas stand a little back in the grass gap
		for _, prop in mixed do
			if prop.kind == "beachUmbrella" then
				T.expect(math.abs(prop.z)).toBeGreaterThan(MAP.walkwayWidth)
				T.expect(sideWallGap(prop, rects)).toBeGreaterThan(3.98 * prop.scale + 1)
			end
		end
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
	T.it("asks only for the colours of the props a theme places", function()
		local function problemsWith(edit: (Types.SeasonTheme) -> ()): { string }
			local config = cloneConfig()
			edit(config.themes.winter)
			return SeasonRules.validate(config, map)
		end
		-- the winter theme places no pumpkins, so it needs no pumpkin colours
		T.expect(Seasons.themes.winter.palette.pumpkin).toBeNil()
		T.expect(#problemsWith(function(t)
			t.palette.ribbons = nil -- its presents need ribbons
		end)).toBe(1)
		T.expect(#problemsWith(function(t)
			t.palette.ornaments = {} -- an empty list counts as missing
		end)).toBe(1)
		T.expect(#problemsWith(function(t)
			-- pumpkins now, without pumpkin and stem colours (a face colour is optional: without one they are plain)
			t.decorations.beltPumpkinsPerSide = 1
		end)).toBe(2)
		T.expect(#problemsWith(function(t)
			(t.palette :: any).presnts = { "#FF0000" } -- a typo is not a palette colour
		end)).toBe(1)
		T.expect(#problemsWith(function(t)
			t.palette.snow = "white"
		end)).toBe(1)
		T.expect(#problemsWith(function(t)
			t.weather = "blizzard" :: any
		end)).toBe(1)
		T.expect(#problemsWith(function(t)
			t.decorations.snowmen = -1
		end)).toBe(1)
		T.expect(#problemsWith(function(t)
			t.weather = nil -- no weather of its own: the map's
		end)).toBe(0)
	end)
	T.it("names every palette key a prop kind needs, and builds every kind", function()
		local partsPer = SeasonRules.PARTS_PER :: { [any]: number }
		local paletteKeys = SeasonRules.PALETTE_KEYS :: { [any]: { string } }
		for kind, parts in partsPer do
			T.expect(parts).toBeGreaterThan(0)
			T.expect(#paletteKeys[kind]).toBeGreaterThan(0)
		end
		for kind in paletteKeys do
			T.expect(partsPer[kind] ~= nil).toBe(true)
		end
	end)
end)

return nil
