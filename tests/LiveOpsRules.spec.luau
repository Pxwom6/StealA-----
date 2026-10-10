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
	T.it("counts an event listed twice only once (scheduled + /event, or re-listed by remote config)", function()
		local luckA: LiveOpsRules.EventDef = { id = "Luck", startsAt = 0, endsAt = 200, luckMultiplier = 2 }
		local luckB: LiveOpsRules.EventDef = { id = "Luck", startsAt = 50, endsAt = 400, luckMultiplier = 2 }
		local cashA: LiveOpsRules.EventDef = { id = "Cash", startsAt = 0, endsAt = 200, cashMultiplier = 2 }
		local cashB: LiveOpsRules.EventDef = { id = "Cash", startsAt = 0, endsAt = 300, cashMultiplier = 2 }
		local list = { luckA, cashA, luckB, cashB }
		T.expect(LiveOpsRules.luckMultiplier(list, {}, 100, limits)).toBe(2)
		T.expect(LiveOpsRules.cashMultiplier(list, 100, limits)).toBe(2)
		-- the copy that ends last wins, so the event keeps running after the first copy ends
		T.expect(LiveOpsRules.luckMultiplier(list, {}, 250, limits)).toBe(2)
		T.expect(LiveOpsRules.cashMultiplier(list, 250, limits)).toBe(2)
		T.expect(LiveOpsRules.luckMultiplier(list, {}, 400, limits)).toBe(1)
		T.expect(LiveOpsRules.cashMultiplier(list, 300, limits)).toBe(1)
		-- with a boost on top, the event still counts once
		local boosts = { { multiplier = 2, endsAt = 500, source = "purchase" } }
		T.expect(LiveOpsRules.luckMultiplier(list, boosts, 100, limits)).toBe(4)
		-- one entry per id, in first-appearance order, keeping the latest end
		local distinct = LiveOpsRules.distinctActiveEvents(list, 100)
		T.expect(#distinct).toBe(2)
		T.expect(distinct[1]).toBe(luckB)
		T.expect(distinct[2]).toBe(cashB)
		T.expect(LiveOpsRules.luckChangesAt(list, {}, 100, limits)).toBe(400)
		local banner = {
			{ id = "B", startsAt = 0, endsAt = 100, bannerText = "Hi" },
			{ id = "B", startsAt = 0, endsAt = 900, bannerText = "Hi" },
		}
		T.expect((LiveOpsRules.bannerEvent(banner, 50) :: LiveOpsRules.EventDef).endsAt).toBe(900)
	end)
	T.it("counts the luck down to its next change, not its last", function()
		local boosts = { { multiplier = 2, endsAt = 180, source = "purchase" } }
		T.expect(LiveOpsRules.luckChangesAt(events, {}, 50, limits)).toBe(0) -- nothing raises the luck
		T.expect(LiveOpsRules.luckChangesAt(events, {}, 150, limits)).toBe(200) -- the luck event's end
		T.expect(LiveOpsRules.luckChangesAt(events, boosts, 150, limits)).toBe(180) -- the boost ends first
		T.expect(LiveOpsRules.luckChangesAt(events, boosts, 190, limits)).toBe(200) -- boost over: the event's end
		T.expect(LiveOpsRules.luckChangesAt(events, boosts, 250, limits)).toBe(0) -- the cash event doesn't count
		local long = { { multiplier = 2, endsAt = 900, source = "admin" } }
		T.expect(LiveOpsRules.luckChangesAt(events, long, 150, limits)).toBe(200)
	end)
	T.it("skips ends that leave the capped luck unchanged", function()
		-- 2x event (ends 200) x 3x admin (ends 600) x 2x bought (ends 180) = 12x, shown as the 6x cap
		local boosts = {
			{ multiplier = 3, endsAt = 600, source = "admin" },
			{ multiplier = 2, endsAt = 180, source = "purchase" },
		}
		T.expect(LiveOpsRules.luckMultiplier(events, boosts, 150, limits)).toBe(6)
		-- at 180 the bought 2x ends but 2 x 3 = 6 still: the first real change is the event's end (-> 3x)
		T.expect(LiveOpsRules.luckChangesAt(events, boosts, 150, limits)).toBe(200)
		T.expect(LiveOpsRules.luckMultiplier(events, boosts, 200, limits)).toBe(3)
		T.expect(LiveOpsRules.luckChangesAt(events, boosts, 200, limits)).toBe(600)
		-- two ends at once that only together drop below the cap
		local capped = {
			{ multiplier = 6, endsAt = 300, source = "admin" },
			{ multiplier = 2, endsAt = 250, source = "purchase" },
		}
		T.expect(LiveOpsRules.luckChangesAt({}, capped, 100, limits)).toBe(300)
		-- an event starting later never counts as a change of the current luck
		local later: { LiveOpsRules.EventDef } = { { id = "Later", startsAt = 120, endsAt = 130, luckMultiplier = 2 } }
		T.expect(LiveOpsRules.luckChangesAt(later, { { multiplier = 2, endsAt = 500, source = "admin" } }, 100, limits))
			.toBe(500)
	end)
	T.it("shows the banner of the first active event that has one", function()
		local list: { LiveOpsRules.EventDef } = {
			{ id = "Quiet", startsAt = 0, endsAt = 100 },
			{ id = "Season", startsAt = 0, endsAt = 1000, bannerText = "Season!" },
			{ id = "Weekend", startsAt = 500, endsAt = 600, bannerText = "Weekend!" },
		}
		T.expect(LiveOpsRules.bannerEvent(list, 50)).toBe(list[2])
		T.expect(LiveOpsRules.bannerEvent(list, 550)).toBe(list[2])
		T.expect(LiveOpsRules.bannerEvent({ list[1], list[3] }, 550)).toBe(list[3])
		T.expect(LiveOpsRules.bannerEvent(list, 1000)).toBeNil()
		T.expect(LiveOpsRules.bannerEvent({ { id = "Empty", startsAt = 0, endsAt = 9, bannerText = "" } }, 1)).toBeNil()
	end)
end)

