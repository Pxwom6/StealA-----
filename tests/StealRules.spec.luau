--!strict
local T = require("./TestKit")
local StealRules = require("../src/shared/Logic/StealRules")

local function grab(overrides: { [string]: any }?): StealRules.GrabContext
	local ctx: StealRules.GrabContext = {
		now = 100,
		thiefUserId = 1,
		ownerUserId = 2,
		thiefCarrying = false,
		thiefCooldownUntil = 0,
		baseLocked = false,
		ownerGraceUntil = 0,
		creaturePresent = true,
		creatureBusy = false,
		distance = 5,
		grabRange = 12,
		thiefInsideBase = true,
		thiefHeightAboveFloor = 3, -- a character standing on the floor
		wallHeight = 7,
		thiefHasFreePodium = true,
		holdStartedAt = 98,
		holdSeconds = 1.5,
		holdTolerance = 0.8,
	}
	if overrides then
		for k, v in overrides do
			(ctx :: any)[k] = v
		end
	end
	return ctx
end

local function reason(ctx: StealRules.GrabContext): string?
	local _, why = StealRules.canGrab(ctx)
	return why
end

T.describe("StealRules.canGrab", function()
	T.it("allows a valid steal", function()
		T.expect((StealRules.canGrab(grab()))).toBe(true)
	end)
	T.it("refuses each invalid case with a reason", function()
		T.expect(reason(grab({ ownerUserId = 1 }))).toBe("own")
		T.expect(reason(grab({ thiefCarrying = true }))).toBe("carrying")
		T.expect(reason(grab({ thiefCooldownUntil = 101 }))).toBe("cooldown")
		T.expect(reason(grab({ baseLocked = true }))).toBe("locked")
		T.expect(reason(grab({ ownerGraceUntil = 200 }))).toBe("protected")
		T.expect(reason(grab({ creaturePresent = false }))).toBe("empty")
		T.expect(reason(grab({ creatureBusy = true }))).toBe("busy")
		T.expect(reason(grab({ distance = 30 }))).toBe("far")
		T.expect(reason(grab({ distance = 0 / 0 }))).toBe("far")
		T.expect(reason(grab({ thiefInsideBase = false }))).toBe("outside")
		T.expect(reason(grab({ thiefHasFreePodium = false }))).toBe("full")
	end)
	T.it("requires the hold to have actually lasted (server-timed)", function()
		local neverHeld = grab()
		neverHeld.holdStartedAt = nil
		T.expect(reason(neverHeld)).toBe("hold")
		T.expect(reason(grab({ holdStartedAt = 99.5 }))).toBe("hold")
		T.expect((StealRules.canGrab(grab({ holdStartedAt = 98.8 })))).toBe(true) -- 1.2s >= 1.5 * 0.8
	end)
	T.it("refuses grabs from above the base (flying / hovering over the walls)", function()
		T.expect(reason(grab({ thiefHeightAboveFloor = 25 }))).toBe("height")
		T.expect(reason(grab({ thiefHeightAboveFloor = 7.5 }))).toBe("height")
		T.expect(reason(grab({ thiefHeightAboveFloor = -5 }))).toBe("height")
		T.expect((StealRules.canGrab(grab({ thiefHeightAboveFloor = 4.4 })))).toBe(true) -- standing on a podium
		T.expect(StealRules.messageKey("height")).toBe("stealOnFloor")
	end)
	T.it("a locked base beats everything after ownership checks", function()
		T.expect(reason(grab({ baseLocked = true, distance = 999 }))).toBe("locked")
	end)
end)

