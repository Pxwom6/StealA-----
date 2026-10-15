--!strict
--[[
	Economy simulation: `lune run tools/simulate.luau`

	Simulates a single player building a base from scratch, using the REAL config (creatures, rarity weights,
	mutations, belt timing, podium prices, rebirth cost) and the same pure logic the game runs (RarityRoll,
	MutationRules, EconomyMath, RebirthMath). Prints the tables used in BALANCE.md. Re-run after any balance change.

	Model (deliberately simple and a little pessimistic):
	  * the player stands at the belt and collects continuously (real players walk back to collect pads)
	  * every belt spawn is considered; other players compete, so a wanted item is won with p = CONTEST_WIN
	  * every spawn rolls its mutation like the server (own RNG stream, so the creature rolls match a run without
	    mutations); mutated items cost and earn their mutated price and income. The map changes every
	    `rotation.mapSeconds` in Config/MapThemes order, so its signature mutation can roll; weather modifiers (and
	    every other server modifier) are left out
	  * an item is affordable if cash + LOOKAHEAD seconds of income covers it (items take 30s to cross the belt)
	  * free podium → buy anything affordable; full base → buy only upgrades over the worst Snackling, selling it
	  * podiums are bought when full and the next one costs at most half of current cash
	  * no stealing, no offline earnings, no daily rewards, no luck boosts (all of these only speed things up)
	  * the main tables run with no LiveOps event; the "During an event" tables replay the free player with every
	    spawn rolled as if the event ran for the whole session (event Snacklings and mutations eligible), with and
	    without the event's luck days. The event defaults to Halloween; another one is chosen by its ids:
	        lune run tools/simulate.luau Winter2026 WinterLuck2026 "Christmas luck"
	  * "Gadgets" replays the free player saving for each gadget of Config/Gadgets in shop order: once the next one
	    costs at most GADGET_SAVE_SECONDS of their income they stop buying Snacklings and podiums until they have it
	  * "Store additions" (exact, no simulation) is what the Lucky Spin packs and the Starter Pack pay at a few steady
	    incomes, beside the cash packs at about the same price; `lune run tools/simulate.luau store` prints only it
]]

local process = require("@lune/process")

local Creatures = require("../src/shared/Config/Creatures")
local Mutations = require("../src/shared/Config/Mutations")
local Rarities = require("../src/shared/Config/Rarities")
local Economy = require("../src/shared/Config/Economy")
local Gadgets = require("../src/shared/Config/Gadgets")
local Theme = require("../src/shared/Config/Theme")
local Gameplay = require("../src/shared/Config/Gameplay")
local Monetization = require("../src/shared/Config/Monetization")
local LiveOps = require("../src/shared/Config/LiveOps")
local MapThemes = require("../src/shared/Config/MapThemes")
local Modifiers = require("../src/shared/Config/Modifiers")
local Types = require("../src/shared/Types")
local Catalog = require("../src/shared/Logic/Catalog")
local EconomyMath = require("../src/shared/Logic/EconomyMath")
local Format = require("../src/shared/Logic/Format")
local MutationRules = require("../src/shared/Logic/MutationRules")
local RarityRoll = require("../src/shared/Logic/RarityRoll")
local RebirthMath = require("../src/shared/Logic/RebirthMath")
local SpinRules = require("../src/shared/Logic/SpinRules")
local Spin = require("../src/shared/Config/Spin")

local RUNS = 60
local HOURS = 24
local CONTEST_WIN = 0.6
local LOOKAHEAD = 10
-- The gadget model: a gadget is worth saving for once it costs at most this many seconds of income.
local GADGET_SAVE_SECONDS = 120

local catalog = Catalog.build(Creatures, Rarities, Mutations)

