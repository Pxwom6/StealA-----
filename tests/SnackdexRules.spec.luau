--!strict
local T = require("./TestKit")
local Fixtures = require("./Fixtures")
local SnackdexRules = require("../src/shared/Logic/SnackdexRules")
local Types = require("../src/shared/Types")

local rarities: { Types.RarityDef } = {
	Fixtures.rarity("Common", 1, 100, false),
	Fixtures.rarity("Rare", 2, 10, true),
	Fixtures.rarity("Secret", 3, 1, true),
}

local creatures: { Types.CreatureDef } = {
	Fixtures.creature("pup", "Common", 1),
	Fixtures.creature("pal", "Common", 1),
	Fixtures.creature("bear", "Rare", 1),
	Fixtures.creature("cat", "Rare", 1, "Halloween"), -- event: its own section, never blocks Rare
	Fixtures.creature("kraken", "Secret", 1),
}

local cfg: Types.SnackdexConfig = {
	incomeBonusPerTier = 0.03,
	maxIncomeBonus = 0.05,
	tierRewards = {
		Common = { incomeSeconds = 60, minimum = 250 },
		Rare = { incomeSeconds = 600, minimum = 10000 },
	},
	defaultTierReward = { incomeSeconds = 120, minimum = 1000 },
}

local function tier(progress: { SnackdexRules.TierProgress }, rarity: string): SnackdexRules.TierProgress
	for _, entry in progress do
		if entry.rarity == rarity then
			return entry
		end
	end
	error(`no tier {rarity}`)
end

T.describe("SnackdexRules discovery", function()
	T.it("records a Snackling and each mutation once", function()
		local dex = SnackdexRules.empty()
		T.expect({ SnackdexRules.discover(dex, "pup", nil) }).toEqual({ true, false })
		T.expect({ SnackdexRules.discover(dex, "pup", nil) }).toEqual({ false, false })
		T.expect({ SnackdexRules.discover(dex, "pup", "golden") }).toEqual({ false, true })
		T.expect({ SnackdexRules.discover(dex, "pup", "golden") }).toEqual({ false, false })
		-- A new Snackling that is already mutated is new twice over.
		T.expect({ SnackdexRules.discover(dex, "bear", "rainbow") }).toEqual({ true, true })
		T.expect(SnackdexRules.hasCreature(dex, "bear")).toBe(true)
		T.expect(SnackdexRules.hasVariant(dex, "bear", "rainbow")).toBe(true)
		T.expect(SnackdexRules.hasVariant(dex, "bear", "golden")).toBe(false)
		T.expect(SnackdexRules.hasVariant(dex, "pal", "golden")).toBe(false)
		-- An empty variant is a plain Snackling; an empty id is nothing.
		T.expect({ SnackdexRules.discover(dex, "pal", "") }).toEqual({ true, false })
		T.expect({ SnackdexRules.discover(dex, "", "golden") }).toEqual({ false, false })
		T.expect(dex.creatures[""]).toBeNil()
	end)

	T.it("keeps ids the config doesn't know (they may come back)", function()
		local dex = SnackdexRules.empty()
		SnackdexRules.discover(dex, "retired_pup", "old_mutation")
		local view = SnackdexRules.view(dex, cfg)
		T.expect(view.creatures).toEqual({ "retired_pup" })
		T.expect(view.variants).toEqual({ retired_pup = { "old_mutation" } })
	end)
end)

