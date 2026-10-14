--!strict
--[[
	Seasonal theme rules: which theme the active LiveOps events switch on, where its decorations go, and validation
	of Config/Seasons. Pure: no Roblox APIs. The server (SeasonService) turns the layout into anchored parts.

	Layout coordinates are world studs (Y up). The map shape is passed in (plot entrances etc.), so the rules don't
	depend on MapBuilder and tests can check that nothing lands inside a plot, on the belt or on the lobby spawn.

	Where each prop goes (every theme uses the same spots, so a new theme is only data):
	  beside each plot entrance   pumpkins, then presents (alternating sides, stepping outwards)
	  the plot's front wall       string-light bulbs hanging under its top; snowdrifts at its ends, on the walkway
	  between neighbouring plots  lamp posts at the walkway; trees a little back, in the grass gap
	  along both belt rails       small pumpkins, then small presents
	  above the walkway           bats; snowflakes a little higher and closer to the belt
	  past both belt ends         ghosts; snowmen at the corners, a little closer in
]]

local MapThemeRules = require("./MapThemeRules")
local Types = require("../Types")

type SeasonsConfig = Types.SeasonsConfig
type SeasonTheme = Types.SeasonTheme
type SeasonDecorations = Types.SeasonDecorations
type SeasonPalette = Types.SeasonPalette

export type PropKind =
	"pumpkin"
	| "bulb"
	| "lamp"
	| "bat"
	| "ghost"
	| "present"
	| "tree"
	| "snowman"
	| "snowflake"
	| "snowPile"

-- One decoration to build. (faceX, faceZ) is the horizontal direction its front looks at.
export type Prop = {
	kind: PropKind,
	x: number,
	y: number, -- bottom of the prop (pumpkins, lamps, ghosts, presents, trees, snowmen, drifts) or its centre (bulbs,
	-- bats, snowflakes)
	z: number,
	faceX: number,
	faceZ: number,
	scale: number,
	color: string?, -- bulbs: their colour (palette.bulbs); presents: the wrapping (palette.presents)
	color2: string?, -- presents: the ribbon (palette.ribbons)
}

-- A plot entrance: the centre of its front wall's outer face, and the unit direction pointing out of the plot.
export type Entrance = { x: number, z: number, outX: number, outZ: number }

export type MapShape = {
	entrances: { Entrance },
	entranceWidth: number,
	plotWidth: number,
	groundY: number, -- top of the walkway props stand on
	wallTopY: number, -- top of the plot walls
	beltLength: number,
	beltWidth: number,
	walkwayWidth: number, -- belt centre line to the plot fronts
}

local SeasonRules = {}

-- Parts each prop kind is built from (SeasonService builds exactly these). Used for the part budget.
SeasonRules.PARTS_PER = {
	pumpkin = 5, -- body, stem, two eyes, mouth
	bulb = 1,
	lamp = 3, -- post, lantern, cap
	bat = 3, -- body, two wings
	ghost = 4, -- head, skirt, two eyes
	present = 5, -- box, lid, two ribbons, bow
	tree = 13, -- trunk, four tiers, six baubles, two star points
	snowman = 12, -- three snowballs, two eyes, nose, hat brim and crown, scarf and its tail, two stick arms
	snowflake = 3, -- three crossed bars
	snowPile = 1,
} :: { [PropKind]: number }

-- The palette colours each prop kind is built with: a theme that places a kind must define these (lists need at
-- least one colour).
SeasonRules.PALETTE_KEYS = {
	pumpkin = { "pumpkin", "pumpkinFace", "stem" },
	bulb = { "bulbs" },
	lamp = { "lampPost", "lampLight" },
	bat = { "bat" },
	ghost = { "ghost" },
	present = { "presents", "ribbons" },
	tree = { "tree", "wood", "treeStar", "ornaments" },
	snowman = { "snow", "carrot", "coal", "scarf", "hat", "wood" },
	snowflake = { "snowflake" },
	snowPile = { "snow" },
} :: { [PropKind]: { string } }

-- Every palette key and whether it holds a list of colours.
local PALETTE_LISTS: { [string]: boolean } = {
	bulbs = true,
	presents = true,
	ribbons = true,
	ornaments = true,
	pumpkin = false,
	pumpkinFace = false,
	stem = false,
	lampPost = false,
	lampLight = false,
	bat = false,
	ghost = false,
	tree = false,
	wood = false,
	treeStar = false,
	snow = false,
	carrot = false,
	coal = false,
	scarf = false,
	hat = false,
	snowflake = false,
}

