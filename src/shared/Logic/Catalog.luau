--!strict
--[[
	Indexes the creature + rarity config for fast lookups and validates its integrity. Config tables are passed
	in so tests can feed fixtures. Pure: no Roblox APIs.

]]

local Types = require("../Types")

export type RarityInfo = Types.RarityDef
export type CreatureInfo = Types.CreatureDef

export type Catalog = {
	creatures: { [string]: CreatureInfo },
	creatureList: { CreatureInfo },
	rarities: { [string]: RarityInfo },
	rarityList: { RarityInfo }, -- sorted by order (most common first)
	byRarity: { [string]: { CreatureInfo } },
}

local Catalog = {}

function Catalog.build(creatures: { CreatureInfo }, rarities: { RarityInfo }): Catalog
	local rarityMap: { [string]: RarityInfo } = {}
	local rarityList: { RarityInfo } = table.clone(rarities)
	table.sort(rarityList, function(a: RarityInfo, b: RarityInfo): boolean
		return a.order < b.order
	end)
	local byRarity: { [string]: { CreatureInfo } } = {}
	for _, rarity in rarityList do
		rarityMap[rarity.id] = rarity
		byRarity[rarity.id] = {}
	end

	local creatureMap: { [string]: CreatureInfo } = {}
	for _, creature in creatures do
		creatureMap[creature.id] = creature
		local bucket = byRarity[creature.rarity]
		if bucket ~= nil then
			table.insert(bucket, creature)
		end
	end

	return {
		creatures = creatureMap,
		creatureList = creatures,
		rarities = rarityMap,
		rarityList = rarityList,
		byRarity = byRarity,
	}
end

-- Returns a list of human-readable problems; an empty list means the config is valid.
function Catalog.validate(creatures: { CreatureInfo }, rarities: { RarityInfo }): { string }
	local problems: { string } = {}
	local function problem(message: string)
		table.insert(problems, message)
	end

	local rarityIds: { [string]: boolean } = {}
	local orders: { [number]: boolean } = {}
	for _, rarity in rarities do
		if rarityIds[rarity.id] then
			problem(`duplicate rarity id {rarity.id}`)
		end
		rarityIds[rarity.id] = true
		if orders[rarity.order] then
			problem(`duplicate rarity order {rarity.order}`)
		end
		orders[rarity.order] = true
		if not (rarity.beltWeight > 0) then
			problem(`rarity {rarity.id} needs a positive beltWeight`)
		end
		if string.match(rarity.color, "^#%x%x%x%x%x%x$") == nil then
			problem(`rarity {rarity.id} colour must be #RRGGBB`)
		end
	end

	local creatureIds: { [string]: boolean } = {}
	local modelNames: { [string]: boolean } = {}
	local perRarity: { [string]: number } = {}
	for _, creature in creatures do
		if creatureIds[creature.id] then
			problem(`duplicate creature id {creature.id}`)
		end
		creatureIds[creature.id] = true
		if modelNames[creature.modelName] then
			problem(`duplicate modelName {creature.modelName}`)
		end
		modelNames[creature.modelName] = true
		if not rarityIds[creature.rarity] then
			problem(`creature {creature.id} has unknown rarity {creature.rarity}`)
		end
		if not (creature.price > 0) or creature.price ~= math.floor(creature.price) then
			problem(`creature {creature.id} needs a positive whole price`)
		end
		if not (creature.income > 0) then
			problem(`creature {creature.id} needs a positive income`)
		end
		if not (creature.beltWeight > 0) then
			problem(`creature {creature.id} needs a positive beltWeight`)
		end
		if string.match(creature.id, "^[%w_]+$") == nil or #creature.id > 40 then
			problem(`creature id {creature.id} must be short and alphanumeric/underscore`)
		end
		if creature.eventId == nil then
			perRarity[creature.rarity] = (perRarity[creature.rarity] or 0) + 1
		end
	end

	for id in rarityIds do
		if (perRarity[id] or 0) == 0 then
			problem(`rarity {id} has no always-available creatures`)
		end
	end

	return problems
end

function Catalog.rarityOf(catalog: Catalog, creatureId: string): RarityInfo?
	local creature = catalog.creatures[creatureId]
	if creature == nil then
		return nil
	end
	return catalog.rarities[creature.rarity]
end

return Catalog