T.describe("SnackdexRules tiers", function()
	T.it("a tier is complete when every regular Snackling of it was owned; event ones never count", function()
		local dex = SnackdexRules.empty()
		SnackdexRules.discover(dex, "pup", nil)
		local progress = SnackdexRules.tierProgress(dex, creatures, rarities)
		T.expect(#progress).toBe(3)
		T.expect(progress[1].rarity).toBe("Common") -- rarity order
		T.expect(tier(progress, "Common")).toEqual({
			rarity = "Common",
			found = 1,
			total = 2,
			complete = false,
			claimed = false,
		})
		-- Rare has one regular Snackling (the event cat is not part of the tier).
		T.expect(tier(progress, "Rare").total).toBe(1)
		SnackdexRules.discover(dex, "cat", nil)
		T.expect(tier(SnackdexRules.tierProgress(dex, creatures, rarities), "Rare").found).toBe(0)
		SnackdexRules.discover(dex, "bear", nil)
		SnackdexRules.discover(dex, "pal", "golden")
		progress = SnackdexRules.tierProgress(dex, creatures, rarities)
		T.expect(tier(progress, "Common").complete).toBe(true)
		T.expect(tier(progress, "Rare").complete).toBe(true)
		T.expect(tier(progress, "Secret").complete).toBe(false)
		T.expect(SnackdexRules.completedUnclaimed(dex, creatures, rarities)).toEqual({ "Common", "Rare" })
	end)

	T.it("an event Snackling never blocks its tier, even undiscovered", function()
		local dex = SnackdexRules.empty()
		SnackdexRules.discover(dex, "bear", nil)
		T.expect(SnackdexRules.completedUnclaimed(dex, creatures, rarities)).toEqual({ "Rare" })
	end)

	T.it("lists sections from the config: tiers hold regular Snacklings, Event holds every event one", function()
		local function ids(list: { Types.CreatureDef }): { string }
			local result: { string } = {}
			for _, def in list do
				table.insert(result, def.id)
			end
			return result
		end
		T.expect(ids(SnackdexRules.section(creatures, "Common"))).toEqual({ "pup", "pal" })
		T.expect(ids(SnackdexRules.section(creatures, "Rare"))).toEqual({ "bear" })
		T.expect(ids(SnackdexRules.section(creatures, SnackdexRules.EVENT_SECTION))).toEqual({ "cat" })
		local dex = SnackdexRules.empty()
		SnackdexRules.discover(dex, "cat", nil)
		T.expect(SnackdexRules.countFound(dex, SnackdexRules.section(creatures, SnackdexRules.EVENT_SECTION))).toBe(1)
	end)

	T.it("a tier with no regular Snacklings is never complete", function()
		local onlyEvent = { Fixtures.creature("ghost", "Common", 1, "Halloween") }
		local progress = SnackdexRules.tierProgress(SnackdexRules.empty(), onlyEvent, rarities)
		T.expect(tier(progress, "Common").complete).toBe(false)
		T.expect(tier(progress, "Common").total).toBe(0)
	end)

	T.it("pays a tier once: claimTier is true the first time only, and the tier stays claimed", function()
		local dex = SnackdexRules.empty()
		SnackdexRules.discover(dex, "pup", nil)
		SnackdexRules.discover(dex, "pal", nil)
		T.expect(SnackdexRules.claimTier(dex, "Common")).toBe(true)
		T.expect(SnackdexRules.claimTier(dex, "Common")).toBe(false)
		T.expect(SnackdexRules.completedUnclaimed(dex, creatures, rarities)).toEqual({})
		-- New Snacklings added to the tier later: the tier is incomplete again but keeps its reward (no second one).
		local grown = table.clone(creatures)
		table.insert(grown, Fixtures.creature("newbie", "Common", 1))
		local progress = SnackdexRules.tierProgress(dex, grown, rarities)
		T.expect(tier(progress, "Common").complete).toBe(false)
		T.expect(tier(progress, "Common").claimed).toBe(true)
		SnackdexRules.discover(dex, "newbie", nil)
		T.expect(SnackdexRules.completedUnclaimed(dex, grown, rarities)).toEqual({})
	end)
end)

T.describe("SnackdexRules rewards", function()
	T.it("the income bonus grows per completed tier and is capped", function()
		local dex = SnackdexRules.empty()
		T.expect(SnackdexRules.incomeBonus(dex, cfg)).toBe(0)
		SnackdexRules.claimTier(dex, "Common")
		T.expect(SnackdexRules.incomeBonus(dex, cfg)).toBeNear(0.03)
		SnackdexRules.claimTier(dex, "Rare")
		T.expect(SnackdexRules.incomeBonus(dex, cfg)).toBeNear(0.05) -- 0.06 capped at 0.05
		SnackdexRules.claimTier(dex, "Secret")
		T.expect(SnackdexRules.incomeBonus(dex, cfg)).toBeNear(0.05)
	end)

	T.it("tier rewards are sized from steady income like cash packs, with the tier's minimum", function()
		T.expect(SnackdexRules.tierReward("Common", 0, cfg)).toBe(250)
		T.expect(SnackdexRules.tierReward("Common", 100, cfg)).toBe(6000) -- 60 s x $100/s
		T.expect(SnackdexRules.tierReward("Rare", 10, cfg)).toBe(10000) -- 6,000 < minimum
		T.expect(SnackdexRules.tierReward("Rare", 1234, cfg)).toBe(740000) -- 740,400 rounded to 2 digits
		-- A rarity without its own entry uses the default; NaN income pays the minimum.
		T.expect(SnackdexRules.tierReward("Secret", 50, cfg)).toBe(6000)
		T.expect(SnackdexRules.tierReward("Secret", 0 / 0, cfg)).toBe(1000)
	end)

	T.it("the client view lists sorted ids and the bonus", function()
		local dex = SnackdexRules.empty()
		SnackdexRules.discover(dex, "pal", "rainbow")
		SnackdexRules.discover(dex, "pup", "golden")
		SnackdexRules.discover(dex, "pal", "golden")
		SnackdexRules.claimTier(dex, "Common")
		T.expect(SnackdexRules.view(dex, cfg)).toEqual({
			creatures = { "pal", "pup" },
			variants = { pal = { "golden", "rainbow" }, pup = { "golden" } },
			tiers = { "Common" },
			incomeBonus = 0.03,
		})
	end)
end)

T.describe("SnackdexRules dev fill", function()
	T.it("marks every regular Snackling of a tier but one, and clears the tier's reward flag", function()
		local dex = SnackdexRules.empty()
		SnackdexRules.discover(dex, "pal", "golden")
		SnackdexRules.claimTier(dex, "Common")
		local leftOut = SnackdexRules.devFill(dex, creatures, "Common", { pup = true })
		T.expect(leftOut and leftOut.id).toBe("pal") -- the first one not owned right now
		T.expect(dex.creatures.pup).toBe(true)
		T.expect(dex.creatures.pal).toBeNil()
		T.expect(dex.variants.pal).toBeNil()
		T.expect(dex.tiers.Common).toBeNil()
		SnackdexRules.discover(dex, "pal", nil)
		T.expect(SnackdexRules.completedUnclaimed(dex, creatures, rarities)).toEqual({ "Common" })
		-- Everything owned: the last one is left out. Unknown tier: nothing.
		local all = SnackdexRules.devFill(SnackdexRules.empty(), creatures, "Common", { pup = true, pal = true })
		T.expect(all and all.id).toBe("pal")
		T.expect(SnackdexRules.devFill(SnackdexRules.empty(), creatures, "Mythic", {})).toBeNil()
	end)
end)

T.describe("SnackdexRules config validation", function()
	T.it("accepts a valid config and reports bad ones", function()
		T.expect(SnackdexRules.validate(cfg, rarities)).toEqual({})
		local bad: Types.SnackdexConfig = {
			incomeBonusPerTier = -1,
			maxIncomeBonus = 2,
			tierRewards = { Nope = { incomeSeconds = -5, minimum = 0 } },
			defaultTierReward = { incomeSeconds = 0 / 0, minimum = 1 },
		}
		T.expect(#SnackdexRules.validate(bad, rarities)).toBe(6)
		local clash = table.clone(rarities)
		table.insert(clash, Fixtures.rarity(SnackdexRules.EVENT_SECTION, 9, 1, true))
		T.expect(#SnackdexRules.validate(cfg, clash)).toBe(1)
	end)
end)

return nil
