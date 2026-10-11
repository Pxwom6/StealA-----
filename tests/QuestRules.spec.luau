--!strict
local T = require("./TestKit")
local QuestRules = require("../src/shared/Logic/QuestRules")
local DailyStreak = require("../src/shared/Logic/DailyStreak")
local Types = require("../src/shared/Types")

local cfg: Types.QuestsConfig = {
	slots = { "easy", "easy", "hard" },
	pool = {
		{ id = "buy", kind = "beltPurchase", difficulty = "easy", textKey = "t", target = 5 },
		{ id = "collect", kind = "collect", difficulty = "easy", textKey = "t", incomeSeconds = 300, minimum = 250 },
		{ id = "sell", kind = "sell", difficulty = "easy", textKey = "t", target = 2 },
		{ id = "lock", kind = "lock", difficulty = "easy", textKey = "t", target = 2 },
		{ id = "steal", kind = "steal", difficulty = "hard", textKey = "t", target = 1 },
		{ id = "buy_rare", kind = "beltPurchase", difficulty = "hard", textKey = "t", target = 1, minRarity = "Rare" },
		{ id = "discover", kind = "discover", difficulty = "hard", textKey = "t", target = 1 },
	},
	rewards = {
		easy = { incomeSeconds = 180, minimum = 250 },
		hard = { incomeSeconds = 600, minimum = 1000 },
	},
	allDoneBonus = { incomeSeconds = 300, minimum = 500 },
}
local byId = QuestRules.index(cfg.pool)
local rarityOrders = { Common = 1, Rare = 3, Epic = 4 }
local DAY = DailyStreak.dayIndex(1767312000) -- 2026-01-02 UTC

local function ids(slots: { Types.QuestSlot }): { string }
	local result: { string } = {}
	for _, slot in slots do
		table.insert(result, slot.id)
	end
	return result
end

-- Claims quest `index`; returns only whether that claim finished the day (all-done bonus due).
local function finishesDay(state: Types.QuestState, index: number): boolean
	local _, allDone = QuestRules.claim(state, index, byId)
	return allDone
end

-- Claims quest `index`; returns only why it was refused (nil when it paid).
local function refusalOf(state: Types.QuestState, index: number): string?
	local _, _, refusal = QuestRules.claim(state, index, byId)
	return refusal
end

local function newState(): Types.QuestState
	return { day = -1, list = {}, bonusClaimed = false }
end

-- A state with today's three quests set to exactly these ids (targets from the pool, no income).
local function stateWith(questIds: { string }): Types.QuestState
	local state = newState()
	state.day = DAY
	for _, id in questIds do
		table.insert(state.list, { id = id, target = QuestRules.target(byId[id], 0), progress = 0, claimed = false })
	end
	return state
end

