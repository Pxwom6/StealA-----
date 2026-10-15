--!strict
--[[
	LiveOps: scheduled events, luck boosts and admin access. Plain data only.

	Three ways to run an event, none of which need a code change:
	  1. Add an entry to `events` below and publish (good for planned weekends / holidays).
	  2. Edit the remote-config DataStore entry (`remoteConfig`) from the Creator Hub's Data Stores manager:
	     servers re-read it every `refreshSeconds`, no publish needed. Same JSON shape as `events`.
	  3. Admin chat command in any live server — broadcast to every server via MessagingService (in Studio anyone
	     can use them, and they only affect that Studio session):
	       /luck <multiplier> <minutes>      e.g. /luck 2 30
	       /event <eventId> [minutes]        start a configured event now (its durationSeconds, or `minutes`); an
	                                         event that is already running is only extended, never doubled
	       /event off [eventId]              end events started with /event (all of them, or just that one)
	       /announce <text>

	Event fields (all times are Unix seconds, UTC):
	  id              unique string; creatures and mutations with a matching `eventId` only spawn while it is
	                  active, and Config/Seasons can map it to a seasonal theme (map decorations + lighting)
	  startsAt/endsAt window (endsAt is exclusive)
	  luckMultiplier  multiplies conveyor weights of luck-affected rarities (optional, default 1)
	  cashMultiplier  multiplies everyone's income (optional, default 1)
	  bannerText      shown in the HUD while active (optional; the first active event with one wins)
	  title           short name for the HUD countdown, "<title> ends in 3d 4h" (optional)
	  durationSeconds used by `/event <id>` when started by an admin (optional, default 1800)

	Changing an event's dates: edit startsAt/endsAt below and publish (or override from the DataStore, which adds
	its events to these). Convert dates with any Unix-time converter, e.g. `date -u -d "2026-10-23 17:00" +%s`.
]]

local Types = require("../Types")

export type EventDef = Types.EventDef

