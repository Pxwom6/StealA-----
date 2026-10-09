--!strict
local T = require("./TestKit")
local LiveOpsRules = require("../src/shared/Logic/LiveOpsRules")
local Catalog = require("../src/shared/Logic/Catalog")
local RarityRoll = require("../src/shared/Logic/RarityRoll")
local Creatures = require("../src/shared/Config/Creatures")
local Rarities = require("../src/shared/Config/Rarities")
local LiveOps = require("../src/shared/Config/LiveOps")
local Monetization = require("../src/shared/Config/Monetization")

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

T.describe("LiveOpsRules Server Luck preview", function()
	local catalog = Catalog.build(Creatures, Rarities)
	local perks = Monetization.perks
	local realLimits = LiveOps.limits
	-- What the server does on a receipt: purchases are uncapped (a receipt always adds its full time).
	local receiptLimits = table.clone(realLimits)
	receiptLimits.maxBoostSeconds = math.huge

	local luckEvent: LiveOpsRules.EventDef = { id = "Luck", startsAt = 0, endsAt = 10000, luckMultiplier = 2 }
	local strongEvent: LiveOpsRules.EventDef = { id = "Strong", startsAt = 0, endsAt = 10000, luckMultiplier = 4 }
	local scenarios: { { name: string, events: { LiveOpsRules.EventDef }, boosts: { LiveOpsRules.Boost } } } = {
		{ name = "nothing running", events = {}, boosts = {} },
		{ name = "luck event", events = { luckEvent }, boosts = {} },
		{ name = "admin boost", events = {}, boosts = { { multiplier = 3, endsAt = 5000, source = "admin" } } },
		{
			name = "purchase running",
			events = {},
			boosts = { { multiplier = perks.serverLuckMultiplier, endsAt = 1500, source = "purchase" } },
		},
		{
			name = "purchase running + event + admin",
			events = { luckEvent },
			boosts = {
				{ multiplier = 1.5, endsAt = 5000, source = "admin" },
				{ multiplier = perks.serverLuckMultiplier, endsAt = 1500, source = "purchase" },
			},
		},
		{
			name = "purchase expired",
			events = {},
			boosts = { { multiplier = perks.serverLuckMultiplier, endsAt = 900, source = "purchase" } },
		},
		{ name = "already at the luck cap", events = { strongEvent, luckEvent }, boosts = {} },
		{
			name = "just under the cap",
			events = { strongEvent },
			boosts = { { multiplier = 1.25, endsAt = 5000, source = "admin" } },
		},
	}

	T.it("the store's odds preview equals the odds the server applies, exactly", function()
		local now = 1000
		for _, scenario in scenarios do
			-- Server: apply the purchase, then roll with the new luck.
			local applied = LiveOpsRules.addBoost(
				scenario.boosts,
				now,
				perks.serverLuckSeconds,
				perks.serverLuckMultiplier,
				"purchase",
				receiptLimits
			)
			local serverLuck = LiveOpsRules.luckMultiplier(scenario.events, applied, now, realLimits)

			-- Store: only what the client can see (the LuckMultiplier and PurchasedLuckEndsAt attributes).
			local shownLuck = LiveOpsRules.luckMultiplier(scenario.events, scenario.boosts, now, realLimits)
			local purchasedEndsAt = LiveOpsRules.boostEndsAt(scenario.boosts, "purchase", now)
			local preview =
				LiveOpsRules.previewBoost(shownLuck, purchasedEndsAt > now, perks.serverLuckMultiplier, realLimits)

			T.expect(preview.before).toBe(shownLuck)
			T.expect(preview.after).toBe(serverLuck)
			local eventIds = LiveOpsRules.activeEventIds(scenario.events, now)
			T.expect(RarityRoll.odds(catalog.rarityList, catalog.creatureList, preview.after, eventIds))
				.toEqual(RarityRoll.odds(catalog.rarityList, catalog.creatureList, serverLuck, eventIds))
		end
	end)

	T.it("buying while a purchased boost runs only adds time: odds stay the same", function()
		local running = { { multiplier = 2, endsAt = 1500, source = "purchase" } }
		local preview = LiveOpsRules.previewBoost(2, true, 2, limits)
		T.expect(preview.extendsOnly).toBe(true)
		T.expect(preview.after).toBe(2)
		local applied = LiveOpsRules.addBoost(running, 1000, 900, 2, "purchase", limits)
		T.expect(#applied).toBe(1)
		T.expect(applied[1].endsAt).toBe(2400)
		T.expect(LiveOpsRules.luckMultiplier({}, applied, 1000, limits)).toBe(2)
		T.expect(running[1].endsAt).toBe(1500) -- the input list is not modified
	end)

	T.it("a new boost multiplies the luck, clamped to the cap", function()
		local fresh = LiveOpsRules.previewBoost(1, false, 2, limits)
		T.expect(fresh.extendsOnly).toBe(false)
		T.expect(fresh.after).toBe(2)
		T.expect(LiveOpsRules.previewBoost(4, false, 2, limits).after).toBe(6)
		T.expect(
			#LiveOpsRules.addBoost({ { multiplier = 3, endsAt = 50, source = "admin" } }, 0, 900, 2, "purchase", limits)
		)
			.toBe(2)
	end)

	T.it("reports when a source's boosts end", function()
		local boosts = {
			{ multiplier = 2, endsAt = 1500, source = "purchase" },
			{ multiplier = 2, endsAt = 1800, source = "admin" },
			{ multiplier = 2, endsAt = 900, source = "purchase" },
		}
		T.expect(LiveOpsRules.boostEndsAt(boosts, "purchase", 1000)).toBe(1500)
		T.expect(LiveOpsRules.boostEndsAt(boosts, "purchase", 1600)).toBe(0)
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
