--!strict
--[[
	Mutation rules: which mutation (if any) a belt spawn gets, and what a mutated creature costs and earns.

	Every place that reads a creature's price or income for a belt item or an owned creature goes through
	`price` / `income` here, so a mutation applies everywhere (belt, income tick, podium labels, sell value, cash
	packs, offline earnings, balance simulation). A variant that is nil or not in the config pays x1, so a save
	holding an id that was removed by mistake keeps it and earns normally again once the id is restored.

	Mutation chances are absolute (per spawn) and never scaled by luck; only a server modifier (Config/Modifiers
	`mutationChance`, e.g. Golden Hour) multiplies them while it runs. Pure: no Roblox APIs; the RNG, the active
	conditions and that multiplier are passed in.

	Gates: a mutation may only roll during a LiveOps event (`eventId`), on one map theme (`mapTheme`, the map's
	signature mutation) or while one server modifier runs (`modifierId`). The roll takes one set of active condition
	keys (`conditions`): LiveOps event ids as they are, plus mapKey(theme) and modifierKey(id). Event ids never contain
	a colon, so the three kinds never clash.
]]

local Format = require("./Format")
local Types = require("../Types")

type MutationDef = Types.MutationDef
type CreatureDef = Types.CreatureDef

export type Odds = { id: string, chance: number }

local MutationRules = {}

-- The condition key of map theme `themeId` / server modifier `modifierId` (see the header).
function MutationRules.mapKey(themeId: string): string
	return `map:{themeId}`
end

function MutationRules.modifierKey(modifierId: string): string
	return `modifier:{modifierId}`
end

-- The active condition keys: the running LiveOps events (a set of ids), the current map theme and the running server
-- modifier (nil: none). A new table; `events` is not changed.
function MutationRules.conditions(
	events: { [string]: boolean },
	mapTheme: string?,
	modifierId: string?
): { [string]: boolean }
	local active: { [string]: boolean } = {}
	for id, on in events do
		if on then
			active[id] = true
		end
	end
	if mapTheme then
		active[MutationRules.mapKey(mapTheme)] = true
	end
	if modifierId then
		active[MutationRules.modifierKey(modifierId)] = true
	end
	return active
end

-- What a mutation waits for: "event", "map", "modifier", or nil when it can roll on any spawn (a permanent one).
function MutationRules.gate(mutation: MutationDef): string?
	if mutation.eventId ~= nil then
		return "event"
	elseif mutation.mapTheme ~= nil then
		return "map"
	elseif mutation.modifierId ~= nil then
		return "modifier"
	end
	return nil
end

-- Whether the mutation can roll under the active conditions (MutationRules.conditions; a plain set of event ids
-- works for event gates).
function MutationRules.isEligible(mutation: MutationDef, active: { [string]: boolean }): boolean
	if mutation.eventId ~= nil and active[mutation.eventId] ~= true then
		return false
	end
	if mutation.mapTheme ~= nil and active[MutationRules.mapKey(mutation.mapTheme)] ~= true then
		return false
	end
	if mutation.modifierId ~= nil and active[MutationRules.modifierKey(mutation.modifierId)] ~= true then
		return false
	end
	return true
end

-- The highest total mutation chance per spawn that can ever be live at once: every permanent and event mutation
-- (events may overlap), plus the strongest single map's signature mutations (one map at a time) and the strongest
-- single modifier's (one modifier at a time). Validation keeps this well below 1. With `modifierId`, the most that can
-- be live while that modifier runs: its own mutations take the strongest modifier's place, since no other modifier
-- runs then (Golden Hour unlocks none, so no weather mutation rolls during it).
function MutationRules.worstCaseTotal(mutations: { MutationDef }, modifierId: string?): number
	local total = 0
	local byMap: { [string]: number } = {}
	local byModifier: { [string]: number } = {}
	for _, mutation in mutations do
		local chance = math.max(0, mutation.chance)
		if mutation.mapTheme ~= nil then
			byMap[mutation.mapTheme] = (byMap[mutation.mapTheme] or 0) + chance
		elseif mutation.modifierId ~= nil then
			byModifier[mutation.modifierId] = (byModifier[mutation.modifierId] or 0) + chance
		else
			total += chance
		end
	end
	local bestMap, bestModifier = 0, 0
	for _, chance in byMap do
		bestMap = math.max(bestMap, chance)
	end
	for _, chance in byModifier do
		bestModifier = math.max(bestModifier, chance)
	end
	if modifierId ~= nil then
		bestModifier = byModifier[modifierId] or 0
	end
	return total + bestMap + bestModifier
