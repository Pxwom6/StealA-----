--!strict
-- Store rules (Logic/StoreRules): which items the store shows, and (later sections) who may buy what.
local T = require("./TestKit")
local CashOfferRules = require("../src/shared/Logic/CashOfferRules")
local StoreRules = require("../src/shared/Logic/StoreRules")
local Economy = require("../src/shared/Config/Economy")
local Monetization = require("../src/shared/Config/Monetization")
local Spin = require("../src/shared/Config/Spin")
local Theme = require("../src/shared/Config/Theme")

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

-- A context where everything is allowed; tests change one field at a time.
local function context(changes: { [string]: any }?): StoreRules.PurchaseContext
	local ctx: StoreRules.PurchaseContext = {
		visible = true,
		paidRandomAllowed = true,
		spins = 0,
		spinBankFull = Spin.maxBanked,
		starterOwned = false,
		podiumFree = true,
	}
	local edits: { [string]: any } = changes or {}
	for key, value in edits do
		(ctx :: any)[key] = value
	end
	return ctx
end

T.describe("StoreRules: Lucky Spin packs before the prompt", function()
	T.it("are paid random items, checked before Roblox's prompt opens", function()
		T.expect(StoreRules.CHECKED_KINDS.Spins).toBe(true)
		T.expect(StoreRules.PAID_RANDOM_KINDS.Spins).toBe(true)
		T.expect(StoreRules.PAID_RANDOM_KINDS.ServerLuck).toBe(true)
		T.expect(StoreRules.PAID_RANDOM_KINDS.Cash).toBeNil()
		local packs = 0
		for key, product in Monetization.products do
			if product.kind == "Spins" then
				packs += 1
				T.expect((product.spins or 0) >= 1).toBe(true)
				T.expect(table.find(Monetization.storeProducts, key) ~= nil).toBe(true)
			end
		end
		T.expect(packs).toBe(2)
		T.expect(Monetization.products.LuckySpins3.spins).toBe(3)
		T.expect(Monetization.products.LuckySpins10.spins).toBe(10)
	end)

	T.it("can be bought when the policy allows it and the bank has room", function()
		T.expect(StoreRules.purchaseRefusal("Spins", context())).toBeNil()
		T.expect(StoreRules.purchaseRefusal("Spins", context({ spins = Spin.maxBanked - 1 }))).toBeNil()
	end)

	T.it("are refused where Roblox's policy restricts paid random items, or while that is being looked up", function()
		T.expect(StoreRules.purchaseRefusal("Spins", context({ paidRandomAllowed = false }))).toBe("restricted")
	end)

	T.it("are refused once the bank is very full, with a clear message", function()
		T.expect(StoreRules.purchaseRefusal("Spins", context({ spins = Spin.maxBanked }))).toBe("bankFull")
		T.expect(StoreRules.purchaseRefusal("Spins", context({ spins = 999 }))).toBe("bankFull")
		T.expect(StoreRules.purchaseRefusal("Spins", context({ spins = 0 / 0 }))).toBe("bankFull") -- never through
		T.expect(StoreRules.messageKey("bankFull")).toBe("spinPackBankFull")
		T.expect((string.find(Theme.text.spinPackBankFull, "{count}", 1, true)) ~= nil).toBe(true) -- says how many
	end)

	T.it("checks in this order: unknown, unavailable, restricted, bank full", function()
		T.expect(StoreRules.purchaseRefusal("Cash", context())).toBe("unknown")
		T.expect(StoreRules.purchaseRefusal("Spins", context({ visible = false, paidRandomAllowed = false })))
			.toBe("unavailable")
		T.expect(StoreRules.purchaseRefusal("Spins", context({ paidRandomAllowed = false, spins = 999 })))
			.toBe("restricted")
	end)

	T.it("has a message for every refusal it reports, and analytics surfaces from a closed list", function()
		for _, reason in StoreRules.REASONS do
			local key = StoreRules.messageKey(reason)
			if key then
				T.expect(type((Theme.text :: any)[key])).toBe("string")
			end
		end
		T.expect(StoreRules.messageKey("unknown")).toBeNil() -- a made-up key from a client: silence
		T.expect(StoreRules.SURFACES).toEqual({ "store", "spin", "offer" })
		for _, key in Monetization.viewTracked do
			T.expect(Monetization.products[key] ~= nil or Monetization.passes[key] ~= nil).toBe(true)
		end
	end)
end)

T.describe("StoreRules: the Starter Pack before the prompt", function()
	T.it("is checked before the prompt, and is not a paid random item (fixed contents)", function()
		T.expect(StoreRules.CHECKED_KINDS.StarterPack).toBe(true)
		T.expect(StoreRules.PAID_RANDOM_KINDS.StarterPack).toBeNil()
		T.expect(StoreRules.purchaseRefusal("StarterPack", context({ paidRandomAllowed = false }))).toBeNil()
	end)

	T.it("is refused once owned: the server says no before a second prompt opens", function()
		T.expect(StoreRules.purchaseRefusal("StarterPack", context({ starterOwned = true }))).toBe("owned")
		T.expect(StoreRules.messageKey("owned")).toBe("starterOwned")
	end)

	T.it("needs a free podium for its Snackling", function()
		T.expect(StoreRules.purchaseRefusal("StarterPack", context({ podiumFree = false }))).toBe("baseFull")
		T.expect(StoreRules.purchaseRefusal("StarterPack", context({ podiumFree = false, starterOwned = true })))
			.toBe("owned")
		T.expect(StoreRules.messageKey("baseFull")).toBe("starterBaseFull")
	end)

	T.it("is hidden before it exists on the Creator Hub, outside Studio", function()
		T.expect(StoreRules.purchaseRefusal("StarterPack", context({ visible = false }))).toBe("unavailable")
	end)
end)

return nil
