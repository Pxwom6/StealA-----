--!strict
--[[
	The Snackdex (collection book) rules, on the saved `data.snackdex` (Types.Snackdex) and Config/Snackdex.

	* Discovery: every Snackling a player ever owns, and every (Snackling, mutation) pair, is recorded once and never
	  removed (a rebirth keeps it; ids the config no longer knows are kept, like quarantined creatures).
	* Tiers: a rarity tier is complete when every REGULAR Snackling of it (no `eventId`) has been owned. Event
	  Snacklings are their own "Event" section and never block a tier. Everything is read from the creature list, so
	  adding Snacklings to the config needs no change here (a tier completed earlier keeps its reward and bonus).
	* Rewards: completing a tier pays a one-time cash reward (tierReward, sized from steady income like a cash pack)
	  and adds a permanent income bonus (incomeBonus, capped). `claimTier` sets the tier's flag before the caller pays,
	  so a tier can only ever pay once per account.

	Pure: no Roblox APIs.
]]

local Types = require("../Types")
local EconomyMath = require("./EconomyMath")

export type Snackdex = Types.Snackdex
export type Config = Types.SnackdexConfig
export type CreatureDef = Types.CreatureDef
export type RarityDef = Types.RarityDef

-- A rarity tier's collection: how many of its regular Snacklings were owned, of how many.
export type TierProgress = {
	rarity: string,
	found: number,
	total: number,
	complete: boolean, -- found == total (and the tier has any)
	claimed: boolean, -- its reward was paid (stays true even if Snacklings are added to the tier later)
}

local SnackdexRules = {}

-- The id of the "Event" section (never a rarity id: CI checks no rarity uses it).
SnackdexRules.EVENT_SECTION = "Event"

function SnackdexRules.empty(): Snackdex
	return { creatures = {}, variants = {}, tiers = {} }
end

-- Whether a creature counts towards its rarity tier (event Snacklings have their own section).
function SnackdexRules.isRegular(def: CreatureDef): boolean
	return def.eventId == nil
end

function SnackdexRules.hasCreature(dex: Snackdex, creatureId: string): boolean
	return dex.creatures[creatureId] == true
end

function SnackdexRules.hasVariant(dex: Snackdex, creatureId: string, variant: string): boolean
	local set = dex.variants[creatureId]
	return set ~= nil and set[variant] == true
end

-- Records that the player owns `creatureId` with mutation `variant` (nil = plain). Returns whether the Snackling and
-- the (Snackling, mutation) pair were new.
function SnackdexRules.discover(dex: Snackdex, creatureId: string, variant: string?): (boolean, boolean)
	if creatureId == "" then
		return false, false
	end
	local newCreature = dex.creatures[creatureId] ~= true
	dex.creatures[creatureId] = true
	local newVariant = false
	if variant ~= nil and variant ~= "" then
		local set = dex.variants[creatureId]
		if set == nil then
			local created: { [string]: boolean } = {}
			dex.variants[creatureId] = created
			set = created
		end
		local variants = set :: { [string]: boolean }
		newVariant = variants[variant] ~= true
		variants[variant] = true
	end
	return newCreature, newVariant
end

-- The regular Snacklings of each tier, in config order, by rarity id.
local function regularByRarity(creatures: { CreatureDef }): { [string]: { CreatureDef } }
	local byRarity: { [string]: { CreatureDef } } = {}
	for _, def in creatures do
		if SnackdexRules.isRegular(def) then
			local list = byRarity[def.rarity]
			if list == nil then
				local created: { CreatureDef } = {}
				byRarity[def.rarity] = created
				list = created
			end
			table.insert(list :: { CreatureDef }, def)
		end
	end
	return byRarity
end

-- The Snacklings listed in a section: a rarity tier's regular ones, or every event one (SnackdexRules.EVENT_SECTION),
-- in config order.
function SnackdexRules.section(creatures: { CreatureDef }, sectionId: string): { CreatureDef }
	local list: { CreatureDef } = {}
	for _, def in creatures do
		local inSection = if sectionId == SnackdexRules.EVENT_SECTION
			then not SnackdexRules.isRegular(def)
			else SnackdexRules.isRegular(def) and def.rarity == sectionId
		if inSection then
			table.insert(list, def)
		end
	end
	return list
end

-- How many of `list` the player has owned.
function SnackdexRules.countFound(dex: Snackdex, list: { CreatureDef }): number
	local found = 0
	for _, def in list do
		if dex.creatures[def.id] == true then
			found += 1
		end
	end
	return found
end

-- Every rarity tier's collection, in rarity order (`rarities` sorted by order, e.g. Catalog.rarityList).
function SnackdexRules.tierProgress(
	dex: Snackdex,
	creatures: { CreatureDef },
	rarities: { RarityDef }
): { TierProgress }
	local byRarity = regularByRarity(creatures)
	local result: { TierProgress } = {}
	for _, rarity in rarities do
		local list = byRarity[rarity.id] or {}
		local found = SnackdexRules.countFound(dex, list)
		table.insert(result, {
			rarity = rarity.id,
			found = found,
			total = #list,
			complete = #list > 0 and found == #list,
			claimed = dex.tiers[rarity.id] == true,
		})
	end
	return result
