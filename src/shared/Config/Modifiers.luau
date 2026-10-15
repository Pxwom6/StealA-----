--!strict
--[[
	Server modifiers: short random twists that change how a server plays for a few minutes. Plain data only.

	Every few minutes (schedule) a server picks one at random (by weight, never the same twice in a row), announces it
	with a banner, shows it as a chip in the HUD with a countdown, and switches it off after `durationSeconds`. Each
	effect is a multiplier on one thing (Types.ModifierEffects) and must stay inside `limits`, so no combination can
	break the game or the anti-cheat: the server widens its movement checks while a speed modifier runs (and for a
	moment after), and prices, hold times and tag reach are worked out the same way on the client
	(Logic/ModifierRules.effects).

	Weather modifiers (Thunderstorm, Meteor Shower, Toxic Fog, Northern Lights, Heatwave, Eclipse) change nothing but
	the sky, and unlock a mutation that only rolls while they run (Config/Mutations `modifierId`): Electric, Galaxy,
	Toxic, Aurora, Toasted and Eclipse Snacklings. Their `weather` replaces the map's particles, `lighting` goes over
	the map's (and a seasonal theme's) like a seasonal overlay, and `skyEffect` adds lightning flashes (off with Reduce
	effects), shooting stars, the shimmering curtains of an aurora, or the eclipsed sun: a black disc in a ring of fire
	where the sun was (the overlay's `hideSun` takes the sky's own sun away).

	Drop modifiers (Supply Drop, Coin Rain, Great Escape, Treasure Hunt) put crates, coins, runaway Snacklings or golden
	forks on the walkways while they run (`drops`; what they hold is in Config/Drops). Snack Attack sends giant
	Snacklings over the belt for everyone to tap together (`drops.kind = "boss"`, Config/Boss).

	Gadget Frenzy halves every gadget's recharge (`gadgetCooldown`), never below the fairness floors in
	Logic/GadgetRules (a speed gadget runs at most a third of the time, a shield a fifth). Bounty Hunt (`bounty`) puts
	a bounty on the server's top earner for as long as it runs: tag them while they carry a Snackling, or get one
	stolen from their base home, for a payout sized from your own income (Config/Bounty, BountyService).

	Commands: /mod <id> [minutes], /mod off, /mod list (anyone in Studio; admins in live servers, that server only).
	Admins can also start and stop any modifier from the host panel (Config/Host), in this server or all of them.

	`hostable = true`: a private server's owner may start (and stop) it from the host panel, every 10 minutes at most.
	Only the five that change how a chase plays and leave the economy alone: Sugar Rush, Quick Hands, Fortress, Snack
	Patrol and Gadget Frenzy. Nothing that raises luck, mutation chances or income, cuts prices, speeds up the belt
	(more rare spawns an hour), drops anything, pays bounties, or is a weather (they unlock a mutation); CI checks
	(HostRules.hostableProblems). Balance notes: BALANCE.md "Server modifiers".
]]

local Types = require("../Types")

export type ModifiersConfig = Types.ModifiersConfig

-- A dark, rainy afternoon.
local STORM: Types.SeasonLighting = {
	clockTime = 15,
	brightness = 1.2,
	ambient = "#56607A",
	outdoorAmbient = "#7A849A",
	colorShiftTop = "#A8B4CC",
	atmosphere = { density = 0.42, offset = 0.1, color = "#8A94A8", decay = "#3E4658", glare = 0, haze = 2.2 },
	colorCorrection = { tint = "#DCE4F4", brightness = -0.02, contrast = 0.12, saturation = -0.3 },
	clouds = { cover = 0.92, density = 0.85, color = "#5E6678" },
}

-- A clear, starry midnight (brighter than a plain night: every map has to stay playable).
local STARRY: Types.SeasonLighting = {
	clockTime = 0.4,
	brightness = 2,
	ambient = "#6C6CA4",
	outdoorAmbient = "#9494D0",
	colorShiftTop = "#A8B0FF",
	atmosphere = { density = 0.22, offset = 0.1, color = "#3A3A72", decay = "#1A1A44", glare = 0, haze = 0.6 },
	colorCorrection = { tint = "#ECEAFF", brightness = 0.06, contrast = 0.1, saturation = 0.1 },
	clouds = { cover = 0.15, density = 0.4, color = "#6A6A9A" },
}

