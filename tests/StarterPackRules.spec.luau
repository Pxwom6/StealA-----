--!strict
-- The Starter Pack (Logic/StarterPackRules, Config/Monetization.starterPack): fixed contents, once per account, and
-- its one-time offer card.
local T = require("./TestKit")
local Catalog = require("../src/shared/Logic/Catalog")
local EconomyMath = require("../src/shared/Logic/EconomyMath")
local MutationRules = require("../src/shared/Logic/MutationRules")
local StarterPackRules = require("../src/shared/Logic/StarterPackRules")
local Creatures = require("../src/shared/Config/Creatures")
local Economy = require("../src/shared/Config/Economy")
local Gadgets = require("../src/shared/Config/Gadgets")
local Monetization = require("../src/shared/Config/Monetization")
local Mutations = require("../src/shared/Config/Mutations")
local Rarities = require("../src/shared/Config/Rarities")
local Types = require("../src/shared/Types")

local catalog = Catalog.build(Creatures, Rarities, Mutations)
local config = Monetization.starterPack

local function gadgetPrice(id: string): number
	return Gadgets.gadgets[id].price
end

local function owning(ids: { string }): (id: string) -> boolean
	return function(id: string): boolean
		return table.find(ids, id) ~= nil
	end
end

local function copy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, item in value do
		result[key] = copy(item)
	end
	return result
end

local creature = catalog.creatures[config.creatureId]
local creaturePrice = MutationRules.price(catalog.mutations, creature, config.variant)

T.describe("StarterPackRules: the real config", function()
	T.it("is valid", function()
		local problems = StarterPackRules.validate(config, catalog.creatures, catalog.mutations, Gadgets.order)
		T.expect(table.concat(problems, "; ")).toBe("")
	end)

	T.it("gives a Golden Rare from the permanent roster and the first two gadgets", function()
		T.expect(creature ~= nil and creature.rarity == "Rare" and creature.eventId == nil).toBe(true)
		T.expect(config.variant).toBe("golden")
		local golden = catalog.mutations.golden
		T.expect(golden.eventId == nil and golden.mapTheme == nil and golden.modifierId == nil).toBe(true)
		T.expect(config.gadgets).toEqual({ Gadgets.order[1], Gadgets.order[2] })
		T.expect(config.gadgets).toEqual({ "soda", "peel" })
	end)

	T.it("is a product checked before the prompt, first in the store, with its copy", function()
		local product = Monetization.products.StarterPack
		T.expect(product.kind).toBe("StarterPack")
		T.expect(Monetization.storeProducts[1]).toBe("StarterPack")
		T.expect(table.find(Monetization.viewTracked, "StarterPack") ~= nil).toBe(true)
	end)

	T.it("keeps its save flags' names (they are in saves once shipped)", function()
		T.expect(StarterPackRules.OWNED_FLAG).toBe("starter_pack")
		T.expect(StarterPackRules.OFFER_FLAG).toBe("starter_offer")
		T.expect(StarterPackRules.owns({ starter_pack = true })).toBe(true)
		T.expect(StarterPackRules.owns({})).toBe(false)
	end)
end)

T.describe("StarterPackRules contents", function()
	T.it("scales its cash with steady income like a cash pack, with a generous floor", function()
		T.expect(StarterPackRules.cash(config, 0)).toBe(config.cash.minimum)
		T.expect(StarterPackRules.cash(config, 0 / 0)).toBe(config.cash.minimum)
		local income = 10000
		T.expect(StarterPackRules.cash(config, income)).toBe(EconomyMath.roundNice(income * config.cash.incomeSeconds))
		-- more than the same-price Snack Basket (49 R$, 35 minutes) at every income, floor included
		local basket = Economy.cashPacks.CashBasket
		T.expect(config.cash.incomeSeconds).toBeGreaterThan(basket.incomeSeconds)
		T.expect(config.cash.minimum).toBeGreaterThan(basket.minimum)
		-- the floor buys a first Epic after a rebirth
		local cheapestEpic = math.huge
		for _, def in Creatures do
			if def.rarity == "Epic" and def.eventId == nil then
				cheapestEpic = math.min(cheapestEpic, def.price)
			end
		end
		T.expect(config.cash.minimum).toBeAtLeast(cheapestEpic)
	end)

	T.it("is fixed: the same inputs always give the same pack, nothing random", function()
		local a = StarterPackRules.contents(config, 60000, owning({}), gadgetPrice)
		local b = StarterPackRules.contents(config, 60000, owning({}), gadgetPrice)
		T.expect(a).toEqual(b)
		T.expect(a).toEqual({
			cash = 60000,
			creatureId = "cupcake_cub",
			variant = "golden",
			gadgets = { "soda", "peel" },
			gadgetCash = 0,
		})
	end)

	T.it("pays a gadget's cash price instead when the buyer owns it already", function()
		local one = StarterPackRules.contents(config, 60000, owning({ "soda" }), gadgetPrice)
		T.expect(one.gadgets).toEqual({ "peel" })
		T.expect(one.gadgetCash).toBe(gadgetPrice("soda"))
		local both = StarterPackRules.contents(config, 60000, owning({ "soda", "peel", "magnet" }), gadgetPrice)
		T.expect(both.gadgets).toEqual({})
		T.expect(both.gadgetCash).toBe(gadgetPrice("soda") + gadgetPrice("peel"))
	end)

	T.it("is worth the same in cash whatever the buyer owns (a second receipt pays that, cash only)", function()
		local fresh = StarterPackRules.contents(config, 60000, owning({}), gadgetPrice)
		local owner = StarterPackRules.contents(config, 60000, owning({ "soda", "peel" }), gadgetPrice)
		local value = StarterPackRules.cashValue(fresh, creaturePrice, gadgetPrice)
		T.expect(value).toBe(60000 + creaturePrice + gadgetPrice("soda") + gadgetPrice("peel"))
		T.expect(StarterPackRules.cashValue(owner, creaturePrice, gadgetPrice)).toBe(value)
		T.expect(creaturePrice).toBe(18750) -- 12,500 x Golden's 1.5
	end)
end)

