--!strict
--[[
	Bounty Hunt (the Config/Modifiers `bounty` modifier): for as long as it runs, the server's top earner wears a bounty
	(a 🎯 BOUNTY marker over their head and a gold outline). Tagging them while they carry a Snackling, or getting a
	Snackling stolen from their base home, claims it: cash sized from the claimer's own steady income, like a cash pack
	(EconomyMath.cashPackAmount), so it means the same to a newcomer and to a big base. Plain data only; the rules are
	Logic/BountyRules (CI validates this config there), the server is BountyService.

	Fair play: the target and their Roblox friends never claim it; each hunter claims it at most `claimsPerHunter`
	times in one hunt; after every claim it rests for `restSeconds`, so nobody farms the target or camps their base.
	BALANCE.md "Server modifiers" has what it pays against the other modifiers.
]]

local Types = require("../Types")

local Bounty: Types.BountyConfig = {
	tag = { incomeSeconds = 60, minimum = 500 },
	steal = { incomeSeconds = 90, minimum = 750 },
	claimsPerHunter = 1,
	restSeconds = 30,
	checkSeconds = 2,
}

return Bounty