T.describe("LiveOpsRules shipped Halloween 2026 events", function()
	local function find(id: string): LiveOpsRules.EventDef
		for _, event in LiveOps.events do
			if event.id == id then
				return event
			end
		end
		error(`LiveOps.events has no {id}`)
	end
	local halloween = find("Halloween2026")
	local luckWeekend = find("HalloweenLuck2026")
	-- Unix seconds of a UTC date (days-from-civil), independent of the machine's time zone.
	local function utc(year: number, month: number, day: number, hour: number, min: number): number
		local y = if month <= 2 then year - 1 else year
		local era = y // 400
		local yearOfEra = y - era * 400
		local dayOfYear = (153 * ((month + 9) % 12) + 2) // 5 + day - 1
		local dayOfEra = yearOfEra * 365 + yearOfEra // 4 - yearOfEra // 100 + dayOfYear
		local days = era * 146097 + dayOfEra - 719468
		return days * 86400 + hour * 3600 + min * 60
	end

	T.it("runs Fri 23 Oct 17:00 UTC to Mon 2 Nov 08:00 UTC, with a 2x luck weekend inside it", function()
		T.expect(halloween.startsAt).toBe(utc(2026, 10, 23, 17, 0))
		T.expect(halloween.endsAt).toBe(utc(2026, 11, 2, 8, 0))
		T.expect(luckWeekend.startsAt).toBe(utc(2026, 10, 30, 17, 0))
		T.expect(luckWeekend.endsAt).toBe(utc(2026, 11, 1, 23, 59))
		T.expect(luckWeekend.luckMultiplier).toBe(2)
		T.expect(luckWeekend.startsAt).toBeGreaterThan(halloween.startsAt)
		T.expect(luckWeekend.endsAt).toBeLessThan(halloween.endsAt)
		T.expect(halloween.luckMultiplier or 1).toBe(1)
		T.expect(halloween.cashMultiplier or 1).toBe(1)
	end)

	T.it("switches on and off by date alone", function()
		local all = LiveOps.events
		T.expect(LiveOpsRules.activeEventIds(all, halloween.startsAt - 1).Halloween2026).toBeNil()
		T.expect(LiveOpsRules.activeEventIds(all, halloween.startsAt).Halloween2026).toBe(true)
		T.expect(LiveOpsRules.activeEventIds(all, halloween.endsAt - 1).Halloween2026).toBe(true)
		T.expect(LiveOpsRules.activeEventIds(all, halloween.endsAt).Halloween2026).toBeNil()
		local midWeekend = luckWeekend.startsAt + 3600
		T.expect(LiveOpsRules.activeEventIds(all, midWeekend))
			.toEqual({ Halloween2026 = true, HalloweenLuck2026 = true })
		T.expect(LiveOpsRules.luckMultiplier(all, {}, midWeekend, LiveOps.limits)).toBe(2)
		T.expect(LiveOpsRules.luckMultiplier(all, {}, luckWeekend.endsAt, LiveOps.limits)).toBe(1)
		-- the Halloween banner (with its countdown title) stays up through the luck weekend
		local banner = LiveOpsRules.bannerEvent(all, midWeekend) :: LiveOpsRules.EventDef
		T.expect(banner.id).toBe("Halloween2026")
		T.expect(banner.title).toBe("Halloween")
		T.expect(LiveOpsRules.luckChangesAt(all, {}, midWeekend, LiveOps.limits)).toBe(luckWeekend.endsAt)
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
		{
			-- the scheduled luck event also started with /event: it must count once, before and after buying
			name = "luck event listed twice",
			events = { luckEvent, { id = "Luck", startsAt = 900, endsAt = 4000, luckMultiplier = 2 } },
			boosts = {},
		},
		{
			name = "luck event listed twice + purchase running",
			events = { luckEvent, { id = "Luck", startsAt = 900, endsAt = 20000, luckMultiplier = 2 } },
			boosts = { { multiplier = perks.serverLuckMultiplier, endsAt = 1500, source = "purchase" } },
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

	T.it("stays exact during the shipped Halloween luck weekend, whatever else is running", function()
		local weekend: LiveOpsRules.EventDef? = nil
		for _, event in LiveOps.events do
			if event.id == "HalloweenLuck2026" then
				weekend = event
			end
		end
		local now = (weekend :: LiveOpsRules.EventDef).startsAt + 600
		local all = LiveOps.events -- Halloween2026 (no luck) and HalloweenLuck2026 (2x) are both active
		local cases: { { LiveOpsRules.Boost } } = {
			{},
			{ { multiplier = perks.serverLuckMultiplier, endsAt = now + 300, source = "purchase" } },
			{ { multiplier = 2, endsAt = now + 900, source = "admin" } },
			{ { multiplier = 3, endsAt = now + 900, source = "admin" } }, -- 2 x 3 = 6, already at the cap
			{
				{ multiplier = 1.5, endsAt = now + 900, source = "admin" },
				{ multiplier = perks.serverLuckMultiplier, endsAt = now + 60, source = "purchase" },
			},
		}
		-- An admin also runs `/event HalloweenLuck2026` during the scheduled weekend: an admin copy of the same id.
		local adminCopy = table.clone(weekend :: LiveOpsRules.EventDef)
		adminCopy.startsAt = now - 10
		adminCopy.endsAt = now + 1800
		local withAdminCopy = table.clone(all)
		table.insert(withAdminCopy, adminCopy)
		for _, list in { all, withAdminCopy } do
			local eventIds = LiveOpsRules.activeEventIds(list, now)
			T.expect(eventIds.HalloweenLuck2026).toBe(true)
			T.expect(LiveOpsRules.luckMultiplier(list, {}, now, realLimits)).toBe(2) -- never 2 x 2
			for _, boosts in cases do
				local shownLuck = LiveOpsRules.luckMultiplier(list, boosts, now, realLimits)
				T.expect(shownLuck).toBeAtLeast(2) -- the event's luck is part of what the store shows as "now"
				local running = LiveOpsRules.boostEndsAt(boosts, "purchase", now) > now
				local preview = LiveOpsRules.previewBoost(shownLuck, running, perks.serverLuckMultiplier, realLimits)
				local applied = LiveOpsRules.addBoost(
					boosts,
					now,
					perks.serverLuckSeconds,
					perks.serverLuckMultiplier,
					"purchase",
					receiptLimits
				)
				local serverLuck = LiveOpsRules.luckMultiplier(list, applied, now, realLimits)
				T.expect(preview.after).toBe(serverLuck)
				T.expect(RarityRoll.odds(catalog.rarityList, catalog.creatureList, preview.before, eventIds))
					.toEqual(RarityRoll.odds(catalog.rarityList, catalog.creatureList, shownLuck, eventIds))
				T.expect(RarityRoll.odds(catalog.rarityList, catalog.creatureList, preview.after, eventIds))
					.toEqual(RarityRoll.odds(catalog.rarityList, catalog.creatureList, serverLuck, eventIds))
			end
		end
		-- With nothing else running, the weekend's 2x and a bought 2x multiply: 2 -> 4.
		local plain = LiveOpsRules.previewBoost(2, false, perks.serverLuckMultiplier, realLimits)
		T.expect(plain.after).toBe(math.min(2 * perks.serverLuckMultiplier, realLimits.maxLuckMultiplier))
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
	T.it("keeps a short title for the HUD countdown", function()
		local raw: any = {
			{ id = "A", startsAt = 1, endsAt = 2, title = "Halloween" } :: any,
			{ id = "B", startsAt = 1, endsAt = 2, title = string.rep("y", 50) } :: any,
			{ id = "C", startsAt = 1, endsAt = 2, title = 5 } :: any,
			{ id = "D", startsAt = 1, endsAt = 2, title = "" } :: any,
		}
		local valid = LiveOpsRules.validateEvents(raw, limits)
		T.expect(valid[1].title).toBe("Halloween")
		T.expect(#(valid[2].title :: string)).toBe(24)
		T.expect(valid[3].title).toBeNil()
		T.expect(valid[4].title).toBeNil()
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
