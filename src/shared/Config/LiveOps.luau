--!strict
--[[
	LiveOps: scheduled events, luck boosts and admin access. Plain data only.

	Three ways to run an event, none of which need a code change:
	  1. Add an entry to `events` below and publish (good for planned weekends / holidays).
	  2. Edit the remote-config DataStore entry (`remoteConfig`) from the Creator Hub's Data Stores manager:
	     servers re-read it every `refreshSeconds`, no publish needed. Same JSON shape as `events`.
	  3. Admin chat command in any live server — broadcast to every server via MessagingService:
	       /luck <multiplier> <minutes>      e.g. /luck 2 30
	       /event <eventId>                  start a configured event now (uses its duration)
	       /announce <text>

	Event fields (all times are Unix seconds, UTC):
	  id              unique string; creatures with a matching `eventId` only spawn while it is active
	  startsAt/endsAt window
	  luckMultiplier  multiplies conveyor weights of luck-affected rarities (optional, default 1)
	  cashMultiplier  multiplies everyone's income (optional, default 1)
	  bannerText      shown in the HUD while active (optional)
	  durationSeconds used by `/event <id>` when started by an admin (optional, default 1800)
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
