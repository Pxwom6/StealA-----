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
	thiefHeightAboveFloor: number, -- thief's root Y minus the plot's floor Y (no grabbing from above the base)
	wallHeight: number,
	grabJumpAllowance: number, -- studs above the walls a grab still counts (jumping while holding Steal)
	thiefHasFreePodium: boolean,
	thiefTrusted: boolean, -- the thief's position fits what the server observed (see stealTrustSince)
	holdStartedAt: number?, -- when the thief began holding the prompt (server time), nil if never
	holdRefusal: string?, -- why canBeginHold refused that hold, if it did
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

-- Movement budget for a carrying thief (see stepCarryTrack): a WalkTrack at carry speed, plus the grab point.
export type CarryTrack = {
	grabX: number,
	grabZ: number,
	startedAt: number,
	lastX: number,
	lastY: number,
	lastZ: number,
	lastT: number,
	climbY: number, -- highest height already paid for (see stepWalkTrack)
	budget: number, -- studs the thief may still move; refills over time, capped
}

-- maxSpeed is the carry walk speed; leeway is the starting budget and the slack on the straight-line cap.
export type CarryLimits = WalkLimits

export type Rect = { minX: number, maxX: number, minZ: number, maxZ: number }

-- A server move that is still settling (see isSettling): where the server put the character, and until when (server
-- time) stale samples are ignored.
export type Settle = { x: number, y: number, z: number, untilT: number }

-- How long a flag keeps a thief from starting or finishing a steal (see stealTrustSince).
export type StealTrustWindows = {
	overrunSeconds: number, -- after an overrun (a lag stall, a server hitch, a fling)
	teleportSeconds: number, -- after a gross overrun (a teleport)
}

