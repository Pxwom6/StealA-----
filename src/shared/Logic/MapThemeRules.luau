--!strict
--[[
	Map theme rules (Config/MapThemes): which map a server starts on, the ballot for the next map, counting the votes,
	part estimates, and validation. Pure: no Roblox APIs; random numbers come in as a function returning [0, 1).

	Votes are a map from voter (a UserId) to the theme id they picked; only votes for a candidate count, one per voter.
]]

local Types = require("../Types")

type MapThemesConfig = Types.MapThemesConfig
type MapThemeDef = Types.MapThemeDef
type FloraKind = Types.FloraKind
type LandmarkKind = Types.LandmarkKind

local MapThemeRules = {}

-- Config/Theme.world colours a map may NOT change: what players read as gameplay looks the same on every map.
MapThemeRules.FIXED_KEYS = table.freeze({
	podium = true,
	emptyPodium = true,
	lockedPodium = true,
	collectPad = true,
	lockButton = true,
	lockField = true,
	graceField = true,
	vipTrim = true,
	upgradePad = true,
	wall = true,
	plotTileDark = true,
	plotTileLight = true,
	plotPost = true,
	signBorder = true,
	lockPlinth = true,
	upgradeFrame = true,
	belt = true,
	beltTrim = true,
	beltChevron = true,
	beltBumper = true,
	hazard = true,
} :: { [string]: boolean })

-- Parts each flora kind is built from (server/Services/ThemeProps builds exactly these).
MapThemeRules.FLORA_PARTS = table.freeze({
	round = 4,
	pine = 4,
	snowyPine = 7,
	lollipop = 4,
	gumdropTree = 4,
	palm = 7,
	cactus = 7,
	deadTree = 4,
	crystal = 4,
	mushroom = 5,
	bush = 3,
	blossomTree = 4,
	bamboo = 4,
	alienPlant = 4,
	moonRock = 3,
	jungleTree = 5,
	fern = 4,
	planterTree = 4,
	streetLamp = 4,
	cloudTree = 4,
	cloudPillar = 3,
	coral = 5,
	kelp = 4,
} :: { [string]: number })

-- How far each flora kind reaches from its spot at scale 1 (studs). A kind may only stand on spots whose tree it fits
-- inside: SceneryLayout.RADIUS.roundTree (4.5) for the round spots, pineTree (5) for the pine spots.
MapThemeRules.FLORA_RADIUS = table.freeze({
	round = 4.5,
	pine = 5,
	snowyPine = 5,
	lollipop = 3,
	gumdropTree = 3.6,
	palm = 4.5,
	cactus = 3.2,
	deadTree = 4.2,
	crystal = 3.4,
	mushroom = 4.2,
	bush = 3.4,
	blossomTree = 4.2,
	bamboo = 3.8,
	alienPlant = 3.9,
	moonRock = 4.2,
	jungleTree = 4.4,
	fern = 4.4,
	planterTree = 2.8,
	streetLamp = 3.1,
	cloudTree = 4.1,
	cloudPillar = 1.9,
	coral = 2.7,
	kelp = 3,
} :: { [string]: number })

-- Parts each landmark kind is built from (server/Services/ThemeProps).
MapThemeRules.LANDMARK_PARTS = table.freeze({
	balloon = 6,
	windmill = 8,
	giantLollipop = 4,
	candyCane = 9,
	cottonCloud = 5,
	iceSpire = 4,
	snowman = 9,
	mesa = 4,
	giantCactus = 7,
	volcano = 8,
	lavaPillar = 4,
	giantMushroom = 6,
	skyLantern = 6,
	lighthouse = 7,
	beachUmbrella = 4,
	barn = 7,
	hayBales = 4,
	torii = 6,
	pagoda = 8,
	rocket = 8,
	planet = 3,
	satelliteDish = 5,
	temple = 6,
	giantFlower = 8,
	skyscraper = 6,
	neonSign = 6,
	floatingIsland = 6,
	skyCastle = 7,
	shipwreck = 7,
	giantClam = 4,
} :: { [string]: number })

MapThemeRules.WEATHER = table.freeze({
	none = true,
	snow = true,
	embers = true,
	leaves = true,
	fireflies = true,
	sprinkles = true,
	dust = true,
	petals = true,
	rain = true,
	spores = true,
	stardust = true,
	pollen = true,
	feathers = true,
	bubbles = true,
} :: { [string]: boolean })

