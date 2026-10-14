--!strict
--[[
	Server modifiers: short random twists that change how a server plays for a few minutes. Plain data only.

	Every few minutes (schedule) a server picks one at random (by weight, never the same twice in a row), announces it
	with a banner, shows it as a chip in the HUD with a countdown, and switches it off after `durationSeconds`. Each
	effect is a multiplier on one thing (Types.ModifierEffects) and must stay inside `limits`, so no combination can
	break the game or the anti-cheat: the server widens its movement checks while a speed modifier runs (and for a
	moment after), and prices, hold times and tag reach are worked out the same way on the client
	(Logic/ModifierRules.effects).

	Commands: /mod <id> [minutes], /mod off, /mod list (anyone in Studio; admins in live servers, that server only).
	Balance notes: BALANCE.md "Server modifiers".
]]

local Types = require("../Types")

export type ModifiersConfig = Types.ModifiersConfig

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
		},
		quickHands = {
			displayName = "Quick Hands",
			icon = "🫳",
			description = "Steals take half the time. Guard your base!",
			color = "#FF8C1A",
			weight = 1,
			effects = { stealHold = 0.5 },
		},
		fortress = {
			displayName = "Fortress",
			icon = "🛡️",
			description = "Base locks last 50% longer!",
			color = "#4DA8FF",
			weight = 1,
			effects = { lockDuration = 1.5 },
		},
		snackPatrol = {
			displayName = "Snack Patrol",
			icon = "👮",
			description = "Tag thieves from 50% further away!",
			color = "#9B6BFF",
			weight = 1,
			effects = { tagRange = 1.5 },
		},
		snackParty = {
			displayName = "Snack Party",
			icon = "🎉",
			description = "A faster belt AND 2x luck!",
			color = "#FF5FD2",
			weight = 0.5, -- the rare double
			effects = { spawnInterval = 0.67, luck = 2 },
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
	},

	schedule = {
		enabled = true,
		durationSeconds = 5 * 60,
		gapMinSeconds = 4 * 60,
		gapMaxSeconds = 8 * 60,
		firstDelaySeconds = 2 * 60,
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
	},
}

return Modifiers
