--!strict
local T = require("./TestKit")
local Achievements = require("../src/shared/Config/Achievements")
local AchievementRules = require("../src/shared/Logic/AchievementRules")
local Catalog = require("../src/shared/Logic/Catalog")
local Creatures = require("../src/shared/Config/Creatures")
local DataSchema = require("../src/shared/Logic/DataSchema")
local GiftRules = require("../src/shared/Logic/GiftRules")
local MapThemes = require("../src/shared/Config/MapThemes")
local Mutations = require("../src/shared/Config/Mutations")
local Rarities = require("../src/shared/Config/Rarities")
local Types = require("../src/shared/Types")

local catalog = Catalog.build(Creatures, Rarities, Mutations)

-- Every achievement id that has shipped. APPEND-ONLY: a renamed id would pay its reward again.
local RELEASED_ACHIEVEMENT_IDS = {
	"firstBite",
	"snackShopper",
	"beltBoss",
	"stickyFingers",
	"masterThief",
	"legendaryBandit",
	"collector",
	"curator",
	"completionist",
	"rareFind",
	"epicTaste",
	"legend",
	"mythical",
	"secretKeeper",
	"shiny",
	"mutationHunter",
	"mutationMaster",
	"pocketMoney",
	"millionaire",
	"billionaire",
	"bornAgain",
	"fiveLives",
	"tourist",
	"globetrotter",
	"luckySpinner",
}

local function rewardProblems(reward: Types.PrizeReward, name: string): { string }
	return GiftRules.rewardProblems(reward, name, catalog.mutations, true)
end

local function save(): Types.PlayerData
	return DataSchema.template(100)
end

local function byId(id: string): Types.AchievementDef
	for _, def in Achievements.list do
		if def.id == id then
			return def
		end
	end
	error(`no achievement {id}`)
end

