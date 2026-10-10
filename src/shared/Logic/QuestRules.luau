--!strict
--[[
	Daily quest rules, on the saved `data.quests` (Types.QuestState) and Config/Quests.

	* Rolling: one quest per configured slot (e.g. easy, easy, hard), picked from the pool by a hash of the player's
	  UserId and the UTC day (DailyStreak.dayIndex), so every server rolls the same quests for that player that day and
	  rejoining never re-rolls. Within a day no quest repeats, and two quests of the same kind are only picked together
	  when no other kind of that difficulty is left. A "collect" target is fixed at roll time from the steady income.
	* Day reset: the list belongs to `state.day`; a later day replaces it (`isStale` / `roll`). A saved day AFTER today
	  (another server's clock ran ahead) is kept as it is: never rolled back, never paid twice.
	* Progress: `apply` adds a gameplay event (what the server saw) to every unfinished quest it counts for, capped at
	  the target.
	* Claiming: `claim` marks the quest claimed (and the all-done bonus, with the last quest) before the caller pays,
	  so a quest can never pay twice. Rewards are sized like cash packs from the steady income.

	Pure: no Roblox APIs (bit32 is plain Luau).
]]

local Types = require("../Types")
local EconomyMath = require("./EconomyMath")

export type Config = Types.QuestsConfig
export type QuestDef = Types.QuestDef
export type QuestSlot = Types.QuestSlot
export type QuestState = Types.QuestState
export type QuestEvent = Types.QuestEvent

-- Why a claim was refused.
export type ClaimRefusal = "missing" | "claimed" | "incomplete" | "unknown"

local SECONDS_PER_DAY = 86400
local TWO_32 = 4294967296

local QuestRules = {}

QuestRules.KINDS = table.freeze({
	beltPurchase = true,
	collect = true,
	sell = true,
	lock = true,
	steal = true,
	discover = true,
}) :: { [string]: boolean }

QuestRules.DIFFICULTIES = table.freeze({ "easy", "hard" }) :: { string }

-- Hashing ------------------------------------------------------------------------------------------------------

local function finite(value: number, fallback: number): number
	if value ~= value or value == math.huge or value == -math.huge then
		return fallback
	end
	return value
end

-- a * b mod 2^32 for 32-bit unsigned a and b, exactly (a plain product can exceed 2^53).
local function mul32(a: number, b: number): number
	local aLo, aHi = a % 65536, a // 65536
	local bLo, bHi = b % 65536, b // 65536
	return (((aHi * bLo + aLo * bHi) % 65536) * 65536 + aLo * bLo) % TWO_32
end

-- MurmurHash3's 32-bit finaliser: neighbouring inputs (consecutive days, user ids) give unrelated outputs.
local function mix(value: number): number
	local h = value % TWO_32
	h = bit32.bxor(h, bit32.rshift(h, 16))
	h = mul32(h, 0x85EBCA6B)
	h = bit32.bxor(h, bit32.rshift(h, 13))
	h = mul32(h, 0xC2B2AE35)
	h = bit32.bxor(h, bit32.rshift(h, 16))
	return h
end

-- The seed of a player's quests for a day: any UserId (Studio test players are negative, real ones can pass 2^32).
-- `salt` re-rolls (Studio /quests reset); 0 for the normal daily roll.
function QuestRules.seed(userId: number, day: number, salt: number?): number
	local id = math.floor(finite(userId, 0))
	local h = mix(bit32.bxor(id % TWO_32, 0x9E3779B9))
	h = mix(bit32.bxor(h, (id // TWO_32) % TWO_32))
	h = mix(bit32.bxor(h, math.floor(finite(day, 0)) % TWO_32))
	return mix(bit32.bxor(h, math.floor(finite(salt or 0, 0)) % TWO_32))
end

-- A deterministic stream of 32-bit integers from a seed (a counter run through `mix`).
local function stream(seed: number): () -> number
	local state = seed
	return function(): number
		state = (state + 0x6D2B79F5) % TWO_32
		return mix(state)
	end
end

-- Config lookups ------------------------------------------------------------------------------------------------

-- Quest definitions by id.
function QuestRules.index(pool: { QuestDef }): { [string]: QuestDef }
	local byId: { [string]: QuestDef } = {}
	for _, def in pool do
		byId[def.id] = def
	end
	return byId
end

-- The quest's target: how many times, or for "collect" an amount of cash sized from the steady income.
function QuestRules.target(def: QuestDef, steadyIncome: number): number
	if def.kind == "collect" then
		return math.max(
			1,
			EconomyMath.cashPackAmount(
				steadyIncome,
				{ incomeSeconds = def.incomeSeconds or 0, minimum = def.minimum or 1 }
			)
		)
	end
	return math.max(1, math.floor(def.target or 1))
end

-- Cash for claiming a quest of this difficulty right now.
function QuestRules.reward(difficulty: string, steadyIncome: number, cfg: Config): number
	local settings = cfg.rewards[difficulty]
	if settings == nil then
		return 0
	end
	return EconomyMath.cashPackAmount(steadyIncome, settings)
end

-- Cash for finishing every quest of the day.
function QuestRules.bonus(steadyIncome: number, cfg: Config): number
	return EconomyMath.cashPackAmount(steadyIncome, cfg.allDoneBonus)
end

-- Rolling -------------------------------------------------------------------------------------------------------

-- The day's quests for a player, one per slot (fewer if the pool runs out), with their targets.
function QuestRules.generate(
	userId: number,
	day: number,
	cfg: Config,
	steadyIncome: number,
	salt: number?
): { QuestSlot }
	local nextRandom = stream(QuestRules.seed(userId, day, salt))
	local usedIds: { [string]: boolean } = {}
	local usedKinds: { [string]: boolean } = {}
	local slots: { QuestSlot } = {}
	for _, difficulty in cfg.slots do
		local candidates: { QuestDef } = {}
		for _, def in cfg.pool do
			if def.difficulty == difficulty and not usedIds[def.id] and not usedKinds[def.kind] then
				table.insert(candidates, def)
			end
		end
		if #candidates == 0 then
			-- Every kind of this difficulty is taken already: a repeated kind, but never a repeated quest.
			for _, def in cfg.pool do
				if def.difficulty == difficulty and not usedIds[def.id] then
					table.insert(candidates, def)
				end
			end
		end
		if #candidates > 0 then
			local def = candidates[nextRandom() % #candidates + 1]
			usedIds[def.id] = true
			usedKinds[def.kind] = true
			table.insert(
				slots,
				{ id = def.id, target = QuestRules.target(def, steadyIncome), progress = 0, claimed = false }
			)
		end
	end
	return slots
end

-- True when the saved quests belong to an earlier day than `today` (or were never rolled).
function QuestRules.isStale(state: QuestState, today: number): boolean
	return state.day < today
end

-- Replaces the quests with `day`'s (progress, claims and the bonus start over).
function QuestRules.roll(
	state: QuestState,
	userId: number,
	day: number,
	cfg: Config,
	steadyIncome: number,
	salt: number?
)
	state.day = day
	state.list = QuestRules.generate(userId, day, cfg, steadyIncome, salt)
	state.bonusClaimed = false
end

-- Progress --------------------------------------------------------------------------------------------------------

-- How much `event` adds to a quest of this definition (0 when it doesn't count for it). `rarityOrders` maps rarity ids
-- to their order (for minRarity); an unknown minRarity counts nothing.
function QuestRules.progressFor(def: QuestDef, event: QuestEvent, rarityOrders: { [string]: number }): number
	if def.kind ~= event.kind then
		return 0
	end
	if def.kind == "collect" then
		local amount = finite(event.amount or 0, 0)
		return math.max(0, math.floor(amount))
	end
	if def.minRarity ~= nil then
		local needed = rarityOrders[def.minRarity]
		if needed == nil or (event.rarityOrder or 0) < needed then
			return 0
		end
	end
	return 1
end

-- Adds an event to every unfinished, unclaimed quest it counts for. Returns whether anything changed and the
-- positions of the quests it just finished.
function QuestRules.apply(
	state: QuestState,
	event: QuestEvent,
	byId: { [string]: QuestDef },
	rarityOrders: { [string]: number }
): (boolean, { number })
	local changed = false
	local finished: { number } = {}
	for index, slot in state.list do
		local def = byId[slot.id]
		if def == nil or slot.claimed or slot.progress >= slot.target then
			continue
		end
		local add = QuestRules.progressFor(def, event, rarityOrders)
		if add > 0 then
			slot.progress = math.min(slot.target, slot.progress + add)
			changed = true
			if slot.progress >= slot.target then
				table.insert(finished, index)
			end
		end
	end
	return changed, finished
end

-- Claiming --------------------------------------------------------------------------------------------------------

function QuestRules.isClaimable(slot: QuestSlot, byId: { [string]: QuestDef }): boolean
	return not slot.claimed and slot.progress >= slot.target and byId[slot.id] ~= nil
end

-- Claims quest number `index`. On success marks it claimed and returns its definition, plus true when this claim
-- finished the day (every quest claimed: the all-done bonus is due and is marked paid). Pay both right away, with no
-- yield in between: a quest and the bonus can only ever pay once.
function QuestRules.claim(
	state: QuestState,
	index: number,
	byId: { [string]: QuestDef }
): (QuestDef?, boolean, ClaimRefusal?)
	local slot = state.list[index]
	if slot == nil then
		return nil, false, "missing"
	elseif slot.claimed then
		return nil, false, "claimed"
	elseif slot.progress < slot.target then
		return nil, false, "incomplete"
	end
	local def = byId[slot.id]
	if def == nil then
		return nil, false, "unknown"
	end
	slot.claimed = true
	local allDone = not state.bonusClaimed
	for _, other in state.list do
		if not other.claimed then
			allDone = false
		end
	end
	if allDone then
		state.bonusClaimed = true
	end
	return def, allDone, nil
end

-- View ----------------------------------------------------------------------------------------------------------

-- What the Rewards panel shows. `today` = DailyStreak.dayIndex(now).
function QuestRules.view(
	state: QuestState,
	byId: { [string]: QuestDef },
	cfg: Config,
	steadyIncome: number,
	today: number
): Types.QuestsView
	local list: { Types.QuestSlotView } = {}
	local claimable = 0
	for _, slot in state.list do
		local def = byId[slot.id]
		if QuestRules.isClaimable(slot, byId) then
			claimable += 1
		end
		table.insert(list, {
			id = slot.id,
			progress = slot.progress,
			target = slot.target,
			claimed = slot.claimed,
			reward = if def then QuestRules.reward(def.difficulty, steadyIncome, cfg) else 0,
		})
	end
	return {
		list = list,
		bonus = QuestRules.bonus(steadyIncome, cfg),
		bonusClaimed = state.bonusClaimed,
		resetsAt = (math.max(state.day, today) + 1) * SECONDS_PER_DAY,
		claimable = claimable,
	}
end

-- Validation ------------------------------------------------------------------------------------------------------

-- Problems with Config/Quests (an empty list means valid). `rarityIds`: known rarity ids; `text`: Theme.text.
function QuestRules.validate(cfg: Config, rarityIds: { [string]: boolean }, text: { [string]: string }): { string }
	local problems: { string } = {}
	local function problem(message: string)
		table.insert(problems, message)
	end
	local function checkReward(name: string, reward: Types.IncomeReward?)
		if reward == nil then
			problem(`{name} is missing`)
			return
		end
		if not (reward.incomeSeconds >= 0 and reward.incomeSeconds < math.huge) then
			problem(`{name}: incomeSeconds must be a number >= 0`)
		end
		if not (reward.minimum >= 1 and reward.minimum < math.huge) then
			problem(`{name}: minimum must be at least 1`)
		end
	end

	if #cfg.slots == 0 then
		problem("slots must not be empty")
	end
	local slotsPerDifficulty: { [string]: number } = {}
	for _, difficulty in cfg.slots do
		slotsPerDifficulty[difficulty] = (slotsPerDifficulty[difficulty] or 0) + 1
	end

	local ids: { [string]: boolean } = {}
	local perDifficulty: { [string]: number } = {}
	for _, def in cfg.pool do
		local id = def.id
		if ids[id] then
			problem(`duplicate quest id {id}`)
		end
		ids[id] = true
		if string.match(id, "^[%w_]+$") == nil or #id > 40 then
			problem(`quest id {id} must be short and alphanumeric/underscore`)
		end
		if not QuestRules.KINDS[def.kind] then
			problem(`quest {id} has unknown kind {def.kind}`)
		end
		if table.find(QuestRules.DIFFICULTIES, def.difficulty) == nil then
			problem(`quest {id} has unknown difficulty {def.difficulty}`)
		end
		perDifficulty[def.difficulty] = (perDifficulty[def.difficulty] or 0) + 1
		if type(text[def.textKey]) ~= "string" then
			problem(`quest {id} text {def.textKey} is not in Theme.text`)
		end
		if def.kind == "collect" then
			local seconds = def.incomeSeconds
			if seconds == nil or not (seconds > 0 and seconds < math.huge) then
				problem(`collect quest {id} needs incomeSeconds > 0`)
			end
			local minimum = def.minimum
			if minimum == nil or not (minimum >= 1 and minimum < math.huge) then
				problem(`collect quest {id} needs a minimum >= 1`)
			end
		else
			local target = def.target
			if target == nil or target < 1 or target ~= math.floor(target) or target > 1000 then
				problem(`quest {id} needs a whole target between 1 and 1000`)
			end
		end
		if def.minRarity ~= nil then
			if def.kind ~= "beltPurchase" then
				problem(`quest {id}: minRarity only applies to beltPurchase quests`)
			elseif not rarityIds[def.minRarity] then
				problem(`quest {id} has unknown minRarity {def.minRarity}`)
			end
		end
	end
	for difficulty, count in slotsPerDifficulty do
		if (perDifficulty[difficulty] or 0) < count then
			problem(
				`{count} {difficulty} slot(s) a day but only {perDifficulty[difficulty] or 0} {difficulty} quest(s)`
			)
		end
		checkReward(`rewards.{difficulty}`, cfg.rewards[difficulty])
	end
	for difficulty in perDifficulty do
		if cfg.rewards[difficulty] == nil then
			problem(`no reward for {difficulty} quests`)
		end
	end
	checkReward("allDoneBonus", cfg.allDoneBonus)
	return problems
end

return QuestRules
