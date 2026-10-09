--!strict
--[[
	Economy simulation: `lune run tools/simulate.luau`

	Simulates a single player building a base from scratch, using the REAL config (creatures, rarity weights,
	belt timing, podium prices, rebirth cost) and the same pure logic the game runs (RarityRoll, EconomyMath,
	RebirthMath). Prints the tables used in BALANCE.md. Re-run after any balance change.

	Model (deliberately simple and a little pessimistic):
	  * the player stands at the belt and collects continuously (real players walk back to collect pads)
	  * every belt spawn is considered; other players compete, so a wanted item is won with p = CONTEST_WIN
	  * an item is affordable if cash + LOOKAHEAD seconds of income covers it (items take 30s to cross the belt)
	  * free podium → buy anything affordable; full base → buy only upgrades over the worst Snackling, selling it
	  * podiums are bought when full and the next one costs at most half of current cash
	  * no stealing, no offline earnings, no daily rewards, no luck boosts (all of these only speed things up)
]]

local Creatures = require("../src/shared/Config/Creatures")
local Rarities = require("../src/shared/Config/Rarities")
local Economy = require("../src/shared/Config/Economy")
local Gameplay = require("../src/shared/Config/Gameplay")
local Monetization = require("../src/shared/Config/Monetization")
local Types = require("../src/shared/Types")
local Catalog = require("../src/shared/Logic/Catalog")
local EconomyMath = require("../src/shared/Logic/EconomyMath")
local Format = require("../src/shared/Logic/Format")
local RarityRoll = require("../src/shared/Logic/RarityRoll")
local RebirthMath = require("../src/shared/Logic/RebirthMath")

local RUNS = 60
local HOURS = 24
local CONTEST_WIN = 0.6
local LOOKAHEAD = 10

local catalog = Catalog.build(Creatures, Rarities)

type Scenario = { name: string, multiplier: number, extraPodiums: number }
type RunResult = {
	firstTier: { [string]: number },
	rebirthReadyAt: number?,
	incomeAt: { [number]: number },
}

local SCENARIOS: { Scenario } = {
	{ name = "Free player", multiplier = 1, extraPodiums = 0 },
	{
		name = "2x Cash pass",
		multiplier = Monetization.perks.doubleCashMultiplier,
		extraPodiums = 0,
	},
	{
		name = "2x Cash + VIP + Extra Podiums",
		multiplier = Monetization.perks.doubleCashMultiplier * (1 + Monetization.perks.vipIncomeBonus),
		extraPodiums = Monetization.perks.extraPodiums,
	},
}

local CHECKPOINTS = { 10 * 60, 30 * 60, 60 * 60, 3 * 3600, 8 * 3600, 24 * 3600 }

local function seededRandom(seed: number): () -> number
	local state = seed % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	return function(): number
		state = (state * 48271) % 2147483647
		return (state - 1) / 2147483646
	end
end

