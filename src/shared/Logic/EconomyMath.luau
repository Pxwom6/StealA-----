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
	-- A server modifier's income effect (Cash Splash, Jackpot), e.g. 2 for double. Live income only: never part of
	-- what is paid or saved from income (DECISIONS #19: temporary bonuses never inflate them). nil = none.
	modifierIncomeMultiplier: number?,
	-- Cap on the LiveOps event and the modifier together (LiveOps.limits.maxCashMultiplier). nil = no cap.
	maxCashMultiplier: number?,
	socialBonus: number, -- friends in the server + group membership (Logic/SocialRules), e.g. 0.3 for +30%
	-- Snackdex collection bonus (Logic/SnackdexRules.incomeBonus), e.g. 0.06 for +6%. Earned for good, so it is part of
	-- the permanent multiplier. nil = none.
	collectionBonus: number?,
}

export type PodiumUpgradeConfig = { basePrice: number, growth: number, maxPurchased: number }
export type CashPack = { incomeSeconds: number, minimum: number }

-- One creature as a cash pack sees it (see packIncome).
export type PackSource = { baseIncome: number, podium: number }

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
	-- The LiveOps event and the server modifier together, under one cap.
	local cash = math.max(0, sane(inputs.eventCashMultiplier, 1))
		* math.max(0, sane(inputs.modifierIncomeMultiplier or 1, 1))
	if inputs.maxCashMultiplier ~= nil then
		cash = math.min(cash, sane(inputs.maxCashMultiplier, 1))
	end
	m *= cash
	m *= 1 + math.max(0, sane(inputs.socialBonus, 0))
	m *= 1 + math.max(0, sane(inputs.collectionBonus or 0, 0))
	return m
end

-- The multiplier without temporary boosts: what the player earned or bought for good (rebirths, passes, the Snackdex
-- collection bonus); LiveOps cash events, server modifiers and the social bonus are left out. Cash packs, quest and
-- Snackdex rewards are sized from it (packIncome).
function EconomyMath.permanentMultiplier(inputs: MultiplierInputs): number
	local steady = table.clone(inputs)
	steady.eventCashMultiplier = 1
	steady.modifierIncomeMultiplier = 1
	steady.socialBonus = 0
	return EconomyMath.incomeMultiplier(steady)
end

-- The multiplier time-based rewards and saved stats use (daily streak, offline earnings, best cash/sec): everything
-- but the social bonus and a server modifier (the Snackdex collection bonus counts, like rebirths). Both depend on
-- this one server at this moment (who is here; a 5-minute Jackpot), so they never inflate a payout or a saved value.
-- A LiveOps cash event, which every server runs at once on a published date, still counts here, as before (#19).
function EconomyMath.rewardMultiplier(inputs: MultiplierInputs): number
	local steady = table.clone(inputs)
	steady.socialBonus = 0
	steady.modifierIncomeMultiplier = 1
	return EconomyMath.incomeMultiplier(steady)
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

-- The steady income cash packs are sized from ("about N minutes of your income"): creatures on an active podium
-- (podium <= capacity), at the permanent multiplier. A running event or creatures parked on podiums beyond capacity
-- never count. A creature a thief is carrying off still counts: the owner owns it until delivery (DECISIONS #7), and
-- a pack bought while a thief grabs it pays what its card showed.
function EconomyMath.packIncome(sources: { PackSource }, capacity: number, permanentMultiplier: number): number
	local total = 0
	for _, source in sources do
		if source.podium <= capacity then
			total += EconomyMath.creatureIncome(source.baseIncome, permanentMultiplier)
		end
	end
	return total
end

-- Cash granted by a developer-product pack: N seconds of the buyer's steady income (packIncome), never below the
-- minimum.
function EconomyMath.cashPackAmount(incomePerSecond: number, pack: CashPack): number
	local income = math.max(0, sane(incomePerSecond, 0))
	return EconomyMath.roundNice(math.max(pack.minimum, income * pack.incomeSeconds))
end

return EconomyMath
