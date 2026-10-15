--!strict
--[[
	Drops: what the Supply Drop, Coin Rain, Great Escape and Treasure Hunt server modifiers (Config/Modifiers `drops`)
	put on the walkways between the belt and the bases, where everyone walks, and around the spawn plaza. Plain data
	only.

	  crate  falls from the sky on a parachute and lands somewhere on a walkway; the first player to hold its prompt
	         for `holdSeconds` opens it: a Snackling rolled with extra luck (and a better shot at a mutation) goes to
	         their base, or its sell value when the base is full, plus some cash. Announced to everyone.
	  coins  a scatter of coins floating over both walkways; walking through one collects a few seconds of your own
	         income (at least `minimum`). Gone after `lifetimeSeconds`.
	  runaway  a Snackling (rolled with extra luck and mutation chance) escapes and runs along a walkway, away from
	         whoever comes near; the first player to reach it catches it, and it goes to their base (its sell value
	         when the base is full). It appears far from everyone and gets away after `lifetimeSeconds`. Announced.
	treasure a golden fork stuck in the ground at one of the hiding places in `spots`, one at a time: tucked beside the
	         Snack Factory and the chute, deep in the gaps between bases, and around the spawn plaza (behind a bench, by
	         the fountain, behind a leaderboard...). The announcement says roughly where (each spot's `where`); the
	         first player to walk into it finds it and wins one of `prizes` (a few seconds of income, or a Lucky
	         Spin). Unfound for `revealSeconds`, a marker shows it; it goes after `lifetimeSeconds`. It never hides
	         within `minPlayerDistance` of anyone (while some spot is that far), nor twice running in the same place.

	Rewards scale with the player's steady income like cash packs (EconomyMath.cashPackAmount), so they matter at
	every stage of the game. The server checks every pickup against the player's trusted position (PositionTracker)
	and re-checks a crate's hold time like a steal's. Logic/DropRules validates this config (CI), and
	tests/DropRules.spec checks every hiding place against the real map: on open ground, clear of the belt, the bases,
	the plaza's furniture, every map's trees and every seasonal decoration.
]]

local Types = require("../Types")

local Drops: Types.DropsConfig = {
	area = { minX = -130, maxX = 130, minZ = 9, maxZ = 25 },

	crate = {
		fallSeconds = 5,
		dropHeight = 110,
		holdSeconds = 2.5,
		holdTolerance = 0.8,
		openRange = 10,
		lifetimeSeconds = 90,
		luck = 3,
		mutationChance = 2,
		cash = { incomeSeconds = 45, minimum = 300 },
	},

	coins = {
		perWave = 12,
		height = 2.2,
		lifetimeSeconds = 22,
		pickupRange = 3.5,
		value = { incomeSeconds = 3, minimum = 30 },
	},

	runaway = {
		speed = 9,
		sprintSpeed = 14.5, -- players walk at 16
		pauseSeconds = 0.4,
		sprintPauseSeconds = 0.1,
		legMin = 10,
		legMax = 26,
		candidates = 12,
		fleeRadius = 40,
		edgeMargin = 30,
		beltHopPenalty = 12,
		catchRange = 4,
		lifetimeSeconds = 45,
		luck = 2,
		mutationChance = 2,
	},

	treasure = {
		lifetimeSeconds = 36, -- under Treasure Hunt's 42 s between forks: one at a time
		revealSeconds = 18,
		pickupRange = 4,
		minPlayerDistance = 30,
		prizes = {
			{ weight = 3, reward = { kind = "cash", incomeSeconds = 40, minimum = 400 } },
			{ weight = 1, reward = { kind = "spin", count = 1 } },
		},
		-- Hiding places (world X / Z). The plaza is centred on (215, 0): benches 17 out, lamps 24, flower beds 21,
		-- trees 33, the What's New board at 126 degrees; the leaderboards stand at (175, +-36) facing the map, the
		-- archway's pillars at (180, +-13). Gaps between bases are centred on x = -76, 0, 76 for |z| 30..124.
		spots = {
			{ x = 215, z = 20.6, where = "treasureWhereBench" },
			{ x = 200.4, z = -14.6, where = "treasureWhereBench" },
			{ x = 223.5, z = 4.9, where = "treasureWhereFountain" },
			{ x = 206.5, z = -4.9, where = "treasureWhereFountain" },
			{ x = 236.1, z = 4.2, where = "treasureWhereFlowers" },
			{ x = 193.6, z = 29.5, where = "treasureWhereNews" },
			{ x = 234.4, z = -26.7, where = "treasureWherePlazaTrees" },
			{ x = 177, z = 15, where = "treasureWhereArch" },
			{ x = 177, z = -15, where = "treasureWhereArch" },
			{ x = 178.9, z = 36.8, where = "treasureWhereBoards" },
			{ x = 178.9, z = -36.8, where = "treasureWhereBoards" },
			{ x = -166, z = 21, where = "treasureWhereFactory" },
			{ x = -166, z = -21, where = "treasureWhereFactory" },
			{ x = -150, z = 27, where = "treasureWhereWalkwayEnd" },
			{ x = -150, z = -27, where = "treasureWhereWalkwayEnd" },
			{ x = 162, z = 27, where = "treasureWhereWalkwayEnd" },
			{ x = 162, z = -27, where = "treasureWhereWalkwayEnd" },
			{ x = -76, z = 64, where = "treasureWhereAlley" },
			{ x = 0, z = 64, where = "treasureWhereAlley" },
			{ x = 76, z = 64, where = "treasureWhereAlley" },
			{ x = -76, z = -64, where = "treasureWhereAlley" },
			{ x = 0, z = -64, where = "treasureWhereAlley" },
			{ x = 76, z = -64, where = "treasureWhereAlley" },
		},
	},
}

return Drops
