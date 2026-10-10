--!strict
--[[
	Seasonal theme rules: which theme the active LiveOps events switch on, where its decorations go, and validation
	of Config/Seasons. Pure: no Roblox APIs. The server (SeasonService) turns the layout into anchored parts.

	Layout coordinates are world studs (Y up). The map shape is passed in (plot entrances etc.), so the rules don't
	depend on MapBuilder and tests can check that nothing lands inside a plot, on the belt or on the lobby spawn.
]]

local Types = require("../Types")

type SeasonsConfig = Types.SeasonsConfig
type SeasonTheme = Types.SeasonTheme
type SeasonDecorations = Types.SeasonDecorations

export type PropKind = "pumpkin" | "bulb" | "lamp" | "bat" | "ghost"

-- One decoration to build. (faceX, faceZ) is the horizontal direction its front looks at.
export type Prop = {
	kind: PropKind,
	x: number,
	y: number, -- bottom of the prop (pumpkins, lamps, ghosts) or its centre (bulbs, bats)
	z: number,
	faceX: number,
	faceZ: number,
	scale: number,
	color: string?, -- bulbs: their colour from palette.bulbs
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
} :: { [PropKind]: number }

local HEX_PATTERN = "^#%x%x%x%x%x%x$"

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

-- Every decoration of a theme, placed on the given map. Deterministic: the same inputs give the same layout.
function SeasonRules.layout(decorations: SeasonDecorations, palette: { bulbs: { string } }, map: MapShape): { Prop }
	local props: { Prop } = {}
	local function add(prop: Prop)
		table.insert(props, prop)
	end

	for _, entrance in map.entrances do
		-- "Right" along the front wall (any perpendicular works: props are placed on both sides).
		local rightX, rightZ = entrance.outZ, -entrance.outX
		local function at(lateral: number, out: number): (number, number)
			return entrance.x + rightX * lateral + entrance.outX * out,
				entrance.z + rightZ * lateral + entrance.outZ * out
		end

		-- Jack-o'-lanterns beside the entrance, alternating sides, facing the walkway.
		for k = 0, count(decorations.pumpkinsPerPlot) - 1 do
			local side = if k % 2 == 0 then -1 else 1
			local lateral = side * (map.entranceWidth / 2 + 2.5 + (k // 2) * 5)
			local x, z = at(lateral, 1.8)
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
					color = if #palette.bulbs > 0 then palette.bulbs[(index - 1) % #palette.bulbs + 1] else nil,
				})
			end
		end
	end

	-- Lamp posts in the gaps between neighbouring plots on the same side of the belt.
	if decorations.lampsBetweenPlots then
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
		for _, key in keys do
			local row = sides[key]
			table.sort(row, function(a: Entrance, b: Entrance): boolean
				return a.x < b.x or (a.x == b.x and a.z < b.z)
			end)
			for i = 1, #row - 1 do
				local a, b = row[i], row[i + 1]
				add({
					kind = "lamp",
					x = (a.x + b.x) / 2 + a.outX * 1.5,
					y = map.groundY,
					z = (a.z + b.z) / 2 + a.outZ * 1.5,
					faceX = a.outX,
					faceZ = a.outZ,
					scale = 1,
				})
			end
		end
	end

	-- Small pumpkins along both belt rails, facing away from the belt.
	local beltPumpkins = count(decorations.beltPumpkinsPerSide)
	for _, side in { -1, 1 } do
		for i = 1, beltPumpkins do
			add({
				kind = "pumpkin",
				x = (i - (beltPumpkins + 1) / 2) * (map.beltLength / beltPumpkins),
				y = map.groundY,
				z = side * (map.beltWidth / 2 + 2.2),
				faceX = 0,
				faceZ = side,
				scale = 0.7,
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

-- Problems with Config/Seasons (an empty list means valid). `map` is used for the part budget.
function SeasonRules.validate(config: SeasonsConfig, map: MapShape): { string }
	local problems: { string } = {}
	local function problem(message: string)
		table.insert(problems, message)
	end
	local function hex(value: string?, what: string)
		if value == nil or string.match(value, HEX_PATTERN) == nil then
			problem(`{what} must be #RRGGBB`)
		end
	end
	local function range(value: number, low: number, high: number, what: string)
		if not (value >= low and value <= high) then
			problem(`{what} must be between {low} and {high}`)
		end
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
		hex(theme.accentColor, `{name} accentColor`)
		local palette = theme.palette
		for _, key in { "pumpkin", "pumpkinFace", "stem", "lampPost", "lampLight", "bat", "ghost" } do
			hex((palette :: any)[key], `{name} palette.{key}`)
		end
		for index, color in palette.bulbs do
			hex(color, `{name} palette.bulbs[{index}]`)
		end
		local decorations = theme.decorations
		for _, key in { "pumpkinsPerPlot", "beltPumpkinsPerSide", "bulbsPerPlot", "bats", "ghosts" } do
			local value = (decorations :: any)[key]
			if value ~= nil and not (type(value) == "number" and value >= 0 and value == math.floor(value)) then
				problem(`{name} decorations.{key} must be a whole number >= 0`)
			end
		end
		if count(decorations.bulbsPerPlot) > 0 and #palette.bulbs == 0 then
			problem(`{name} has bulbs but no palette.bulbs colours`)
		end
		local parts = SeasonRules.partCount(SeasonRules.layout(decorations, palette, map))
		if parts > config.maxParts then
			problem(`{name} builds {parts} parts, over the budget of {config.maxParts}`)
		end

		local lighting = theme.lighting
		if lighting then
			range(lighting.clockTime, 0, 24, `{name} lighting.clockTime`)
			range(lighting.brightness, 0, 10, `{name} lighting.brightness`)
			hex(lighting.ambient, `{name} lighting.ambient`)
			hex(lighting.outdoorAmbient, `{name} lighting.outdoorAmbient`)
			hex(lighting.colorShiftTop, `{name} lighting.colorShiftTop`)
			local atmosphere = lighting.atmosphere
			range(atmosphere.density, 0, 1, `{name} atmosphere.density`)
			range(atmosphere.offset, 0, 1, `{name} atmosphere.offset`)
			range(atmosphere.glare, 0, 10, `{name} atmosphere.glare`)
			range(atmosphere.haze, 0, 10, `{name} atmosphere.haze`)
			hex(atmosphere.color, `{name} atmosphere.color`)
			hex(atmosphere.decay, `{name} atmosphere.decay`)
			local correction = lighting.colorCorrection
			hex(correction.tint, `{name} colorCorrection.tint`)
			range(correction.brightness, -1, 1, `{name} colorCorrection.brightness`)
			range(correction.contrast, -1, 1, `{name} colorCorrection.contrast`)
			range(correction.saturation, -1, 1, `{name} colorCorrection.saturation`)
		end
	end
	return problems
end

return SeasonRules
