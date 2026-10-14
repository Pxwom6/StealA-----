--!strict
local T = require("./TestKit")
local DropRules = require("../src/shared/Logic/DropRules")
local Drops = require("../src/shared/Config/Drops")
local Gameplay = require("../src/shared/Config/Gameplay")
local Modifiers = require("../src/shared/Config/Modifiers")
local Types = require("../src/shared/Types")

local WALKWAY = {
	maxX = Gameplay.belt.length / 2,
	maxZ = Gameplay.map.walkwayWidth,
	beltHalfWidth = Gameplay.belt.width / 2,
}

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

local function sequence(values: { number }): () -> number
	local index = 0
	return function(): number
		index += 1
		return values[(index - 1) % #values + 1]
	end
end

T.describe("DropRules: the real config", function()
	T.it("is valid", function()
		local problems = DropRules.validate(Drops, WALKWAY)
		if #problems > 0 then
			print(table.concat(problems, "\n"))
		end
		T.expect(#problems).toBe(0)
	end)

	T.it("gives Supply Drop a few crates and Coin Rain several showers", function()
		local duration = Modifiers.schedule.durationSeconds
		T.expect(#DropRules.times(Modifiers.modifiers.supplyDrop.drops :: Types.ModifierDrops, duration)).toBe(4)
		T.expect(#DropRules.times(Modifiers.modifiers.coinRain.drops :: Types.ModifierDrops, duration)).toBe(8)
	end)
end)

T.describe("DropRules.position", function()
	T.it("lands inside the area, on either walkway", function()
		local area = Drops.area
		local x, z = DropRules.position(area, sequence({ 0, 0, 0.9 }))
		T.expect(x).toBe(area.minX)
		T.expect(z).toBe(area.minZ)
		x, z = DropRules.position(area, sequence({ 0.5, 0.5, 0.1 }))
		T.expect(x).toBe((area.minX + area.maxX) / 2)
		T.expect(z).toBe(-(area.minZ + area.maxZ) / 2)
	end)

	T.it("never lands on the belt or in a base", function()
		local random = T.seededRandom(3)
		for _ = 1, 2000 do
			local x, z = DropRules.position(Drops.area, random)
			T.expect(math.abs(x)).toBeAtMost(WALKWAY.maxX)
			T.expect(math.abs(z)).toBeGreaterThan(WALKWAY.beltHalfWidth + 2)
			T.expect(math.abs(z)).toBeLessThan(WALKWAY.maxZ - 2)
		end
	end)
end)

T.describe("DropRules timing and rewards", function()
	T.it("drops from the first time, then every so often, until the modifier ends", function()
		local drops: Types.ModifierDrops = { kind = "crate", firstSeconds = 10, everySeconds = 75 }
		T.expect(DropRules.times(drops, 300)).toEqual({ 10, 85, 160, 235 })
		T.expect(DropRules.times(drops, 10)).toEqual({})
		T.expect(DropRules.times({ kind = "coins", firstSeconds = 0, everySeconds = 0 }, 300)).toEqual({})
	end)

	T.it("pays a few seconds of income, never less than the minimum", function()
		local reward = { incomeSeconds = 3, minimum = 30 }
		T.expect(DropRules.amount(reward, 0)).toBe(30)
		T.expect(DropRules.amount(reward, 5)).toBe(30)
		T.expect(DropRules.amount(reward, 1000)).toBe(3000)
	end)

	T.it("opens a crate only after a long enough hold", function()
		local hold = Drops.crate.holdSeconds * Drops.crate.holdTolerance
		T.expect(DropRules.holdLongEnough(Drops, nil, 100)).toBe(false)
		T.expect(DropRules.holdLongEnough(Drops, 100, 100 + hold - 0.01)).toBe(false)
		T.expect(DropRules.holdLongEnough(Drops, 100, 100 + hold)).toBe(true)
	end)

	T.it("picks up a coin only when you walk through it", function()
		local range = Drops.coins.pickupRange
		T.expect(DropRules.inPickupRange(Drops, range, 0)).toBe(true)
		T.expect(DropRules.inPickupRange(Drops, range + 0.1, 0)).toBe(false)
		T.expect(DropRules.inPickupRange(Drops, 0, 30)).toBe(false)
	end)
end)

T.describe("DropRules.validate", function()
	local function broken(edit: (config: any) -> ()): number
		local config = copy(Drops)
		edit(config)
		return #DropRules.validate(config :: Types.DropsConfig, WALKWAY)
	end

	T.it("keeps drops on the walkways", function()
		T.expect(broken(function(config)
			config.area.minZ = 2 -- on the belt
		end)).toBeAtLeast(1)
		T.expect(broken(function(config)
			config.area.maxZ = 40 -- inside the bases
		end)).toBeAtLeast(1)
		T.expect(broken(function(config)
			config.area.maxX = 500
		end)).toBeAtLeast(1)
	end)

	T.it("refuses broken crates and coins", function()
		T.expect(broken(function(config)
			config.crate.holdTolerance = 2
		end)).toBe(1)
		T.expect(broken(function(config)
			config.crate.luck = 50
		end)).toBe(1)
		T.expect(broken(function(config)
			config.coins.perWave = 0
		end)).toBe(1)
		T.expect(broken(function(config)
			config.coins.value.incomeSeconds = -1
		end)).toBe(1)
	end)

	T.it("checks a modifier's drops", function()
		T.expect(#DropRules.dropsProblems({ kind = "crate", firstSeconds = 10, everySeconds = 75 }, 300, "x")).toBe(0)
		T.expect(#DropRules.dropsProblems({ kind = "pinata" :: any, firstSeconds = 10, everySeconds = 75 }, 300, "x"))
			.toBe(1)
		T.expect(#DropRules.dropsProblems({ kind = "coins", firstSeconds = 400, everySeconds = 75 }, 300, "x")).toBe(1)
		T.expect(#DropRules.dropsProblems({ kind = "coins", firstSeconds = 0, everySeconds = 1 }, 300, "x")).toBe(1)
	end)
end)

return nil
