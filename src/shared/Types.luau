--!strict
--[[
	Canonical data types shared by Config (the data), Logic (the rules), the server and the client.

	Luau tables are invariant, so a `{ CreatureDef }` can only be passed where exactly `{ CreatureDef }` is
	expected. Keeping one definition here (instead of narrower per-module copies) is what lets config flow into
	the pure logic modules without casts. Types only: this module has no runtime content.
]]

-- Config: rarities and creatures ------------------------------------------------------------------------------

export type RarityDef = {
	id: string,
	order: number,
	displayName: string,
	color: string, -- "#RRGGBB"
	beltWeight: number, -- relative chance for the conveyor to pick this tier
	luckAffected: boolean, -- luck boosts multiply this tier's weight
	glow: boolean,
	particles: boolean,
	announceOnSpawn: boolean,
	announceOnBuy: boolean,
	announceOnSteal: boolean,
	modelScale: number,
}

-- The 3D model of each creature is a recipe in Config/CreatureLooks (keyed by id, see "Snackling model recipes" below).
export type CreatureDef = {
	id: string,
	displayName: string,
	rarity: string,
	price: number,
	income: number,
	beltWeight: number,
	modelName: string,
	flavor: string,
	eventId: string?,
}

-- Config: Snackling model recipes (Config/CreatureLooks, turned into parts by Logic/CreatureRecipe) ---------------
-- Sizes are in units of the recipe's `size` (1 = the creature's size in studs), colours are "#RRGGBB" and materials
-- are Enum.Material names. Every kind and style is documented in Logic/CreatureRecipe.

-- How body and head are arranged (legs, arms, where the face goes).
export type LookPlan = "blob" | "biped" | "quadruped" | "swimmer" | "tentacled"

-- The food shape a body or head is made of.
export type LookSkin =
	"round"
	| "lumpy"
	| "slice"
	| "roll"
	| "can"
	| "stack"
	| "macaron"
	| "cup"
	| "flan"
	| "ring"
	| "block"
	| "bun"
	| "cone"
	| "pear"
	| "bowl"

export type LookVolume = {
	skin: LookSkin,
	color: string,
	color2: string?, -- second colour of the skin (crust, liner, filling, icing...)
	color3: string?,
	w: number?, -- width / height / depth in units (each plan has defaults)
	h: number?,
	d: number?,
	n: number?, -- count used by some skins (layers, lumps)
	style: string?, -- skin variant
	material: string?,
}

export type LookEyes = "round" | "big" | "dot" | "happy" | "sleepy" | "stalk"
export type LookMouth = "smile" | "open" | "tongue" | "fang" | "o" | "cat" | "grin" | "none"

export type LookFace = {
	eyes: LookEyes?,
	mouth: LookMouth?,
	cheeks: string?, -- blush colour
	brows: string?, -- eyebrow colour
	nose: string?, -- small nose colour (creatures with a snout get theirs from the snout)
	pupil: string?, -- pupil colour (default near-black)
	patches: string?, -- dark patches behind the eyes (pandas)
	mouthColor: string?, -- default a dark red-brown
	mouthAt: number?, -- mouth height, -1..1 of the face's half-height (default: half a face below the eyes)
	spacing: number?, -- eye distance from the centre line, 0..1 of the face's half-width
	height: number?, -- eye height, -1..1 of the face's half-height
	scale: number?, -- eye size multiplier
}

export type LookFeatureKind =
	"ears"
	| "horns"
	| "antennae"
	| "tail"
	| "wings"
	| "shell"
	| "mane"
	| "snout"
	| "whiskers"
	| "spikes"
	| "fins"
	| "tusks"
	| "claws"
	| "legs"
	| "belly"
	| "mask"
	| "spots"
	| "stripes"
	| "fan"
	| "crest"
	| "heads"
	| "straw"
	| "bubble"
	| "flame"
	| "bow"
	| "teeth"
	| "segments"
	| "sides"
	| "handle"
	| "slip"

export type LookFeature = {
	kind: LookFeatureKind,
	style: string?,
	color: string?, -- default: the colour of what it attaches to
	color2: string?,
	color3: string?,
	n: number?,
	scale: number?,
	on: string?, -- "body" | "head" (default depends on the kind)
	material: string?,
}

export type LookToppingKind =
	"sprinkles"
	| "seeds"
	| "chips"
	| "discs"
	| "drips"
	| "cap"
	| "swirl"
	| "cherry"
	| "leaf"
	| "band"
	| "sticks"
	| "strands"
	| "balls"
	| "crumbs"
	| "egg"
	| "swirlmark"
	| "zigzag"
	| "bits"
	| "spikes"
	| "pat"

export type LookTopping = {
	kind: LookToppingKind,
	colors: { string }, -- cycled through the pieces
	n: number?,
	scale: number?,
	spread: number?, -- 0..1: how far from the centre pieces are scattered
	on: string?, -- "body" | "head" | "shell" (default: the head if there is one, else the body)
	at: number?, -- height on the shape for bands / drips (-1..1)
	style: string?,
	material: string?,
}

export type CreatureLook = {
	size: number, -- overall size in studs before the rarity's modelScale
	plan: LookPlan,
	body: LookVolume,
	head: LookVolume?, -- biped / quadruped only (default: a round head in the body colour)
	face: LookFace,
	limbs: string?, -- legs / feet / arms / tentacles colour (default: body colour)
	arms: boolean?, -- blob: little arms; biped: arms unless false
	feet: boolean?, -- blob / tentacled-free plans: little feet
	legs: number?, -- quadruped / biped leg length in units
	neck: number?, -- biped / quadruped: lifts the head on a neck this long (units)
	tentacles: number?, -- tentacled: how many (default 6)
	features: { LookFeature }, -- may be empty
	toppings: { LookTopping }, -- may be empty
}

