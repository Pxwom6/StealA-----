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
			t.decorations.beltPumpkinsPerSide = 1 -- pumpkins now, without pumpkin, pumpkinFace and stem colours
		end)).toBe(3)
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
