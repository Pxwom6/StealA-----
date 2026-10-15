--!strict
--[[
	Achievement rules (Config/Achievements): how far a player is with each goal, read from what the save already keeps
	(stats, the Snackdex, rebirths, Lucky Spins, the daily streak, redeemed codes, map and milestone flags), which ones
	are done, and validation. A finished one is marked with the flag ach_<id> (no save-format change) and paid once
	(AchievementService).

	Milestones are things done at least once that no counter keeps (opening a Supply Crate, taking down a Snack Attack
	giant...): the service where it happens emits a GameEvents "milestone" and AchievementService sets the flag
	did_<milestone>. They count from the day they shipped (nothing earlier was recorded).
	Pure: no Roblox APIs.
]]

local Types = require("../Types")
local CodeRules = require("./CodeRules")

type AchievementDef = Types.AchievementDef
type AchievementsConfig = Types.AchievementsConfig

local AchievementRules = {}

AchievementRules.FLAG_PREFIX = "ach_"
AchievementRules.MAP_FLAG_PREFIX = "map_"
AchievementRules.MILESTONE_FLAG_PREFIX = "did_"

-- The milestones a "milestone" goal can ask for, and where each is recorded.
AchievementRules.MILESTONES = table.freeze({
	crate = true, -- opened a Supply Crate (DropService)
	runaway = true, -- caught a runaway Snackling (DropService)
	snackAttack = true, -- shared in a Snack Attack takedown: landed its minimum hits (BossService)
	snackAttackTop = true, -- the top hitter on a Snack Attack giant that went down (BossService)
} :: { [string]: boolean })

local SECONDS_PER_HOUR = 3600

AchievementRules.GOALS = table.freeze({
	beltPurchases = true,
	steals = true,
	rebirths = true,
	spins = true,
	earned = true,
	discovered = true,
	allRegular = true,
	rarity = true,
	mutations = true,
	maps = true,
	stolenFrom = true,
	income = true,
	playHours = true,
	limited = true,
	tiers = true,
	streak = true,
	codes = true,
	milestone = true,
} :: { [string]: boolean })

-- What the goals are counted from, gathered once per check (AchievementRules.context).
export type Context = {
	beltPurchases: number,
	steals: number,
	rebirths: number,
	spins: number,
	earned: number,
	discovered: number,
	regularFound: number,
	regularTotal: number,
	bestRarityOrder: number, -- the rarest rarity ever owned (its order), 0 for none
	mutations: number,
	maps: number,
	stolenFrom: number,
	income: number, -- the best steady income per second ever reached
	playHours: number, -- fractional
	limited: number, -- limited (event) Snacklings discovered
	tiers: number, -- Snackdex tiers completed
	streak: number,
	codes: number,
	milestones: { [string]: boolean }, -- milestone ids done
}

function AchievementRules.flagKey(id: string): string
	return AchievementRules.FLAG_PREFIX .. id
end

function AchievementRules.mapFlagKey(themeId: string): string
	return AchievementRules.MAP_FLAG_PREFIX .. themeId
end

function AchievementRules.milestoneFlagKey(milestone: string): string
	return AchievementRules.MILESTONE_FLAG_PREFIX .. milestone
end