-- Store additions -------------------------------------------------------------------------------------------------
-- What the Lucky Spin packs and the Starter Pack pay at a few steady incomes (EconomyMath.packIncome: what cash packs
-- and prizes are sized from), beside the cash packs at about the same price. Exact: every cash prize is sized from
-- steady income like a cash pack, so no simulation is needed.
local function printStoreTable()
	local chances = SpinRules.chances(Spin.segments)
	-- One spin: its expected cash at `income`, and its chance of a Snackling.
	local function perSpin(income: number): (number, number)
		local cash, snackling = 0, 0
		for index, segment in Spin.segments do
			local reward = segment.reward
			if reward.kind == "cash" then
				local pack = { incomeSeconds = reward.incomeSeconds, minimum = reward.minimum }
				cash += chances[index] * EconomyMath.cashPackAmount(income, pack)
			elseif reward.kind == "creature" then
				snackling += chances[index]
			end
		end
		return cash, snackling
	end
	local starter = Monetization.starterPack
	local creature = catalog.creatures[starter.creatureId]
	local creaturePrice = MutationRules.price(catalog.mutations, creature, starter.variant)
	local creatureIncome = MutationRules.income(catalog.mutations, creature, starter.variant)
	local gadgetsPrice = 0
	for _, id in starter.gadgets do
		gadgetsPrice += Gadgets.gadgets[id].price
	end
	local function money(amount: number): string
		return Format.cash(amount, "$")
	end
	local function minutes(amount: number, income: number): string
		return if income > 0 then ` ({math.floor(amount / income / 60 + 0.5)} min)` else ""
	end
	local _, chance = perSpin(0)
	print("\n## Store additions: what each pays at a few steady incomes\n")
	print(
		`A spin wins a Snackling {Format.percent(chance)} of the time (Golden or Diamond included); the cash below is `
			.. "the average a spin pays. The Starter Pack's own column counts its "
			.. `{MutationRules.displayName(catalog.mutations, creature, starter.variant, Theme.text.mutatedName)} `
			.. `at its belt price ({money(creaturePrice)}, `
			.. `earning {money(creatureIncome)}/s) and its gadgets at their cash prices ({money(gadgetsPrice)}).\n`
	)
	local small = Monetization.products.LuckySpins3.spins or 0
	local big = Monetization.products.LuckySpins10.spins or 0
	print(
		`| Steady income | {small} Lucky Spins | {big} Lucky Spins | Starter Pack: cash | Starter Pack: all of it `
			.. "| Snack Pack (25 R$) | Snack Basket (49 R$) | Snack Crate (75 R$) |"
	)
	print("| --- | --- | --- | --- | --- | --- | --- | --- |")
	for _, income in { 0, 100, 1000, 10000, 100000, 1000000 } do
		local spinCash = perSpin(income)
		local starterCash = EconomyMath.cashPackAmount(income, starter.cash)
		local whole = starterCash + creaturePrice + gadgetsPrice
		local packs: { string } = {}
		for _, key in { "CashSmall", "CashBasket", "CashMedium" } do
			local pack = (Economy.cashPacks :: any)[key] :: Economy.CashPack
			local amount = EconomyMath.cashPackAmount(income, pack)
			table.insert(packs, money(amount) .. minutes(amount, income))
		end
		local function spins(count: number): string
			local cash = count * spinCash
			return `{money(cash)}{minutes(cash, income)} + {string.format("%.1f", count * chance)} Snacklings`
		end
		print(
			`| {money(income)}/s | {spins(small)} | {spins(big)} | {money(starterCash)}{minutes(starterCash, income)} `
				.. `| {money(whole)} | {table.concat(packs, " | ")} |`
		)
	end
end

if process.args[1] == "store" then
	printStoreTable()
	process.exit(0)
end

