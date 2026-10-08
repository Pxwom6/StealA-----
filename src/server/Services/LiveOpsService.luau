--!strict
--[[
	Server-wide modifiers: scheduled events (Config/LiveOps), purchased / admin luck boosts, and the cash
	multiplier from events. Current values are mirrored to workspace attributes (LuckMultiplier, LuckEndsAt,
	EventBanner, CashMultiplier, ActiveEventIds) so every client can show them without extra remotes.

	Runtime control without publishing:
	  * remote config: event list JSON in a DataStore entry, re-read every few minutes
	  * admin chat commands (/luck, /event, /announce), broadcast to every server with MessagingService
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
-- its full duration; the store stops offering the product near the cap instead, see `purchasedLuckRemaining`).
function LiveOpsService.addLuckBoost(
	seconds: number,
	multiplier: number,
	source: string,
	uncapped: boolean?
): LiveOpsRules.Boost
	local now = LiveOpsService.now()
	local existingIndex: number? = nil
	for index, boost in boosts do
		if boost.source == source and boost.multiplier == multiplier and boost.endsAt > now then
			existingIndex = index
			break
		end
	end
	local limits = LiveOps.limits
	if uncapped then
		limits = table.clone(LiveOps.limits)
		limits.maxBoostSeconds = math.huge
	end
	local updated = LiveOpsRules.extendBoost(
		if existingIndex then boosts[existingIndex] else nil,
		now,
		seconds,
		multiplier,
		source,
		limits
	)
	if existingIndex then
		boosts[existingIndex] = updated
	else
		table.insert(boosts, updated)
	end
	LiveOpsService.publishAttributes()
	return updated
end

-- Starts a configured (or ad-hoc) event right now for `seconds`.
function LiveOpsService.startEventNow(event: Types.EventDef, seconds: number)
	local now = os.time()
	local copy = table.clone(event)
	copy.startsAt = now
	copy.endsAt = now + seconds
	table.insert(adminEvents, copy)
	LiveOpsService.publishAttributes()
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

function LiveOpsService.publishAttributes()
	local now = LiveOpsService.now()
	boosts = LiveOpsRules.pruneBoosts(boosts, now)
	local luck = LiveOpsService.luckMultiplier()
	local luckEndsAt = 0
	for _, boost in boosts do
		luckEndsAt = math.max(luckEndsAt, boost.endsAt)
	end
	local banner = ""
	for _, event in LiveOpsRules.activeEvents(LiveOpsService.events(), now) do
		if (event.luckMultiplier or 1) > 1 then
			luckEndsAt = math.max(luckEndsAt, event.endsAt)
		end
		if banner == "" and event.bannerText then
			banner = event.bannerText
		end
	end
	local purchasedEndsAt = 0
	for _, boost in boosts do
		if boost.source == "purchase" then
			purchasedEndsAt = math.max(purchasedEndsAt, boost.endsAt)
		end
	end
	workspace:SetAttribute("PurchasedLuckEndsAt", purchasedEndsAt)
	workspace:SetAttribute("LuckMultiplier", luck)
	workspace:SetAttribute("LuckEndsAt", if luck > 1 then luckEndsAt else 0)
	workspace:SetAttribute("EventBanner", banner)
	local activeIds: { string } = {}
	for id in LiveOpsService.activeEventIds() do
		table.insert(activeIds, id)
	end
	table.sort(activeIds)
	workspace:SetAttribute("ActiveEventIds", table.concat(activeIds, ","))

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

local function applyCommand(command: Command)
	if command.kind == "luck" then
		local multiplier = math.clamp(command.multiplier or 2, 1, LiveOps.limits.maxLuckMultiplier)
		local minutes = math.clamp(command.minutes or 15, 1, 24 * 60)
		LiveOpsService.addLuckBoost(minutes * 60, multiplier, "admin")
		Announcer.broadcast({ text = `{multiplier}x LUCK for {minutes} minutes!`, rarity = "Legendary", kind = "luck" })
	elseif command.kind == "event" and command.eventId then
		local event = LiveOpsService.findConfiguredEvent(command.eventId)
		if event then
			LiveOpsService.startEventNow(event, event.durationSeconds or 1800)
			if event.bannerText then
				Announcer.broadcast({ text = event.bannerText, rarity = "Mythic", kind = "admin" })
			end
		end
	elseif command.kind == "announce" and command.text then
		Announcer.broadcast({ text = command.text, kind = "admin" })
	end
end

-- Publishes to every server (including this one); falls back to applying locally (e.g. in Studio).
local function broadcastCommand(command: Command)
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

local function startAdminTools()
	pcall(function()
		MessagingService:SubscribeAsync(LiveOps.messagingTopic, function(message: any)
			local ok, decoded = pcall(function(): any
				return HttpService:JSONDecode(message.Data)
			end)
			if ok and type(decoded) == "table" and type(decoded.kind) == "string" then
				applyCommand(decoded :: Command)
			end
		end)
	end)

	addCommand("luck", function(_userId: number, args: { string })
		broadcastCommand({ kind = "luck", multiplier = tonumber(args[1]), minutes = tonumber(args[2]) })
	end)
	addCommand("event", function(_userId: number, args: { string })
		if args[1] then
			broadcastCommand({ kind = "event", eventId = args[1] })
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
