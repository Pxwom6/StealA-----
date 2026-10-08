--!strict
--[[
	Rules for stealing and defending. The server gathers facts (positions, timers, ownership) and asks these
	functions for a verdict, so every rule is unit-tested without Studio. Pure: no requires, no Roblox APIs.
]]

export type GrabContext = {
	now: number,
	thiefUserId: number,
	ownerUserId: number,
	thiefCarrying: boolean,
	thiefCooldownUntil: number,
	baseLocked: boolean,
	ownerGraceUntil: number,
	creaturePresent: boolean,
	creatureBusy: boolean, -- already being carried by someone
	distance: number,
	grabRange: number,
	thiefHasFreePodium: boolean,
	holdStartedAt: number?, -- when the thief began holding the prompt (server time), nil if never
	holdSeconds: number,
	holdTolerance: number,
}

export type TagContext = {
	now: number,
	taggerUserId: number,
	thiefUserId: number,
	thiefCarrying: boolean,
	distance: number,
	tagRange: number,
	taggerCooldownUntil: number,
}

export type Rect = { minX: number, maxX: number, minZ: number, maxZ: number }

local StealRules = {}

-- Order matters: the first failing reason is what the player is told.
function StealRules.canGrab(ctx: GrabContext): (boolean, string?)
	if ctx.thiefUserId == ctx.ownerUserId then
		return false, "own"
	end
	if ctx.ownerUserId <= 0 then
		return false, "empty"
	end
	if ctx.thiefCarrying then
		return false, "carrying"
	end
	if ctx.now < ctx.thiefCooldownUntil then
		return false, "cooldown"
	end
	if ctx.baseLocked then
		return false, "locked"
	end
	if ctx.now < ctx.ownerGraceUntil then
		return false, "protected"
	end
	if not ctx.creaturePresent then
		return false, "empty"
	end
	if ctx.creatureBusy then
		return false, "busy"
	end
	if not (ctx.distance <= ctx.grabRange) then
		return false, "far"
	end
	if not ctx.thiefHasFreePodium then
		return false, "full"
	end
	local started = ctx.holdStartedAt
	if started == nil or ctx.now - started < ctx.holdSeconds * ctx.holdTolerance then
		return false, "hold"
	end
	return true, nil
end

function StealRules.canTag(ctx: TagContext): (boolean, string?)
	if ctx.taggerUserId == ctx.thiefUserId then
		return false, "self"
	end
	if not ctx.thiefCarrying then
		return false, "not_carrying"
	end
	if ctx.now < ctx.taggerCooldownUntil then
		return false, "cooldown"
	end
	if not (ctx.distance <= ctx.tagRange) then
		return false, "far"
	end
	return true, nil
end

-- Server-side speed sanity check while carrying (character physics is client-owned, so a speed exploit would
-- otherwise make stealing trivial). `distance` is horizontal studs moved in `dt` seconds.
function StealRules.isMovementPlausible(
	distance: number,
	dt: number,
	maxSpeed: number,
	tolerance: number,
	leeway: number
): boolean
	if distance ~= distance then
		return false
	end
	if dt <= 0 then
		return distance <= leeway
	end
	return distance <= maxSpeed * dt * tolerance + leeway
end

function StealRules.isCarryExpired(startedAt: number, now: number, timeoutSeconds: number): boolean
	return now - startedAt >= timeoutSeconds
end

function StealRules.isInsideRect(x: number, z: number, rect: Rect): boolean
	return x >= rect.minX and x <= rect.maxX and z >= rect.minZ and z <= rect.maxZ
end

-- Grace (new-player protection) end time, from total play time so far. Rejoining doesn't reset it.
function StealRules.graceUntil(now: number, playTimeSeconds: number, graceSeconds: number): number
	local remaining = graceSeconds - math.max(0, playTimeSeconds)
	if remaining <= 0 then
		return 0
	end
	return now + remaining
end

-- Friendly message key for a refusal reason (keys are in Config/Theme.text).
function StealRules.messageKey(reason: string): string?
	local map: { [string]: string } = {
		own = "cantStealOwn",
		carrying = "alreadyCarrying",
		cooldown = "stealCooldown",
		locked = "cantStealLocked",
		protected = "cantStealProtected",
		far = "tooFar",
		full = "baseFull",
	}
	return map[reason]
end

return StealRules
