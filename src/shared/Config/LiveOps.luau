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
	-- TODO(owner): add your own Roblox UserId(s). Group-rank based admin can be added in LiveOpsService.
	adminUserIds = {} :: { number },

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