local function startsWith(text: string, prefix: string): boolean
	return string.sub(text, 1, #prefix) == prefix
end

-- Gathers the counts from a save. `creatures` / `rarities` are the catalog's (by id).
function AchievementRules.context(
	data: Types.PlayerData,
	creatures: { [string]: Types.CreatureDef },
	rarities: { [string]: Types.RarityDef }
): Context
	local discovered, regularFound, regularTotal, best, limited = 0, 0, 0, 0, 0
	for id, def in creatures do
		if def.eventId == nil then
			regularTotal += 1
			if data.snackdex.creatures[id] == true then
				regularFound += 1
			end
		end
	end
	local mutations: { [string]: boolean } = {}
	for id, owned in data.snackdex.creatures do
		if owned then
			discovered += 1
			local def = creatures[id]
			local rarity = if def then rarities[def.rarity] else nil
			if rarity then
				best = math.max(best, rarity.order)
			end
			if def and def.eventId ~= nil then
				limited += 1
			end
		end
	end
	for _, set in data.snackdex.variants do
		for variant, owned in set do
			if owned then
				mutations[variant] = true
			end
		end
	end
	local mutationCount, maps, codes, tiers = 0, 0, 0, 0
	for _ in mutations do
		mutationCount += 1
	end
	local milestones: { [string]: boolean } = {}
	for key, value in data.flags do
		if not value then
			continue
		end
		if startsWith(key, AchievementRules.MAP_FLAG_PREFIX) then
			maps += 1
		elseif startsWith(key, CodeRules.FLAG_PREFIX) then
			codes += 1
		elseif startsWith(key, AchievementRules.MILESTONE_FLAG_PREFIX) then
			milestones[string.sub(key, #AchievementRules.MILESTONE_FLAG_PREFIX + 1)] = true
		end
	end
	for _, claimed in data.snackdex.tiers do
		if claimed then
			tiers += 1
		end
	end
	return {
		beltPurchases = data.stats.beltPurchases,
		steals = data.stats.steals,
		rebirths = data.rebirths,
		spins = data.spin.total,
		earned = data.stats.totalEarned,
		discovered = discovered,
		regularFound = regularFound,
		regularTotal = regularTotal,
		bestRarityOrder = best,
		mutations = mutationCount,
		maps = maps,
		stolenFrom = data.stats.timesStolenFrom,
		income = data.stats.bestCashPerSecond,
		playHours = data.stats.playTime / SECONDS_PER_HOUR,
		limited = limited,
		tiers = tiers,
		streak = data.daily.streak,
		codes = codes,
		milestones = milestones,
	}
end

-- How far `ctx` is with `def`: (progress, target). Progress never goes past the target.
function AchievementRules.progress(
	def: AchievementDef,
	ctx: Context,
	rarities: { [string]: Types.RarityDef }
): (number, number)
	local goal = def.goal
	local value: number
	local target = def.target
	if goal == "allRegular" then
		value, target = ctx.regularFound, math.max(1, ctx.regularTotal)
	elseif goal == "rarity" then
		local rarity = if def.rarity then rarities[def.rarity] else nil
		value = if rarity and ctx.bestRarityOrder >= rarity.order then 1 else 0
		target = 1
	elseif goal == "milestone" then
		value = if def.milestone and ctx.milestones[def.milestone] then 1 else 0
		target = 1
	else
		value = (ctx :: any)[goal] or 0
	end
	return math.min(value, target), target
end

function AchievementRules.isDone(def: AchievementDef, ctx: Context, rarities: { [string]: Types.RarityDef }): boolean
	local progress, target = AchievementRules.progress(def, ctx, rarities)
	return progress >= target
end

-- The achievements reached but not paid yet (no ach_<id> flag), in config order.
function AchievementRules.newlyDone(
	config: AchievementsConfig,
	ctx: Context,
	flags: { [string]: boolean },
	rarities: { [string]: Types.RarityDef }
): { AchievementDef }
	local list: { AchievementDef } = {}
	for _, def in config.list do
		if flags[AchievementRules.flagKey(def.id)] ~= true and AchievementRules.isDone(def, ctx, rarities) then
			table.insert(list, def)
		end
	end
	return list
end

-- Every achievement as the Trophies tab shows it.
function AchievementRules.view(
	config: AchievementsConfig,
	ctx: Context,
	flags: { [string]: boolean },
	rarities: { [string]: Types.RarityDef }
): { Types.AchievementView }
	local list: { Types.AchievementView } = {}
	for _, def in config.list do
		local progress, target = AchievementRules.progress(def, ctx, rarities)
		table.insert(list, {
			id = def.id,
			progress = progress,
			target = target,
			done = flags[AchievementRules.flagKey(def.id)] == true,
		})
	end
	return list
end

-- Problems with Config/Achievements (an empty list means valid). `rarities` by id, `mapCount` the number of maps,
-- `rewardProblems` checks one prize (GiftRules.rewardProblems).
function AchievementRules.validate(
	config: AchievementsConfig,
	rarities: { [string]: Types.RarityDef },
	mapCount: number,
	rewardProblems: (reward: Types.PrizeReward, name: string) -> { string }
): { string }
	local problems: { string } = {}
	local seen: { [string]: boolean } = {}
	for index, def in config.list do
		local name = `achievement {def.id}`
		if string.match(def.id, "^[%w_]+$") == nil or #def.id > 40 or seen[def.id] then
			table.insert(problems, `achievement {index} needs a unique short id`)
		end
		seen[def.id] = true
		if def.title == "" or #def.title > 24 then
			table.insert(problems, `{name} needs a title of at most 24 characters`)
		end
		if def.description == "" or #def.description > 48 then
			table.insert(problems, `{name} needs a description of at most 48 characters`)
		end
		if def.icon == "" then
			table.insert(problems, `{name} needs an icon`)
		end
		if not AchievementRules.GOALS[def.goal] then
			table.insert(problems, `{name} goal {def.goal} is not a goal`)
		end
		if not (def.target >= 1 and def.target < math.huge) then
			table.insert(problems, `{name} target must be at least 1`)
		end
		if def.goal == "rarity" and (def.rarity == nil or rarities[def.rarity] == nil) then
			table.insert(problems, `{name} needs a rarity that exists`)
		end
		if def.goal == "milestone" and (def.milestone == nil or not AchievementRules.MILESTONES[def.milestone]) then
			table.insert(problems, `{name} needs a milestone that exists`)
		end
		if def.goal == "maps" and def.target > mapCount then
			table.insert(problems, `{name} needs more maps than there are ({mapCount})`)
		end
		if def.badgeId ~= nil and not (def.badgeId > 0 and def.badgeId % 1 == 0) then
			table.insert(problems, `{name} badgeId must be a whole number`)
		end
		for _, message in rewardProblems(def.reward, name) do
			table.insert(problems, message)
		end
	end
	return problems
end

return AchievementRules