end

-- Rarity ids (in rarity order) whose tier is complete but whose reward hasn't been paid yet.
function SnackdexRules.completedUnclaimed(
	dex: Snackdex,
	creatures: { CreatureDef },
	rarities: { RarityDef }
): { string }
	local due: { string } = {}
	for _, tier in SnackdexRules.tierProgress(dex, creatures, rarities) do
		if tier.complete and not tier.claimed then
			table.insert(due, tier.rarity)
		end
	end
	return due
end

-- Marks a tier's reward as paid. Returns true the first time only: pay the reward then, with no yield in between.
function SnackdexRules.claimTier(dex: Snackdex, rarityId: string): boolean
	if dex.tiers[rarityId] == true then
		return false
	end
	dex.tiers[rarityId] = true
	return true
end

-- The permanent collection bonus (0.06 = +6% income): incomeBonusPerTier for every tier whose reward was paid, capped.
function SnackdexRules.incomeBonus(dex: Snackdex, cfg: Config): number
	local tiers = 0
	for _, claimed in dex.tiers do
		if claimed then
			tiers += 1
		end
	end
	return math.clamp(tiers * math.max(0, cfg.incomeBonusPerTier), 0, math.max(0, cfg.maxIncomeBonus))
end

-- The tier's reward settings (its own, or the default).
function SnackdexRules.rewardFor(rarityId: string, cfg: Config): Types.IncomeReward
	return cfg.tierRewards[rarityId] or cfg.defaultTierReward
end

-- Cash for completing a tier: `incomeSeconds` of steady income (EconomyMath.packIncome), at least the minimum.
function SnackdexRules.tierReward(rarityId: string, steadyIncome: number, cfg: Config): number
	return EconomyMath.cashPackAmount(steadyIncome, SnackdexRules.rewardFor(rarityId, cfg))
end

local function sortedKeys(set: { [string]: boolean }): { string }
	local keys: { string } = {}
	for key, value in set do
		if value then
			table.insert(keys, key)
		end
	end
	table.sort(keys)
	return keys
end

-- What the client gets (SnackdexSync): sorted id lists and the bonus.
function SnackdexRules.view(dex: Snackdex, cfg: Config): Types.SnackdexView
	local variants: { [string]: { string } } = {}
	for creatureId, set in dex.variants do
		local list = sortedKeys(set)
		if #list > 0 then
			variants[creatureId] = list
		end
	end
	return {
		creatures = sortedKeys(dex.creatures),
		variants = variants,
		tiers = sortedKeys(dex.tiers),
		incomeBonus = SnackdexRules.incomeBonus(dex, cfg),
	}
end

-- Studio testing (/dex fill): marks every regular Snackling of a tier discovered except one, and clears the tier's
-- reward flag so completing it pays again. Leaves out the first one (config order) the player doesn't own right now
-- (`owned`), else the last one. Returns the creature left out, or nil when the tier has no Snacklings.
function SnackdexRules.devFill(
	dex: Snackdex,
	creatures: { CreatureDef },
	rarityId: string,
	owned: { [string]: boolean }
): CreatureDef?
	local list = SnackdexRules.section(creatures, rarityId)
	if #list == 0 then
		return nil
	end
	local leftOut = list[#list]
	for _, def in list do
		if not owned[def.id] then
			leftOut = def
			break
		end
	end
	for _, def in list do
		if def ~= leftOut then
			dex.creatures[def.id] = true
		end
	end
	dex.creatures[leftOut.id] = nil
	dex.variants[leftOut.id] = nil
	dex.tiers[rarityId] = nil
	return leftOut
end

-- Problems with Config/Snackdex (an empty list means valid).
function SnackdexRules.validate(cfg: Config, rarities: { RarityDef }): { string }
	local problems: { string } = {}
	local function problem(message: string)
		table.insert(problems, message)
	end
	local function checkReward(name: string, reward: Types.IncomeReward)
		if not (reward.incomeSeconds >= 0 and reward.incomeSeconds < math.huge) then
			problem(`{name}: incomeSeconds must be a number >= 0`)
		end
		if not (reward.minimum >= 1 and reward.minimum < math.huge) then
			problem(`{name}: minimum must be at least 1`)
		end
	end
	if not (cfg.incomeBonusPerTier >= 0 and cfg.incomeBonusPerTier <= 1) then
		problem("incomeBonusPerTier must be between 0 and 1")
	end
	if not (cfg.maxIncomeBonus >= 0 and cfg.maxIncomeBonus <= 1) then
		problem("maxIncomeBonus must be between 0 and 1")
	end
	local rarityIds: { [string]: boolean } = {}
	for _, rarity in rarities do
		rarityIds[rarity.id] = true
		if rarity.id == SnackdexRules.EVENT_SECTION then
			problem(`rarity id {rarity.id} clashes with the Snackdex event section`)
		end
	end
	for rarityId, reward in cfg.tierRewards do
		if not rarityIds[rarityId] then
			problem(`tierRewards has unknown rarity {rarityId}`)
		end
		checkReward(`tierRewards.{rarityId}`, reward)
	end
	checkReward("defaultTierReward", cfg.defaultTierReward)
	return problems
end

return SnackdexRules
