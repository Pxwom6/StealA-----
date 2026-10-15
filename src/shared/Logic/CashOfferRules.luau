--!strict
--[[
	"Need $X more?" offers. When a purchase fails because the player is short of cash, the server can suggest the
	cheapest of the small cash packs that covers the gap (server/Services/CashOfferService, client CashOfferController).

	Pure rules so they are unit-tested (tests/CashOfferRules.spec.luau):
	  * pick: the first pack in the offer list (Config/Monetization.cashOffer.packs: the small packs, cheapest first,
	    in store order; validate) whose payout covers the shortfall, so the cheapest that does. Never a pack that would
	    still leave the player short.
	  * waitSeconds: a gap the player's income covers within `smallGapSeconds` is no reason to sell them anything; they
	    are told how long instead.
	  * allowed: never during the first-time tutorial, nor in a player's first `minPlaySeconds` of play, and at most
	    one offer per cooldown, so a young player who keeps tapping things they can't afford isn't nagged.
	  * decide: all of the above, in that order.
]]

local EconomyMath = require("./EconomyMath")
local StoreRules = require("./StoreRules")

export type Offer = {
	key: string, -- Monetization.products key
	amount: number, -- cash the pack pays right now (EconomyMath.cashPackAmount)
	shortfall: number, -- how much more cash the purchase needed
}

export type Product = { id: number, kind: string }
export type Settings = {
	cooldownSeconds: number, -- at most one offer this often
	minPlaySeconds: number, -- no offer before this much total play (stats.playTime)
	smallGapSeconds: number, -- a gap of at most this many seconds of income: no offer, the seconds instead
	packs: { string }, -- the packs an offer may suggest: cash packs, cheapest first (store order)
}

-- What the server does about one failed purchase: show `offer`, or say how many seconds of income are missing
-- (`waitSeconds`), or (neither) the plain "Not enough cash!".
export type Decision = { offer: Offer?, waitSeconds: number? }

