--!strict
local T = require("./TestKit")
local RarityRoll = require("../src/shared/Logic/RarityRoll")
local F = require("./Fixtures")

local rarities = {
	F.rarity("Common", 1, 90, false),
	F.rarity("Rare", 2, 9, true),
	F.rarity("Mythic", 3, 1, true),
}
local creatures = {
	F.creature("a", "Common", 3),
	F.creature("b", "Common", 1),
	F.creature("r", "Rare", 1),
	F.creature("m", "Mythic", 1),
	F.creature("e", "Mythic", 1000, "Halloween"),
}

T.describe("RarityRoll.pickWeighted", function()
	T.it("maps r across cumulative weights", function()
		local items = { { n = "x", w = 1 }, { n = "y", w = 3 } }
		local function w(item: { n: string, w: number }): number
			return item.w
		end
		T.expect((RarityRoll.pickWeighted(items, w, 0) :: any).n).toBe("x")
		T.expect((RarityRoll.pickWeighted(items, w, 0.24) :: any).n).toBe("x")
		T.expect((RarityRoll.pickWeighted(items, w, 0.26) :: any).n).toBe("y")
		T.expect((RarityRoll.pickWeighted(items, w, 0.9999999) :: any).n).toBe("y")
	end)
	T.it("never picks zero-weight items and returns nil for an empty pool", function()
		local items = { { n = "zero", w = 0 }, { n = "one", w = 1 } }
		local function w(item: { n: string, w: number }): number
			return item.w
		end
		T.expect((RarityRoll.pickWeighted(items, w, 0) :: any).n).toBe("one")
		T.expect(RarityRoll.pickWeighted({}, w, 0.5)).toBeNil()
	end)
	T.it("clamps out-of-range r", function()
		local items = { { n = "x", w = 1 } }
		local function w(item: { n: string, w: number }): number
			return item.w
		end
		T.expect((RarityRoll.pickWeighted(items, w, 1.5) :: any).n).toBe("x")
		T.expect((RarityRoll.pickWeighted(items, w, -1) :: any).n).toBe("x")
	end)
end)

T.describe("RarityRoll.odds", function()
	T.it("reports exact base odds", function()
		local odds = RarityRoll.odds(rarities, creatures, 1, {})
		T.expect(odds[1].chance).toBeNear(0.9)
		T.expect(odds[2].chance).toBeNear(0.09)
		T.expect(odds[3].chance).toBeNear(0.01)
	end)
	T.it("luck multiplies only luck-affected tiers", function()
		local odds = RarityRoll.odds(rarities, creatures, 2, {})
		-- weights 90, 18, 2 → total 110
		T.expect(odds[1].chance).toBeNear(90 / 110)
		T.expect(odds[2].chance).toBeNear(18 / 110)
		T.expect(odds[3].chance).toBeNear(2 / 110)
	end)
	T.it("treats invalid luck as 1", function()
		local odds = RarityRoll.odds(rarities, creatures, 0 / 0, {})
		T.expect(odds[3].chance).toBeNear(0.01)
	end)
	T.it("skips tiers that have no eligible creature", function()
		local onlyEvent = {
			F.creature("a", "Common", 1),
			F.creature("e", "Mythic", 1, "Halloween"),
		}
		local odds = RarityRoll.odds(rarities, onlyEvent, 1, {})
		T.expect(odds[1].chance).toBeNear(1)
		T.expect(odds[3].chance).toBe(0)
	end)
end)

T.describe("RarityRoll.roll", function()
	T.it("matches configured odds over many rolls", function()
		local rng = T.seededRandom(42)
		local counts: { [string]: number } = {}
		local n = 200000
		for _ = 1, n do
			local id = RarityRoll.roll(rarities, creatures, 1, {}, rng) :: string
			counts[id] = (counts[id] or 0) + 1
		end
		-- Common split 3:1 between a and b
		T.expect((counts.a or 0) / n).toBeNear(0.9 * 0.75, 0.01)
		T.expect((counts.b or 0) / n).toBeNear(0.9 * 0.25, 0.01)
		T.expect((counts.r or 0) / n).toBeNear(0.09, 0.005)
		T.expect((counts.m or 0) / n).toBeNear(0.01, 0.002)
		T.expect(counts.e).toBeNil()
	end)
	T.it("event creatures only appear while their event is active", function()
		local rng = T.seededRandom(7)
		local sawEvent = false
		for _ = 1, 20000 do
			if RarityRoll.roll(rarities, creatures, 1, { Halloween = true }, rng) == "e" then
				sawEvent = true
				break
			end
		end
		T.expect(sawEvent).toBe(true)
	end)
	T.it("returns nil when nothing is eligible", function()
		T.expect(RarityRoll.roll(rarities, {}, 1, {}, T.seededRandom(1))).toBeNil()
	end)
end)

T.describe("RarityRoll.creatureOdds", function()
	T.it("gives each creature its tier's chance times its share of the tier, adding up to 1", function()
		local odds = RarityRoll.creatureOdds(rarities, creatures, 1, {})
		T.expect(odds.a).toBeNear(0.9 * 0.75, 1e-12)
		T.expect(odds.b).toBeNear(0.9 * 0.25, 1e-12)
		T.expect(odds.r).toBeNear(0.09, 1e-12)
		T.expect(odds.m).toBeNear(0.01, 1e-12)
		T.expect(odds.e).toBeNil() -- its event isn't on
		local total = 0
		for _, chance in odds do
			total += chance
		end
		T.expect(total).toBeNear(1, 1e-12)
	end)

	T.it("follows luck and events exactly as RarityRoll.odds does", function()
		local odds = RarityRoll.creatureOdds(rarities, creatures, 4, { Halloween = true })
		local tiers: { [string]: number } = {}
		for _, entry in RarityRoll.odds(rarities, creatures, 4, { Halloween = true }) do
			tiers[entry.id] = entry.chance
		end
		T.expect(odds.r).toBeNear(tiers.Rare, 1e-12)
		T.expect(odds.m + odds.e).toBeNear(tiers.Mythic, 1e-12)
		T.expect(odds.e / odds.m).toBeNear(1000, 1e-9)
	end)

	T.it("matches what RarityRoll.roll draws with the same arguments", function()
		local rng = T.seededRandom(99)
		local counts: { [string]: number } = {}
		local n = 200000
		for _ = 1, n do
			local id = RarityRoll.roll(rarities, creatures, 3, {}, rng) :: string
			counts[id] = (counts[id] or 0) + 1
		end
		for id, chance in RarityRoll.creatureOdds(rarities, creatures, 3, {}) do
			T.expect((counts[id] or 0) / n).toBeNear(chance, 0.006)
		end
	end)

	T.it("leaves out creatures that can never roll", function()
		local list = { F.creature("a", "Common", 1), F.creature("zero", "Common", 0) }
		local odds = RarityRoll.creatureOdds(rarities, list, 1, {})
		T.expect(odds.a).toBeNear(1, 1e-12)
		T.expect(odds.zero).toBeNil()
		T.expect((next(RarityRoll.creatureOdds(rarities, {}, 1, {})))).toBeNil()
	end)
end)

return nil
