--!strict
local T = require("./TestKit")
local ModifierRules = require("../src/shared/Logic/ModifierRules")
local MutationRules = require("../src/shared/Logic/MutationRules")
local Modifiers = require("../src/shared/Config/Modifiers")
local Mutations = require("../src/shared/Config/Mutations")
local Types = require("../src/shared/Types")

-- The most mutation chance that can be live while a modifier runs (only one modifier runs at a time).
local function mutationTotal(modifierId: string): number
	return MutationRules.worstCaseTotal(Mutations, modifierId)
end

-- The modifiers a mutation waits for (Config/Mutations modifierId).
local function unlocks(): { [string]: boolean }
	local set: { [string]: boolean } = {}
	for _, mutation in Mutations do
		if mutation.modifierId then
			set[mutation.modifierId] = true
		end
	end
	return set
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
		local problems = ModifierRules.validate(Modifiers, mutationTotal, unlocks())
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

T.describe("ModifierRules.lenient (just after a modifier starts or ends)", function()
	local none = ModifierRules.none()
	local grace = Modifiers.schedule.changeGraceSeconds
	local function at(current: any, previous: any, secondsAfter: number): ModifierRules.Effects
		return ModifierRules.lenient(current, previous, 100, 100 + secondsAfter, grace)
	end

	T.it("lasts about a second and a half", function()
		T.expect(grace).toBeAtLeast(1)
		T.expect(grace).toBeAtMost(2)
	end)

	T.it("charges the sale price for a moment after Clearance Sale ends, then the full price", function()
		local sale = ModifierRules.effects(Modifiers, "clearanceSale")
		T.expect(ModifierRules.beltPrice(1000, at(none, sale, 0.3))).toBe(700) -- the client still showed $700
		T.expect(ModifierRules.beltPrice(1000, at(none, sale, grace))).toBe(1000)
		T.expect(ModifierRules.beltPrice(1000, at(sale, none, 0.3))).toBe(700) -- a sale starting: the lower price at once
	end)

	T.it("accepts a Quick Hands hold that finishes just after it ends", function()
		local quick = ModifierRules.effects(Modifiers, "quickHands")
		T.expect(at(none, quick, 0.5).stealHold).toBe(quick.stealHold)
		T.expect(at(none, quick, grace + 0.01).stealHold).toBe(1)
		T.expect(at(quick, none, 0.5).stealHold).toBe(quick.stealHold)
	end)

	T.it("keeps Snack Patrol's tag reach for a moment after it ends", function()
		local patrol = ModifierRules.effects(Modifiers, "snackPatrol")
		T.expect(patrol.tagRange).toBeGreaterThan(1)
		T.expect(at(none, patrol, 1).tagRange).toBe(patrol.tagRange)
		T.expect(at(none, patrol, grace).tagRange).toBe(1)
	end)

	T.it("changes nothing else, and nothing at all without a change", function()
		local rush = ModifierRules.effects(Modifiers, "rushHour")
		T.expect(at(none, rush, 0.2).spawnInterval).toBe(1) -- the belt, income and the rest follow the server at once
		T.expect(ModifierRules.lenient(rush, none, -math.huge, 100, grace)).toEqual(rush)
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
		return ModifierRules.validate(config :: Types.ModifiersConfig, mutationTotal, unlocks())
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

	T.it("lets a weather modifier change only the sky when it unlocks a mutation", function()
		T.expect(#ModifierRules.validate(Modifiers, mutationTotal, unlocks())).toBe(0)
		-- without its mutation, a storm changes nothing
		T.expect(mentions(ModifierRules.validate(Modifiers, mutationTotal, {}), "thunderstorm changes nothing"))
			.toBeTruthy()
	end)

	T.it("lets a drop modifier change nothing but what it drops", function()
		T.expect(mentions(ModifierRules.validate(Modifiers, mutationTotal, unlocks()), "supplyDrop")).toBe(false)
		T.expect(mentions(
			broken(function(config)
				config.modifiers.coinRain.drops = nil
			end),
			"coinRain changes nothing"
		)).toBeTruthy()
		T.expect(mentions(
			broken(function(config)
				config.modifiers.supplyDrop.drops.kind = "pinata"
			end),
			"drops.kind"
		)).toBeTruthy()
	end)

	T.it("checks the weather, the sky effect and the lighting", function()
		T.expect(mentions(
			broken(function(config)
				config.modifiers.thunderstorm.weather = "hail"
			end),
			"weather hail"
		)).toBeTruthy()
		T.expect(mentions(
			broken(function(config)
				config.modifiers.meteorShower.skyEffect = "rainbowArc"
			end),
			"skyEffect rainbowArc"
		)).toBeTruthy()
		T.expect(mentions(
			broken(function(config)
				config.modifiers.toxicFog.lighting.atmosphere.density = 2
			end),
			"atmosphere.density"
		)).toBeTruthy()
		T.expect(mentions(
			broken(function(config)
				config.modifiers.thunderstorm.lighting.clouds.color = "grey"
			end),
			"clouds.color"
		)).toBeTruthy()
	end)

	T.it("refuses making mutations too common", function()
		local problems = ModifierRules.validate(Modifiers, constant(0.2)) -- 0.2 x Golden Hour's 3 = 0.6
		T.expect(mentions(problems, "too common")).toBeTruthy()
	end)

	T.it("counts only the mutations that can roll while the multiplying modifier itself runs", function()
		-- one modifier at a time: during Golden Hour no weather mutation can roll, so it multiplies everything
		-- permanent, every event's (only an admin's /event could run them all at once) and the strongest map's
		local goldenHour = MutationRules.worstCaseTotal(Mutations, "goldenHour")
		T.expect(goldenHour).toBeLessThan(MutationRules.worstCaseTotal(Mutations))
		T.expect(goldenHour * ModifierRules.effects(Modifiers, "goldenHour").mutationChance).toBeLessThan(0.5)
		T.expect(MutationRules.worstCaseTotal(Mutations, "thunderstorm"))
			.toBeNear(MutationRules.worstCaseTotal(Mutations))
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
