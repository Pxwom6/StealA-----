--!strict
--[[
	Drop rules (Config/Drops, and Config/Modifiers `drops` for when): where a crate or a coin lands, the times a
	modifier drops something, what a pickup pays, whether a crate was held open long enough, and validation.
	Pure: no Roblox APIs; random numbers come in as a function returning [0, 1).
]]

local EconomyMath = require("./EconomyMath")
local Types = require("../Types")

type DropsConfig = Types.DropsConfig
type ModifierDrops = Types.ModifierDrops

local DropRules = {}

DropRules.KINDS = table.freeze({ crate = true, coins = true } :: { [string]: boolean })

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

-- Problems with Config/Drops (an empty list means valid). `walkway` is the band the walkways cover: |z| up to
-- `maxZ` (Gameplay.map.walkwayWidth) and |x| up to `maxX`, with the belt's half width `beltHalfWidth` in the middle.
function DropRules.validate(
	config: DropsConfig,
	walkway: { maxX: number, maxZ: number, beltHalfWidth: number }
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
	return problems
end

-- Problems with a modifier's `drops` (see ModifierRules.validate); `name` starts each message.
function DropRules.dropsProblems(drops: ModifierDrops, duration: number, name: string): { string }
	local problems: { string } = {}
	if not DropRules.KINDS[drops.kind] then
		table.insert(problems, `{name} drops.kind {drops.kind} is not crate or coins`)
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
