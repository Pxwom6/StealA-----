--!strict
--[[
	Drop rules (Config/Drops, and Config/Modifiers `drops` for when): where a crate or a coin lands, the times a
	modifier drops something, what a pickup pays, whether a crate was held open long enough, where a runaway Snackling
	appears and runs, where a golden fork hides and what it pays, and validation. Pure: no Roblox APIs; random numbers
	come in as a function returning [0, 1).

	A runaway moves in legs: it waits at `from` until `startsAt`, then runs in a straight line to `to`, arriving at
	`endsAt`. The server plans the next leg when one ends (away from the players near it, sprinting when someone is
	close; now and then hopping over the belt to the other walkway) and publishes it as a string attribute; the client
	draws the runaway on the same leg, and the server checks catches against the same position (legPosition), so
	nothing is sent while it runs.
]]

local EconomyMath = require("./EconomyMath")
local Types = require("../Types")

type DropsConfig = Types.DropsConfig
type ModifierDrops = Types.ModifierDrops

local DropRules = {}

DropRules.KINDS =
	table.freeze({ crate = true, coins = true, runaway = true, treasure = true, boss = true } :: { [string]: boolean })

-- A horizontal position (world X, Z).
export type Point = { x: number, z: number }

-- One straight run of a runaway Snackling (server time): it waits at from until startsAt, then reaches to at endsAt.
export type Leg = { fromX: number, fromZ: number, toX: number, toZ: number, startsAt: number, endsAt: number }

-- A landing spot (world X, Z) on one of the two walkways, picked at random. Draws exactly three numbers.
function DropRules.position(
	area: { minX: number, maxX: number, minZ: number, maxZ: number },
	random: () -> number
): (number, number)
	local x = area.minX + (area.maxX - area.minX) * random()
	local z = area.minZ + (area.maxZ - area.minZ) * random()
	if random() < 0.5 then
		z = -z
	end
	return x, z
end

-- When a modifier running for `duration` seconds drops something: seconds after it starts, in order.
function DropRules.times(drops: ModifierDrops, duration: number): { number }
	local list: { number } = {}
	if not (drops.everySeconds > 0) then
		return list
	end
	local t = drops.firstSeconds
	while t < duration and #list < 200 do
		table.insert(list, t)
		t += drops.everySeconds
	end
	return list
end

-- What a reward pays a player with this steady income per second (sized like a cash pack, at least the minimum).
function DropRules.amount(reward: Types.IncomeReward, income: number): number
	return EconomyMath.cashPackAmount(income, { incomeSeconds = reward.incomeSeconds, minimum = reward.minimum })
end

-- Whether a crate hold that began at `startedAt` (nil: never began) may open it at `now`: held for at least the
-- configured time, less the network tolerance.
function DropRules.holdLongEnough(config: DropsConfig, startedAt: number?, now: number): boolean
	if startedAt == nil then
		return false
	end
	return now - startedAt >= config.crate.holdSeconds * config.crate.holdTolerance
end

-- Whether a player standing at horizontal distance `distance` (studs) from a coin picks it up.
function DropRules.inPickupRange(config: DropsConfig, horizontal: number, vertical: number): boolean
	return horizontal <= config.coins.pickupRange and math.abs(vertical) <= config.coins.height + 6
end

-- Runaways ------------------------------------------------------------------------------------------------------------

-- Horizontal distance from (x, z) to the nearest of `players` (math.huge with none).
local function nearest(players: { Point }, x: number, z: number): number
	local best = math.huge
	for _, point in players do
		local dx, dz = point.x - x, point.z - z
		best = math.min(best, math.sqrt(dx * dx + dz * dz))
	end
	return best
end

-- (x, z) moved onto the nearest walkway inside the drop area: a runaway may hop over the belt, never stop on it.
local function snapToWalkway(
	area: { minX: number, maxX: number, minZ: number, maxZ: number },
	x: number,
	z: number
): (number, number)
	local side = if z < 0 then -1 else 1
	return math.clamp(x, area.minX, area.maxX), math.clamp(math.abs(z), area.minZ, area.maxZ) * side
end

