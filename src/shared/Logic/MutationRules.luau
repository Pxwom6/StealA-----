--!strict
--[[
	Mutation rules: which mutation (if any) a belt spawn gets, and what a mutated creature costs and earns.

	Every place that reads a creature's price or income for a belt item or an owned creature goes through
	`price` / `income` here, so a mutation applies everywhere (belt, income tick, podium labels, sell value, cash
	packs, offline earnings, balance simulation). A variant that is nil or not in the config pays x1, so a save
	holding an id that was removed by mistake keeps it and earns normally again once the id is restored.

	Mutation chances are absolute (per spawn) and never scaled by luck. Pure: no Roblox APIs; the RNG and the
	active-event set are passed in.
]]

local Format = require("./Format")
local Types = require("../Types")

type MutationDef = Types.MutationDef
type CreatureDef = Types.CreatureDef

export type Odds = { id: string, chance: number }

local MutationRules = {}

function MutationRules.isEligible(mutation: MutationDef, activeEvents: { [string]: boolean }): boolean
	return mutation.eventId == nil or activeEvents[mutation.eventId] == true
end

-- The eligible mutations in roll order (by `order`), each with its exact chance per spawn. The chances are used as
-- given; Catalog.validateMutations keeps their total below 1 (it is clamped here as a last resort).
function MutationRules.odds(mutations: { MutationDef }, activeEvents: { [string]: boolean }): { Odds }
	local eligible: { MutationDef } = {}
	for _, mutation in mutations do
		if MutationRules.isEligible(mutation, activeEvents) and mutation.chance > 0 then
			table.insert(eligible, mutation)
		end
	end
	table.sort(eligible, function(a: MutationDef, b: MutationDef): boolean
		return a.order < b.order
	end)
	local result: { Odds } = {}
	local total = 0
	for _, mutation in eligible do
		local chance = math.min(mutation.chance, math.max(0, 1 - total))
		total += chance
		table.insert(result, { id = mutation.id, chance = chance })
	end
	return result
end

-- Rolls the mutation for one belt spawn: a mutation id, or nil for a plain creature. Always draws exactly one
-- number from `rng` (which returns numbers in [0, 1)), so a seeded roll sequence stays reproducible.
function MutationRules.roll(mutations: { MutationDef }, activeEvents: { [string]: boolean }, rng: () -> number): string?
	local r = rng()
	local running = 0
	for _, entry in MutationRules.odds(mutations, activeEvents) do
		running += entry.chance
		if r < running then
			return entry.id
		end
	end
	return nil
end

-- The mutation a saved / belt variant refers to, or nil (plain, or an id the config no longer has).
function MutationRules.find(byId: { [string]: MutationDef }, variant: string?): MutationDef?
	if variant == nil then
		return nil
	end
	return byId[variant]
end

-- Belt price of a creature with this variant: a whole number, never below the base price.
function MutationRules.price(byId: { [string]: MutationDef }, creature: CreatureDef, variant: string?): number
	local mutation = MutationRules.find(byId, variant)
	if mutation == nil then
		return creature.price
	end
	return math.max(creature.price, math.floor(creature.price * mutation.priceMultiplier + 0.5))
end

-- Base cash per second of a creature with this variant (before rebirth / pass / event multipliers).
function MutationRules.income(byId: { [string]: MutationDef }, creature: CreatureDef, variant: string?): number
	local mutation = MutationRules.find(byId, variant)
	if mutation == nil then
		return creature.income
	end
	return creature.income * math.max(1, mutation.incomeMultiplier)
end

-- "Golden Pizza Pup" from a template such as "{mutation} {creature}"; the plain name without a known mutation.
function MutationRules.displayName(
	byId: { [string]: MutationDef },
	creature: CreatureDef,
	variant: string?,
	template: string
): string
	local mutation = MutationRules.find(byId, variant)
	if mutation == nil then
		return creature.displayName
	end
	return Format.template(template, { mutation = mutation.displayName, creature = creature.displayName })
end

-- Expected income and price multiplier of one belt spawn (for BALANCE.md): 1 + sum of chance × (multiplier - 1).
function MutationRules.expectedMultipliers(
	mutations: { MutationDef },
	activeEvents: { [string]: boolean }
): (number, number)
	local byId: { [string]: MutationDef } = {}
	for _, mutation in mutations do
		byId[mutation.id] = mutation
	end
	local income, price = 1, 1
	for _, entry in MutationRules.odds(mutations, activeEvents) do
		local mutation = byId[entry.id]
		income += entry.chance * (mutation.incomeMultiplier - 1)
		price += entry.chance * (mutation.priceMultiplier - 1)
	end
	return income, price
end

return MutationRules
