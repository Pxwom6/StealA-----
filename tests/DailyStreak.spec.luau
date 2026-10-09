--!strict
local T = require("./TestKit")
local DailyStreak = require("../src/shared/Logic/DailyStreak")

local DAY = 86400

T.describe("DailyStreak", function()
	T.it("first claim starts a streak of 1", function()
		local state = DailyStreak.claim({ streak = 0, lastClaimDay = -1 }, 10 * DAY + 5)
		T.expect(state).toEqual({ streak = 1, lastClaimDay = 10 })
	end)
	T.it("only one claim per UTC day", function()
		local state = { streak = 1, lastClaimDay = 10 }
		T.expect(DailyStreak.claim(state, 10 * DAY + 80000)).toBeNil()
		local status = DailyStreak.status(state, 10 * DAY + 80000)
		T.expect(status.canClaim).toBe(false)
		T.expect(status.secondsUntilNext).toBe(DAY - 80000)
	end)
	T.it("consecutive days grow the streak", function()
		local state = { streak = 3, lastClaimDay = 10 }
		T.expect(DailyStreak.claim(state, 11 * DAY + 1)).toEqual({ streak = 4, lastClaimDay = 11 })
	end)
	T.it("missing a day resets to 1", function()
		local state = { streak = 6, lastClaimDay = 10 }
		T.expect(DailyStreak.claim(state, 12 * DAY + 1)).toEqual({ streak = 1, lastClaimDay = 12 })
	end)
	T.it("a saved day in the future (clock skew) never pays out", function()
		T.expect(DailyStreak.claim({ streak = 2, lastClaimDay = 50 }, 10 * DAY)).toBeNil()
	end)
	T.it("reward slots cycle", function()
		T.expect(DailyStreak.slot(1, 7)).toBe(1)
		T.expect(DailyStreak.slot(7, 7)).toBe(7)
		T.expect(DailyStreak.slot(8, 7)).toBe(1)
		T.expect(DailyStreak.slot(0, 7)).toBe(1)
	end)
	T.it("reward scales with income above the minimum", function()
		local slot = { minimum = 500, incomeMinutes = 5 }
		T.expect(DailyStreak.rewardAmount(slot, 0)).toBe(500)
		T.expect(DailyStreak.rewardAmount(slot, 10)).toBe(3000)
		T.expect(DailyStreak.rewardAmount(slot, 0 / 0)).toBe(500)
	end)
end)

return nil
