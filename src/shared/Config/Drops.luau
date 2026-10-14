--!strict
--[[
	Drops: what the Supply Drop, Coin Rain and Great Escape server modifiers (Config/Modifiers `drops`) put on the
	walkways between the belt and the bases, where everyone walks. Plain data only.

	  crate  falls from the sky on a parachute and lands somewhere on a walkway; the first player to hold its prompt
	         for `holdSeconds` opens it: a Snackling rolled with extra luck (and a better shot at a mutation) goes to
	         their base, or its sell value when the base is full, plus some cash. Announced to everyone.
	  coins  a scatter of coins floating over both walkways; walking through one collects a few seconds of your own
	         income (at least `minimum`). Gone after `lifetimeSeconds`.
	  runaway  a Snackling (rolled with extra luck and mutation chance) escapes and runs along a walkway, away from
	         whoever comes near; the first player to reach it catches it, and it goes to their base (its sell value
	         when the base is full). It appears far from everyone and gets away after `lifetimeSeconds`. Announced.

	Rewards scale with the player's steady income like cash packs (EconomyMath.cashPackAmount), so they matter at
	every stage of the game. The server checks every pickup against the player's trusted position (PositionTracker)
	and re-checks a crate's hold time like a steal's. Logic/DropRules validates this config (CI).
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
}

return Drops