-- A thick green haze.
local TOXIC: Types.SeasonLighting = {
	clockTime = 16.5,
	brightness = 1.5,
	ambient = "#4E6A44",
	outdoorAmbient = "#7E9A6A",
	colorShiftTop = "#C8FF9A",
	atmosphere = { density = 0.48, offset = 0.05, color = "#9AD878", decay = "#3E6A2E", glare = 0.2, haze = 2.6 },
	colorCorrection = { tint = "#E4FFD8", brightness = 0, contrast = 0.08, saturation = -0.05 },
	clouds = { cover = 0.7, density = 0.7, color = "#8AA86A" },
}

-- A clear polar night lit by an aurora (bright enough to play on every map).
local POLAR: Types.SeasonLighting = {
	clockTime = 23.4,
	brightness = 1.9,
	ambient = "#4E6A7E",
	outdoorAmbient = "#7EA4B8",
	colorShiftTop = "#9AFFD8",
	atmosphere = { density = 0.18, offset = 0.1, color = "#2A4A5E", decay = "#10202E", glare = 0, haze = 0.6 },
	colorCorrection = { tint = "#E8FFF6", brightness = 0.07, contrast = 0.1, saturation = 0.15 },
	clouds = { cover = 0.08, density = 0.3, color = "#4A6A7A" },
}

-- A blazing, hazy noon.
local HEAT: Types.SeasonLighting = {
	clockTime = 13.2,
	brightness = 3.4,
	ambient = "#9A7A5A",
	outdoorAmbient = "#D8B48A",
	colorShiftTop = "#FFC890",
	atmosphere = { density = 0.38, offset = 0.15, color = "#FFD8A0", decay = "#E89A5A", glare = 0.6, haze = 2.4 },
	colorCorrection = { tint = "#FFF0DC", brightness = 0.04, contrast = 0.06, saturation = 0.08 },
	clouds = { cover = 0.05, density = 0.2, color = "#FFFFFF" },
}

-- A total eclipse in the late afternoon: the sun goes (each client draws the eclipsed sun in its place), the day
-- turns to a violet dusk and the horizon glows all round like a sunset (bright enough to play on every map).
local ECLIPSE: Types.SeasonLighting = {
	clockTime = 16.6, -- the sun low enough in the west to sit in view, high enough to clear the bases
	brightness = 0.95,
	ambient = "#544A78",
	outdoorAmbient = "#6E6496",
	colorShiftTop = "#FFA982", -- the corona's warm light along the tops of things
	atmosphere = { density = 0.33, offset = 0.25, color = "#E08A9A", decay = "#2A2050", glare = 0, haze = 1.6 },
	colorCorrection = { tint = "#E2D6FF", brightness = -0.05, contrast = 0.15, saturation = -0.12 },
	clouds = { cover = 0.18, density = 0.3, color = "#4A3E6E" },
	hideSun = true,
}

