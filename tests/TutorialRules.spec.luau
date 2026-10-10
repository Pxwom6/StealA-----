--!strict
local T = require("./TestKit")
local TutorialRules = require("../src/shared/Logic/TutorialRules")
local DataSchema = require("../src/shared/Logic/DataSchema")
local Tutorial = require("../src/shared/Config/Tutorial")
local Theme = require("../src/shared/Config/Theme")
local Types = require("../src/shared/Types")

local function config(): Types.TutorialConfig
	return {
		enabled = true,
		reward = 500,
		steps = {
			{ id = "buy" },
			{ id = "collect" },
			{ id = "lock", unavailableSeconds = 20, timeoutSeconds = 60 },
			{ id = "steal", timeoutSeconds = 90 },
		},
		belt = { minSecondsLeft = 4, switchMargin = 12 },
	}
end

local function newPlayer(): Types.PlayerData
	return DataSchema.template(100)
end

local function stepId(flags: TutorialRules.Flags, cfg: Types.TutorialConfig): string?
	local step = TutorialRules.currentStep(flags, cfg)
	return if step then step.id else nil
end

T.describe("TutorialRules join", function()
	T.it("starts a brand-new player from the first step", function()
		local cfg = config()
		local data = newPlayer()
		T.expect(TutorialRules.joinStatus(data, cfg)).toBe("new")
		local step, index = TutorialRules.currentStep(data.flags, cfg)
		T.expect(step and step.id).toBe("buy")
		T.expect(index).toBe(1)
	end)
	T.it("treats players with progress but no tutorial flags as existing players", function()
		local cfg = config()
		local withCreature = newPlayer()
		table.insert(withCreature.creatures, { uid = "1", id = "x", podium = 1, acquiredAt = 0, stored = 0 })
		T.expect(TutorialRules.joinStatus(withCreature, cfg)).toBe("returning")

		local rebirthed = newPlayer()
		rebirthed.rebirths = 1 -- a rebirth spends every Snackling: still an existing player
		T.expect(TutorialRules.joinStatus(rebirthed, cfg)).toBe("returning")

		local soldEverything = newPlayer()
		soldEverything.stats.beltPurchases = 3
		T.expect(TutorialRules.joinStatus(soldEverything, cfg)).toBe("returning")

		local quarantined = newPlayer()
		table.insert(quarantined.quarantine, { uid = "2", id = "gone", podium = 1, acquiredAt = 0, stored = 0 })
		T.expect(TutorialRules.joinStatus(quarantined, cfg)).toBe("returning")

		local thief = newPlayer()
		thief.stats.steals = 1
		T.expect(TutorialRules.joinStatus(thief, cfg)).toBe("returning")
	end)
	T.it("a joined-before player who never bought anything still gets the tutorial", function()
		local data = newPlayer()
		data.flags.ob_Joined = true
		data.stats.playTime = 30
		T.expect(TutorialRules.joinStatus(data, config())).toBe("new")
	end)
	T.it("resumes a tutorial in progress even though the player now owns Snacklings", function()
		local cfg = config()
		local data = newPlayer()
		T.expect(TutorialRules.markStep(data.flags, "buy", cfg)).toBe(true)
		table.insert(data.creatures, { uid = "1", id = "x", podium = 1, acquiredAt = 0, stored = 0 })
		data.stats.beltPurchases = 1
		T.expect(TutorialRules.joinStatus(data, cfg)).toBe("resume")
		T.expect(stepId(data.flags, cfg)).toBe("collect")
	end)
	T.it("never restarts a finished tutorial, and is off when disabled", function()
		local cfg = config()
		local data = newPlayer()
		TutorialRules.finish(data.flags, "skipped", cfg)
		T.expect(TutorialRules.joinStatus(data, cfg)).toBe("done")
		T.expect(stepId(data.flags, cfg)).toBeNil()
		local off = config()
		off.enabled = false
		T.expect(TutorialRules.joinStatus(newPlayer(), off)).toBe("off")
	end)
	T.it("progress survives the save sanitiser (flags only, no schema change)", function()
		local cfg = config()
		local data = newPlayer()
		TutorialRules.markStep(data.flags, "buy", cfg)
		TutorialRules.markStep(data.flags, "collect", cfg)
		local clean = DataSchema.sanitise(data :: any, 100, {
			isValidCreature = function()
				return true
			end,
			maxPodiums = 20,
			maxPodiumUpgrades = 8,
			startingPodiums = 8,
			maxRebirths = 30,
			maxReceipts = 100,
			maxHistory = 100,
		})
		T.expect(stepId(clean.flags, cfg)).toBe("lock")
		T.expect(clean.version).toBe(DataSchema.VERSION)
	end)
end)

