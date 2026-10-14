--!strict
local T = require("./TestKit")
local MapThemeRules = require("../src/shared/Logic/MapThemeRules")
local SceneryLayout = require("../src/shared/Logic/SceneryLayout")
local MapThemes = require("../src/shared/Config/MapThemes")
local Scenery = require("../src/shared/Config/Scenery")
local Gameplay = require("../src/shared/Config/Gameplay")
local Theme = require("../src/shared/Config/Theme")
local Types = require("../src/shared/Types")

-- What validate needs from the real scenery: every tree spot's kind and the part estimate with default trees.
local function treeKinds(): { string }
	local kinds: { string } = {}
	for _, tree in SceneryLayout.layout(Scenery).trees do
		table.insert(kinds, tree.kind)
	end
	return kinds
end

local function defaultParts(): number
	return SceneryLayout.partEstimate(Scenery, SceneryLayout.layout(Scenery), Gameplay.map, Gameplay.belt)
end

local function validate(config: Types.MapThemesConfig): { string }
	return MapThemeRules.validate(
		config,
		Theme.world,
		treeKinds(),
		#Scenery.landmarkSpots,
		defaultParts(),
		Scenery.partBudget
	)
end

-- A deep copy of the real config to break in one place.
local function copy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, item in value do
		result[key] = copy(item)
	end
	return result
end

local function mentions(problems: { string }, text: string): boolean
	for _, problem in problems do
		if string.find(problem, text, 1, true) then
			return true
		end
	end
	return false
end

