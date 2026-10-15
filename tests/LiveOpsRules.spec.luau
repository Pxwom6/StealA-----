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
	T.it("leaves one source's boosts out when asked (prize rolls leave out bought Server Luck)", function()
		local boosts = {
			{ multiplier = 2, endsAt = 500, source = "purchase" },
			{ multiplier = 1.5, endsAt = 500, source = "modifier" },
		}
		T.expect(LiveOpsRules.luckMultiplier(events, boosts, 150, limits)).toBe(6) -- 2 event x 2 bought x 1.5 modifier
		T.expect(LiveOpsRules.luckMultiplier(events, boosts, 150, limits, "purchase")).toBe(3) -- event and modifier stay
		T.expect(LiveOpsRules.luckMultiplier({}, boosts, 150, limits, "purchase")).toBe(1.5)
		T.expect(LiveOpsRules.luckMultiplier({}, { boosts[1] }, 150, limits, "purchase")).toBe(1)
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

T.describe("LiveOpsRules.oneSeasonAtATime", function()
	local seasonal = { Halloween = true, Winter = true, Easter = true }
	local halloween: LiveOpsRules.EventDef =
		{ id = "Halloween", startsAt = 0, endsAt = 1000, bannerText = "Halloween!", title = "Halloween" }
	local luck: LiveOpsRules.EventDef = { id = "Luck", startsAt = 300, endsAt = 700, luckMultiplier = 2 }
	local cash: LiveOpsRules.EventDef = { id = "Cash", startsAt = 0, endsAt = 2000, cashMultiplier = 2 }
	-- an admin's /event Winter 100 s into Halloween's window
	local winter: LiveOpsRules.EventDef =
		{ id = "Winter", startsAt = 400, endsAt = 500, bannerText = "Winter!", title = "Winter" }

	T.it("lets a second seasonal event end the first the moment it starts", function()
		local list = LiveOpsRules.oneSeasonAtATime({ halloween, luck, cash, winter }, seasonal)
		T.expect(LiveOpsRules.activeEventIds(list, 399)).toEqual({ Halloween = true, Luck = true, Cash = true })
		T.expect(LiveOpsRules.activeEventIds(list, 400)).toEqual({ Winter = true, Luck = true, Cash = true })
		T.expect(LiveOpsRules.activeEventIds(list, 499)).toEqual({ Winter = true, Luck = true, Cash = true })
		local banner = LiveOpsRules.bannerEvent(list, 450) :: LiveOpsRules.EventDef
		T.expect(banner.id).toBe("Winter")
		T.expect(banner.endsAt).toBe(500)
	end)

	T.it("brings a scheduled one back when the one that took over ends, if its own dates still say so", function()
		local list = LiveOpsRules.oneSeasonAtATime({ halloween, luck, cash, winter }, seasonal)
		T.expect(LiveOpsRules.activeEventIds(list, 500)).toEqual({ Halloween = true, Luck = true, Cash = true })
		local banner = LiveOpsRules.bannerEvent(list, 600) :: LiveOpsRules.EventDef
		T.expect(banner.id).toBe("Halloween")
		T.expect(banner.endsAt).toBe(1000)
		T.expect(LiveOpsRules.activeEventIds(list, 1000)).toEqual({ Cash = true })
		-- before the takeover, Halloween's own countdown runs to the moment Winter starts
		T.expect((LiveOpsRules.bannerEvent(list, 100) :: LiveOpsRules.EventDef).endsAt).toBe(400)
		-- an admin event that outlasts the scheduled one leaves nothing behind it
		local long = table.clone(winter)
		long.endsAt = 1500
		local later = LiveOpsRules.oneSeasonAtATime({ halloween, long }, seasonal)
		T.expect(LiveOpsRules.activeEventIds(later, 1200)).toEqual({ Winter = true })
		T.expect(LiveOpsRules.activeEventIds(later, 1500)).toEqual({})
	end)

	T.it("leaves luck and cash events running beside any seasonal event, untouched", function()
		local list = LiveOpsRules.oneSeasonAtATime({ halloween, luck, cash, winter }, seasonal)
		T.expect(LiveOpsRules.luckMultiplier(list, {}, 450, limits)).toBe(2)
		T.expect(LiveOpsRules.cashMultiplier(list, 450, limits)).toBe(2)
		local plain: { LiveOpsRules.EventDef } = {}
		for _, event in list do
			if not seasonal[event.id] then
				table.insert(plain, event)
			end
		end
		T.expect(plain).toEqual({ luck, cash })
	end)

	T.it("keeps the list's order, so the banner rule still reads it", function()
		local list = LiveOpsRules.oneSeasonAtATime({ halloween, luck, cash, winter }, seasonal)
		local order: { string } = {}
		for _, event in list do
			table.insert(order, event.id)
		end
		-- Halloween before and after the takeover, then the others as listed
		T.expect(order).toEqual({ "Halloween", "Halloween", "Luck", "Cash", "Winter" })
	end)

	T.it("never lets two copies of one event cut each other", function()
		-- scheduled, and extended by /event: still one event
		local again: LiveOpsRules.EventDef = { id = "Halloween", startsAt = 200, endsAt = 1200 }
		local list = LiveOpsRules.oneSeasonAtATime({ halloween, again }, seasonal)
		T.expect(list).toEqual({ halloween, again })
		T.expect(LiveOpsRules.activeEventIds(list, 1100)).toEqual({ Halloween = true })
	end)

	T.it("gives a tie on the same start to the one listed last: an admin's /event beats the schedule", function()
		-- LiveOpsService lists config, then remote config, then what admins started
		local scheduled: LiveOpsRules.EventDef = { id = "Winter", startsAt = 100, endsAt = 300 }
		local started: LiveOpsRules.EventDef = { id = "Easter", startsAt = 100, endsAt = 200 }
		local list = LiveOpsRules.oneSeasonAtATime({ scheduled, started }, seasonal)
		T.expect(LiveOpsRules.activeEventIds(list, 150)).toEqual({ Easter = true })
		T.expect(LiveOpsRules.activeEventIds(list, 250)).toEqual({ Winter = true })
		T.expect(LiveOpsRules.activeEventIds(LiveOpsRules.oneSeasonAtATime({ started, scheduled }, seasonal), 150))
			.toEqual({ Winter = true })
	end)

	T.it("changes nothing with fewer than two seasonal events", function()
		local list = { halloween, luck, cash }
		T.expect(LiveOpsRules.oneSeasonAtATime(list, seasonal)).toEqual(list)
		T.expect(LiveOpsRules.oneSeasonAtATime({ halloween, winter }, {})).toEqual({ halloween, winter })
	end)

	T.it("never runs two seasonal events at once, whatever the windows (the newest open one runs)", function()
		local rng = T.seededRandom(58)
		for _ = 1, 200 do
			local list: { LiveOpsRules.EventDef } = {}
			for _, id in { "Halloween", "Winter", "Easter", "Halloween", "Luck", "Cash" } do
				local startsAt = math.floor(rng() * 1000)
				table.insert(list, { id = id, startsAt = startsAt, endsAt = startsAt + 1 + math.floor(rng() * 600) })
			end
			local cut = LiveOpsRules.oneSeasonAtATime(list, seasonal)
			for t = 0, 1600, 7 do
				local running: { string } = {}
				for id in LiveOpsRules.activeEventIds(cut, t) do
					if seasonal[id] then
						table.insert(running, id)
					end
				end
				-- the open seasonal window that started last (on a tie, the one listed last), if any
				local newest: LiveOpsRules.EventDef? = nil
				for _, event in list do
					if seasonal[event.id] and t >= event.startsAt and t < event.endsAt then
						local best = newest
						if best == nil or event.startsAt >= best.startsAt then
							newest = event
						end
					end
				end
				if newest then
					T.expect(running).toEqual({ newest.id })
				else
					T.expect(#running).toBe(0)
				end
				-- plain events are exactly as listed
				local plain = LiveOpsRules.activeEventIds(list, t)
				local after = LiveOpsRules.activeEventIds(cut, t)
				T.expect(after.Luck).toBe(plain.Luck)
				T.expect(after.Cash).toBe(plain.Cash)
			end
		end
	end)
end)

local function findShipped(id: string): LiveOpsRules.EventDef
	for _, event in LiveOps.events do
		if event.id == id then
			return event
		end
	end
	error(`LiveOps.events has no {id}`)
end

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

T.describe("LiveOpsRules shipped Halloween 2026 events", function()
	local halloween = findShipped("Halloween2026")
	local luckWeekend = findShipped("HalloweenLuck2026")

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

T.describe("LiveOpsRules shipped Harvest Feast 2026 events", function()
	local harvest = findShipped("Harvest2026")
	local luck = findShipped("HarvestLuck2026")
	local all = LiveOps.events

	T.it("runs Fri 20 Nov 17:00 UTC to Mon 30 Nov 08:00 UTC, with a 2x luck feast weekend inside it", function()
		T.expect(harvest.startsAt).toBe(utc(2026, 11, 20, 17, 0))
		T.expect(harvest.endsAt).toBe(utc(2026, 11, 30, 8, 0))
		T.expect(luck.startsAt).toBe(utc(2026, 11, 27, 17, 0))
		T.expect(luck.endsAt).toBe(utc(2026, 11, 29, 23, 59))
		T.expect(luck.luckMultiplier).toBe(2)
		T.expect(luck.startsAt).toBeGreaterThan(harvest.startsAt)
		T.expect(luck.endsAt).toBeLessThan(harvest.endsAt)
		T.expect(harvest.luckMultiplier or 1).toBe(1)
		T.expect(harvest.cashMultiplier or 1).toBe(1)
		-- in the empty weeks between Halloween and Winter: one seasonal theme at a time
		T.expect(harvest.startsAt).toBeGreaterThan(findShipped("Halloween2026").endsAt)
		T.expect(harvest.endsAt).toBeLessThan(findShipped("Winter2026").startsAt)
	end)

	T.it("switches on and off by date alone, with 2x luck on the feast weekend", function()
		T.expect(LiveOpsRules.activeEventIds(all, harvest.startsAt - 1).Harvest2026).toBeNil()
		T.expect(LiveOpsRules.activeEventIds(all, harvest.startsAt).Harvest2026).toBe(true)
		T.expect(LiveOpsRules.activeEventIds(all, harvest.endsAt - 1).Harvest2026).toBe(true)
		T.expect(LiveOpsRules.activeEventIds(all, harvest.endsAt).Harvest2026).toBeNil()
		-- the event alone in its first week (US Thanksgiving is Thu 26 Nov): no luck yet
		local thanksgiving = utc(2026, 11, 26, 18, 0)
		T.expect(LiveOpsRules.activeEventIds(all, thanksgiving)).toEqual({ Harvest2026 = true })
		T.expect(LiveOpsRules.luckMultiplier(all, {}, thanksgiving, LiveOps.limits)).toBe(1)
		local saturday = utc(2026, 11, 28, 12, 0)
		T.expect(LiveOpsRules.activeEventIds(all, saturday)).toEqual({ Harvest2026 = true, HarvestLuck2026 = true })
		T.expect(LiveOpsRules.luckMultiplier(all, {}, saturday, LiveOps.limits)).toBe(2)
		T.expect(LiveOpsRules.luckChangesAt(all, {}, saturday, LiveOps.limits)).toBe(luck.endsAt)
		T.expect(LiveOpsRules.luckMultiplier(all, {}, luck.endsAt, LiveOps.limits)).toBe(1)
		T.expect(LiveOpsRules.cashMultiplier(all, saturday, LiveOps.limits)).toBe(1)
	end)

	T.it("shows the Harvest Feast banner with its countdown title, the luck weekend included", function()
		for _, at in { harvest.startsAt, utc(2026, 11, 28, 12, 0), harvest.endsAt - 1 } do
			local banner = LiveOpsRules.bannerEvent(all, at) :: LiveOpsRules.EventDef
			T.expect(banner.id).toBe("Harvest2026")
			T.expect(banner.title).toBe("Harvest Feast")
		end
		T.expect(LiveOpsRules.bannerEvent(all, harvest.endsAt)).toBeNil()
		T.expect(luck.bannerText).toBeNil() -- the HUD's luck pill counts the weekend down under the banner
	end)
end)

T.describe("LiveOpsRules shipped Winter 2026 events", function()
	local winter = findShipped("Winter2026")
	local christmasLuck = findShipped("WinterLuck2026")
	local newYear = findShipped("NewYearCash2026")
	local all = LiveOps.events

	T.it(
		"runs Fri 18 Dec 17:00 UTC to Mon 4 Jan 08:00 UTC, with Christmas luck and New Year's cash inside it",
		function()
			T.expect(winter.startsAt).toBe(utc(2026, 12, 18, 17, 0))
			T.expect(winter.endsAt).toBe(utc(2027, 1, 4, 8, 0))
			T.expect(christmasLuck.startsAt).toBe(utc(2026, 12, 24, 17, 0))
			T.expect(christmasLuck.endsAt).toBe(utc(2026, 12, 26, 23, 59))
			T.expect(newYear.startsAt).toBe(utc(2026, 12, 31, 17, 0))
			T.expect(newYear.endsAt).toBe(utc(2027, 1, 1, 23, 59))
			T.expect(christmasLuck.luckMultiplier).toBe(2)
			T.expect(newYear.cashMultiplier).toBe(2)
			for _, inner in { christmasLuck, newYear } do
				T.expect(inner.startsAt).toBeGreaterThan(winter.startsAt)
				T.expect(inner.endsAt).toBeLessThan(winter.endsAt)
			end
			T.expect(winter.luckMultiplier or 1).toBe(1)
			T.expect(winter.cashMultiplier or 1).toBe(1)
			-- never overlaps Halloween: one seasonal theme at a time
			T.expect(winter.startsAt).toBeGreaterThan(findShipped("Halloween2026").endsAt)
		end
	)

	T.it("switches on and off by date alone, with the right luck and cash on each day", function()
		T.expect(LiveOpsRules.activeEventIds(all, winter.startsAt - 1).Winter2026).toBeNil()
		T.expect(LiveOpsRules.activeEventIds(all, winter.startsAt).Winter2026).toBe(true)
		T.expect(LiveOpsRules.activeEventIds(all, winter.endsAt - 1).Winter2026).toBe(true)
		T.expect(LiveOpsRules.activeEventIds(all, winter.endsAt).Winter2026).toBeNil()
		local christmasDay = utc(2026, 12, 25, 12, 0)
		T.expect(LiveOpsRules.activeEventIds(all, christmasDay)).toEqual({ Winter2026 = true, WinterLuck2026 = true })
		T.expect(LiveOpsRules.luckMultiplier(all, {}, christmasDay, LiveOps.limits)).toBe(2)
		T.expect(LiveOpsRules.cashMultiplier(all, christmasDay, LiveOps.limits)).toBe(1)
		local newYearsEve = utc(2026, 12, 31, 22, 0)
		T.expect(LiveOpsRules.activeEventIds(all, newYearsEve)).toEqual({ Winter2026 = true, NewYearCash2026 = true })
		T.expect(LiveOpsRules.luckMultiplier(all, {}, newYearsEve, LiveOps.limits)).toBe(1)
		T.expect(LiveOpsRules.cashMultiplier(all, newYearsEve, LiveOps.limits)).toBe(2)
		T.expect(LiveOpsRules.cashMultiplier(all, newYear.endsAt, LiveOps.limits)).toBe(1)
	end)

	T.it("shows the Winter banner, and New Year's 2x Cash banner while that runs", function()
		local christmasDay = utc(2026, 12, 25, 12, 0)
		local banner = LiveOpsRules.bannerEvent(all, christmasDay) :: LiveOpsRules.EventDef
		T.expect(banner.id).toBe("Winter2026")
		T.expect(banner.title).toBe("Winter")
		local nye = LiveOpsRules.bannerEvent(all, utc(2026, 12, 31, 22, 0)) :: LiveOpsRules.EventDef
		T.expect(nye.id).toBe("NewYearCash2026")
		T.expect(nye.title).toBe("2x Cash")
		local after = LiveOpsRules.bannerEvent(all, newYear.endsAt) :: LiveOpsRules.EventDef
		T.expect(after.id).toBe("Winter2026")
	end)
end)

T.describe("LiveOpsRules shipped Valentine's 2027 events", function()
	local valentine = findShipped("Valentine2027")
	local luck = findShipped("ValentineLuck2027")
	local all = LiveOps.events

	T.it("runs Fri 5 Feb 17:00 UTC to Tue 16 Feb 08:00 UTC, with a 2x luck Valentine's weekend inside it", function()
		T.expect(valentine.startsAt).toBe(utc(2027, 2, 5, 17, 0))
		T.expect(valentine.endsAt).toBe(utc(2027, 2, 16, 8, 0))
		T.expect(luck.startsAt).toBe(utc(2027, 2, 12, 17, 0))
		T.expect(luck.endsAt).toBe(utc(2027, 2, 14, 23, 59))
		T.expect(luck.luckMultiplier).toBe(2)
		T.expect(luck.startsAt).toBeGreaterThan(valentine.startsAt)
		T.expect(luck.endsAt).toBeLessThan(valentine.endsAt)
		T.expect(valentine.luckMultiplier or 1).toBe(1)
		T.expect(valentine.cashMultiplier or 1).toBe(1)
		-- never overlaps Winter: one seasonal theme at a time
		T.expect(valentine.startsAt).toBeGreaterThan(findShipped("Winter2026").endsAt)
	end)

	T.it("switches on and off by date alone, with 2x luck on Valentine's Day", function()
		T.expect(LiveOpsRules.activeEventIds(all, valentine.startsAt - 1).Valentine2027).toBeNil()
		T.expect(LiveOpsRules.activeEventIds(all, valentine.startsAt).Valentine2027).toBe(true)
		T.expect(LiveOpsRules.activeEventIds(all, valentine.endsAt - 1).Valentine2027).toBe(true)
		T.expect(LiveOpsRules.activeEventIds(all, valentine.endsAt).Valentine2027).toBeNil()
		local valentinesDay = utc(2027, 2, 14, 12, 0)
		T.expect(LiveOpsRules.activeEventIds(all, valentinesDay))
			.toEqual({ Valentine2027 = true, ValentineLuck2027 = true })
		T.expect(LiveOpsRules.luckMultiplier(all, {}, valentinesDay, LiveOps.limits)).toBe(2)
		T.expect(LiveOpsRules.luckMultiplier(all, {}, utc(2027, 2, 15, 12, 0), LiveOps.limits)).toBe(1)
		local banner = LiveOpsRules.bannerEvent(all, valentinesDay) :: LiveOpsRules.EventDef
		T.expect(banner.id).toBe("Valentine2027")
		T.expect(banner.title).toBe("Valentine's")
	end)
end)

T.describe("LiveOpsRules shipped Easter 2027 events", function()
	local easter = findShipped("Easter2027")
	local luck = findShipped("EasterLuck2027")
	local all = LiveOps.events

	T.it("runs Fri 19 Mar 17:00 UTC to Tue 6 Apr 07:00 UTC, with 2x luck from Good Friday to Easter Monday", function()
		T.expect(easter.startsAt).toBe(utc(2027, 3, 19, 17, 0))
		T.expect(easter.endsAt).toBe(utc(2027, 4, 6, 7, 0))
		T.expect(luck.startsAt).toBe(utc(2027, 3, 26, 17, 0))
		T.expect(luck.endsAt).toBe(utc(2027, 3, 29, 23, 59))
		T.expect(luck.luckMultiplier).toBe(2)
		T.expect(luck.startsAt).toBeGreaterThan(easter.startsAt)
		T.expect(luck.endsAt).toBeLessThan(easter.endsAt)
		T.expect(easter.luckMultiplier or 1).toBe(1)
		T.expect(easter.cashMultiplier or 1).toBe(1)
		-- never overlaps Valentine's: one seasonal theme at a time
		T.expect(easter.startsAt).toBeGreaterThan(findShipped("Valentine2027").endsAt)
	end)

	T.it("switches on and off by date alone, with 2x luck on Easter Sunday", function()
		T.expect(LiveOpsRules.activeEventIds(all, easter.startsAt - 1).Easter2027).toBeNil()
		T.expect(LiveOpsRules.activeEventIds(all, easter.startsAt).Easter2027).toBe(true)
		T.expect(LiveOpsRules.activeEventIds(all, easter.endsAt - 1).Easter2027).toBe(true)
		T.expect(LiveOpsRules.activeEventIds(all, easter.endsAt).Easter2027).toBeNil()
		local easterSunday = utc(2027, 3, 28, 12, 0)
		T.expect(LiveOpsRules.activeEventIds(all, easterSunday)).toEqual({ Easter2027 = true, EasterLuck2027 = true })
		T.expect(LiveOpsRules.luckMultiplier(all, {}, easterSunday, LiveOps.limits)).toBe(2)
		T.expect(LiveOpsRules.luckMultiplier(all, {}, utc(2027, 3, 30, 12, 0), LiveOps.limits)).toBe(1)
		local banner = LiveOpsRules.bannerEvent(all, easterSunday) :: LiveOpsRules.EventDef
		T.expect(banner.id).toBe("Easter2027")
		T.expect(banner.title).toBe("Easter")
	end)
end)

T.describe("LiveOpsRules shipped St Patrick's 2027 events", function()
	local patrick = findShipped("StPatrick2027")
	local luck = findShipped("StPatrickLuck2027")
	local all = LiveOps.events

	T.it("runs Fri 12 Mar 17:00 UTC to Thu 18 Mar 07:00 UTC, opening with a 2x luck weekend", function()
		T.expect(patrick.startsAt).toBe(utc(2027, 3, 12, 17, 0))
		T.expect(patrick.endsAt).toBe(utc(2027, 3, 18, 7, 0))
		T.expect(luck.startsAt).toBe(utc(2027, 3, 12, 17, 0))
		T.expect(luck.endsAt).toBe(utc(2027, 3, 14, 23, 59))
		T.expect(luck.luckMultiplier).toBe(2)
		T.expect(luck.cashMultiplier or 1).toBe(1)
		T.expect(luck.startsAt).toBeAtLeast(patrick.startsAt)
		T.expect(luck.endsAt).toBeLessThan(patrick.endsAt)
		T.expect(patrick.luckMultiplier or 1).toBe(1)
		T.expect(patrick.cashMultiplier or 1).toBe(1)
		-- St Patrick's Day itself (Wed 17 Mar) is inside it, all day round the world
		T.expect(utc(2027, 3, 17, 0, 0)).toBeGreaterThan(patrick.startsAt)
		T.expect(utc(2027, 3, 18, 0, 0)).toBeLessThan(patrick.endsAt)
		-- between Valentine's and Easter, ending more than a day before Easter starts: one seasonal theme at a time,
		-- with a gap so the two themes never swap straight over
		T.expect(patrick.startsAt).toBeGreaterThan(findShipped("Valentine2027").endsAt)
		T.expect(findShipped("Easter2027").startsAt - patrick.endsAt).toBeAtLeast(24 * 3600)
	end)

	T.it("switches on and off by date alone, with 2x luck on its first weekend only", function()
		T.expect(LiveOpsRules.activeEventIds(all, patrick.startsAt - 1).StPatrick2027).toBeNil()
		T.expect(LiveOpsRules.activeEventIds(all, patrick.startsAt))
			.toEqual({ StPatrick2027 = true, StPatrickLuck2027 = true })
		T.expect(LiveOpsRules.activeEventIds(all, patrick.endsAt - 1).StPatrick2027).toBe(true)
		T.expect(LiveOpsRules.activeEventIds(all, patrick.endsAt).StPatrick2027).toBeNil()
		local saturday = utc(2027, 3, 13, 12, 0)
		T.expect(LiveOpsRules.luckMultiplier(all, {}, saturday, LiveOps.limits)).toBe(2)
		T.expect(LiveOpsRules.luckChangesAt(all, {}, saturday, LiveOps.limits)).toBe(luck.endsAt)
		T.expect(LiveOpsRules.cashMultiplier(all, saturday, LiveOps.limits)).toBe(1)
		local stPatricksDay = utc(2027, 3, 17, 12, 0)
		T.expect(LiveOpsRules.activeEventIds(all, stPatricksDay)).toEqual({ StPatrick2027 = true })
		T.expect(LiveOpsRules.luckMultiplier(all, {}, stPatricksDay, LiveOps.limits)).toBe(1)
		-- nothing seasonal in the gap before Easter
		local gap = LiveOpsRules.activeEventIds(all, patrick.endsAt + 12 * 3600)
		T.expect(gap.StPatrick2027).toBeNil()
		T.expect(gap.Easter2027).toBeNil()
	end)

	T.it("shows the Lucky Clover banner with its countdown title, the luck weekend included", function()
		for _, at in { patrick.startsAt, utc(2027, 3, 13, 12, 0), patrick.endsAt - 1 } do
			local banner = LiveOpsRules.bannerEvent(all, at) :: LiveOpsRules.EventDef
			T.expect(banner.id).toBe("StPatrick2027")
			T.expect(banner.title).toBe("Lucky Clover")
		end
		T.expect(LiveOpsRules.bannerEvent(all, patrick.endsAt)).toBeNil()
		T.expect(luck.bannerText).toBeNil() -- the HUD's luck pill counts the weekend down under the banner
	end)
end)

T.describe("LiveOpsRules shipped Summer Splash 2027 events", function()
	local summer = findShipped("Summer2027")
	local splash = findShipped("SplashCash2027")
	local all = LiveOps.events

	T.it(
		"runs Fri 25 Jun 17:00 UTC to Mon 12 Jul 07:00 UTC, with a 2x cash Independence Day weekend inside it",
		function()
			T.expect(summer.startsAt).toBe(utc(2027, 6, 25, 17, 0))
			T.expect(summer.endsAt).toBe(utc(2027, 7, 12, 7, 0))
			T.expect(splash.startsAt).toBe(utc(2027, 7, 2, 17, 0))
			T.expect(splash.endsAt).toBe(utc(2027, 7, 5, 23, 59))
			T.expect(splash.cashMultiplier).toBe(2)
			T.expect(splash.luckMultiplier or 1).toBe(1)
			T.expect(splash.startsAt).toBeGreaterThan(summer.startsAt)
			T.expect(splash.endsAt).toBeLessThan(summer.endsAt)
			T.expect(summer.luckMultiplier or 1).toBe(1)
			T.expect(summer.cashMultiplier or 1).toBe(1)
			-- well after Easter: one seasonal theme at a time
			T.expect(summer.startsAt).toBeGreaterThan(findShipped("Easter2027").endsAt)
		end
	)

	T.it("switches on and off by date alone, with 2x cash on the Splash weekend", function()
		T.expect(LiveOpsRules.activeEventIds(all, summer.startsAt - 1).Summer2027).toBeNil()
		T.expect(LiveOpsRules.activeEventIds(all, summer.startsAt).Summer2027).toBe(true)
		T.expect(LiveOpsRules.activeEventIds(all, summer.endsAt - 1).Summer2027).toBe(true)
		T.expect(LiveOpsRules.activeEventIds(all, summer.endsAt).Summer2027).toBeNil()
		local firstMonday = utc(2027, 6, 28, 12, 0)
		T.expect(LiveOpsRules.activeEventIds(all, firstMonday)).toEqual({ Summer2027 = true })
		T.expect(LiveOpsRules.cashMultiplier(all, firstMonday, LiveOps.limits)).toBe(1)
		local fourthOfJuly = utc(2027, 7, 4, 18, 0)
		T.expect(LiveOpsRules.activeEventIds(all, fourthOfJuly)).toEqual({ Summer2027 = true, SplashCash2027 = true })
		T.expect(LiveOpsRules.cashMultiplier(all, fourthOfJuly, LiveOps.limits)).toBe(2)
		T.expect(LiveOpsRules.luckMultiplier(all, {}, fourthOfJuly, LiveOps.limits)).toBe(1)
		T.expect(LiveOpsRules.cashMultiplier(all, splash.endsAt, LiveOps.limits)).toBe(1)
	end)

	T.it("shows the Summer Splash banner, and the Splash weekend's 2x Cash banner while that runs", function()
		local banner = LiveOpsRules.bannerEvent(all, utc(2027, 6, 28, 12, 0)) :: LiveOpsRules.EventDef
		T.expect(banner.id).toBe("Summer2027")
		T.expect(banner.title).toBe("Summer Splash")
		local weekend = LiveOpsRules.bannerEvent(all, utc(2027, 7, 4, 18, 0)) :: LiveOpsRules.EventDef
		T.expect(weekend.id).toBe("SplashCash2027")
		T.expect(weekend.title).toBe("2x Cash")
		local after = LiveOpsRules.bannerEvent(all, splash.endsAt) :: LiveOpsRules.EventDef
		T.expect(after.id).toBe("Summer2027")
		T.expect(LiveOpsRules.bannerEvent(all, summer.endsAt)).toBeNil()
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
