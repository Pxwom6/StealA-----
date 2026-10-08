--!strict
local T = require("./TestKit")
local RebirthMath = require("../src/shared/Logic/RebirthMath")

local cfg = {
	baseCost = 1000000,
	costGrowth = 5,
	multiplierPerRebirth = 0.5,
	lockBonusPerRebirth = 5,
	maxLockBonus = 12,
	maxRebirths = 3,
}

T.describe("RebirthMath", function()
	T.it("cost grows per rebirth and stops at the cap", function()
		T.expect(RebirthMath.cost(0, cfg)).toBe(1000000)
		T.expect(RebirthMath.cost(1, cfg)).toBe(5000000)
		T.expect(RebirthMath.cost(2, cfg)).toBe(25000000)
		T.expect(RebirthMath.cost(3, cfg)).toBeNil()
	end)
	T.it("multiplier and lock bonus grow linearly (lock bonus capped)", function()
		T.expect(RebirthMath.multiplierFor(0, cfg)).toBe(1)
		T.expect(RebirthMath.multiplierFor(2, cfg)).toBe(2)
		T.expect(RebirthMath.lockBonusFor(1, cfg)).toBe(5)
		T.expect(RebirthMath.lockBonusFor(3, cfg)).toBe(12)
	end)
	T.it("requires enough cash and respects the cap", function()
		T.expect((RebirthMath.canRebirth(999999, 0, cfg))).toBe(false)
		local ok, reason = RebirthMath.canRebirth(999999, 0, cfg)
		T.expect(ok).toBe(false)
		T.expect(reason).toBe("cash")
		T.expect((RebirthMath.canRebirth(1000000, 0, cfg))).toBe(true)
		local okMax, reasonMax = RebirthMath.canRebirth(1e300, 3, cfg)
		T.expect(okMax).toBe(false)
		T.expect(reasonMax).toBe("max")
	end)
	T.it("previews exactly what is lost and gained", function()
		local preview = RebirthMath.preview({
			cash = 2000000,
			rebirths = 1,
			rebirthMultiplier = 1.5,
			creatureCount = 8,
			incomePerSecond = 5000,
			baseLockSeconds = 60,
		}, cfg)
		T.expect(preview.canRebirth).toBe(false)
		T.expect(preview.reason).toBe("cash")
		T.expect(preview.cost).toBe(5000000)
		T.expect(preview.loseCash).toBe(2000000)
		T.expect(preview.loseCreatures).toBe(8)
		T.expect(preview.loseIncomePerSecond).toBe(5000)
		T.expect(preview.multiplierFrom).toBe(1.5)
		T.expect(preview.multiplierTo).toBe(2)
		T.expect(preview.lockFrom).toBe(65)
		T.expect(preview.lockTo).toBe(70)
	end)
	T.it("never lowers a stored multiplier (balance changes are not retroactive)", function()
		local preview = RebirthMath.preview({
			cash = 0,
			rebirths = 1,
			rebirthMultiplier = 3,
			creatureCount = 0,
			incomePerSecond = 0,
			baseLockSeconds = 60,
		}, cfg)
		T.expect(preview.multiplierTo).toBe(3)
	end)
end)

return nil
