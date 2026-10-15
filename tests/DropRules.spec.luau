--!strict
local T = require("./TestKit")
local DropRules = require("../src/shared/Logic/DropRules")
local MapThemeRules = require("../src/shared/Logic/MapThemeRules")
local SceneryLayout = require("../src/shared/Logic/SceneryLayout")
local SeasonRules = require("../src/shared/Logic/SeasonRules")
local Drops = require("../src/shared/Config/Drops")
local Gameplay = require("../src/shared/Config/Gameplay")
local Modifiers = require("../src/shared/Config/Modifiers")
local Scenery = require("../src/shared/Config/Scenery")
local Seasons = require("../src/shared/Config/Seasons")
local Theme = require("../src/shared/Config/Theme")
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
		local problems = DropRules.validate(Drops, WALKWAY, (Theme.text :: any) :: { [string]: string })
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
		T.expect(#DropRules.times(Modifiers.modifiers.treasureHunt.drops :: Types.ModifierDrops, duration)).toBe(7)
	end)

	T.it("hides one golden fork at a time", function()
		local drops = Modifiers.modifiers.treasureHunt.drops :: Types.ModifierDrops
		T.expect(Drops.treasure.lifetimeSeconds).toBeLessThan(drops.everySeconds)
		-- and the last one still has its whole life before the next modifier can start
		local times = DropRules.times(drops, Modifiers.schedule.durationSeconds)
		T.expect(times[#times] + Drops.treasure.lifetimeSeconds)
			.toBeAtMost(Modifiers.schedule.durationSeconds + Modifiers.schedule.gapMinSeconds)
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

-- The real map, laid out as MapBuilder and SeasonService place things (as tests/SeasonRules.spec builds it).
local MAP = Gameplay.map
local function seasonMap(): SeasonRules.MapShape
	local entrances: { SeasonRules.Entrance } = {}
	local spanX = MAP.plotsPerSide * MAP.plotWidth + (MAP.plotsPerSide - 1) * MAP.plotGap
	for index = 1, MAP.plotCount do
		local north = index <= MAP.plotsPerSide
		local column = (index - 1) % MAP.plotsPerSide
		local x = -spanX / 2 + MAP.plotWidth / 2 + column * (MAP.plotWidth + MAP.plotGap)
		local sign = if north then 1 else -1
		local z = sign * (MAP.walkwayWidth + MAP.plotDepth / 2)
		table.insert(entrances, { x = x, z = z - sign * MAP.plotDepth / 2, outX = 0, outZ = -sign })
	end
	return {
		entrances = entrances,
		entranceWidth = MAP.entranceWidth,
		plotWidth = MAP.plotWidth,
		groundY = 0.2,
		wallTopY = 0.4 + MAP.wallHeight,
		beltLength = Gameplay.belt.length,
		beltWidth = Gameplay.belt.width,
		walkwayWidth = MAP.walkwayWidth,
	}
end

-- Horizontal distance from (x, z) to the segment of half length `half` through (cx, cz) along (dx, dz) (a unit vector).
local function segmentDistance(
	x: number,
	z: number,
	cx: number,
	cz: number,
	dx: number,
	dz: number,
	half: number
): number
	local along = math.clamp((x - cx) * dx + (z - cz) * dz, -half, half)
	local px, pz = cx + dx * along, cz + dz * along
	return math.sqrt((x - px) ^ 2 + (z - pz) ^ 2)
end

T.describe("DropRules Treasure Hunt", function()
	local function far(): { DropRules.Point }
		return { { x = 0, z = 0 } } -- one player on the belt's middle
	end

	T.it("hides a fork far from every player, never twice running in the same place", function()
		local spots = Drops.treasure.spots
		local random = T.seededRandom(11)
		local last: number? = nil
		local used: { [number]: boolean } = {}
		for _ = 1, 400 do
			local index = DropRules.treasureSpot(Drops, far(), last, random) :: number
			T.expect(index ~= last).toBe(true)
			T.expect(DropRules.treasureDistance(Drops, index, far())).toBeAtLeast(Drops.treasure.minPlayerDistance)
			used[index] = true
			last = index
		end
		-- every hiding place far enough from the middle of the belt gets used
		for index in spots do
			if DropRules.treasureDistance(Drops, index, far()) >= Drops.treasure.minPlayerDistance then
				T.expect(used[index] == true).toBe(true)
			end
		end
	end)

	T.it("goes to the farthest place when every one is near someone", function()
		local config = copy(Drops)
		config.treasure.minPlayerDistance = 10000
		local index = DropRules.treasureSpot(config, far(), nil, function(): number
			return 0.5
		end) :: number
		local best = 0
		for other in Drops.treasure.spots do
			best = math.max(best, DropRules.treasureDistance(Drops, other, far()))
		end
		T.expect(DropRules.treasureDistance(Drops, index, far())).toBe(best)
	end)

	T.it("draws exactly one number, and needs a hiding place", function()
		local draws = 0
		DropRules.treasureSpot(Drops, far(), nil, function(): number
			draws += 1
			return 0.3
		end)
		T.expect(draws).toBe(1)
		local empty = copy(Drops)
		empty.treasure.spots = {}
		T.expect(DropRules.treasureSpot(empty, far(), nil, function(): number
			return 0
		end)).toBeNil()
	end)

	T.it("is found by walking into it, not from a jump over it or under the map", function()
		local range = Drops.treasure.pickupRange
		T.expect(DropRules.findsTreasure(Drops, range, 3)).toBe(true)
		T.expect(DropRules.findsTreasure(Drops, range + 0.1, 3)).toBe(false)
		T.expect(DropRules.findsTreasure(Drops, 0, 12)).toBe(false)
		T.expect(DropRules.findsTreasure(Drops, 0, -5)).toBe(false)
		T.expect(DropRules.findsTreasure(Drops, 0 / 0, 3)).toBe(false)
	end)

	T.it("pays a few seconds of income three times in four, else a Lucky Spin", function()
		local chances = DropRules.treasureChances(Drops.treasure.prizes)
		T.expect(chances[1]).toBeNear(0.75, 1e-9)
		T.expect(chances[2]).toBeNear(0.25, 1e-9)
		local first = DropRules.treasurePrize(Drops.treasure.prizes, 0) :: Types.PrizeReward
		local last = DropRules.treasurePrize(Drops.treasure.prizes, 0.99) :: Types.PrizeReward
		T.expect(first.kind).toBe("cash")
		T.expect(last.kind).toBe("spin")
		T.expect((DropRules.treasurePrize(Drops.treasure.prizes, 0.749) :: Types.PrizeReward).kind).toBe("cash")
		T.expect((DropRules.treasurePrize(Drops.treasure.prizes, 0.75) :: Types.PrizeReward).kind).toBe("spin")
		T.expect(DropRules.treasurePrize({ { weight = 0, reward = first } }, 0.5)).toBeNil()
	end)

	T.it("hides every fork on open ground: clear of the belt, the bases and everything on the map", function()
		local shape = SceneryLayout.mapShape(MAP :: any, Gameplay.belt :: any)
		local layout = SceneryLayout.layout(Scenery)
		local plaza = Scenery.plaza
		local boundary = Scenery.boundary
		local widest = 0
		for _, radius in MapThemeRules.FLORA_RADIUS do
			widest = math.max(widest, radius)
		end
		local seasonal: { SeasonRules.Prop } = {}
		for _, theme in Seasons.themes do
			for _, prop in SeasonRules.layout(theme.decorations, theme.palette, seasonMap()) do
				table.insert(seasonal, prop)
			end
		end
		local problems: { string } = {}
		local function needs(ok: boolean, index: number, what: string)
			if not ok then
				table.insert(problems, `spot {index} {what}`)
			end
		end
		for index, spot in Drops.treasure.spots do
			local x, z = spot.x, spot.z
			needs(
				x > boundary.minX + boundary.wallThickness + 3 and x < boundary.maxX - boundary.wallThickness - 3,
				index,
				"inside the boundary (X)"
			)
			needs(math.abs(z) < boundary.maxZ - boundary.wallThickness - 3, index, "inside the boundary (Z)")
			for _, rect in shape.plots do
				needs(SceneryLayout.rectDistance(rect, x, z) >= 3, index, "clear of the bases")
			end
			needs(SceneryLayout.rectDistance(shape.belt, x, z) >= 3, index, "clear of the belt")
			for _, rect in shape.structures do
				needs(SceneryLayout.rectDistance(rect, x, z) >= 3, index, "clear of the factory and the chute")
			end
			local function clear(px: number, pz: number, radius: number, what: string)
				needs(math.sqrt((x - px) ^ 2 + (z - pz) ^ 2) >= radius, index, `clear of {what}`)
			end
			clear(plaza.x, plaza.z, plaza.fountainRadius + 1.5, "the fountain")
			for _, bench in layout.benches do
				clear(bench.x, bench.z, SceneryLayout.RADIUS.bench + 1, "a bench")
			end
			for _, lamp in layout.lamps do
				clear(lamp.x, lamp.z, SceneryLayout.RADIUS.lamp + 1.5, "a lamp")
			end
			for _, bed in layout.flowerBeds do
				clear(bed.x, bed.z, SceneryLayout.RADIUS.flowerBed + 1, "a flower bed")
			end
			for _, side in { -1, 1 } do
				clear(plaza.archX, side * plaza.archSpan / 2, SceneryLayout.RADIUS.pillar + 1.5, "an arch pillar")
				-- each leaderboard faces the map's middle: 18 wide, its plinth 3.4 deep behind it
				local bx, bz = plaza.boardX, side * plaza.boardZ
				local length = math.sqrt(bx * bx + bz * bz)
				local nx, nz = -bx / length, -bz / length
				needs(segmentDistance(x, z, bx, bz, -nz, nx, 10) >= 3.5, index, "clear of a leaderboard")
			end
			local news = layout.newsBoard
			needs(
				segmentDistance(x, z, news.x, news.z, -math.sin(math.rad(news.yaw)), math.cos(math.rad(news.yaw)), 7)
					>= 2.5,
				index,
				"clear of the What's New board"
			)
			clear(MAP.lobby.x, MAP.lobby.z, 5, "the lobby spawn")
			for _, tree in layout.trees do
				if not tree.outside then
					-- any map's flora on that spot, at its scale
					clear(tree.x, tree.z, widest * tree.scale + 1.5, "a tree spot's flora")
				end
			end
			for _, prop in seasonal do
				clear(prop.x, prop.z, 6 * prop.scale, `a seasonal {prop.kind}`)
			end
		end
		T.expect(table.concat(problems, ", ")).toBe("")
	end)

	T.it("says where every hiding place is", function()
		local text = (Theme.text :: any) :: { [string]: string }
		for _, spot in Drops.treasure.spots do
			T.expect(type(text[spot.where])).toBe("string")
			local line = string.gsub(text.treasureHidden, "{where}", text[spot.where])
			T.expect(#line).toBeAtMost(80)
		end
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

	T.it("refuses broken golden forks", function()
		T.expect(broken(function(config)
			config.treasure.revealSeconds = config.treasure.lifetimeSeconds
		end)).toBe(1)
		T.expect(broken(function(config)
			config.treasure.prizes[1].reward = { kind = "creature", luck = 3 }
		end)).toBe(1)
		T.expect(broken(function(config)
			config.treasure.prizes[2].reward.count = 50
		end)).toBe(1)
		T.expect(broken(function(config)
			for _, prize in config.treasure.prizes do
				prize.weight = 0
			end
		end)).toBe(1)
		T.expect(broken(function(config)
			config.treasure.spots[1] = { x = 10, z = 0, where = "treasureWhereBench" } -- on the belt
		end)).toBe(1)
		T.expect(broken(function(config)
			config.treasure.spots = { config.treasure.spots[1] }
		end)).toBe(1)
		local config = copy(Drops)
		config.treasure.spots[1].where = "treasureWhereNowhere"
		T.expect(#DropRules.validate(config, WALKWAY, (Theme.text :: any) :: { [string]: string })).toBe(1)
	end)

	T.it("checks a modifier's drops", function()
		T.expect(#DropRules.dropsProblems({ kind = "crate", firstSeconds = 10, everySeconds = 75 }, 300, "x")).toBe(0)
		T.expect(#DropRules.dropsProblems({ kind = "runaway", firstSeconds = 6, everySeconds = 50 }, 300, "x")).toBe(0)
		T.expect(#DropRules.dropsProblems({ kind = "treasure", firstSeconds = 6, everySeconds = 42 }, 300, "x")).toBe(0)
		T.expect(#DropRules.dropsProblems({ kind = "pinata" :: any, firstSeconds = 10, everySeconds = 75 }, 300, "x"))
			.toBe(1)
		T.expect(#DropRules.dropsProblems({ kind = "coins", firstSeconds = 400, everySeconds = 75 }, 300, "x")).toBe(1)
		T.expect(#DropRules.dropsProblems({ kind = "coins", firstSeconds = 0, everySeconds = 1 }, 300, "x")).toBe(1)
	end)
end)

return nil