local Modifiers: ModifiersConfig = {
	modifiers = {
		rushHour = {
			displayName = "Rush Hour",
			icon = "⚡",
			description = "Snacklings pour off the belt twice as fast!",
			color = "#FFD23F",
			weight = 1,
			effects = { spawnInterval = 0.5 },
		},
		clearanceSale = {
			displayName = "Clearance Sale",
			icon = "🏷️",
			description = "Everything on the belt is 30% off!",
			color = "#3DDC84",
			weight = 1,
			effects = { beltPrice = 0.7 },
		},
		goldenHour = {
			displayName = "Golden Hour",
			icon = "✨",
			description = "Mutations are 3x more likely!",
			color = "#FFC83D",
			weight = 1,
			effects = { mutationChance = 3 },
		},
		luckyBreeze = {
			displayName = "Lucky Breeze",
			icon = "🍀",
			description = "2x luck: rarer Snacklings on the belt!",
			color = "#7CFF4D",
			weight = 1,
			effects = { luck = 2 },
		},
		cashSplash = {
			displayName = "Cash Splash",
			icon = "💰",
			description = "Everyone earns 50% more!",
			color = "#8CFF6B",
			weight = 1,
			effects = { income = 1.5 },
		},
		sugarRush = {
			displayName = "Sugar Rush",
			icon = "🍬",
			description = "Everyone runs 25% faster!",
			color = "#FF6FB5",
			weight = 1,
			effects = { walkSpeed = 1.25 },
			hostable = true, -- private-server owners may start it (Config/Host)
		},
		quickHands = {
			displayName = "Quick Hands",
			icon = "🫳",
			description = "Steals take half the time. Guard your base!",
			color = "#FF8C1A",
			weight = 1,
			effects = { stealHold = 0.5 },
			hostable = true, -- private-server owners may start it (Config/Host)
		},
		fortress = {
			displayName = "Fortress",
			icon = "🛡️",
			description = "Base locks last 50% longer!",
			color = "#4DA8FF",
			weight = 1,
			effects = { lockDuration = 1.5 },
			hostable = true, -- private-server owners may start it (Config/Host)
		},
		snackPatrol = {
			displayName = "Snack Patrol",
			icon = "👮",
			description = "Tag thieves from 50% further away!",
			color = "#9B6BFF",
			weight = 1,
			effects = { tagRange = 1.5 },
			hostable = true, -- private-server owners may start it (Config/Host)
		},
		snackParty = {
			displayName = "Snack Party",
			icon = "🎉",
			description = "A faster belt AND 2x luck!",
			color = "#FF5FD2",
			weight = 0.5, -- the rare double
			effects = { spawnInterval = 0.67, luck = 2 },
		},
		jackpot = {
			displayName = "Jackpot",
			icon = "🎰",
			description = "Everyone earns DOUBLE cash!",
			color = "#FFD700",
			weight = 0.35, -- rarer than Cash Splash, twice the boost
			effects = { income = 2 },
		},

		-- Weather: each unlocks a mutation (Config/Mutations modifierId) and changes the sky.
		thunderstorm = {
			displayName = "Thunderstorm",
			icon = "⛈️",
			description = "Electric Snacklings can appear on the belt!",
			color = "#5CD2FF",
			weight = 1,
			effects = {},
			weather = "rain",
			lighting = STORM,
			skyEffect = "lightning",
		},
		meteorShower = {
			displayName = "Meteor Shower",
			icon = "☄️",
			description = "Galaxy Snacklings can appear on the belt!",
			color = "#9C7BFF",
			weight = 1,
			effects = {},
			lighting = STARRY,
			skyEffect = "meteors",
		},
		toxicFog = {
			displayName = "Toxic Fog",
			icon = "☢️",
			description = "Toxic Snacklings can appear on the belt!",
			color = "#7CFF4D",
			weight = 1,
			effects = {},
			weather = "spores",
			lighting = TOXIC,
		},
		northernLights = {
			displayName = "Northern Lights",
			icon = "🌌",
			description = "Aurora Snacklings can appear on the belt!",
			color = "#3CF0B4",
			weight = 1,
			effects = {},
			lighting = POLAR,
			skyEffect = "aurora",
		},
		heatwave = {
			displayName = "Heatwave",
			icon = "🥵",
			description = "Toasted Snacklings can appear on the belt!",
			color = "#FF8A3D",
			weight = 1,
			effects = {},
			weather = "heat",
			lighting = HEAT,
		},
		eclipse = {
			displayName = "Eclipse",
			icon = "🌑",
			description = "Eclipse Snacklings can appear on the belt!",
			color = "#B44DFF",
			weight = 1,
			effects = {},
			lighting = ECLIPSE,
			skyEffect = "eclipse",
		},

		-- Gear: every gadget recharges in half the time, never below its fairness floor (Logic/GadgetRules).
		gadgetFrenzy = {
			displayName = "Gadget Frenzy",
			icon = "🔋",
			description = "Gadgets recharge twice as fast!",
			color = "#5C7CFF",
			weight = 1,
			effects = { gadgetCooldown = 0.5 },
			hostable = true, -- private-server owners may start it (Config/Host)
		},

		-- A bounty on the server's top earner (Config/Bounty).
		bountyHunt = {
			displayName = "Bounty Hunt",
			icon = "🎯",
			description = "Tag the top earner or rob their base for a bounty!",
			color = "#FF3D6E",
			weight = 1,
			effects = {},
			bounty = true,
		},

		-- Drops on the walkways (Config/Drops).
		supplyDrop = {
			displayName = "Supply Drop",
			icon = "📦",
			description = "Crates are falling! Open one for a free Snackling!",
			color = "#C9894A",
			weight = 1,
			effects = {},
			drops = { kind = "crate", firstSeconds = 10, everySeconds = 75 }, -- 4 crates
		},
		coinRain = {
			displayName = "Coin Rain",
			icon = "🪙",
			description = "Coins are raining on the walkways. Grab them!",
			color = "#FFD23F",
			weight = 1,
			effects = {},
			drops = { kind = "coins", firstSeconds = 3, everySeconds = 40 }, -- 8 showers
		},
		greatEscape = {
			displayName = "Great Escape",
			icon = "🏃",
			description = "Snacklings escaped! Catch them on the walkways!",
			color = "#FF8C1A",
			weight = 1,
			effects = {},
			drops = { kind = "runaway", firstSeconds = 6, everySeconds = 50 }, -- 6 runaways
		},
		snackAttack = {
			displayName = "Snack Attack",
			icon = "👾",
			description = "Giant Snacklings raid the belt! Tap them together!",
			color = "#FF5C5C",
			weight = 1,
			effects = {},
			drops = { kind = "boss", firstSeconds = 8, everySeconds = 100 }, -- 3 giants (Config/Boss)
		},
		treasureHunt = {
			displayName = "Treasure Hunt",
			icon = "🍴",
			description = "Golden Forks are hidden around the map. Find them!",
			color = "#FFB627",
			weight = 1,
			effects = {},
			drops = { kind = "treasure", firstSeconds = 6, everySeconds = 42 }, -- 7 forks, one at a time
		},
	},

	order = {
		"rushHour",
		"clearanceSale",
		"goldenHour",
		"luckyBreeze",
		"cashSplash",
		"sugarRush",
		"quickHands",
		"fortress",
		"snackPatrol",
		"snackParty",
		"jackpot",
		"thunderstorm",
		"meteorShower",
		"toxicFog",
		"northernLights",
		"heatwave",
		"supplyDrop",
		"coinRain",
		"greatEscape",
		"snackAttack",
		"eclipse",
		"gadgetFrenzy",
		"treasureHunt",
		"bountyHunt",
	},

	schedule = {
		enabled = true,
		durationSeconds = 5 * 60,
		gapMinSeconds = 4 * 60,
		gapMaxSeconds = 8 * 60,
		firstDelaySeconds = 2 * 60,
		-- For this long after a modifier starts or ends, a belt purchase, a steal hold and a tag are checked against the
		-- kinder of the old and new price, hold time and reach (clients show the old ones for a moment).
		changeGraceSeconds = 1.5,
	},

	limits = {
		spawnInterval = { min = 0.4, max = 1.5 },
		beltPrice = { min = 0.5, max = 1.5 },
		mutationChance = { min = 1, max = 4 },
		luck = { min = 1, max = 3 },
		income = { min = 1, max = 2 },
		walkSpeed = { min = 0.8, max = 1.35 },
		stealHold = { min = 0.5, max = 2 },
		lockDuration = { min = 0.5, max = 2 },
		tagRange = { min = 0.75, max = 1.6 },
		gadgetCooldown = { min = 0.5, max = 2 },
	},
}

return Modifiers