T.describe("TutorialRules steps", function()
	T.it("advances through the steps in order as their actions happen", function()
		local cfg = config()
		local flags: TutorialRules.Flags = {}
		T.expect(TutorialRules.markStep(flags, "buy", cfg)).toBe(true)
		T.expect(stepId(flags, cfg)).toBe("collect")
		T.expect(TutorialRules.markStep(flags, "collect", cfg)).toBe(true)
		T.expect(stepId(flags, cfg)).toBe("lock")
		T.expect(TutorialRules.markStep(flags, "lock", cfg)).toBe(true)
		local step, index = TutorialRules.currentStep(flags, cfg)
		T.expect(step and step.id).toBe("steal")
		T.expect(index).toBe(4)
		T.expect(TutorialRules.markStep(flags, "steal", cfg)).toBe(true)
		T.expect(stepId(flags, cfg)).toBeNil() -- every step done: the caller finishes the tutorial
	end)
	T.it("skips a step whose action was done early", function()
		local cfg = config()
		local flags: TutorialRules.Flags = {}
		TutorialRules.markStep(flags, "buy", cfg)
		T.expect(TutorialRules.markStep(flags, "lock", cfg)).toBe(true) -- locked during the collect step
		T.expect(stepId(flags, cfg)).toBe("collect")
		TutorialRules.markStep(flags, "collect", cfg)
		T.expect(stepId(flags, cfg)).toBe("steal")
	end)
	T.it("ignores repeats, unknown actions and a finished tutorial", function()
		local cfg = config()
		local flags: TutorialRules.Flags = {}
		T.expect(TutorialRules.markStep(flags, "buy", cfg)).toBe(true)
		T.expect(TutorialRules.markStep(flags, "buy", cfg)).toBe(false)
		T.expect(TutorialRules.markStep(flags, "rebirth", cfg)).toBe(false)
		T.expect(flags["tutorial_rebirth"]).toBeNil()
		TutorialRules.finish(flags, "skipped", cfg)
		T.expect(TutorialRules.markStep(flags, "collect", cfg)).toBe(false)
		T.expect(flags["tutorial_collect"]).toBeNil()
	end)
	T.it("follows the configured order", function()
		local cfg = config()
		cfg.steps = { { id = "lock" }, { id = "buy" } }
		T.expect(stepId({}, cfg)).toBe("lock")
		T.expect(TutorialRules.stepIndex("buy", cfg)).toBe(2)
		T.expect(TutorialRules.stepIndex("collect", cfg)).toBe(0)
		T.expect(TutorialRules.markStep({}, "collect", cfg)).toBe(false) -- not a step in this config
	end)
end)

