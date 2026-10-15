--!strict
-- The Auto Collect pass's timing rule (Logic/AutoCollectRules) and what it does to the Snack Magnet (GadgetRules).
local T = require("./TestKit")
local AutoCollectRules = require("../src/shared/Logic/AutoCollectRules")
local GadgetRules = require("../src/shared/Logic/GadgetRules")
local Gadgets = require("../src/shared/Config/Gadgets")
local Monetization = require("../src/shared/Config/Monetization")
local Theme = require("../src/shared/Config/Theme")

local INTERVAL = Monetization.perks.autoCollectSeconds

T.describe("AutoCollectRules timing", function()
	T.it("collects at the first check once the pass is on, then once per interval", function()
		T.expect(AutoCollectRules.due(nil, 100, INTERVAL)).toBe(true)
		T.expect(AutoCollectRules.due(100, 100, INTERVAL)).toBe(false)
		T.expect(AutoCollectRules.due(100, 100 + INTERVAL - 0.01, INTERVAL)).toBe(false)
		T.expect(AutoCollectRules.due(100, 100 + INTERVAL, INTERVAL)).toBe(true)
		T.expect(AutoCollectRules.due(100, 100 + 10 * INTERVAL, INTERVAL)).toBe(true)
	end)

	T.it("plays it out on a once-a-second check: one collect per interval, never two in a row", function()
		local lastAt: number? = nil
		local collects = 0
		for now = 0, 60 do
			if AutoCollectRules.due(lastAt, now, INTERVAL) then
				lastAt = now
				collects += 1
			end
		end
		-- 0, 5, 10, ... 60 with the 5 s interval
		T.expect(collects).toBe(math.floor(60 / INTERVAL) + 1)
	end)

	T.it("never leaves a player waiting on a broken clock", function()
		T.expect(AutoCollectRules.due(100, 50, INTERVAL)).toBe(true) -- went backwards
		T.expect(AutoCollectRules.due(0 / 0, 50, INTERVAL)).toBe(true)
		T.expect(AutoCollectRules.due(100, 0 / 0, INTERVAL)).toBe(true)
	end)

	T.it("says how long until the next one", function()
		T.expect(AutoCollectRules.remaining(nil, 10, INTERVAL)).toBe(0)
		T.expect(AutoCollectRules.remaining(10, 11, INTERVAL)).toBeNear(INTERVAL - 1, 1e-9)
		T.expect(AutoCollectRules.remaining(10, 10 + INTERVAL, INTERVAL)).toBe(0)
	end)

	T.it("keeps the configured interval 'every few seconds'", function()
		T.expect(#AutoCollectRules.validate(INTERVAL)).toBe(0)
		T.expect(INTERVAL).toBeAtLeast(AutoCollectRules.LIMITS.min)
		T.expect(INTERVAL).toBeAtMost(AutoCollectRules.LIMITS.max)
		T.expect(#AutoCollectRules.validate(1)).toBe(1)
		T.expect(#AutoCollectRules.validate(31)).toBe(1)
		T.expect(#AutoCollectRules.validate(0 / 0)).toBe(1)
		-- far more often than the Snack Magnet recharges: owning both would make the magnet pointless
		T.expect(INTERVAL).toBeLessThan(Gadgets.gadgets.magnet.cooldownSeconds)
	end)

	T.it("is a pass in the store, with its copy", function()
		T.expect(Monetization.passes.AutoCollect ~= nil).toBe(true)
		T.expect(table.find(Monetization.storePasses, "AutoCollect") ~= nil).toBe(true)
		T.expect(Theme.store.AutoCollect.name).toBe("Auto Collect")
	end)
end)

T.describe("Auto Collect and the Snack Magnet", function()
	local magnet = Gadgets.gadgets.magnet

	T.it("covers the magnet only, and only for pass owners", function()
		T.expect(GadgetRules.coveredByAutoCollect(magnet, true)).toBe(true)
		T.expect(GadgetRules.coveredByAutoCollect(magnet, false)).toBe(false)
		for id, def in Gadgets.gadgets do
			if def.kind ~= "magnet" then
				T.expect(GadgetRules.coveredByAutoCollect(def, true)).toBe(false)
				T.expect(id ~= "magnet").toBe(true)
			end
		end
	end)

	T.it("an owned magnet stays harmless: refused as 'auto', so its cooldown never starts", function()
		local ok, reason = GadgetRules.canUse({
			owned = true,
			inTutorial = false,
			alive = true,
			now = 10,
			readyAt = nil,
			covered = true,
		})
		T.expect(ok).toBe(false)
		T.expect(reason).toBe("auto")
		-- not owned still says so first
		local _, notOwned = GadgetRules.canUse({
			owned = false,
			inTutorial = false,
			alive = true,
			now = 10,
			covered = true,
		})
		T.expect(notOwned).toBe("notOwned")
		T.expect(GadgetRules.messageKey("auto")).toBe("magnetAuto")
		T.expect(type(Theme.text.magnetAuto)).toBe("string")
	end)

	T.it("isn't sold to pass owners for cash it would waste, but an owned one says owned", function()
		local function buy(owned: boolean, covered: boolean, cash: number): string?
			local _, reason = GadgetRules.canBuy({
				exists = true,
				owned = owned,
				cash = cash,
				price = magnet.price,
				covered = covered,
			})
			return reason
		end
		T.expect(buy(false, true, 1e12)).toBe("auto")
		T.expect(buy(false, true, 0)).toBe("auto") -- the more useful answer than "Not enough cash!"
		T.expect(buy(true, true, 1e12)).toBe("owned")
		T.expect(buy(false, false, 1e12)).toBeNil()
	end)
end)

return nil