T.describe("QuestRules rolling", function()
	T.it("is deterministic per player and day: every server rolls the same quests", function()
		for _, userId in { 1, 42, 123456789, 9876543210123, -1, -2 } do
			local a = QuestRules.generate(userId, DAY, cfg, 100)
			local b = QuestRules.generate(userId, DAY, cfg, 100)
			T.expect(a).toEqual(b)
		end
	end)

	T.it("rolls two easy quests then one hard one, never the same quest or kind twice", function()
		for userId = 1, 200 do
			local slots = QuestRules.generate(userId, DAY + userId % 7, cfg, 0)
			T.expect(#slots).toBe(3)
			T.expect(byId[slots[1].id].difficulty).toBe("easy")
			T.expect(byId[slots[2].id].difficulty).toBe("easy")
			T.expect(byId[slots[3].id].difficulty).toBe("hard")
			local kinds: { [string]: boolean } = {}
			for _, slot in slots do
				local kind = byId[slot.id].kind
				T.expect(kinds[kind]).toBeNil()
				kinds[kind] = true
				T.expect(slot.progress).toBe(0)
				T.expect(slot.claimed).toBe(false)
			end
		end
	end)

	T.it("varies between days and players, and covers the whole pool", function()
		local seen: { [string]: boolean } = {}
		local sameAsDayOne = 0
		local first = ids(QuestRules.generate(77, DAY, cfg, 0))
		for day = DAY, DAY + 59 do
			local list = ids(QuestRules.generate(77, day, cfg, 0))
			for _, id in list do
				seen[id] = true
			end
			if table.concat(list, ",") == table.concat(first, ",") then
				sameAsDayOne += 1
			end
		end
		for _, def in cfg.pool do
			T.expect(seen[def.id]).toBe(true)
		end
		T.expect(sameAsDayOne).toBeLessThan(15) -- 36 possible lists: day one's comes back now and then, not daily
		local differentPlayers = 0
		for userId = 1, 30 do
			local list = table.concat(ids(QuestRules.generate(userId, DAY, cfg, 0)), ",")
			if list ~= table.concat(ids(QuestRules.generate(userId + 1, DAY, cfg, 0)), ",") then
				differentPlayers += 1
			end
		end
		T.expect(differentPlayers).toBeGreaterThan(15)
	end)

	T.it("a salt re-rolls (Studio /quests reset) and the seed handles any UserId", function()
		local rerolled = 0
		local base = table.concat(ids(QuestRules.generate(5, DAY, cfg, 0)), ",")
		for salt = 1, 20 do
			if table.concat(ids(QuestRules.generate(5, DAY, cfg, 0, salt)), ",") ~= base then
				rerolled += 1
			end
		end
		T.expect(rerolled).toBeGreaterThan(5)
		for _, userId in { 0, -1, 2 ^ 40 + 3, 0 / 0, math.huge } do
			local seed = QuestRules.seed(userId, DAY)
			T.expect(seed >= 0 and seed < 2 ^ 32 and seed == math.floor(seed)).toBe(true)
		end
		T.expect(QuestRules.seed(2 ^ 32 + 1, DAY) ~= QuestRules.seed(1, DAY)).toBe(true)
	end)

	T.it("falls back to a repeated kind (never a repeated quest) when the pool runs short", function()
		local small: Types.QuestsConfig = table.clone(cfg)
		small.pool = {
			{ id = "a", kind = "sell", difficulty = "easy", textKey = "t", target = 1 },
			{ id = "b", kind = "sell", difficulty = "easy", textKey = "t", target = 2 },
		}
		small.slots = { "easy", "easy", "easy", "hard" }
		local slots = QuestRules.generate(3, DAY, small, 0)
		local list = ids(slots)
		table.sort(list)
		T.expect(list).toEqual({ "a", "b" })
	end)

	T.it("sizes collect targets from steady income when rolled, with a minimum", function()
		local collect = byId.collect
		T.expect(QuestRules.target(collect, 0)).toBe(250)
		T.expect(QuestRules.target(collect, 0 / 0)).toBe(250)
		T.expect(QuestRules.target(collect, 1234)).toBe(370000) -- 370,200 rounded to 2 digits
		T.expect(QuestRules.target(byId.buy, 1e9)).toBe(5)
	end)
end)

T.describe("QuestRules day reset", function()
	T.it("rolls when the saved day is earlier (or never rolled), keeps today's and a later day's", function()
		local state = newState()
		T.expect(QuestRules.isStale(state, DAY)).toBe(true)
		QuestRules.roll(state, 9, DAY, cfg, 0)
		T.expect(state.day).toBe(DAY)
		T.expect(#state.list).toBe(3)
		T.expect(QuestRules.isStale(state, DAY)).toBe(false)
		T.expect(QuestRules.isStale(state, DAY + 1)).toBe(true)
		-- Another server's clock ran ahead: the later day's quests are kept, never rolled back.
		state.day = DAY + 1
		T.expect(QuestRules.isStale(state, DAY)).toBe(false)
		-- ...but a day far in the future (clock glitch / damaged save) would freeze quests, so it re-rolls.
		state.day = DAY + 30
		T.expect(QuestRules.isStale(state, DAY)).toBe(true)
	end)

	T.it("a new day starts progress, claims and the bonus over", function()
		local state = stateWith({ "buy", "sell", "steal" })
		state.list[1].progress = 5
		state.list[1].claimed = true
		state.bonusClaimed = true
		QuestRules.roll(state, 9, DAY + 1, cfg, 0)
		T.expect(state.day).toBe(DAY + 1)
		T.expect(state.bonusClaimed).toBe(false)
		for _, slot in state.list do
			T.expect(slot.progress).toBe(0)
			T.expect(slot.claimed).toBe(false)
		end
		T.expect(state.list).toEqual(QuestRules.generate(9, DAY + 1, cfg, 0))
	end)
end)

T.describe("QuestRules progress", function()
	T.it("counts only the events each quest asks for, capped at the target", function()
		local state = stateWith({ "buy", "collect", "steal" })
		local changed, finished =
			QuestRules.apply(state, { kind = "beltPurchase", rarityOrder = 1 }, byId, rarityOrders)
		T.expect(changed).toBe(true)
		T.expect(finished).toEqual({})
		T.expect(state.list[1].progress).toBe(1)
		T.expect(state.list[2].progress).toBe(0)
		changed = QuestRules.apply(state, { kind = "sell" }, byId, rarityOrders)
		T.expect(changed).toBe(false)
		QuestRules.apply(state, { kind = "collect", amount = 100.7 }, byId, rarityOrders)
		T.expect(state.list[2].progress).toBe(100)
		changed, finished = QuestRules.apply(state, { kind = "collect", amount = 1000 }, byId, rarityOrders)
		T.expect(changed).toBe(true)
		T.expect(state.list[2].progress).toBe(250)
		T.expect(finished).toEqual({ 2 })
		-- Finished quests stop counting; garbage amounts count nothing.
		changed = QuestRules.apply(state, { kind = "collect", amount = 5 }, byId, rarityOrders)
		T.expect(changed).toBe(false)
		QuestRules.apply(state, { kind = "beltPurchase", rarityOrder = 1 }, byId, rarityOrders)
		T.expect(QuestRules.progressFor(byId.collect, { kind = "collect", amount = 0 / 0 }, rarityOrders)).toBe(0)
		T.expect(QuestRules.progressFor(byId.collect, { kind = "collect", amount = -50 }, rarityOrders)).toBe(0)
		T.expect(QuestRules.progressFor(byId.collect, { kind = "collect" }, rarityOrders)).toBe(0)
		changed, finished = QuestRules.apply(state, { kind = "steal" }, byId, rarityOrders)
		T.expect(changed).toBe(true)
		T.expect(finished).toEqual({ 3 })
	end)

	T.it("a minimum rarity only counts Snacklings that rare or rarer", function()
		local state = stateWith({ "buy_rare" })
		T.expect((QuestRules.apply(state, { kind = "beltPurchase", rarityOrder = 1 }, byId, rarityOrders))).toBe(false)
		T.expect((QuestRules.apply(state, { kind = "beltPurchase" }, byId, rarityOrders))).toBe(false)
		local _, finished = QuestRules.apply(state, { kind = "beltPurchase", rarityOrder = 4 }, byId, rarityOrders)
		T.expect(finished).toEqual({ 1 })
		-- A minRarity the config doesn't know counts nothing.
		local odd: Types.QuestDef = table.clone(byId.buy_rare)
		odd.minRarity = "Nope"
		T.expect(QuestRules.progressFor(odd, { kind = "beltPurchase", rarityOrder = 99 }, rarityOrders)).toBe(0)
	end)

	T.it("a quest the config no longer knows never progresses or pays", function()
		local state = stateWith({ "buy" })
		state.list[1].id = "removed_quest"
		state.list[1].progress = state.list[1].target
		T.expect((QuestRules.apply(state, { kind = "beltPurchase" }, byId, rarityOrders))).toBe(false)
		T.expect(QuestRules.isClaimable(state.list[1], byId)).toBe(false)
		local def, _, refusal = QuestRules.claim(state, 1, byId)
		T.expect(def).toBeNil()
		T.expect(refusal).toBe("unknown")
	end)
end)

T.describe("QuestRules claiming", function()
	T.it("pays a finished quest exactly once", function()
		local state = stateWith({ "buy", "sell", "steal" })
		local def, allDone, refusal = QuestRules.claim(state, 1, byId)
		T.expect(def).toBeNil()
		T.expect(refusal).toBe("incomplete")
		state.list[1].progress = 5
		def, allDone, refusal = QuestRules.claim(state, 1, byId)
		T.expect(def and def.id).toBe("buy")
		T.expect(allDone).toBe(false)
		T.expect(refusal).toBeNil()
		T.expect(state.list[1].claimed).toBe(true)
		def, allDone, refusal = QuestRules.claim(state, 1, byId)
		T.expect(def).toBeNil()
		T.expect(allDone).toBe(false)
		T.expect(refusal).toBe("claimed")
		T.expect((QuestRules.claim(state, 4, byId))).toBeNil()
		T.expect(refusalOf(state, 0)).toBe("missing")
	end)

	T.it("the claim that finishes the day also pays the all-done bonus, once", function()
		local state = stateWith({ "buy", "sell", "steal" })
		for _, slot in state.list do
			slot.progress = slot.target
		end
		T.expect(finishesDay(state, 3)).toBe(false)
		T.expect(finishesDay(state, 1)).toBe(false)
		T.expect(finishesDay(state, 2)).toBe(true)
		T.expect(state.bonusClaimed).toBe(true)
		-- Nothing left to pay, whatever is retried.
		for index = 1, 3 do
			T.expect((QuestRules.claim(state, index, byId))).toBeNil()
		end
		-- A day whose bonus was already paid never pays it again (e.g. a list changed under it).
		local paid = stateWith({ "buy" })
		paid.bonusClaimed = true
		paid.list[1].progress = 5
		T.expect(finishesDay(paid, 1)).toBe(false)
	end)

	T.it("sizes rewards and the bonus from steady income, with minimums", function()
		T.expect(QuestRules.reward("easy", 0, cfg)).toBe(250)
		T.expect(QuestRules.reward("easy", 1000, cfg)).toBe(180000)
		T.expect(QuestRules.reward("hard", 1, cfg)).toBe(1000)
		T.expect(QuestRules.reward("hard", 1000, cfg)).toBe(600000)
		T.expect(QuestRules.reward("legendary", 1000, cfg)).toBe(0)
		T.expect(QuestRules.bonus(0, cfg)).toBe(500)
		T.expect(QuestRules.bonus(1000, cfg)).toBe(300000)
		T.expect(QuestRules.bonus(0 / 0, cfg)).toBe(500)
	end)

	T.it("the view shows progress, live rewards, what is claimable and when quests reset", function()
		local state = stateWith({ "buy", "sell", "steal" })
		state.list[2].progress = 2
		local view = QuestRules.view(state, byId, cfg, 1000, DAY)
		T.expect(view.claimable).toBe(1)
		T.expect(view.list[1]).toEqual({ id = "buy", progress = 0, target = 5, claimed = false, reward = 180000 })
		T.expect(view.list[3].reward).toBe(600000)
		T.expect(view.bonus).toBe(300000)
		T.expect(view.bonusClaimed).toBe(false)
		T.expect(view.resetsAt).toBe((DAY + 1) * 86400)
		QuestRules.claim(state, 2, byId)
		T.expect(QuestRules.view(state, byId, cfg, 1000, DAY).claimable).toBe(0)
	end)
end)

T.describe("QuestRules config validation", function()
	T.it("accepts a valid config and reports bad ones", function()
		local text = { t = "x" }
		T.expect(QuestRules.validate(cfg, { Rare = true }, text)).toEqual({})
		local bad: Types.QuestsConfig = {
			slots = { "easy", "hard", "hard" },
			pool = {
				{ id = "dup", kind = "sell", difficulty = "easy", textKey = "t", target = 0 },
				{ id = "dup", kind = "sell", difficulty = "easy", textKey = "missing", target = 1.5 },
				{ id = "c", kind = "collect", difficulty = "hard", textKey = "t" },
				{ id = "r", kind = "sell", difficulty = "hard", textKey = "t", target = 1, minRarity = "Rare" },
				{ id = "bad id!", kind = "nope" :: any, difficulty = "medium" :: any, textKey = "t", target = 1 },
			},
			rewards = { easy = { incomeSeconds = 1, minimum = 0 } },
			allDoneBonus = { incomeSeconds = -1, minimum = 5 },
		}
		local problems = QuestRules.validate(bad, { Rare = true }, text)
		local joined = table.concat(problems, "\n")
		for _, expected in
			{
				"duplicate quest id dup",
				"quest dup needs a whole target",
				"text missing is not in Theme.text",
				"collect quest c needs incomeSeconds",
				"collect quest c needs a minimum",
				"minRarity only applies to beltPurchase",
				"must be short",
				"unknown kind nope",
				"unknown difficulty medium",
				"rewards.easy: minimum",
				"rewards.hard is missing",
				"no reward for medium quests",
				"allDoneBonus: incomeSeconds",
			}
		do
			T.expect(string.find(joined, expected, 1, true) ~= nil).toBe(true)
		end
		-- Two hard slots, two hard quests: fine; three would not be.
		bad.slots = { "hard", "hard", "hard" }
		T.expect(string.find(table.concat(QuestRules.validate(bad, {}, text), "\n"), "3 hard slot(s)", 1, true) ~= nil)
			.toBe(true)
	end)
end)

return nil