export type Context = {
	shortfall: number, -- price - cash
	income: number, -- cash per second the player earns now (the HUD's "+$/s"): the small-gap test and its seconds
	packIncome: number, -- steady income the packs are sized from (EconomyMath.packIncome)
	now: number, -- the clock lastOfferAt is on
	lastOfferAt: number, -- when the previous offer was shown (-math.huge: never)
	inTutorial: boolean,
	playSeconds: number, -- the save's stats.playTime
	allowUnconfigured: boolean, -- Studio: packs not created on the Creator Hub yet count (StoreRules.visible)
}

local CashOfferRules = {}

-- What Config/Monetization.cashOffer may set (CI): never more often than every 90 s, and only packs that pay at most
-- 15 minutes of income (the Snack Pack's): the small ones.
CashOfferRules.LIMITS = table.freeze({
	cooldownSeconds = table.freeze({ min = 90, max = 3600 }),
	minPlaySeconds = table.freeze({ min = 0, max = 3600 }),
	smallGapSeconds = table.freeze({ min = 0, max = 300 }),
	packIncomeSeconds = 15 * 60,
})

local function usable(value: number): boolean
	return value == value and value > 0 and value < math.huge
end

-- The cheapest pack in `packs` (in order) that pays at least `shortfall` at this steady income (see
-- EconomyMath.packIncome). Products not created on the Creator Hub yet (id 0) only count when `allowUnconfigured`
-- (Studio, where the store grants them through the test path): the store's own rule (StoreRules.visible). nil when
-- the shortfall is not a positive number or no pack covers it.
function CashOfferRules.pick(
	shortfall: number,
	incomePerSecond: number,
	packs: { string },
	products: { [string]: Product },
	cashPacks: { [string]: EconomyMath.CashPack },
	allowUnconfigured: boolean
): Offer?
	if not usable(shortfall) then
		return nil
	end
	for _, key in packs do
		local product = products[key]
		local pack = cashPacks[key]
		if
			product ~= nil
			and product.kind == "Cash"
			and pack ~= nil
			and StoreRules.visible(product.id, allowUnconfigured)
		then
			local amount = EconomyMath.cashPackAmount(incomePerSecond, pack)
			if amount >= shortfall then
				return { key = key, amount = amount, shortfall = shortfall }
			end
		end
	end
	return nil
end

-- Seconds of `income` the gap needs, when that is `smallGapSeconds` or less (at least 1): then nothing is offered and
-- the player is told the seconds. nil for a bigger gap, no income, or a broken number.
function CashOfferRules.waitSeconds(shortfall: number, income: number, settings: Settings): number?
	if not usable(shortfall) or not usable(income) then
		return nil
	end
	local seconds = shortfall / income
	if seconds > settings.smallGapSeconds then
		return nil
	end
	return math.max(1, math.ceil(seconds))
end

-- Whether an offer may be shown now. `lastOfferAt` is when the previous one was shown (-math.huge: never).
function CashOfferRules.allowed(
	now: number,
	lastOfferAt: number,
	inTutorial: boolean,
	playSeconds: number,
	settings: Settings
): boolean
	if inTutorial or not (playSeconds >= settings.minPlaySeconds) then
		return false
	end
	return now - lastOfferAt >= settings.cooldownSeconds
end

-- What to do about one purchase that failed for lack of cash (see Decision).
function CashOfferRules.decide(
	ctx: Context,
	settings: Settings,
	products: { [string]: Product },
	cashPacks: { [string]: EconomyMath.CashPack }
): Decision
	local wait = CashOfferRules.waitSeconds(ctx.shortfall, ctx.income, settings)
	if wait then
		return { offer = nil, waitSeconds = wait }
	end
	if not CashOfferRules.allowed(ctx.now, ctx.lastOfferAt, ctx.inTutorial, ctx.playSeconds, settings) then
		return { offer = nil, waitSeconds = nil }
	end
	local offer =
		CashOfferRules.pick(ctx.shortfall, ctx.packIncome, settings.packs, products, cashPacks, ctx.allowUnconfigured)
	return { offer = offer, waitSeconds = nil }
end

-- Problems with Config/Monetization.cashOffer (an empty list means valid): its numbers within LIMITS, and every pack
-- a small cash pack, cheapest first (after the one before in `storeOrder`, which lists cash packs cheapest first).
function CashOfferRules.validate(
	settings: Settings,
	products: { [string]: Product },
	cashPacks: { [string]: EconomyMath.CashPack },
	storeOrder: { string }
): { string }
	local problems: { string } = {}
	local limits = CashOfferRules.LIMITS
	local function within(value: number, range: { min: number, max: number }, name: string)
		if not (value >= range.min and value <= range.max) then
			table.insert(problems, `{name} must be between {range.min} and {range.max}`)
		end
	end
	within(settings.cooldownSeconds, limits.cooldownSeconds, "cooldownSeconds")
	within(settings.minPlaySeconds, limits.minPlaySeconds, "minPlaySeconds")
	within(settings.smallGapSeconds, limits.smallGapSeconds, "smallGapSeconds")
	if #settings.packs == 0 then
		table.insert(problems, "packs: at least one")
	end
	local last = 0
	for index, key in settings.packs do
		local product = products[key]
		local pack = cashPacks[key]
		if product == nil or product.kind ~= "Cash" or pack == nil then
			table.insert(problems, `packs[{index}] {key}: not a cash pack`)
			continue
		end
		if not (pack.incomeSeconds <= limits.packIncomeSeconds) then
			table.insert(
				problems,
				`packs[{index}] {key}: pays more than {limits.packIncomeSeconds // 60} minutes of income (only small packs)`
			)
		end
		local at = table.find(storeOrder, key) or 0
		if at <= last then
			table.insert(problems, `packs[{index}] {key}: not after the pack before it in store order (cheapest first)`)
		end
		last = math.max(last, at)
	end
	return problems
end

return CashOfferRules
