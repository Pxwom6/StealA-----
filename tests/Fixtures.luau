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
		look = { body = "Ball", bodyColor = "#FFFFFF", accent = "Ears", accentColor = "#000000", size = 1 },
		eventId = eventId,
	}
end

return Fixtures