-- An offer context where it is due; tests change one field at a time.
local function offer(changes: { [string]: any }?): StarterPackRules.OfferContext
	local ctx: StarterPackRules.OfferContext = {
		owned = false,
		seen = false,
		forSale = true,
		inTutorial = false,
		rebirths = 0,
		playSeconds = config.offer.afterPlaySeconds,
	}
	local edits: { [string]: any } = changes or {}
	for key, value in edits do
		(ctx :: any)[key] = value
	end
	return ctx
end

T.describe("StarterPackRules: the one-time offer card", function()
	T.it("comes after the first rebirth or 30 minutes of total play, whichever is first", function()
		T.expect(config.offer.afterRebirths).toBe(1)
		T.expect(config.offer.afterPlaySeconds).toBe(30 * 60)
		T.expect(StarterPackRules.offerDue(offer(), config)).toBe(true)
		T.expect(StarterPackRules.offerDue(offer({ playSeconds = 29 * 60 }), config)).toBe(false)
		T.expect(StarterPackRules.offerDue(offer({ playSeconds = 60, rebirths = 1 }), config)).toBe(true)
	end)

	T.it("never comes once bought, once shown, during the tutorial, or before it is on sale", function()
		T.expect(StarterPackRules.offerDue(offer({ owned = true }), config)).toBe(false)
		T.expect(StarterPackRules.offerDue(offer({ seen = true }), config)).toBe(false)
		T.expect(StarterPackRules.offerDue(offer({ inTutorial = true }), config)).toBe(false)
		T.expect(StarterPackRules.offerDue(offer({ forSale = false }), config)).toBe(false)
	end)

	T.it("reads its context from a save", function()
		local data = { flags = { starter_offer = true }, rebirths = 2, stats = { playTime = 99 } }
		local ctx = StarterPackRules.offerContext((data :: any) :: Types.PlayerData, false, true)
		T.expect(ctx).toEqual({
			owned = false,
			seen = true,
			forSale = true,
			inTutorial = false,
			rebirths = 2,
			playSeconds = 99,
		})
	end)

	T.it("shows only at a calm moment: never over a dialog, while carrying, over another offer, or twice", function()
		local function moment(changes: { [string]: any }?): boolean
			local ctx: StarterPackRules.MomentContext = {
				due = true,
				inTutorial = false,
				dialogOpen = false,
				carrying = false,
				otherOffer = false,
				shownThisSession = false,
			}
			local edits: { [string]: any } = changes or {}
			for key, value in edits do
				(ctx :: any)[key] = value
			end
			return StarterPackRules.canShowOffer(ctx)
		end
		T.expect(moment()).toBe(true)
		T.expect(moment({ due = false })).toBe(false)
		T.expect(moment({ inTutorial = true })).toBe(false)
		T.expect(moment({ dialogOpen = true })).toBe(false)
		T.expect(moment({ carrying = true })).toBe(false)
		T.expect(moment({ otherOffer = true })).toBe(false)
		T.expect(moment({ shownThisSession = true })).toBe(false)
	end)
end)

T.describe("StarterPackRules.validate", function()
	local function broken(edit: (config: any) -> ()): number
		local edited = copy(config)
		edit(edited)
		return #StarterPackRules.validate(edited, catalog.creatures, catalog.mutations, Gadgets.order)
	end

	T.it("refuses event Snacklings and mutations, unknown ones, unknown gadgets and odd numbers", function()
		T.expect(broken(function(c)
			c.creatureId = "candy_corn_cat" -- Halloween's
		end)).toBe(1)
		T.expect(broken(function(c)
			c.creatureId = "nope"
		end)).toBe(1)
		T.expect(broken(function(c)
			c.variant = "haunted" -- Halloween's
		end)).toBe(1)
		T.expect(broken(function(c)
			c.variant = "molten" -- a map's signature
		end)).toBe(1)
		T.expect(broken(function(c)
			c.gadgets = { "soda", "rocketBoots" }
		end)).toBe(1)
		T.expect(broken(function(c)
			c.gadgets = { "soda", "soda" }
		end)).toBe(1)
		T.expect(broken(function(c)
			c.cash.minimum = 10
		end)).toBe(1)
		T.expect(broken(function(c)
			c.offer.afterRebirths = 0
		end)).toBe(1)
		T.expect(broken(function(c)
			c.offer.showSeconds = 60
		end)).toBe(1)
	end)
end)

return nil
