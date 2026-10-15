--!strict
--[[
	Seasonal theme rules: which theme the active LiveOps events switch on, where its decorations go, and validation
	of Config/Seasons. Pure: no Roblox APIs. The server (SeasonService) turns the layout into anchored parts.

	Layout coordinates are world studs (Y up). The map shape is passed in (plot entrances etc.), so the rules don't
	depend on MapBuilder and tests can check that nothing lands inside a plot, on the belt or on the lobby spawn.

	Where each prop goes (every theme uses the same spots, so a new theme is only data):
	  beside each plot entrance   pumpkins, then presents, then potted roses, then painted eggs, then hay bales, then
	                              clover patches, then swim rings, then beach balls (alternating sides, stepping
	                              outwards)
	  the plot's front wall       string-light bulbs hanging under its top; bunting pennants between them, a little
	                              lower; snowdrifts at its ends, on the walkway
	  between neighbouring plots  lamp posts at the walkway (beach umbrellas there too, or a little back when there
	                              are lamps); trees a little back, in the grass gap; blossom trees there too, then
	                              scarecrows, then rainbows with a pot of gold at their foot (each further back when
	                              there is one in front)
	  along both belt rails       small pumpkins, then small presents, then small roses, then small eggs, then small
	                              cornucopias, then small pots of gold, then small beach balls
	  above the walkway           bats; snowflakes a little higher and closer to the belt; heart balloons lower and
	                              a little closer in; butterflies lower still, nearer the bases
	  past both belt ends         ghosts; snowmen at the corners, a little closer in, then giant hearts, then
	                              chocolate bunnies, then giant corn stalks, then sandcastles, then giant shamrocks
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
	| "rosePot"
	| "heartBalloon"
	| "giantHeart"
	| "easterEgg"
	| "chocolateBunny"
	| "blossomTree"
	| "butterfly"
	| "hayBale"
	| "scarecrow"
	| "cornucopia"
	| "cornStalk"
	| "rainbow"
	| "potOfGold"
	| "cloverPatch"
	| "beachUmbrella"
	| "sandcastle"
	| "swimRing"
	| "beachBall"
	| "pennant"
	| "shamrock"

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
	color: string?, -- bulbs: their colour (palette.bulbs); presents: the wrapping (palette.presents); roses and
	-- balloons: their colour (palette.roses, palette.balloons); eggs: the shell (palette.eggs); blossom trees: their
	-- blossom (palette.blossoms); butterflies: their wings (palette.butterflies); beach umbrellas: the canopy
	-- (palette.umbrellas); swim rings: the ring (palette.rings); beach balls: their first panel (palette.ballPanels);
	-- pennants: the flag (palette.pennants)
	color2: string?, -- presents: the ribbon (palette.ribbons); roses: the middle bloom; eggs: the painted bands and
	-- dots (palette.eggStripes); blossom trees: their second blossom colour; beach umbrellas: the towel under them
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
	pumpkin = 5, -- body, stem, two eyes, mouth (carved); or body, two ribs, stem, leaf (plain: no pumpkinFace)
	bulb = 1,
	lamp = 3, -- post, lantern, cap
	bat = 3, -- body, two wings
	ghost = 4, -- head, skirt, two eyes
	present = 5, -- box, lid, two ribbons, bow
	tree = 13, -- trunk, four tiers, six baubles, two star points
	snowman = 12, -- three snowballs, two eyes, nose, hat brim and crown, scarf and its tail, two stick arms
	snowflake = 3, -- three crossed bars
	snowPile = 1,
	rosePot = 5, -- pot, bush, three blooms
	heartBalloon = 4, -- two lobes, the point, the string
	giantHeart = 8, -- pedestal, two lobes and the point, the arrow's shaft, tip and two feathers
	easterEgg = 5, -- shell, two painted bands, two dots
	chocolateBunny = 15, -- body, head, two ears and their linings, two eyes and pupils, nose, two feet, a two-loop bow
	blossomTree = 5, -- trunk, four clouds of blossom
	butterfly = 3, -- body, two wings
	hayBale = 4, -- bale, two twine bands, a tuft of loose straw on top
	scarecrow = 14, -- post, sleeves, shirt, overalls, two straw hands, sack head, hat brim and crown, two button eyes,
	-- a two-stroke stitched smile, a straw fringe under the hat
	cornucopia = 10, -- three woven bands, the curled tip, the lip, the hollow, a pumpkin, an apple, grapes, an ear of corn
	cornStalk = 8, -- the stalk, four long leaves, an ear of corn and its husk, the tassel
	rainbow = 31, -- six bands of five segments each, a puff of cloud at its left foot
	potOfGold = 6, -- the cauldron, its rim, a heap of chocolate gold coins, three coins standing in it
	cloverPatch = 5, -- a low mound of clover, a four-leaf clover on it
	beachUmbrella = 9, -- pole, canopy, four ribs across it, a band round its rim, the knob on top, a towel on the grass
	sandcastle = 15, -- a mound, the keep and its top, three towers and their tops, a door, a flagpole and its flag, a
	-- bucket, a spade and its handle
	swimRing = 8, -- eight segments round the ring, in two colours
	beachBall = 4, -- the ball, three coloured panels round it
	pennant = 1,
	shamrock = 10, -- its stem and three heart-shaped leaves, each two lobes and a point
} :: { [PropKind]: number }

-- The palette colours each prop kind is built with: a theme that places a kind must define these (lists need at
-- least one colour).
SeasonRules.PALETTE_KEYS = {
	pumpkin = { "pumpkin", "stem" }, -- and pumpkinFace to carve them into glowing jack-o'-lanterns
	bulb = { "bulbs" },
	lamp = { "lampPost", "lampLight" },
	bat = { "bat" },
	ghost = { "ghost" },
	present = { "presents", "ribbons" },
	tree = { "tree", "wood", "treeStar", "ornaments" },
	snowman = { "snow", "carrot", "coal", "scarf", "hat", "wood" },
	snowflake = { "snowflake" },
	snowPile = { "snow" },
	rosePot = { "pot", "leaves", "roses" },
	heartBalloon = { "balloons", "balloonString" },
	giantHeart = { "heart", "pedestal", "arrow" },
	easterEgg = { "eggs", "eggStripes" },
	chocolateBunny = { "chocolate", "bunnyBow" },
	blossomTree = { "wood", "blossoms" },
	butterfly = { "butterflies", "butterflyBody" },
	hayBale = { "straw", "twine" },
	scarecrow = { "wood", "straw", "shirt", "overalls", "burlap", "hat" },
	cornucopia = { "wicker", "produce" },
	cornStalk = { "stalks", "corn" },
	rainbow = { "rainbow", "cloud" },
	potOfGold = { "cauldron", "gold" },
	cloverPatch = { "clover" },
	beachUmbrella = { "umbrellas", "stripe" },
	sandcastle = { "sand", "flag", "bucket" },
	swimRing = { "rings", "stripe" },
	beachBall = { "ballPanels", "stripe" },
	pennant = { "pennants" },
	shamrock = { "clover" },
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
	roses = true,
	balloons = true,
	pot = false,
	leaves = false,
	balloonString = false,
	heart = false,
	pedestal = false,
	arrow = false,
	eggs = true,
	eggStripes = true,
	blossoms = true,
	butterflies = true,
	butterflyBody = false,
	chocolate = false,
	bunnyBow = false,
	straw = false,
	twine = false,
	shirt = false,
	overalls = false,
	burlap = false,
	wicker = false,
	produce = true,
	stalks = false,
	corn = false,
	rainbow = true,
	cloud = false,
	cauldron = false,
	gold = false,
	clover = false,
	umbrellas = true,
	stripe = false,
	sand = false,
	flag = false,
	bucket = false,
	rings = true,
	ballPanels = true,
	pennants = true,
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
	"rosesPerPlot",
	"beltRosesPerSide",
	"heartBalloons",
	"giantHearts",
	"eggsPerPlot",
	"beltEggsPerSide",
	"butterflies",
	"chocolateBunnies",
	"hayBalesPerPlot",
	"beltCornucopiasPerSide",
	"cornStalks",
	"cloverPatchesPerPlot",
	"beltPotsOfGoldPerSide",
	"swimRingsPerPlot",
	"beachBallsPerPlot",
	"beltBeachBallsPerSide",
	"pennantsPerPlot",
	"sandcastles",
	"shamrocks",
}

local HEX_PATTERN = "^#%x%x%x%x%x%x$"

-- Presents beside an entrance vary a little in size and angle, so a row reads as a pile of gifts.
local PRESENT_SCALES = { 1, 0.8, 1.15, 0.9 }
local PRESENT_TURNS = { 0, 0.32, -0.24, 0.45 } -- radians off the walkway direction
-- Trees stand this far back from the plot fronts, in the grass between two bases; blossom trees there too, or this
-- much further back when a theme has both.
local TREE_BACK = 6
local BLOSSOM_BEHIND_TREES = 10
-- Painted eggs beside an entrance lean a little, each its own way (radians off the walkway direction).
local EGG_TURNS = { 0.2, -0.3, 0.35, -0.15 }
-- Hay bales are set down a little crooked, as if by hand (radians off the walkway direction).
local BALE_TURNS = { 0.1, -0.14, 0.06, -0.08 }
-- A rainbow's feet stand this far either side of its middle (the middle of its bands at scale 1: SeasonService builds
-- them from 3.1 to 8.2 studs out); its pot of gold stands on the right one.
SeasonRules.RAINBOW_FOOT = 5.65
SeasonRules.RAINBOW_RADIUS = 8.2
local RAINBOW_FOOT = SeasonRules.RAINBOW_FOOT
-- Beach umbrellas stand at the walkway, or this far back into the grass gap when a theme has lamps there too.
local UMBRELLA_BEHIND_LAMPS = 3

