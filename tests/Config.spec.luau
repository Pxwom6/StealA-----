--!strict
-- Integrity checks for the data modules: a typo in config should fail CI, not a live server.
local T = require("./TestKit")
local Catalog = require("../src/shared/Logic/Catalog")
local RarityRoll = require("../src/shared/Logic/RarityRoll")
local Creatures = require("../src/shared/Config/Creatures")
local Rarities = require("../src/shared/Config/Rarities")
local Economy = require("../src/shared/Config/Economy")
local Gameplay = require("../src/shared/Config/Gameplay")
local Monetization = require("../src/shared/Config/Monetization")
local Theme = require("../src/shared/Config/Theme")
local Sounds = require("../src/shared/Config/Sounds")
local LiveOps = require("../src/shared/Config/LiveOps")
local LiveOpsRules = require("../src/shared/Logic/LiveOpsRules")
local StealRules = require("../src/shared/Logic/StealRules")

-- Every creature id that has shipped. APPEND-ONLY: add new ids when they release, never remove or rename one —
-- players own them. (A save holding an id missing from config quarantines that creature: it vanishes from the
-- base until the id is back.) To stop a creature spawning, give it an `eventId` that is never active instead.
local RELEASED_CREATURE_IDS = {
	"pizza_pup",
	"pretzel_pal",
	"gummy_grub",
	"toast_toad",
	"sushi_slug",
	"nacho_newt",
	"waffle_wombat",
	"taco_turtle",
	"burrito_bear",
	"cupcake_cub",
	"ramen_raccoon",
	"popcorn_penguin",
	"bagel_badger",
	"donut_dragon",
	"pancake_panda",
	"churro_cheetah",
	"lasagna_lion",
	"dumpling_dino",
	"gelato_griffin",
	"croissant_kraken",
}