T.describe("TutorialRules automatic step endings", function()
	local cfg = config()
	local lock = cfg.steps[3]
	local steal = cfg.steps[4]
	local buy = cfg.steps[1]

	T.it("moves past the lock step once the lock has been unavailable for 20 s in a row", function()
		local since: number? = nil
		since = TutorialRules.trackUnavailable(since, false, 100)
		T.expect(since).toBe(100)
		since = TutorialRules.trackUnavailable(since, false, 110)
		T.expect(since).toBe(100) -- keeps the start of the streak
		T.expect(TutorialRules.autoOutcome(lock, 100, since, 119.9)).toBeNil()
		T.expect(TutorialRules.autoOutcome(lock, 100, since, 120)).toBe("unavailable")
	end)
	T.it("restarts the 20 s whenever the lock becomes available", function()
		local since = TutorialRules.trackUnavailable(nil, false, 100)
		since = TutorialRules.trackUnavailable(since, true, 115)
		T.expect(since).toBeNil()
		T.expect(TutorialRules.autoOutcome(lock, 100, since, 125)).toBeNil()
		since = TutorialRules.trackUnavailable(since, false, 125)
		T.expect(TutorialRules.autoOutcome(lock, 100, since, 140)).toBeNil()
		T.expect(TutorialRules.autoOutcome(lock, 100, since, 145)).toBe("unavailable")
	end)
	T.it("gives up on the lock step after its timeout even if the lock stays ready", function()
		T.expect(TutorialRules.autoOutcome(lock, 100, nil, 159)).toBeNil()
		T.expect(TutorialRules.autoOutcome(lock, 100, nil, 160)).toBe("timeout")
	end)
	T.it("ends the steal step after 90 s", function()
		T.expect(TutorialRules.autoOutcome(steal, 1000, nil, 1089)).toBeNil()
		T.expect(TutorialRules.autoOutcome(steal, 1000, nil, 1090)).toBe("timeout")
		-- unavailability has no effect on a step without unavailableSeconds
		T.expect(TutorialRules.autoOutcome(steal, 1000, 0, 1050)).toBeNil()
	end)
	T.it("never ends the buy step on its own", function()
		T.expect(TutorialRules.autoOutcome(buy, 0, 0, 1e9)).toBeNil()
	end)
end)

T.describe("TutorialRules reward", function()
	T.it("pays the reward once, when completed", function()
		local cfg = config()
		local flags: TutorialRules.Flags = {}
		T.expect(TutorialRules.finish(flags, "completed", cfg)).toBe(500)
		T.expect(flags[TutorialRules.DONE_FLAG]).toBe(true)
		T.expect(TutorialRules.finish(flags, "completed", cfg)).toBe(0)
		T.expect(TutorialRules.finish(flags, "skipped", cfg)).toBe(0)
	end)
	T.it("pays nothing for a skip or an existing player, and never afterwards", function()
		local cfg = config()
		local skipped: TutorialRules.Flags = {}
		T.expect(TutorialRules.finish(skipped, "skipped", cfg)).toBe(0)
		T.expect(TutorialRules.finish(skipped, "completed", cfg)).toBe(0)
		local existing: TutorialRules.Flags = {}
		T.expect(TutorialRules.finish(existing, "returning", cfg)).toBe(0)
		T.expect(TutorialRules.finish(existing, "completed", cfg)).toBe(0)
	end)
	T.it("never pays a broken reward value", function()
		local cfg = config()
		for _, bad in { 0 / 0, math.huge, -5 } do
			cfg.reward = bad
			T.expect(TutorialRules.finish({}, "completed", cfg)).toBe(0)
		end
		cfg.reward = 250.7
		T.expect(TutorialRules.finish({}, "completed", cfg)).toBe(250)
	end)
	T.it("reset (Studio /tutorial) starts it over", function()
		local cfg = config()
		local flags: TutorialRules.Flags = { ob_Joined = true }
		TutorialRules.markStep(flags, "buy", cfg)
		TutorialRules.finish(flags, "completed", cfg)
		TutorialRules.reset(flags, cfg)
		T.expect(stepId(flags, cfg)).toBe("buy")
		T.expect(flags.ob_Joined).toBe(true) -- other flags untouched
	end)
end)