-- Enum.Material names a map may use for its ground, walkway and boundary wall.
MapThemeRules.MATERIALS = table.freeze({
	Grass = true,
	Sand = true,
	Snow = true,
	Basalt = true,
	Slate = true,
	SmoothPlastic = true,
	Plastic = true,
	Pavement = true,
	Cobblestone = true,
	Sandstone = true,
	WoodPlanks = true,
	Ice = true,
	Glacier = true,
	Concrete = true,
	Brick = true,
	Ground = true,
	Marble = true,
	Fabric = true,
	Asphalt = true,
	LeafyGrass = true,
	Pebble = true,
	DiamondPlate = true,
	Metal = true,
} :: { [string]: boolean })

local HEX_PATTERN = "^#%x%x%x%x%x%x$"

-- Picks one id from `ids` with chance proportional to its weight (ids with weight <= 0 are never picked). nil when
-- nothing can be picked.
local function weightedPick(config: MapThemesConfig, ids: { string }, random: () -> number): string?
	local total = 0
	for _, id in ids do
		total += math.max(0, config.themes[id].weight)
	end
	if total <= 0 then
		return nil
	end
	local roll = random() * total
	for _, id in ids do
		local weight = math.max(0, config.themes[id].weight)
		if weight > 0 then
			if roll < weight then
				return id
			end
			roll -= weight
		end
	end
	-- Rounding: the last id with weight.
	for index = #ids, 1, -1 do
		if config.themes[ids[index]].weight > 0 then
			return ids[index]
		end
	end
	return nil
end

-- The map a new server starts on: config.firstMap, or a weighted random one when that is "random" (or unknown).
function MapThemeRules.firstMap(config: MapThemesConfig, random: () -> number): string
	if config.themes[config.firstMap] then
		return config.firstMap
	end
	return weightedPick(config, config.order, random) or config.order[1]
end