-- A polished Snackling model imported from Claude Design (Config/CreatureParts, Logic/CreatureRecipe.compileImported).
export type ImportedModel = {
	scale: number, -- studs per design unit at rarity scale 1
	-- { name, shape, size {x, y, z}, position {x, y, z}, rotation {x, y, z} degrees, color, material, role,
	-- transparency? }
	parts: { { any } },
}

-- Config: mutations (rare variants of any creature) --------------------------------------------------------------

-- How a mutation changes a model, on top of its rarity flair. Applied to every visible part except the face
-- (placeholder models) and parts with the attribute MutationSkip = true (custom models).
export type MutationLook = {
	material: string, -- Enum.Material item name, e.g. "Foil"
	tint: string?, -- "#RRGGBB" blended into each part's colour
	tintStrength: number?, -- 0..1, how far towards `tint` (default 1 = replace the colour)
	transparency: number?, -- minimum part transparency (glassy looks)
	reflectance: number?,
	sparkles: boolean?, -- sparkle particles in the mutation colour
	rainbow: boolean?, -- hue-cycling colours (animated on the client) and rainbow particles
	glow: string?, -- "#RRGGBB": a soft point light in this colour (ghostly / glowing looks)
	particles: string?, -- a particle preset around the body (Logic/Catalog.MUTATION_PARTICLES: "snow", "embers"...)
	halo: boolean?, -- a glowing golden ring floating above the head
}

export type MutationDef = {
	id: string, -- saved in CreatureRecord.variant: never rename or remove one that has shipped
	displayName: string,
	color: string, -- "#RRGGBB", labels and banners
	order: number, -- display / roll order, rarest last
	chance: number, -- probability per belt spawn, independent of rarity and luck
	incomeMultiplier: number,
	priceMultiplier: number,
	announceOnSpawn: boolean,
	announceOnBuy: boolean,
	announceOnSteal: boolean,
	look: MutationLook,
	-- At most one gate (none = it can roll on any spawn):
	eventId: string?, -- only rolls while this LiveOps event is active
	mapTheme: string?, -- only rolls while this map theme (Config/MapThemes) is up: the map's signature mutation
	modifierId: string?, -- only rolls while this server modifier (Config/Modifiers) runs
}

-- Config: LiveOps ---------------------------------------------------------------------------------------------

export type EventDef = {
	id: string,
	startsAt: number,
	endsAt: number,
	luckMultiplier: number?,
	cashMultiplier: number?,
	bannerText: string?,
	title: string?, -- short name for the HUD countdown ("Halloween ends in 3d 4h")
	durationSeconds: number?,
}

-- Config: seasonal themes (Config/Seasons) --------------------------------------------------------------------

-- Lighting while a theme is on. Colours are "#RRGGBB"; the server puts the original values back when it ends.
export type SeasonAtmosphere = {
	density: number, -- 0..1 (fog)
	offset: number, -- 0..1
	color: string,
	decay: string,
	glare: number, -- 0..10
	haze: number, -- 0..10
}

export type SeasonColorCorrection = {
	tint: string,
	brightness: number, -- -1..1
	contrast: number, -- -1..1
	saturation: number, -- -1..1
}

export type SeasonLighting = {
	clockTime: number, -- 0..24 (17.8 = dusk)
	brightness: number,
	ambient: string,
	outdoorAmbient: string,
	colorShiftTop: string,
	atmosphere: SeasonAtmosphere,
	colorCorrection: SeasonColorCorrection,
	clouds: { cover: number, density: number, color: string }?, -- nil: the map's clouds
}

