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

	T.it("with the real config, a new player's small shortfall is offered the cheapest small pack", function()
		local offer = CashOfferRules.pick(
			100,
			0,
			Monetization.cashOffer.packs,
			Monetization.products :: any,
			Economy.cashPacks :: any,
			false
		) :: CashOfferRules.Offer
		T.expect(offer ~= nil).toBe(true)
		T.expect(offer.key).toBe(Monetization.cashOffer.packs[1])
		T.expect(offer.key).toBe("CashBite")
	end)

	T.it("offers only the small packs: a gap only a bigger pack covers gets no offer", function()
		-- at 100/s the Snack Pack pays 90K and the Snack Basket 210K: a 100K gap is beyond every small pack
		local packs, products, cashPacks =
			Monetization.cashOffer.packs, Monetization.products :: any, Economy.cashPacks :: any
		T.expect(CashOfferRules.pick(100000, 100, packs, products, cashPacks, false)).toBeNil()
		local ladder = CashOfferRules.pick(100000, 100, Monetization.storeProducts, products, cashPacks, false)
		T.expect((ladder :: CashOfferRules.Offer).key).toBe("CashBasket") -- what the whole ladder would have sold
	end)
end)

local SETTINGS: CashOfferRules.Settings =
	{ cooldownSeconds = 180, minPlaySeconds = 600, smallGapSeconds = 45, packs = {} }

T.describe("CashOfferRules.allowed", function()
	T.it("never during the first-time tutorial", function()
		T.expect(CashOfferRules.allowed(1000, -math.huge, true, 5000, SETTINGS)).toBe(false)
	end)
	T.it("never in a player's first ten minutes of play", function()
		T.expect(CashOfferRules.allowed(1000, -math.huge, false, 599, SETTINGS)).toBe(false)
		T.expect(CashOfferRules.allowed(1000, -math.huge, false, 600, SETTINGS)).toBe(true)
		T.expect(CashOfferRules.allowed(1000, -math.huge, false, 0 / 0, SETTINGS)).toBe(false)
	end)
	T.it("the first offer is allowed, then at most one per cooldown", function()
		T.expect(CashOfferRules.allowed(5, -math.huge, false, 600, SETTINGS)).toBe(true)
		T.expect(CashOfferRules.allowed(199, 20, false, 600, SETTINGS)).toBe(false)
		T.expect(CashOfferRules.allowed(200, 20, false, 600, SETTINGS)).toBe(true)
	end)
end)

T.describe("CashOfferRules.waitSeconds", function()
	T.it("a gap the income covers within 45 s gets its seconds, not an offer", function()
		T.expect(CashOfferRules.waitSeconds(450, 10, SETTINGS)).toBe(45)
		T.expect(CashOfferRules.waitSeconds(451, 10, SETTINGS)).toBeNil()
		T.expect(CashOfferRules.waitSeconds(32, 15, SETTINGS)).toBe(3) -- the reviewer's: $32 short at $15/s
		T.expect(CashOfferRules.waitSeconds(1, 1000, SETTINGS)).toBe(1) -- never "0s"
	end)
	T.it("nothing to wait for without income, or with a broken number", function()
		T.expect(CashOfferRules.waitSeconds(100, 0, SETTINGS)).toBeNil()
		T.expect(CashOfferRules.waitSeconds(100, 0 / 0, SETTINGS)).toBeNil()
		T.expect(CashOfferRules.waitSeconds(100, math.huge, SETTINGS)).toBeNil()
		T.expect(CashOfferRules.waitSeconds(0 / 0, 10, SETTINGS)).toBeNil()
		T.expect(CashOfferRules.waitSeconds(0, 10, SETTINGS)).toBeNil()
		T.expect(CashOfferRules.waitSeconds(-5, 10, SETTINGS)).toBeNil()
	end)
end)

T.describe("CashOfferRules.decide (real config)", function()
	local function decide(changes: { [string]: any }): CashOfferRules.Decision
		-- an established player: an hour of play, no offer yet, $10/s
		local ctx: { [string]: any } = {
			shortfall = 1000,
			income = 10,
			packIncome = 10,
			now = 1000,
			lastOfferAt = -math.huge,
			inTutorial = false,
			playSeconds = 3600,
			allowUnconfigured = false,
		}
		for key, value in changes do
			ctx[key] = value
		end
		return CashOfferRules.decide(
			ctx :: any,
			Monetization.cashOffer,
			Monetization.products :: any,
			Economy.cashPacks :: any
		)
	end

	T.it("a gap of more than 45 s of income gets the cheapest small pack that covers it", function()
		local decision = decide({})
		T.expect((decision.offer :: CashOfferRules.Offer).key).toBe("CashBite")
		T.expect(decision.waitSeconds).toBeNil()
	end)

	T.it("a gap of 45 s of income or less: the seconds, never an offer", function()
		local decision = decide({ shortfall = 300 })
		T.expect(decision.offer).toBeNil()
		T.expect(decision.waitSeconds).toBe(30)
	end)

	T.it("no offer in the tutorial, the first ten minutes or within 3 minutes of the last one", function()
		local cases: { { [string]: any } } =
			{ { inTutorial = true }, { playSeconds = 599 }, { lastOfferAt = 1000 - 179 } }
		for _, changes in cases do
			local decision = decide(changes)
			T.expect(decision.offer).toBeNil()
			T.expect(decision.waitSeconds).toBeNil()
		end
		T.expect(decide({ lastOfferAt = 1000 - 180 }).offer ~= nil).toBe(true)
	end)

	T.it("the reviewer's cases", function()
		-- a Legendary tapped 45 s after the tutorial ($2.42M short at $157/s): it was the 199 R$ Snack Truck
		T.expect(decide({ shortfall = 2420404, income = 157, packIncome = 157, playSeconds = 180 }).offer).toBeNil()
		T.expect(decide({ shortfall = 2420404, income = 157, packIncome = 157 }).offer).toBeNil()
		-- $32 short at $15/s: it was a 5 R$ offer
		local tiny = decide({ shortfall = 32, income = 15, packIncome = 15 })
		T.expect(tiny.offer).toBeNil()
		T.expect(tiny.waitSeconds).toBe(3)
	end)
end)

T.describe("Config/Monetization.cashOffer", function()
	local cfg = Monetization.cashOffer
	local products, cashPacks = Monetization.products :: any, Economy.cashPacks :: any

	T.it("is valid: small cash packs only, cheapest first, and gentle numbers", function()
		T.expect(table.concat(CashOfferRules.validate(cfg, products, cashPacks, Monetization.storeProducts), "; "))
			.toBe("")
		T.expect(cfg.cooldownSeconds).toBeAtLeast(180)
		T.expect(cfg.minPlaySeconds).toBeAtLeast(600)
		T.expect(cfg.smallGapSeconds).toBeAtLeast(45)
	end)

	T.it("refuses a big pack, a product that isn't cash, the wrong order and bad numbers", function()
		local bad: CashOfferRules.Settings = {
			cooldownSeconds = 30,
			minPlaySeconds = -1,
			smallGapSeconds = 0 / 0,
			packs = { "CashSmall", "CashBite", "CashLarge", "InstantLock" },
		}
		T.expect(#CashOfferRules.validate(bad, products, cashPacks, Monetization.storeProducts)).toBe(6)
		local empty = table.clone(cfg)
		empty.packs = {}
		T.expect(#CashOfferRules.validate(empty, products, cashPacks, Monetization.storeProducts)).toBe(1)
	end)
end)

return nil
