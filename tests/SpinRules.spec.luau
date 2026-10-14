--!strict
local T = require("./TestKit")
local Catalog = require("../src/shared/Logic/Catalog")
local Creatures = require("../src/shared/Config/Creatures")
local Mutations = require("../src/shared/Config/Mutations")
local Rarities = require("../src/shared/Config/Rarities")
local Spin = require("../src/shared/Config/Spin")
local SpinRules = require("../src/shared/Logic/SpinRules")
local Types = require("../src/shared/Types")

local catalog = Catalog.build(Creatures, Rarities, Mutations)

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

local function constant(value: number): () -> number
	return function(): number
		return value
	end
end

T.describe("SpinRules: the real config", function()
	T.it("is valid", function()
		local problems = SpinRules.validate(Spin, catalog.mutations)
		if #problems > 0 then
			print(table.concat(problems, "\n"))
		end
		T.expect(#problems).toBe(0)
	end)

	T.it("has odds that add up to 1, the jackpot the rarest", function()
		local chances = SpinRules.chances(Spin.segments)
		local total, rarest, rarestIndex = 0, 1, 0
		for index, chance in chances do
			total += chance
			if chance < rarest then
				rarest, rarestIndex = chance, index
			end
		end
		T.expect(total).toBeNear(1, 1e-9)
		T.expect(Spin.segments[rarestIndex].id).toBe("jackpot")
	end)
end)

T.describe("SpinRules spins", function()
	T.it("uses the free spin first, then banked ones", function()
		local state: Types.SpinState = { nextFreeAt = 0, spins = 2, total = 0 }
		T.expect(SpinRules.source(state, 1000)).toBe("free")
		SpinRules.consume(state, "free", 1000, Spin)
		T.expect(state.nextFreeAt).toBe(1000 + Spin.freeEverySeconds)
		T.expect(SpinRules.source(state, 1001)).toBe("banked")
		SpinRules.consume(state, "banked", 1001, Spin)
		SpinRules.consume(state, "banked", 1002, Spin)
		T.expect(state.spins).toBe(0)
		T.expect(SpinRules.source(state, 1003)).toBeNil()
		T.expect(SpinRules.source(state, 1000 + Spin.freeEverySeconds)).toBe("free")
		T.expect(state.total).toBe(3)
	end)

	T.it("banks spins up to the limit and hands back the rest", function()
		local state: Types.SpinState = { nextFreeAt = 0, spins = Spin.maxBanked - 1, total = 0 }
		T.expect(SpinRules.bank(state, 3, Spin)).toBe(2)
		T.expect(state.spins).toBe(Spin.maxBanked)
		T.expect(SpinRules.bank(state, 1, Spin)).toBe(1)
	end)

	T.it("picks prizes by weight", function()
		local segments = Spin.segments
		T.expect(SpinRules.pick(segments, constant(0))).toBe(1)
		T.expect(SpinRules.pick(segments, constant(0.9999999))).toBe(#segments)
		local random = T.seededRandom(9)
		local counts: { number } = {}
		local draws = 20000
		for _ = 1, draws do
			local index = SpinRules.pick(segments, random)
			counts[index] = (counts[index] or 0) + 1
		end
		for index, chance in SpinRules.chances(segments) do
			T.expect((counts[index] or 0) / draws).toBeNear(chance, 0.02)
		end
	end)
end)

T.describe("SpinRules.validate", function()
	local function broken(edit: (config: any) -> ()): number
		local config = copy(Spin)
		edit(config)
		return #SpinRules.validate(config :: Types.SpinConfig, catalog.mutations)
	end

	T.it("refuses spins as a spin prize, bad weights and repeated ids", function()
		T.expect(broken(function(config)
			config.segments[1].reward = { kind = "spin", count = 1 }
		end)).toBe(1)
		T.expect(broken(function(config)
			config.segments[2].weight = 0
		end)).toBe(1)
		T.expect(broken(function(config)
			config.segments[3].id = config.segments[1].id
		end)).toBe(1)
		T.expect(broken(function(config)
			config.segments[1].color = "green"
		end)).toBe(1)
		T.expect(broken(function(config)
			config.freeEverySeconds = 60
		end)).toBe(1)
	end)
end)

return nil
