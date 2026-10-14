--!strict
--[[
	Playtime gift rules (Config/Gifts) on the saved `data.gifts` (Types.GiftState): which gifts today's playtime has
	unlocked, claiming one (once per day, any order), the day change, and validation (shared with the Lucky Spin's
	prizes). Pure: no Roblox APIs.
]]

local Types = require("../Types")

type GiftState = Types.GiftState
type GiftsConfig = Types.GiftsConfig
type GiftDef = Types.GiftDef
type PrizeReward = Types.PrizeReward

local GiftRules = {}

-- True when the saved gifts belong to an earlier day than `day` (a UTC day index).
function GiftRules.isStale(state: GiftState, day: number): boolean
	return state.day ~= day
end

-- Starts `day` afresh: no time played, nothing claimed.
function GiftRules.reset(state: GiftState, day: number)
	state.day = day
	state.seconds = 0
	table.clear(state.claimed)
end

-- Adds playtime (seconds, at most a day in total).
function GiftRules.addTime(state: GiftState, seconds: number)
	if seconds == seconds and seconds > 0 then
		state.seconds = math.min(86400, state.seconds + seconds)
	end
end

function GiftRules.isClaimed(state: GiftState, index: number): boolean
	return table.find(state.claimed, index) ~= nil
end

-- Whether gift `index` is unlocked by today's playtime (`seconds`, default the saved ones).
function GiftRules.isUnlocked(config: GiftsConfig, index: number, seconds: number): boolean
	local def = config.ladder[index]
	return def ~= nil and seconds >= def.minutes * 60
end

-- Seconds of play still needed for gift `index` (0 once unlocked).
function GiftRules.secondsUntil(config: GiftsConfig, index: number, seconds: number): number
	local def = config.ladder[index]
	if def == nil then
		return math.huge
	end
	return math.max(0, def.minutes * 60 - seconds)
end

-- Gifts unlocked and not claimed yet.
function GiftRules.claimable(state: GiftState, config: GiftsConfig, seconds: number?): number
	local played = seconds or state.seconds
	local count = 0
	for index in config.ladder do
		if GiftRules.isUnlocked(config, index, played) and not GiftRules.isClaimed(state, index) then
			count += 1
		end
	end
	return count
end

-- Marks gift `index` claimed and returns it, or nil when it is locked, already claimed or not a gift. The caller pays.
function GiftRules.claim(state: GiftState, config: GiftsConfig, index: number): GiftDef?
	if not GiftRules.isUnlocked(config, index, state.seconds) or GiftRules.isClaimed(state, index) then
		return nil
	end
	table.insert(state.claimed, index)
	return config.ladder[index]
end

-- Problems with one prize (a gift's or a Lucky Spin segment's); `name` starts each message. `mutations` are the
-- known mutation ids; `allowSpin` whether "spin" prizes are allowed (not on the Lucky Spin itself).
function GiftRules.rewardProblems(
	reward: PrizeReward,
	name: string,
	mutations: { [string]: any },
	allowSpin: boolean
): { string }
	local problems: { string } = {}
	local raw = reward :: any
	if raw.kind == "cash" then
		if not (type(raw.incomeSeconds) == "number" and raw.incomeSeconds > 0 and raw.incomeSeconds <= 3600) then
			table.insert(problems, `{name} incomeSeconds must be between 0 and 3600`)
		end
		if not (type(raw.minimum) == "number" and raw.minimum >= 0 and raw.minimum < math.huge) then
			table.insert(problems, `{name} minimum must be 0 or more`)
		end
	elseif raw.kind == "spin" then
		if not allowSpin then
			table.insert(problems, `{name} can't give spins`)
		elseif not (type(raw.count) == "number" and raw.count >= 1 and raw.count <= 10 and raw.count % 1 == 0) then
			table.insert(problems, `{name} count must be a whole number from 1 to 10`)
		end
	elseif raw.kind == "creature" then
		if not (type(raw.luck) == "number" and raw.luck >= 1 and raw.luck <= 10) then
			table.insert(problems, `{name} luck must be between 1 and 10`)
		end
		if raw.mutation ~= nil and mutations[raw.mutation] == nil then
			table.insert(problems, `{name} mutation {tostring(raw.mutation)} is not a mutation`)
		end
	else
		table.insert(problems, `{name} reward kind must be cash, spin or creature`)
	end
	return problems
end

-- Problems with Config/Gifts (an empty list means valid).
function GiftRules.validate(config: GiftsConfig, mutations: { [string]: any }): { string }
	local problems: { string } = {}
	if #config.ladder == 0 or #config.ladder > 32 then
		table.insert(problems, "ladder must have 1 to 32 gifts")
	end
	local previous = 0
	for index, def in config.ladder do
		local name = `gift {index}`
		if not (def.minutes > previous and def.minutes <= 24 * 60) then
			table.insert(problems, `{name} minutes must be later than the gift before and within a day`)
		end
		previous = def.minutes
		if def.icon == "" then
			table.insert(problems, `{name} needs an icon`)
		end
		for _, message in GiftRules.rewardProblems(def.reward, name, mutations, true) do
			table.insert(problems, message)
		end
	end
	return problems
end

return GiftRules
