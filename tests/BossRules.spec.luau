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
		T.expect(BossRules.maxHp(Boss, 0)).toBe(Boss.minHp) -- nobody playing: still a giant
	end)

	T.it("counts only the players playing towards its health (review 2)", function()
		local now = 1000
		-- moved or hit within activeSeconds, out of the tutorial
		T.expect(BossRules.counts(Boss, false, now, now)).toBe(true)
		T.expect(BossRules.counts(Boss, false, now - Boss.activeSeconds, now)).toBe(true)
		-- idle for longer, never moved, or still in the first-time tutorial however busy
		T.expect(BossRules.counts(Boss, false, now - Boss.activeSeconds - 1, now)).toBe(false)
		T.expect(BossRules.counts(Boss, false, -math.huge, now)).toBe(false)
		T.expect(BossRules.counts(Boss, true, now, now)).toBe(false)
		-- the reviewer's server: 2 playing among 8 now face what 2 can bring down, where all 8 counted made it
		-- 720 hits, more than 2 can land in its lifetime
		local playing = 0
		for index = 1, 8 do
			local idle = index > 2
			if BossRules.counts(Boss, index > 6, if idle then -math.huge else now - 5, now) then
				playing += 1
			end
		end
		T.expect(playing).toBe(2)
		T.expect(BossRules.maxHp(Boss, 8) / (Boss.hitsPerSecond * 2)).toBeGreaterThan(Boss.lifetimeSeconds * 0.9)
		T.expect(BossRules.fastestTakedown(Boss, playing)).toBeLessThan(Boss.lifetimeSeconds * 0.5)
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
		T.expect(broken(function(config)
			config.activeSeconds = 5 -- a player pausing to read a toast would stop counting
		end)).toBe(1)
		-- flashing faster than twice a second, a flinch as long as the gap, or a near-opaque red fill
		T.expect(broken(function(config)
			config.flinch.gapSeconds = 0.3
		end)).toBe(1)
		T.expect(broken(function(config)
			config.flinch.seconds = 0.35
			config.flinch.gapSeconds = 0.35 -- also too fast: two problems
		end)).toBe(2)
		T.expect(broken(function(config)
			config.flinch.peakFill = 0.2
		end)).toBe(1)
	end)
end)

T.describe("BossRules flinch (photosensitivity)", function()
	-- Starts of a flinch on a client that sees the HP drop every `step` seconds for `seconds` (the server updates HP
	-- ten times a second; 50 per second is far beyond any server).
	local function flinchStarts(step: number, seconds: number, reduced: boolean): { number }
		local starts: { number } = {}
		local last = -math.huge
		for i = 0, math.floor(seconds / step + 0.5) - 1 do
			local t = i * step
			if BossRules.startsFlinch(Boss, last, t, reduced) then
				last = t
				table.insert(starts, t)
			end
		end
		return starts
	end

	T.it("flashes at most twice a second however fast the hits come", function()
		for _, step in { 0.1, 0.05, 0.02 } do
			local starts = flinchStarts(step, 10, false)
			T.expect(#starts).toBeAtMost(20)
			T.expect(#starts).toBeAtLeast(18) -- a hit still shows
			-- in any one second, at most two (each one a single soft pulse)
			for i = 3, #starts do
				T.expect(starts[i] - starts[i - 2]).toBeAtLeast(1 - 1e-9)
			end
		end
		T.expect(Boss.flinch.gapSeconds).toBeAtLeast(0.5)
	end)

	T.it("never flashes with Reduce effects", function()
		T.expect(#flinchStarts(0.1, 10, true)).toBe(0)
		T.expect(BossRules.startsFlinch(Boss, -math.huge, 0, true)).toBe(false)
	end)

	T.it("is a soft pulse: strongest at once, fading back to nothing", function()
		T.expect(BossRules.flinchFill(Boss, 0)).toBe(Boss.flinch.peakFill)
		T.expect(Boss.flinch.peakFill).toBeAtLeast(0.5) -- never more than half-opaque red
		local previous = BossRules.flinchFill(Boss, 0)
		for i = 1, 10 do
			local fill = BossRules.flinchFill(Boss, Boss.flinch.seconds * i / 10)
			T.expect(fill).toBeAtLeast(previous)
			previous = fill
		end
		T.expect(BossRules.flinchFill(Boss, Boss.flinch.seconds)).toBe(1)
		T.expect(BossRules.flinchFill(Boss, -1)).toBe(1)
		T.expect(BossRules.flinchFill(Boss, math.huge)).toBe(1)
		T.expect(Boss.flinch.seconds).toBeLessThan(Boss.flinch.gapSeconds)
	end)
end)

return nil
