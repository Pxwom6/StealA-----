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

-- What the store shows before someone buys a luck boost (see previewBoost).
export type LuckPreview = {
	before: number,
	after: number,
	extendsOnly: boolean, -- the same boost is already running: buying only adds time, the odds stay the same
}

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

-- The active events with each id counted once: the same event can be listed more than once (scheduled in config,
-- re-listed by remote config, started again with /event), and must never stack with itself. Keeps the order in which
-- each id first appears, and of its active copies the one that ends last.
function LiveOpsRules.distinctActiveEvents(events: { EventDef }, now: number): { EventDef }
	local distinct: { EventDef } = {}
	local indexById: { [string]: number } = {}
	for _, event in LiveOpsRules.activeEvents(events, now) do
		local index = indexById[event.id]
		if index == nil then
			table.insert(distinct, event)
			indexById[event.id] = #distinct
		elseif event.endsAt > distinct[index].endsAt then
			distinct[index] = event
		end
	end
	return distinct
end

-- Product of every active event's luck (each event id once) and every unexpired boost, clamped to [1, max].
function LiveOpsRules.luckMultiplier(events: { EventDef }, boosts: { Boost }, now: number, limits: Limits): number
	local m = 1
	for _, event in LiveOpsRules.distinctActiveEvents(events, now) do
		m *= math.max(1, event.luckMultiplier or 1)
	end
	for _, boost in boosts do
		if now < boost.endsAt then
			m *= math.max(1, boost.multiplier)
		end
	end
	return math.clamp(m, 1, limits.maxLuckMultiplier)
end

-- When the luck multiplier next changes because something feeding it ends: the earliest end among the active luck
-- events (luckMultiplier > 1) and unexpired boosts. 0 when nothing raises the luck. The HUD counts down to this, so
-- a 15-minute bought boost during a two-day luck event shows 15 minutes (then the event's own time), not two days.
function LiveOpsRules.luckChangesAt(events: { EventDef }, boosts: { Boost }, now: number): number
	local earliest = math.huge
	for _, event in LiveOpsRules.distinctActiveEvents(events, now) do
		if (event.luckMultiplier or 1) > 1 then
			earliest = math.min(earliest, event.endsAt)
		end
	end
	for _, boost in boosts do
		if now < boost.endsAt and boost.multiplier > 1 then
			earliest = math.min(earliest, boost.endsAt)
		end
	end
	return if earliest == math.huge then 0 else earliest
end

-- The event whose banner the HUD shows: the first active event (in list order) that has bannerText, or nil. A
-- listed-twice event counts down to its latest end.
function LiveOpsRules.bannerEvent(events: { EventDef }, now: number): EventDef?
	for _, event in LiveOpsRules.distinctActiveEvents(events, now) do
		if event.bannerText ~= nil and event.bannerText ~= "" then
			return event
		end
	end
	return nil
end

-- Product of every active event's cash multiplier (each event id once), clamped to [1, max].
function LiveOpsRules.cashMultiplier(events: { EventDef }, now: number, limits: Limits): number
	local m = 1
	for _, event in LiveOpsRules.distinctActiveEvents(events, now) do
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

-- Adds one boost to `boosts` exactly as the server applies it: a running boost with the same source and multiplier
-- only gains time (extendBoost); otherwise a new boost joins the list. Returns a new list (the input is untouched).
function LiveOpsRules.addBoost(
	boosts: { Boost },
	now: number,
	seconds: number,
	multiplier: number,
	source: string,
	limits: Limits
): { Boost }
	local result = table.clone(boosts)
	for index, boost in result do
		if boost.source == source and boost.multiplier == multiplier and boost.endsAt > now then
			result[index] = LiveOpsRules.extendBoost(boost, now, seconds, multiplier, source, limits)
			return result
		end
	end
	table.insert(result, LiveOpsRules.extendBoost(nil, now, seconds, multiplier, source, limits))
	return result
end

-- When the running boosts from `source` end (0 when none is running).
function LiveOpsRules.boostEndsAt(boosts: { Boost }, source: string, now: number): number
	local endsAt = 0
	for _, boost in boosts do
		if boost.source == source and boost.endsAt > now then
			endsAt = math.max(endsAt, boost.endsAt)
		end
	end
	return endsAt
end

-- The luck before and right after buying a boost of `multiplier`, from what a client can see: the current luck
-- (luckMultiplier) and whether the same boost is already running. Matches addBoost + luckMultiplier exactly: a
-- running boost is only extended, otherwise the new multiplier joins the product, clamped the same way.
function LiveOpsRules.previewBoost(
	currentLuck: number,
	sameBoostRunning: boolean,
	multiplier: number,
	limits: Limits
): LuckPreview
	if sameBoostRunning then
		return { before = currentLuck, after = currentLuck, extendsOnly = true }
	end
	local after = math.clamp(currentLuck * math.max(1, multiplier), 1, limits.maxLuckMultiplier)
	return { before = currentLuck, after = after, extendsOnly = false }
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
			title = if type(entry.title) == "string" and #entry.title > 0 then string.sub(entry.title, 1, 24) else nil,
			durationSeconds = if type(entry.durationSeconds) == "number"
					and entry.durationSeconds == entry.durationSeconds
				then math.clamp(entry.durationSeconds, 60, 7 * 86400)
				else nil,
		})
	end
	return events, problems
end

return LiveOpsRules