local COUNT_KEYS = {
	"pumpkinsPerPlot",
	"beltPumpkinsPerSide",
	"bulbsPerPlot",
	"bats",
	"ghosts",
	"presentsPerPlot",
	"beltPresentsPerSide",
	"snowmen",
	"snowflakes",
	"snowPilesPerPlot",
}

local HEX_PATTERN = "^#%x%x%x%x%x%x$"

-- Presents beside an entrance vary a little in size and angle, so a row reads as a pile of gifts.
local PRESENT_SCALES = { 1, 0.8, 1.15, 0.9 }
local PRESENT_TURNS = { 0, 0.32, -0.24, 0.45 } -- radians off the walkway direction
-- Trees stand this far back from the plot fronts, in the grass between two bases.
local TREE_BACK = 6

-- The theme to show for the active events: among active events that map to a theme, the highest-priority theme
-- (ties: the alphabetically first event id, so every server agrees). Returns the theme id and the event that
-- switched it on, or nil when no themed event is active.
function SeasonRules.activeTheme(config: SeasonsConfig, activeEventIds: { [string]: boolean }): (string?, string?)
	local bestTheme: string? = nil
	local bestEvent: string? = nil
	local bestPriority = -math.huge
	for eventId, active in activeEventIds do
		local themeId = config.eventThemes[eventId]
		local theme = if themeId then config.themes[themeId] else nil
		if not active or theme == nil then
			continue
		end
		if
			theme.priority > bestPriority
			or (theme.priority == bestPriority and bestEvent ~= nil and eventId < bestEvent)
		then
			bestTheme, bestEvent, bestPriority = themeId, eventId, theme.priority
		end
	end
	return bestTheme, bestEvent
end

-- The theme an event switches on, or nil (used for the colour of the "EVENT" tag and the HUD event pill).
function SeasonRules.themeForEvent(config: SeasonsConfig, eventId: string?): SeasonTheme?
	if eventId == nil then
		return nil
	end
	local themeId = config.eventThemes[eventId]
	return if themeId then config.themes[themeId] else nil
end

local function count(value: number?): number
	return math.max(0, math.floor(value or 0))
end

