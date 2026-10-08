--!strict
local T = require("./TestKit")
local LiveOpsRules = require("../src/shared/Logic/LiveOpsRules")

local limits = { maxLuckMultiplier = 6, maxCashMultiplier = 3, maxBoostSeconds = 3600 }
local events: { LiveOpsRules.EventDef } = {
	{ id = "Weekend", startsAt = 100, endsAt = 200, luckMultiplier = 2 },
	{ id = "Cash", startsAt = 150, endsAt = 300, cashMultiplier = 2 },
}

T.describe("LiveOpsRules events", function()
	T.it("finds active events by time window (end exclusive)", function()
		T.expect(#LiveOpsRules.activeEvents(events, 99)).toBe(0)
		T.expect(#LiveOpsRules.activeEvents(events, 100)).toBe(1)
		T.expect(#LiveOpsRules.activeEvents(events, 160)).toBe(2)
		T.expect(LiveOpsRules.activeEventIds(events, 250)).toEqual({ Cash = true })
	end)
	T.it("combines luck from events and boosts, clamped", function()
		T.expect(LiveOpsRules.luckMultiplier(events, {}, 50, limits)).toBe(1)
		T.expect(LiveOpsRules.luckMultiplier(events, {}, 150, limits)).toBe(2)
		local boosts = { { multiplier = 2, endsAt = 500, source = "purchase" } }
		T.expect(LiveOpsRules.luckMultiplier(events, boosts, 150, limits)).toBe(4)
		T.expect(LiveOpsRules.luckMultiplier(events, boosts, 600, limits)).toBe(1)
		local many = {
			{ multiplier = 3, endsAt = 500, source = "admin" },
			{ multiplier = 3, endsAt = 500, source = "purchase" },
		}
		T.expect(LiveOpsRules.luckMultiplier(events, many, 150, limits)).toBe(6)
	end)
	T.it("combines cash multipliers", function()
		T.expect(LiveOpsRules.cashMultiplier(events, 250, limits)).toBe(2)
		T.expect(LiveOpsRules.cashMultiplier(events, 50, limits)).toBe(1)
	end)
end)

T.describe("LiveOpsRules boosts", function()
	T.it("buying again extends time instead of multiplying", function()
		local b1 = LiveOpsRules.extendBoost(nil, 0, 900, 2, "purchase", limits)
		T.expect(b1.endsAt).toBe(900)
		local b2 = LiveOpsRules.extendBoost(b1, 100, 900, 2, "purchase", limits)
		T.expect(b2.endsAt).toBe(1800)
		T.expect(b2.multiplier).toBe(2)
	end)
	T.it("caps remaining time", function()
		local boost: LiveOpsRules.Boost? = nil
		for _ = 1, 10 do
			boost = LiveOpsRules.extendBoost(boost, 0, 900, 2, "purchase", limits)
		end
		T.expect((boost :: LiveOpsRules.Boost).endsAt).toBe(3600)
	end)
	T.it("an expired boost restarts from now", function()
		local old = { multiplier = 2, endsAt = 50, source = "purchase" }
		T.expect(LiveOpsRules.extendBoost(old, 100, 900, 2, "purchase", limits).endsAt).toBe(1000)
	end)
	T.it("reports the strongest boost and prunes expired ones", function()
		local boosts = {
			{ multiplier = 2, endsAt = 100, source = "a" },
			{ multiplier = 3, endsAt = 50, source = "b" },
			{ multiplier = 2, endsAt = 200, source = "c" },
		}
		local m, remaining = LiveOpsRules.strongestBoost(boosts, 60)
		T.expect(m).toBe(2)
		T.expect(remaining).toBe(140)
		T.expect(#LiveOpsRules.pruneBoosts(boosts, 60)).toBe(2)
	end)
end)

T.describe("LiveOpsRules.validateEvents", function()
	T.it("keeps valid entries and clamps multipliers", function()
		local valid, problems = LiveOpsRules.validateEvents({
			{ id = "Ok", startsAt = 1, endsAt = 2, luckMultiplier = 100, bannerText = string.rep("x", 200) },
		}, limits)
		T.expect(#problems).toBe(0)
		T.expect(valid[1].luckMultiplier).toBe(6)
		T.expect(#(valid[1].bannerText :: string)).toBe(80)
	end)
	T.it("drops malformed entries", function()
		local garbage: any = {
			"nope" :: any,
			{ id = "", startsAt = 1, endsAt = 2 } :: any,
			{ id = "Backwards", startsAt = 5, endsAt = 2 } :: any,
			{ id = "NaN", startsAt = 0 / 0, endsAt = 2 } :: any,
		}
		local valid, problems = LiveOpsRules.validateEvents(garbage, limits)
		T.expect(#valid).toBe(0)
		T.expect(#problems).toBe(4)
		local _, notList = LiveOpsRules.validateEvents("hello", limits)
		T.expect(#notList).toBe(1)
	end)
end)

return nil
