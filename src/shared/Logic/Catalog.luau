--!strict
--[[
	Indexes the creature + rarity + mutation config for fast lookups and validates its integrity. Config tables are
	passed in so tests can feed fixtures. Pure: no Roblox APIs.

]]

local MutationRules = require("./MutationRules")
local Types = require("../Types")

export type RarityInfo = Types.RarityDef
export type CreatureInfo = Types.CreatureDef
export type MutationInfo = Types.MutationDef

export type Catalog = {
	creatures: { [string]: CreatureInfo },
	creatureList: { CreatureInfo },
	rarities: { [string]: RarityInfo },
	rarityList: { RarityInfo }, -- sorted by order (most common first)
	byRarity: { [string]: { CreatureInfo } },
	mutations: { [string]: MutationInfo },
	mutationList: { MutationInfo }, -- sorted by order
}

local Catalog = {}

-- Enum.Material names a mutation look may use (checked in CI, since pure code cannot see Roblox enums).
Catalog.MUTATION_MATERIALS = {
	"Plastic",
	"SmoothPlastic",
	"Neon",
	"Glass",
	"Foil",
	"Metal",
	"DiamondPlate",
	"ForceField",
	"Ice",
	"Glacier",
	"Marble",
	"Granite",
	"Slate",
	"Pebble",
	"Fabric",
	"Sand",
	"Wood",
	"WoodPlanks",
	"CorrodedMetal",
	"CrackedLava",
	"Sandstone",
	"Limestone",
	"Basalt",
	"Salt",
	"Grass",
}

-- Particle presets a mutation look may add around the body (MutationLook.particles; built by CreatureVisuals).
Catalog.MUTATION_PARTICLES = {
	"drips",
	"sprinkles",
	"snow",
	"dust",
	"embers",
	"motes",
	"bubbles",
	"leaves",
	"sparks",
	"stars",
	"ooze",
	"petals",
	"glitter",
	"pollen",
	"glitch",
	"feathers",
	"biolume",
}

local HEX_PATTERN = "^#%x%x%x%x%x%x$"

local function isFinite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

function Catalog.build(creatures: { CreatureInfo }, rarities: { RarityInfo }, mutations: { MutationInfo }?): Catalog
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

	local mutationList: { MutationInfo } = table.clone(mutations or {})
	table.sort(mutationList, function(a: MutationInfo, b: MutationInfo): boolean
		return a.order < b.order
	end)
	local mutationMap: { [string]: MutationInfo } = {}
	for _, mutation in mutationList do
		mutationMap[mutation.id] = mutation
	end

	return {
		creatures = creatureMap,
		creatureList = creatures,
		rarities = rarityMap,
		rarityList = rarityList,
		byRarity = byRarity,
		mutations = mutationMap,
		mutationList = mutationList,
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
	local displayNames: { [string]: boolean } = {}
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
		if displayNames[creature.displayName] then
			problem(`duplicate displayName {creature.displayName}`)
		end
		displayNames[creature.displayName] = true
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

-- Problems with the mutation config (an empty list means valid): unique short ids and orders, chances in (0, 1)
-- whose total stays below 1 even with every event-only mutation active plus the strongest map's and modifier's, at
-- most one gate each, multipliers >= 1, valid colours and looks. Whether a gate names a real map theme / modifier is
-- checked against those configs in tests/Config.spec.luau.
function Catalog.validateMutations(mutations: { MutationInfo }): { string }
	local problems: { string } = {}
	local function problem(message: string)
		table.insert(problems, message)
	end

	local ids: { [string]: boolean } = {}
	local orders: { [number]: boolean } = {}
	for _, mutation in mutations do
		local id = mutation.id
		if ids[id] then
			problem(`duplicate mutation id {id}`)
		end
		ids[id] = true
		if string.match(id, "^[%w_]+$") == nil or #id > 40 then
			problem(`mutation id {id} must be short and alphanumeric/underscore`)
		end
		if orders[mutation.order] then
			problem(`duplicate mutation order {mutation.order}`)
		end
		orders[mutation.order] = true
		if mutation.displayName == "" then
			problem(`mutation {id} needs a displayName`)
		end
		if string.match(mutation.color, HEX_PATTERN) == nil then
			problem(`mutation {id} colour must be #RRGGBB`)
		end
		if not (mutation.chance > 0 and mutation.chance < 1) then
			problem(`mutation {id} chance must be between 0 and 1 (exclusive)`)
		end
		if not (isFinite(mutation.incomeMultiplier) and mutation.incomeMultiplier >= 1) then
			problem(`mutation {id} incomeMultiplier must be a number >= 1`)
		end
		if not (isFinite(mutation.priceMultiplier) and mutation.priceMultiplier >= 1) then
			problem(`mutation {id} priceMultiplier must be a number >= 1`)
		end
		local gates = 0
		for _, key in { "eventId", "mapTheme", "modifierId" } do
			local value = (mutation :: any)[key]
			if value ~= nil then
				gates += 1
				if type(value) ~= "string" or value == "" or string.find(value, ":", 1, true) then
					problem(`mutation {id} {key} must be a non-empty id without a colon`)
				end
			end
		end
		if gates > 1 then
			problem(`mutation {id} has more than one gate (eventId, mapTheme, modifierId): pick one`)
		end

		local look = mutation.look
		if table.find(Catalog.MUTATION_MATERIALS, look.material) == nil then
			problem(`mutation {id} look.material {look.material} is not a known material`)
		end
		if look.tint ~= nil and string.match(look.tint, HEX_PATTERN) == nil then
			problem(`mutation {id} look.tint must be #RRGGBB`)
		end
		if look.tintStrength ~= nil and not (look.tintStrength >= 0 and look.tintStrength <= 1) then
			problem(`mutation {id} look.tintStrength must be between 0 and 1`)
		end
		if look.transparency ~= nil and not (look.transparency >= 0 and look.transparency < 1) then
			problem(`mutation {id} look.transparency must be in [0, 1)`)
		end
		if look.reflectance ~= nil and not (look.reflectance >= 0 and look.reflectance <= 1) then
			problem(`mutation {id} look.reflectance must be between 0 and 1`)
		end
		if look.glow ~= nil and string.match(look.glow, HEX_PATTERN) == nil then
			problem(`mutation {id} look.glow must be #RRGGBB`)
		end
		if look.particles ~= nil and table.find(Catalog.MUTATION_PARTICLES, look.particles) == nil then
			problem(`mutation {id} look.particles {look.particles} is not a known preset`)
		end
	end
	-- Only one map and one modifier are ever live at once: the most that can roll together (MutationRules).
	local worst = MutationRules.worstCaseTotal(mutations)
	if not (worst < 1) then
		problem(`mutation chances add up to {worst}; together they must stay below 1`)
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
