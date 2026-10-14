--!strict
--[[
	Server modifier rules (Config/Modifiers): the effects of the running modifier, the belt price it makes, which one
	comes next and when, and validation. Pure: no Roblox APIs; random numbers come in as a function returning [0, 1).

	The client works out prices, hold times and tag reach with the same `effects` from the modifier id the server
	publishes, so what a player sees is what the server checks.
]]

local DropRules = require("./DropRules")
local MapThemeRules = require("./MapThemeRules")
local SeasonRules = require("./SeasonRules")
local Types = require("../Types")

type ModifiersConfig = Types.ModifiersConfig
type ModifierDef = Types.ModifierDef

-- Every effect, resolved (1 = unchanged).
export type Effects = {
	spawnInterval: number,
	beltPrice: number,
	mutationChance: number,
	luck: number,
	income: number,
	walkSpeed: number,
	stealHold: number,
	lockDuration: number,
	tagRange: number,
}

local ModifierRules = {}

ModifierRules.EFFECT_KEYS = table.freeze({
	"spawnInterval",
	"beltPrice",
	"mutationChance",
	"luck",
	"income",
	"walkSpeed",
	"stealHold",
	"lockDuration",
	"tagRange",
})

-- Effects in the sky a weather modifier may use (the client builds them: WeatherController).
ModifierRules.SKY_EFFECTS = table.freeze({ lightning = true, meteors = true, aurora = true } :: { [string]: boolean })

local HEX_PATTERN = "^#%x%x%x%x%x%x$"

function ModifierRules.none(): Effects
	return {
		spawnInterval = 1,
		beltPrice = 1,
		mutationChance = 1,
		luck = 1,
		income = 1,
		walkSpeed = 1,
		stealHold = 1,
		lockDuration = 1,
		tagRange = 1,
	}
end

-- The effects of modifier `id` (nothing running, or an unknown id: no effects).
function ModifierRules.effects(config: ModifiersConfig, id: string?): Effects
	local result = ModifierRules.none()
	local def = if id then config.modifiers[id] else nil
	if def then
		local raw = def.effects :: { [string]: number? }
		for _, key in ModifierRules.EFFECT_KEYS do
			local value = raw[key]
			if type(value) == "number" and value == value and value > 0 then
				(result :: any)[key] = value
			end
		end
	end
	return result
end

-- A belt item's price while `effects` run: whole cash, at least 1 (the unchanged price when there is no discount).
function ModifierRules.beltPrice(price: number, effects: Effects): number
	if effects.beltPrice == 1 then
		return price
	end
	return math.max(1, math.floor(price * effects.beltPrice + 0.5))
end

-- How many items the belt may hold: more when it spawns faster, so a faster belt really carries more.
function ModifierRules.beltCapacity(maxItems: number, effects: Effects): number
	return math.ceil(maxItems / math.min(1, effects.spawnInterval))
end