-- The `index`th colour of a list (1-based, cycling), or nil for an empty or missing list.
local function cycle(list: { string }?, index: number): string?
	if list == nil or #list == 0 then
		return nil
	end
	return list[(index - 1) % #list + 1]
end

-- The midpoints between neighbouring plots on the same side of the belt, with the direction out of those plots.
local function gaps(map: MapShape): { Entrance }
	local sides: { [string]: { Entrance } } = {}
	for _, entrance in map.entrances do
		local key = `{math.floor(entrance.outX * 10 + 0.5)},{math.floor(entrance.outZ * 10 + 0.5)}`
		sides[key] = sides[key] or {}
		table.insert(sides[key], entrance)
	end
	local keys: { string } = {}
	for key in sides do
		table.insert(keys, key)
	end
	table.sort(keys)
	local list: { Entrance } = {}
	for _, key in keys do
		local row = sides[key]
		table.sort(row, function(a: Entrance, b: Entrance): boolean
			return a.x < b.x or (a.x == b.x and a.z < b.z)
		end)
		for i = 1, #row - 1 do
			local a, b = row[i], row[i + 1]
			table.insert(list, { x = (a.x + b.x) / 2, z = (a.z + b.z) / 2, outX = a.outX, outZ = a.outZ })
		end
	end
	return list
end

-- Every decoration of a theme, placed on the given map. Deterministic: the same inputs give the same layout.
function SeasonRules.layout(decorations: SeasonDecorations, palette: SeasonPalette, map: MapShape): { Prop }
	local props: { Prop } = {}
	local function add(prop: Prop)
		table.insert(props, prop)
	end

	local pumpkinsPerPlot = count(decorations.pumpkinsPerPlot)
	local presentsPerPlot = count(decorations.presentsPerPlot)
	local presentIndex = 0
	for _, entrance in map.entrances do
		-- "Right" along the front wall (any perpendicular works: props are placed on both sides).
		local rightX, rightZ = entrance.outZ, -entrance.outX
		local function at(lateral: number, out: number): (number, number)
			return entrance.x + rightX * lateral + entrance.outX * out,
				entrance.z + rightZ * lateral + entrance.outZ * out
		end
		-- Spot k (0-based) beside the entrance: alternating sides, stepping outwards every two.
		local function slot(k: number): number
			local side = if k % 2 == 0 then -1 else 1
			return side * (map.entranceWidth / 2 + 2.5 + (k // 2) * 5)
		end

		-- Jack-o'-lanterns beside the entrance, alternating sides, facing the walkway.
		for k = 0, pumpkinsPerPlot - 1 do
			local x, z = at(slot(k), 1.8)
			add({
				kind = "pumpkin",
				x = x,
				y = map.groundY,
				z = z,
				faceX = entrance.outX,
				faceZ = entrance.outZ,
				scale = 1,
			})
		end

		-- Presents in the next spots, each a little bigger or smaller and turned, in cycling wrapping and ribbons.
		for k = pumpkinsPerPlot, pumpkinsPerPlot + presentsPerPlot - 1 do
			presentIndex += 1
			local x, z = at(slot(k), 1.8)
			local turn = PRESENT_TURNS[(presentIndex - 1) % #PRESENT_TURNS + 1]
			add({
				kind = "present",
				x = x,
				y = map.groundY,
				z = z,
				faceX = entrance.outX * math.cos(turn) - entrance.outZ * math.sin(turn),
				faceZ = entrance.outX * math.sin(turn) + entrance.outZ * math.cos(turn),
				scale = PRESENT_SCALES[(presentIndex - 1) % #PRESENT_SCALES + 1],
				color = cycle(palette.presents, presentIndex),
				color2 = cycle(palette.ribbons, presentIndex),
			})
		end

		-- String-light bulbs hanging along the front wall, split between both wall segments.
		local bulbs = count(decorations.bulbsPerPlot)
		local segment = (map.plotWidth - map.entranceWidth) / 2
		local perSide = { math.ceil(bulbs / 2), bulbs // 2 }
		local index = 0
		for sideIndex, side in { -1, 1 } do
			local n = perSide[sideIndex]
			for j = 1, n do
				index += 1
				local lateral = side * (map.entranceWidth / 2 + (j - 0.5) * segment / n)
				local x, z = at(lateral, 0.5)
				-- a gentle sag between the ends of each segment
				local sag = math.sin((j - 0.5) / n * math.pi) * 0.5
				add({
					kind = "bulb",
					x = x,
					y = map.wallTopY - 0.5 - sag,
					z = z,
					faceX = entrance.outX,
					faceZ = entrance.outZ,
					scale = 1,
					color = cycle(palette.bulbs, index),
				})
			end
		end

		-- Snowdrifts against the front wall: one at each end, then further in.
		for k = 0, count(decorations.snowPilesPerPlot) - 1 do
			local side = if k % 2 == 0 then -1 else 1
			local x, z = at(side * (map.plotWidth / 2 - 3.5 - (k // 2) * 6), 1.4)
			add({
				kind = "snowPile",
				x = x,
				y = map.groundY,
				z = z,
				faceX = entrance.outX,
				faceZ = entrance.outZ,
				scale = 1,
			})
		end
	end

	-- Lamp posts at the walkway between neighbouring plots on the same side of the belt, trees further back.
	for _, gap in gaps(map) do
		if decorations.lampsBetweenPlots then
			add({
				kind = "lamp",
				x = gap.x + gap.outX * 1.5,
				y = map.groundY,
				z = gap.z + gap.outZ * 1.5,
				faceX = gap.outX,
				faceZ = gap.outZ,
				scale = 1,
			})
		end
		if decorations.treesBetweenPlots then
			add({
				kind = "tree",
				x = gap.x - gap.outX * TREE_BACK,
				y = map.groundY,
				z = gap.z - gap.outZ * TREE_BACK,
				faceX = gap.outX,
				faceZ = gap.outZ,
				scale = 1,
			})
		end
	end

	-- Small pumpkins, then small presents, along both belt rails, facing away from the belt.
	local beltPumpkins = count(decorations.beltPumpkinsPerSide)
	local beltPresents = count(decorations.beltPresentsPerSide)
	local beltTotal = beltPumpkins + beltPresents
	for sideIndex, side in { -1, 1 } do
		for i = 1, beltTotal do
			local isPumpkin = i <= beltPumpkins
			local n = (sideIndex - 1) * beltPresents + (i - beltPumpkins)
			add({
				kind = if isPumpkin then "pumpkin" else "present",
				x = (i - (beltTotal + 1) / 2) * (map.beltLength / beltTotal),
				y = map.groundY,
				z = side * (map.beltWidth / 2 + 2.2),
				faceX = 0,
				faceZ = side,
				scale = 0.7,
				color = if isPumpkin then nil else cycle(palette.presents, n + 2),
				color2 = if isPumpkin then nil else cycle(palette.ribbons, n + 1),
			})
		end
	end

	-- Bats flying high over the walkway, spread along the belt.
	local bats = count(decorations.bats)
	for i = 1, bats do
		local angle = i * 2.1
		add({
			kind = "bat",
			x = (i - (bats + 1) / 2) * (map.beltLength * 0.8 / bats),
			y = 16 + (i % 3) * 3,
			z = (if i % 2 == 0 then 1 else -1) * map.walkwayWidth * 0.55,
			faceX = math.cos(angle),
			faceZ = math.sin(angle),
			scale = 1,
		})
	end

	-- Snowflakes hanging higher and closer to the belt, turned a little towards it.
	local flakes = count(decorations.snowflakes)
	for i = 1, flakes do
		local zSide = if i % 2 == 0 then 1 else -1
		local turn = ((i % 4) - 1.5) * 0.3
		add({
			kind = "snowflake",
			x = (i - (flakes + 1) / 2) * (map.beltLength * 0.85 / flakes),
			y = 20 + (i % 3) * 2.5,
			z = zSide * map.walkwayWidth * 0.4,
			faceX = math.sin(turn),
			faceZ = -zSide * math.cos(turn),
			scale = 1,
		})
	end

	-- Ghosts floating past the belt's end arches, looking back at the belt.
	for i = 1, count(decorations.ghosts) do
		local endSide = if i % 2 == 1 then -1 else 1
		local zSide = if ((i - 1) // 2) % 2 == 0 then -1 else 1
		local row = (i - 1) // 4
		add({
			kind = "ghost",
			x = endSide * (map.beltLength / 2 + 12 + row * 6),
			y = map.groundY + 2.5,
			z = zSide * (10 + row * 3),
			faceX = -endSide,
			faceZ = 0,
			scale = 1,
		})
	end

	-- Snowmen at the corners of both belt ends (clear of the factory and the chute), looking along the walkway.
	for i = 1, count(decorations.snowmen) do
		local endSide = if i % 2 == 1 then -1 else 1
		local zSide = if ((i - 1) // 2) % 2 == 0 then -1 else 1
		local row = (i - 1) // 4
		add({
			kind = "snowman",
			x = endSide * (map.beltLength / 2 + 8 + row * 7),
			y = map.groundY,
			z = zSide * (12 + row * 2),
			faceX = -endSide,
			faceZ = 0,
			scale = 1,
		})
	end

	return props
end

-- How many parts a layout is built from.
function SeasonRules.partCount(props: { Prop }): number
	local total = 0
	for _, prop in props do
		total += SeasonRules.PARTS_PER[prop.kind]
	end
	return total
end

-- Problems with a lighting overlay (a seasonal theme's, or a weather modifier's); `name` starts each message.
function SeasonRules.lightingProblems(lighting: Types.SeasonLighting, name: string): { string }
	local problems: { string } = {}
	local function hex(value: string?, what: string)
		if value == nil or string.match(value, HEX_PATTERN) == nil then
			table.insert(problems, `{name} {what} must be #RRGGBB`)
		end
	end
	local function range(value: number, low: number, high: number, what: string)
		if not (value >= low and value <= high) then
			table.insert(problems, `{name} {what} must be between {low} and {high}`)
		end
	end
	range(lighting.clockTime, 0, 24, "lighting.clockTime")
	range(lighting.brightness, 0, 10, "lighting.brightness")
	hex(lighting.ambient, "lighting.ambient")
	hex(lighting.outdoorAmbient, "lighting.outdoorAmbient")
	hex(lighting.colorShiftTop, "lighting.colorShiftTop")
	local atmosphere = lighting.atmosphere
	range(atmosphere.density, 0, 1, "atmosphere.density")
	range(atmosphere.offset, 0, 1, "atmosphere.offset")
	range(atmosphere.glare, 0, 10, "atmosphere.glare")
	range(atmosphere.haze, 0, 10, "atmosphere.haze")
	hex(atmosphere.color, "atmosphere.color")
	hex(atmosphere.decay, "atmosphere.decay")
	local correction = lighting.colorCorrection
	hex(correction.tint, "colorCorrection.tint")
	range(correction.brightness, -1, 1, "colorCorrection.brightness")
	range(correction.contrast, -1, 1, "colorCorrection.contrast")
	range(correction.saturation, -1, 1, "colorCorrection.saturation")
	local clouds = lighting.clouds
	if clouds then
		range(clouds.cover, 0, 1, "clouds.cover")
		range(clouds.density, 0, 1, "clouds.density")
		hex(clouds.color, "clouds.color")
	end
	return problems
end

-- Problems with a theme's palette: unknown keys, colours that aren't #RRGGBB, and colours missing for a prop kind
-- the theme places (`kinds`).
local function paletteProblems(palette: SeasonPalette, kinds: { [string]: boolean }, name: string): { string }
	local problems: { string } = {}
	local raw = (palette :: any) :: { [string]: any }
	local keys: { string } = {}
	for key in raw do
		table.insert(keys, key)
	end
	table.sort(keys)
	for _, key in keys do
		local value = raw[key]
		local isList = PALETTE_LISTS[key]
		if isList == nil then
			table.insert(problems, `{name} palette.{key} is not a palette colour`)
		elseif isList then
			if type(value) ~= "table" then
				table.insert(problems, `{name} palette.{key} must be a list of #RRGGBB colours`)
			else
				for index, color in value do
					if type(color) ~= "string" or string.match(color, HEX_PATTERN) == nil then
						table.insert(problems, `{name} palette.{key}[{index}] must be #RRGGBB`)
					end
				end
			end
		elseif type(value) ~= "string" or string.match(value, HEX_PATTERN) == nil then
			table.insert(problems, `{name} palette.{key} must be #RRGGBB`)
		end
	end
	local kindList: { string } = {}
	for kind in kinds do
		table.insert(kindList, kind)
	end
	table.sort(kindList)
	for _, kind in kindList do
		for _, key in SeasonRules.PALETTE_KEYS[kind :: PropKind] do
			local value = raw[key]
			if value == nil or (type(value) == "table" and #value == 0) then
				table.insert(problems, `{name} places {kind} props but has no palette.{key}`)
			end
		end
	end
	return problems
end

-- Problems with Config/Seasons (an empty list means valid). `map` is used for the part budget.
function SeasonRules.validate(config: SeasonsConfig, map: MapShape): { string }
	local problems: { string } = {}
	local function problem(message: string)
		table.insert(problems, message)
	end

	for eventId, themeId in config.eventThemes do
		if config.themes[themeId] == nil then
			problem(`event {eventId} maps to unknown theme {themeId}`)
		end
	end
	if not (config.maxParts > 0) then
		problem("maxParts must be positive")
	end
	if not (config.transitionSeconds >= 0 and config.transitionSeconds <= 30) then
		problem("transitionSeconds must be between 0 and 30")
	end

	for themeId, theme in config.themes do
		local name = `theme {themeId}`
		if theme.displayName == "" then
			problem(`{name} needs a displayName`)
		end
		if theme.priority ~= theme.priority then
			problem(`{name} priority must be a number`)
		end
		if string.match(theme.accentColor, HEX_PATTERN) == nil then
			problem(`{name} accentColor must be #RRGGBB`)
		end
		if theme.weather ~= nil and not MapThemeRules.WEATHER[theme.weather] then
			problem(`{name} weather {theme.weather} is not a weather kind`)
		end
		local decorations = theme.decorations
		for _, key in COUNT_KEYS do
			local value = (decorations :: any)[key]
			if value ~= nil and not (type(value) == "number" and value >= 0 and value == math.floor(value)) then
				problem(`{name} decorations.{key} must be a whole number >= 0`)
			end
		end
		local props = SeasonRules.layout(decorations, theme.palette, map)
		local kinds: { [string]: boolean } = {}
		for _, prop in props do
			kinds[prop.kind] = true
		end
		for _, message in paletteProblems(theme.palette, kinds, name) do
			problem(message)
		end
		local parts = SeasonRules.partCount(props)
		if parts > config.maxParts then
			problem(`{name} builds {parts} parts, over the budget of {config.maxParts}`)
		end

		local lighting = theme.lighting
		if lighting then
			for _, message in SeasonRules.lightingProblems(lighting, name) do
				problem(message)
			end
		end
	end
	return problems
end

return SeasonRules
