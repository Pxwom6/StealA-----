--!strict
local T = require("./TestKit")
local CashOfferRules = require("../src/shared/Logic/CashOfferRules")
local EconomyMath = require("../src/shared/Logic/EconomyMath")
local Economy = require("../src/shared/Config/Economy")
local Monetization = require("../src/shared/Config/Monetization")

-- A small fixed ladder so these tests don't move when the real config is tuned.
local ORDER = { "Boost", "Small", "Medium", "Large", "Lock" }
local PRODUCTS: { [string]: CashOfferRules.Product } = {
	Boost = { id = 11, kind = "ServerLuck" },
	Small = { id = 1, kind = "Cash" },
	Medium = { id = 2, kind = "Cash" },
	Large = { id = 3, kind = "Cash" },
	Lock = { id = 12, kind = "LockToken" },
}
local PACKS: { [string]: EconomyMath.CashPack } = {
	Small = { incomeSeconds = 60, minimum = 400 },
	Medium = { incomeSeconds = 600, minimum = 2000 },
	Large = { incomeSeconds = 3600, minimum = 10000 },
}

local function pick(shortfall: number, income: number, products: { [string]: CashOfferRules.Product }?)
	return CashOfferRules.pick(shortfall, income, ORDER, products or PRODUCTS, PACKS, false)
end

T.describe("CashOfferRules.pick", function()
	T.it("picks the cheapest pack whose payout covers the shortfall", function()
		-- No income yet: the minimums decide.
		T.expect((pick(300, 0) :: CashOfferRules.Offer).key).toBe("Small")
		T.expect((pick(400, 0) :: CashOfferRules.Offer).key).toBe("Small") -- exactly enough counts
		T.expect((pick(401, 0) :: CashOfferRules.Offer).key).toBe("Medium")
		T.expect((pick(9000, 0) :: CashOfferRules.Offer).key).toBe("Large")
		-- With income the packs scale: 100/s makes Small pay 6K, so a 5K gap only needs the small pack.
		local offer = pick(5000, 100) :: CashOfferRules.Offer
		T.expect(offer.key).toBe("Small")
		T.expect(offer.amount).toBe(6000)
		T.expect(offer.shortfall).toBe(5000)
	end)

	T.it("never suggests a pack that would still leave the player short", function()
		T.expect(pick(10001, 0)).toBeNil()
		T.expect(pick(400000, 100)).toBeNil() -- Large pays 360K at 100/s
	end)

	T.it("offers nothing for a zero, negative or broken shortfall", function()
		T.expect(pick(0, 50)).toBeNil()
		T.expect(pick(-10, 50)).toBeNil()
		T.expect(pick(0 / 0, 50)).toBeNil()
		T.expect(pick(math.huge, 50)).toBeNil()
	end)

	T.it("only offers cash packs, and skips packs not created on the Creator Hub unless allowed", function()
		local products = table.clone(PRODUCTS)
		products.Small = { id = 0, kind = "Cash" }
		T.expect((pick(300, 0, products) :: CashOfferRules.Offer).key).toBe("Medium")
		local studio = CashOfferRules.pick(300, 0, ORDER, products, PACKS, true) :: CashOfferRules.Offer
		T.expect(studio.key).toBe("Small")
		for _, shortfall in { 1, 500, 5000, 10000 } do
			local offer = pick(shortfall, 0)
			if offer then
				T.expect(PRODUCTS[offer.key].kind).toBe("Cash")
			end
		end
	end)

	T.it("with the real config, a new player's small shortfall is offered the cheapest pack", function()
		local offer = CashOfferRules.pick(
			100,
			0,
			Monetization.storeProducts,
			Monetization.products :: any,
			Economy.cashPacks :: any,
			false
		) :: CashOfferRules.Offer
		T.expect(offer ~= nil).toBe(true)
		local first: string? = nil
		for _, key in Monetization.storeProducts do
			if Monetization.products[key].kind == "Cash" then
				first = key
				break
			end
		end
		T.expect(offer.key).toBe(first)
	end)
end)

T.describe("CashOfferRules.allowed", function()
	local settings = { cooldownSeconds = 90 }
	T.it("never during the first-time tutorial", function()
		T.expect(CashOfferRules.allowed(1000, -math.huge, true, settings)).toBe(false)
	end)
	T.it("the first offer is allowed, then at most one per cooldown", function()
		T.expect(CashOfferRules.allowed(5, -math.huge, false, settings)).toBe(true)
		T.expect(CashOfferRules.allowed(100, 20, false, settings)).toBe(false)
		T.expect(CashOfferRules.allowed(110, 20, false, settings)).toBe(true)
	end)
end)

return nil