-- How many of each code-built prop the server places (0 / nil = none). Positions come from the map layout.
export type SeasonDecorations = {
	pumpkinsPerPlot: number?, -- glowing jack-o'-lanterns beside each plot entrance
	beltPumpkinsPerSide: number?, -- smaller ones along both belt rails
	bulbsPerPlot: number?, -- string-light bulbs along each plot's front wall
	lampsBetweenPlots: boolean?, -- lamp posts in the gaps between plots
	bats: number?, -- floating above the walkway
	ghosts: number?, -- near the leaderboards at the belt ends
	presentsPerPlot: number?, -- wrapped presents beside each plot entrance (after any pumpkins)
	beltPresentsPerSide: number?, -- smaller ones along both belt rails (after any pumpkins)
	treesBetweenPlots: boolean?, -- decorated trees in the gaps between plots, a little back from the walkway
	snowmen: number?, -- at the belt ends (the ghosts' spots)
	snowflakes: number?, -- big flakes hanging above the walkway (the bats' spots, a little higher)
	snowPilesPerPlot: number?, -- snowdrifts along each plot's front wall, from the corners in (1 or 2)
	rosesPerPlot: number?, -- potted rose bushes beside each plot entrance (after any pumpkins and presents)
	beltRosesPerSide: number?, -- smaller ones along both belt rails (after any pumpkins and presents)
	heartBalloons: number?, -- heart-shaped balloons floating above the walkway
	giantHearts: number?, -- big hearts pierced by Cupid's arrow at the belt ends (after any snowmen)
}

-- Colours of the props a theme uses ("#RRGGBB"). Only the keys of the props a theme places are needed
-- (Logic/SeasonRules.PALETTE_KEYS lists them per prop); lists are cycled through.
export type SeasonPalette = {
	bulbs: { string }, -- string lights (may be empty when the theme has none)
	pumpkin: string?,
	pumpkinFace: string?, -- glowing eyes / mouth (and their light)
	stem: string?,
	lampPost: string?,
	lampLight: string?,
	bat: string?,
	ghost: string?,
	presents: { string }?, -- wrapping paper
	ribbons: { string }?, -- ribbon and bow
	tree: string?, -- the tree's tiers
	wood: string?, -- the tree's trunk and a snowman's stick arms
	treeStar: string?, -- the glowing star on top
	ornaments: { string }?, -- baubles
	snow: string?, -- snowmen and snowdrifts
	carrot: string?, -- a snowman's nose
	coal: string?, -- a snowman's eyes and buttons
	scarf: string?,
	hat: string?,
	snowflake: string?,
	pot: string?, -- rose pots
	leaves: string?, -- rose bushes
	roses: { string }?, -- rose blooms
	balloons: { string }?, -- heart balloons
	balloonString: string?,
	heart: string?, -- the giant hearts
	pedestal: string?,
	arrow: string?, -- Cupid's arrow through each giant heart
}

export type SeasonTheme = {
	displayName: string,
	accentColor: string, -- HUD event pill and the "EVENT" tag on this event's Snacklings
	priority: number, -- when several themed events overlap, the highest priority wins
	lighting: SeasonLighting?,
	-- Particles around every player while the theme is on, instead of the map's own (a weather modifier's still win).
	-- nil: the map's weather.
	weather: WeatherKind?,
	decorations: SeasonDecorations,
	palette: SeasonPalette,
}

export type SeasonsConfig = {
	eventThemes: { [string]: string }, -- LiveOps event id -> theme id
	themes: { [string]: SeasonTheme },
	maxParts: number, -- decoration part budget (CI checks every theme's estimate against it)
	transitionSeconds: number, -- lighting fades in / out over this long
}

-- Config: scenery (Config/Scenery): the world's look around the gameplay geometry -----------------------------------

-- The everyday lighting MapBuilder applies at server start (a seasonal theme fades from it and back to it).
export type SceneryLighting = {
	clockTime: number, -- 0..24
	geographicLatitude: number,
	brightness: number,
	exposureCompensation: number,
	ambient: string,
	outdoorAmbient: string,
	colorShiftTop: string,
	colorShiftBottom: string,
	environmentDiffuseScale: number, -- 0..1
	environmentSpecularScale: number, -- 0..1
	shadowSoftness: number, -- 0..1
	atmosphere: SeasonAtmosphere,
	colorCorrection: SeasonColorCorrection,
	bloom: { intensity: number, size: number, threshold: number },
	sunRays: { intensity: number, spread: number },
	sky: { sunAngularSize: number, moonAngularSize: number, starCount: number },
	clouds: { cover: number, density: number, color: string },
}

-- The play area is a rectangle with a low stone wall (and an invisible barrier above it) on its edge.
export type SceneryBoundary = {
	minX: number,
	maxX: number,
	minZ: number,
	maxZ: number,
	wallHeight: number, -- the visible wall
	wallThickness: number,
	barrierHeight: number, -- invisible, collidable: nobody jumps out
}

-- A terrain hill: a sphere of `radius` sunk into the ground so its top is `height` above it.
export type HillDef = { x: number, z: number, radius: number, height: number }
export type RockDef = { x: number, z: number, radius: number }
export type LakeDef = { x: number, z: number, radius: number, depth: number }

export type SceneryTerrain = {
	extent: number, -- grass reaches this far from the map centre (studs, in X and Z)
	depth: number, -- thickness of the grass layer under y = 0
	hills: { HillDef },
	rocks: { RockDef },
	lake: LakeDef?,
}

-- The spawn plaza past the belt's east end. Ring items are placed by angle (degrees; x = x0 + r cos a,
-- z = z0 + r sin a, so 180 points back along the belt).
export type SceneryPlaza = {
	x: number,
	z: number,
	radius: number, -- paving
	fountainRadius: number,
	archX: number, -- the "Steal a Snackling" archway over the path from the walkway
	archSpan: number, -- distance between its pillars
	pathWidth: number,
	boardX: number, -- the two leaderboards flank the archway at z = ±boardZ
	boardZ: number,
	benchRadius: number,
	benchAngles: { number },
	lampRadius: number,
	lampAngles: { number },
	flowerRadius: number,
	flowerAngles: { number },
	extraFlowerBeds: { { x: number, z: number, yaw: number } },
	treeRadius: number,
	treeAngles: { number },
}

export type TreeKind = "round" | "pine"
export type TreeDef = { x: number, z: number, scale: number?, kind: TreeKind? }

-- A spot for a map's landmark, well outside the boundary wall (out of reach): `scale` sizes what stands there.
export type LandmarkSpot = { x: number, z: number, scale: number? }

export type SceneryConfig = {
	lighting: SceneryLighting,
	boundary: SceneryBoundary,
	terrain: SceneryTerrain,
	plaza: SceneryPlaza,
	trees: { TreeDef }, -- inside the boundary (around the bases)
	treeLine: { count: number, minDistance: number, maxDistance: number, seed: number }, -- outside the wall
	landmarkSpots: { LandmarkSpot }, -- each map's big props (Config/MapThemes landmarks) stand here
	chevronSpacing: number, -- belt markings
	partBudget: number, -- every part MapBuilder + SceneryBuilder add on top of the gameplay geometry
}

-- Config: map themes (Config/MapThemes): the world's look changes, the gameplay geometry never does ------------------

-- What grows on the tree spots. Each map picks one kind for the spots the default map fills with round trees and one
-- for its pines; every kind fits inside the footprint of the tree it replaces (Logic/MapThemeRules.FLORA_RADIUS), so
-- the scenery checks hold on every map.
export type FloraKind =
	"round"
	| "pine"
	| "snowyPine"
	| "lollipop"
	| "gumdropTree"
	| "palm"
	| "cactus"
	| "deadTree"
	| "crystal"
	| "mushroom"
	| "bush"
	| "blossomTree"
	| "bamboo"
	| "alienPlant"
	| "moonRock"
	| "jungleTree"
	| "fern"
	| "planterTree"
	| "streetLamp"
	| "cloudTree"
	| "cloudPillar"
	| "coral"
	| "kelp"
	| "dippedStrawberry"
	| "cocoaTree"
	| "cottonCandyTree"
	| "balloonBunch"
	| "oliveTree"
	| "cypress"
	| "rockCandyStick"
	| "lemonTree"
	| "gumTree"
	| "bubblePlant"

-- Big props on Config/Scenery.landmarkSpots, outside the boundary wall (decoration only). Floating kinds (balloons,
-- clouds, lanterns) hang in the sky above their spot.
export type LandmarkKind =
	"balloon"
	| "windmill"
	| "giantLollipop"
	| "candyCane"
	| "cottonCloud"
	| "iceSpire"
	| "snowman"
	| "mesa"
	| "giantCactus"
	| "volcano"
	| "lavaPillar"
	| "giantMushroom"
	| "skyLantern"
	| "lighthouse"
	| "beachUmbrella"
	| "barn"
	| "hayBales"
	| "torii"
	| "pagoda"
	| "rocket"
	| "planet"
	| "satelliteDish"
	| "temple"
	| "giantFlower"
	| "skyscraper"
	| "neonSign"
	| "floatingIsland"
	| "skyCastle"
	| "shipwreck"
	| "giantClam"
	| "chocolateFountain"
	| "ferrisWheel"
	| "circusTent"
	| "leaningTower"
	| "pizzaOven"
	| "geode"
	| "lemonadeStand"
	| "giantLemonSlice"
	| "stiltHouse"
	| "giantBubble"

-- Particles drifting around each player's camera (client, WeatherController; off with Reduce effects).
export type WeatherKind =
	"none"
	| "snow"
	| "embers"
	| "leaves"
	| "fireflies"
	| "sprinkles"
	| "dust"
	| "petals"
	| "rain"
	| "spores"
	| "stardust"
	| "pollen"
	| "feathers"
	| "bubbles"
	| "shavings"
	| "confetti"
	| "fizz"
	| "heat"

export type MapThemeDef = {
	displayName: string,
	icon: string, -- emoji on the vote buttons and the title card
	tagline: string, -- one line under the title card
	accentColor: string, -- vote button, title card and announcement
	weight: number, -- how often it comes up (first map, vote candidates); 0 = only by command
	-- Config/Theme.world colours this map changes. Scenery only: plots, podiums, pads, the lock button and the belt
	-- keep their colours on every map (Logic/MapThemeRules.FIXED_KEYS).
	palette: { [string]: string },
	lighting: SceneryLighting,
	groundMaterial: string, -- Enum.Material name: the play area's ground part
	walkwayMaterial: string, -- the walkway between the plots and the belt
	boundaryMaterial: string, -- the boundary wall
	water: { transparency: number, reflectance: number }, -- terrain water (colour: palette.terrainWater)
	flora: { round: FloraKind, pine: FloraKind },
	landmarks: { LandmarkKind }, -- cycled over Config/Scenery.landmarkSpots
	weather: WeatherKind,
}

export type MapRotation = {
	enabled: boolean, -- false: a server keeps its first map
	mapSeconds: number, -- how long each map stays
	voteSeconds: number, -- the vote for the next map runs this long, ending as the map changes
	candidates: number, -- maps on the ballot (never the current one)
}

-- Config: server modifiers (Config/Modifiers): short random twists that change how the server plays -----------------

-- What a modifier changes, as multipliers (1 = unchanged; a missing field is 1). Each stays inside
-- Config/Modifiers.limits (Logic/ModifierRules.validate).
export type ModifierEffects = {
	spawnInterval: number?, -- × the belt's spawn interval (0.5 = twice as many Snacklings)
	beltPrice: number?, -- × belt prices
	mutationChance: number?, -- × every mutation's chance per spawn
	luck: number?, -- × server luck (a LiveOps boost: it shows in the luck pill and is capped like the others)
	income: number?, -- × everyone's income (capped with LiveOps cash events at limits.maxCashMultiplier)
	walkSpeed: number?, -- × everyone's walking speed (carrying thieves too)
	stealHold: number?, -- × the hold-to-steal time
	lockDuration: number?, -- × base lock time (locks started while it runs)
	tagRange: number?, -- × how far a tag reaches
}

-- An effect in the sky while a weather modifier runs (client only; off with Reduce effects).
export type SkyEffect = "lightning" | "meteors" | "aurora"

-- Things a modifier drops on the walkways while it runs (DropService, Config/Drops): supply crates (hold to open,
-- first player wins), a shower of coins (walk over them) or a runaway Snackling (catch it); or a giant Snackling over
-- the belt that everyone taps together (BossService, Config/Boss).
export type ModifierDrops = {
	kind: "crate" | "coins" | "runaway" | "boss",
	firstSeconds: number, -- the first drop this long after the modifier starts
	everySeconds: number, -- then one every this long until it ends
}

export type ModifierDef = {
	displayName: string,
	icon: string, -- emoji on the HUD chip and the banner
	description: string, -- the start banner and the chip's tap toast; keep it short
	color: string, -- chip and banner colour
	weight: number, -- how often it comes up; 0 = only by command
	effects: ModifierEffects, -- may be empty when the modifier unlocks a mutation (Config/Mutations modifierId)
	-- Weather while it runs (looks only, all optional): particles around each player instead of the map's, a lighting
	-- overlay over the map's (and a seasonal theme's) and an effect in the sky.
	weather: WeatherKind?,
	lighting: SeasonLighting?,
	skyEffect: SkyEffect?,
	drops: ModifierDrops?, -- crates, coins or runaways on the walkways (Config/Drops)
	-- A private server's owner may start it from the host panel (Config/Host). Only modifiers that leave the economy
	-- alone: no luck, mutations, income, sale prices, faster belt, drops or mutation-unlocking weather (CI checks).
	hostable: boolean?,
}