-- Picks the next modifier: weighted, never `last` (unless it is the only one that can come up). nil when none can.
function ModifierRules.pick(config: ModifiersConfig, last: string?, random: () -> number): string?
	local pool: { string } = {}
	local total = 0
	for _, id in config.order do
		local def = config.modifiers[id]
		if def and def.weight > 0 and id ~= last then
			table.insert(pool, id)
			total += def.weight
		end
	end
	if #pool == 0 then
		if last and config.modifiers[last] and config.modifiers[last].weight > 0 then
			return last
		end
		return nil
	end
	local roll = random() * total
	for _, id in pool do
		local weight = config.modifiers[id].weight
		if roll < weight then
			return id
		end
		roll -= weight
	end
	return pool[#pool]
end

-- Seconds until the next modifier after one ends: uniform between the schedule's gaps.
function ModifierRules.gap(schedule: Types.ModifierSchedule, random: () -> number): number
	return schedule.gapMinSeconds + (schedule.gapMaxSeconds - schedule.gapMinSeconds) * random()
end

-- The largest walking-speed multiplier any modifier can set (the movement checks never need more than this).
function ModifierRules.maxWalkSpeed(config: ModifiersConfig): number
	local best = 1
	for _, def in config.modifiers do
		best = math.max(best, def.effects.walkSpeed or 1)
	end
	return best
end

-- Problems with Config/Modifiers (an empty list means valid). `mutationChanceTotal` is the most mutation chance per
-- spawn that can be live at once (MutationRules.worstCaseTotal): even multiplied by the strongest mutation modifier it
-- must stay well below 1. `unlocks`: the modifiers a mutation is gated on (Config/Mutations modifierId); such a
-- modifier may have no other effect.
function ModifierRules.validate(
	config: ModifiersConfig,
	mutationChanceTotal: number,
	unlocks: { [string]: boolean }?
): { string }
	local problems: { string } = {}
	local function problem(message: string)
		table.insert(problems, message)
	end

	local seen: { [string]: boolean } = {}
	for _, id in config.order do
		if config.modifiers[id] == nil then
			problem(`order lists unknown modifier {id}`)
		elseif seen[id] then
			problem(`order lists {id} twice`)
		end
		seen[id] = true
	end
	local pickable = 0
	for id, def in config.modifiers do
		local name = `modifier {id}`
		if not seen[id] then
			problem(`{name} is missing from order`)
		end
		if def.displayName == "" or #def.displayName > 20 then
			problem(`{name} needs a displayName of at most 20 characters`)
		end
		if def.icon == "" then
			problem(`{name} needs an icon`)
		end
		if def.description == "" or #def.description > 60 then
			problem(`{name} needs a description of at most 60 characters`)
		end
		if string.match(def.color, HEX_PATTERN) == nil then
			problem(`{name} color must be #RRGGBB`)
		end
		if not (def.weight >= 0) then
			problem(`{name} weight must be 0 or more`)
		elseif def.weight > 0 then
			pickable += 1
		end
		local raw = def.effects :: { [string]: any }
		local any = false
		for key, value in raw do
			local limit = config.limits[key]
			if table.find(ModifierRules.EFFECT_KEYS, key) == nil or limit == nil then
				problem(`{name} has an unknown effect {key}`)
			elseif type(value) ~= "number" or not (value >= limit.min and value <= limit.max) then
				problem(`{name} {key} must be between {limit.min} and {limit.max}`)
			elseif value ~= 1 then
				any = true
			end
		end
		if not any and not (unlocks and unlocks[id]) and def.drops == nil then
			problem(`{name} changes nothing`)
		end
		if def.drops then
			for _, message in DropRules.dropsProblems(def.drops, config.schedule.durationSeconds, name) do
				problem(message)
			end
		end
		if def.weather ~= nil and not MapThemeRules.WEATHER[def.weather] then
			problem(`{name} weather {def.weather} is not a known kind`)
		end
		if def.skyEffect ~= nil and not ModifierRules.SKY_EFFECTS[def.skyEffect] then
			problem(`{name} skyEffect {def.skyEffect} is not a known effect`)
		end
		if def.lighting then
			for _, message in SeasonRules.lightingProblems(def.lighting, name) do
				problem(message)
			end
		end
		local chance = ModifierRules.effects(config, id).mutationChance
		if mutationChanceTotal * chance >= 0.5 then
			problem(`{name} would make mutations too common ({mutationChanceTotal * chance})`)
		end
	end
	if pickable == 0 then
		problem("no modifier has a weight above 0")
	end

	local schedule = config.schedule
	if not (schedule.durationSeconds >= 30 and schedule.durationSeconds <= 30 * 60) then
		problem("schedule.durationSeconds must be between 30 and 1800")
	end
	if not (schedule.gapMinSeconds >= 0 and schedule.gapMaxSeconds >= schedule.gapMinSeconds) then
		problem("schedule gaps must be 0 or more, with gapMax >= gapMin")
	end
	if not (schedule.firstDelaySeconds >= 0) then
		problem("schedule.firstDelaySeconds must be 0 or more")
	end
	for _, key in ModifierRules.EFFECT_KEYS do
		local limit = config.limits[key]
		if limit == nil then
			problem(`limits.{key} is missing`)
		elseif not (limit.min > 0 and limit.min <= 1 and limit.max >= 1) then
			problem(`limits.{key} must include 1 and stay above 0`)
		end
	end
	return problems
end

return ModifierRules