local LiveOps = {
	-- Roblox UserIds allowed to use the admin chat commands in live servers. 723735722 = Pxwom5 (the owner).
	-- Group-rank based admin can be added in LiveOpsService.
	adminUserIds = { 723735722 } :: { number },

	events = {
		-- Example (dates in the past, so it never runs). Copy, change the id and dates, publish.
		{
			id = "LaunchWeekendLuck",
			startsAt = 1735689600, -- 2025-01-01 00:00 UTC
			endsAt = 1735862400, -- 2025-01-03 00:00 UTC
			luckMultiplier = 2,
			cashMultiplier = 1,
			bannerText = "Launch Weekend: 2x Luck!",
			durationSeconds = 1800,
		},

		-- Halloween 2026: four event Snacklings (Config/Creatures), the Haunted mutation (Config/Mutations) and the
		-- "halloween" seasonal theme (Config/Seasons: pumpkins, lights, bats, dusk lighting).
		-- Fri 23 Oct 17:00 UTC (1 PM EDT / 10 AM PDT) -> Mon 2 Nov 08:00 UTC (3 AM EST / Sun midnight PST).
		{
			id = "Halloween2026",
			startsAt = 1792774800, -- 2026-10-23 17:00 UTC
			endsAt = 1793606400, -- 2026-11-02 08:00 UTC
			bannerText = "Halloween: spooky Snacklings & Haunted mutations!",
			title = "Halloween",
			durationSeconds = 3600, -- `/event Halloween2026` runs it for an hour
		},
		-- Halloween luck weekend inside the event: 2x luck (stacks with Server Luck, clamped by limits below).
		-- Fri 30 Oct 17:00 UTC (1 PM EDT / 10 AM PDT) -> Sun 1 Nov 23:59 UTC (6:59 PM EST / 3:59 PM PST).
		-- No bannerText: the HUD's luck pill shows "2x LUCK" with its own countdown, under the Halloween banner.
		{
			id = "HalloweenLuck2026",
			startsAt = 1793379600, -- 2026-10-30 17:00 UTC
			endsAt = 1793577540, -- 2026-11-01 23:59 UTC
			luckMultiplier = 2,
			title = "Luck weekend",
			durationSeconds = 1800,
		},

		-- Winter 2026: four event Snacklings (Config/Creatures), the Festive mutation (Config/Mutations) and the
		-- "winter" seasonal theme (Config/Seasons: presents, trees, snowmen, string lights, snowfall, a wintry dusk).
		-- New Year's Eve 2x Cash comes first in this list so its banner shows instead of the Winter one while it runs
		-- (the HUD shows the first active event that has a banner).
		-- Thu 31 Dec 17:00 UTC (12 PM EST / 9 AM PST) -> Fri 1 Jan 23:59 UTC (6:59 PM EST / 3:59 PM PST).
		{
			id = "NewYearCash2026",
			startsAt = 1798736400, -- 2026-12-31 17:00 UTC
			endsAt = 1798847940, -- 2027-01-01 23:59 UTC
			cashMultiplier = 2,
			bannerText = "New Year's Eve: 2x Cash!",
			title = "2x Cash",
			durationSeconds = 1800,
		},
		-- Fri 18 Dec 17:00 UTC (12 PM EST / 9 AM PST) -> Mon 4 Jan 08:00 UTC (3 AM EST / Sun midnight PST).
		{
			id = "Winter2026",
			startsAt = 1797613200, -- 2026-12-18 17:00 UTC
			endsAt = 1799049600, -- 2027-01-04 08:00 UTC
			bannerText = "Winter: festive Snacklings & Festive mutations!",
			title = "Winter",
			durationSeconds = 3600, -- `/event Winter2026` runs it for an hour
		},
		-- Christmas luck days inside the event: 2x luck (stacks with Server Luck, clamped by limits below).
		-- Thu 24 Dec 17:00 UTC (12 PM EST / 9 AM PST) -> Sat 26 Dec 23:59 UTC (6:59 PM EST / 3:59 PM PST).
		{
			id = "WinterLuck2026",
			startsAt = 1798131600, -- 2026-12-24 17:00 UTC
			endsAt = 1798329540, -- 2026-12-26 23:59 UTC
			luckMultiplier = 2,
			title = "Christmas luck",
			durationSeconds = 1800,
		},

		-- Valentine's 2027: four event Snacklings (Config/Creatures), the Sweetheart mutation (Config/Mutations) and the
		-- "valentine" seasonal theme (Config/Seasons: potted roses, heart balloons, giant hearts with Cupid's arrows,
		-- string lights, rose-pink lamps, falling petals and a rosy late afternoon).
		-- Fri 5 Feb 17:00 UTC (12 PM EST / 9 AM PST) -> Tue 16 Feb 08:00 UTC (3 AM EST / Mon midnight PST), so it
		-- takes in Valentine's Day (Sun 14) and the US Presidents' Day holiday after it (Mon 15).
		{
			id = "Valentine2027",
			startsAt = 1801846800, -- 2027-02-05 17:00 UTC
			endsAt = 1802764800, -- 2027-02-16 08:00 UTC
			bannerText = "Valentine's: sweet Snacklings & Sweetheart mutations!",
			title = "Valentine's",
			durationSeconds = 3600, -- `/event Valentine2027` runs it for an hour
		},
		-- Valentine's weekend inside the event: 2x luck (stacks with Server Luck, clamped by limits below).
		-- Fri 12 Feb 17:00 UTC (12 PM EST / 9 AM PST) -> Sun 14 Feb 23:59 UTC (6:59 PM EST / 3:59 PM PST).
		{
			id = "ValentineLuck2027",
			startsAt = 1802451600, -- 2027-02-12 17:00 UTC
			endsAt = 1802649540, -- 2027-02-14 23:59 UTC
			luckMultiplier = 2,
			title = "Sweetheart luck",
			durationSeconds = 1800,
		},

		-- Easter 2027: four event Snacklings (Config/Creatures), the Pastel mutation (Config/Mutations) and the
		-- "spring" seasonal theme (Config/Seasons: giant painted eggs, chocolate bunnies, blossom trees, butterflies,
		-- pastel string lights and lamps, a bright spring morning and falling blossom).
		-- Fri 19 Mar 17:00 UTC (1 PM EDT / 10 AM PDT) -> Tue 6 Apr 07:00 UTC (3 AM EDT / Tue midnight PDT): two
		-- weekends, Easter (Sun 28 Mar) and Easter Monday, and the spring holidays either side.
		{
			id = "Easter2027",
			startsAt = 1805475600, -- 2027-03-19 17:00 UTC
			endsAt = 1806994800, -- 2027-04-06 07:00 UTC
			bannerText = "Easter: hatching Snacklings & Pastel mutations!",
			title = "Easter",
			durationSeconds = 3600, -- `/event Easter2027` runs it for an hour
		},
		-- Easter weekend inside the event, Good Friday to Easter Monday: 2x luck (stacks with Server Luck, clamped by
		-- limits below). Fri 26 Mar 17:00 UTC (1 PM EDT / 10 AM PDT) -> Mon 29 Mar 23:59 UTC (7:59 PM EDT / 4:59 PM
		-- PDT).
		{
			id = "EasterLuck2027",
			startsAt = 1806080400, -- 2027-03-26 17:00 UTC
			endsAt = 1806364740, -- 2027-03-29 23:59 UTC
			luckMultiplier = 2,
			title = "Easter luck",
			durationSeconds = 1800,
		},
	} :: { EventDef },

	limits = {
		maxLuckMultiplier = 6, -- product of every active boost and event is clamped to this
		maxCashMultiplier = 3,
		-- Luck boosts stack duration up to this much remaining time. For the paid Server Luck it is a soft cap: the
		-- store stops offering it once another purchase would pass the cap, but a receipt always adds its full time.
		maxBoostSeconds = 60 * 60,
	},

	remoteConfig = {
		enabled = true,
		dataStoreName = "LiveOpsConfig",
		key = "events",
		refreshSeconds = 300,
	},

	messagingTopic = "SnacklingLiveOps",
}

return LiveOps
