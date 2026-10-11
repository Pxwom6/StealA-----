--!strict
-- Builders for full config records, so specs can describe small worlds without repeating every field.
local Types = require("../src/shared/Types")

local Fixtures = {}

function Fixtures.rarity(id: string, order: number, beltWeight: number, luckAffected: boolean): Types.RarityDef
	return {
		id = id,
		order = order,
		displayName = id,
		color = "#FFFFFF",
		beltWeight = beltWeight,
		luckAffected = luckAffected,
		glow = false,
		particles = false,
		announceOnSpawn = false,
		announceOnBuy = false,
		announceOnSteal = false,
		modelScale = 1,
	}
end

function Fixtures.creature(id: string, rarity: string, beltWeight: number, eventId: string?): Types.CreatureDef
	return {
		id = id,
		displayName = id,
		rarity = rarity,
		price = 10,
		income = 1,
		beltWeight = beltWeight,
		modelName = id,
		flavor = "",
		eventId = eventId,
	}
end

function Fixtures.mutation(id: string, order: number, chance: number, eventId: string?): Types.MutationDef
	return {
		id = id,
		displayName = id,
		color = "#FFFFFF",
		order = order,
		chance = chance,
		incomeMultiplier = 2,
		priceMultiplier = 1.5,
		announceOnSpawn = false,
		announceOnBuy = false,
		announceOnSteal = false,
		look = { material = "Neon" },
		eventId = eventId,
	}
end

return Fixtures
