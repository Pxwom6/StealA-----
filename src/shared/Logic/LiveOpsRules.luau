--!strict
--[[
	LiveOps rules: which events are active, combined luck / cash multipliers, luck-boost stacking, and validation
	of remotely edited event config (it comes from a DataStore a human edits, so treat it as untrusted).
	Pure: no Roblox APIs.
]]

local Types = require("../Types")

export type EventDef = Types.EventDef

export type Boost = {
	multiplier: number,
	endsAt: number,
	source: string,
}

export type Limits = { maxLuckMultiplier: number, maxCashMultiplier: number, maxBoostSeconds: number }

local LiveOpsRules = {}

local function isActive(event: EventDef, now: number): boolean
	return now >= event.startsAt and now < event.endsAt
end

function LiveOpsRules.activeEvents(events: { EventDef }, now: number): { EventDef }
	local active: { EventDef } = {}
	for _, event in events do
		if isActive(event, now) then
			table.insert(active, event)
		end
	end
	return active
end

function LiveOpsRules.activeEventIds(events: { EventDef }, now: number): { [string]: boolean }
	local ids: { [string]: boolean } = {}
	for _, event in LiveOpsRules.activeEvents(events, now) do
		ids[event.id] = true
	end
	return ids
end

-- Product of every active event's luck and every unexpired boost, clamped to [1, max].
function LiveOpsRules.luckMultiplier(events: { EventDef }, boosts: { Boost }, now: number, limits: Limits): number
	local m = 1
	for _, event in LiveOpsRules.activeEvents(events, now) do
		m *= math.max(1, event.luckMultiplier or 1)
	end
	for _, boost in boosts do
		if now < boost.endsAt then
			m *= math.max(1, boost.multiplier)
		end
	end
	return math.clamp(m, 1, limits.maxLuckMultiplier)
end

function LiveOpsRules.cashMultiplier(events: { EventDef }, now: number, limits: Limits): number
	local m = 1
	for _, event in LiveOpsRules.activeEvents(events, now) do
		m *= math.max(1, event.cashMultiplier or 1)
	end
	return math.clamp(m, 1, limits.maxCashMultiplier)
end

-- Adds `seconds` of a boost. Buying the same boost again extends it (never multiplies it), capped so at most
-- `maxBoostSeconds` remain. Returns the updated boost.
function LiveOpsRules.extendBoost(
	current: Boost?,
	now: number,
	seconds: number,
	multiplier: number,
	source: string,
	limits: Limits
): Boost
	local base = now
	if current ~= nil and current.endsAt > now and current.multiplier == multiplier then
		base = current.endsAt
	end
	local endsAt = math.min(base + seconds, now + limits.maxBoostSeconds)
	return { multiplier = multiplier, endsAt = endsAt, source = source }
end

-- Longest remaining boost (for the HUD). Returns multiplier and seconds left (0 when none).
function LiveOpsRules.strongestBoost(boosts: { Boost }, now: number): (number, number)
	local bestMultiplier, bestRemaining = 1, 0
	for _, boost in boosts do
		local remaining = boost.endsAt - now
		if
			remaining > 0
			and (
				boost.multiplier > bestMultiplier or (boost.multiplier == bestMultiplier and remaining > bestRemaining)
			)
		then
			bestMultiplier, bestRemaining = boost.multiplier, remaining
		end
	end
	return bestMultiplier, bestRemaining
end

function LiveOpsRules.pruneBoosts(boosts: { Boost }, now: number): { Boost }
	local kept: { Boost } = {}
	for _, boost in boosts do
		if now < boost.endsAt then
			table.insert(kept, boost)
		end
	end
	return kept
end

-- Validates untrusted event config (decoded JSON). Invalid entries are dropped and reported.
function LiveOpsRules.validateEvents(raw: unknown, limits: Limits): ({ EventDef }, { string })
	local events: { EventDef } = {}
	local problems: { string } = {}
	if type(raw) ~= "table" then
		table.insert(problems, "config is not a list")
		return events, problems
	end
	for index, entry in raw :: { [any]: any } do
		if type(entry) ~= "table" then
			table.insert(problems, `entry {tostring(index)} is not a table`)
			continue
		end
		local id, startsAt, endsAt = entry.id, entry.startsAt, entry.endsAt
		if type(id) ~= "string" or #id == 0 or #id > 64 then
			table.insert(problems, `entry {tostring(index)} has a bad id`)
			continue
		end
		if
			type(startsAt) ~= "number"
			or type(endsAt) ~= "number"
			or startsAt ~= startsAt
			or endsAt ~= endsAt
			or endsAt <= startsAt
		then
			table.insert(problems, `event {id} has a bad time window`)
			continue
		end
		local function multiplier(value: unknown, max: number): number?
			if value == nil then
				return nil
			end
			if type(value) ~= "number" or value ~= value then
				return 1
			end
			return math.clamp(value, 1, max)
		end
		table.insert(events, {
			id = id,
			startsAt = startsAt,
			endsAt = endsAt,
			luckMultiplier = multiplier(entry.luckMultiplier, limits.maxLuckMultiplier),
			cashMultiplier = multiplier(entry.cashMultiplier, limits.maxCashMultiplier),
			bannerText = if type(entry.bannerText) == "string" then string.sub(entry.bannerText, 1, 80) else nil,
			durationSeconds = if type(entry.durationSeconds) == "number"
					and entry.durationSeconds == entry.durationSeconds
				then math.clamp(entry.durationSeconds, 60, 7 * 86400)
				else nil,
		})
	end
	return events, problems
end

return LiveOpsRules
