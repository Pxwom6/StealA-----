--!strict
--[[
	Server-wide modifiers: scheduled events (Config/LiveOps), purchased / admin luck boosts, and the cash
	multiplier from events. Current values are mirrored to workspace attributes (LuckMultiplier, LuckEndsAt,
	EventBanner, CashMultiplier) so every client can show them without extra remotes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LiveOps = require(ReplicatedStorage.Shared.Config.LiveOps)
local LiveOpsRules = require(ReplicatedStorage.Shared.Logic.LiveOpsRules)
local Types = require(ReplicatedStorage.Shared.Types)

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

-- Adds (or extends) a luck boost. Boosts from the same source and multiplier stack time, capped.
function LiveOpsService.addLuckBoost(seconds: number, multiplier: number, source: string): LiveOpsRules.Boost
	local now = LiveOpsService.now()
	local existingIndex: number? = nil
	for index, boost in boosts do
		if boost.source == source and boost.multiplier == multiplier and boost.endsAt > now then
			existingIndex = index
			break
		end
	end
	local updated = LiveOpsRules.extendBoost(
		if existingIndex then boosts[existingIndex] else nil,
		now,
		seconds,
		multiplier,
		source,
		LiveOps.limits
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

function LiveOpsService.start()
	LiveOpsService.publishAttributes()
	task.spawn(function()
		while true do
			task.wait(1)
			LiveOpsService.publishAttributes()
		end
	end)
end

return LiveOpsService
