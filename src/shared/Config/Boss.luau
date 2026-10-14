--!strict
--[[
	Snack Attack: the giant Snackling a "boss" server modifier (Config/Modifiers `drops.kind = "boss"`) sends over the
	middle of the belt. Plain data only.

	It hovers above the belt where both walkways can reach it, slowly turning, with a health bar. Everyone taps it
	(a ClickDetector: mouse or touch); the server counts each player's hits, at most `hitsPerSecond` (with a small
	`burst`), only from players standing within `reach` at a position it trusts (PositionTracker), like a steal. Its
	health is `hpPerPlayer` for each player in the server when it appears (at least `minHp`), so it is a team effort
	whatever the server size. Taken down within `lifetimeSeconds`, it pays everyone who landed `minHits` or more: cash
	sized from their own steady income, more for a bigger share of the hits; the top hitter also wins a Snackling rolled
	with extra luck (its sell value when their base is full). Announced to everyone. Not taken down in time, it flies
	off and nothing is paid.

	Logic/BossRules works out the health and the rewards and validates this config (CI).
]]

local Types = require("../Types")

local Boss: Types.BossConfig = {
	hpPerPlayer = 90,
	minHp = 120,
	hitsPerSecond = 5,
	burst = 8,
	reach = 45,
	lifetimeSeconds = 75,
	scale = 3.2,
	hoverHeight = 9,
	rarities = { "Legendary", "Mythic" },
	minHits = 5,
	cash = { baseSeconds = 20, shareSeconds = 120, minimum = 300 },
	luck = 3,
	mutationChance = 2,
}

return Boss