T.describe("AchievementRules: the real config", function()
	T.it("is valid", function()
		local problems = AchievementRules.validate(Achievements, catalog.rarities, #MapThemes.order, rewardProblems)
		if #problems > 0 then
			print(table.concat(problems, "\n"))
		end
		T.expect(#problems).toBe(0)
	end)

	T.it("keeps every shipped id, and lists every new one", function()
		local ids: { [string]: boolean } = {}
		for _, def in Achievements.list do
			ids[def.id] = true
			if table.find(RELEASED_ACHIEVEMENT_IDS, def.id) == nil then
				error(`append "{def.id}" to RELEASED_ACHIEVEMENT_IDS so it is protected`)
			end
		end
		for _, id in RELEASED_ACHIEVEMENT_IDS do
			if not ids[id] then
				error(`achievement {id} shipped and must stay (a renamed id pays again)`)
			end
		end
	end)

	T.it("asks for every map in 'Globetrotter'", function()
		T.expect(byId("globetrotter").target).toBe(#MapThemes.order)
	end)
end)

T.describe("AchievementRules progress", function()
	T.it("starts with nothing done", function()
		local data = save()
		local ctx = AchievementRules.context(data, catalog.creatures, catalog.rarities)
		T.expect(#AchievementRules.newlyDone(Achievements, ctx, data.flags, catalog.rarities)).toBe(0)
	end)

	T.it("counts belt purchases, steals, earnings, spins and rebirths from the save", function()
		local data = save()
		data.stats.beltPurchases = 30
		data.stats.steals = 2
		data.stats.totalEarned = 2e6
		data.spin.total = 10
		data.rebirths = 1
		local ctx = AchievementRules.context(data, catalog.creatures, catalog.rarities)
		local done: { [string]: boolean } = {}
		for _, def in AchievementRules.newlyDone(Achievements, ctx, data.flags, catalog.rarities) do
			done[def.id] = true
		end
		for _, id in
			{ "firstBite", "snackShopper", "stickyFingers", "pocketMoney", "millionaire", "luckySpinner", "bornAgain" }
		do
			T.expect(done[id]).toBe(true)
		end
		T.expect(done.beltBoss).toBeNil()
		T.expect(done.billionaire).toBeNil()
		T.expect(done.masterThief).toBeNil()
	end)

	T.it("reads the Snackdex: discoveries, the rarest owned, mutations", function()
		local data = save()
		local legendary: string? = nil
		for id, def in catalog.creatures do
			if def.rarity == "Legendary" and def.eventId == nil then
				legendary = id
			end
		end
		data.snackdex.creatures[legendary :: string] = true
		data.snackdex.variants[legendary :: string] = { golden = true, molten = true }
		local ctx = AchievementRules.context(data, catalog.creatures, catalog.rarities)
		T.expect(ctx.discovered).toBe(1)
		T.expect(ctx.mutations).toBe(2)
		T.expect(AchievementRules.isDone(byId("legend"), ctx, catalog.rarities)).toBe(true)
		T.expect(AchievementRules.isDone(byId("rareFind"), ctx, catalog.rarities)).toBe(true) -- or rarer
		T.expect(AchievementRules.isDone(byId("mythical"), ctx, catalog.rarities)).toBe(false)
		T.expect(AchievementRules.isDone(byId("shiny"), ctx, catalog.rarities)).toBe(true)
		local progress, target = AchievementRules.progress(byId("completionist"), ctx, catalog.rarities)
		T.expect(progress).toBe(1)
		T.expect(target).toBe(ctx.regularTotal)
	end)

	T.it("counts the maps played on from their flags", function()
		local data = save()
		for index = 1, 5 do
			data.flags[AchievementRules.mapFlagKey(MapThemes.order[index])] = true
		end
		local ctx = AchievementRules.context(data, catalog.creatures, catalog.rarities)
		T.expect(ctx.maps).toBe(5)
		T.expect(AchievementRules.isDone(byId("tourist"), ctx, catalog.rarities)).toBe(true)
		T.expect(AchievementRules.isDone(byId("globetrotter"), ctx, catalog.rarities)).toBe(false)
	end)

	T.it("never pays one twice: a flag marks it done", function()
		local data = save()
		data.stats.beltPurchases = 1
		local ctx = AchievementRules.context(data, catalog.creatures, catalog.rarities)
		T.expect(#AchievementRules.newlyDone(Achievements, ctx, data.flags, catalog.rarities)).toBe(1)
		data.flags[AchievementRules.flagKey("firstBite")] = true
		T.expect(#AchievementRules.newlyDone(Achievements, ctx, data.flags, catalog.rarities)).toBe(0)
		local view = AchievementRules.view(Achievements, ctx, data.flags, catalog.rarities)
		T.expect(view[1]).toEqual({ id = "firstBite", progress = 1, target = 1, done = true })
	end)
end)

T.describe("AchievementRules.validate", function()
	local function problems(list: { any }): number
		return #AchievementRules.validate({ list = list } :: any, catalog.rarities, #MapThemes.order, rewardProblems)
	end
	local good = byId("firstBite")

	T.it("refuses repeated ids, unknown goals and rarities, too many maps and bad rewards", function()
		T.expect(problems({ good, good })).toBe(1)
		T.expect(problems({ table.clone(good) :: any })).toBe(0)
		local unknownGoal = table.clone(good) :: any
		unknownGoal.goal = "jumps"
		T.expect(problems({ unknownGoal })).toBe(1)
		local badRarity = table.clone(byId("legend")) :: any
		badRarity.rarity = "Ultra"
		T.expect(problems({ badRarity })).toBe(1)
		local tooManyMaps = table.clone(byId("globetrotter")) :: any
		tooManyMaps.target = 99
		T.expect(problems({ tooManyMaps })).toBe(1)
		local badReward = table.clone(good) :: any
		badReward.reward = { kind = "gems" }
		T.expect(problems({ badReward })).toBe(1)
	end)
end)

return nil
