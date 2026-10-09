--!strict
--[[
	Cash maths: income multipliers, podium capacity and upgrade costs, sell values, income-scaled cash packs.
	Pure: no requires, no Roblox APIs. All amounts are whole numbers of cash unless stated otherwise.
]]

export type MultiplierInputs = {
	rebirthMultiplier: number, -- from saved data (1 = no rebirths)
	hasDoubleCash: boolean,
	doubleCashMultiplier: number,
	isVip: boolean,
	vipIncomeBonus: number, -- e.g. 0.1 for +10%
	eventCashMultiplier: number, -- LiveOps (1 = no event)
}

export type PodiumUpgradeConfig = { basePrice: number, growth: number, maxPurchased: number }
export type CashPack = { incomeSeconds: number, minimum: number }

local EconomyMath = {}

local function sane(value: number, fallback: number): number
	if value ~= value or value == math.huge or value == -math.huge then
		return fallback
	end
	return value
end

-- Total income multiplier applied to every creature's base income.
function EconomyMath.incomeMultiplier(inputs: MultiplierInputs): number
	local m = math.max(1, sane(inputs.rebirthMultiplier, 1))
	if inputs.hasDoubleCash then
		m *= math.max(1, inputs.doubleCashMultiplier)
	end
	if inputs.isVip then
		m *= 1 + math.max(0, inputs.vipIncomeBonus)
	end
	m *= math.max(0, sane(inputs.eventCashMultiplier, 1))
	return m
end

-- Cash per second for one creature (kept fractional; accumulation is fractional and collection floors it).
function EconomyMath.creatureIncome(baseIncome: number, multiplier: number): number
	return math.max(0, baseIncome) * math.max(0, multiplier)
end

function EconomyMath.totalIncome(baseIncomes: { number }, multiplier: number): number
	local total = 0
	for _, income in baseIncomes do
		total += EconomyMath.creatureIncome(income, multiplier)
	end
	return total
end

function EconomyMath.podiumCapacity(
	startingPodiums: number,
	purchased: number,
	passBonus: number,
	maxPodiums: number
): number
	return math.clamp(startingPodiums + math.max(0, purchased) + math.max(0, passBonus), 0, maxPodiums)
end

-- Cost of the next podium given how many have been bought so far. Nil when the cap is reached.
function EconomyMath.podiumUpgradeCost(purchased: number, cfg: PodiumUpgradeConfig): number?
	if purchased >= cfg.maxPurchased then
		return nil
	end
	return math.floor(cfg.basePrice * cfg.growth ^ purchased)
end

function EconomyMath.sellValue(price: number, refundRate: number): number
	return math.floor(math.max(0, price) * math.clamp(refundRate, 0, 1))
end

-- Rounds to 2 significant digits, downward, so pack sizes read nicely ("$45K" rather than "$45,237").
function EconomyMath.roundNice(amount: number): number
	if amount < 100 then
		return math.floor(amount)
	end
	local magnitude = 10 ^ (math.floor(math.log10(amount)) - 1)
	return math.floor(amount / magnitude) * magnitude
end

-- Cash granted by a developer-product pack: N seconds of the buyer's current income, never below the minimum.
function EconomyMath.cashPackAmount(incomePerSecond: number, pack: CashPack): number
	local income = math.max(0, sane(incomePerSecond, 0))
	return EconomyMath.roundNice(math.max(pack.minimum, income * pack.incomeSeconds))
end

return EconomyMath
