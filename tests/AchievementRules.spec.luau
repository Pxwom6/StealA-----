--!strict
local T = require("./TestKit")
local Achievements = require("../src/shared/Config/Achievements")
local AchievementRules = require("../src/shared/Logic/AchievementRules")
local Catalog = require("../src/shared/Logic/Catalog")
local CodeRules = require("../src/shared/Logic/CodeRules")
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
	-- more achievements (28)
	"conveyorKing",
	"phantomThief",
	"robbed",
	"thickSkin",
	"archivist",
	"fullSet",
	"snackdexScholar",
	"limitedEdition",
	"seasonCollector",
	"mutationManiac",
	"trillionaire",
	"moneyMachine",
	"cashCannon",
	"snackEmpire",
	"sevenLives",
	"explorer",
	"highRoller",
	"snackBreak",
	"regular",
	"veteran",
	"weekStreak",
	"devoted",
	"insider",
	"codeCracker",
	"crateCracker",
	"gotcha",
	"giantSlayer",
	"mvp",
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

	T.it("only asks for what exists: mutations, limited Snacklings, tiers", function()
		local regularMutations, limited = 0, 0
		for _, mutation in catalog.mutationList do
			if mutation.eventId == nil then
				regularMutations += 1
			end
		end
		for _, def in catalog.creatures do
			if def.eventId ~= nil then
				limited += 1
			end
		end
		local tiers = 0
		for _ in catalog.rarities do
			tiers += 1
		end
		for _, def in Achievements.list do
			if def.goal == "mutations" then
				T.expect(def.target <= regularMutations).toBe(true)
			elseif def.goal == "limited" then
				T.expect(def.target <= limited).toBe(true)
			elseif def.goal == "tiers" then
				T.expect(def.target <= tiers).toBe(true)
			end
		end
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

	T.it("counts being robbed, the best income, time played, the daily streak and codes", function()
		local data = save()
		data.stats.timesStolenFrom = 3
		data.stats.bestCashPerSecond = 150000
		data.stats.playTime = 5400 -- 1.5 hours
		data.daily.streak = 8
		data.flags[CodeRules.flagKey("WELCOME")] = true
		data.flags[CodeRules.flagKey("SNACKTIME")] = true
		data.flags[AchievementRules.mapFlagKey("meadow")] = true -- other flags don't count as codes
		local ctx = AchievementRules.context(data, catalog.creatures, catalog.rarities)
		T.expect(ctx.stolenFrom).toBe(3)
		T.expect(ctx.income).toBe(150000)
		T.expect(ctx.playHours).toBe(1.5)
		T.expect(ctx.streak).toBe(8)
		T.expect(ctx.codes).toBe(2)
		local function done(id: string): boolean
			return AchievementRules.isDone(byId(id), ctx, catalog.rarities)
		end
		T.expect(done("robbed")).toBe(true)
		T.expect(done("thickSkin")).toBe(false)
		T.expect(done("moneyMachine")).toBe(true)
		T.expect(done("cashCannon")).toBe(true)
		T.expect(done("snackEmpire")).toBe(false)
		T.expect(done("snackBreak")).toBe(true)
		T.expect(done("regular")).toBe(false)
		T.expect(done("weekStreak")).toBe(true)
		T.expect(done("devoted")).toBe(false)
		T.expect(done("insider")).toBe(true)
		T.expect(done("codeCracker")).toBe(false)
		local progress, target = AchievementRules.progress(byId("regular"), ctx, catalog.rarities)
		T.expect(progress).toBe(1.5) -- the bar moves before the first whole hour
		T.expect(target).toBe(10)
	end)

	T.it("counts limited Snacklings and completed Snackdex tiers", function()
		local data = save()
		local found = 0
		for id, def in catalog.creatures do
			if def.eventId ~= nil and found < 2 then
				data.snackdex.creatures[id] = true
				found += 1
			end
		end
		data.snackdex.tiers.Common = true
		data.snackdex.tiers.Uncommon = true
		local ctx = AchievementRules.context(data, catalog.creatures, catalog.rarities)
		T.expect(ctx.limited).toBe(2)
		T.expect(ctx.discovered).toBe(2)
		T.expect(ctx.tiers).toBe(2)
		T.expect(AchievementRules.isDone(byId("limitedEdition"), ctx, catalog.rarities)).toBe(true)
		T.expect(AchievementRules.isDone(byId("seasonCollector"), ctx, catalog.rarities)).toBe(false)
		T.expect(AchievementRules.isDone(byId("fullSet"), ctx, catalog.rarities)).toBe(true)
		T.expect(AchievementRules.isDone(byId("snackdexScholar"), ctx, catalog.rarities)).toBe(false)
	end)

	T.it("counts milestones from their flags, and only known ones", function()
		local data = save()
		data.flags[AchievementRules.milestoneFlagKey("crate")] = true
		data.flags[AchievementRules.milestoneFlagKey("snackAttack")] = true
		local ctx = AchievementRules.context(data, catalog.creatures, catalog.rarities)
		local done: { [string]: boolean } = {}
		for _, def in AchievementRules.newlyDone(Achievements, ctx, data.flags, catalog.rarities) do
			done[def.id] = true
		end
		T.expect(done.crateCracker).toBe(true)
		T.expect(done.giantSlayer).toBe(true)
		T.expect(done.gotcha).toBeNil()
		T.expect(done.mvp).toBeNil()
		local progress, target = AchievementRules.progress(byId("mvp"), ctx, catalog.rarities)
		T.expect(progress).toBe(0)
		T.expect(target).toBe(1)
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

	T.it("an earned Completionist stays done when new Snacklings ship", function()
		-- Paid before the newest 20 regular Snacklings existed: everything else was found.
		local data = save()
		local regular: { string } = {}
		for id, def in catalog.creatures do
			if def.eventId == nil then
				table.insert(regular, id)
			end
		end
		table.sort(regular)
		for i = 1, #regular - 20 do
			data.snackdex.creatures[regular[i]] = true
		end
		data.flags[AchievementRules.flagKey("completionist")] = true
		local ctx = AchievementRules.context(data, catalog.creatures, catalog.rarities)
		T.expect(AchievementRules.isDone(byId("completionist"), ctx, catalog.rarities)).toBe(false)
		local due: { [string]: boolean } = {}
		for _, def in AchievementRules.newlyDone(Achievements, ctx, data.flags, catalog.rarities) do
			due[def.id] = true
		end
		T.expect(due.completionist).toBeNil()
		for _, entry in AchievementRules.view(Achievements, ctx, data.flags, catalog.rarities) do
			if entry.id == "completionist" then
				T.expect(entry.done).toBe(true)
			end
		end
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
		local unknownMilestone = table.clone(byId("gotcha")) :: any
		unknownMilestone.milestone = "jumpedTwice"
		T.expect(problems({ unknownMilestone })).toBe(1)
		local noMilestone = table.clone(byId("gotcha")) :: any
		noMilestone.milestone = nil
		T.expect(problems({ noMilestone })).toBe(1)
	end)
end)

return nil
