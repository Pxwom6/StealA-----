--!strict
-- Integrity checks for the data modules: a typo in config should fail CI, not a live server.
local T = require("./TestKit")
local Catalog = require("../src/shared/Logic/Catalog")
local RarityRoll = require("../src/shared/Logic/RarityRoll")
local Creatures = require("../src/shared/Config/Creatures")
local Rarities = require("../src/shared/Config/Rarities")
local Mutations = require("../src/shared/Config/Mutations")
local MutationRules = require("../src/shared/Logic/MutationRules")
local Format = require("../src/shared/Logic/Format")
local Economy = require("../src/shared/Config/Economy")
local Gameplay = require("../src/shared/Config/Gameplay")
local Monetization = require("../src/shared/Config/Monetization")
local Theme = require("../src/shared/Config/Theme")
local Sounds = require("../src/shared/Config/Sounds")
local LiveOps = require("../src/shared/Config/LiveOps")
local LiveOpsRules = require("../src/shared/Logic/LiveOpsRules")
local StealRules = require("../src/shared/Logic/StealRules")
local Types = require("../src/shared/Types")

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
	-- Halloween 2026 event Snacklings (eventId "Halloween2026")
	"candy_corn_cat",
	"pumpkin_pie_bat",
	"caramel_apple_ghoul",
	"jack_o_lantern_latte",
}