-- Where the thief is when they start holding Steal (see canBeginHold).
export type HoldContext = {
	distance: number, -- thief root to podium
	grabRange: number,
	rangeSlack: number, -- extra studs allowed at begin (the prompt shows a little before the server's range)
	thiefInsideBase: boolean,
	thiefTrusted: boolean, -- the thief's reported position fits what the server observed (no teleporting in)
}

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
	if not StealRules.isAtGrabHeight(ctx.thiefHeightAboveFloor, ctx.wallHeight, ctx.grabJumpAllowance) then
		return false, "height"
	end
	if not ctx.thiefHasFreePodium then
		return false, "full"
	end
	if not ctx.thiefTrusted then
		return false, "untrusted"
	end
	local started = ctx.holdStartedAt
	if started == nil and ctx.holdRefusal == "untrusted" then
		return false, "untrusted" -- the hold never started because of a connection hiccup: say that, not "hold"
	end
	if started == nil or ctx.now - started < ctx.holdSeconds * ctx.holdTolerance then
		return false, "hold"
	end
	return true, nil
end

-- A hold (StealBegin) only starts when the thief is already at the podium: within grab range (plus a little slack),
-- inside the base, and their position trusted (not teleported in). Otherwise the hold timer could run while they
-- are far away and they could teleport in and confirm instantly. Height is NOT checked here: pressing mid-jump is
-- normal, and canGrab checks the grab height when the hold completes.
-- Returns ok, and a reason ("far" | "outside" | "untrusted") when not ok.
function StealRules.canBeginHold(ctx: HoldContext): (boolean, string?)
	if not (ctx.distance <= ctx.grabRange + ctx.rangeSlack) then
		return false, "far"
	elseif not ctx.thiefInsideBase then
		return false, "outside"
	elseif not ctx.thiefTrusted then
		return false, "untrusted"
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
-- Delivery uses it, so a creature can't be delivered from the air above a base.
function StealRules.isAtFloorLevel(heightAboveFloor: number, wallHeight: number): boolean
	return heightAboveFloor >= -2 and heightAboveFloor <= wallHeight
end

-- True when a thief's root is low enough to grab: floor level, plus `jumpAllowance` studs above the walls so that
-- jumping while holding Steal still works (a jump lifts the root ~7 studs). The 3D grab range to the podium
-- already stops grabs from high in the air.
function StealRules.isAtGrabHeight(heightAboveFloor: number, wallHeight: number, jumpAllowance: number): boolean
	return StealRules.isAtFloorLevel(heightAboveFloor, wallHeight + math.max(0, jumpAllowance))
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

-- After the SERVER moves a character (spawning, respawning, ejecting from a locked base), its client can keep
-- reporting where it was before the move for a moment (a stale position). Until `untilT` passes, a sample more than
-- `radius` studs from the target is ignored instead of judged, so that stale position never looks like a teleport;
-- samples near the target are judged. Returns true when the sample at (x, y, z) should be ignored.
function StealRules.isSettling(settle: Settle?, x: number, y: number, z: number, t: number, radius: number): boolean
	if settle == nil or t >= settle.untilT then
		return false
	end
	local distance = math.sqrt((x - settle.x) ^ 2 + (y - settle.y) ^ 2 + (z - settle.z) ^ 2)
	return not (distance <= radius) -- NaN counts as not arrived
end

-- One position sample while a server move may be settling: whether to ignore it (see isSettling), and the settle to
-- keep. A sample near the target does not end the window early: right after the move the server reads its own write
-- (the target) until the client's updates from before the move arrive, and those must still be ignored. Only
-- `untilT` ends it.
function StealRules.settleSample(
	settle: Settle?,
	x: number,
	y: number,
	z: number,
	t: number,
	radius: number
): (boolean, Settle?)
	if settle == nil or t >= settle.untilT then
		return false, nil
	end
	return StealRules.isSettling(settle, x, y, z, t, radius), settle
end

-- The `flagSince` / `teleportSince` times (see TrustContext) for starting or finishing a steal at time `t`: a flag
-- only counts while it is recent, so after a lag spike the thief can steal again once they have moved normally for
-- a few seconds (any new flag restarts that clock), without walking out of the base and back in. A teleport (onto a
-- podium, say) takes longer to clear.
function StealRules.stealTrustSince(t: number, windows: StealTrustWindows): (number, number)
	return t - windows.overrunSeconds, t - windows.teleportSeconds
end

-- Starts tracking a carry at the grab position.
function StealRules.newCarryTrack(x: number, y: number, z: number, t: number, limits: CarryLimits): CarryTrack
	return {
		grabX = x,
		grabZ = z,
		startedAt = t,
		lastX = x,
		lastY = y,
		lastZ = z,
		lastT = t,
		climbY = y,
		budget = limits.leeway,
	}
end

-- One server tick of a carry. The movement budget works like stepWalkTrack at carry speed: it refills by
-- maxSpeed * dt * tolerance (capped at budgetSeconds of refill) and pays for the distance moved (horizontal, plus
-- height gained above the highest point already paid for, so repeated jumps cost one jump); the carry fails if it
-- goes negative. That rejects sustained speed hacks yet forgives a lag spike (positions freeze, then catch up in one
-- jump: the budget built up while frozen pays for it). Separately the straight-line horizontal distance from the grab
-- point may never exceed maxSpeed * elapsed + leeway, which stops a teleport home right after a grab.
-- Returns ok, and a reason ("speed" | "distance") when not ok. Mutates `track`.
function StealRules.stepCarryTrack(
	track: CarryTrack,
	x: number,
	y: number,
	z: number,
	t: number,
	limits: CarryLimits
): (boolean, string?)
	if not StealRules.stepWalkTrack(track, x, y, z, t, limits) then
		return false, "speed"
	end
	local fromGrab = math.sqrt((x - track.grabX) ^ 2 + (z - track.grabZ) ^ 2)
	if fromGrab > limits.maxSpeed * math.max(0, t - track.startedAt) + limits.leeway then
		return false, "distance"
	end
	return true, nil
end

-- The nearest point `margin` studs outside `rect` from a point inside it. A carrying thief ejected from a locked base
-- is put there, and their carry budget pays for that short move like any other: the server's move is never a
-- shortcut (sending them to the entrance could carry them far toward home for free).
function StealRules.nearestOutside(x: number, z: number, rect: Rect, margin: number): (number, number)
	local toMinX, toMaxX, toMinZ, toMaxZ = x - rect.minX, rect.maxX - x, z - rect.minZ, rect.maxZ - z
	local nearest = math.min(toMinX, toMaxX, toMinZ, toMaxZ)
	if nearest == toMinX then
		return rect.minX - margin, z
	elseif nearest == toMaxX then
		return rect.maxX + margin, z
	elseif nearest == toMinZ then
		return x, rect.minZ - margin
	end
	return x, rect.maxZ + margin
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
		hold = "stealHoldNear",
		untrusted = "stealConnectionHiccup",
		full = "baseFull",
	}
	return map[reason]
end

return StealRules
