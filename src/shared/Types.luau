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
	eventId: string?, -- only rolls while this LiveOps event is active
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
}

-- How many of each code-built prop the server places (0 / nil = none). Positions come from the map layout.
export type SeasonDecorations = {
	pumpkinsPerPlot: number?, -- glowing jack-o'-lanterns beside each plot entrance
	beltPumpkinsPerSide: number?, -- smaller ones along both belt rails
	bulbsPerPlot: number?, -- string-light bulbs along each plot's front wall
	lampsBetweenPlots: boolean?, -- lamp posts in the gaps between plots
	bats: number?, -- floating above the walkway
	ghosts: number?, -- near the leaderboards at the belt ends
}

export type SeasonPalette = {
	pumpkin: string,
	pumpkinFace: string, -- glowing eyes / mouth (and their light)
	stem: string,
	bulbs: { string }, -- string lights cycle through these
	lampPost: string,
	lampLight: string,
	bat: string,
	ghost: string,
}

export type SeasonTheme = {
	displayName: string,
	accentColor: string, -- HUD event pill and the "EVENT" tag on this event's Snacklings
	priority: number, -- when several themed events overlap, the highest priority wins
	lighting: SeasonLighting?,
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

export type SceneryConfig = {
	lighting: SceneryLighting,
	boundary: SceneryBoundary,
	terrain: SceneryTerrain,
	plaza: SceneryPlaza,
	trees: { TreeDef }, -- inside the boundary (around the bases)
	treeLine: { count: number, minDistance: number, maxDistance: number, seed: number }, -- outside the wall
	chevronSpacing: number, -- belt markings
	partBudget: number, -- every part MapBuilder + SceneryBuilder add on top of the gameplay geometry
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
}

export type BeltItem = { id: number, creatureId: string, spawnAt: number, variant: string? }

return {}
