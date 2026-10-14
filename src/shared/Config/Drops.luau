--!strict
--[[
	Drops: what the Supply Drop and Coin Rain server modifiers (Config/Modifiers `drops`) put on the walkways between
	the belt and the bases, where everyone walks. Plain data only.

	  crate  falls from the sky on a parachute and lands somewhere on a walkway; the first player to hold its prompt
	         for `holdSeconds` opens it: a Snackling rolled with extra luck (and a better shot at a mutation) goes to
	         their base, or its sell value when the base is full, plus some cash. Announced to everyone.
	  coins  a scatter of coins floating over both walkways; walking through one collects a few seconds of your own
	         income (at least `minimum`). Gone after `lifetimeSeconds`.

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
}

return Drops