-- Random numbers from a list, in order (then repeating the last).
local function sequence(values: { number }): () -> number
	local index = 0
	return function(): number
		index = math.min(index + 1, #values)
		return values[index]
	end
end

T.describe("MapThemeRules: the real config", function()
	T.it("is valid", function()
		local problems = validate(MapThemes)
		T.expect(#problems).toBe(0)
		if #problems > 0 then
			print(table.concat(problems, "\n"))
		end
	end)

	T.it("has eight maps, every one in the order once", function()
		local count = 0
		for _ in MapThemes.themes do
			count += 1
		end
		T.expect(count).toBe(8)
		T.expect(#MapThemes.order).toBe(8)
	end)

	T.it("keeps every map's scenery under the part budget", function()
		for id, theme in MapThemes.themes do
			local parts = defaultParts() + MapThemeRules.extraParts(theme, treeKinds(), #Scenery.landmarkSpots)
			T.expect(parts).toBeAtMost(Scenery.partBudget)
			T.expect(id ~= "").toBeTruthy()
		end
	end)

	T.it("never recolours gameplay", function()
		for _, theme in MapThemes.themes do
			for key in theme.palette do
				T.expect(MapThemeRules.FIXED_KEYS[key]).toBeNil()
			end
		end
	end)

	T.it("gives each map a different look", function()
		local seen: { [string]: string } = {}
		for id, theme in MapThemes.themes do
			local signature =
				`{theme.palette.ground or Theme.world.ground}|{theme.lighting.clockTime}|{theme.flora.round}`
			T.expect(seen[signature]).toBeNil()
			seen[signature] = id
		end
	end)
end)

T.describe("MapThemeRules.firstMap", function()
	T.it("is the configured map when firstMap names one", function()
		local config = copy(MapThemes)
		config.firstMap = "winter"
		T.expect(MapThemeRules.firstMap(config, sequence({ 0.99 }))).toBe("winter")
	end)

	T.it("is a weighted random map otherwise", function()
		local config = copy(MapThemes)
		config.firstMap = "random"
		T.expect(MapThemeRules.firstMap(config, sequence({ 0 }))).toBe(config.order[1])
		T.expect(MapThemeRules.firstMap(config, sequence({ 0.999 }))).toBe(config.order[#config.order])
	end)

	T.it("never picks a map with weight 0", function()
		local config = copy(MapThemes)
		config.firstMap = "random"
		for _, id in config.order do
			config.themes[id].weight = 0
		end
		config.themes.volcano.weight = 1
		for _, roll in { 0, 0.3, 0.7, 0.999 } do
			T.expect(MapThemeRules.firstMap(config, sequence({ roll }))).toBe("volcano")
		end
	end)
end)

T.describe("MapThemeRules.candidates", function()
	T.it("offers different maps, never the current one, in config order", function()
		for _, current in MapThemes.order do
			for _, roll in { 0, 0.25, 0.5, 0.75, 0.999 } do
				local list = MapThemeRules.candidates(MapThemes, current, 3, sequence({ roll, 1 - roll, roll / 2 }))
				T.expect(#list).toBe(3)
				local seen: { [string]: boolean } = {}
				local lastIndex = 0
				for _, id in list do
					T.expect(id ~= current).toBeTruthy()
					T.expect(seen[id]).toBeNil()
					seen[id] = true
					local index = table.find(MapThemes.order, id) :: number
					T.expect(index).toBeGreaterThan(lastIndex)
					lastIndex = index
				end
			end
		end
	end)

	T.it("offers fewer when there aren't enough maps", function()
		local config = copy(MapThemes)
		for _, id in config.order do
			config.themes[id].weight = 0
		end
		config.themes.candy.weight = 1
		config.themes.winter.weight = 1
		local list = MapThemeRules.candidates(config, "candy", 3, sequence({ 0.5 }))
		T.expect(#list).toBe(1)
		T.expect(list[1]).toBe("winter")
	end)
end)

T.describe("MapThemeRules votes", function()
	local ballot = { "candy", "winter", "desert" }

	T.it("counts only votes for a candidate", function()
		local counts = MapThemeRules.counts(ballot, { [1] = "winter", [2] = "winter", [3] = "desert", [4] = "meadow" })
		T.expect(counts).toEqual({ 0, 2, 1 })
	end)

	T.it("picks the most voted map", function()
		T.expect(MapThemeRules.winner(ballot, { [1] = "desert", [2] = "desert", [3] = "candy" }, sequence({ 0 })))
			.toBe("desert")
	end)

	T.it("settles a tie at random among the tied maps", function()
		local votes = { [1] = "candy", [2] = "desert" }
		T.expect(MapThemeRules.winner(ballot, votes, sequence({ 0 }))).toBe("candy")
		T.expect(MapThemeRules.winner(ballot, votes, sequence({ 0.99 }))).toBe("desert")
	end)

	T.it("picks any candidate when nobody voted", function()
		T.expect(MapThemeRules.winner(ballot, {}, sequence({ 0 }))).toBe("candy")
		T.expect(MapThemeRules.winner(ballot, {}, sequence({ 0.5 }))).toBe("winter")
		T.expect(MapThemeRules.winner(ballot, {}, sequence({ 0.99 }))).toBe("desert")
	end)

	T.it("has no winner without candidates", function()
		T.expect(MapThemeRules.winner({}, { [1] = "candy" }, sequence({ 0 }))).toBeNil()
	end)

	T.it("opens the vote voteSeconds before the change", function()
		T.expect(MapThemeRules.voteOpensAt(1000, MapThemes.rotation)).toBe(1000 - MapThemes.rotation.voteSeconds)
	end)
end)

T.describe("MapThemeRules flora and landmarks", function()
	T.it("grows the map's kind on each tree spot", function()
		local desert = MapThemes.themes.desert
		T.expect(MapThemeRules.floraFor(desert, "round")).toBe(desert.flora.round)
		T.expect(MapThemeRules.floraFor(desert, "pine")).toBe(desert.flora.pine)
	end)

	T.it("repeats the landmark list over the spots", function()
		local theme = copy(MapThemes.themes.meadow)
		theme.landmarks = { "balloon", "windmill" }
		T.expect(MapThemeRules.landmarkFor(theme, 1)).toBe("balloon")
		T.expect(MapThemeRules.landmarkFor(theme, 2)).toBe("windmill")
		T.expect(MapThemeRules.landmarkFor(theme, 3)).toBe("balloon")
		theme.landmarks = {}
		T.expect(MapThemeRules.landmarkFor(theme, 1)).toBeNil()
	end)

	T.it("counts the extra parts of flora and landmarks", function()
		local theme = copy(MapThemes.themes.meadow)
		theme.landmarks = {}
		T.expect(MapThemeRules.extraParts(theme, { "round", "pine" }, 10)).toBe(0)
		theme.flora = { round = "palm", pine = "cactus" }
		local expected = (MapThemeRules.FLORA_PARTS.palm - 4) + (MapThemeRules.FLORA_PARTS.cactus - 4)
		T.expect(MapThemeRules.extraParts(theme, { "round", "pine" }, 10)).toBe(expected)
		theme.landmarks = { "windmill" }
		T.expect(MapThemeRules.extraParts(theme, {}, 3)).toBe(3 * MapThemeRules.LANDMARK_PARTS.windmill)
	end)

	T.it("knows every flora kind's footprint and parts", function()
		for kind, parts in MapThemeRules.FLORA_PARTS do
			T.expect(MapThemeRules.FLORA_RADIUS[kind] ~= nil).toBeTruthy()
			T.expect(parts).toBeGreaterThan(0)
		end
	end)
end)

T.describe("MapThemeRules.validate", function()
	local function broken(edit: (config: any) -> ()): { string }
		local config = copy(MapThemes)
		edit(config)
		return validate(config)
	end

	T.it("refuses palette keys Config/Theme.world doesn't have", function()
		T.expect(mentions(
			broken(function(config)
				config.themes.candy.palette.notAColour = "#FFFFFF"
			end),
			"palette.notAColour"
		)).toBeTruthy()
	end)

	T.it("refuses recolouring gameplay", function()
		T.expect(mentions(
			broken(function(config)
				config.themes.candy.palette.collectPad = "#FFFFFF"
			end),
			"gameplay colour"
		)).toBeTruthy()
	end)

	T.it("refuses bad colours", function()
		T.expect(mentions(
			broken(function(config)
				config.themes.winter.palette.ground = "white"
			end),
			"palette.ground must be #RRGGBB"
		)).toBeTruthy()
		T.expect(mentions(
			broken(function(config)
				config.themes.winter.lighting.ambient = "#12345"
			end),
			"lighting ambient"
		)).toBeTruthy()
	end)

	T.it("refuses unknown flora, landmarks, weather and materials", function()
		T.expect(mentions(
			broken(function(config)
				config.themes.night.flora.round = "beanstalk"
			end),
			"not a flora kind"
		)).toBeTruthy()
		T.expect(mentions(
			broken(function(config)
				config.themes.night.landmarks = { "castle" }
			end),
			"not a landmark kind"
		)).toBeTruthy()
		T.expect(mentions(
			broken(function(config)
				config.themes.night.weather = "hail"
			end),
			"not a weather kind"
		)).toBeTruthy()
		T.expect(mentions(
			broken(function(config)
				config.themes.night.groundMaterial = "ForceField"
			end),
			"groundMaterial"
		)).toBeTruthy()
	end)

	T.it("refuses flora wider than the tree it replaces", function()
		T.expect(mentions(
			broken(function(config)
				config.themes.beach.flora.round = "pine" -- a pine is wider than a round tree's spot
			end),
			"wider than"
		)).toBeTruthy()
	end)

	T.it("refuses a map over the part budget", function()
		local tight = MapThemeRules.validate(
			MapThemes,
			Theme.world,
			treeKinds(),
			#Scenery.landmarkSpots,
			defaultParts(),
			defaultParts() + 20
		)
		T.expect(mentions(tight, "map desert builds about")).toBeTruthy()
	end)

	T.it("checks the order, the first map and the rotation", function()
		T.expect(mentions(
			broken(function(config)
				table.remove(config.order, 1)
			end),
			"missing from order"
		)).toBeTruthy()
		T.expect(mentions(
			broken(function(config)
				table.insert(config.order, "candy")
			end),
			"twice"
		)).toBeTruthy()
		T.expect(mentions(
			broken(function(config)
				config.firstMap = "moon"
			end),
			"firstMap"
		)).toBeTruthy()
		T.expect(mentions(
			broken(function(config)
				config.rotation.voteSeconds = config.rotation.mapSeconds
			end),
			"voteSeconds"
		)).toBeTruthy()
		T.expect(mentions(
			broken(function(config)
				config.rotation.candidates = 1
			end),
			"candidates"
		)).toBeTruthy()
	end)
end)

return nil