export type ModifierSchedule = {
	enabled: boolean,
	durationSeconds: number, -- how long each modifier runs
	gapMinSeconds: number, -- a random break between two modifiers
	gapMaxSeconds: number,
	firstDelaySeconds: number, -- a new server waits this long before the first one
}

export type ModifiersConfig = {
	modifiers: { [string]: ModifierDef },
	order: { string }, -- every modifier id once (display order; ties in picks resolve by it)
	schedule: ModifierSchedule,
	limits: { [string]: { min: number, max: number } }, -- allowed range of each effect
}

-- Config: playtime gifts (Config/Gifts) and the Lucky Spin (Config/Spin) ------------------------------------------

-- What a gift or a spin gives: cash sized from steady income (like a cash pack), spins for the Lucky Spin, or a
-- Snackling rolled at `luck` x the server's luck (sold for its refund when the base is full), optionally always with
-- `mutation`.
export type PrizeReward =
	{ kind: "cash", incomeSeconds: number, minimum: number }
	| { kind: "spin", count: number }
	| { kind: "creature", luck: number, mutation: string? }

export type GiftDef = {
	minutes: number, -- minutes played today before it unlocks
	icon: string,
	reward: PrizeReward,
}

export type GiftsConfig = {
	ladder: { GiftDef }, -- in unlock order
}

