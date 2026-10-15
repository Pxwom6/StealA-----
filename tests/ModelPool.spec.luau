--!strict
local T = require("./TestKit")
local Creatures = require("../src/shared/Config/Creatures")
local Gameplay = require("../src/shared/Config/Gameplay")
local MapThemes = require("../src/shared/Config/MapThemes")
local Modifiers = require("../src/shared/Config/Modifiers")
local Mutations = require("../src/shared/Config/Mutations")
local Rarities = require("../src/shared/Config/Rarities")
local Catalog = require("../src/shared/Logic/Catalog")
local ModelPool = require("../src/shared/Logic/ModelPool")
local ModifierRules = require("../src/shared/Logic/ModifierRules")
local MutationRules = require("../src/shared/Logic/MutationRules")
local RarityRoll = require("../src/shared/Logic/RarityRoll")

type Result = { maxParked: number, maxAlive: number, builds: number, spawns: number, kinds: number, perKind: number }

-- Replays a belt session like BeltService (spawns rolled with the real configs, a map change every rotation, the
-- modifier schedule) with BeltController's pooling: take a parked model or build one; park it when the item leaves;
-- destroy what the pool hands back. Like the UI reviewer's poolSim.luau, without the Roblox parts.
local function replay(hours: number, seed: number, events: { [string]: boolean }): Result
	local rng = T.seededRandom(seed)
	local catalog = Catalog.build(Creatures, Rarities, Mutations)
	local belt = Gameplay.belt
	local pool = ModelPool.new(belt.modelPool.perKind, belt.modelPool.max) :: ModelPool.Pool<string>
	local t = 0
	local mapId = MapThemes.order[1]
	local nextMapAt = MapThemes.rotation.mapSeconds
	local modifier: string? = nil
	local lastModifier: string? = nil
	local modifierEndsAt = 0
	local nextModifierAt = Modifiers.schedule.firstDelaySeconds
	local active: { { key: string, endsAt: number } } = {}
	local seen: { [string]: boolean } = {}
	local result: Result = { maxParked = 0, maxAlive = 0, builds = 0, spawns = 0, kinds = 0, perKind = 0 }
	while t < hours * 3600 do
		if t >= nextMapAt then
			local others = {}
			for _, id in MapThemes.order do
				if id ~= mapId then
					table.insert(others, id)
				end
			end
			mapId = others[math.clamp(math.floor(rng() * #others) + 1, 1, #others)]
			nextMapAt = t + MapThemes.rotation.mapSeconds
		end
		if modifier and t >= modifierEndsAt then
			lastModifier, modifier = modifier, nil
			nextModifierAt = t + ModifierRules.gap(Modifiers.schedule, rng)
		end
		if modifier == nil and t >= nextModifierAt then
			modifier = ModifierRules.pick(Modifiers, lastModifier, rng)
			modifierEndsAt = t + Modifiers.schedule.durationSeconds
		end
		local effects = ModifierRules.effects(Modifiers, modifier)
		for index = #active, 1, -1 do
			if t >= active[index].endsAt then
				ModelPool.park(pool, active[index].key, active[index].key) -- whatever comes back is destroyed
				table.remove(active, index)
			end
		end
		if #active < ModifierRules.beltCapacity(belt.maxItems, effects) then
			local creatureId = RarityRoll.roll(catalog.rarityList, catalog.creatureList, effects.luck, events, rng)
			if creatureId then
				local conditions = MutationRules.conditions(events, mapId, modifier)
				local variant = MutationRules.roll(catalog.mutationList, conditions, rng, effects.mutationChance)
				local key = creatureId .. "|" .. (variant or "")
				result.spawns += 1
				if not seen[key] then
					seen[key] = true
					result.kinds += 1
				end
				if ModelPool.take(pool, key) == nil then
					result.builds += 1
				end
				table.insert(active, { key = key, endsAt = t + belt.travelSeconds })
			end
		end
		result.maxParked = math.max(result.maxParked, ModelPool.size(pool))
		result.maxAlive = math.max(result.maxAlive, ModelPool.size(pool) + #active)
		for _, count in pool.perKeyCount do
			result.perKind = math.max(result.perKind, count)
		end
		t += belt.spawnInterval * effects.spawnInterval
	end
	return result
end

T.describe("ModelPool", function()
	T.it("gives back what was parked under the same key, newest first", function()
		local pool = ModelPool.new(2, 10) :: ModelPool.Pool<string>
		T.expect(ModelPool.take(pool, "a")).toBeNil()
		T.expect(#ModelPool.park(pool, "a", "a1")).toBe(0)
		T.expect(#ModelPool.park(pool, "a", "a2")).toBe(0)
		T.expect(#ModelPool.park(pool, "b", "b1")).toBe(0)
		T.expect(ModelPool.size(pool)).toBe(3)
		T.expect(ModelPool.take(pool, "a")).toBe("a2")
		T.expect(ModelPool.take(pool, "a")).toBe("a1")
		T.expect(ModelPool.take(pool, "a")).toBeNil()
		T.expect(ModelPool.items(pool)).toEqual({ "b1" })
	end)
	T.it("refuses a second one of a kind past perKey, and drops the least recently parked past the total", function()
		local pool = ModelPool.new(1, 3) :: ModelPool.Pool<string>
		ModelPool.park(pool, "a", "a1")
		T.expect(ModelPool.park(pool, "a", "a2")).toEqual({ "a2" }) -- one like it already waits
		ModelPool.park(pool, "b", "b1")
		ModelPool.park(pool, "c", "c1")
		T.expect(ModelPool.park(pool, "d", "d1")).toEqual({ "a1" }) -- the oldest goes
		T.expect(ModelPool.size(pool)).toBe(3)
		T.expect(ModelPool.take(pool, "a")).toBeNil()
		-- taking one frees its kind's place again
		T.expect(ModelPool.take(pool, "b")).toBe("b1")
		T.expect(#ModelPool.park(pool, "b", "b2")).toBe(0)
	end)
	T.it("holds nothing with a total of 0", function()
		local pool = ModelPool.new(1, 0) :: ModelPool.Pool<string>
		T.expect(ModelPool.park(pool, "a", "a1")).toEqual({ "a1" })
		T.expect(ModelPool.size(pool)).toBe(0)
	end)
	T.it("has sane caps in Config/Gameplay", function()
		local caps = Gameplay.belt.modelPool
		T.expect(caps.perKind).toBe(1)
		T.expect(caps.max).toBeAtLeast(8)
		T.expect(caps.max).toBeAtMost(64)
	end)
	T.it("stays bounded through a 10-hour session with every map, modifier and mutation", function()
		-- The old pool kept one model per Snackling and mutation pair ever seen: about 450 after 10 hours.
		local caps = Gameplay.belt.modelPool
		local beltMost = Gameplay.belt.maxItems
		for id in Modifiers.modifiers do
			local effects = ModifierRules.effects(Modifiers, id)
			beltMost = math.max(beltMost, ModifierRules.beltCapacity(Gameplay.belt.maxItems, effects))
		end
		for _, run in { { seed = 1, events = {} }, { seed = 7, events = { Winter2026 = true } } } do
			local result = replay(10, run.seed, run.events :: { [string]: boolean })
			T.expect(result.kinds).toBeGreaterThan(5 * caps.max) -- the session really sees hundreds of kinds
			T.expect(result.maxParked).toBeAtMost(caps.max)
			T.expect(result.perKind).toBeAtMost(caps.perKind)
			-- models alive at once: what is on the belt (more with a faster belt) plus the spares
			T.expect(result.maxAlive).toBeAtMost(beltMost + caps.max)
			-- and spares are still reused (the common Snacklings come back)
			T.expect(result.builds).toBeLessThan(result.spawns * 0.8)
		end
	end)
end)

return nil
