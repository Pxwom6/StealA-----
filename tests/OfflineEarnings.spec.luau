--!strict
local T = require("./TestKit")
local OfflineEarnings = require("../src/shared/Logic/OfflineEarnings")

local cfg = { rate = 0.5, capSeconds = 7200, minSecondsAway = 120 }

T.describe("OfflineEarnings", function()
	T.it("pays a reduced rate for time away", function()
		local r = OfflineEarnings.compute(1000, 1000 + 600, 10, cfg)
		T.expect(r.secondsAway).toBe(600)
		T.expect(r.paidSeconds).toBe(600)
		T.expect(r.amount).toBe(3000)
	end)
	T.it("caps the paid time, with an optional bonus", function()
		local r = OfflineEarnings.compute(1000, 1000 + 86400, 10, cfg)
		T.expect(r.paidSeconds).toBe(7200)
		T.expect(r.amount).toBe(36000)
		local vip = OfflineEarnings.compute(1000, 1000 + 86400, 10, cfg, 3600)
		T.expect(vip.paidSeconds).toBe(10800)
	end)
	T.it("pays nothing for short breaks, first joins, clock skew or bad income", function()
		T.expect(OfflineEarnings.compute(1000, 1060, 10, cfg).amount).toBe(0)
		T.expect(OfflineEarnings.compute(0, 5000, 10, cfg).amount).toBe(0)
		T.expect(OfflineEarnings.compute(9000, 5000, 10, cfg).amount).toBe(0)
		T.expect(OfflineEarnings.compute(1000, 9000, 0 / 0, cfg).amount).toBe(0)
		T.expect(OfflineEarnings.compute(1000, 9000, math.huge, cfg).amount).toBe(0)
		T.expect(OfflineEarnings.compute(0 / 0, 9000, 10, cfg).amount).toBe(0)
	end)
end)

return nil