export type SpinSegment = {
	id: string,
	label: string, -- on its reel tile, e.g. "Jackpot!"
	icon: string,
	color: string, -- the tile's colour
	weight: number, -- chance = weight / total
	reward: PrizeReward, -- never "spin"
}

export type SpinConfig = {
	freeEverySeconds: number, -- a free spin this long after the last free one
	maxBanked: number, -- spins from gifts beyond this are paid as cash instead (Logic/SpinRules)
	bankedOverflow: { incomeSeconds: number, minimum: number }, -- that cash, per spin
	segments: { SpinSegment },
}

-- Config: achievements (Config/Achievements) -------------------------------------------------------------------------

-- What an achievement counts (Logic/AchievementRules.progress reads each from the save):
--   beltPurchases / steals / rebirths / spins   counters
--   earned        total cash ever earned
--   discovered    Snacklings in the Snackdex (any)
--   allRegular    every regular Snackling discovered (target ignored: the current roster size)
--   rarity        owning a Snackling of `rarity` or rarer (target 1)
--   mutations     different mutations owned (on any Snackling)
--   maps          different maps played on
--   stolenFrom    times a Snackling was stolen from the player
--   income        the best steady income per second ever reached
--   playHours     hours played (fractional, so the bar moves)
--   limited       limited (event) Snacklings in the Snackdex
--   tiers         Snackdex tiers completed
--   streak        the daily reward streak (consecutive days claimed)
--   codes         redeem codes used
--   milestone     something done at least once, recorded where it happens (`milestone`; target 1)
export type AchievementGoal =
	"beltPurchases"
	| "steals"
	| "rebirths"
	| "spins"
	| "earned"
	| "discovered"
	| "allRegular"
	| "rarity"
	| "mutations"
	| "maps"
	| "stolenFrom"
	| "income"
	| "playHours"
	| "limited"
	| "tiers"
	| "streak"
	| "codes"
	| "milestone"

export type AchievementDef = {
	id: string, -- saved as the flag ach_<id>: never rename one that has shipped
	title: string,
	description: string,
	icon: string,
	goal: AchievementGoal,
	target: number,
	rarity: string?, -- for goal "rarity"
	milestone: string?, -- for goal "milestone": one of AchievementRules.MILESTONES
	reward: PrizeReward,
	badgeId: number?, -- a Roblox badge to award too (create it in the Creator Hub, paste its id); nil = none
}

export type AchievementsConfig = { list: { AchievementDef } }

-- One achievement as the Trophies tab shows it.
export type AchievementView = { id: string, progress: number, target: number, done: boolean }

-- Config: redeem codes (server/Codes.luau, server-only so codes never reach a client) --------------------------------

-- What a code gives: cash sized from the player's steady income (like a cash pack), or a Snackling (with a mutation
-- or plain) on a free podium.
export type CodeReward =
	{ kind: "cash", incomeSeconds: number, minimum: number }
	| { kind: "creature", creatureId: string, variant: string? }

export type CodeDef = {
	reward: CodeReward,
	expiresAt: number?, -- unix seconds (UTC); nil = never
}

-- Codes by their text: letters and digits only, any case when typed (CodeRules.normalize upper-cases it).
export type CodesConfig = { [string]: CodeDef }

-- Config: drops (Config/Drops): what Supply Drop and Coin Rain put on the walkways -------------------------------

-- Rewards are IncomeReward (below): sized from the player's steady income, like a cash pack.
-- Config: Snack Attack (Config/Boss): a giant Snackling over the middle of the belt that everyone taps together -----
export type BossConfig = {
	hpPerPlayer: number, -- hits it takes for each player in the server when it appears
	minHp: number,
	hitsPerSecond: number, -- the most hits the server counts from one player (taps beyond it are ignored)
	burst: number, -- hits a player can land at once before the limit kicks in
	reach: number, -- studs from its middle a player can tap it from (the server allows a little more)
	lifetimeSeconds: number, -- not taken down within this long, it flies off and nothing is paid
	scale: number, -- times its podium size
	hoverHeight: number, -- studs between the walkway and its feet (clear of the belt and the players)
	rarities: { string }, -- the giant is a regular Snackling of one of these tiers (looks only)
	minHits: number, -- hits a player needs to share the reward
	cash: { baseSeconds: number, shareSeconds: number, minimum: number }, -- each helper: steady income x (base +
	-- share x their share of all hits), at least the minimum
	luck: number, -- × server luck for the top hitter's Snackling
	mutationChance: number, -- × mutation chances for it
}

