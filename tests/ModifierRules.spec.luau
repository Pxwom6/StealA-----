--!strict
local T = require("./TestKit")
local ModifierRules = require("../src/shared/Logic/ModifierRules")
local Modifiers = require("../src/shared/Config/Modifiers")
local Mutations = require("../src/shared/Config/Mutations")
local Types = require("../src/shared/Types")

local function mutationTotal(): number
	local total = 0
	for _, mutation in Mutations do
		total += mutation.chance
	end
	return total
end

local function copy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, item in value do
		result[key] = copy(item)
	end
	return result
end

local function mentions(problems: { string }, text: string): boolean
	for _, problem in problems do
		if string.find(problem, text, 1, true) then
			return true
		end
	end
	return false
end

local function constant(value: number): () -> number
	return function(): number
		return value
	end
end

T.describe("ModifierRules: the real config", function()
	T.it("is valid", function()
		local problems = ModifierRules.validate(Modifiers, mutationTotal())
		T.expect(#problems).toBe(0)
		if #problems > 0 then
			print(table.concat(problems, "\n"))
		end
	end)

	T.it("keeps every effect inside its limits", function()
		for _, id in Modifiers.order do
			local effects = ModifierRules.effects(Modifiers, id)
			for _, key in ModifierRules.EFFECT_KEYS do
				local value = (effects :: any)[key]
				local limit = Modifiers.limits[key]
				T.expect(value).toBeAtLeast(limit.min)
				T.expect(value).toBeAtMost(limit.max)
			end
		end
	end)

	T.it("never runs anything stronger than the movement checks allow", function()
		T.expect(ModifierRules.maxWalkSpeed(Modifiers)).toBeAtMost(Modifiers.limits.walkSpeed.max)
	end)
end)

T.describe("ModifierRules.effects", function()
	T.it("changes nothing without a modifier, or for an unknown id", function()
		T.expect(ModifierRules.effects(Modifiers, nil)).toEqual(ModifierRules.none())
		T.expect(ModifierRules.effects(Modifiers, "notAModifier")).toEqual(ModifierRules.none())
	end)

	T.it("reads a modifier's effects and leaves the rest at 1", function()
		local effects = ModifierRules.effects(Modifiers, "snackParty")
		T.expect(effects.spawnInterval).toBe(0.67)
		T.expect(effects.luck).toBe(2)
		T.expect(effects.beltPrice).toBe(1)
		T.expect(effects.walkSpeed).toBe(1)
	end)
end)

T.describe("ModifierRules prices and the belt", function()
	local sale = ModifierRules.effects(Modifiers, "clearanceSale")

	T.it("leaves prices alone without a sale", function()
		T.expect(ModifierRules.beltPrice(1234, ModifierRules.none())).toBe(1234)
	end)

	T.it("discounts to a whole number, never below 1", function()
		T.expect(ModifierRules.beltPrice(1000, sale)).toBe(700)
		T.expect(ModifierRules.beltPrice(15, sale)).toBe(11) -- 10.5 rounds up
		T.expect(ModifierRules.beltPrice(1, sale)).toBe(1)
	end)

	T.it("lets a faster belt hold more", function()
		T.expect(ModifierRules.beltCapacity(16, ModifierRules.none())).toBe(16)
		T.expect(ModifierRules.beltCapacity(16, ModifierRules.effects(Modifiers, "rushHour"))).toBe(32)
		local slower = ModifierRules.none()
		slower.spawnInterval = 1.5
		T.expect(ModifierRules.beltCapacity(16, slower)).toBe(16)
	end)
end)

T.describe("ModifierRules.pick", function()
	T.it("never repeats the last modifier", function()
		for _, last in Modifiers.order do
			for _, roll in { 0, 0.2, 0.5, 0.8, 0.9999 } do
				local id = ModifierRules.pick(Modifiers, last, constant(roll))
				T.expect(id ~= nil and id ~= last).toBeTruthy()
			end
		end
	end)

	T.it("goes by weight", function()
		local config = copy(Modifiers)
		for _, id in config.order do
			config.modifiers[id].weight = 0
		end
		config.modifiers.fortress.weight = 1
		config.modifiers.rushHour.weight = 3
		-- rushHour comes first in the order: rolls under 3/4 of the total pick it.
		T.expect(ModifierRules.pick(config, nil, constant(0.7))).toBe("rushHour")
		T.expect(ModifierRules.pick(config, nil, constant(0.8))).toBe("fortress")
	end)

	T.it("repeats the only pickable modifier rather than none", function()
		local config = copy(Modifiers)
		for _, id in config.order do
			config.modifiers[id].weight = 0
		end
		config.modifiers.fortress.weight = 1
		T.expect(ModifierRules.pick(config, "fortress", constant(0.5))).toBe("fortress")
		config.modifiers.fortress.weight = 0
		T.expect(ModifierRules.pick(config, nil, constant(0.5))).toBeNil()
	end)

	T.it("waits a random gap between modifiers", function()
		local schedule = Modifiers.schedule
		T.expect(ModifierRules.gap(schedule, constant(0))).toBe(schedule.gapMinSeconds)
		T.expect(ModifierRules.gap(schedule, constant(0.5))).toBe((schedule.gapMinSeconds + schedule.gapMaxSeconds) / 2)
	end)
end)

T.describe("ModifierRules.validate", function()
	local function broken(edit: (config: any) -> ()): { string }
		local config = copy(Modifiers)
		edit(config)
		return ModifierRules.validate(config :: Types.ModifiersConfig, mutationTotal())
	end

	T.it("refuses effects outside their limits", function()
		T.expect(mentions(
			broken(function(config)
				config.modifiers.sugarRush.effects.walkSpeed = 2
			end),
			"walkSpeed must be between"
		)).toBeTruthy()
		T.expect(mentions(
			broken(function(config)
				config.modifiers.clearanceSale.effects.beltPrice = 0.1
			end),
			"beltPrice must be between"
		)).toBeTruthy()
	end)

	T.it("refuses unknown effects and modifiers that change nothing", function()
		T.expect(mentions(
			broken(function(config)
				config.modifiers.fortress.effects.gravity = 0.5
			end),
			"unknown effect gravity"
		)).toBeTruthy()
		T.expect(mentions(
			broken(function(config)
				config.modifiers.fortress.effects = { lockDuration = 1 }
			end),
			"changes nothing"
		)).toBeTruthy()
	end)

	T.it("refuses making mutations too common", function()
		local problems = ModifierRules.validate(Modifiers, 0.2) -- 0.2 x Golden Hour's 3 = 0.6
		T.expect(mentions(problems, "too common")).toBeTruthy()
	end)

	T.it("checks the order, the text and the schedule", function()
		T.expect(mentions(
			broken(function(config)
				table.remove(config.order, 1)
			end),
			"missing from order"
		)).toBeTruthy()
		T.expect(mentions(
			broken(function(config)
				config.modifiers.rushHour.color = "yellow"
			end),
			"color must be"
		)).toBeTruthy()
		T.expect(mentions(
			broken(function(config)
				config.schedule.gapMaxSeconds = config.schedule.gapMinSeconds - 1
			end),
			"gaps"
		)).toBeTruthy()
		T.expect(mentions(
			broken(function(config)
				config.limits.luck = { min = 1.5, max = 3 }
			end),
			"limits.luck"
		)).toBeTruthy()
	end)
end)

return nil