T.describe("StealRules.canTag", function()
	local base: StealRules.TagContext = {
		now = 10,
		taggerUserId = 1,
		thiefUserId = 2,
		thiefCarrying = true,
		horizontalDistance = 5,
		verticalDistance = 0,
		tagRange = 13,
		tagVerticalAllowance = 22,
		taggerCooldownUntil = 0,
		taggerTrusted = true,
	}
	T.it("anyone near a carrying thief can tag", function()
		T.expect((StealRules.canTag(base))).toBe(true)
	end)
	T.it("refuses self-tags, non-thieves, cooldown and distance", function()
		local function why(overrides: { [string]: any }): string?
			local ctx = table.clone(base)
			for k, v in overrides do
				(ctx :: any)[k] = v
			end
			local _, r = StealRules.canTag(ctx)
			return r
		end
		T.expect(why({ thiefUserId = 1 })).toBe("self")
		T.expect(why({ thiefCarrying = false })).toBe("not_carrying")
		T.expect(why({ taggerCooldownUntil = 11 })).toBe("cooldown")
		T.expect(why({ horizontalDistance = 14 })).toBe("far")
		T.expect(why({ verticalDistance = 30 })).toBe("far")
	end)
	T.it("refuses tags from a tagger whose position the server can't vouch for", function()
		local ctx = table.clone(base)
		ctx.taggerTrusted = false
		local ok, why = StealRules.canTag(ctx)
		T.expect(ok).toBe(false)
		T.expect(why).toBe("untrusted")
	end)
	T.it("measures reach horizontally, so flying up out of 3D range doesn't escape a tag", function()
		-- thief 18 studs straight above the tagger: 3D distance 18 > tag range 13, but still taggable
		local ctx = table.clone(base)
		ctx.horizontalDistance = 2
		ctx.verticalDistance = 18
		T.expect((StealRules.canTag(ctx))).toBe(true)
		ctx.verticalDistance = -18
		T.expect((StealRules.canTag(ctx))).toBe(true)
		T.expect(StealRules.withinTagReach(13, 0, 13, 22)).toBe(true)
		T.expect(StealRules.withinTagReach(13.1, 0, 13, 22)).toBe(false)
		T.expect(StealRules.withinTagReach(0, 22.5, 13, 22)).toBe(false)
	end)
end)