export type DropsConfig = {
	-- Where drops land: a band on each side of the belt, between it and the bases (world X / Z; mirrored in Z).
	area: { minX: number, maxX: number, minZ: number, maxZ: number },
	crate: {
		fallSeconds: number, -- parachuting down from the sky
		dropHeight: number, -- studs above the walkway it starts falling from
		holdSeconds: number, -- hold to open (the server re-checks it, like a steal)
		holdTolerance: number, -- share of holdSeconds the server accepts (network jitter)
		openRange: number, -- studs from the crate (the client prompt's reach; the server allows a little more)
		lifetimeSeconds: number, -- an unopened crate vanishes this long after landing
		luck: number, -- × server luck for the Snackling inside
		mutationChance: number, -- × mutation chances for it
		cash: IncomeReward, -- cash inside as well
	},
	coins: {
		perWave: number,
		height: number, -- studs above the walkway they float at
		lifetimeSeconds: number,
		pickupRange: number, -- horizontal studs from a coin's centre to the player's root
		value: IncomeReward, -- each coin
	},
	-- A Snackling that escaped the factory and runs along a walkway, away from whoever comes near: walk into it to
	-- catch it (Logic/DropRules.runawayTarget plans each leg; the client follows the same legs).
	runaway: {
		speed: number, -- studs per second while it wanders
		sprintSpeed: number, -- while someone is within fleeRadius (slower than players: Gameplay.walkSpeed)
		pauseSeconds: number, -- it stops this long at every turn while it wanders
		sprintPauseSeconds: number, -- and this long while it flees
		legMin: number, -- studs per leg
		legMax: number,
		candidates: number, -- spots it considers for each leg (and for where it appears)
		fleeRadius: number, -- players nearer than this scare it; farther ones don't
		edgeMargin: number, -- it appears at least this far from the ends of the walkways
		beltHopPenalty: number, -- studs a spot over the belt counts less (higher: it hops over less often)
		catchRange: number, -- horizontal studs from its centre to a player's root (the server allows a little more)
		lifetimeSeconds: number, -- uncaught, it gets away after this long
		luck: number, -- × server luck for which Snackling escapes
		mutationChance: number, -- × mutation chances for it
	},
}

export type MapThemesConfig = {
	themes: { [string]: MapThemeDef },
	order: { string }, -- every theme id once: display order, and ties in picks resolve by it
	firstMap: string, -- "random" (weighted) or a theme id: the map a new server starts on
	rotation: MapRotation,
	transitionSeconds: number, -- lighting fades between maps over this long
}

-- Config: sounds (Config/Sounds) -----------------------------------------------------------------------------------

-- A sound effect: an asset ("rbxassetid://123", or a file that ships with Roblox: "rbxasset://sounds/x.wav"), its
-- volume (0..1, default 0.5) and playback speed (pitch, default 1). "" = silent.
export type SoundDef = { id: string, volume: number?, pitch: number? }
export type SoundSlot = string | SoundDef

-- A looping music track. id "" = no music for that slot.
export type MusicTrack = { id: string, volume: number? }

-- Config: friend & group rewards (Config/Social) ---------------------------------------------------------------

export type FriendsConfig = {
	incomeBonusPerFriend: number, -- e.g. 0.1 for +10% per friend
	maxFriends: number, -- friends counted at most
	checkAttempts: number,
	retrySeconds: number,
}

-- Same shape as Economy's CashPack: N seconds of steady income, never below the minimum.
export type GroupWelcomeReward = { incomeSeconds: number, minimum: number }

export type GroupConfig = {
	groupId: number, -- 0 = no group: the group feature is off
	incomeBonus: number,
	welcomeReward: GroupWelcomeReward?,
	recheckCooldownSeconds: number,
	checkAttempts: number,
	retrySeconds: number,
}

export type SocialConfig = { friends: FriendsConfig, group: GroupConfig }

-- Config: first-time player tutorial (Config/Tutorial) ----------------------------------------------------------

-- Each step is finished by doing its gameplay action, which the server observes (never a client message).
export type TutorialStepId = "buy" | "collect" | "lock" | "steal"

export type TutorialStepDef = {
	id: TutorialStepId,
	-- The step also finishes on its own after this many seconds on it (nil: only by doing it).
	timeoutSeconds: number?,
	-- The step also finishes on its own once its action has been unavailable this many seconds in a row (e.g. the
	-- base lock recharging). nil: never.
	unavailableSeconds: number?,
}

-- Which belt item the "buy" guide points at (Logic/TutorialRules.pickBeltItem).
export type TutorialBeltConfig = {
	minSecondsLeft: number, -- skip items about to fall off the belt end
	switchMargin: number, -- keep the current item unless another one is this many studs closer
}

export type TutorialConfig = {
	enabled: boolean, -- false: nobody sees the tutorial (and nothing is saved)
	reward: number, -- cash paid once per account when the tutorial is completed (not skipped)
	steps: { TutorialStepDef },
	belt: TutorialBeltConfig,
}

-- Config: Snackdex and daily quests (Config/Snackdex, Config/Quests) ---------------------------------------------

-- Cash sized like a cash pack: N seconds of the player's steady income (EconomyMath.packIncome: rebirths, passes and
-- the Snackdex bonus; no LiveOps cash event, no friend & group bonus), never below the minimum.
export type IncomeReward = { incomeSeconds: number, minimum: number }

export type SnackdexConfig = {
	-- Permanent income bonus per rarity tier completed (0.03 = +3%), and the cap on all of them together.
	incomeBonusPerTier: number,
	maxIncomeBonus: number,
	-- One-time cash for owning every regular (non-event) Snackling of a tier, by rarity id.
	tierRewards: { [string]: IncomeReward },
	defaultTierReward: IncomeReward, -- a rarity missing from tierRewards
}

-- What a daily quest counts (Logic/QuestRules): belt purchases, cash collected from pads, Snacklings sold, base locks,
-- delivered steals, new Snackdex entries (a new Snackling or a new mutation of one).
export type QuestKind = "beltPurchase" | "collect" | "sell" | "lock" | "steal" | "discover"
export type QuestDifficulty = "easy" | "hard"

export type QuestDef = {
	id: string, -- saved in the day's quest list: never reuse an id for a different quest
	kind: QuestKind,
	difficulty: QuestDifficulty,
	textKey: string, -- Theme.text key: {count} = the target, {amount} = a cash target, {rarity} = minRarity's name
	target: number?, -- how many (every kind but "collect")
	-- "collect": the target is this many seconds of steady income when the day's quests are rolled, at least `minimum`
	incomeSeconds: number?,
	minimum: number?,
	minRarity: string?, -- "beltPurchase": only Snacklings of this rarity id or rarer count
}