local function simulate(scenario: Scenario, seed: number): RunResult
	local rng = seededRandom(seed)
	local cash = Economy.startingCash
	local owned: { Types.CreatureDef } = {}
	local upgrades = 0
	local firstTier: { [string]: number } = {}
	local rebirthReadyAt: number? = nil
	local incomeAt: { [number]: number } = {}
	local rebirthCost = RebirthMath.cost(0, Economy.rebirth) or math.huge
	local interval = Gameplay.belt.spawnInterval
	local horizon = HOURS * 3600
	local nextCheckpoint = 1

	local function income(): number
		local incomes: { number } = {}
		for _, def in owned do
			table.insert(incomes, def.income)
		end
		return EconomyMath.totalIncome(incomes, scenario.multiplier)
	end
	local function capacity(): number
		return EconomyMath.podiumCapacity(
			Economy.startingPodiums,
			upgrades,
			scenario.extraPodiums,
			Gameplay.map.maxPodiums
		)
	end

	local currentIncome = 0
	local t = 0
	while t < horizon do
		t += interval
		cash += currentIncome * interval
		while nextCheckpoint <= #CHECKPOINTS and t >= CHECKPOINTS[nextCheckpoint] do
			incomeAt[CHECKPOINTS[nextCheckpoint]] = currentIncome
			nextCheckpoint += 1
		end
		if rebirthReadyAt == nil and cash >= rebirthCost then
			rebirthReadyAt = t
		end

		local id = RarityRoll.roll(catalog.rarityList, catalog.creatureList, 1, {}, rng)
		local def = if id then catalog.creatures[id] else nil
		if def and rng() < CONTEST_WIN and cash + currentIncome * LOOKAHEAD >= def.price then
			if #owned < capacity() then
				cash -= def.price
				table.insert(owned, def)
			else
				local worstIndex, worstIncome = 0, math.huge
				for index, ownedDef in owned do
					if ownedDef.income < worstIncome then
						worstIndex, worstIncome = index, ownedDef.income
					end
				end
				if def.income > worstIncome then
					cash += EconomyMath.sellValue(owned[worstIndex].price, Economy.sellRefund) - def.price
					owned[worstIndex] = def
				end
			end
			if firstTier[def.rarity] == nil and table.find(owned, def) then
				firstTier[def.rarity] = t
			end
			currentIncome = income()
		end

		if #owned >= capacity() then
			local cost = EconomyMath.podiumUpgradeCost(upgrades, Economy.podiumUpgrade)
			if cost and cost <= cash * 0.5 and capacity() < Gameplay.map.maxPodiums then
				cash -= cost
				upgrades += 1
			end
		end
	end
	for _, checkpoint in CHECKPOINTS do
		if incomeAt[checkpoint] == nil then
			incomeAt[checkpoint] = currentIncome
		end
	end
	return { firstTier = firstTier, rebirthReadyAt = rebirthReadyAt, incomeAt = incomeAt }
end

local function median(values: { number }): number?
	if #values == 0 then
		return nil
	end
	table.sort(values)
	return values[math.floor((#values + 1) / 2)]
end

local function cell(values: { number }, runs: number): string
	local m = median(values)
	if m == nil or #values < runs / 2 then
		return `> {HOURS}h ({math.floor(#values / runs * 100)}% got one)`
	end
	return `{Format.duration(m)}`
end

local results: { [string]: { RunResult } } = {}
for _, scenario in SCENARIOS do
	local list: { RunResult } = {}
	for run = 1, RUNS do
		table.insert(list, simulate(scenario, run * 7919))
	end
	results[scenario.name] = list
end

local header = "| Rarity | "
	.. table.concat(
		(function(): { string }
			local names: { string } = {}
			for _, scenario in SCENARIOS do
				table.insert(names, scenario.name)
			end
			return names
		end)(),
		" | "
	)
	.. " |"
local divider = "| --- |" .. string.rep(" --- |", #SCENARIOS)

print(`## Median play time until the first Snackling of each rarity ({RUNS} runs, {HOURS}h cap)\n`)
print(header)
print(divider)
for _, rarity in catalog.rarityList do
	local cells: { string } = {}
	for _, scenario in SCENARIOS do
		local values: { number } = {}
		for _, result in results[scenario.name] do
			local first = result.firstTier[rarity.id]
			if first then
				table.insert(values, first)
			end
		end
		table.insert(cells, cell(values, RUNS))
	end
	print(`| {rarity.displayName} | {table.concat(cells, " | ")} |`)
end

local rebirthCells: { string } = {}
for _, scenario in SCENARIOS do
	local values: { number } = {}
	for _, result in results[scenario.name] do
		if result.rebirthReadyAt then
			table.insert(values, result.rebirthReadyAt)
		end
	end
	table.insert(rebirthCells, cell(values, RUNS))
end
print(`| First rebirth affordable | {table.concat(rebirthCells, " | ")} |`)

print(`\n## Median cash/sec after N minutes of play\n`)
print((string.gsub(header, "Rarity", "Play time")))
print(divider)
for _, checkpoint in CHECKPOINTS do
	local cells: { string } = {}
	for _, scenario in SCENARIOS do
		local values: { number } = {}
		for _, result in results[scenario.name] do
			table.insert(values, result.incomeAt[checkpoint] or 0)
		end
		table.insert(cells, Format.cash(median(values) or 0, "$") .. "/s")
	end
	print(`| {Format.duration(checkpoint)} | {table.concat(cells, " | ")} |`)
end