type Scenario = {
	name: string,
	multiplier: number,
	extraPodiums: number,
	events: { [string]: boolean }?, -- active LiveOps events (default none)
	luck: number?, -- belt luck (default 1)
	gadgets: { number }?, -- gadget prices to save for, in shop order (see GADGET_SAVE_SECONDS)
}
-- One Snackling in the simulated base, with its mutated price and income.
type Owned = { def: Types.CreatureDef, price: number, income: number }
type RunResult = {
	firstTier: { [string]: number },
	rebirthReadyAt: number?,
	incomeAt: { [number]: number },
	eventBought: number, -- event Snacklings bought
	firstEventAt: number?, -- play time of the first event Snackling bought
	gadgetAt: { [number]: number }, -- play time each gadget (by shop index) was bought
	gadgetIncome: { [number]: number }, -- income per second when it was bought
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

-- The seasonal event the "During an event" tables simulate, and its luck event's multiplier (Config/LiveOps).
local EVENT_ID = process.args[1] or "Halloween2026"
local EVENT_LUCK_ID = process.args[2] or "HalloweenLuck2026"
local EVENT_LUCK_LABEL = process.args[3] or "luck weekend"
local eventLuck = 1
for _, event in LiveOps.events do
	if event.id == EVENT_LUCK_ID then
		eventLuck = event.luckMultiplier or 1
	end
end

local EVENT_SCENARIOS: { Scenario } = {
	{ name = `Free player, {EVENT_ID}`, multiplier = 1, extraPodiums = 0, events = { [EVENT_ID] = true } },
	{
		name = `Free player, {EVENT_ID} + {eventLuck}x {EVENT_LUCK_LABEL}`,
		multiplier = 1,
		extraPodiums = 0,
		events = { [EVENT_ID] = true, [EVENT_LUCK_ID] = true },
		luck = eventLuck,
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
	local mutationRng = seededRandom(seed + 104729)
	local cash = Economy.startingCash
	local owned: { Owned } = {}
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
		for _, entry in owned do
			table.insert(incomes, entry.income)
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

	local events = scenario.events or {}
	local luck = scenario.luck or 1
	-- The mutation conditions on each map (the events plus that map's signature), worked out once.
	local onMap: { { [string]: boolean } } = {}
	for index, themeId in MapThemes.order do
		onMap[index] = MutationRules.conditions(events, themeId, nil)
	end
	local eventBought = 0
	local firstEventAt: number? = nil
	local gadgetPrices = scenario.gadgets or {}
	local gadgetAt: { [number]: number } = {}
	local gadgetIncome: { [number]: number } = {}
	local nextGadget = 1
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
		-- Saving for the next gadget: buy it once the cash is there; nothing else is bought meanwhile.
		local saving = false
		local price = gadgetPrices[nextGadget]
		if price and price <= currentIncome * GADGET_SAVE_SECONDS then
			if cash >= price then
				cash -= price
				gadgetAt[nextGadget] = t
				gadgetIncome[nextGadget] = currentIncome
				nextGadget += 1
			else
				saving = true
			end
		end

		local id = RarityRoll.roll(catalog.rarityList, catalog.creatureList, luck, events, rng)
		local map = math.floor(t / MapThemes.rotation.mapSeconds) % #MapThemes.order + 1
		local variant = MutationRules.roll(catalog.mutationList, onMap[map], mutationRng)
		local def = if id then catalog.creatures[id] else nil
		local item: Owned? = if def
			then {
				def = def,
				price = MutationRules.price(catalog.mutations, def, variant),
				income = MutationRules.income(catalog.mutations, def, variant),
			}
			else nil
		if item and not saving and rng() < CONTEST_WIN and cash + currentIncome * LOOKAHEAD >= item.price then
			if #owned < capacity() then
				cash -= item.price
				table.insert(owned, item)
			else
				local worstIndex, worstIncome = 0, math.huge
				for index, entry in owned do
					if entry.income < worstIncome then
						worstIndex, worstIncome = index, entry.income
					end
				end
				if item.income > worstIncome then
					cash += EconomyMath.sellValue(owned[worstIndex].price, Economy.sellRefund) - item.price
					owned[worstIndex] = item
				end
			end
			if firstTier[item.def.rarity] == nil and table.find(owned, item) then
				firstTier[item.def.rarity] = t
			end
			if item.def.eventId ~= nil and table.find(owned, item) then
				eventBought += 1
				firstEventAt = firstEventAt or t
			end
			currentIncome = income()
		end

		if #owned >= capacity() and not saving then
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
	return {
		firstTier = firstTier,
		rebirthReadyAt = rebirthReadyAt,
		incomeAt = incomeAt,
		eventBought = eventBought,
		firstEventAt = firstEventAt,
		gadgetAt = gadgetAt,
		gadgetIncome = gadgetIncome,
	}
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
local function runAll(scenarios: { Scenario })
	for _, scenario in scenarios do
		if results[scenario.name] == nil then
			local list: { RunResult } = {}
			for run = 1, RUNS do
				table.insert(list, simulate(scenario, run * 7919))
			end
			results[scenario.name] = list
		end
	end
end

local function printTables(scenarios: { Scenario }, tierHeading: string, incomeHeading: string)
	local names: { string } = {}
	for _, scenario in scenarios do
		table.insert(names, scenario.name)
	end
	local header = "| Rarity | " .. table.concat(names, " | ") .. " |"
	local divider = "| --- |" .. string.rep(" --- |", #scenarios)

	print(tierHeading .. "\n")
	print(header)
	print(divider)
	for _, rarity in catalog.rarityList do
		local cells: { string } = {}
		for _, scenario in scenarios do
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
	for _, scenario in scenarios do
		local values: { number } = {}
		for _, result in results[scenario.name] do
			if result.rebirthReadyAt then
				table.insert(values, result.rebirthReadyAt)
			end
		end
		table.insert(rebirthCells, cell(values, RUNS))
	end
	print(`| First rebirth affordable | {table.concat(rebirthCells, " | ")} |`)

	print(`\n{incomeHeading}\n`)
	print((string.gsub(header, "Rarity", "Play time")))
	print(divider)
	for _, checkpoint in CHECKPOINTS do
		local cells: { string } = {}
		for _, scenario in scenarios do
			local values: { number } = {}
			for _, result in results[scenario.name] do
				table.insert(values, result.incomeAt[checkpoint] or 0)
			end
			table.insert(cells, Format.cash(median(values) or 0, "$") .. "/s")
		end
		print(`| {Format.duration(checkpoint)} | {table.concat(cells, " | ")} |`)
	end
end

local spawnsPerHour = 3600 / Gameplay.belt.spawnInterval
local function perHour(chance: number): number
	return math.floor(chance * spawnsPerHour * 10 + 0.5) / 10
end

-- When a mutation can roll, for the table.
local function whenText(mutation: Types.MutationDef): string
	if mutation.eventId then
		return `during {mutation.eventId}`
	elseif mutation.mapTheme then
		local theme = MapThemes.themes[mutation.mapTheme]
		return `on {if theme then theme.displayName else mutation.mapTheme}`
	elseif mutation.modifierId then
		local modifier = Modifiers.modifiers[mutation.modifierId]
		return `during {if modifier then modifier.displayName else mutation.modifierId}`
	end
	return "always"
end

-- Every mutation that can roll with `events` running, on any map and under any modifier: the chance is per spawn
-- while it can roll ("Per server-hour" too). The summary line is for an ordinary spawn: the events, the map's own
-- signature mutation, no modifier.
local function printMutations(events: { [string]: boolean })
	print("| Mutation | When | Chance per spawn | Per server-hour | Income | Price | Payback vs plain | Announced |")
	print("| --- | --- | --- | --- | --- | --- | --- | --- |")
	local everything = table.clone(events)
	for _, mutation in catalog.mutationList do
		if mutation.mapTheme then
			everything[MutationRules.mapKey(mutation.mapTheme)] = true
		elseif mutation.modifierId then
			everything[MutationRules.modifierKey(mutation.modifierId)] = true
		end
	end
	for _, entry in MutationRules.odds(catalog.mutationList, everything) do
		local mutation = catalog.mutations[entry.id]
		local announced: { string } = {}
		if mutation.announceOnSpawn then
			table.insert(announced, "spawn")
		end
		if mutation.announceOnBuy then
			table.insert(announced, "buy")
		end
		if mutation.announceOnSteal then
			table.insert(announced, "steal")
		end
		print(
			`| {mutation.displayName} | {whenText(mutation)} | {Format.percent(entry.chance)} | {perHour(entry.chance)} `
				.. `| x{mutation.incomeMultiplier} | x{mutation.priceMultiplier} `
				.. `| x{math.floor(mutation.priceMultiplier / mutation.incomeMultiplier * 100 + 0.5) / 100} `
				.. `| {if #announced > 0 then table.concat(announced, ", ") else "no"} |`
		)
	end
	local ordinary = MutationRules.conditions(events, MapThemes.order[1], nil)
	local expectedIncome, expectedPrice = MutationRules.expectedMultipliers(catalog.mutationList, ordinary)
	local anyChance = 0
	for _, entry in MutationRules.odds(catalog.mutationList, ordinary) do
		anyChance += entry.chance
	end
	print(
		`\nAny mutation on an ordinary spawn (the map's signature included, no modifier): {Format.percent(anyChance)} `
			.. `of spawns ({perHour(anyChance)} per server-hour). Expected value of one spawn: income `
			.. `x{math.floor(expectedIncome * 10000 + 0.5) / 10000}, price x{math.floor(expectedPrice * 10000 + 0.5) / 10000}.`
	)
end

runAll(SCENARIOS)
printTables(
	SCENARIOS,
	`## Median play time until the first Snackling of each rarity ({RUNS} runs, {HOURS}h cap)`,
	"## Median cash/sec after N minutes of play"
)

print(`\n## Mutations (per belt spawn, any rarity; luck never changes these)\n`)
printMutations({})

-- During an event ----------------------------------------------------------------------------------------------

local eventScenarios: { Scenario } = { SCENARIOS[1] } -- the free player without the event, for comparison
for _, scenario in EVENT_SCENARIOS do
	table.insert(eventScenarios, scenario)
end
runAll(eventScenarios)
print(`\n## During an event: {EVENT_ID} running for the whole session (free player)\n`)
printTables(
	eventScenarios,
	`### Median play time until the first Snackling of each rarity ({RUNS} runs, {HOURS}h cap)`,
	"### Median cash/sec after N minutes of play"
)

print(`\n### {EVENT_ID} Snacklings on the belt (they share their tier's odds)\n`)
print("| Snackling | Rarity | Price | Income | Payback | Share of its tier | Per server-hour | With 2x luck |")
print("| --- | --- | --- | --- | --- | --- | --- | --- |")
local eventIds = { [EVENT_ID] = true }
local tierOdds = RarityRoll.odds(catalog.rarityList, catalog.creatureList, 1, eventIds)
local luckyOdds = RarityRoll.odds(catalog.rarityList, catalog.creatureList, 2, eventIds)
for _, def in catalog.creatureList do
	if def.eventId ~= EVENT_ID then
		continue
	end
	local tierWeight = 0
	for _, other in catalog.byRarity[def.rarity] do
		if other.eventId == nil or eventIds[other.eventId] then
			tierWeight += other.beltWeight
		end
	end
	local share = def.beltWeight / tierWeight
	local tierChance, luckyChance = 0, 0
	for index, entry in tierOdds do
		if entry.id == def.rarity then
			tierChance, luckyChance = entry.chance, luckyOdds[index].chance
		end
	end
	print(
		`| {def.displayName} | {def.rarity} | {Format.cash(def.price, "$")} | {Format.cash(def.income, "$")}/s `
			.. `| {Format.duration(def.price / def.income)} | {Format.percent(share)} `
			.. `| {perHour(tierChance * share)} | {perHour(luckyChance * share)} |`
	)
end

for _, scenario in EVENT_SCENARIOS do
	local bought: { number } = {}
	local first: { number } = {}
	for _, result in results[scenario.name] do
		table.insert(bought, result.eventBought)
		if result.firstEventAt then
			table.insert(first, result.firstEventAt)
		end
	end
	print(
		`\n{scenario.name}: median {median(bought) or 0} event Snacklings bought in {HOURS}h, first one after `
			.. `{cell(first, RUNS)}.`
	)
end

print(`\n### Mutations while {EVENT_ID} runs\n`)
printMutations(eventIds)

-- Gadgets ----------------------------------------------------------------------------------------------------------

local gadgetPrices: { number } = {}
for _, id in Gadgets.order do
	table.insert(gadgetPrices, Gadgets.gadgets[id].price)
end
local gadgetScenario: Scenario = {
	name = "Free player buying every gadget",
	multiplier = 1,
	extraPodiums = 0,
	gadgets = gadgetPrices,
}
local gadgetScenarios: { Scenario } = { SCENARIOS[1], gadgetScenario }
runAll(gadgetScenarios)
print(
	`\n## Gadgets: a free player saving for each one in shop order, once it costs at most {GADGET_SAVE_SECONDS} s of `
		.. "their income\n"
)
print("| Gadget | Price | Bought after (median) | Income then (median) | Price in seconds of that income |")
print("| --- | --- | --- | --- | --- |")
for index, id in Gadgets.order do
	local def = Gadgets.gadgets[id]
	local times: { number } = {}
	local incomes: { number } = {}
	for _, result in results[gadgetScenario.name] do
		local at = result.gadgetAt[index]
		if at then
			table.insert(times, at)
			table.insert(incomes, result.gadgetIncome[index])
		end
	end
	local income = median(incomes) or 0
	local name = ((Theme.text :: any) :: { [string]: string })[def.nameKey] or id
	print(
		`| {def.icon} {name} | {Format.cash(def.price, "$")} | {cell(times, RUNS)} | {Format.cash(income, "$")}/s `
			.. `| {if income > 0 then math.floor(def.price / income + 0.5) else "-"} |`
	)
end
printTables(
	gadgetScenarios,
	`\n### Median play time until the first Snackling of each rarity, with and without the gadgets ({RUNS} runs)`,
	"### Median cash/sec after N minutes of play, with and without the gadgets"
)

printStoreTable()