-- Up to `count` different maps for the next vote, weighted, never `current`, in config.order. Fewer when there aren't
-- enough maps that can come up.
function MapThemeRules.candidates(
	config: MapThemesConfig,
	current: string?,
	count: number,
	random: () -> number
): { string }
	local pool: { string } = {}
	for _, id in config.order do
		if id ~= current and config.themes[id] and config.themes[id].weight > 0 then
			table.insert(pool, id)
		end
	end
	local picked: { [string]: boolean } = {}
	for _ = 1, math.min(count, #pool) do
		local remaining: { string } = {}
		for _, id in pool do
			if not picked[id] then
				table.insert(remaining, id)
			end
		end
		local id = weightedPick(config, remaining, random)
		if id == nil then
			break
		end
		picked[id] = true
	end
	local result: { string } = {}
	for _, id in config.order do
		if picked[id] then
			table.insert(result, id)
		end
	end
	return result
end

-- Votes per candidate, in the candidates' order. Only votes for a candidate count.
function MapThemeRules.counts(candidates: { string }, votes: { [any]: string }): { number }
	local counts: { number } = table.create(#candidates, 0)
	for _, choice in votes do
		local index = table.find(candidates, choice)
		if index then
			counts[index] += 1
		end
	end
	return counts
end

-- The vote's winner: the candidate with the most votes; a tie (or no votes at all) is settled at random among the
-- tied candidates. nil only when there are no candidates.
function MapThemeRules.winner(candidates: { string }, votes: { [any]: string }, random: () -> number): string?
	if #candidates == 0 then
		return nil
	end
	local counts = MapThemeRules.counts(candidates, votes)
	local best = -1
	local tied: { string } = {}
	for index, id in candidates do
		if counts[index] > best then
			best = counts[index]
			tied = { id }
		elseif counts[index] == best then
			table.insert(tied, id)
		end
	end
	return tied[math.clamp(math.floor(random() * #tied) + 1, 1, #tied)]
end

-- When the next vote opens for a map that changes at `switchAt` (the vote ends as the map changes).
function MapThemeRules.voteOpensAt(switchAt: number, rotation: Types.MapRotation): number
	return switchAt - math.min(rotation.voteSeconds, rotation.mapSeconds)
end

-- The flora kind that grows on a tree spot of `treeKind` ("round" or "pine") on this map.
function MapThemeRules.floraFor(theme: MapThemeDef, treeKind: string): FloraKind
	return if treeKind == "pine" then theme.flora.pine else theme.flora.round
end

-- The landmark kind standing on landmark spot `index` (the map's list, repeated).
function MapThemeRules.landmarkFor(theme: MapThemeDef, index: number): LandmarkKind?
	local list = theme.landmarks
	if #list == 0 then
		return nil
	end
	return list[(index - 1) % #list + 1]
end

-- How many parts this map's flora and landmarks add, compared with the default trees (round and pine, 4 parts each):
-- added to SceneryLayout.partEstimate, which counts default trees.
function MapThemeRules.extraParts(theme: MapThemeDef, treeKinds: { string }, landmarkSpots: number): number
	-- Unknown kinds count as nothing here (validate reports them).
	local extra = 0
	for _, kind in treeKinds do
		local parts = MapThemeRules.FLORA_PARTS[MapThemeRules.floraFor(theme, kind)]
		extra += if parts then parts - 4 else 0
	end
	for index = 1, landmarkSpots do
		local landmark = MapThemeRules.landmarkFor(theme, index)
		extra += if landmark then MapThemeRules.LANDMARK_PARTS[landmark] or 0 else 0
	end
	return extra
end

-- Problems with Config/MapThemes (an empty list means valid). `worldKeys` are Config/Theme.world's keys (a map can
-- only recolour colours that exist); `treeKinds` the kind of every tree spot in the scenery layout and
-- `defaultParts` the scenery's part estimate with default trees (SceneryLayout.partEstimate), for the budget.
function MapThemeRules.validate(
	config: MapThemesConfig,
	worldKeys: { [string]: any },
	treeKinds: { string },
	landmarkSpots: number,
	defaultParts: number,
	partBudget: number
): { string }
	local problems: { string } = {}
	local function problem(message: string)
		table.insert(problems, message)
	end
	local function hex(value: unknown, what: string)
		if type(value) ~= "string" or string.match(value, HEX_PATTERN) == nil then
			problem(`{what} must be #RRGGBB`)
		end
	end
	local function range(value: number, low: number, high: number, what: string)
		if not (value >= low and value <= high) then
			problem(`{what} must be between {low} and {high}`)
		end
	end

	local seen: { [string]: boolean } = {}
	for _, id in config.order do
		if config.themes[id] == nil then
			problem(`order lists unknown map {id}`)
		elseif seen[id] then
			problem(`order lists {id} twice`)
		end
		seen[id] = true
	end
	local pickable = 0
	for id, theme in config.themes do
		if not seen[id] then
			problem(`map {id} is missing from order`)
		end
		if theme.weight > 0 then
			pickable += 1
		end
	end
	if config.firstMap ~= "random" and config.themes[config.firstMap] == nil then
		problem(`firstMap {config.firstMap} is not a map (or "random")`)
	end
	if pickable == 0 then
		problem("no map has a weight above 0")
	end
	local rotation = config.rotation
	if rotation.enabled then
		if not (rotation.mapSeconds >= 120) then
			problem("rotation.mapSeconds must be at least 120")
		end
		if not (rotation.voteSeconds >= 10 and rotation.voteSeconds <= rotation.mapSeconds / 2) then
			problem("rotation.voteSeconds must be at least 10 and at most half of mapSeconds")
		end
		if not (rotation.candidates >= 2 and rotation.candidates <= 4 and rotation.candidates % 1 == 0) then
			problem("rotation.candidates must be a whole number from 2 to 4")
		end
		if pickable < 2 then
			problem("rotation needs at least two maps with a weight above 0")
		end
	end
	if not (config.transitionSeconds >= 0 and config.transitionSeconds <= 30) then
		problem("transitionSeconds must be between 0 and 30")
	end

	for id, theme in config.themes do
		local name = `map {id}`
		if theme.displayName == "" or #theme.displayName > 24 then
			problem(`{name} needs a displayName of at most 24 characters`)
		end
		if theme.icon == "" then
			problem(`{name} needs an icon`)
		end
		if #theme.tagline > 60 then
			problem(`{name} tagline is longer than 60 characters`)
		end
		hex(theme.accentColor, `{name} accentColor`)
		if not (theme.weight >= 0) then
			problem(`{name} weight must be 0 or more`)
		end
		for key, value in theme.palette do
			if worldKeys[key] == nil then
				problem(`{name} palette.{key} is not a Config/Theme.world colour`)
			elseif MapThemeRules.FIXED_KEYS[key] then
				problem(`{name} palette.{key} is a gameplay colour maps keep`)
			end
			hex(value, `{name} palette.{key}`)
		end
		for _, field in { "groundMaterial", "walkwayMaterial", "boundaryMaterial" } do
			local material = (theme :: any)[field]
			if not MapThemeRules.MATERIALS[material] then
				problem(`{name} {field} {tostring(material)} is not an allowed material`)
			end
		end
		range(theme.water.transparency, 0, 1, `{name} water.transparency`)
		range(theme.water.reflectance, 0, 1, `{name} water.reflectance`)
		for treeKind, flora in { round = theme.flora.round, pine = theme.flora.pine } :: { [string]: FloraKind } do
			local radius = MapThemeRules.FLORA_RADIUS[flora]
			local limit = if treeKind == "pine"
				then MapThemeRules.FLORA_RADIUS.pine
				else MapThemeRules.FLORA_RADIUS.round
			if radius == nil then
				problem(`{name} flora.{treeKind} {flora} is not a flora kind`)
			elseif radius > limit then
				problem(`{name} flora.{treeKind} {flora} is wider than the {treeKind} trees it replaces`)
			end
		end
		for index, landmark in theme.landmarks do
			if MapThemeRules.LANDMARK_PARTS[landmark] == nil then
				problem(`{name} landmarks[{index}] {landmark} is not a landmark kind`)
			end
		end
		if not MapThemeRules.WEATHER[theme.weather] then
			problem(`{name} weather {theme.weather} is not a weather kind`)
		end

		local lighting = theme.lighting
		range(lighting.clockTime, 0, 24, `{name} lighting.clockTime`)
		range(lighting.geographicLatitude, -90, 90, `{name} lighting.geographicLatitude`)
		range(lighting.brightness, 0, 10, `{name} lighting.brightness`)
		range(lighting.exposureCompensation, -3, 3, `{name} lighting.exposureCompensation`)
		range(lighting.environmentDiffuseScale, 0, 1, `{name} lighting.environmentDiffuseScale`)
		range(lighting.environmentSpecularScale, 0, 1, `{name} lighting.environmentSpecularScale`)
		range(lighting.shadowSoftness, 0, 1, `{name} lighting.shadowSoftness`)
		range(lighting.atmosphere.density, 0, 1, `{name} atmosphere.density`)
		range(lighting.atmosphere.offset, 0, 1, `{name} atmosphere.offset`)
		range(lighting.atmosphere.glare, 0, 10, `{name} atmosphere.glare`)
		range(lighting.atmosphere.haze, 0, 10, `{name} atmosphere.haze`)
		range(lighting.colorCorrection.brightness, -1, 1, `{name} colorCorrection.brightness`)
		range(lighting.colorCorrection.contrast, -1, 1, `{name} colorCorrection.contrast`)
		range(lighting.colorCorrection.saturation, -1, 1, `{name} colorCorrection.saturation`)
		range(lighting.clouds.cover, 0, 1, `{name} clouds.cover`)
		range(lighting.clouds.density, 0, 1, `{name} clouds.density`)
		range(lighting.sky.starCount, 0, 5000, `{name} sky.starCount`)
		for key, value in
			{
				ambient = lighting.ambient,
				outdoorAmbient = lighting.outdoorAmbient,
				colorShiftTop = lighting.colorShiftTop,
				colorShiftBottom = lighting.colorShiftBottom,
				atmosphereColor = lighting.atmosphere.color,
				atmosphereDecay = lighting.atmosphere.decay,
				tint = lighting.colorCorrection.tint,
				cloudColor = lighting.clouds.color,
			} :: { [string]: string }
		do
			hex(value, `{name} lighting {key}`)
		end

		local parts = defaultParts + MapThemeRules.extraParts(theme, treeKinds, landmarkSpots)
		if parts > partBudget then
			problem(`{name} builds about {parts} scenery parts, over the budget of {partBudget}`)
		end
	end
	return problems
end

return MapThemeRules