export type QuestsConfig = {
	slots: { QuestDifficulty }, -- one quest per entry every UTC day, in display order (e.g. easy, easy, hard)
	pool: { QuestDef },
	rewards: { [string]: IncomeReward }, -- by difficulty
	allDoneBonus: IncomeReward, -- paid once a day, with the claim that finishes the last quest
}

-- A gameplay event as daily quests see it (QuestService builds it from GameEvents).
export type QuestEvent = { kind: string, amount: number?, rarityOrder: number? }

-- Save data ---------------------------------------------------------------------------------------------------

export type CreatureRecord = {
	uid: string,
	id: string,
	podium: number,
	acquiredAt: number,
	stored: number, -- uncollected cash sitting on the podium
	-- Mutation id (Config/Mutations), nil for a plain creature. An id missing from the config is kept as-is and
	-- pays x1 until it exists again.
	variant: string?,
}

export type PurchaseRecord = {
	purchaseId: string,
	productId: number,
	key: string,
	robux: number,
	at: number,
}

-- A cash pack's amount, fixed when its receipt is first seen (ReceiptLedger.quote).
export type ReceiptQuote = { purchaseId: string, amount: number }

export type Stats = {
	steals: number,
	timesStolenFrom: number,
	beltPurchases: number,
	playTime: number,
	bestCashPerSecond: number,
	robuxSpent: number,
	totalEarned: number,
}

export type DailyState = { streak: number, lastClaimDay: number }

-- Base-lock timers carried between sessions, in wall-clock (os.time) seconds; 0 = not running.
export type LockTimers = { cooldownUntil: number, vulnerableUntil: number }

-- The collection book (v3): everything the player has ever owned. It never shrinks (a rebirth keeps it), and ids the
-- config no longer knows are kept, like quarantined creatures.
export type Snackdex = {
	creatures: { [string]: boolean }, -- creature id -> true once owned
	variants: { [string]: { [string]: boolean } }, -- creature id -> mutation ids it has been owned with
	tiers: { [string]: boolean }, -- rarity ids whose completion reward was paid (each gives the permanent bonus)
}

-- One of the day's quests (v3). `target` is fixed when the day's quests are rolled.
export type QuestSlot = { id: string, target: number, progress: number, claimed: boolean }

export type QuestState = {
	day: number, -- UTC day index (DailyStreak.dayIndex) the list belongs to; -1 before the first roll
	list: { QuestSlot },
	bonusClaimed: boolean, -- the all-done bonus for `day` was paid
}

-- Playtime gifts (v4): a ladder of gifts that unlock with time played each UTC day (Config/Gifts, Logic/GiftRules).
export type GiftState = {
	day: number, -- UTC day index (DailyStreak.dayIndex) the playtime belongs to; -1 before the first
	seconds: number, -- seconds played that day (counted while in game)
	claimed: { number }, -- ladder indices claimed that day
}

-- The Lucky Spin (v4): a free spin every so often, plus spins banked from gifts (Config/Spin, Logic/SpinRules).
export type SpinState = {
	nextFreeAt: number, -- Unix time the next free spin is ready (0 = ready now)
	spins: number, -- extra spins banked
	total: number, -- spins ever spun
}

export type PlayerData = {
	version: number,
	cash: number,
	creatures: { CreatureRecord },
	-- Creatures the save holds but no podium can show right now, kept off the podiums instead of being deleted: ones
	-- whose id is missing from the current config (removed or renamed by mistake), and ones whose podium was invalid
	-- or taken with no free podium in the base. They return automatically on a later load once the id exists again
	-- and a podium is free (DataSchema.sanitise). A rebirth spends them like any other Snackling.
	quarantine: { CreatureRecord },
	nextUid: number,
	podiumUpgrades: number,
	rebirths: number,
	rebirthMultiplier: number,
	lockTokens: number,
	lockTimers: LockTimers,
	processedReceipts: { string },
	cashPackQuotes: { ReceiptQuote },
	purchaseHistory: { PurchaseRecord },
	daily: DailyState,
	stats: Stats,
	flags: { [string]: boolean },
	firstJoin: number,
	lastSeen: number,
	snackdex: Snackdex, -- v3
	quests: QuestState, -- v3
	gifts: GiftState, -- v4
	spin: SpinState, -- v4
}

-- Runtime / network ---------------------------------------------------------------------------------------------

export type Passes = {
	DoubleCash: boolean,
	VIP: boolean,
	ExtraPodiums: boolean,
	LongerLock: boolean,
}

export type DailyView = {
	canClaim: boolean,
	streak: number,
	nextStreak: number,
	secondsUntilNext: number,
	reward: number,
}

-- The player's friend & group bonus (Logic/SocialRules), as the HUD shows it. Bonuses are fractions (0.2 = +20%).
export type SocialView = {
	friends: number, -- Roblox friends playing in this server (before the maxFriends cap)
	friendBonus: number,
	groupMember: boolean,
	groupBonus: number,
	bonus: number, -- friendBonus + groupBonus
	groupRewardClaimed: boolean, -- the one-time group welcome reward was already paid to this account
}

-- The player's tutorial progress (server-owned, Logic/TutorialRules).
export type TutorialView = {
	step: string, -- current step id (TutorialStepId), "" when no tutorial is running
	index: number, -- 1-based position of `step` in Config/Tutorial.steps, 0 when none
	count: number, -- number of steps
	stepStartedAt: number, -- server time the current step started
}

-- The player's settings (Logic/SettingsRules), saved as `settings_<key>` flags. All default to false.
export type SettingsView = {
	musicOff: boolean,
	sfxOff: boolean,
	reduceEffects: boolean, -- fewer particles / animated flair (low-end phones)
}