T.describe("TutorialRules guide targets", function()
	local beltCfg: Types.TutorialBeltConfig = { minSecondsLeft = 4, switchMargin = 12 }

	local function item(id: number, price: number, x: number, secondsLeft: number): TutorialRules.BeltCandidate
		return { id = id, price = price, x = x, z = 0, secondsLeft = secondsLeft }
	end

	T.it("points at the nearest belt item the player can afford", function()
		local items = { item(1, 25, 50, 20), item(2, 5000, 1, 20), item(3, 60, -20, 20) }
		T.expect(TutorialRules.pickBeltItem(items, 100, 0, 10, nil, beltCfg)).toBe(3)
		T.expect(TutorialRules.pickBeltItem(items, 10000, 0, 10, nil, beltCfg)).toBe(2)
		T.expect(TutorialRules.pickBeltItem(items, 10, 0, 10, nil, beltCfg)).toBeNil()
	end)
	T.it("skips items about to fall off the belt", function()
		local items = { item(1, 25, 0, 3), item(2, 25, 40, 10) }
		T.expect(TutorialRules.pickBeltItem(items, 100, 0, 0, nil, beltCfg)).toBe(2)
	end)
	T.it("keeps its target unless another item is clearly closer", function()
		local items = { item(1, 25, 20, 20), item(2, 25, 10, 20) }
		T.expect(TutorialRules.pickBeltItem(items, 100, 0, 0, 1, beltCfg)).toBe(1) -- only 10 studs closer
		local farther = { item(1, 25, 40, 20), item(2, 25, 10, 20) }
		T.expect(TutorialRules.pickBeltItem(farther, 100, 0, 0, 1, beltCfg)).toBe(2)
		-- a target that is no longer affordable or about to leave is dropped
		T.expect(TutorialRules.pickBeltItem({ item(1, 500, 0, 20), item(2, 25, 30, 20) }, 100, 0, 0, 1, beltCfg))
			.toBe(2)
		T.expect(TutorialRules.pickBeltItem({ item(1, 25, 0, 2), item(2, 25, 30, 20) }, 100, 0, 0, 1, beltCfg)).toBe(2)
	end)
	T.it("breaks distance ties by item id", function()
		local items = { item(7, 25, 10, 20), item(4, 25, -10, 20) }
		T.expect(TutorialRules.pickBeltItem(items, 100, 0, 0, nil, beltCfg)).toBe(4)
	end)
	T.it("points at the occupied podium with the most cash to collect", function()
		T.expect(TutorialRules.pickCollectPodium({
			{ index = 1, occupied = true, stored = 3 },
			{ index = 2, occupied = false, stored = 50 },
			{ index = 3, occupied = true, stored = 9 },
		})).toBe(3)
		T.expect(TutorialRules.pickCollectPodium({
			{ index = 4, occupied = true, stored = 0 },
			{ index = 2, occupied = true, stored = 0 },
		})).toBe(2)
		T.expect(TutorialRules.pickCollectPodium({ { index = 1, occupied = false, stored = 0 } })).toBeNil()
	end)
end)

T.describe("Config/Tutorial", function()
	T.it("passes validation", function()
		local problems = TutorialRules.validate(Tutorial)
		if #problems > 0 then
			error(table.concat(problems, "; "))
		end
	end)
	T.it("validation catches bad values", function()
		local bad = config()
		bad.reward = -1
		bad.steps = {
			{ id = "buy", timeoutSeconds = 0 },
			{ id = "buy", unavailableSeconds = 0 / 0 },
			{ id = "dance" :: any },
		}
		-- reward, timeout, duplicate, unavailableSeconds, unknown id
		T.expect(#TutorialRules.validate(bad)).toBe(5)
	end)
	T.it("every step has a short banner line in Theme.text", function()
		local text = (Theme.text :: any) :: { [string]: string }
		for _, step in Tutorial.steps do
			local key = TutorialRules.TEXT_KEYS[step.id]
			if key == nil or type(text[key]) ~= "string" then
				error(`tutorial step {step.id} has no banner text (key {tostring(key)})`)
			end
			-- "the loop must be understood in 10 seconds": one short line, no text walls
			T.expect(#text[key]).toBeAtMost(50)
		end
	end)
	T.it("the shipped tutorial covers the whole loop and can always end", function()
		local ids: { string } = {}
		for _, step in Tutorial.steps do
			table.insert(ids, step.id)
		end
		T.expect(ids).toEqual({ "buy", "collect", "lock", "steal" })
		-- the steps that depend on other players or a cooldown must be able to end on their own
		T.expect(Tutorial.steps[3].unavailableSeconds).toBe(20)
		T.expect(Tutorial.steps[4].timeoutSeconds).toBe(90)
		T.expect(Tutorial.reward).toBeAtMost(1000) -- a nice moment, not a shortcut (BALANCE.md)
	end)
end)

return nil
