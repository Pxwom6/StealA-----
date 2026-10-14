--!strict
local T = require("./TestKit")
local Catalog = require("../src/shared/Logic/Catalog")
local Creatures = require("../src/shared/Config/Creatures")
local Gifts = require("../src/shared/Config/Gifts")
local GiftRules = require("../src/shared/Logic/GiftRules")
local Mutations = require("../src/shared/Config/Mutations")
local Rarities = require("../src/shared/Config/Rarities")
local Types = require("../src/shared/Types")

local catalog = Catalog.build(Creatures, Rarities, Mutations)

local LADDER: Types.GiftsConfig = {
	ladder = {
		{ minutes = 5, icon = "💵", reward = { kind = "cash", incomeSeconds = 30, minimum = 100 } },
		{ minutes = 10, icon = "🎰", reward = { kind = "spin", count = 1 } },
		{ minutes = 20, icon = "🎁", reward = { kind = "creature", luck = 2 } },
	},
}

local function fresh(): Types.GiftState
	return { day = 100, seconds = 0, claimed = {} }
end

T.describe("GiftRules: the real config", function()
	T.it("is valid", function()
		local problems = GiftRules.validate(Gifts, catalog.mutations)
		if #problems > 0 then
			print(table.concat(problems, "\n"))
		end
		T.expect(#problems).toBe(0)
	end)

	T.it("finishes the ladder within an hour of play", function()
		T.expect(Gifts.ladder[#Gifts.ladder].minutes).toBeAtMost(60)
	end)
end)

T.describe("GiftRules playtime and claims", function()
	T.it("unlocks gifts as the minutes go by", function()
		local state = fresh()
		T.expect(GiftRules.claimable(state, LADDER)).toBe(0)
		GiftRules.addTime(state, 5 * 60)
		T.expect(GiftRules.claimable(state, LADDER)).toBe(1)
		T.expect(GiftRules.secondsUntil(LADDER, 2, state.seconds)).toBe(5 * 60)
		GiftRules.addTime(state, 30 * 60)
		T.expect(GiftRules.claimable(state, LADDER)).toBe(3)
		T.expect(GiftRules.secondsUntil(LADDER, 3, state.seconds)).toBe(0)
	end)

	T.it("pays each gift once a day, in any order, never a locked one", function()
		local state = fresh()
		GiftRules.addTime(state, 10 * 60)
		T.expect(GiftRules.claim(state, LADDER, 3)).toBeNil() -- locked
		T.expect((GiftRules.claim(state, LADDER, 2) :: Types.GiftDef).minutes).toBe(10)
		T.expect(GiftRules.claim(state, LADDER, 2)).toBeNil() -- already claimed
		T.expect((GiftRules.claim(state, LADDER, 1) :: Types.GiftDef).minutes).toBe(5)
		T.expect(GiftRules.claim(state, LADDER, 9)).toBeNil() -- not a gift
		T.expect(state.claimed).toEqual({ 2, 1 })
		T.expect(GiftRules.claimable(state, LADDER)).toBe(0)
	end)

	T.it("starts again on a new day", function()
		local state = fresh()
		GiftRules.addTime(state, 3600)
		GiftRules.claim(state, LADDER, 1)
		T.expect(GiftRules.isStale(state, 100)).toBe(false)
		T.expect(GiftRules.isStale(state, 101)).toBe(true)
		GiftRules.reset(state, 101)
		T.expect(state).toEqual({ day = 101, seconds = 0, claimed = {} })
	end)

	T.it("never counts more than a day, nor negative or broken time", function()
		local state = fresh()
		GiftRules.addTime(state, 10 * 86400)
		T.expect(state.seconds).toBe(86400)
		local other = fresh()
		GiftRules.addTime(other, -50)
		GiftRules.addTime(other, 0 / 0)
		T.expect(other.seconds).toBe(0)
	end)
end)

T.describe("GiftRules.validate", function()
	local function problems(config: any): number
		return #GiftRules.validate(config, catalog.mutations)
	end

	T.it("accepts a good ladder", function()
		T.expect(problems(LADDER)).toBe(0)
	end)

	T.it("refuses gifts out of order and broken rewards", function()
		T.expect(problems({ ladder = { LADDER.ladder[2], LADDER.ladder[1] } })).toBe(1)
		T.expect(problems({ ladder = {} })).toBe(1)
		T.expect(problems({ ladder = { { minutes = 5, icon = "x", reward = { kind = "spin", count = 0 } } } })).toBe(1)
		T.expect(problems({ ladder = { { minutes = 5, icon = "x", reward = { kind = "creature", luck = 50 } } } }))
			.toBe(1)
		T.expect(problems({
			ladder = { { minutes = 5, icon = "x", reward = { kind = "creature", luck = 2, mutation = "plaid" } } },
		})).toBe(1)
		T.expect(problems({ ladder = { { minutes = 5, icon = "x", reward = { kind = "gems" } } } })).toBe(1)
	end)
end)

return nil
