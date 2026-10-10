--!strict
--[[
	Idle animation curves for Snacklings. Pure maths (no Roblox APIs): the client turns a pose into one CFrame and a
	squash of the body (IdleController for podiums, BeltController for the conveyor).

	  podium  a slow breathing bob: up and down by a few % of the model's height, squashed at the bottom and stretched
	          at the top, with a slow sway (roll) and a gentle turn (yaw)
	  belt    a bouncy hop: stretched in the air, squashed when it lands, leaning to alternate sides (a waddle)

	Each model passes its own `phase` (0..1) so a row of Snacklings never moves in lockstep.
]]

export type Pose = {
	lift: number, -- studs above the resting position
	squash: number, -- -0.05 = 5% shorter (and a little wider), 0.05 = 5% taller
	roll: number, -- radians, around the model's forward axis (sway)
	yaw: number, -- radians, around the vertical axis
}

local IdleMotion = {}

IdleMotion.PODIUM = {
	period = 2.4, -- seconds per breath (each model runs up to 10% faster or slower)
	lift = 0.035, -- share of the model's height
	maxLift = 0.3, -- studs, for the biggest models
	squash = 0.04,
	roll = 0.045,
	yaw = 0.06,
}

IdleMotion.BELT = {
	hopsPerSecond = 1.9,
	height = 0.35, -- studs
	squash = 0.08,
	roll = 0.07,
}

local TAU = math.pi * 2

-- Resting pose on a podium at clock time `t` for a model `height` studs tall.
function IdleMotion.podium(t: number, phase: number, height: number): Pose
	local cfg = IdleMotion.PODIUM
	local speed = 1 + (phase - 0.5) * 0.2
	local angle = (t * speed / cfg.period + phase) * TAU
	local c = math.cos(angle)
	local lift = math.min(cfg.lift * math.max(height, 0), cfg.maxLift)
	return {
		lift = lift * (1 - c) / 2,
		squash = -cfg.squash * c,
		roll = cfg.roll * math.sin(angle * 0.5 + phase * 7),
		yaw = cfg.yaw * math.sin(angle * 0.37 + phase * 13),
	}
end

-- Hopping pose on the belt, `t` seconds after the item spawned.
function IdleMotion.belt(t: number, phase: number): Pose
	local cfg = IdleMotion.BELT
	local u = t * cfg.hopsPerSecond + phase
	local hop = u - math.floor(u)
	local arc = math.sin(math.pi * hop) -- 0 when touching the belt, 1 at the top of the hop
	local side = if math.floor(u) % 2 == 0 then 1 else -1
	return {
		lift = cfg.height * arc,
		squash = cfg.squash * (0.6 * arc - (1 - arc) ^ 6),
		roll = cfg.roll * arc * side,
		yaw = 0,
	}
end

-- A stable 0..1 phase from any number (e.g. a belt item id).
function IdleMotion.phaseOf(n: number): number
	local x = n * 0.6180339887
	return x - math.floor(x)
end

return IdleMotion
