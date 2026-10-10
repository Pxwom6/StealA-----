--!strict
-- Integrity checks for the Snackdex and daily quest config (Config/Snackdex, Config/Quests).
local T = require("./TestKit")
local Catalog = require("../src/shared/Logic/Catalog")
local Creatures = require("../src/shared/Config/Creatures")
local Economy = require("../src/shared/Config/Economy")
local Format = require("../src/shared/Logic/Format")
local Gameplay = require("../src/shared/Config/Gameplay")
local Mutations = require("../src/shared/Config/Mutations")
local QuestRules = require("../src/shared/Logic/QuestRules")
local Quests = require("../src/shared/Config/Quests")
local Rarities = require("../src/shared/Config/Rarities")
local Snackdex = require("../src/shared/Config/Snackdex")
local SnackdexRules = require("../src/shared/Logic/SnackdexRules")
local Theme = require("../src/shared/Config/Theme")

local catalog = Catalog.build(Creatures, Rarities, Mutations)
local text = (Theme.text :: any) :: { [string]: string }

T.describe("Snackdex config", function()
	T.it("validates against the rarities", function()
		T.expect(SnackdexRules.validate(Snackdex, Rarities)).toEqual({})
	end)

	T.it("every rarity has its own tier reward, and rarer tiers pay more", function()
		local previous: { incomeSeconds: number, minimum: number }? = nil
		for _, rarity in catalog.rarityList do
			local reward = Snackdex.tierRewards[rarity.id]
			T.expect(reward ~= nil).toBe(true)
			if previous and reward then
				T.expect(reward.minimum).toBeGreaterThan(previous.minimum)
				T.expect(reward.incomeSeconds).toBeAtLeast(previous.incomeSeconds)
			end
			previous = reward
		end
	end)

	T.it("each tier's minimum reward stays well below its cheapest Snackling (no alt-account lending profit)", function()
		for _, rarity in catalog.rarityList do
			local cheapest = math.huge
			for _, creature in Creatures do
				if creature.rarity == rarity.id and creature.eventId == nil then
					cheapest = math.min(cheapest, creature.price)
				end
			end
			local reward = Snackdex.tierRewards[rarity.id]
			if reward and cheapest < math.huge then
				T.expect(reward.minimum).toBeAtMost(cheapest * 0.5)
			end
		end
	end)

	T.it("every tier can be completed from the belt, whatever the roster", function()
		for _, tier in SnackdexRules.tierProgress(SnackdexRules.empty(), Creatures, catalog.rarityList) do
			T.expect(tier.total).toBeGreaterThan(0)
		end
	end)

	T.it("the whole collection is worth less than one rebirth", function()
		local everyTier = #catalog.rarityList * Snackdex.incomeBonusPerTier
		T.expect(math.min(everyTier, Snackdex.maxIncomeBonus)).toBeLessThan(Economy.rebirth.multiplierPerRebirth)
		T.expect(Snackdex.maxIncomeBonus).toBeAtLeast(everyTier) -- the cap never takes a tier's bonus away today
	end)

	T.it("has the UI text it needs", function()
		local line =
			Format.template(Theme.text.snackdexTierComplete, { rarity = "Common", amount = "$250", percent = 3 })
		T.expect((string.find(line, "{", 1, true))).toBeNil()
		T.expect(#Theme.text.snackdexEventTab).toBeGreaterThan(0)
	end)
end)

T.describe("Daily quests config", function()
	local rarityIds: { [string]: boolean } = {}
	for _, rarity in Rarities do
		rarityIds[rarity.id] = true
	end

	T.it("validates against the rarities and Theme.text", function()
		T.expect(QuestRules.validate(Quests, rarityIds, text)).toEqual({})
	end)

	T.it("rolls two easy quests and one harder one a day", function()
		T.expect(Quests.slots).toEqual({ "easy", "easy", "hard" })
	end)

	T.it("every quest's text fills in with nothing left over", function()
		for _, def in Quests.pool do
			local minRarity = if def.minRarity then catalog.rarities[def.minRarity] else nil
			local line = Format.template(text[def.textKey], {
				count = QuestRules.target(def, 100),
				amount = Format.cash(QuestRules.target(def, 100), Theme.currencySymbol),
				rarity = if minRarity then minRarity.displayName else "",
			})
			T.expect((string.find(line, "{", 1, true))).toBeNil()
		end
	end)

	T.it("a full day of quests pays well under an hour of steady income", function()
		local seconds = Quests.allDoneBonus.incomeSeconds
		for _, difficulty in Quests.slots do
			seconds += Quests.rewards[difficulty].incomeSeconds
		end
		T.expect(seconds).toBeLessThan(3600)
		-- Hard quests pay more than easy ones.
		T.expect(Quests.rewards.hard.incomeSeconds).toBeGreaterThan(Quests.rewards.easy.incomeSeconds)
		T.expect(Quests.rewards.hard.minimum).toBeGreaterThan(Quests.rewards.easy.minimum)
	end)

	T.it("claiming is rate limited", function()
		local limit = Gameplay.rateLimits.ClaimQuest
		T.expect(limit ~= nil).toBe(true)
		T.expect(limit.burst).toBeAtLeast(1)
		T.expect(limit.perSecond).toBeGreaterThan(0)
	end)
end)

return nil
