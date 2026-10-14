--!strict
--[[
	Redeem codes. Server-only (this module never replicates), so players only know the codes you post.

	Add a code: a new entry keyed by its text in UPPER CASE letters and digits (players can type any case). Each works
	once per account (CodeRules, flag `code_<CODE>`). Rewards:
	  { kind = "cash", incomeSeconds = N, minimum = M }   N seconds of the player's steady income, at least M
	  { kind = "creature", creatureId = "...", variant = "golden" }   a Snackling (variant optional) on a free podium;
	                                                      with a full base the code is not used up and says so
	expiresAt (optional): unix seconds (UTC) after which the code stops working, e.g. https://www.epochconverter.com.
	CI checks every entry (tests/CodeRules.spec.luau). Changing this file needs a publish.

	Plain data with no requires, so the unit tests can load it too (its shape is Types.CodesConfig).
]]

local Codes = {
	-- Launch codes
	WELCOME = { reward = { kind = "cash", incomeSeconds = 120, minimum = 500 } },
	SNACKTIME = { reward = { kind = "creature", creatureId = "pizza_pup", variant = "golden" } },
	FOURTEENMAPS = { reward = { kind = "cash", incomeSeconds = 180, minimum = 1000 } },
	STORMCHASER = { reward = { kind = "creature", creatureId = "pretzel_pal", variant = "electric" } },
	-- Halloween 2026: a Haunted Candy Corn Cat until the event ends.
	SPOOKY26 = {
		reward = { kind = "creature", creatureId = "candy_corn_cat", variant = "haunted" },
		expiresAt = 1793606400, -- 2026-11-02 08:00 UTC
	},
}

return Codes
