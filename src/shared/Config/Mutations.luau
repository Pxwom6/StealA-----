--!strict
--[[
	Mutations: rare variants of ANY Snackling that appear on the conveyor and earn more. Plain data only.

	Every belt spawn first rolls its creature (rarity weights × luck), then rolls at most one mutation here, with
	each mutation's own `chance`. Luck boosts never change these chances (DECISIONS.md #18), so the Server Luck odds
	disclosure stays exact. A creature keeps its mutation for life: it is saved in `CreatureRecord.variant` and
	travels with it when stolen.

	id                saved in players' data: NEVER rename or remove one that has shipped (append new ids to
	                  RELEASED_MUTATION_IDS in tests/Config.spec.luau). A save holding an unknown id keeps it and
	                  earns x1 until the id exists again. To stop one appearing, give it a never-active `eventId`.
	displayName       "Golden" -> "Golden Pizza Pup" (Theme.text.mutatedName)
	color             label / banner colour
	order             display order (rarest last); also the order mutations are rolled in
	chance            probability per belt spawn, 0 < chance < 1; all chances together must stay below 1
	incomeMultiplier  × the creature's base income (>= 1)
	priceMultiplier   × the creature's belt price, rounded to a whole number (>= 1); sell value follows it
	announce*         server-wide banner on spawn / buy / steal (in addition to the rarity's own flags)
	look              material (Enum.Material name), optional tint (+ tintStrength 0..1), transparency,
	                  reflectance, sparkles, rainbow (hue-cycling colours + rainbow particles)
	eventId           optional: only rolls while that LiveOps event is active (event-only mutations)

	Balance notes live in BALANCE.md ("Mutations"); `lune run tools/simulate.luau` re-runs the numbers.
]]

local Types = require("../Types")

export type MutationDef = Types.MutationDef

local Mutations: { MutationDef } = {
	{
		id = "golden",
		displayName = "Golden",
		color = "#FFC83D",
		order = 1,
		chance = 0.03,
		incomeMultiplier = 2,
		priceMultiplier = 1.5,
		announceOnSpawn = false,
		announceOnBuy = false,
		announceOnSteal = false,
		look = { material = "Foil", tint = "#FFC83D", tintStrength = 0.85, reflectance = 0.15 },
	},
	{
		id = "diamond",
		displayName = "Diamond",
		color = "#8FF3FF",
		order = 2,
		chance = 0.008,
		incomeMultiplier = 4,
		priceMultiplier = 2.5,
		announceOnSpawn = false,
		announceOnBuy = false,
		announceOnSteal = false,
		look = {
			material = "Glass",
			tint = "#BFF7FF",
			tintStrength = 0.8,
			transparency = 0.3,
			reflectance = 0.25,
			sparkles = true,
		},
	},
	{
		id = "rainbow",
		displayName = "Rainbow",
		color = "#FF5FD2",
		order = 3,
		chance = 0.0015,
		incomeMultiplier = 8,
		priceMultiplier = 4,
		announceOnSpawn = true,
		announceOnBuy = true,
		announceOnSteal = true,
		look = { material = "Neon", rainbow = true },
	},
}

return Mutations
