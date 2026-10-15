--!strict
--[[
	Server-wide modifiers: scheduled events (Config/LiveOps), purchased / admin luck boosts, and the cash
	multiplier from events. Current values are mirrored to workspace attributes (LuckMultiplier, LuckEndsAt,
	PurchasedLuckEndsAt, EventBanner, EventBannerId, EventTitle, EventEndsAt, CashMultiplier, ActiveEventIds) so
	every client can show them without extra remotes. Listeners hear when the set of active events changes
	(onActiveEventsChanged; SeasonService switches seasonal themes with it).

	Runtime control without publishing:
	  * remote config: event list JSON in a DataStore entry, re-read every few minutes
	  * admin actions: startLuck, startEvent, endEvents and announce, run by HostService for the host panel and the
	    admin chat commands (/luck, /event <id> [minutes], /event off [id], /announce), in this server or, through
	    CrossServer, every server

	One seasonal-theme event at a time (Config/Seasons; DECISIONS.md #58): whichever started last runs
	(LiveOpsRules.oneSeasonAtATime). Starting one with /event or the host panel ends every other seasonal event an admin
	started, and a scheduled one steps aside until it ends (then it comes back if its dates still say so). Luck and
	cash events overlap anything.
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local LiveOps = require(ReplicatedStorage.Shared.Config.LiveOps)
local Seasons = require(ReplicatedStorage.Shared.Config.Seasons)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local LiveOpsRules = require(ReplicatedStorage.Shared.Logic.LiveOpsRules)
local SeasonRules = require(ReplicatedStorage.Shared.Logic.SeasonRules)
local Types = require(ReplicatedStorage.Shared.Types)
local Announcer = require(script.Parent.Announcer)

local LiveOpsService = {}

-- The source of luck boosts bought with Robux (Server Luck).
LiveOpsService.PURCHASE_SOURCE = "purchase"

-- The events that switch on a seasonal theme: only one of them runs at a time.
local SEASONAL = SeasonRules.seasonalEventIds(Seasons)

local configEvents: { Types.EventDef } = table.clone(LiveOps.events)
local remoteEvents: { Types.EventDef } = {}
local adminEvents: { Types.EventDef } = {}
-- Every event with the seasonal ones cut to one at a time, worked out again whenever a list changes.
local resolved: { Types.EventDef }? = nil
local boosts: { LiveOpsRules.Boost } = {}
local cashListeners: { () -> () } = {}
local lastCashMultiplier = 1
local activeEventListeners: { (ids: { [string]: boolean }) -> () } = {}
local lastActiveIds = ""

function LiveOpsService.now(): number
	return workspace:GetServerTimeNow()
end

-- Whether event `id` switches on a seasonal theme (only one such event runs at a time).
function LiveOpsService.isSeasonal(id: string): boolean
	return SEASONAL[id] == true
end

-- Every event, scheduled (config and remote config) and started by admins, as the rules see it: each seasonal event
-- cut wherever a later one runs (LiveOpsRules.oneSeasonAtATime), so the active ones never include two.
function LiveOpsService.events(): { Types.EventDef }
	if resolved == nil then
		local all: { Types.EventDef } = {}
		for _, list in { configEvents, remoteEvents, adminEvents } do
			for _, event in list do
				table.insert(all, event)
			end
		end
		resolved = LiveOpsRules.oneSeasonAtATime(all, SEASONAL)
	end
	return resolved :: { Types.EventDef }
end

-- The luck belt rolls use: events and every boost (the bought one included; the store card shows these odds).
function LiveOpsService.luckMultiplier(): number
	return LiveOpsRules.luckMultiplier(LiveOpsService.events(), boosts, LiveOpsService.now(), LiveOps.limits)
end

-- The luck prize Snacklings roll at (Lucky Spin, gifts, crates, runaways, Snack Attack, achievements): the same, but
-- without a bought Server Luck boost, whose card never disclosed these odds. Event, admin and modifier luck count.
function LiveOpsService.prizeLuckMultiplier(): number
	return LiveOpsRules.luckMultiplier(
		LiveOpsService.events(),
		boosts,
		LiveOpsService.now(),
		LiveOps.limits,
		LiveOpsService.PURCHASE_SOURCE
	)
end

function LiveOpsService.cashMultiplier(): number
	return LiveOpsRules.cashMultiplier(LiveOpsService.events(), LiveOpsService.now(), LiveOps.limits)
end

function LiveOpsService.activeEventIds(): { [string]: boolean }
	return LiveOpsRules.activeEventIds(LiveOpsService.events(), LiveOpsService.now())
end

-- Adds (or extends) a luck boost. Boosts from the same source and multiplier stack time, capped at
-- LiveOps.limits.maxBoostSeconds of remaining time — unless `uncapped` (paid boosts: a receipt must always deliver
-- its full duration; the store stops offering the product near the cap instead, see StoreController's `luckMaxed`).
-- Uses Logic/LiveOpsRules.addBoost, the same rule the store's odds preview is tested against.
function LiveOpsService.addLuckBoost(seconds: number, multiplier: number, source: string, uncapped: boolean?)
	LiveOpsService.setBoosts(LiveOpsService.boostsWith(seconds, multiplier, source, uncapped))
	LiveOpsService.publishAttributes()
end

-- The boost list with one more boost added (see addLuckBoost), without applying it. Receipts compute this first and
-- apply it with setBoosts in their non-failing step.
function LiveOpsService.boostsWith(
	seconds: number,
	multiplier: number,
	source: string,
	uncapped: boolean?
): { LiveOpsRules.Boost }
	local limits = LiveOps.limits
	if uncapped then
		limits = table.clone(LiveOps.limits)
		limits.maxBoostSeconds = math.huge
	end
	return LiveOpsRules.addBoost(boosts, LiveOpsService.now(), seconds, multiplier, source, limits)
end

-- Replaces the boost list (plain assignment; attributes catch up on the next publish, at most 1 s later).
function LiveOpsService.setBoosts(list: { LiveOpsRules.Boost })
	boosts = list
end

-- Ends every running boost from `source` now (e.g. "modifier" when a server modifier is switched off early).
function LiveOpsService.endBoosts(source: string)
	local kept: { LiveOpsRules.Boost } = {}
	for _, boost in boosts do
		if boost.source ~= source then
			table.insert(kept, boost)
		end
	end
	boosts = kept
	LiveOpsService.publishAttributes()
end

-- Starts a configured (or ad-hoc) event right now for `seconds`. If that event id is already running (scheduled,
-- remote config, or started earlier), this only extends it: it ends at the later of its current end and now +
-- `seconds`, never sooner, and never runs twice (the rules count each event id once, LiveOpsRules.distinctActiveEvents).
-- Use `/event off` first to shorten an event started this way. A seasonal-theme event ends every other one: those an
-- admin started are gone for good, and a scheduled one steps aside while this one runs (LiveOpsRules.oneSeasonAtATime).
-- Returns the ids of the seasonal events that were running and no longer are (sorted).
function LiveOpsService.startEventNow(event: Types.EventDef, seconds: number): { string }
	local now = LiveOpsService.now()
	local before = LiveOpsService.activeEventIds()
	local seasonal = LiveOpsService.isSeasonal(event.id)
	-- the other seasonal events an admin started end first, so they never stretch this one
	local kept: { Types.EventDef } = {}
	for _, running in adminEvents do
		if running.id == event.id or not (seasonal and LiveOpsService.isSeasonal(running.id)) then
			table.insert(kept, running)
		end
	end
	adminEvents = kept
	resolved = nil
	local endsAt = now + seconds
	for _, running in LiveOpsRules.activeEvents(LiveOpsService.events(), now) do
		if running.id == event.id then
			endsAt = math.max(endsAt, running.endsAt)
		end
	end
	local copy = table.clone(event)
	copy.startsAt = now
	copy.endsAt = endsAt
	kept = {}
	for _, running in adminEvents do
		if running.id ~= event.id then
			table.insert(kept, running)
		end
	end
	table.insert(kept, copy)
	adminEvents = kept
	resolved = nil
	local after = LiveOpsService.activeEventIds()
	local ended: { string } = {}
	for id in before do
		if id ~= event.id and not after[id] and LiveOpsService.isSeasonal(id) then
			table.insert(ended, id)
		end
	end
	table.sort(ended)
	LiveOpsService.publishAttributes()
	return ended
end

-- Ends events started with /event (startEventNow): every one, or only those with `id`. Scheduled (config and
-- remote-config) events are not affected: change their dates to end them (a scheduled seasonal event an admin's had
-- taken over from comes back as soon as that one ends). Returns how many were ended.
function LiveOpsService.endStartedEvents(id: string?): number
	local kept: { Types.EventDef } = {}
	for _, event in adminEvents do
		if id ~= nil and event.id ~= id then
			table.insert(kept, event)
		end
	end
	local ended = #adminEvents - #kept
	adminEvents = kept
	resolved = nil
	LiveOpsService.publishAttributes()
	return ended
end

function LiveOpsService.setRemoteEvents(events: { Types.EventDef })
	remoteEvents = events
	resolved = nil
	LiveOpsService.publishAttributes()
end

-- The events started with /event (a copy), and putting such a list back: the Studio self-test switches every seasonal
-- event on in turn, which ends any an admin had started, and leaves the session as it found it with these.
function LiveOpsService.startedEvents(): { Types.EventDef }
	return table.clone(adminEvents)
end

function LiveOpsService.restoreStartedEvents(events: { Types.EventDef })
	adminEvents = table.clone(events)
	resolved = nil
	LiveOpsService.publishAttributes()
end

function LiveOpsService.findConfiguredEvent(id: string): Types.EventDef?
	for _, event in configEvents do
		if event.id == id then
			return event
		end
	end
	for _, event in remoteEvents do
		if event.id == id then
			return event
		end
	end
	return nil
end

function LiveOpsService.onCashMultiplierChanged(listener: () -> ())
	table.insert(cashListeners, listener)
end

-- Calls `listener` with the active event ids whenever that set changes: an event starts or ends by its dates (checked
-- every second), arrives with remote config, or is started / ended by an admin command. Listeners should also read
-- activeEventIds() once when they start, for the events already running.
function LiveOpsService.onActiveEventsChanged(listener: (ids: { [string]: boolean }) -> ())
	table.insert(activeEventListeners, listener)
end

function LiveOpsService.publishAttributes()
	local now = LiveOpsService.now()
	boosts = LiveOpsRules.pruneBoosts(boosts, now)
	local events = LiveOpsService.events()
	local luck = LiveOpsService.luckMultiplier()
	workspace:SetAttribute("PurchasedLuckEndsAt", LiveOpsRules.boostEndsAt(boosts, LiveOpsService.PURCHASE_SOURCE, now))
	workspace:SetAttribute("LuckMultiplier", luck)
	-- When the luck shown next changes (a boost or luck event ends), not when the last one ends.
	workspace:SetAttribute(
		"LuckEndsAt",
		if luck > 1 then LiveOpsRules.luckChangesAt(events, boosts, now, LiveOps.limits) else 0
	)
	-- The HUD event pill: banner text, which event it belongs to (theme colour), its title and end for the countdown.
	local bannerEvent = LiveOpsRules.bannerEvent(events, now)
	workspace:SetAttribute("EventBanner", if bannerEvent then bannerEvent.bannerText else "")
	workspace:SetAttribute("EventBannerId", if bannerEvent then bannerEvent.id else "")
	workspace:SetAttribute("EventTitle", if bannerEvent then bannerEvent.title or "" else "")
	workspace:SetAttribute("EventEndsAt", if bannerEvent then bannerEvent.endsAt else 0)
	local activeIds: { string } = {}
	for id in LiveOpsService.activeEventIds() do
		table.insert(activeIds, id)
	end
	table.sort(activeIds)
	local activeKey = table.concat(activeIds, ",")
	workspace:SetAttribute("ActiveEventIds", activeKey)
	if activeKey ~= lastActiveIds then
		lastActiveIds = activeKey
		for _, listener in activeEventListeners do
			task.spawn(listener, LiveOpsService.activeEventIds())
		end
	end

	local cash = LiveOpsService.cashMultiplier()
	workspace:SetAttribute("CashMultiplier", cash)
	if cash ~= lastCashMultiplier then
		lastCashMultiplier = cash
		for _, listener in cashListeners do
			task.spawn(listener)
		end
	end
end

-- Remote config ------------------------------------------------------------------------------------------------

local function loadRemoteConfig()
	local cfg = LiveOps.remoteConfig
	local ok, raw = pcall(function(): any
		return DataStoreService:GetDataStore(cfg.dataStoreName):GetAsync(cfg.key)
	end)
	if not ok or raw == nil then
		return
	end
	local decoded: any = raw
	if type(raw) == "string" then
		local decodeOk, value = pcall(function(): any
			return HttpService:JSONDecode(raw)
		end)
		if not decodeOk then
			warn("[LiveOps] remote config is not valid JSON")
			return
		end
		decoded = value
	end
	local events, problems = LiveOpsRules.validateEvents(decoded, LiveOps.limits)
	for _, problem in problems do
		warn(`[LiveOps] remote config: {problem}`)
	end
	LiveOpsService.setRemoteEvents(events)
end

-- Admin actions (HostService: the host panel and the admin chat commands) ------------------------------------------

-- Every configured event id (Config/LiveOps and remote config): the events an admin may start or end.
function LiveOpsService.configuredEventIds(): { [string]: boolean }
	local ids: { [string]: boolean } = {}
	for _, list in { configEvents, remoteEvents } do
		for _, event in list do
			ids[event.id] = true
		end
	end
	return ids
end

-- An admin luck boost: `multiplier`x luck for `minutes` (already clamped by HostRules), with its banner.
function LiveOpsService.startLuck(multiplier: number, minutes: number)
	LiveOpsService.addLuckBoost(minutes * 60, multiplier, "admin")
	Announcer.broadcast({
		text = Format.template(Theme.text.adminLuck, { multiplier = multiplier, minutes = minutes }),
		rarity = "Legendary",
		kind = "luck",
	})
end

-- Starts configured event `id` now, for `minutes` or else its own durationSeconds (30 minutes without one), with
-- its banner; a seasonal one ends any other seasonal event that was running (startEventNow). Returns false when no
-- event has that id, else true and the ids of the seasonal events it ended.
function LiveOpsService.startEvent(id: string, minutes: number?): (boolean, { string })
	local event = LiveOpsService.findConfiguredEvent(id)
	if event == nil then
		return false, {}
	end
	local seconds = if minutes then minutes * 60 else event.durationSeconds or 1800
	local ended = LiveOpsService.startEventNow(event, seconds)
	print(`[LiveOps] {event.id} running for at least {seconds // 60} min`)
	if #ended > 0 then
		print(`[LiveOps] one seasonal event at a time: {table.concat(ended, ", ")} ended`)
	end
	if event.bannerText then
		Announcer.broadcast({ text = event.bannerText, rarity = "Mythic", kind = "admin" })
	end
	return true, ended
end

-- Ends events started by an admin (every one, or only `id`); returns how many.
function LiveOpsService.endEvents(id: string?): number
	local ended = LiveOpsService.endStartedEvents(id)
	print(`[LiveOps] ended {ended} started event(s)`)
	return ended
end

-- A banner for everyone. `text` must already be filtered (filterForBroadcast).
function LiveOpsService.announce(text: string)
	Announcer.broadcast({ text = text, kind = "admin" })
end

-- `text` as Roblox's filter lets everyone see it, or nil when the filter can't be reached. Text shown to every player
-- goes through it, even from admins. Yields.
function LiveOpsService.filterForBroadcast(text: string, fromUserId: number): string?
	local ok, result = pcall(function(): string
		return TextService:FilterStringAsync(text, fromUserId):GetNonChatStringForBroadcastAsync()
	end)
	return if ok then result else nil
end

function LiveOpsService.start()
	LiveOpsService.publishAttributes()
	-- One error must not stop events starting and ending (or remote config) for good: each body runs protected.
	task.spawn(function()
		while true do
			task.wait(1)
			local ok, err = pcall(LiveOpsService.publishAttributes :: () -> ...any)
			if not ok then
				warn(`[LiveOps] {err}`)
			end
		end
	end)
	if LiveOps.remoteConfig.enabled then
		task.spawn(function()
			while true do
				local ok, err = pcall(loadRemoteConfig :: () -> ...any)
				if not ok then
					warn(`[LiveOps] remote config: {err}`)
				end
				task.wait(LiveOps.remoteConfig.refreshSeconds)
			end
		end)
	end
end

return LiveOpsService
