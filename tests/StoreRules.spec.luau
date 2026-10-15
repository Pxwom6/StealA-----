--!strict
-- Store rules (Logic/StoreRules): which items the store shows, and (later sections) who may buy what.
local T = require("./TestKit")
local CashOfferRules = require("../src/shared/Logic/CashOfferRules")
local StoreRules = require("../src/shared/Logic/StoreRules")
local Economy = require("../src/shared/Config/Economy")
local Monetization = require("../src/shared/Config/Monetization")

T.describe("StoreRules: unconfigured items (id 0)", function()
	T.it("hides an item not created on the Creator Hub outside Studio, and shows it in Studio", function()
		T.expect(StoreRules.visible(0, false)).toBe(false)
		T.expect(StoreRules.visible(0, true)).toBe(true)
		T.expect(StoreRules.visible(3717868366, false)).toBe(true)
		T.expect(StoreRules.visible(3717868366, true)).toBe(true)
	end)

	T.it("keeps the store order and drops hidden and unknown keys", function()
		local items = { a = { id = 11 }, b = { id = 0 }, c = { id = 33 } }
		T.expect(StoreRules.visibleKeys({ "c", "b", "zz", "a" }, items, false)).toEqual({ "c", "a" })
		T.expect(StoreRules.visibleKeys({ "c", "b", "zz", "a" }, items, true)).toEqual({ "c", "b", "a" })
		T.expect(StoreRules.visibleKeys({ "b" }, items, false)).toEqual({})
	end)

	T.it("applies to every pass and product in the real store lists", function()
		for _, isStudio in { false, true } do
			local products = StoreRules.visibleKeys(Monetization.storeProducts, Monetization.products, isStudio)
			local passes = StoreRules.visibleKeys(Monetization.storePasses, Monetization.passes, isStudio)
			local expectedProducts, expectedPasses = 0, 0
			for _, key in Monetization.storeProducts do
				if isStudio or Monetization.products[key].id ~= 0 then
					expectedProducts += 1
				end
			end
			for _, key in Monetization.storePasses do
				if isStudio or Monetization.passes[key].id ~= 0 then
					expectedPasses += 1
				end
			end
			T.expect(#products).toBe(expectedProducts)
			T.expect(#passes).toBe(expectedPasses)
			for _, key in products do
				T.expect(isStudio or Monetization.products[key].id ~= 0).toBe(true)
			end
			for _, key in passes do
				T.expect(isStudio or Monetization.passes[key].id ~= 0).toBe(true)
			end
		end
		-- In Studio every item shows, so each one can be tested through DevGrantProduct.
		T.expect(#StoreRules.visibleKeys(Monetization.storeProducts, Monetization.products, true))
			.toBe(#Monetization.storeProducts)
		T.expect(#StoreRules.visibleKeys(Monetization.storePasses, Monetization.passes, true))
			.toBe(#Monetization.storePasses)
	end)

	T.it("is the rule the 'Need $X more?' offer follows too", function()
		local products = {
			Small = { id = 0, kind = "Cash" },
			Big = { id = 7, kind = "Cash" },
		}
		local packs = {
			Small = { incomeSeconds = 60, minimum = 500 },
			Big = { incomeSeconds = 600, minimum = 5000 },
		}
		local live = CashOfferRules.pick(300, 0, { "Small", "Big" }, products, packs, false)
		local studio = CashOfferRules.pick(300, 0, { "Small", "Big" }, products, packs, true)
		T.expect(live and live.key).toBe("Big") -- the unconfigured Small pack is hidden live
		T.expect(studio and studio.key).toBe("Small")
		-- the real ladder still offers something live when its packs exist
		local real = CashOfferRules.pick(
			100,
			0,
			Monetization.storeProducts,
			Monetization.products :: any,
			Economy.cashPacks :: any,
			false
		)
		T.expect(real ~= nil).toBe(true)
	end)
end)

return nil