end

-- The signature mutation of map theme `themeId` (the first by order), or nil.
function MutationRules.forMap(mutations: { MutationDef }, themeId: string): MutationDef?
	local found: MutationDef? = nil
	for _, mutation in mutations do
		if mutation.mapTheme == themeId and (found == nil or mutation.order < found.order) then
			found = mutation
		end
	end
	return found
end

-- The mutation server modifier `modifierId` unlocks (the first by order), or nil.
function MutationRules.forModifier(mutations: { MutationDef }, modifierId: string): MutationDef?
	local found: MutationDef? = nil
	for _, mutation in mutations do
		if mutation.modifierId == modifierId and (found == nil or mutation.order < found.order) then
			found = mutation
		end
	end
	return found
end

-- The eligible mutations in roll order (by `order`), each with its exact chance per spawn: the configured chance times
-- `chanceMultiplier` (default 1). Catalog.validateMutations and ModifierRules.validate keep the total well below 1 (it
-- is clamped here as a last resort). `active`: the active condition keys (MutationRules.conditions).
function MutationRules.odds(
	mutations: { MutationDef },
	active: { [string]: boolean },
	chanceMultiplier: number?
): { Odds }
	local multiplier = math.max(0, chanceMultiplier or 1)
	local eligible: { MutationDef } = {}
	for _, mutation in mutations do
		if MutationRules.isEligible(mutation, active) and mutation.chance > 0 then
			table.insert(eligible, mutation)
		end
	end
	table.sort(eligible, function(a: MutationDef, b: MutationDef): boolean
		return a.order < b.order
	end)
	local result: { Odds } = {}
	local total = 0
	for _, mutation in eligible do
		local chance = math.min(mutation.chance * multiplier, math.max(0, 1 - total))
		total += chance
		table.insert(result, { id = mutation.id, chance = chance })
	end
	return result
end

-- Rolls the mutation for one belt spawn: a mutation id, or nil for a plain creature. Always draws exactly one
-- number from `rng` (which returns numbers in [0, 1)), so a seeded roll sequence stays reproducible.
function MutationRules.roll(
	mutations: { MutationDef },
	active: { [string]: boolean },
	rng: () -> number,
	chanceMultiplier: number?
): string?
	local r = rng()
	local running = 0
	for _, entry in MutationRules.odds(mutations, active, chanceMultiplier) do
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

-- Whether a spawn / buy / steal (`kind`) gets a server-wide banner, and its colour override. Either the rarity's own
-- flag (`rarityAnnounces`) or the mutation's flag for that kind is enough. When the rarity announces, its colour is
-- kept (nil override) even if the mutation would announce too; the mutation still shows, because the banner text
-- always uses the mutated name (displayName). Only a banner the mutation alone triggers takes the mutation colour.
function MutationRules.banner(rarityAnnounces: boolean, mutation: MutationDef?, kind: string): (boolean, string?)
	local mutationAnnounces = false
	if mutation then
		mutationAnnounces = if kind == "spawn"
			then mutation.announceOnSpawn
			elseif kind == "buy" then mutation.announceOnBuy
			else mutation.announceOnSteal
	end
	if not rarityAnnounces and not mutationAnnounces then
		return false, nil
	end
	return true, if not rarityAnnounces and mutation then mutation.color else nil
end

-- Expected income and price multiplier of one belt spawn (for BALANCE.md): 1 + sum of chance × (multiplier - 1).
function MutationRules.expectedMultipliers(mutations: { MutationDef }, active: { [string]: boolean }): (number, number)
	local byId: { [string]: MutationDef } = {}
	for _, mutation in mutations do
		byId[mutation.id] = mutation
	end
	local income, price = 1, 1
	for _, entry in MutationRules.odds(mutations, active) do
		local mutation = byId[entry.id]
		income += entry.chance * (mutation.incomeMultiplier - 1)
		price += entry.chance * (mutation.priceMultiplier - 1)
	end
	return income, price
end

return MutationRules