-- The seasonal-theme events: the ids of the LiveOps events that switch a theme on. Only one of them runs at a time
-- (LiveOpsRules.oneSeasonAtATime, DECISIONS.md #58), so only one's Snacklings and mutation can be live at once
-- (MutationRules.worstCaseTotal).
function SeasonRules.seasonalEventIds(config: SeasonsConfig): { [string]: boolean }
	local ids: { [string]: boolean } = {}
	for eventId, themeId in config.eventThemes do
		if config.themes[themeId] ~= nil then
			ids[eventId] = true
		end
	end
	return ids
end

-- The theme to show for the active events: among active events that map to a theme, the highest-priority theme
-- (ties: the alphabetically first event id, so every server agrees). Returns the theme id and the event that
-- switched it on, or nil when no themed event is active. Since only one seasonal event runs at a time
-- (seasonalEventIds), the live game only ever has one to choose from; the priority is for anything else that passes
-- several (tests, older configs).
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
	local rosesPerPlot = count(decorations.rosesPerPlot)
	local eggsPerPlot = count(decorations.eggsPerPlot)
	local balesPerPlot = count(decorations.hayBalesPerPlot)
	local patchesPerPlot = count(decorations.cloverPatchesPerPlot)
	local ringsPerPlot = count(decorations.swimRingsPerPlot)
	local ballsPerPlot = count(decorations.beachBallsPerPlot)
	local presentIndex = 0
	local roseIndex = 0
	local eggIndex = 0
	local baleIndex = 0
	local patchIndex = 0
	local ringIndex = 0
	local ballIndex = 0
	local pennantIndex = 0
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

		-- Potted rose bushes in the spots after those, facing the walkway, their blooms in cycling colours.
		for k = pumpkinsPerPlot + presentsPerPlot, pumpkinsPerPlot + presentsPerPlot + rosesPerPlot - 1 do
			roseIndex += 1
			local x, z = at(slot(k), 1.8)
			add({
				kind = "rosePot",
				x = x,
				y = map.groundY,
				z = z,
				faceX = entrance.outX,
				faceZ = entrance.outZ,
				scale = 1,
				color = cycle(palette.roses, roseIndex),
				color2 = cycle(palette.roses, roseIndex + 1),
			})
		end

		-- Giant painted eggs in the spots after those, each turned a little, in cycling shells and stripes.
		local firstEgg = pumpkinsPerPlot + presentsPerPlot + rosesPerPlot
		for k = firstEgg, firstEgg + eggsPerPlot - 1 do
			eggIndex += 1
			local x, z = at(slot(k), 1.8)
			local turn = EGG_TURNS[(eggIndex - 1) % #EGG_TURNS + 1]
			add({
				kind = "easterEgg",
				x = x,
				y = map.groundY,
				z = z,
				faceX = entrance.outX * math.cos(turn) - entrance.outZ * math.sin(turn),
				faceZ = entrance.outX * math.sin(turn) + entrance.outZ * math.cos(turn),
				scale = 1,
				color = cycle(palette.eggs, eggIndex),
				color2 = cycle(palette.eggStripes, eggIndex),
			})
		end

		-- Hay bales in the spots after those, their long side along the wall, each set down a little crooked.
		local firstBale = firstEgg + eggsPerPlot
		for k = firstBale, firstBale + balesPerPlot - 1 do
			baleIndex += 1
			local x, z = at(slot(k), 1.9)
			local turn = BALE_TURNS[(baleIndex - 1) % #BALE_TURNS + 1]
			add({
				kind = "hayBale",
				x = x,
				y = map.groundY,
				z = z,
				faceX = entrance.outX * math.cos(turn) - entrance.outZ * math.sin(turn),
				faceZ = entrance.outX * math.sin(turn) + entrance.outZ * math.cos(turn),
				scale = 1,
			})
		end

		-- Clover patches in the spots after those, each four-leaf clover turned its own way.
		local firstPatch = firstBale + balesPerPlot
		for k = firstPatch, firstPatch + patchesPerPlot - 1 do
			patchIndex += 1
			local x, z = at(slot(k), 2)
			local turn = EGG_TURNS[(patchIndex - 1) % #EGG_TURNS + 1] * 1.5
			add({
				kind = "cloverPatch",
				x = x,
				y = map.groundY,
				z = z,
				faceX = entrance.outX * math.cos(turn) - entrance.outZ * math.sin(turn),
				faceZ = entrance.outX * math.sin(turn) + entrance.outZ * math.cos(turn),
				scale = 1.2,
			})
		end

		-- Swim rings next, standing close to the wall and leaning back on it, facing the walkway.
		local firstRing = firstPatch + patchesPerPlot
		for k = firstRing, firstRing + ringsPerPlot - 1 do
			ringIndex += 1
			local x, z = at(slot(k), 1.2)
			add({
				kind = "swimRing",
				x = x,
				y = map.groundY,
				z = z,
				faceX = entrance.outX,
				faceZ = entrance.outZ,
				scale = 1,
				color = cycle(palette.rings, ringIndex),
			})
		end

		-- Then beach balls, each turned so its panels don't all line up.
		local firstBall = firstRing + ringsPerPlot
		for k = firstBall, firstBall + ballsPerPlot - 1 do
			ballIndex += 1
			local x, z = at(slot(k), 2)
			local turn = ballIndex * 0.7
			add({
				kind = "beachBall",
				x = x,
				y = map.groundY,
				z = z,
				faceX = entrance.outX * math.cos(turn) - entrance.outZ * math.sin(turn),
				faceZ = entrance.outX * math.sin(turn) + entrance.outZ * math.cos(turn),
				scale = 1,
				color = cycle(palette.ballPanels, ballIndex),
			})
		end

		-- String-light bulbs hanging along the front wall, split between both wall segments; bunting pennants between
		-- them, a little lower.
		local segment = (map.plotWidth - map.entranceWidth) / 2
		local function alongWall(kind: PropKind, n: number, offset: number, drop: number)
			local perSide = { math.ceil(n / 2), n // 2 }
			local index = 0
			for sideIndex, side in { -1, 1 } do
				local m = perSide[sideIndex]
				for j = 1, m do
					index += 1
					local lateral = side * (map.entranceWidth / 2 + (j - 0.5 + offset) * segment / (m + offset * 2))
					local x, z = at(lateral, 0.5)
					-- a gentle sag between the ends of each segment
					local sag = math.sin((j - 0.5 + offset) / (m + offset * 2) * math.pi) * 0.5
					local color: string? = nil
					if kind == "bulb" then
						color = cycle(palette.bulbs, index)
					else
						pennantIndex += 1
						color = cycle(palette.pennants, pennantIndex)
					end
					add({
						kind = kind,
						x = x,
						y = map.wallTopY - drop - sag,
						z = z,
						faceX = entrance.outX,
						faceZ = entrance.outZ,
						scale = 1,
						color = color,
					})
				end
			end
		end
		alongWall("bulb", count(decorations.bulbsPerPlot), 0, 0.5)
		alongWall("pennant", count(decorations.pennantsPerPlot), 0.5, 1.4)

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

	-- Lamp posts at the walkway between neighbouring plots on the same side of the belt, trees further back, blossom
	-- trees there too (or behind the trees), beach umbrellas, rainbows.
	local blossomIndex = 0
	local umbrellaIndex = 0
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
		if decorations.blossomTreesBetweenPlots then
			blossomIndex += 1
			local back = if decorations.treesBetweenPlots then TREE_BACK + BLOSSOM_BEHIND_TREES else TREE_BACK
			add({
				kind = "blossomTree",
				x = gap.x - gap.outX * back,
				y = map.groundY,
				z = gap.z - gap.outZ * back,
				faceX = gap.outX,
				faceZ = gap.outZ,
				scale = 1,
				color = cycle(palette.blossoms, blossomIndex),
				color2 = cycle(palette.blossoms, blossomIndex + 1),
			})
		end
		if decorations.scarecrowsBetweenPlots then
			-- in the grass gap, behind whichever trees the theme has, looking out at the walkway
			local back = TREE_BACK
			if decorations.treesBetweenPlots then
				back += BLOSSOM_BEHIND_TREES
			end
			if decorations.blossomTreesBetweenPlots then
				back += BLOSSOM_BEHIND_TREES
			end
			add({
				kind = "scarecrow",
				x = gap.x - gap.outX * back,
				y = map.groundY,
				z = gap.z - gap.outZ * back,
				faceX = gap.outX,
				faceZ = gap.outZ,
				scale = 1.2, -- about 10 studs tall, its arms 6 across
			})
		end
		if decorations.umbrellasBetweenPlots then
			umbrellaIndex += 1
			-- at the walkway where the lamps go, or a little back in the grass when there are lamps too
			local out = if decorations.lampsBetweenPlots then -UMBRELLA_BEHIND_LAMPS else 1.5
			add({
				kind = "beachUmbrella",
				x = gap.x + gap.outX * out,
				y = map.groundY,
				z = gap.z + gap.outZ * out,
				faceX = gap.outX,
				faceZ = gap.outZ,
				scale = 1,
				color = cycle(palette.umbrellas, umbrellaIndex),
				color2 = cycle(palette.umbrellas, umbrellaIndex + 1),
			})
		end
		if decorations.rainbowsBetweenPlots then
			-- arching over the grass gap behind whatever else stands in it, facing the walkway, its pot of gold at the
			-- foot on its own right (a frame facing (outX, outZ) has its right at (-outZ, outX)), a step in front
			local back = TREE_BACK
			for _, behind in
				{
					decorations.treesBetweenPlots,
					decorations.blossomTreesBetweenPlots,
					decorations.scarecrowsBetweenPlots,
				}
			do
				if behind then
					back += BLOSSOM_BEHIND_TREES
				end
			end
			local x, z = gap.x - gap.outX * back, gap.z - gap.outZ * back
			add({ kind = "rainbow", x = x, y = map.groundY, z = z, faceX = gap.outX, faceZ = gap.outZ, scale = 1 })
			add({
				kind = "potOfGold",
				x = x - gap.outZ * RAINBOW_FOOT + gap.outX * 1.2,
				y = map.groundY,
				z = z + gap.outX * RAINBOW_FOOT + gap.outZ * 1.2,
				faceX = gap.outX,
				faceZ = gap.outZ,
				scale = 1.15,
			})
		end
	end

	-- Small pumpkins, then small presents, then small roses, then small eggs, then small cornucopias, along both
	-- belt rails, facing away from the belt.
	local beltPumpkins = count(decorations.beltPumpkinsPerSide)
	local beltPresents = count(decorations.beltPresentsPerSide)
	local beltRoses = count(decorations.beltRosesPerSide)
	local beltEggs = count(decorations.beltEggsPerSide)
	local beltCornucopias = count(decorations.beltCornucopiasPerSide)
	local beltPots = count(decorations.beltPotsOfGoldPerSide)
	local beltBalls = count(decorations.beltBeachBallsPerSide)
	local beforePots = beltPumpkins + beltPresents + beltRoses + beltEggs + beltCornucopias
	local beltTotal = beforePots + beltPots + beltBalls
	for sideIndex, side in { -1, 1 } do
		for i = 1, beltTotal do
			local x = (i - (beltTotal + 1) / 2) * (map.beltLength / beltTotal)
			local z = side * (map.beltWidth / 2 + 2.2)
			if i > beforePots + beltPots then
				-- a beach ball resting by the rail, turned its own way
				local n = (sideIndex - 1) * beltBalls + (i - beforePots - beltPots)
				local turn = n * 1.1
				add({
					kind = "beachBall",
					x = x,
					y = map.groundY,
					z = z,
					faceX = math.sin(turn),
					faceZ = math.cos(turn),
					scale = 0.7,
					color = cycle(palette.ballPanels, n + 1),
				})
			elseif i > beforePots then
				-- a little pot of chocolate coins, its heap of gold towards the walkway
				add({
					kind = "potOfGold",
					x = x,
					y = map.groundY,
					z = z,
					faceX = 0,
					faceZ = side,
					scale = 0.85,
				})
			elseif i > beltPumpkins + beltPresents + beltRoses + beltEggs then
				-- lying along the rail, its mouth spilling the harvest towards the walkway
				add({
					kind = "cornucopia",
					x = x,
					y = map.groundY,
					z = z,
					faceX = 0,
					faceZ = side,
					scale = 0.9,
				})
			elseif i > beltPumpkins + beltPresents + beltRoses then
				local n = (sideIndex - 1) * beltEggs + (i - beltPumpkins - beltPresents - beltRoses)
				add({
					kind = "easterEgg",
					x = x,
					y = map.groundY,
					z = z,
					faceX = 0,
					faceZ = side,
					scale = 0.7,
					color = cycle(palette.eggs, n + 2),
					color2 = cycle(palette.eggStripes, n + 1),
				})
			elseif i <= beltPumpkins + beltPresents then
				local isPumpkin = i <= beltPumpkins
				local n = (sideIndex - 1) * beltPresents + (i - beltPumpkins)
				add({
					kind = if isPumpkin then "pumpkin" else "present",
					x = x,
					y = map.groundY,
					z = z,
					faceX = 0,
					faceZ = side,
					scale = 0.7,
					color = if isPumpkin then nil else cycle(palette.presents, n + 2),
					color2 = if isPumpkin then nil else cycle(palette.ribbons, n + 1),
				})
			else
				local n = (sideIndex - 1) * beltRoses + (i - beltPumpkins - beltPresents)
				add({
					kind = "rosePot",
					x = x,
					y = map.groundY,
					z = z,
					faceX = 0,
					faceZ = side,
					scale = 0.7,
					color = cycle(palette.roses, n + 1),
					color2 = cycle(palette.roses, n + 2),
				})
			end
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

	-- Heart balloons floating over the walkway, lower than the bats and a little closer to the belt, turned to face
	-- across it (a little off square, so a row of them doesn't look stamped out).
	local balloons = count(decorations.heartBalloons)
	for i = 1, balloons do
		local zSide = if i % 2 == 0 then 1 else -1
		local turn = ((i % 3) - 1) * 0.35
		add({
			kind = "heartBalloon",
			x = (i - 0.5 - balloons / 2) * (map.beltLength * 0.9 / balloons),
			y = 12 + (i % 3) * 2,
			z = zSide * map.walkwayWidth * 0.48,
			faceX = math.sin(turn),
			faceZ = -zSide * math.cos(turn),
			scale = 1,
			color = cycle(palette.balloons, i),
		})
	end

	-- Butterflies hovering over the walkway, lower than the balloons and nearer the bases, each facing its own way.
	local butterflies = count(decorations.butterflies)
	for i = 1, butterflies do
		local zSide = if i % 2 == 0 then 1 else -1
		local angle = i * 2.4
		add({
			kind = "butterfly",
			x = (i - 0.5 - butterflies / 2) * (map.beltLength * 0.9 / butterflies),
			y = 8.5 + (i % 3) * 1.2,
			z = zSide * map.walkwayWidth * 0.62,
			faceX = math.cos(angle),
			faceZ = math.sin(angle),
			scale = 1,
			color = cycle(palette.butterflies, i),
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

	-- Snowmen at the corners of both belt ends (clear of the factory and the chute), looking along the walkway; giant
	-- hearts in the next spots out, then chocolate bunnies.
	local snowmen = count(decorations.snowmen)
	local function corner(i: number): (number, number, number)
		local endSide = if i % 2 == 1 then -1 else 1
		local zSide = if ((i - 1) // 2) % 2 == 0 then -1 else 1
		local row = (i - 1) // 4
		return endSide, zSide, row
	end
	for i = 1, snowmen do
		local endSide, zSide, row = corner(i)
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
	local giantHearts = count(decorations.giantHearts)
	for i = 1, giantHearts do
		local endSide, zSide, row = corner(snowmen + i)
		add({
			kind = "giantHeart",
			x = endSide * (map.beltLength / 2 + 8 + row * 7),
			y = map.groundY,
			z = zSide * (12 + row * 2),
			faceX = -endSide,
			faceZ = 0,
			scale = 1,
		})
	end
	local bunnies = count(decorations.chocolateBunnies)
	for i = 1, bunnies do
		local endSide, zSide, row = corner(snowmen + giantHearts + i)
		add({
			kind = "chocolateBunny",
			x = endSide * (map.beltLength / 2 + 8 + row * 7),
			y = map.groundY,
			z = zSide * (12 + row * 2),
			faceX = -endSide,
			faceZ = 0,
			scale = 1.3, -- a landmark: about 11 studs tall
		})
	end
	local cornStalks = count(decorations.cornStalks)
	for i = 1, cornStalks do
		local endSide, zSide, row = corner(snowmen + giantHearts + bunnies + i)
		add({
			kind = "cornStalk",
			x = endSide * (map.beltLength / 2 + 8 + row * 7),
			y = map.groundY,
			z = zSide * (12 + row * 2),
			faceX = -endSide,
			faceZ = 0,
			scale = 1.3, -- a landmark: about 11 studs tall
		})
	end
	local sandcastles = count(decorations.sandcastles)
	for i = 1, sandcastles do
		local endSide, zSide, row = corner(snowmen + giantHearts + bunnies + cornStalks + i)
		add({
			kind = "sandcastle",
			x = endSide * (map.beltLength / 2 + 8 + row * 7),
			y = map.groundY,
			z = zSide * (12 + row * 2),
			faceX = -endSide,
			faceZ = 0,
			scale = 1.3, -- a landmark: its tallest tower about 9 studs up
		})
	end
	for i = 1, count(decorations.shamrocks) do
		local endSide, zSide, row = corner(snowmen + giantHearts + bunnies + cornStalks + sandcastles + i)
		add({
			kind = "shamrock",
			x = endSide * (map.beltLength / 2 + 8 + row * 7),
			y = map.groundY,
			z = zSide * (12 + row * 2),
			faceX = -endSide,
			faceZ = 0,
			scale = 1.3, -- a landmark: about 11 studs tall
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
	if lighting.hideSun ~= nil and type(lighting.hideSun) ~= "boolean" then
		table.insert(problems, `{name} lighting.hideSun must be true, false or nil`)
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