-- Where a runaway appears: of `candidates` random spots on the walkways (at least edgeMargin from their ends, so it has
-- room to run either way), the one farthest from every player, so nobody can wait for it (with no players, the
-- first). Draws exactly 3 numbers per candidate.
function DropRules.runawayStart(config: DropsConfig, players: { Point }, random: () -> number): (number, number)
	local area, margin = config.area, config.runaway.edgeMargin
	local inner = { minX = area.minX + margin, maxX = area.maxX - margin, minZ = area.minZ, maxZ = area.maxZ }
	local bestX, bestZ, bestScore = 0, 0, -math.huge
	for _ = 1, config.runaway.candidates do
		local x, z = DropRules.position(inner, random)
		local score = nearest(players, x, z)
		if score > bestScore then
			bestX, bestZ, bestScore = x, z, score
		end
	end
	return bestX, bestZ
end

-- Whether someone is near enough to scare a runaway at (x, z): it sprints, and barely stops at turns.
function DropRules.isFleeing(config: DropsConfig, x: number, z: number, players: { Point }): boolean
	return nearest(players, x, z) <= config.runaway.fleeRadius
end

-- Where a runaway at (x, z) runs next: of `candidates` random spots legMin..legMax away on a walkway, the one farthest
-- from the nearest player within fleeRadius (farther players don't scare it), with a little randomness so it never
-- runs the same way twice; with nobody near, it wanders. A spot on the other walkway (a hop over the belt) counts
-- beltHopPenalty studs less, so it only hops over when that really gets it away. Draws exactly 3 numbers per
-- candidate.
function DropRules.runawayTarget(
	config: DropsConfig,
	x: number,
	z: number,
	players: { Point },
	random: () -> number
): (number, number)
	local cfg = config.runaway
	local bestX, bestZ, bestScore = x, z, -math.huge
	for _ = 1, cfg.candidates do
		local angle = random() * math.pi * 2
		local distance = cfg.legMin + (cfg.legMax - cfg.legMin) * random()
		local jitter = random()
		local cx, cz = snapToWalkway(config.area, x + math.cos(angle) * distance, z + math.sin(angle) * distance)
		local score = math.min(nearest(players, cx, cz), cfg.fleeRadius) + jitter * cfg.legMin * 0.5
		if (cz < 0) ~= (z < 0) then
			score -= cfg.beltHopPenalty
		end
		if score > bestScore then
			bestX, bestZ, bestScore = cx, cz, score
		end
	end
	return bestX, bestZ
end

-- The leg from (x, z) to (toX, toZ) starting at `now`: a pause, then a run; both quicker while `fleeing`.
function DropRules.runawayLeg(
	config: DropsConfig,
	x: number,
	z: number,
	toX: number,
	toZ: number,
	now: number,
	fleeing: boolean
): Leg
	local cfg = config.runaway
	local startsAt = now + (if fleeing then cfg.sprintPauseSeconds else cfg.pauseSeconds)
	local speed = if fleeing then cfg.sprintSpeed else cfg.speed
	local dx, dz = toX - x, toZ - z
	return {
		fromX = x,
		fromZ = z,
		toX = toX,
		toZ = toZ,
		startsAt = startsAt,
		endsAt = startsAt + math.sqrt(dx * dx + dz * dz) / speed,
	}
end

-- How far along `leg` a runaway is at `t` (0 before it sets off, 1 once it arrived).
function DropRules.legProgress(leg: Leg, t: number): number
	if leg.endsAt <= leg.startsAt then
		return if t >= leg.endsAt then 1 else 0
	end
	return math.clamp((t - leg.startsAt) / (leg.endsAt - leg.startsAt), 0, 1)
end

-- Whether `leg` hops over the belt to the other walkway (the client draws a big jump).
function DropRules.crossesBelt(leg: Leg): boolean
	return (leg.fromZ < 0) ~= (leg.toZ < 0)
end

-- Where a runaway is at time `t` on `leg`, and whether it is running (false while it waits, and once it arrived).
function DropRules.legPosition(leg: Leg, t: number): (number, number, boolean)
	if t <= leg.startsAt then
		return leg.fromX, leg.fromZ, false
	elseif t >= leg.endsAt then
		return leg.toX, leg.toZ, false
	end
	local share = (t - leg.startsAt) / (leg.endsAt - leg.startsAt)
	return leg.fromX + (leg.toX - leg.fromX) * share, leg.fromZ + (leg.toZ - leg.fromZ) * share, true
end

-- A leg as text for an attribute (one value, so a client never sees half of a new leg), and back. decodeLeg is nil
-- for anything that isn't six finite numbers.
function DropRules.encodeLeg(leg: Leg): string
	return string.format(
		"%.2f,%.2f,%.2f,%.2f,%.3f,%.3f",
		leg.fromX,
		leg.fromZ,
		leg.toX,
		leg.toZ,
		leg.startsAt,
		leg.endsAt
	)
end

function DropRules.decodeLeg(text: string): Leg?
	local parts = string.split(text, ",")
	if #parts ~= 6 then
		return nil
	end
	local numbers: { number } = {}
	for index, part in parts do
		local value = tonumber(part)
		if value == nil or value ~= value or value == math.huge or value == -math.huge then
			return nil
		end
		numbers[index] = value
	end
	return {
		fromX = numbers[1],
		fromZ = numbers[2],
		toX = numbers[3],
		toZ = numbers[4],
		startsAt = numbers[5],
		endsAt = numbers[6],
	}
end

-- Whether a player whose root is `horizontal` studs from a runaway (and `vertical` above it) catches it. `slack` is
-- the extra reach the server allows (the player's position is a little behind on the server).
function DropRules.catches(config: DropsConfig, horizontal: number, vertical: number, slack: number): boolean
	return horizontal <= config.runaway.catchRange + slack and math.abs(vertical) <= 8
end

-- Treasure Hunt ------------------------------------------------------------------------------------------------------

-- Horizontal distance from spot `index` of the treasure config to the nearest of `players` (math.huge with none).
function DropRules.treasureDistance(config: DropsConfig, index: number, players: { Point }): number
	local spot = config.treasure.spots[index]
	return if spot then nearest(players, spot.x, spot.z) else 0
end

-- Which hiding place the next golden fork goes to: one at random of those at least minPlayerDistance from every player
-- (so nobody standing there finds it at once), never `last` (the previous fork's) while another will do; when none
-- is that far, the farthest from everyone. nil only with no spots. Draws exactly one number.
function DropRules.treasureSpot(config: DropsConfig, players: { Point }, last: number?, random: () -> number): number?
	local spots = config.treasure.spots
	local roll = random()
	local far: { number } = {}
	local best, bestDistance = nil :: number?, -math.huge
	for index in spots do
		if index == last and #spots > 1 then
			continue
		end
		local distance = DropRules.treasureDistance(config, index, players)
		if distance >= config.treasure.minPlayerDistance then
			table.insert(far, index)
		end
		if distance > bestDistance then
			best, bestDistance = index, distance
		end
	end
	if #far > 0 then
		return far[math.clamp(math.floor(roll * #far) + 1, 1, #far)]
	end
	return best
end

-- Whether a player whose root is `horizontal` studs from a fork (and `vertical` above its foot) walks into it.
function DropRules.findsTreasure(config: DropsConfig, horizontal: number, vertical: number): boolean
	return horizontal <= config.treasure.pickupRange and vertical >= -2 and vertical <= 8
end

-- The prize a found fork pays: one of `prizes` by weight (roll in [0, 1)). nil only with no prize of weight above 0.
function DropRules.treasurePrize(prizes: { Types.TreasurePrize }, roll: number): Types.PrizeReward?
	local total = 0
	for _, prize in prizes do
		if prize.weight > 0 then
			total += prize.weight
		end
	end
	if not (total > 0) then
		return nil
	end
	local left = math.clamp(roll, 0, 1) * total
	local chosen: Types.PrizeReward? = nil
	for _, prize in prizes do
		if prize.weight > 0 then
			chosen = prize.reward
			if left < prize.weight then
				return chosen
			end
			left -= prize.weight
		end
	end
	return chosen
end

-- The chance of each prize (weight / total), in config order: what the docs and BALANCE.md quote.
function DropRules.treasureChances(prizes: { Types.TreasurePrize }): { number }
	local total = 0
	for _, prize in prizes do
		total += math.max(0, prize.weight)
	end
	local list: { number } = {}
	for _, prize in prizes do
		table.insert(list, if total > 0 then math.max(0, prize.weight) / total else 0)
	end
	return list
end

-- Problems with Config/Drops (an empty list means valid). `walkway` is the band the walkways cover: |z| up to
-- `maxZ` (Gameplay.map.walkwayWidth) and |x| up to `maxX`, with the belt's half width `beltHalfWidth` in the middle.
-- `text` (Config/Theme.text, optional): every hiding place's `where` must be there.
function DropRules.validate(
	config: DropsConfig,
	walkway: { maxX: number, maxZ: number, beltHalfWidth: number },
	text: { [string]: string }?
): { string }
	local problems: { string } = {}
	local function problem(message: string)
		table.insert(problems, message)
	end
	local function positive(value: number, what: string)
		if not (value > 0 and value < math.huge) then
			problem(`{what} must be a positive number`)
		end
	end
	local function reward(value: Types.IncomeReward, what: string)
		if not (value.incomeSeconds >= 0 and value.incomeSeconds <= 600) then
			problem(`{what}.incomeSeconds must be between 0 and 600`)
		end
		if not (value.minimum >= 0 and value.minimum < math.huge) then
			problem(`{what}.minimum must be 0 or more`)
		end
	end

	local area = config.area
	if not (area.minX < area.maxX and area.minZ < area.maxZ) then
		problem("area must have minX < maxX and minZ < maxZ")
	end
	if not (area.minX >= -walkway.maxX and area.maxX <= walkway.maxX) then
		problem("area must stay along the walkways (X)")
	end
	if not (area.minZ > walkway.beltHalfWidth + 2 and area.maxZ < walkway.maxZ - 2) then
		problem("area must stay between the belt and the bases (Z)")
	end

	local crate = config.crate
	positive(crate.fallSeconds, "crate.fallSeconds")
	positive(crate.dropHeight, "crate.dropHeight")
	positive(crate.holdSeconds, "crate.holdSeconds")
	if not (crate.holdTolerance > 0 and crate.holdTolerance <= 1) then
		problem("crate.holdTolerance must be in (0, 1]")
	end
	positive(crate.openRange, "crate.openRange")
	positive(crate.lifetimeSeconds, "crate.lifetimeSeconds")
	if not (crate.luck >= 1 and crate.luck <= 6) then
		problem("crate.luck must be between 1 and 6")
	end
	if not (crate.mutationChance >= 1 and crate.mutationChance <= 4) then
		problem("crate.mutationChance must be between 1 and 4")
	end
	reward(crate.cash, "crate.cash")

	local coins = config.coins
	if not (coins.perWave >= 1 and coins.perWave <= 40 and coins.perWave % 1 == 0) then
		problem("coins.perWave must be a whole number from 1 to 40")
	end
	positive(coins.height, "coins.height")
	positive(coins.lifetimeSeconds, "coins.lifetimeSeconds")
	positive(coins.pickupRange, "coins.pickupRange")
	reward(coins.value, "coins.value")

	local runaway = config.runaway
	positive(runaway.speed, "runaway.speed")
	if not (runaway.sprintSpeed >= runaway.speed) then
		problem("runaway.sprintSpeed must be at least its speed")
	end
	if not (runaway.pauseSeconds >= 0 and runaway.pauseSeconds <= 3) then
		problem("runaway.pauseSeconds must be between 0 and 3")
	end
	if not (runaway.sprintPauseSeconds >= 0 and runaway.sprintPauseSeconds <= runaway.pauseSeconds) then
		problem("runaway.sprintPauseSeconds must be between 0 and pauseSeconds")
	end
	if not (runaway.edgeMargin >= 0 and runaway.edgeMargin * 2 < area.maxX - area.minX) then
		problem("runaway.edgeMargin must leave some walkway in the middle")
	end
	if not (runaway.beltHopPenalty >= 0) then
		problem("runaway.beltHopPenalty must be 0 or more")
	end
	if
		not (runaway.legMin > 0 and runaway.legMax >= runaway.legMin and runaway.legMax <= area.maxZ - area.minZ + 40)
	then
		problem("runaway legs need 0 < legMin <= legMax, and not much longer than the walkway is wide")
	end
	if not (runaway.candidates >= 1 and runaway.candidates <= 32 and runaway.candidates % 1 == 0) then
		problem("runaway.candidates must be a whole number from 1 to 32")
	end
	positive(runaway.fleeRadius, "runaway.fleeRadius")
	positive(runaway.catchRange, "runaway.catchRange")
	positive(runaway.lifetimeSeconds, "runaway.lifetimeSeconds")
	if not (runaway.luck >= 1 and runaway.luck <= 6) then
		problem("runaway.luck must be between 1 and 6")
	end
	if not (runaway.mutationChance >= 1 and runaway.mutationChance <= 4) then
		problem("runaway.mutationChance must be between 1 and 4")
	end

	local treasure = config.treasure
	if not (treasure.lifetimeSeconds >= 10 and treasure.lifetimeSeconds <= 120) then
		problem("treasure.lifetimeSeconds must be between 10 and 120")
	end
	if not (treasure.revealSeconds >= 0 and treasure.revealSeconds < treasure.lifetimeSeconds) then
		problem("treasure.revealSeconds must be 0 or more, and before it goes")
	end
	if not (treasure.pickupRange >= 1 and treasure.pickupRange <= 8) then
		problem("treasure.pickupRange must be between 1 and 8")
	end
	if not (treasure.minPlayerDistance >= 0 and treasure.minPlayerDistance <= 200) then
		problem("treasure.minPlayerDistance must be between 0 and 200")
	end
	local weighted = 0
	for index, prize in treasure.prizes do
		local name = `treasure.prizes[{index}]`
		if not (prize.weight >= 0 and prize.weight < math.huge) then
			problem(`{name}.weight must be 0 or more`)
		elseif prize.weight > 0 then
			weighted += 1
		end
		local prizeReward = prize.reward
		if prizeReward.kind == "cash" then
			reward({ incomeSeconds = prizeReward.incomeSeconds, minimum = prizeReward.minimum }, `{name}.reward`)
		elseif prizeReward.kind == "spin" then
			if not (prizeReward.count >= 1 and prizeReward.count <= 3 and prizeReward.count % 1 == 0) then
				problem(`{name}.reward.count must be a whole number from 1 to 3`)
			end
		else
			problem(`{name}.reward must be cash or a spin`)
		end
	end
	if weighted == 0 then
		problem("treasure.prizes needs a prize with a weight above 0")
	end
	if #treasure.spots < 4 then
		problem("treasure.spots needs at least 4 hiding places")
	end
	for index, spot in treasure.spots do
		local name = `treasure.spots[{index}]`
		if not (math.abs(spot.x) < 1000 and math.abs(spot.z) < 1000) then
			problem(`{name} must be a finite position on the map`)
		elseif math.abs(spot.z) <= walkway.beltHalfWidth + 2 and math.abs(spot.x) <= walkway.maxX + 6 then
			problem(`{name} is on the belt`)
		end
		if text and (type(text[spot.where]) ~= "string" or text[spot.where] == "") then
			problem(`{name}.where must be a Theme.text key ({spot.where} is not)`)
		end
	end
	return problems
end

-- Problems with a modifier's `drops` (see ModifierRules.validate); `name` starts each message.
function DropRules.dropsProblems(drops: ModifierDrops, duration: number, name: string): { string }
	local problems: { string } = {}
	if not DropRules.KINDS[drops.kind] then
		table.insert(problems, `{name} drops.kind {drops.kind} is not crate, coins, runaway, treasure or boss`)
	end
	if not (drops.firstSeconds >= 0 and drops.firstSeconds < duration) then
		table.insert(problems, `{name} drops.firstSeconds must be at least 0 and before the modifier ends`)
	end
	if not (drops.everySeconds >= 10) then
		table.insert(problems, `{name} drops.everySeconds must be at least 10`)
	end
	return problems
end

return DropRules
