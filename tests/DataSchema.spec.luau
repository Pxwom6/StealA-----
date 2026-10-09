--!strict
local T = require("./TestKit")
local DataSchema = require("../src/shared/Logic/DataSchema")

local rules: DataSchema.SanitiseRules = {
	isValidCreature = function(id: string): boolean
		return id == "pizza_pup" or id == "donut_dragon"
	end,
	maxPodiums = 20,
	maxPodiumUpgrades = 8,
	maxRebirths = 30,
	maxReceipts = 3,
	maxHistory = 2,
}

T.describe("DataSchema", function()
	T.it("template is valid and survives sanitise unchanged", function()
		local template = DataSchema.template(100)
		local clean, fixes = DataSchema.sanitise(table.clone(template) :: any, 100, rules)
		T.expect(#fixes).toBe(0)
		T.expect(clean).toEqual(template)
	end)

	T.it("migrates unversioned saves", function()
		local raw = DataSchema.migrate({ cash = 5 })
		T.expect(raw.version).toBe(DataSchema.VERSION)
	end)

	T.it("migrates version 1 saves: lock timers start empty, existing ones are kept", function()
		local v1 = DataSchema.migrate({ version = 1, cash = 5 })
		T.expect(v1.version).toBe(2)
		T.expect(v1.lockTimers).toEqual({ cooldownUntil = 0, vulnerableUntil = 0 })
		local clean = DataSchema.sanitise(v1, 100, rules)
		T.expect(clean.lockTimers).toEqual({ cooldownUntil = 0, vulnerableUntil = 0 })

		local saved: any = { version = 2, lockTimers = { cooldownUntil = 1700000090, vulnerableUntil = 1700000030 } }
		T.expect(DataSchema.sanitise(DataSchema.migrate(saved), 100, rules).lockTimers).toEqual({
			cooldownUntil = 1700000090,
			vulnerableUntil = 1700000030,
		})
		local bad: any = { lockTimers = { cooldownUntil = 0 / 0, vulnerableUntil = -5 } }
		T.expect(DataSchema.sanitise(bad, 100, rules).lockTimers).toEqual({ cooldownUntil = 0, vulnerableUntil = 0 })
	end)

	T.it("repairs garbage values", function()
		local garbage: any = {
			cash = 0 / 0,
			rebirths = 999,
			podiumUpgrades = -4,
			lockTokens = 2.7,
			rebirthMultiplier = "lots",
			stats = { steals = -1, playTime = math.huge },
			flags = { firstBuy = true, bogus = "yes" },
			daily = "nope",
		}
		local clean, fixes = DataSchema.sanitise(garbage, 100, rules)
		T.expect(clean.cash).toBe(100)
		T.expect(clean.rebirths).toBe(30)
		T.expect(clean.podiumUpgrades).toBe(0)
		T.expect(clean.lockTokens).toBe(2)
		T.expect(clean.rebirthMultiplier).toBe(1)
		T.expect(clean.stats.steals).toBe(0)
		T.expect(clean.stats.playTime).toBe(0)
		T.expect(clean.flags).toEqual({ firstBuy = true })
		T.expect(clean.daily).toEqual({ streak = 0, lastClaimDay = -1 })
		T.expect(#fixes).toBeGreaterThan(0)
	end)

	T.it("drops unknown creatures, duplicate podiums and fixes duplicate uids", function()
		local saved: any = {
			nextUid = 10,
			creatures = {
				{ uid = "1", id = "pizza_pup", podium = 1, acquiredAt = 5, stored = 12 },
				{ uid = "1", id = "donut_dragon", podium = 2, acquiredAt = 6, stored = -3 },
				{ uid = "3", id = "deleted_creature", podium = 3 } :: any,
				{ uid = "4", id = "pizza_pup", podium = 1 } :: any,
				{ uid = "5", id = "pizza_pup", podium = 99 } :: any,
				"garbage" :: any,
			},
		}
		local clean = DataSchema.sanitise(saved, 100, rules)
		T.expect(#clean.creatures).toBe(2)
		T.expect(clean.creatures[1].uid).toBe("1")
		T.expect(clean.creatures[1].stored).toBe(12)
		T.expect(clean.creatures[2].uid).toBe("10")
		T.expect(clean.creatures[2].stored).toBe(0)
		T.expect(clean.nextUid).toBe(11)
	end)

	T.it("bounds receipts and history", function()
		local saved: any = {
			processedReceipts = { "a", "b", "c", "d", 5 :: any },
			purchaseHistory = {
				{ purchaseId = "a", productId = 1, key = "CashSmall", robux = 10, at = 1 },
				{ purchaseId = "b", productId = 1, key = "CashSmall", robux = 10, at = 2 },
				{ purchaseId = "c", productId = 1, key = "CashSmall", robux = 10, at = 3 },
				{ nope = true } :: any,
			},
		}
		local clean = DataSchema.sanitise(saved, 100, rules)
		T.expect(clean.processedReceipts).toEqual({ "b", "c", "d" })
		T.expect(#clean.purchaseHistory).toBe(2)
		T.expect(clean.purchaseHistory[1].purchaseId).toBe("b")
	end)

	T.it("applies in place, keeping the table identity", function()
		local live: { [string]: any } = { cash = 5, junk = true }
		local clean = DataSchema.sanitise(live, 100, rules)
		T.expect(DataSchema.applyInPlace(live, clean)).toBe(true)
		T.expect(live.junk).toBeNil()
		T.expect(live.cash).toBe(5)
		T.expect(live.version).toBe(DataSchema.VERSION)
	end)

	T.it("detects saves written by a newer release", function()
		T.expect(DataSchema.isFromNewerVersion({ version = DataSchema.VERSION + 1 })).toBe(true)
		T.expect(DataSchema.isFromNewerVersion({ version = DataSchema.VERSION })).toBe(false)
		T.expect(DataSchema.isFromNewerVersion({ version = 1 })).toBe(false)
		T.expect(DataSchema.isFromNewerVersion({})).toBe(false)
		T.expect(DataSchema.isFromNewerVersion({ version = 0 / 0 })).toBe(false)
	end)

	T.it("never strips unknown fields from (or downgrades) a save written by a newer release", function()
		local newer: { [string]: any } = {
			version = DataSchema.VERSION + 1,
			cash = 5,
			pets = { { id = "future_pet" } },
			settings = { music = false },
		}
		local snapshot = table.clone(newer)
		DataSchema.migrate(newer)
		T.expect(newer).toEqual(snapshot)
		local clean = DataSchema.sanitise(table.clone(newer), 100, rules)
		T.expect(DataSchema.applyInPlace(newer, clean)).toBe(false)
		T.expect(newer).toEqual(snapshot)
		T.expect(newer.version).toBe(DataSchema.VERSION + 1)
		T.expect(newer.pets).toEqual({ { id = "future_pet" } })
	end)
end)

return nil
