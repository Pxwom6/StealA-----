--!strict
--[[
	Server-wide modifiers: scheduled events (Config/LiveOps), purchased / admin luck boosts, and the cash
	multiplier from events. Current values are mirrored to workspace attributes (LuckMultiplier, LuckEndsAt,
	PurchasedLuckEndsAt, EventBanner, EventBannerId, EventTitle, EventEndsAt, CashMultiplier, ActiveEventIds) so
	every client can show them without extra remotes. Listeners hear when the set of active events changes
	(onActiveEventsChanged; SeasonService switches seasonal themes with it).

	Runtime control without publishing:
	  * remote config: event list JSON in a DataStore entry, re-read every few minutes
	  * admin chat commands (/luck, /event <id> [minutes], /event off [id], /announce), broadcast to every server
	    with MessagingService. In Studio anyone may use them and they apply to that Studio session only.
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local MessagingService = game:GetService("MessagingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local TextService = game:GetService("TextService")

local LiveOps = require(ReplicatedStorage.Shared.Config.LiveOps)
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
	workspace:SetAttribute("LuckEndsAt", if luck > 1 then LiveOpsRules.luckChangesAt(events, boosts, now) else 0)
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

-- Admin commands -----------------------------------------------------------------------------------------------

type Command = { kind: string, multiplier: number?, minutes: number?, eventId: string?, text: string? }

local MAX_EVENT_MINUTES = 7 * 24 * 60

local function applyCommand(command: Command)
	if command.kind == "luck" then
		local multiplier = math.clamp(command.multiplier or 2, 1, LiveOps.limits.maxLuckMultiplier)
		local minutes = math.clamp(command.minutes or 15, 1, 24 * 60)
		LiveOpsService.addLuckBoost(minutes * 60, multiplier, "admin")
		Announcer.broadcast({ text = `{multiplier}x LUCK for {minutes} minutes!`, rarity = "Legendary", kind = "luck" })
	elseif command.kind == "event" and command.eventId then
		local event = LiveOpsService.findConfiguredEvent(command.eventId)
		if event then
			local seconds = if type(command.minutes) == "number" and command.minutes == command.minutes
				then math.clamp(math.floor(command.minutes), 1, MAX_EVENT_MINUTES) * 60
				else event.durationSeconds or 1800
			LiveOpsService.startEventNow(event, seconds)
			print(`[LiveOps] /event: {event.id} running for at least {seconds // 60} min`)
			if event.bannerText then
				Announcer.broadcast({ text = event.bannerText, rarity = "Mythic", kind = "admin" })
			end
		else
			warn(`[LiveOps] /event: no configured event "{command.eventId}"`)
		end
	elseif command.kind == "eventOff" then
		local ended = LiveOpsService.endStartedEvents(command.eventId)
		print(`[LiveOps] /event off: ended {ended} started event(s)`)
	elseif command.kind == "announce" and command.text then
		Announcer.broadcast({ text = command.text, kind = "admin" })
	end
end

-- Publishes to every server (including this one); falls back to applying locally if publishing fails. In Studio a
-- command only ever applies to the Studio session: anyone may use the commands there (isAdmin), and with Studio API
-- access on, publishing would reach every live server.
local function broadcastCommand(command: Command)
	if RunService:IsStudio() then
		applyCommand(command)
		return
	end
	local ok = pcall(function()
		MessagingService:PublishAsync(LiveOps.messagingTopic, HttpService:JSONEncode(command))
	end)
	if not ok then
		applyCommand(command)
	end
end

local function isAdmin(userId: number): boolean
	return RunService:IsStudio() or table.find(LiveOps.adminUserIds, userId) ~= nil
end

local function filterForBroadcast(text: string, fromUserId: number): string?
	local ok, result = pcall(function(): string
		return TextService:FilterStringAsync(text, fromUserId):GetNonChatStringForBroadcastAsync()
	end)
	return if ok then result else nil
end

local function addCommand(alias: string, handler: (userId: number, args: { string }, rawArgs: string) -> ())
	local command = Instance.new("TextChatCommand")
	command.Name = "LiveOps" .. alias
	command.PrimaryAlias = "/" .. alias
	command.AutocompleteVisible = false
	command.Parent = TextChatService
	command.Triggered:Connect(function(source: TextSource, text: string)
		if not isAdmin(source.UserId) then
			return
		end
		local rawArgs = string.match(text, "^%S+%s*(.*)$") or ""
		local args: { string } = {}
		for word in string.gmatch(rawArgs, "%S+") do
			table.insert(args, word)
		end
		handler(source.UserId, args, rawArgs)
	end)
end

-- Subscribes to admin commands from other servers. MessagingService can fail (limits, outages; in Studio it is
-- usually unavailable), so keep retrying with a growing delay (5 s, 10 s, ... capped at 60 s) until it works. Only
-- the first failure warns; the retries are quiet, so a Studio session's output isn't flooded once a minute.
local function subscribeToCommands()
	local attempt = 0
	while true do
		attempt += 1
		local ok, err = pcall(function()
			MessagingService:SubscribeAsync(LiveOps.messagingTopic, function(message: any)
				local decodeOk, decoded = pcall(function(): any
					return HttpService:JSONDecode(message.Data)
				end)
				if decodeOk and type(decoded) == "table" and type(decoded.kind) == "string" then
					applyCommand(decoded :: Command)
				end
			end)
		end)
		if ok then
			if attempt > 1 then
				print(`[LiveOps] subscribed to admin commands after {attempt} attempts`)
			end
			return
		end
		if attempt == 1 then
			warn(`[LiveOps] could not subscribe to admin commands, retrying quietly in the background: {err}`)
		end
		task.wait(math.min(60, 5 * 2 ^ (attempt - 1)))
	end
end

local function startAdminTools()
	task.spawn(subscribeToCommands)

	addCommand("luck", function(_userId: number, args: { string })
		broadcastCommand({ kind = "luck", multiplier = tonumber(args[1]), minutes = tonumber(args[2]) })
	end)
	-- /event <eventId> [minutes]   start a configured event now (for its durationSeconds, or `minutes`)
	-- /event off [eventId]         end the events started this way (all of them, or just that one)
	addCommand("event", function(_userId: number, args: { string })
		local first = args[1]
		if first == nil or #first > 64 then
			return
		end
		if string.lower(first) == "off" then
			local id = args[2]
			if id and #id > 64 then
				return
			end
			broadcastCommand({ kind = "eventOff", eventId = id })
		else
			broadcastCommand({ kind = "event", eventId = first, minutes = tonumber(args[2]) })
		end
	end)
	addCommand("announce", function(userId: number, _args: { string }, rawArgs: string)
		local text = string.sub(rawArgs, 1, 120)
		if #text == 0 then
			return
		end
		-- Text shown to every player must go through Roblox filtering, even from admins.
		local filtered = filterForBroadcast(text, userId)
		if filtered then
			broadcastCommand({ kind = "announce", text = filtered })
		end
	end)
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
	startAdminTools()
end

return LiveOpsService
