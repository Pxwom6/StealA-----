--!strict
--[[
	Conveyor maths. Belt items are not physics objects: their position is a pure function of spawn time, so the
	server can validate a "buy" against where the item really is (clients only render it). Positions are 2D
	(x, z) on the ground plane. Pure: no requires, no Roblox APIs.
]]

export type Belt = {
	startX: number,
	startZ: number,
	dirX: number, -- unit direction of travel
	dirZ: number,
	length: number,
	travelSeconds: number,
}

local BeltMath = {}

function BeltMath.speed(belt: Belt): number
	return belt.length / belt.travelSeconds
end

-- Distance travelled along the belt (studs), clamped to [0, length].
function BeltMath.along(belt: Belt, spawnAt: number, now: number): number
	return math.clamp((now - spawnAt) * BeltMath.speed(belt), 0, belt.length)
end

function BeltMath.position(belt: Belt, spawnAt: number, now: number): (number, number)
	local a = BeltMath.along(belt, spawnAt, now)
	return belt.startX + belt.dirX * a, belt.startZ + belt.dirZ * a
end

function BeltMath.isExpired(belt: Belt, spawnAt: number, now: number): boolean
	return now - spawnAt >= belt.travelSeconds
end

local function distanceToSegment(px: number, pz: number, ax: number, az: number, bx: number, bz: number): number
	local abx, abz = bx - ax, bz - az
	local lengthSq = abx * abx + abz * abz
	local t = 0
	if lengthSq > 0 then
		t = math.clamp(((px - ax) * abx + (pz - az) * abz) / lengthSq, 0, 1)
	end
	local cx, cz = ax + abx * t, az + abz * t
	return math.sqrt((px - cx) ^ 2 + (pz - cz) ^ 2)
end

-- Smallest distance between a player and an item over the last `tolerance` seconds of its travel, which
-- forgives network latency (the client saw the item slightly earlier than the server's "now").
function BeltMath.distanceTo(
	belt: Belt,
	spawnAt: number,
	now: number,
	px: number,
	pz: number,
	tolerance: number
): number
	local ax, az = BeltMath.position(belt, spawnAt, now - math.max(0, tolerance))
	local bx, bz = BeltMath.position(belt, spawnAt, now)
	return distanceToSegment(px, pz, ax, az, bx, bz)
end

return BeltMath
