--!strict
--[[
	"Need $X more?" offers. When a purchase fails because the player is short of cash, the server can suggest the
	cheapest cash pack that covers the gap (server/Services/CashOfferService, client CashOfferController).

	Pure rules so they are unit-tested (tests/CashOfferRules.spec.luau):
	  * pick: the first cash pack in store order whose payout covers the shortfall. Store order lists cash packs
	    cheapest first and each pays more than the one before (tests/Config.spec), so the first that covers it is
	    the cheapest that does. Never a pack that would still leave the player short.
	  * allowed: never during the first-time tutorial, and at most one offer per cooldown, so a player who keeps
	    tapping things they can't afford isn't nagged.
]]

local EconomyMath = require("./EconomyMath")
local StoreRules = require("./StoreRules")

export type Offer = {
	key: string, -- Monetization.products key
	amount: number, -- cash the pack pays right now (EconomyMath.cashPackAmount)
	shortfall: number, -- how much more cash the purchase needed
}

export type Product = { id: number, kind: string }
export type Settings = { cooldownSeconds: number }

local CashOfferRules = {}

-- The cheapest cash pack that pays at least `shortfall` at this steady income (see EconomyMath.packIncome).
-- Products not created on the Creator Hub yet (id 0) only count when `allowUnconfigured` (Studio, where the store
-- grants them through the test path): the store's own rule (StoreRules.visible). nil when the shortfall is not a
-- positive number or no pack covers it.
function CashOfferRules.pick(
	shortfall: number,
	incomePerSecond: number,
	storeOrder: { string },
	products: { [string]: Product },
	cashPacks: { [string]: EconomyMath.CashPack },
	allowUnconfigured: boolean
): Offer?
	if shortfall ~= shortfall or shortfall <= 0 or shortfall == math.huge then
		return nil
	end
	for _, key in storeOrder do
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

-- Whether an offer may be shown now. `lastOfferAt` is when the previous one was shown (-math.huge: never).
function CashOfferRules.allowed(now: number, lastOfferAt: number, inTutorial: boolean, settings: Settings): boolean
	if inTutorial then
		return false
	end
	return now - lastOfferAt >= settings.cooldownSeconds
end

return CashOfferRules