-- Every mutation id that has shipped (saved in players' CreatureRecord.variant). APPEND-ONLY, like creature ids: a
-- save keeps a variant the config doesn't know, but it earns x1 and looks plain until the id is back. To stop a
-- mutation appearing, give it an `eventId` that is never active instead.
local RELEASED_MUTATION_IDS = {
	"golden",
	"diamond",
	"rainbow",
	"haunted", -- Halloween 2026 (event-only)
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

	T.it("every mutation id from a past release still exists (never remove or rename one)", function()
		local byId: { [string]: boolean } = {}
		for _, mutation in Mutations do
			byId[mutation.id] = true
		end
		for _, id in RELEASED_MUTATION_IDS do
			if not byId[id] then
				error(`mutation id "{id}" shipped in a release but is missing from Config/Mutations`)
			end
		end
	end)

	T.it("every mutation in config is on the released list (append new ids when they ship)", function()
		for _, mutation in Mutations do
			if table.find(RELEASED_MUTATION_IDS, mutation.id) == nil then
				error(`append "{mutation.id}" to RELEASED_MUTATION_IDS in tests/Config.spec.luau so it is protected`)
			end
		end
	end)

	T.it("mutation config validates", function()
		local problems = Catalog.validateMutations(Mutations)
		if #problems > 0 then
			print(table.concat(problems, "\n"))
		end
		T.expect(#problems).toBe(0)
	end)

	T.it("mutation ids never clash with creature ids or rarity ids", function()
		for _, mutation in Mutations do
			for _, creature in Creatures do
				T.expect(mutation.id ~= creature.id).toBe(true)
			end
			for _, rarity in Rarities do
				T.expect(mutation.id ~= rarity.id).toBe(true)
			end
		end
	end)

	T.it("rarer mutations pay more, and a mutated creature always earns more than it costs extra", function()
		local catalog = Catalog.build(Creatures, Rarities, Mutations)
		local previous: Types.MutationDef? = nil
		for _, mutation in catalog.mutationList do
			if previous ~= nil and previous.eventId == nil and mutation.eventId == nil then
				T.expect(mutation.chance).toBeLessThan(previous.chance)
				T.expect(mutation.incomeMultiplier).toBeGreaterThan(previous.incomeMultiplier)
			end
			-- payback never gets worse than the plain creature's (a mutation is always a lucky find)
			T.expect(mutation.incomeMultiplier).toBeAtLeast(mutation.priceMultiplier)
			previous = mutation
		end
	end)

	T.it("every announcement names the mutation (banners use the mutated creature name)", function()
		local catalog = Catalog.build(Creatures, Rarities, Mutations)
		local def = catalog.creatureList[1]
		for _, mutation in catalog.mutationList do
			local name = MutationRules.displayName(catalog.mutations, def, mutation.id, Theme.text.mutatedName)
			for _, template in { Theme.text.announceSpawn, Theme.text.announceBuy, Theme.text.announceSteal } do
				local text = Format.template(
					template,
					{ creature = name, rarity = "Secret", player = "A", thief = "A", owner = "B" }
				)
				T.expect(string.find(text, mutation.displayName, 1, true) ~= nil).toBe(true)
				T.expect(string.find(text, def.displayName, 1, true) ~= nil).toBe(true)
			end
		end
	end)

	T.it("mutation odds ignore luck: the Server Luck disclosure stays exact", function()
		-- MutationRules has no luck input at all; this pins that the shipped odds are the configured chances.
		local odds = MutationRules.odds(Mutations, {})
		local total = 0
		for _, entry in odds do
			total += entry.chance
		end
		local configured = 0
		for _, mutation in Mutations do
			if mutation.eventId == nil then
				configured += mutation.chance
			end
		end
		T.expect(total).toBeNear(configured, 1e-12)
		T.expect(total).toBeLessThan(0.1) -- keeps BALANCE.md's time-to-rarity tables meaningful
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

T.describe("Halloween 2026 event Snacklings", function()
	local catalog = Catalog.build(Creatures, Rarities, Mutations)
	local eventCreatures: { Types.CreatureDef } = {}
	for _, creature in Creatures do
		if creature.eventId == "Halloween2026" then
			table.insert(eventCreatures, creature)
		end
	end

	T.it("has one Snackling per tier from Rare to Mythic, tied to a configured event", function()
		local tiers: { string } = {}
		for _, creature in eventCreatures do
			table.insert(tiers, creature.rarity)
		end
		T.expect(tiers).toEqual({ "Rare", "Epic", "Legendary", "Mythic" })
		local configured = false
		for _, event in LiveOps.events do
			configured = configured or event.id == "Halloween2026"
		end
		T.expect(configured).toBe(true)
	end)

	T.it("prices and pays back like the regular Snacklings of its tier", function()
		for _, creature in eventCreatures do
			local minPrice, maxPrice, minPayback, maxPayback = math.huge, 0, math.huge, 0
			for _, regular in catalog.byRarity[creature.rarity] do
				if regular.eventId == nil then
					minPrice = math.min(minPrice, regular.price)
					maxPrice = math.max(maxPrice, regular.price)
					minPayback = math.min(minPayback, regular.price / regular.income)
					maxPayback = math.max(maxPayback, regular.price / regular.income)
				end
			end
			T.expect(creature.price).toBeAtLeast(minPrice)
			T.expect(creature.price).toBeAtMost(maxPrice)
			T.expect(creature.price / creature.income).toBeAtLeast(minPayback)
			T.expect(creature.price / creature.income).toBeAtMost(maxPayback)
		end
	end)

	T.it("leaves every regular belt roll unchanged outside the event", function()
		local regular: { Types.CreatureDef } = {}
		for _, creature in Creatures do
			if creature.eventId == nil then
				table.insert(regular, creature)
			end
		end
		local withEvent, without = T.seededRandom(31337), T.seededRandom(31337)
		for _, luck in { 1, 2, 6 } do
			for _ = 1, 20000 do
				local a = RarityRoll.roll(Rarities, Creatures, luck, {}, withEvent)
				local b = RarityRoll.roll(Rarities, regular, luck, {}, without)
				T.expect(a).toBe(b)
			end
		end
	end)

	T.it("shares its tier's odds during the event instead of adding to them", function()
		local events = { Halloween2026 = true }
		for _, luck in { 1, 2 } do
			T.expect(RarityRoll.odds(Rarities, Creatures, luck, events))
				.toEqual(RarityRoll.odds(Rarities, Creatures, luck, {}))
		end
		local rng = T.seededRandom(2026)
		local seen: { [string]: boolean } = {}
		for _ = 1, 200000 do
			local id = RarityRoll.roll(Rarities, Creatures, 1, events, rng) :: string
			seen[id] = true
		end
		for _, creature in eventCreatures do
			T.expect(seen[creature.id]).toBe(true)
		end
	end)
end)

T.describe("Halloween 2026 Haunted mutation", function()
	local haunted: Types.MutationDef? = nil
	for _, mutation in Mutations do
		if mutation.id == "haunted" then
			haunted = mutation
		end
	end
	local function total(events: { [string]: boolean }): number
		local sum = 0
		for _, entry in MutationRules.odds(Mutations, events) do
			sum += entry.chance
		end
		return sum
	end

	T.it("only rolls during Halloween2026 and is always a lucky find", function()
		local def = haunted :: Types.MutationDef
		T.expect(def.eventId).toBe("Halloween2026")
		T.expect(def.incomeMultiplier).toBeAtLeast(def.priceMultiplier)
		for _, entry in MutationRules.odds(Mutations, {}) do
			T.expect(entry.id ~= "haunted").toBe(true)
		end
		T.expect(total({ Halloween2026 = true }) - total({})).toBeNear(def.chance, 1e-12)
	end)

	T.it("is a chase: rarer than Golden and stronger, so Golden still matters during the event", function()
		local def = haunted :: Types.MutationDef
		local golden: Types.MutationDef? = nil
		for _, mutation in Mutations do
			if mutation.id == "golden" then
				golden = mutation
			end
		end
		T.expect(def.chance).toBeLessThan((golden :: Types.MutationDef).chance)
		T.expect(def.incomeMultiplier).toBeGreaterThan((golden :: Types.MutationDef).incomeMultiplier)
	end)

	T.it("keeps every mutation chance together, event ones included, below 10%", function()
		local allEvents: { [string]: boolean } = {}
		for _, mutation in Mutations do
			if mutation.eventId then
				allEvents[mutation.eventId] = true
			end
		end
		T.expect(total(allEvents)).toBeLessThan(0.1)
	end)

	T.it("rolls after the permanent mutations, so their rolls are unchanged", function()
		local def = haunted :: Types.MutationDef
		for _, mutation in Mutations do
			if mutation.eventId == nil then
				T.expect(mutation.order).toBeLessThan(def.order)
			end
		end
		local a, b = T.seededRandom(5), T.seededRandom(5)
		for _ = 1, 20000 do
			local during = MutationRules.roll(Mutations, { Halloween2026 = true }, a)
			local outside = MutationRules.roll(Mutations, {}, b)
			if during ~= "haunted" then
				T.expect(during).toBe(outside)
			end
		end
	end)
end)

T.describe("Event HUD copy", function()
	T.it("counts the banner event down as '<title> ends in 3d 4h'", function()
		local seconds = 3 * 86400 + 4 * 3600 + 59 * 60
		local text = Format.template(Theme.text.eventEndsIn, { event = "Halloween", time = Format.duration(seconds) })
		T.expect(text).toBe("Halloween ends in 3d 4h")
		T.expect(type(Theme.text.eventFallbackTitle)).toBe("string")
		T.expect(#Theme.text.eventTag).toBeGreaterThan(0)
	end)
end)

T.describe("Config integrity (continued)", function()
	T.it("every LiveOps event id is unique", function()
		local seen: { [string]: boolean } = {}
		for _, event in LiveOps.events do
			T.expect(seen[event.id]).toBeNil()
			seen[event.id] = true
		end
	end)
end)

return nil
