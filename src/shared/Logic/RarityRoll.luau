--!strict
--[[
	Weighted conveyor rolls. Two stages: pick a rarity tier, then a creature inside that tier.
	Luck multiplies the weight of luck-affected tiers (Rare and up), which lowers Common/Uncommon odds in turn.
	Creatures with an `eventId` are only eligible while that event is active.

	The RNG is passed in as a function returning a number in [0, 1) so tests are deterministic and the server
	can use a Random object. Pure: no Roblox APIs.
]]

local Types = require("../Types")

type RarityWeight = Types.RarityDef
type CreatureWeight = Types.CreatureDef
export type Odds = { id: string, chance: number }

local RarityRoll = {}

local function isEligible(creature: CreatureWeight, activeEvents: { [string]: boolean }): boolean
	return creature.eventId == nil or activeEvents[creature.eventId] == true
end

-- Picks an element by weight. `r` must be in [0, 1). Returns nil only if the total weight is zero.
function RarityRoll.pickWeighted<T>(items: { T }, weightOf: (T) -> number, r: number): T?
	local total = 0
	for _, item in items do
		total += math.max(0, weightOf(item))
	end
	if total <= 0 then
		return nil
	end
	local target = math.clamp(r, 0, 0.999999999) * total
	local running = 0
	local last: T? = nil
	for _, item in items do
		local w = math.max(0, weightOf(item))
		if w > 0 then
			running += w
			last = item
			if target < running then
				return item
			end
		end
	end
	return last
end

-- Effective weight of each rarity, skipping tiers with no eligible creature.
function RarityRoll.rarityWeights(
	rarities: { RarityWeight },
	creatures: { CreatureWeight },
	luck: number,
	activeEvents: { [string]: boolean }
): { [string]: number }
	local hasEligible: { [string]: boolean } = {}
	for _, creature in creatures do
		if isEligible(creature, activeEvents) and creature.beltWeight > 0 then
			hasEligible[creature.rarity] = true
		end
	end
	local safeLuck = if luck == luck and luck > 0 then luck else 1
	local weights: { [string]: number } = {}
	for _, rarity in rarities do
		if hasEligible[rarity.id] then
			weights[rarity.id] = rarity.beltWeight * (if rarity.luckAffected then safeLuck else 1)
		end
	end
	return weights
end

-- Exact probability of each rarity tier, in the given tier order. Used by the store's odds disclosure.
function RarityRoll.odds(
	rarities: { RarityWeight },
	creatures: { CreatureWeight },
	luck: number,
	activeEvents: { [string]: boolean }
): { Odds }
	local weights = RarityRoll.rarityWeights(rarities, creatures, luck, activeEvents)
	local total = 0
	for _, w in weights do
		total += w
	end
	local result: { Odds } = {}
	for _, rarity in rarities do
		local w = weights[rarity.id] or 0
		table.insert(result, { id = rarity.id, chance = if total > 0 then w / total else 0 })
	end
	return result
end

-- Rolls one creature id. `rng` returns numbers in [0, 1).
function RarityRoll.roll(
	rarities: { RarityWeight },
	creatures: { CreatureWeight },
	luck: number,
	activeEvents: { [string]: boolean },
	rng: () -> number
): string?
	local weights = RarityRoll.rarityWeights(rarities, creatures, luck, activeEvents)
	local rarity = RarityRoll.pickWeighted(rarities, function(r: RarityWeight): number
		return weights[r.id] or 0
	end, rng())
	if rarity == nil then
		return nil
	end
	local pool: { CreatureWeight } = {}
	for _, creature in creatures do
		if creature.rarity == rarity.id and isEligible(creature, activeEvents) then
			table.insert(pool, creature)
		end
	end
	local creature = RarityRoll.pickWeighted(pool, function(c: CreatureWeight): number
		return c.beltWeight
	end, rng())
	return if creature then creature.id else nil
end

return RarityRoll
