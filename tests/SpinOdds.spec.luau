--!strict
-- The Lucky Spin's complete odds (Logic/SpinOdds): every outcome of one spin with its exact chance, the disclosure
-- Roblox's Paid Random Items policy asks of the paid Lucky Spin packs, and the same whatever is live.
local T = require("./TestKit")
local Catalog = require("../src/shared/Logic/Catalog")
local Creatures = require("../src/shared/Config/Creatures")
local Mutations = require("../src/shared/Config/Mutations")
local Rarities = require("../src/shared/Config/Rarities")
local Spin = require("../src/shared/Config/Spin")
local RarityRoll = require("../src/shared/Logic/RarityRoll")
local SpinOdds = require("../src/shared/Logic/SpinOdds")
local SpinRules = require("../src/shared/Logic/SpinRules")
local Types = require("../src/shared/Types")

local catalog = Catalog.build(Creatures, Rarities, Mutations)
local rarities, creatures = catalog.rarityList, catalog.creatureList

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

local function permanentCount(): number
	local count = 0
	for _, creature in creatures do
		if creature.eventId == nil and creature.beltWeight > 0 then
			count += 1
		end
	end
	return count
end

T.describe("SpinOdds: every outcome of one spin", function()
	local outcomes = SpinOdds.outcomes(Spin, rarities, creatures)
	local chances = SpinRules.chances(Spin.segments)

	T.it("adds up to exactly 100%, every outcome possible", function()
		local total = 0
		for _, outcome in outcomes do
			T.expect(outcome.chance).toBeGreaterThan(0)
			total += outcome.chance
		end
		T.expect(total).toBeNear(1, 1e-12)
	end)

	T.it("lists a cash prize once, at its reel chance, and a Snackling prize as one outcome per Snackling", function()
		local bySegment: { [string]: { SpinOdds.Outcome } } = {}
		for _, outcome in outcomes do
			bySegment[outcome.segment] = bySegment[outcome.segment] or {}
			table.insert(bySegment[outcome.segment], outcome)
		end
		local snacklingPrizes = 0
		for index, segment in Spin.segments do
			local list: { SpinOdds.Outcome } = bySegment[segment.id] or {}
			local total = 0
			for _, outcome in list do
				total += outcome.chance
			end
			T.expect(total).toBeNear(chances[index], 1e-12)
			if segment.reward.kind == "creature" then
				snacklingPrizes += 1
				T.expect(#list).toBe(permanentCount())
			else
				T.expect(#list).toBe(1)
				T.expect(list[1].creatureId).toBeNil()
			end
		end
		T.expect(snacklingPrizes).toBe(3) -- 🎁 Snackling, ✨ Golden!, 💎 Diamond!
	end)

	T.it("never gives an event Snackling, and only its segment's own mutation (none for the plain prize)", function()
		for _, outcome in outcomes do
			local creatureId = outcome.creatureId
			if creatureId then
				T.expect(catalog.creatures[creatureId].eventId).toBeNil()
				local segment = nil
				for _, candidate in Spin.segments do
					if candidate.id == outcome.segment then
						segment = candidate
					end
				end
				local reward = (segment :: Types.SpinSegment).reward :: any
				T.expect(outcome.variant).toBe(reward.mutation)
			end
		end
	end)

	T.it("is the reel chance times the roll the server makes: the segment's luck, no events", function()
		for index, segment in Spin.segments do
			local reward = segment.reward :: any
			if reward.kind == "creature" then
				local byId = RarityRoll.creatureOdds(rarities, creatures, reward.luck, {})
				for _, outcome in outcomes do
					if outcome.segment == segment.id and outcome.creatureId then
						T.expect(outcome.chance).toBeNear(chances[index] * byId[outcome.creatureId], 1e-15)
					end
				end
			end
		end
	end)

	T.it("matches what the server's fixed roll draws (RarityRoll.roll, the segment's luck, no events)", function()
		local rng = T.seededRandom(2027)
		local counts: { [string]: number } = {}
		local n = 200000
		for _ = 1, n do
			local id = RarityRoll.roll(rarities, creatures, 2, SpinOdds.NO_EVENTS, rng) :: string
			counts[id] = (counts[id] or 0) + 1
		end
		local byId = SpinOdds.creatureChances(2, rarities, creatures)
		for _, creature in creatures do
			local expected = byId[creature.id] or 0
			T.expect((counts[creature.id] or 0) / n).toBeNear(expected, 0.003)
			if creature.eventId then
				T.expect(counts[creature.id]).toBeNil()
			end
		end
	end)
end)

T.describe("SpinOdds.table: the Details list", function()
	local odds = SpinOdds.table(Spin, rarities, creatures)

	T.it("has every reel segment in order, and a column per Snackling prize", function()
		T.expect(#odds.segments).toBe(#Spin.segments)
		local total = 0
		for index, row in odds.segments do
			T.expect(row.segment.id).toBe(Spin.segments[index].id)
			total += row.chance
		end
		T.expect(total).toBeNear(1, 1e-12)
		local ids: { string } = {}
		for _, segment in odds.columns do
			table.insert(ids, segment.id)
		end
		T.expect(table.concat(ids, ",")).toBe("snackling,golden,diamond")
	end)

	T.it("adds every tier up from its Snacklings, and every prize to 100%", function()
		local total = 0
		for _, row in odds.segments do
			if row.segment.reward.kind ~= "creature" then
				total += row.chance
			end
		end
		local seen = 0
		local order = 0
		for _, tier in odds.tiers do
			T.expect(catalog.rarities[tier.rarity].order).toBeGreaterThan(order) -- in rarity order
			order = catalog.rarities[tier.rarity].order
			for column = 1, #odds.columns do
				local sum = 0
				for _, creature in tier.creatures do
					T.expect(creature.rarity).toBe(tier.rarity)
					sum += creature.chances[column]
				end
				T.expect(tier.chances[column]).toBeNear(sum, 1e-15)
				total += tier.chances[column]
			end
			seen += #tier.creatures
		end
		T.expect(total).toBeNear(1, 1e-12)
		T.expect(seen).toBe(permanentCount()) -- every permanent Snackling once
		T.expect(#odds.tiers).toBe(#rarities)
	end)
end)

T.describe("SpinOdds: the odds stay fixed", function()
	T.it("the real config gives Snackling prizes only permanent mutations", function()
		for _, segment in Spin.segments do
			local reward = segment.reward :: any
			if reward.kind == "creature" and reward.mutation then
				local mutation = catalog.mutations[reward.mutation]
				T.expect(mutation.eventId == nil and mutation.mapTheme == nil and mutation.modifierId == nil).toBe(true)
			end
		end
		T.expect(#SpinRules.validate(Spin, catalog.mutations)).toBe(0)
	end)

	T.it("refuses a Snackling prize with an event's, a map's or a weather's mutation", function()
		local gated: { string } = {}
		for _, mutation in catalog.mutationList do
			if mutation.eventId or mutation.mapTheme or mutation.modifierId then
				table.insert(gated, mutation.id)
			end
		end
		T.expect(#gated).toBeGreaterThan(2)
		for _, id in gated do
			local config = copy(Spin)
			config.segments[5].reward.mutation = id -- Golden!'s
			T.expect(#SpinRules.validate(config :: Types.SpinConfig, catalog.mutations)).toBe(1)
		end
	end)
end)

return nil
