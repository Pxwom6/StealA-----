--!strict
local T = require("./TestKit")
local EconomyMath = require("../src/shared/Logic/EconomyMath")

local function inputs(overrides: { [string]: any }?): EconomyMath.MultiplierInputs
	local base: EconomyMath.MultiplierInputs = {
		rebirthMultiplier = 1,
		hasDoubleCash = false,
		doubleCashMultiplier = 2,
		isVip = false,
		vipIncomeBonus = 0.1,
		eventCashMultiplier = 1,
	}
	if overrides then
		for k, v in overrides do
			(base :: any)[k] = v
		end
	end
	return base
end

T.describe("EconomyMath.incomeMultiplier", function()
	T.it("is 1 for a fresh free player", function()
		T.expect(EconomyMath.incomeMultiplier(inputs())).toBe(1)
	end)
	T.it("stacks rebirth, 2x cash, VIP and events multiplicatively", function()
		T.expect(EconomyMath.incomeMultiplier(inputs({ rebirthMultiplier = 2 }))).toBe(2)
		T.expect(EconomyMath.incomeMultiplier(inputs({ hasDoubleCash = true }))).toBe(2)
		T.expect(EconomyMath.incomeMultiplier(inputs({ isVip = true }))).toBeNear(1.1)
		T.expect(EconomyMath.incomeMultiplier(inputs({
			rebirthMultiplier = 1.5,
			hasDoubleCash = true,
			isVip = true,
			eventCashMultiplier = 2,
		}))).toBeNear(1.5 * 2 * 1.1 * 2)
	end)
	T.it("ignores garbage multipliers instead of producing NaN", function()
		T.expect(EconomyMath.incomeMultiplier(inputs({ rebirthMultiplier = 0 / 0, eventCashMultiplier = math.huge })))
			.toBe(1)
		T.expect(EconomyMath.incomeMultiplier(inputs({ rebirthMultiplier = 0.2 }))).toBe(1)
	end)
end)

T.describe("EconomyMath income", function()
	T.it("sums creature incomes", function()
		T.expect(EconomyMath.totalIncome({ 1, 2, 3 }, 2)).toBe(12)
		T.expect(EconomyMath.totalIncome({}, 5)).toBe(0)
		T.expect(EconomyMath.creatureIncome(-5, 2)).toBe(0)
	end)
end)

T.describe("EconomyMath podiums", function()
	local cfg = { basePrice = 1000, growth = 3, maxPurchased = 3 }
	T.it("costs grow geometrically and stop at the cap", function()
		T.expect(EconomyMath.podiumUpgradeCost(0, cfg)).toBe(1000)
		T.expect(EconomyMath.podiumUpgradeCost(1, cfg)).toBe(3000)
		T.expect(EconomyMath.podiumUpgradeCost(2, cfg)).toBe(9000)
		T.expect(EconomyMath.podiumUpgradeCost(3, cfg)).toBeNil()
	end)
	T.it("capacity includes upgrades and pass bonus, clamped to the map maximum", function()
		T.expect(EconomyMath.podiumCapacity(8, 2, 0, 20)).toBe(10)
		T.expect(EconomyMath.podiumCapacity(8, 8, 4, 20)).toBe(20)
		T.expect(EconomyMath.podiumCapacity(8, 50, 4, 20)).toBe(20)
		T.expect(EconomyMath.podiumCapacity(8, -3, 0, 20)).toBe(8)
	end)
end)

T.describe("EconomyMath selling and cash packs", function()
	T.it("refunds a share of the price", function()
		T.expect(EconomyMath.sellValue(25, 0.5)).toBe(12)
		T.expect(EconomyMath.sellValue(100, 2)).toBe(100)
	end)
	T.it("rounds pack amounts to two significant digits, downward", function()
		T.expect(EconomyMath.roundNice(45237)).toBe(45000)
		T.expect(EconomyMath.roundNice(99)).toBe(99)
		T.expect(EconomyMath.roundNice(1999)).toBe(1900)
	end)
	T.it("scales with income but never drops below the minimum", function()
		local pack = { incomeSeconds = 3600, minimum = 15000 }
		T.expect(EconomyMath.cashPackAmount(0, pack)).toBe(15000)
		T.expect(EconomyMath.cashPackAmount(1, pack)).toBe(15000)
		T.expect(EconomyMath.cashPackAmount(100, pack)).toBe(360000)
		T.expect(EconomyMath.cashPackAmount(123, pack)).toBe(440000) -- 442,800 rounded down
		T.expect(EconomyMath.cashPackAmount(0 / 0, pack)).toBe(15000)
	end)
end)

return nil