-- One of today's quests as the Rewards panel shows it. `reward` is what claiming pays right now.
export type QuestSlotView = { id: string, progress: number, target: number, claimed: boolean, reward: number }

-- Playtime gifts as the Rewards panel shows them. The client counts on from `seconds` while it stays in game.
export type GiftsView = {
	seconds: number, -- seconds played today when this state was sent
	syncedAt: number, -- Unix time it was sent (server clock)
	claimed: { number }, -- ladder indices claimed today
	claimable: number, -- unlocked and not claimed, when sent
	resetsAt: number, -- Unix time of the next UTC midnight (the ladder starts again)
	rewards: { number }, -- what each cash gift pays right now (0 for other kinds)
}

export type SpinView = {
	nextFreeAt: number, -- Unix time the next free spin is ready
	spins: number, -- banked spins
	ready: boolean, -- a spin can be used now (free or banked)
	rewards: { number }, -- what each cash segment pays right now (0 for other kinds)
}

export type QuestsView = {
	list: { QuestSlotView },
	bonus: number, -- the all-done bonus right now
	bonusClaimed: boolean,
	resetsAt: number, -- Unix time of the next UTC midnight (new quests)
	claimable: number, -- quests finished and not claimed yet
}

-- The Snackdex as its client sees it (SnackdexSync).
export type SnackdexView = {
	creatures: { string }, -- creature ids ever owned (sorted)
	variants: { [string]: { string } }, -- creature id -> mutation ids ever owned with it (sorted)
	tiers: { string }, -- rarity ids completed (reward paid)
	incomeBonus: number, -- the permanent collection bonus (0.06 = +6%)
}

-- A new Snackdex entry: a Snackling never owned before, or a mutation of it never owned before (`variant`).
export type SnackdexDiscovery = { creatureId: string, variant: string?, newCreature: boolean }

-- A rarity tier just completed: the cash it paid and the income bonus it added.
export type SnackdexTierPaid = { rarity: string, amount: number, bonus: number }

-- Server -> client SnackdexSync: the whole (small) Snackdex, plus what just happened.
export type SnackdexSync = {
	dex: SnackdexView,
	discovered: SnackdexDiscovery?,
	completed: { SnackdexTierPaid }?,
}

-- Config: the host panel, cross-server LiveOps and rare-pull shout-outs (Config/Host) ---------------------------------

-- An allowed range; `default` is used when a command leaves the value out.
export type HostRange = { min: number, max: number, default: number? }

export type HostConfig = {
	owner: { mapCooldownSeconds: number, modifierCooldownSeconds: number },
	admin: { giftCooldownSeconds: number },
	limits: {
		modifierMinutes: HostRange,
		luckMultiplier: HostRange,
		luckMinutes: HostRange,
		eventMinutes: HostRange,
		giftMinutes: HostRange,
		broadcastLength: number,
	},
	-- The values the panel's steppers offer (each inside its limit, ascending).
	presets: {
		modifierMinutes: { number },
		luckMultiplier: { number },
		luckMinutes: { number },
		eventMinutes: { number },
		giftMinutes: { number },
	},
	gift: { minimumPerMinute: number },
	messaging: HostMessaging,
	shoutouts: HostShoutouts,
}

-- Messages between servers (MessagingService): topics, the message version, expiry, dedupe and rate caps.
export type HostMessaging = {
	hostTopic: string, -- admin actions for "All servers"
	shoutTopic: string, -- rare-pull shout-outs
	version: number,
	maxAgeSeconds: number, -- older messages are ignored
	maxFutureSeconds: number, -- so are messages dated further ahead than this
	rememberIds: number, -- message ids kept for spotting duplicates
	maxBytes: number, -- the encoded message (Roblox allows 1 KB)
	sendBurst: number, -- admin actions this server may send at once...
	sendPerMinute: number, -- ...then this many a minute
	receiveBurst: number, -- messages per topic a server acts on at once...
	receivePerMinute: number, -- ...then this many a minute
}

-- Global rare-pull shout-outs: what counts, and how often a server sends and shows one.
export type HostShoutouts = {
	enabled: boolean,
	rarity: string, -- any Snackling of this rarity or rarer
	mutatedRarity: string, -- or one of `mutations` on this rarity or rarer
	mutations: { string },
	publishEverySeconds: number,
	showEverySeconds: number,
}

-- What a player may host here (StateUpdate `host`, written by HostService). Owners see their cooldowns.
export type HostView = {
	role: string, -- "admin" | "owner" | "" (nobody: the Settings row stays hidden)
	studio: boolean, -- a Studio session: "All servers" only ever reaches this session
	mapReadyAt: number, -- server time an owner may switch the map again (0 = now)
	modifierReadyAt: number, -- server time an owner may start a modifier again
	giftReadyAt: number, -- server time an admin may gift everyone again (a double tap never pays twice)
}

-- What the server sends the owning client in StateUpdate (see server/Services/Replication.luau).
-- Costs of -1 mean "not available" (max reached).
export type ClientState = {
	cash: number,
	income: number,
	multiplier: number,
	rebirths: number,
	rebirthMultiplier: number,
	rebirthCost: number,
	creatureCount: number,
	capacity: number,
	packIncome: number, -- steady income cash packs are sized from (EconomyMath.packIncome)
	podiumUpgrades: number,
	nextPodiumCost: number,
	lockTokens: number,
	lockedUntil: number,
	lockCooldownUntil: number,
	lockVulnerableUntil: number,
	lockDuration: number,
	graceUntil: number,
	plot: number,
	passes: Passes,
	carrying: string, -- creature id being carried, "" when not stealing
	stealCooldownUntil: number,
	steals: number,
	daily: DailyView,
	social: SocialView,
	tutorial: TutorialView,
	settings: SettingsView,
	quests: QuestsView,
	gifts: GiftsView,
	spin: SpinView,
}

export type BeltItem = { id: number, creatureId: string, spawnAt: number, variant: string? }

return {}
