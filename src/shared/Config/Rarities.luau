--!strict
--[[
	Rarity tiers, from most common to rarest. Plain data only (no Roblox types) so Lune tests can load it. Colours are hex strings; the Roblox layer converts them with Color3.fromHex.

	beltWeight      relative chance for the conveyor to pick this tier (luck boosts multiply luck-affected tiers)
	glow/particles  visual flair on podiums and the belt
	announce*       server-wide banner when one spawns on the belt / is bought / is stolen
]]

local Types = require("../Types")

export type RarityDef = Types.RarityDef

local Rarities: { RarityDef } = {
	{
		id = "Common",
		order = 1,
		displayName = "Common",
		color = "#C9D1DA",
		beltWeight = 560,
		luckAffected = false,
		glow = false,
		particles = false,
		announceOnSpawn = false,
		announceOnBuy = false,
		announceOnSteal = false,
		modelScale = 1,
	},
	{
		id = "Uncommon",
		order = 2,
		displayName = "Uncommon",
		color = "#5CE05C",
		beltWeight = 270,
		luckAffected = false,
		glow = false,
		particles = false,
		announceOnSpawn = false,
		announceOnBuy = false,
		announceOnSteal = false,
		modelScale = 1.05,
	},
	{
		id = "Rare",
		order = 3,
		displayName = "Rare",
		color = "#3FA9FF",
		beltWeight = 115,
		luckAffected = true,
		glow = true,
		particles = false,
		announceOnSpawn = false,
		announceOnBuy = false,
		announceOnSteal = false,
		modelScale = 1.1,
	},
	{
		id = "Epic",
		order = 4,
		displayName = "Epic",
		color = "#B65CFF",
		beltWeight = 42,
		luckAffected = true,
		glow = true,
		particles = true,
		announceOnSpawn = false,
		announceOnBuy = false,
		announceOnSteal = false,
		modelScale = 1.2,
	},
	{
		id = "Legendary",
		order = 5,
		displayName = "Legendary",
		color = "#FFB21E",
		beltWeight = 11,
		luckAffected = true,
		glow = true,
		particles = true,
		announceOnSpawn = false,
		announceOnBuy = false,
		announceOnSteal = true,
		modelScale = 1.3,
	},
	{
		id = "Mythic",
		order = 6,
		displayName = "Mythic",
		color = "#FF3B6B",
		beltWeight = 1.8,
		luckAffected = true,
		glow = true,
		particles = true,
		announceOnSpawn = true,
		announceOnBuy = true,
		announceOnSteal = true,
		modelScale = 1.45,
	},
	{
		id = "Secret",
		order = 7,
		displayName = "SECRET",
		color = "#1DFFE0",
		beltWeight = 0.2,
		luckAffected = true,
		glow = true,
		particles = true,
		announceOnSpawn = true,
		announceOnBuy = true,
		announceOnSteal = true,
		modelScale = 1.6,
	},
}

return Rarities
