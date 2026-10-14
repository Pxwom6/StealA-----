--!strict
local T = require("./TestKit")
local Catalog = require("../src/shared/Logic/Catalog")
local MutationRules = require("../src/shared/Logic/MutationRules")
local Types = require("../src/shared/Types")
local F = require("./Fixtures")

-- Listed out of order on purpose: rolls go by `order`.
local mutations = {
	F.mutation("diamond", 2, 0.02),
	F.mutation("golden", 1, 0.1),
	F.mutation("rainbow", 3, 0.005),
	F.mutation("haunted", 4, 0.05, "Halloween"),
}

local function byId(list: { Types.MutationDef }): { [string]: Types.MutationDef }
	return Catalog.build({}, {}, list).mutations
end

-- An RNG that returns the given numbers in turn (and counts how many were drawn).
local function scripted(values: { number }): (() -> number, () -> number)
	local index = 0
	return function(): number
		index += 1
		return values[index]
	end, function(): number
		return index
	end
end

T.describe("MutationRules.odds", function()
	T.it("lists eligible mutations in roll order with their exact chances", function()
		local odds = MutationRules.odds(mutations, {})
		T.expect(#odds).toBe(3)
		T.expect(odds[1]).toEqual({ id = "golden", chance = 0.1 })
		T.expect(odds[2]).toEqual({ id = "diamond", chance = 0.02 })
		T.expect(odds[3]).toEqual({ id = "rainbow", chance = 0.005 })
	end)
	T.it("includes an event-only mutation only while its event is active", function()
		T.expect(#MutationRules.odds(mutations, { OtherEvent = true })).toBe(3)
		local odds = MutationRules.odds(mutations, { Halloween = true })
		T.expect(#odds).toBe(4)
		T.expect(odds[4]).toEqual({ id = "haunted", chance = 0.05 })
	end)
	T.it("never lets the total pass 1, even with broken config", function()
		local broken = { F.mutation("a", 1, 0.7), F.mutation("b", 2, 0.6) }
		local odds = MutationRules.odds(broken, {})
		T.expect(odds[1].chance).toBeNear(0.7)
		T.expect(odds[2].chance).toBeNear(0.3)
	end)
	T.it("multiplies every chance by a server modifier's mutation chance", function()
		local odds = MutationRules.odds(mutations, { Halloween = true }, 3)
		T.expect(odds[1].chance).toBeNear(0.3)
		T.expect(odds[2].chance).toBeNear(0.06)
		T.expect(odds[3].chance).toBeNear(0.015)
		T.expect(odds[4].chance).toBeNear(0.15)
		-- Still clamped at 1 in total.
		local huge = MutationRules.odds(mutations, {}, 20)
		local total = 0
		for _, entry in huge do
			total += entry.chance
		end
		T.expect(total).toBeNear(1)
	end)
end)

T.describe("MutationRules.roll", function()
	T.it("maps one random number across the cumulative chances", function()
		local function rollWith(r: number, events: { [string]: boolean }?): string?
			local rng = scripted({ r })
			return MutationRules.roll(mutations, events or {}, rng)
		end
		T.expect(rollWith(0)).toBe("golden")
		T.expect(rollWith(0.0999)).toBe("golden")
		T.expect(rollWith(0.1)).toBe("diamond")
		T.expect(rollWith(0.1199)).toBe("diamond")
		T.expect(rollWith(0.1201)).toBe("rainbow")
		T.expect(rollWith(0.1249)).toBe("rainbow")
		T.expect(rollWith(0.125)).toBeNil()
		T.expect(rollWith(0.9999)).toBeNil()
		T.expect(rollWith(0.13, { Halloween = true })).toBe("haunted")
		T.expect(rollWith(0.13)).toBeNil()
	end)
	T.it("draws exactly one number per roll, mutated or not", function()
		local rng, count = scripted({ 0.5, 0.01, 0.99 })
		MutationRules.roll(mutations, {}, rng)
		MutationRules.roll(mutations, {}, rng)
		MutationRules.roll(mutations, {}, rng)
		T.expect(count()).toBe(3)
		local none, noneCount = scripted({ 0.01 })
		T.expect(MutationRules.roll({}, {}, none)).toBeNil()
		T.expect(noneCount()).toBe(1)
	end)
	T.it("is deterministic for a seeded RNG", function()
		local a, b = T.seededRandom(99), T.seededRandom(99)
		for _ = 1, 2000 do
			T.expect(MutationRules.roll(mutations, {}, a)).toBe(MutationRules.roll(mutations, {}, b))
		end
	end)
	T.it("matches the configured chances over many rolls", function()
		local rng = T.seededRandom(1234)
		local counts: { [string]: number } = {}
		local n = 400000
		for _ = 1, n do
			local id = MutationRules.roll(mutations, {}, rng) or "none"
			counts[id] = (counts[id] or 0) + 1
		end
		T.expect((counts.golden or 0) / n).toBeNear(0.1, 0.003)
		T.expect((counts.diamond or 0) / n).toBeNear(0.02, 0.0015)
		T.expect((counts.rainbow or 0) / n).toBeNear(0.005, 0.0007)
		T.expect((counts.none or 0) / n).toBeNear(0.875, 0.003)
		T.expect(counts.haunted).toBeNil()
	end)
	T.it("rolls with the multiplied chances", function()
		local rng = scripted({ 0.29 })
		T.expect(MutationRules.roll(mutations, {}, rng, 3)).toBe("golden")
		local plain = scripted({ 0.29 })
		T.expect(MutationRules.roll(mutations, {}, plain)).toBeNil()
	end)
	T.it("rolls an event-only mutation at its chance while the event runs", function()
		local rng = T.seededRandom(77)
		local haunted = 0
		local n = 200000
		for _ = 1, n do
			if MutationRules.roll(mutations, { Halloween = true }, rng) == "haunted" then
				haunted += 1
			end
		end
		T.expect(haunted / n).toBeNear(0.05, 0.002)
	end)
end)

T.describe("MutationRules price and income", function()
	local index = byId(mutations)
	local pup = F.creature("pup", "Common", 1)
	pup.price = 25
	pup.income = 3
	T.it("plain and unknown variants cost and earn x1", function()
		T.expect(MutationRules.price(index, pup, nil)).toBe(25)
		T.expect(MutationRules.income(index, pup, nil)).toBe(3)
		T.expect(MutationRules.price(index, pup, "retired_mutation")).toBe(25)
		T.expect(MutationRules.income(index, pup, "retired_mutation")).toBe(3)
		T.expect(MutationRules.find(index, "retired_mutation")).toBeNil()
	end)
	T.it("applies the mutation's multipliers; prices stay whole numbers", function()
		T.expect(MutationRules.price(index, pup, "golden")).toBe(38) -- 37.5 rounds up
		T.expect(MutationRules.income(index, pup, "golden")).toBe(6)
		local odd = F.mutation("odd", 9, 0.01)
		odd.priceMultiplier = 1.37
		odd.incomeMultiplier = 2.5
		local oddIndex = byId({ odd })
		for _, price in { 25, 60, 120, 4500, 1800000000, 3200000000 } do
			pup.price = price
			local mutated = MutationRules.price(oddIndex, pup, "odd")
			T.expect(mutated).toBe(math.floor(mutated))
			T.expect(mutated).toBeAtLeast(price)
			T.expect(mutated).toBeNear(price * 1.37, 0.5)
		end
		T.expect(MutationRules.income(oddIndex, pup, "odd")).toBe(7.5)
		pup.price = 25
	end)
	T.it("names a mutated creature from the template", function()
		local named = F.creature("pup", "Common", 1)
		named.displayName = "Pizza Pup"
		local golden = F.mutation("golden", 1, 0.1)
		golden.displayName = "Golden"
		local goldIndex = byId({ golden })
		T.expect(MutationRules.displayName(goldIndex, named, "golden", "{mutation} {creature}"))
			.toBe("Golden Pizza Pup")
		T.expect(MutationRules.displayName(goldIndex, named, nil, "{mutation} {creature}")).toBe("Pizza Pup")
		T.expect(MutationRules.displayName(goldIndex, named, "gone", "{mutation} {creature}")).toBe("Pizza Pup")
	end)
	T.it("reports the expected multipliers of one belt spawn", function()
		local income, price = MutationRules.expectedMultipliers(mutations, {})
		-- golden x2 / x1.5 at 10%, diamond, rainbow likewise (fixture multipliers) at 2% and 0.5%
		T.expect(income).toBeNear(1 + 0.125 * 1)
		T.expect(price).toBeNear(1 + 0.125 * 0.5)
	end)
end)

T.describe("MutationRules.banner", function()
	local loud = F.mutation("rainbow", 3, 0.001)
	loud.color = "#FF5FD2"
	loud.announceOnSpawn = true
	loud.announceOnSteal = true
	local quiet = F.mutation("golden", 1, 0.03)
	T.it("announces when the rarity asks, keeping the rarity colour", function()
		T.expect((MutationRules.banner(true, nil, "spawn"))).toBe(true)
		T.expect(select(2, MutationRules.banner(true, nil, "spawn"))).toBeNil()
		T.expect(select(2, MutationRules.banner(true, quiet, "buy"))).toBeNil()
	end)
	T.it("announces when only the mutation asks, in the mutation colour", function()
		local announce, color = MutationRules.banner(false, loud, "spawn")
		T.expect(announce).toBe(true)
		T.expect(color).toBe("#FF5FD2")
		T.expect(select(2, MutationRules.banner(false, loud, "steal"))).toBe("#FF5FD2")
	end)
	T.it("keeps the rarity colour when both ask", function()
		local announce, color = MutationRules.banner(true, loud, "spawn")
		T.expect(announce).toBe(true)
		T.expect(color).toBeNil()
	end)
	T.it("stays quiet when neither asks", function()
		T.expect((MutationRules.banner(false, nil, "spawn"))).toBe(false)
		T.expect((MutationRules.banner(false, quiet, "spawn"))).toBe(false)
		T.expect((MutationRules.banner(false, loud, "buy"))).toBe(false) -- loud only announces spawns and steals
	end)
end)

T.describe("Catalog mutations", function()
	T.it("indexes mutations by id and sorts them by order", function()
		local catalog = Catalog.build({}, {}, mutations)
		T.expect(catalog.mutationList[1].id).toBe("golden")
		T.expect(catalog.mutationList[4].id).toBe("haunted")
		T.expect(catalog.mutations.rainbow.chance).toBe(0.005)
		T.expect(#Catalog.build({}, {}).mutationList).toBe(0)
	end)
	T.it("accepts a valid mutation list", function()
		T.expect(#Catalog.validateMutations(mutations)).toBe(0)
		T.expect(#Catalog.validateMutations({})).toBe(0)
	end)
	T.it("reports every kind of broken mutation", function()
		local function problemsWith(edit: (Types.MutationDef) -> ()): number
			local m = F.mutation("ok", 1, 0.1)
			edit(m)
			return #Catalog.validateMutations({ m })
		end
		T.expect(problemsWith(function(m)
			m.chance = 0
		end)).toBeAtLeast(1)
		T.expect(problemsWith(function(m)
			m.chance = 1
		end)).toBeAtLeast(1)
		T.expect(problemsWith(function(m)
			m.chance = 0 / 0
		end)).toBeAtLeast(1)
		T.expect(problemsWith(function(m)
			m.incomeMultiplier = 0.5
		end)).toBeAtLeast(1)
		T.expect(problemsWith(function(m)
			m.priceMultiplier = math.huge
		end)).toBeAtLeast(1)
		T.expect(problemsWith(function(m)
			m.color = "gold"
		end)).toBeAtLeast(1)
		T.expect(problemsWith(function(m)
			m.id = "has space"
		end)).toBeAtLeast(1)
		T.expect(problemsWith(function(m)
			m.displayName = ""
		end)).toBeAtLeast(1)
		T.expect(problemsWith(function(m)
			m.look = { material = "Unobtanium" }
		end)).toBeAtLeast(1)
		T.expect(problemsWith(function(m)
			m.look = { material = "Foil", tint = "#12345" }
		end)).toBeAtLeast(1)
		T.expect(problemsWith(function(m)
			m.look = { material = "Glass", transparency = 1 }
		end)).toBeAtLeast(1)
		T.expect(problemsWith(function(m)
			m.look = { material = "Glass", tintStrength = 2, reflectance = -1 }
		end)).toBeAtLeast(2)
		T.expect(problemsWith(function(m)
			m.look = { material = "ForceField", glow = "green" }
		end)).toBe(1)
		T.expect(problemsWith(function(m)
			m.look = { material = "ForceField", glow = "#7CFF9B" }
		end)).toBe(0)
	end)
	T.it("rejects duplicate ids and orders, and chances that add up to 1 or more", function()
		T.expect(#Catalog.validateMutations({ F.mutation("a", 1, 0.1), F.mutation("a", 2, 0.1) })).toBe(1)
		T.expect(#Catalog.validateMutations({ F.mutation("a", 1, 0.1), F.mutation("b", 1, 0.1) })).toBe(1)
		-- event-only mutations count too: the total must stay below 1 even if every event runs at once
		local tooMuch = { F.mutation("a", 1, 0.6), F.mutation("b", 2, 0.5, "Halloween") }
		T.expect(#Catalog.validateMutations(tooMuch)).toBe(1)
	end)
	T.it("counts only one map and one modifier towards the total", function()
		local list = { F.mutation("a", 1, 0.5) }
		for index, theme in { "candy", "winter", "desert" } do
			local m = F.mutation(`map{index}`, 1 + index, 0.3)
			m.mapTheme = theme
			table.insert(list, m)
		end
		local storm = F.mutation("storm", 9, 0.15)
		storm.modifierId = "thunderstorm"
		table.insert(list, storm)
		-- 0.5 + one map's 0.3 + one modifier's 0.15 = 0.95 (the plain sum would be 1.55)
		T.expect(#Catalog.validateMutations(list)).toBe(0)
		local second = F.mutation("storm2", 10, 0.1)
		second.modifierId = "thunderstorm" -- the same modifier: both roll together
		table.insert(list, second)
		T.expect(#Catalog.validateMutations(list)).toBe(1)
	end)
	T.it("refuses more than one gate, empty gates and unknown particle presets", function()
		local both = F.mutation("both", 1, 0.1, "Halloween")
		both.mapTheme = "candy"
		T.expect(#Catalog.validateMutations({ both })).toBe(1)
		local empty = F.mutation("empty", 1, 0.1)
		empty.modifierId = ""
		T.expect(#Catalog.validateMutations({ empty })).toBe(1)
		local colon = F.mutation("colon", 1, 0.1)
		colon.mapTheme = "map:candy"
		T.expect(#Catalog.validateMutations({ colon })).toBe(1)
		local sparkly = F.mutation("sparkly", 1, 0.1)
		sparkly.look = { material = "Neon", particles = "glitter" }
		T.expect(#Catalog.validateMutations({ sparkly })).toBe(1)
		sparkly.look = { material = "CrackedLava", particles = "embers" }
		T.expect(#Catalog.validateMutations({ sparkly })).toBe(0)
	end)
end)

T.describe("MutationRules gates: map themes and server modifiers", function()
	local molten = F.mutation("molten", 5, 0.04)
	molten.mapTheme = "volcano"
	local frozen = F.mutation("frozen", 6, 0.04)
	frozen.mapTheme = "winter"
	local electric = F.mutation("electric", 7, 0.05)
	electric.modifierId = "thunderstorm"
	local all = table.clone(mutations)
	for _, m in { molten, frozen, electric } do
		table.insert(all, m)
	end

	local function ids(active: { [string]: boolean }): { string }
		local list: { string } = {}
		for _, entry in MutationRules.odds(all, active) do
			table.insert(list, entry.id)
		end
		return list
	end

	T.it("builds the condition keys from the events, the map and the modifier", function()
		local events = { Halloween = true, Old = false }
		local active = MutationRules.conditions(events, "volcano", "thunderstorm")
		T.expect(active).toEqual({ Halloween = true, ["map:volcano"] = true, ["modifier:thunderstorm"] = true })
		T.expect(events).toEqual({ Halloween = true, Old = false }) -- not changed
		T.expect(MutationRules.conditions({}, nil, nil)).toEqual({})
		T.expect(MutationRules.mapKey("candy")).toBe("map:candy")
		T.expect(MutationRules.modifierKey("toxicFog")).toBe("modifier:toxicFog")
	end)

	T.it("rolls a map's mutation only on that map, and a modifier's only while it runs", function()
		T.expect(ids({})).toEqual({ "golden", "diamond", "rainbow" })
		T.expect(ids(MutationRules.conditions({}, "volcano", nil)))
			.toEqual({ "golden", "diamond", "rainbow", "molten" })
		T.expect(ids(MutationRules.conditions({}, "winter", nil))).toEqual({ "golden", "diamond", "rainbow", "frozen" })
		T.expect(ids(MutationRules.conditions({}, "meadow", "thunderstorm"))).toEqual({
			"golden",
			"diamond",
			"rainbow",
			"electric",
		})
		T.expect(ids(MutationRules.conditions({ Halloween = true }, "volcano", "thunderstorm"))).toEqual({
			"golden",
			"diamond",
			"rainbow",
			"haunted",
			"molten",
			"electric",
		})
		-- A plain event id that happens to equal a map or modifier id opens nothing else.
		T.expect(ids({ volcano = true, thunderstorm = true })).toEqual({ "golden", "diamond", "rainbow" })
	end)

	T.it("never changes a permanent roll, whatever map or modifier is up", function()
		local index = byId(all)
		local a, b = T.seededRandom(11), T.seededRandom(11)
		local active = MutationRules.conditions({ Halloween = true }, "volcano", "thunderstorm")
		for _ = 1, 5000 do
			local during = MutationRules.roll(all, active, a)
			local plain = MutationRules.roll(all, {}, b)
			local def = MutationRules.find(index, during)
			if def == nil or MutationRules.gate(def) == nil then
				T.expect(during).toBe(plain)
			end
		end
	end)

	T.it("names each mutation's gate", function()
		T.expect(MutationRules.gate(mutations[2])).toBeNil()
		T.expect(MutationRules.gate(mutations[4])).toBe("event")
		T.expect(MutationRules.gate(molten)).toBe("map")
		T.expect(MutationRules.gate(electric)).toBe("modifier")
	end)

	T.it("finds a map's signature mutation and a modifier's", function()
		T.expect((MutationRules.forMap(all, "volcano") :: Types.MutationDef).id).toBe("molten")
		T.expect(MutationRules.forMap(all, "meadow")).toBeNil()
		T.expect((MutationRules.forModifier(all, "thunderstorm") :: Types.MutationDef).id).toBe("electric")
		T.expect(MutationRules.forModifier(all, "fortress")).toBeNil()
	end)

	T.it("adds up the worst case: everything permanent and every event, plus one map and one modifier", function()
		-- 0.1 + 0.02 + 0.005 + 0.05 (haunted) + 0.04 (one map) + 0.05 (the modifier)
		T.expect(MutationRules.worstCaseTotal(all)).toBeNear(0.265)
		local worst = 0
		for _, map in { "volcano", "winter", "meadow" } do
			for _, modifier in { "thunderstorm", "fortress" } do
				local total = 0
				for _, entry in MutationRules.odds(all, MutationRules.conditions({ Halloween = true }, map, modifier)) do
					total += entry.chance
				end
				worst = math.max(worst, total)
			end
		end
		T.expect(worst).toBeNear(MutationRules.worstCaseTotal(all))
	end)
end)

return nil
