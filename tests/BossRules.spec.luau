--!strict
local T = require("./TestKit")
local BossRules = require("../src/shared/Logic/BossRules")
local Boss = require("../src/shared/Config/Boss")
local Modifiers = require("../src/shared/Config/Modifiers")
local DropRules = require("../src/shared/Logic/DropRules")
local Rarities = require("../src/shared/Config/Rarities")
local Types = require("../src/shared/Types")

local function rarityIds(): { [string]: boolean }
	local ids: { [string]: boolean } = {}
	for _, rarity in Rarities do
		ids[rarity.id] = true
	end
	return ids
end

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

T.describe("BossRules: the real config", function()
	T.it("is valid", function()
		local problems = BossRules.validate(Boss, rarityIds())
		if #problems > 0 then
			print(table.concat(problems, "\n"))
		end
		T.expect(#problems).toBe(0)
	end)

	T.it("sends three giants during Snack Attack, each gone before the next", function()
		local drops = Modifiers.modifiers.snackAttack.drops :: Types.ModifierDrops
		T.expect(drops.kind).toBe("boss")
		local times = DropRules.times(drops, Modifiers.schedule.durationSeconds)
		T.expect(#times).toBe(3)
		T.expect(drops.everySeconds).toBeGreaterThan(Boss.lifetimeSeconds)
	end)

	T.it("is a team effort at every server size, and beatable in time", function()
		for players = 1, 30 do
			local seconds = BossRules.fastestTakedown(Boss, players)
			-- everyone hitting flat out: quick enough to be fun, slow enough to be a fight
			T.expect(seconds).toBeLessThan(Boss.lifetimeSeconds * 0.5)
			T.expect(seconds).toBeGreaterThan(10)
		end
		T.expect(BossRules.maxHp(Boss, 1)).toBe(Boss.minHp)
		T.expect(BossRules.maxHp(Boss, 10)).toBe(Boss.hpPerPlayer * 10)
	end)
end)

T.describe("BossRules rewards", function()
	T.it("shares the reward among everyone who helped enough, the top hitter first", function()
		local shares = BossRules.shares(Boss, { a = 40, b = 70, c = 4, d = 70 })
		T.expect(#shares).toBe(3) -- c landed fewer than minHits
		T.expect(shares[1].key).toBe("b") -- a tie on hits goes to the smaller key
		T.expect(shares[2].key).toBe("d")
		T.expect(shares[3].key).toBe("a")
		T.expect(shares[1].share).toBeNear(70 / 184, 1e-9)
		T.expect(#BossRules.shares(Boss, {})).toBe(0)
	end)

	T.it("pays more for a bigger share, from each player's own income, never less than the minimum", function()
		local small = BossRules.cash(Boss, 0.1, 1000)
		local big = BossRules.cash(Boss, 0.6, 1000)
		T.expect(big).toBeGreaterThan(small)
		T.expect(BossRules.cash(Boss, 1, 0)).toBe(Boss.cash.minimum)
		T.expect(BossRules.cash(Boss, 0.5, 100000)).toBeGreaterThan(BossRules.cash(Boss, 0.5, 1000))
		-- a solo takedown pays the full share
		T.expect(BossRules.cash(Boss, 1, 1000)).toBe(1000 * (Boss.cash.baseSeconds + Boss.cash.shareSeconds))
	end)

	T.it("refuses a broken config", function()
		local function broken(edit: (config: any) -> ()): number
			local config = copy(Boss)
			edit(config)
			return #BossRules.validate(config :: Types.BossConfig, rarityIds())
		end
		T.expect(broken(function(config)
			config.rarities = { "Legendary", "Mega" }
		end)).toBe(1)
		T.expect(broken(function(config)
			config.burst = 1
		end)).toBe(1)
		T.expect(broken(function(config)
			config.minHp = 5000
			config.lifetimeSeconds = 20 -- one player could never finish it
		end)).toBe(1)
		T.expect(broken(function(config)
			config.luck = 50
		end)).toBe(1)
	end)
end)

return nil
