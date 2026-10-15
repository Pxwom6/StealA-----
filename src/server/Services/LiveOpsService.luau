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
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local LiveOps = require(ReplicatedStorage.Shared.Config.LiveOps)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local LiveOpsRules = require(ReplicatedStorage.Shared.Logic.LiveOpsRules)
local Types = require(ReplicatedStorage.Shared.Types)
local Announcer = require(script.Parent.Announcer)

local LiveOpsService = {}

local configEvents: { Types.EventDef } = table.clone(LiveOps.events)
local remoteEvents: { Types.EventDef } = {}
local adminEvents: { Types.EventDef } = {}
local boosts: { LiveOpsRules.Boost } = {}
local cashListeners: { () -> () } = {}
local lastCashMultiplier = 1
local activeEventListeners: { (ids: { [string]: boolean }) -> () } = {}
local lastActiveIds = ""

function LiveOpsService.now(): number
	return workspace:GetServerTimeNow()
end

function LiveOpsService.events(): { Types.EventDef }
	local all: { Types.EventDef } = {}
	for _, list in { configEvents, remoteEvents, adminEvents } do
		for _, event in list do
			table.insert(all, event)
		end
	end
	return all
end

function LiveOpsService.luckMultiplier(): number
	return LiveOpsRules.luckMultiplier(LiveOpsService.events(), boosts, LiveOpsService.now(), LiveOps.limits)
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
-- Use `/event off` first to shorten an event started this way.
function LiveOpsService.startEventNow(event: Types.EventDef, seconds: number)
	local now = LiveOpsService.now()
	local endsAt = now + seconds
	for _, running in LiveOpsRules.activeEvents(LiveOpsService.events(), now) do
		if running.id == event.id then
			endsAt = math.max(endsAt, running.endsAt)
		end
	end
	local copy = table.clone(event)
	copy.startsAt = now
	copy.endsAt = endsAt
	local kept: { Types.EventDef } = {}
	for _, running in adminEvents do
		if running.id ~= event.id then
			table.insert(kept, running)
		end
	end
	table.insert(kept, copy)
	adminEvents = kept
	LiveOpsService.publishAttributes()
end

-- Ends events started with /event (startEventNow): every one, or only those with `id`. Scheduled (config and
-- remote-config) events are not affected: change their dates to end them. Returns how many were ended.
function LiveOpsService.endStartedEvents(id: string?): number
	local kept: { Types.EventDef } = {}
	for _, event in adminEvents do
		if id ~= nil and event.id ~= id then
			table.insert(kept, event)
		end
	end
	local ended = #adminEvents - #kept
	adminEvents = kept
	LiveOpsService.publishAttributes()
	return ended
end

function LiveOpsService.setRemoteEvents(events: { Types.EventDef })
	remoteEvents = events
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
	workspace:SetAttribute("PurchasedLuckEndsAt", LiveOpsRules.boostEndsAt(boosts, "purchase", now))
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
-- its banner. Returns false when no event has that id.
function LiveOpsService.startEvent(id: string, minutes: number?): boolean
	local event = LiveOpsService.findConfiguredEvent(id)
	if event == nil then
		return false
	end
	local seconds = if minutes then minutes * 60 else event.durationSeconds or 1800
	LiveOpsService.startEventNow(event, seconds)
	print(`[LiveOps] {event.id} running for at least {seconds // 60} min`)
	if event.bannerText then
		Announcer.broadcast({ text = event.bannerText, rarity = "Mythic", kind = "admin" })
	end
	return true
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
	task.spawn(function()
		while true do
			task.wait(1)
			LiveOpsService.publishAttributes()
		end
	end)
	if LiveOps.remoteConfig.enabled then
		task.spawn(function()
			while true do
				loadRemoteConfig()
				task.wait(LiveOps.remoteConfig.refreshSeconds)
			end
		end)
	end
end

return LiveOpsService
