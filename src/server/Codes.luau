--!strict
--[[
	Redeem codes. Server-only (this module never replicates), so players only know the codes you post.

	Add a code: a new entry keyed by its text in UPPER CASE letters and digits (players can type any case). Each works
	once per account (CodeRules, flag `code_<CODE>`). Rewards:
	  { kind = "cash", incomeSeconds = N, minimum = M }   N seconds of the player's steady income, at least M
	  { kind = "creature", creatureId = "...", variant = "golden" }   a Snackling (variant optional) on a free podium;
	                                                      with a full base the code is not used up and says so
	startsAt / expiresAt (optional): unix seconds (UTC) when the code starts and stops working, e.g.
	https://www.epochconverter.com. Before startsAt it answers like an unknown code. An event code starts with its
	LiveOps event (Config/LiveOps), so its Snackling can't be had early.
	CI checks every entry (tests/CodeRules.spec.luau), including that an event Snackling's code starts no earlier than
	its event. Changing this file needs a publish.

	Not secret: this file never reaches a game client, but the GitHub repo is public, so anyone can read it there (see
	README "Redeem codes").

	Plain data with no requires, so the unit tests can load it too (its shape is Types.CodesConfig).
]]

local Codes = {
	-- Launch codes
	WELCOME = { reward = { kind = "cash", incomeSeconds = 120, minimum = 500 } },
	SNACKTIME = { reward = { kind = "creature", creatureId = "pizza_pup", variant = "golden" } },
	FOURTEENMAPS = { reward = { kind = "cash", incomeSeconds = 180, minimum = 1000 } },
	STORMCHASER = { reward = { kind = "creature", creatureId = "pretzel_pal", variant = "electric" } },
	-- Twenty maps: a Gummy Grub with Bubblegum Bayou's signature mutation.
	TWENTYMAPS = { reward = { kind = "creature", creatureId = "gummy_grub", variant = "bubblegum" } },
	-- Twenty-three maps: a Popcorn Penguin with Popcorn Drive-In's signature mutation.
	MOVIENIGHT = { reward = { kind = "creature", creatureId = "popcorn_penguin", variant = "buttered" } },
	-- Halloween 2026: a Haunted Candy Corn Cat while the event runs.
	SPOOKY26 = {
		reward = { kind = "creature", creatureId = "candy_corn_cat", variant = "haunted" },
		startsAt = 1792774800, -- 2026-10-23 17:00 UTC (Halloween2026 starts)
		expiresAt = 1793606400, -- 2026-11-02 08:00 UTC
	},
	-- Harvest Feast 2026: a Maple Cranberry Crane while the event runs.
	FEAST26 = {
		reward = { kind = "creature", creatureId = "cranberry_crane", variant = "maple" },
		startsAt = 1795194000, -- 2026-11-20 17:00 UTC (Harvest2026 starts)
		expiresAt = 1796025600, -- 2026-11-30 08:00 UTC
	},
	-- Winter 2026: a Festive Peppermint Puffin while the event runs, and a New Year cash gift for New Year's week.
	JINGLE26 = {
		reward = { kind = "creature", creatureId = "peppermint_puffin", variant = "festive" },
		startsAt = 1797613200, -- 2026-12-18 17:00 UTC (Winter2026 starts)
		expiresAt = 1799049600, -- 2027-01-04 08:00 UTC
	},
	HAPPY2027 = {
		reward = { kind = "cash", incomeSeconds = 300, minimum = 5000 },
		startsAt = 1798736400, -- 2026-12-31 17:00 UTC (NewYearCash2026 starts)
		expiresAt = 1799366400, -- 2027-01-08 00:00 UTC
	},
	-- Valentine's 2027: a Sweetheart Candy Heart Hamster while the event runs.
	LOVE27 = {
		reward = { kind = "creature", creatureId = "candy_heart_hamster", variant = "sweetheart" },
		startsAt = 1801846800, -- 2027-02-05 17:00 UTC (Valentine2027 starts)
		expiresAt = 1802764800, -- 2027-02-16 08:00 UTC
	},
	-- Easter 2027: a Pastel Custard Chick while the event runs.
	EGGHUNT27 = {
		reward = { kind = "creature", creatureId = "custard_chick", variant = "pastel" },
		startsAt = 1805475600, -- 2027-03-19 17:00 UTC (Easter2027 starts)
		expiresAt = 1806994800, -- 2027-04-06 07:00 UTC
	},
}

return Codes