T.describe("Config integrity", function()
	T.it("every grab refusal with a message has that text in Theme.text", function()
		local text = (Theme.text :: any) :: { [string]: string }
		local reasons = {
			"own",
			"carrying",
			"cooldown",
			"locked",
			"protected",
			"far",
			"outside",
			"height",
			"hold",
			"full",
			"untrusted",
		}
		for _, reason in reasons do
			local key = StealRules.messageKey(reason)
			if key == nil or type(text[key]) ~= "string" then
				error(`grab refusal "{reason}" has no message in Theme.text (key {tostring(key)})`)
			end
		end
	end)

	T.it("every carry cancel reason with a message has that text in Theme.text", function()
		local text = (Theme.text :: any) :: { [string]: string }
		for _, reason in StealRules.CANCEL_REASONS do
			local key = StealRules.cancelMessageKey(reason)
			if key ~= nil and type(text[key]) ~= "string" then
				error(`carry cancel "{reason}" has no message in Theme.text (key {key})`)
			end
		end
	end)

	T.it("every creature id from a past release still exists (never remove or rename one)", function()
		local byId: { [string]: boolean } = {}
		for _, creature in Creatures do
			byId[creature.id] = true
		end
		for _, id in RELEASED_CREATURE_IDS do
			if not byId[id] then
				error(`creature id "{id}" shipped in a release but is missing from Config/Creatures`)
			end
		end
	end)

	T.it("every creature in config is on the released list (append new ids when they ship)", function()
		for _, creature in Creatures do
			if table.find(RELEASED_CREATURE_IDS, creature.id) == nil then
				error(`append "{creature.id}" to RELEASED_CREATURE_IDS in tests/Config.spec.luau so it is protected`)
			end
		end
	end)

	T.it("creature and rarity config validates", function()
		local problems = Catalog.validate(Creatures, Rarities)
		T.expect(#problems).toBe(0)
		if #problems > 0 then
			print(table.concat(problems, "\n"))
		end
	end)

	T.it("has exactly the seven rarity tiers in order", function()
		local catalog = Catalog.build(Creatures, Rarities)
		local ids = {}
		for _, rarity in catalog.rarityList do
			table.insert(ids, rarity.id)
		end
		T.expect(ids).toEqual({ "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret" })
	end)

	T.it("rarer tiers are strictly rarer, pricier and earn more", function()
		local catalog = Catalog.build(Creatures, Rarities)
		local previous: Catalog.RarityInfo? = nil
		local previousMaxIncome, previousMaxPrice = 0, 0
		for _, rarity in catalog.rarityList do
			if previous ~= nil then
				T.expect(rarity.beltWeight).toBeLessThan(previous.beltWeight)
			end
			local minIncome, minPrice, maxIncome, maxPrice = math.huge, math.huge, 0, 0
			for _, creature in catalog.byRarity[rarity.id] do
				minIncome = math.min(minIncome, creature.income)
				minPrice = math.min(minPrice, creature.price)
				maxIncome = math.max(maxIncome, creature.income)
				maxPrice = math.max(maxPrice, creature.price)
			end
			T.expect(minIncome).toBeGreaterThan(previousMaxIncome)
			T.expect(minPrice).toBeGreaterThan(previousMaxPrice)
			previousMaxIncome, previousMaxPrice = maxIncome, maxPrice
			previous = rarity
		end
	end)

	T.it("payback time grows with rarity (the chase stays meaningful)", function()
		local catalog = Catalog.build(Creatures, Rarities)
		local previousAvg = 0
		for _, rarity in catalog.rarityList do
			local sum, count = 0, 0
			for _, creature in catalog.byRarity[rarity.id] do
				sum += creature.price / creature.income
				count += 1
			end
			local avg = sum / count
			T.expect(avg).toBeGreaterThan(previousAvg)
			previousAvg = avg
		end
	end)

	T.it("Mythic and Secret are announced server-wide", function()
		for _, rarity in Rarities do
			if rarity.id == "Mythic" or rarity.id == "Secret" then
				T.expect(rarity.announceOnSpawn).toBe(true)
				T.expect(rarity.announceOnBuy).toBe(true)
			end
		end
	end)

	T.it("odds sum to 1 with and without luck", function()
		for _, luck in { 1, 2, 6 } do
			local sum = 0
			for _, entry in RarityRoll.odds(Rarities, Creatures, luck, {}) do
				sum += entry.chance
			end
			T.expect(sum).toBeNear(1, 1e-9)
		end
	end)

	T.it("every rarity has a sound slot and a theme colour is valid hex", function()
		for _, rarity in Rarities do
			T.expect(Sounds.rarity[rarity.id] ~= nil).toBe(true)
		end
		for name, hex in (Theme.palette :: any) :: { [string]: string } do
			T.expect(string.match(hex, "^#%x%x%x%x%x%x$") ~= nil and name ~= "").toBe(true)
		end
		for _, hex in (Theme.world :: any) :: { [string]: string } do
			T.expect(string.match(hex, "^#%x%x%x%x%x%x$") ~= nil).toBe(true)
		end
		T.expect(#Theme.plotColors).toBeAtLeast(Gameplay.map.plotCount)
	end)

	T.it("every store item has copy, an id field and a matching product kind", function()
		for _, key in Monetization.storePasses do
			T.expect(Monetization.passes[key] ~= nil).toBe(true)
			T.expect(Theme.store[key] ~= nil).toBe(true)
		end
		for _, key in Monetization.storeProducts do
			T.expect(Monetization.products[key] ~= nil).toBe(true)
			T.expect(Theme.store[key] ~= nil).toBe(true)
		end
		for key, product in Monetization.products do
			if product.kind == "Cash" then
				T.expect((Economy.cashPacks :: any)[key] ~= nil).toBe(true)
			end
		end
	end)

	T.it("product and pass ids are whole numbers and never duplicated", function()
		local seen: { [number]: boolean } = {}
		local function check(id: number)
			T.expect(id == math.floor(id) and id >= 0).toBe(true)
			if id ~= 0 then
				T.expect(seen[id]).toBeNil()
				seen[id] = true
			end
		end
		for _, pass in Monetization.passes do
			check(pass.id)
		end
		for _, product in Monetization.products do
			check(product.id)
		end
	end)

	T.it("fairness: a paid lock can never chain into a permanent lock", function()
		T.expect(Gameplay.lock.minVulnerableSeconds).toBeGreaterThan(0)
		T.expect(Gameplay.lock.minVulnerableSeconds).toBeAtMost(Gameplay.lock.cooldownSeconds)
	end)

	T.it("rate limits exist for every client intent", function()
		for _, name in
			{
				"ClientReady",
				"BuyBeltItem",
				"BuyPodium",
				"SellCreature",
				"StealBegin",
				"StealConfirm",
				"TagThief",
				"LockBase",
				"Rebirth",
				"ClaimDaily",
				"ClientEvent",
				"CheckGroup",
				"InvitePrompted",
				"DevGrantProduct",
			}
		do
			local limit = Gameplay.rateLimits[name]
			T.expect(limit ~= nil).toBe(true)
			T.expect(limit.burst).toBeAtLeast(1)
			T.expect(limit.perSecond).toBeGreaterThan(0)
		end
	end)

	T.it("any thief allowed to carry can still be tagged from the ground", function()
		-- a tagger standing on the ground (root ~3 studs up) must reach a thief at the carry height cap
		T.expect(Gameplay.steal.tagVerticalAllowance).toBeGreaterThan(Gameplay.steal.maxCarryHeight - 3)
		T.expect(Gameplay.steal.maxCarryHeight).toBeGreaterThan(Gameplay.map.wallHeight)
		-- and a thief standing on the ground (root ~3 studs up) is never below the carry floor
		T.expect(Gameplay.steal.minCarryHeight).toBeLessThan(2)
	end)

	T.it("collect pads never overlap their neighbours", function()
		T.expect(Gameplay.collect.padRange).toBeLessThan(Gameplay.map.podiumRowSpacing / 2)
	end)

	T.it("podium geometry fits the plot", function()
		local map = Gameplay.map
		local rows = math.ceil(map.maxPodiums / map.podiumColumns)
		local depthUsed = map.podiumFirstRowOffset + (rows - 1) * map.podiumRowSpacing
		T.expect(depthUsed).toBeLessThan(map.plotDepth - 4)
		local maxFromCash = Economy.startingPodiums + Economy.podiumUpgrade.maxPurchased
		T.expect(maxFromCash + Monetization.perks.extraPodiums).toBeAtMost(map.maxPodiums)
	end)

	T.it("shipped LiveOps events pass validation", function()
		local _, problems = LiveOpsRules.validateEvents(LiveOps.events, LiveOps.limits)
		T.expect(#problems).toBe(0)
	end)
end)

return nil
