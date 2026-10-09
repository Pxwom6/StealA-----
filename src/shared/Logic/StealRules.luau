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
	thiefInsideBase: boolean, -- no grabbing through walls: the thief must be inside the victim's plot
	thiefHeightAboveFloor: number, -- thief's root Y minus the plot's floor Y (no grabbing from mid-air)
	wallHeight: number,
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
	horizontalDistance: number, -- between the two root parts, ignoring height
	verticalDistance: number, -- absolute height difference between the two root parts
	tagRange: number,
	tagVerticalAllowance: number,
	taggerCooldownUntil: number,
	taggerTrusted: boolean, -- see isPositionTrusted: the tagger's reported position matches what the server saw
}

-- A character's movement as the server observed it (see stepWalkTrack). Times are server time.
export type WalkTrack = {
	lastX: number,
	lastY: number,
	lastZ: number,
	lastT: number,
	climbY: number, -- highest height already paid for: climbing costs once, jumping back up to it is free
	budget: number, -- studs the character may still move; refills over time, capped
}

export type WalkLimits = {
	maxSpeed: number, -- walk speed (studs/s)
	tolerance: number, -- refill rate multiplier on maxSpeed
	budgetSeconds: number, -- the budget never holds more than this many seconds of refill
	leeway: number, -- starting budget
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
	if not ctx.thiefInsideBase then
		return false, "outside"
	end
	if not StealRules.isAtFloorLevel(ctx.thiefHeightAboveFloor, ctx.wallHeight) then
		return false, "height"
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
	if not ctx.taggerTrusted then
		return false, "untrusted"
	end
	if
		not StealRules.withinTagReach(
			ctx.horizontalDistance,
			ctx.verticalDistance,
			ctx.tagRange,
			ctx.tagVerticalAllowance
		)
	then
		return false, "far"
	end
	return true, nil
end

-- Tag reach is horizontal range plus a generous vertical allowance, so a thief can't escape a tag by gaining
-- height (the carry height cap keeps every legitimate thief well inside the allowance).
function StealRules.withinTagReach(
	horizontalDistance: number,
	verticalDistance: number,
	tagRange: number,
	verticalAllowance: number
): boolean
	return horizontalDistance <= tagRange and math.abs(verticalDistance) <= verticalAllowance
end

-- True when a root part is near floor height: not below the floor, and not higher than the plot's walls.
-- Used for grabbing and delivering, so neither can be done from the air above a base.
function StealRules.isAtFloorLevel(heightAboveFloor: number, wallHeight: number): boolean
	return heightAboveFloor >= -2 and heightAboveFloor <= wallHeight
end

-- A carried creature is delivered only when the thief stands inside their own plot at floor level.
function StealRules.canDeliver(insideOwnPlot: boolean, heightAboveFloor: number, wallHeight: number): boolean
	return insideOwnPlot and StealRules.isAtFloorLevel(heightAboveFloor, wallHeight)
end

-- While carrying, the thief's root must stay between `minHeight` and `maxHeight` above the ground: no flying away
-- above every tagger, and no sinking under the map out of their reach either.
function StealRules.isCarryHeightAllowed(heightAboveGround: number, minHeight: number, maxHeight: number): boolean
	return heightAboveGround >= minHeight and heightAboveGround <= maxHeight -- false for NaN
end

-- Movement that counts against a carrying thief: horizontal distance plus any upward rise. Falling is free
-- (gravity), climbing or flying is not.
function StealRules.movementDistance(dx: number, dy: number, dz: number): number
	return math.sqrt(dx * dx + dz * dz) + math.max(0, dy)
end

-- Server-side speed sanity check while carrying (character physics is client-owned, so a speed exploit would
-- otherwise make stealing trivial). `distance` is studs moved in `dt` seconds (see movementDistance).
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

-- Starts tracking a character's movement at a server-observed position.
function StealRules.newWalkTrack(x: number, y: number, z: number, t: number, limits: WalkLimits): WalkTrack
	return { lastX = x, lastY = y, lastZ = z, lastT = t, climbY = y, budget = limits.leeway }
end

-- One server-observed step. The budget refills by maxSpeed * dt * tolerance (holding at most budgetSeconds of
-- refill) and pays for the distance moved: horizontal, plus height gained above the highest point already paid for,
-- so jumping again and again costs one jump and falling is free. Returns false when the budget goes negative, i.e.
-- faster than anyone can walk: a teleport or a sustained speed hack. A short stall followed by a catch-up jump (lag)
-- is paid for by the budget built up meanwhile. Mutates `track`.
function StealRules.stepWalkTrack(
	track: WalkTrack,
	x: number,
	y: number,
	z: number,
	t: number,
	limits: WalkLimits
): boolean
	if x ~= x or y ~= y or z ~= z then
		return false
	end
	local dt = math.max(0, t - track.lastT)
	local cap = limits.maxSpeed * limits.tolerance * limits.budgetSeconds
	track.budget = math.min(cap, track.budget + limits.maxSpeed * dt * limits.tolerance)
	local climb = math.max(0, y - track.climbY)
	track.budget -= math.sqrt((x - track.lastX) ^ 2 + (z - track.lastZ) ^ 2) + climb
	track.climbY += climb
	track.lastX, track.lastY, track.lastZ, track.lastT = x, y, z, math.max(track.lastT, t)
	return track.budget >= 0
end

-- How bad a step was, after stepWalkTrack: "ok"; "overrun" (a little more than the budget could pay: a long lag
-- stall, a server hitch, a physics fling); or "teleport" (more than `teleportDeficit` studs beyond it).
function StealRules.walkStepVerdict(track: WalkTrack, teleportDeficit: number): "ok" | "overrun" | "teleport"
	if track.budget >= 0 then
		return "ok"
	elseif track.budget < -teleportDeficit then
		return "teleport"
	end
	return "overrun"
end

-- What the server knows when judging a client-reported position (see isPositionTrusted). Times are server time.
export type TrustContext = {
	track: WalkTrack?, -- nil until the first sample
	flaggedAt: number, -- last step that overran the walk budget at all
	teleportedAt: number, -- last step that overran it grossly (a teleport)
	flagSince: number, -- any overrun at or after this time makes the position untrusted
	teleportSince: number, -- a teleport at or after this time does
	x: number,
	z: number,
	t: number,
	stepSlack: number, -- studs allowed beyond walking speed between the latest sample and now (jitter)
}

-- Character physics is client-owned, so a reported position (a tagger's, or a thief's at a podium) is only trusted
-- when it fits what the server itself observed: they are being tracked, nothing flagged since the given times (the
-- server asks for "no teleport since just before this carry started", so teleporting ahead of a thief and waiting
-- doesn't work), and the step from the latest sample to the reported position is walkable in the time since. That
-- step never spends the stored budget, so a tagger can't blink toward a thief, tag and blink back.
function StealRules.isPositionTrusted(ctx: TrustContext, limits: WalkLimits): boolean
	local track = ctx.track
	if track == nil or ctx.flaggedAt >= ctx.flagSince or ctx.teleportedAt >= ctx.teleportSince then
		return false
	end
	local dt = math.max(0, ctx.t - track.lastT)
	local step = math.sqrt((ctx.x - track.lastX) ^ 2 + (ctx.z - track.lastZ) ^ 2)
	return step <= limits.maxSpeed * limits.tolerance * dt + ctx.stepSlack -- false for NaN
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
		outside = "stealFromInside",
		height = "stealOnFloor",
		full = "baseFull",
	}
	return map[reason]
end

return StealRules
