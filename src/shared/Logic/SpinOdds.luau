--!strict
--[[
	The Lucky Spin's complete odds (Config/Spin), the disclosure Roblox's Paid Random Items policy asks of the paid Lucky
	Spin packs: every final outcome of one spin with its exact chance, adding up to 100%.

	A spin's prizes never depend on anything live, so these numbers are always the ones the server rolls with, and they
	never change while someone reads them: a Snackling prize is a permanent Snackling (never an event one) rolled at its
	segment's own `luck` (no server, event, admin or modifier luck), plain or always its segment's `mutation` (no
	mutation roll). The server rolls it with RarityRoll.roll on exactly these arguments (PrizeService.rollFixed); this
	module works out the same weights with RarityRoll.creatureOdds.

	The Spin tab's Odds view and each pack's Shop card show the reel's chances (SpinRules.chances), and their Details
	list shows everything here (UI/OddsDetails, laid out by StoreLayout.oddsDetails).

	Pure: no Roblox APIs.
]]

local RarityRoll = require("./RarityRoll")
local SpinRules = require("./SpinRules")
local Types = require("../Types")

type RarityDef = Types.RarityDef
type CreatureDef = Types.CreatureDef
type SpinConfig = Types.SpinConfig
type SpinSegment = Types.SpinSegment

local SpinOdds = {}

-- The events a spin's Snackling prize rolls with: none, so only permanent Snacklings can come.
SpinOdds.NO_EVENTS = table.freeze({}) :: { [string]: boolean }

export type Outcome = {
	segment: string, -- the reel segment's id
	creatureId: string?, -- for a Snackling prize: which one
	variant: string?, -- its mutation (nil: plain)
	chance: number, -- on one spin
}

-- Each creature id's chance once a Snackling segment of `luck` has won (they add up to 1).
function SpinOdds.creatureChances(
	luck: number,
	rarities: { RarityDef },
	creatures: { CreatureDef }
): { [string]: number }
	return RarityRoll.creatureOdds(rarities, creatures, luck, SpinOdds.NO_EVENTS)
end

-- Every final outcome of one spin, in reel order: a cash segment as one outcome, a Snackling segment as one outcome
-- per Snackling it can give (in catalogue order). The chances add up to 1.
function SpinOdds.outcomes(config: SpinConfig, rarities: { RarityDef }, creatures: { CreatureDef }): { Outcome }
	local list: { Outcome } = {}
	local chances = SpinRules.chances(config.segments)
	for index, segment in config.segments do
		local reward = segment.reward
		if reward.kind == "creature" then
			local byId = SpinOdds.creatureChances(reward.luck, rarities, creatures)
			for _, creature in creatures do
				local chance = byId[creature.id]
				if chance then
					table.insert(list, {
						segment = segment.id,
						creatureId = creature.id,
						variant = reward.mutation,
						chance = chances[index] * chance,
					})
				end
			end
		else
			table.insert(list, { segment = segment.id, chance = chances[index] })
		end
	end
	return list
end

export type SegmentRow = { segment: SpinSegment, chance: number }
-- A rarity tier, or one Snackling: one chance per Snackling segment (`columns`), each the chance of getting exactly
-- that prize (that Snackling, plain or with the segment's mutation) on one spin.
export type CreatureRow = { id: string, rarity: string, chances: { number } }
export type TierRow = { rarity: string, chances: { number }, creatures: { CreatureRow } }
export type Table = {
	segments: { SegmentRow }, -- every reel segment with its chance, in reel order (they add up to 1)
	columns: { SpinSegment }, -- the Snackling segments, in reel order
	tiers: { TierRow }, -- in rarity order, each with its Snacklings in catalogue order
}

-- What the Details list shows: the reel's segments, then each rarity tier and each Snackling with its chance under
-- each Snackling segment. Every number in `tiers` is a share of the whole spin, so the cash segments' chances and
-- every Snackling's add up to 1.
function SpinOdds.table(config: SpinConfig, rarities: { RarityDef }, creatures: { CreatureDef }): Table
	local chances = SpinRules.chances(config.segments)
	local result: Table = { segments = {}, columns = {}, tiers = {} }
	local columnOdds: { { [string]: number } } = {}
	local columnChance: { number } = {}
	for index, segment in config.segments do
		table.insert(result.segments, { segment = segment, chance = chances[index] })
		local reward = segment.reward
		if reward.kind == "creature" then
			table.insert(result.columns, segment)
			table.insert(columnOdds, SpinOdds.creatureChances(reward.luck, rarities, creatures))
			table.insert(columnChance, chances[index])
		end
	end
	for _, rarity in rarities do
		local tier: TierRow = { rarity = rarity.id, chances = table.create(#result.columns, 0), creatures = {} }
		for _, creature in creatures do
			if creature.rarity == rarity.id then
				local row: CreatureRow = { id = creature.id, rarity = rarity.id, chances = {} }
				local any = false
				for column, odds in columnOdds do
					local chance = (odds[creature.id] or 0) * columnChance[column]
					any = any or chance > 0
					row.chances[column] = chance
					tier.chances[column] += chance
				end
				if any then
					table.insert(tier.creatures, row)
				end
			end
		end
		if #tier.creatures > 0 then
			table.insert(result.tiers, tier)
		end
	end
	return result
end

return SpinOdds