T.describe("StealRules movement and timing", function()
	T.it("catches a teleport home even when checked only 0.2s into a window", function()
		-- grab at the podium, then appear 40 studs away (inside your own base) one tick later
		T.expect(StealRules.isMovementPlausible(40, 0.2, 10, 1.6, 6)).toBe(false)
		-- honest carry speed over the same tick is fine
		T.expect(StealRules.isMovementPlausible(2, 0.2, 10, 1.6, 6)).toBe(true)
	end)
	T.it("flags implausible carry speed", function()
		-- carry speed 10 studs/s, tolerance 1.6, leeway 6
		T.expect(StealRules.isMovementPlausible(10, 1, 10, 1.6, 6)).toBe(true)
		T.expect(StealRules.isMovementPlausible(21, 1, 10, 1.6, 6)).toBe(true)
		T.expect(StealRules.isMovementPlausible(23, 1, 10, 1.6, 6)).toBe(false)
		T.expect(StealRules.isMovementPlausible(100, 0.2, 10, 1.6, 6)).toBe(false)
		T.expect(StealRules.isMovementPlausible(0 / 0, 1, 10, 1.6, 6)).toBe(false)
		T.expect(StealRules.isMovementPlausible(3, 0, 10, 1.6, 6)).toBe(true)
	end)
	T.it("counts upward movement (flying) but not falling", function()
		T.expect(StealRules.movementDistance(3, 0, 4)).toBe(5)
		T.expect(StealRules.movementDistance(0, 30, 0)).toBe(30)
		T.expect(StealRules.movementDistance(3, -40, 4)).toBe(5)
		-- flying straight up 30 studs within one 0.2s tick is not plausible for a carrying thief
		T.expect(StealRules.isMovementPlausible(StealRules.movementDistance(0, 30, 0), 0.2, 10, 1.6, 6)).toBe(false)
	end)
	local walk: StealRules.WalkLimits = { maxSpeed = 16, tolerance = 1.5, budgetSeconds = 1.5, leeway = 12 }

	-- Root height while running at 16 studs/s and jumping every `period` s (default jump: about 7.2 studs high).
	local function runningJump(t: number, period: number): (number, number)
		local phase = t % period
		local airtime = 0.74
		local h = if phase < airtime then 7.2 * (1 - ((phase - airtime / 2) / (airtime / 2)) ^ 2) else 0
		return 16 * t, 3 + h
	end

	T.it("walk tracking: honest running jumps sampled at 4 Hz are never flagged", function()
		for _, offset in { 0, 0.05, 0.1, 0.15, 0.2 } do
			for _, period in { 0.75, 0.9, 1.3 } do
				local track = StealRules.newWalkTrack(0, 3, 0, offset, walk)
				for i = 1, 80 do
					local t = offset + i * 0.25
					local x, y = runningJump(t, period)
					T.expect(StealRules.stepWalkTrack(track, x, y, 0, t, walk)).toBe(true)
				end
			end
		end
	end)

	T.it("walk tracking: flags a teleport and a sustained speed hack, forgives a lag catch-up", function()
		local track = StealRules.newWalkTrack(0, 3, 0, 0, walk)
		T.expect(StealRules.stepWalkTrack(track, 4, 3, 0, 0.25, walk)).toBe(true)
		T.expect(StealRules.stepWalkTrack(track, 64, 3, 0, 0.5, walk)).toBe(false) -- 60 studs in 0.25 s

		local hack = StealRules.newWalkTrack(0, 3, 0, 0, walk)
		local flagged = false
		for i = 1, 20 do -- 39 studs/s (2.4x walk speed), under 10 studs per sample
			flagged = flagged or not StealRules.stepWalkTrack(hack, 39 * i * 0.25, 3, 0, i * 0.25, walk)
		end
		T.expect(flagged).toBe(true)

		local laggy = StealRules.newWalkTrack(0, 3, 0, 0, walk)
		for i = 1, 8 do
			StealRules.stepWalkTrack(laggy, 16 * i * 0.25, 3, 0, i * 0.25, walk)
		end
		-- replication stalls for 0.65 s while they keep running, then catches up in one step
		T.expect(StealRules.stepWalkTrack(laggy, 32 + 16 * 0.65, 3, 0, 2.65, walk)).toBe(true)
		T.expect(StealRules.stepWalkTrack(laggy, 0, -40, 0, 2.9, walk)).toBe(false) -- falling is free, the 42 studs back are not
	end)

	T.it("walk tracking: a small overrun (lag, hitch) is told apart from a teleport", function()
		local track = StealRules.newWalkTrack(0, 3, 0, 0, walk) -- budget cap 36
		for i = 1, 8 do
			StealRules.stepWalkTrack(track, 16 * i * 0.25, 3, 0, i * 0.25, walk)
		end
		T.expect(StealRules.walkStepVerdict(track, 24)).toBe("ok")
		-- a 3 s server hitch while running: 48 studs at once, 12 more than the budget can pay
		StealRules.stepWalkTrack(track, 32 + 48, 3, 0, 5, walk)
		T.expect(StealRules.walkStepVerdict(track, 24)).toBe("overrun")
		local tele = StealRules.newWalkTrack(0, 3, 0, 0, walk)
		StealRules.stepWalkTrack(tele, 150, 3, 0, 0.25, walk)
		T.expect(StealRules.walkStepVerdict(tele, 24)).toBe("teleport")
	end)

	T.it("trusts a walking tagger, but not a blink, a recent overrun, or a teleport since the carry began", function()
		local track = StealRules.newWalkTrack(0, 3, 0, 10, walk)
		local function ctx(overrides: { [string]: any }): StealRules.TrustContext
			local c: StealRules.TrustContext = {
				track = track,
				flaggedAt = -math.huge,
				teleportedAt = -math.huge,
				flagSince = 8,
				teleportSince = 3,
				x = 3,
				z = 0,
				t = 10.2,
				stepSlack = 4,
			}
			for key, value in overrides do
				(c :: any)[key] = value
			end
			return c
		end
		-- walked 3 studs in 0.2 s since the last sample: fine
		T.expect(StealRules.isPositionTrusted(ctx({}), walk)).toBe(true)
		-- appeared 120 studs away: refused
		T.expect(StealRules.isPositionTrusted(ctx({ x = 120, t = 10.1 }), walk)).toBe(false)
		-- blinked 24 studs toward a thief between samples (a full stored budget must not pay for it): refused
		T.expect(StealRules.isPositionTrusted(ctx({ x = 24, t = 10.1 }), walk)).toBe(false)
		-- a small overrun 1 s ago (inside the 2 s window): refused; 3 s ago: fine again
		T.expect(StealRules.isPositionTrusted(ctx({ flaggedAt = 9.2 }), walk)).toBe(false)
		T.expect(StealRules.isPositionTrusted(ctx({ flaggedAt = 7 }), walk)).toBe(true)
		-- teleported ahead of the thief during the carry (or its hold), then waited: refused for the whole carry
		T.expect(StealRules.isPositionTrusted(ctx({ flaggedAt = 4, teleportedAt = 4 }), walk)).toBe(false)
		-- a teleport long before this carry started no longer counts
		T.expect(StealRules.isPositionTrusted(ctx({ flaggedAt = 1, teleportedAt = 1 }), walk)).toBe(true)
		-- not tracked yet (just spawned): refused
		local untracked = ctx({})
		untracked.track = nil
		T.expect(StealRules.isPositionTrusted(untracked, walk)).toBe(false)
		T.expect(StealRules.isPositionTrusted(ctx({ x = 0 / 0 }), walk)).toBe(false)
	end)

	T.it("caps a carrying thief's height above the ground", function()
		T.expect(StealRules.isCarryHeightAllowed(12, 0, 22)).toBe(true) -- jumping off a podium
		T.expect(StealRules.isCarryHeightAllowed(22.5, 0, 22)).toBe(false)
		T.expect(StealRules.isCarryHeightAllowed(0 / 0, 0, 22)).toBe(false)
	end)
	T.it("a carrying thief can't sink under the map, out of every tagger's reach", function()
		T.expect(StealRules.isCarryHeightAllowed(3, 0, 22)).toBe(true) -- standing on the ground
		T.expect(StealRules.isCarryHeightAllowed(-0.5, 0, 22)).toBe(false)
		T.expect(StealRules.isCarryHeightAllowed(-26.6, 0, 22)).toBe(false) -- no-clipped under the ground
	end)
	T.it("only delivers at floor level inside your own plot", function()
		T.expect(StealRules.canDeliver(true, 3, 7)).toBe(true)
		T.expect(StealRules.canDeliver(true, 40, 7)).toBe(false) -- hovering above your own base
		T.expect(StealRules.canDeliver(false, 3, 7)).toBe(false)
	end)
	T.it("expires long carries", function()
		T.expect(StealRules.isCarryExpired(0, 74, 75)).toBe(false)
		T.expect(StealRules.isCarryExpired(0, 75, 75)).toBe(true)
	end)
	T.it("checks rectangles inclusively", function()
		local rect = { minX = 0, maxX = 10, minZ = -5, maxZ = 5 }
		T.expect(StealRules.isInsideRect(10, 5, rect)).toBe(true)
		T.expect(StealRules.isInsideRect(10.1, 0, rect)).toBe(false)
	end)
	T.it("grace protection is based on total play time", function()
		T.expect(StealRules.graceUntil(1000, 0, 240)).toBe(1240)
		T.expect(StealRules.graceUntil(1000, 200, 240)).toBe(1040)
		T.expect(StealRules.graceUntil(1000, 500, 240)).toBe(0)
	end)
	T.it("maps reasons to theme message keys", function()
		T.expect(StealRules.messageKey("locked")).toBe("cantStealLocked")
		T.expect(StealRules.messageKey("outside")).toBe("stealFromInside")
		T.expect(StealRules.messageKey("hold")).toBeNil()
	end)
end)

return nil
