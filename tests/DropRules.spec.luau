--!strict
local T = require("./TestKit")
local DropRules = require("../src/shared/Logic/DropRules")
local Drops = require("../src/shared/Config/Drops")
local Gameplay = require("../src/shared/Config/Gameplay")
local Modifiers = require("../src/shared/Config/Modifiers")
local Types = require("../src/shared/Types")

local WALKWAY = {
	maxX = Gameplay.belt.length / 2,
	maxZ = Gameplay.map.walkwayWidth,
	beltHalfWidth = Gameplay.belt.width / 2,
}

local function copy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, item in value do
		result[key] = copy(item)
	end
	return result
end

local function sequence(values: { number }): () -> number
	local index = 0
	return function(): number
		index += 1
		return values[(index - 1) % #values + 1]
	end
end

T.describe("DropRules: the real config", function()
	T.it("is valid", function()
		local problems = DropRules.validate(Drops, WALKWAY)
		if #problems > 0 then
			print(table.concat(problems, "\n"))
		end
		T.expect(#problems).toBe(0)
	end)

	T.it("gives Supply Drop a few crates and Coin Rain several showers", function()
		local duration = Modifiers.schedule.durationSeconds
		T.expect(#DropRules.times(Modifiers.modifiers.supplyDrop.drops :: Types.ModifierDrops, duration)).toBe(4)
		T.expect(#DropRules.times(Modifiers.modifiers.coinRain.drops :: Types.ModifierDrops, duration)).toBe(8)
		T.expect(#DropRules.times(Modifiers.modifiers.greatEscape.drops :: Types.ModifierDrops, duration)).toBe(6)
	end)

	T.it("lets a runaway run slower than players walk, and only one at a time mostly", function()
		local cfg = Drops.runaway
		T.expect(cfg.speed).toBeLessThan(Gameplay.walkSpeed * 0.8)
		local drops = Modifiers.modifiers.greatEscape.drops :: Types.ModifierDrops
		-- a new one escapes about when the last one would get away
		T.expect(drops.everySeconds).toBeAtLeast(cfg.lifetimeSeconds)
	end)
end)

T.describe("DropRules.position", function()
	T.it("lands inside the area, on either walkway", function()
		local area = Drops.area
		local x, z = DropRules.position(area, sequence({ 0, 0, 0.9 }))
		T.expect(x).toBe(area.minX)
		T.expect(z).toBe(area.minZ)
		x, z = DropRules.position(area, sequence({ 0.5, 0.5, 0.1 }))
		T.expect(x).toBe((area.minX + area.maxX) / 2)
		T.expect(z).toBe(-(area.minZ + area.maxZ) / 2)
	end)

	T.it("never lands on the belt or in a base", function()
		local random = T.seededRandom(3)
		for _ = 1, 2000 do
			local x, z = DropRules.position(Drops.area, random)
			T.expect(math.abs(x)).toBeAtMost(WALKWAY.maxX)
			T.expect(math.abs(z)).toBeGreaterThan(WALKWAY.beltHalfWidth + 2)
			T.expect(math.abs(z)).toBeLessThan(WALKWAY.maxZ - 2)
		end
	end)
end)

T.describe("DropRules timing and rewards", function()
	T.it("drops from the first time, then every so often, until the modifier ends", function()
		local drops: Types.ModifierDrops = { kind = "crate", firstSeconds = 10, everySeconds = 75 }
		T.expect(DropRules.times(drops, 300)).toEqual({ 10, 85, 160, 235 })
		T.expect(DropRules.times(drops, 10)).toEqual({})
		T.expect(DropRules.times({ kind = "coins", firstSeconds = 0, everySeconds = 0 }, 300)).toEqual({})
	end)

	T.it("pays a few seconds of income, never less than the minimum", function()
		local reward = { incomeSeconds = 3, minimum = 30 }
		T.expect(DropRules.amount(reward, 0)).toBe(30)
		T.expect(DropRules.amount(reward, 5)).toBe(30)
		T.expect(DropRules.amount(reward, 1000)).toBe(3000)
	end)

	T.it("opens a crate only after a long enough hold", function()
		local hold = Drops.crate.holdSeconds * Drops.crate.holdTolerance
		T.expect(DropRules.holdLongEnough(Drops, nil, 100)).toBe(false)
		T.expect(DropRules.holdLongEnough(Drops, 100, 100 + hold - 0.01)).toBe(false)
		T.expect(DropRules.holdLongEnough(Drops, 100, 100 + hold)).toBe(true)
	end)

	T.it("picks up a coin only when you walk through it", function()
		local range = Drops.coins.pickupRange
		T.expect(DropRules.inPickupRange(Drops, range, 0)).toBe(true)
		T.expect(DropRules.inPickupRange(Drops, range + 0.1, 0)).toBe(false)
		T.expect(DropRules.inPickupRange(Drops, 0, 30)).toBe(false)
	end)
end)

T.describe("DropRules runaways", function()
	local area = Drops.area
	local function onWalkway(x: number, z: number): boolean
		return x >= area.minX - 1e-9
			and x <= area.maxX + 1e-9
			and math.abs(z) >= area.minZ - 1e-9
			and math.abs(z) <= area.maxZ + 1e-9
	end
	local function distance(x: number, z: number, point: DropRules.Point): number
		return math.sqrt((x - point.x) ^ 2 + (z - point.z) ^ 2)
	end

	T.it("appears as far from everyone as it can, away from the ends of the walkways", function()
		local players = { { x = -100, z = 15 }, { x = 0, z = -15 } }
		local random = T.seededRandom(11)
		local margin = Drops.runaway.edgeMargin
		for _ = 1, 50 do
			local x, z = DropRules.runawayStart(Drops, players, random)
			T.expect(onWalkway(x, z)).toBe(true)
			T.expect(x).toBeAtLeast(area.minX + margin)
			T.expect(x).toBeAtMost(area.maxX - margin)
			-- never right next to someone (the walkways are long enough to keep away)
			T.expect(math.min(distance(x, z, players[1]), distance(x, z, players[2]))).toBeGreaterThan(30)
		end
		-- nobody around: the first spot
		local x, z = DropRules.runawayStart(Drops, {}, sequence({ 0, 0, 0.9 }))
		T.expect(x).toBe(area.minX + margin)
		T.expect(z).toBe(area.minZ)
	end)

	T.it("runs away from a player who comes near, never stopping on the belt", function()
		local random = T.seededRandom(5)
		local fled, crossed = 0, 0
		for i = 1, 200 do
			local side = if i % 2 == 0 then 1 else -1
			local x, z = -60 + i * 0.5, 17 * side
			local player = { x = x - 6, z = z }
			local tx, tz = DropRules.runawayTarget(Drops, x, z, { player }, random)
			T.expect(onWalkway(tx, tz)).toBe(true)
			if tz * side < 0 then
				crossed += 1
			end
			if distance(tx, tz, player) > distance(x, z, player) + Drops.runaway.legMin * 0.5 then
				fled += 1
			end
		end
		T.expect(fled).toBeGreaterThan(190)
		-- mostly along its walkway; now and then over the belt to the other one
		T.expect(crossed).toBeGreaterThan(0)
		T.expect(crossed).toBeLessThan(60)
	end)

	T.it("wanders when nobody is near, in legs of about the configured length", function()
		local random = T.seededRandom(9)
		local cfg = Drops.runaway
		local x, z = 0, 17
		local moved = 0
		for _ = 1, 100 do
			local tx, tz = DropRules.runawayTarget(Drops, x, z, { { x = 120, z = -20 } }, random)
			local length = math.sqrt((tx - x) ^ 2 + (tz - z) ^ 2)
			-- a hop over the belt lands on the other walkway: up to the belt gap longer
			T.expect(length).toBeAtMost(cfg.legMax + area.minZ * 2 + 1e-9)
			moved += length
			x, z = tx, tz
			T.expect(onWalkway(x, z)).toBe(true)
		end
		T.expect(moved / 100).toBeGreaterThan(cfg.legMin * 0.5)
	end)

	T.it("sprints, and barely stops, while someone is near", function()
		local cfg = Drops.runaway
		T.expect(DropRules.isFleeing(Drops, 0, 15, { { x = cfg.fleeRadius - 1, z = 15 } })).toBe(true)
		T.expect(DropRules.isFleeing(Drops, 0, 15, { { x = cfg.fleeRadius + 1, z = 15 } })).toBe(false)
		T.expect(DropRules.isFleeing(Drops, 0, 15, {})).toBe(false)
		local calm = DropRules.runawayLeg(Drops, 0, 15, 20, 15, 0, false)
		local scared = DropRules.runawayLeg(Drops, 0, 15, 20, 15, 0, true)
		T.expect(scared.startsAt).toBeLessThan(calm.startsAt)
		T.expect(scared.endsAt - scared.startsAt).toBeLessThan(calm.endsAt - calm.startsAt)
		T.expect(cfg.sprintSpeed).toBeLessThan(Gameplay.walkSpeed)
	end)

	T.it("knows how far along a leg it is, and when it jumps the belt", function()
		local leg = DropRules.runawayLeg(Drops, 0, 15, 0, -15, 10, true)
		T.expect(DropRules.crossesBelt(leg)).toBe(true)
		T.expect(DropRules.legProgress(leg, 0)).toBe(0)
		T.expect(DropRules.legProgress(leg, (leg.startsAt + leg.endsAt) / 2)).toBeNear(0.5, 1e-9)
		T.expect(DropRules.legProgress(leg, leg.endsAt + 1)).toBe(1)
		T.expect(DropRules.crossesBelt(DropRules.runawayLeg(Drops, 0, 15, 20, 12, 10, true))).toBe(false)
	end)

	T.it("waits, runs in a straight line, and arrives", function()
		local leg = DropRules.runawayLeg(Drops, 0, 15, 22, 15, 100, false)
		T.expect(leg.startsAt).toBeNear(100 + Drops.runaway.pauseSeconds, 1e-9)
		T.expect(leg.endsAt - leg.startsAt).toBeNear(22 / Drops.runaway.speed, 1e-9)
		local x, z, moving = DropRules.legPosition(leg, 100)
		T.expect(x).toBe(0)
		T.expect(moving).toBe(false)
		x, z, moving = DropRules.legPosition(leg, (leg.startsAt + leg.endsAt) / 2)
		T.expect(x).toBeNear(11, 1e-9)
		T.expect(z).toBeNear(15, 1e-9)
		T.expect(moving).toBe(true)
		x, z, moving = DropRules.legPosition(leg, leg.endsAt + 5)
		T.expect(x).toBe(22)
		T.expect(z).toBe(15)
		T.expect(moving).toBe(false)
	end)

	T.it("sends a leg as one piece of text and reads it back", function()
		local leg = DropRules.runawayLeg(Drops, -12.5, 17.25, 3.75, 20.5, 1760000000.125, true)
		local back = DropRules.decodeLeg(DropRules.encodeLeg(leg)) :: DropRules.Leg
		T.expect(back).toBeTruthy()
		for _, key in { "fromX", "fromZ", "toX", "toZ", "startsAt", "endsAt" } do
			T.expect((back :: any)[key]).toBeNear((leg :: any)[key], 0.01)
		end
		T.expect(DropRules.decodeLeg("1,2,3")).toBe(nil)
		T.expect(DropRules.decodeLeg("1,2,3,4,5,x")).toBe(nil)
		T.expect(DropRules.decodeLeg("1,2,3,4,5,inf")).toBe(nil)
		T.expect(DropRules.decodeLeg("1,2,3,4,5,nan")).toBe(nil)
	end)

	T.it("is caught by walking into it, with a little slack for lag", function()
		local range = Drops.runaway.catchRange
		T.expect(DropRules.catches(Drops, range, 2, 0)).toBe(true)
		T.expect(DropRules.catches(Drops, range + 1, 2, 0)).toBe(false)
		T.expect(DropRules.catches(Drops, range + 1, 2, 2)).toBe(true)
		T.expect(DropRules.catches(Drops, 0, 30, 2)).toBe(false)
	end)

	-- A chase with the real numbers: players walking straight at it catch it well before it gets away.
	local function chase(starts: { DropRules.Point }, seed: number): number?
		local random = T.seededRandom(seed)
		local players = table.clone(starts)
		for index, point in players do
			players[index] = { x = point.x, z = point.z }
		end
		local x, z = DropRules.runawayStart(Drops, players, random)
		local leg = DropRules.runawayLeg(Drops, x, z, x, z, 0, false)
		local step = 0.1
		local t = 0
		while t < Drops.runaway.lifetimeSeconds do
			t += step
			if t >= leg.endsAt then
				local tx, tz = DropRules.runawayTarget(Drops, leg.toX, leg.toZ, players, random)
				local fleeing = DropRules.isFleeing(Drops, leg.toX, leg.toZ, players)
				leg = DropRules.runawayLeg(Drops, leg.toX, leg.toZ, tx, tz, t, fleeing)
			end
			local rx, rz = DropRules.legPosition(leg, t)
			for _, player in players do
				local dx, dz = rx - player.x, rz - player.z
				local gap = math.sqrt(dx * dx + dz * dz)
				if DropRules.catches(Drops, gap, 0, 0) then
					return t
				end
				local stride = math.min(gap, Gameplay.walkSpeed * step)
				player.x += dx / gap * stride
				player.z += dz / gap * stride
			end
		end
		return nil
	end

	T.it("can be caught by one player chasing it, and sooner by two", function()
		local alone, together = 0, 0
		for seed = 1, 20 do
			local soloTime = chase({ { x = -120, z = 17 } }, seed)
			T.expect(soloTime ~= nil).toBe(true)
			alone += soloTime :: number
			local pairTime = chase({ { x = -120, z = 17 }, { x = 120, z = -17 } }, seed)
			T.expect(pairTime ~= nil).toBe(true)
			together += pairTime :: number
		end
		T.expect(alone / 20).toBeGreaterThan(5) -- a real chase, not a free pickup
		T.expect(together).toBeLessThan(alone)
	end)
end)

T.describe("DropRules.validate", function()
	local function broken(edit: (config: any) -> ()): number
		local config = copy(Drops)
		edit(config)
		return #DropRules.validate(config :: Types.DropsConfig, WALKWAY)
	end

	T.it("keeps drops on the walkways", function()
		T.expect(broken(function(config)
			config.area.minZ = 2 -- on the belt
		end)).toBeAtLeast(1)
		T.expect(broken(function(config)
			config.area.maxZ = 40 -- inside the bases
		end)).toBeAtLeast(1)
		T.expect(broken(function(config)
			config.area.maxX = 500
		end)).toBeAtLeast(1)
	end)

	T.it("refuses broken crates and coins", function()
		T.expect(broken(function(config)
			config.crate.holdTolerance = 2
		end)).toBe(1)
		T.expect(broken(function(config)
			config.crate.luck = 50
		end)).toBe(1)
		T.expect(broken(function(config)
			config.coins.perWave = 0
		end)).toBe(1)
		T.expect(broken(function(config)
			config.coins.value.incomeSeconds = -1
		end)).toBe(1)
	end)

	T.it("refuses broken runaways", function()
		T.expect(broken(function(config)
			config.runaway.speed = 0
		end)).toBe(1)
		T.expect(broken(function(config)
			config.runaway.sprintSpeed = config.runaway.speed - 1
		end)).toBe(1)
		T.expect(broken(function(config)
			config.runaway.edgeMargin = 1000
		end)).toBe(1)
		T.expect(broken(function(config)
			config.runaway.legMax = config.runaway.legMin - 1
		end)).toBe(1)
		T.expect(broken(function(config)
			config.runaway.candidates = 0
		end)).toBe(1)
		T.expect(broken(function(config)
			config.runaway.luck = 50
		end)).toBe(1)
	end)

	T.it("checks a modifier's drops", function()
		T.expect(#DropRules.dropsProblems({ kind = "crate", firstSeconds = 10, everySeconds = 75 }, 300, "x")).toBe(0)
		T.expect(#DropRules.dropsProblems({ kind = "runaway", firstSeconds = 6, everySeconds = 50 }, 300, "x")).toBe(0)
		T.expect(#DropRules.dropsProblems({ kind = "pinata" :: any, firstSeconds = 10, everySeconds = 75 }, 300, "x"))
			.toBe(1)
		T.expect(#DropRules.dropsProblems({ kind = "coins", firstSeconds = 400, everySeconds = 75 }, 300, "x")).toBe(1)
		T.expect(#DropRules.dropsProblems({ kind = "coins", firstSeconds = 0, everySeconds = 1 }, 300, "x")).toBe(1)
	end)
end)

return nil
