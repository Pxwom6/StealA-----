--!strict
--[[
	Lucky Spin rules (Config/Spin) on the saved `data.spin` (Types.SpinState): whether a spin is available (the free
	one first, then a banked one), using one, banking spins from gifts, picking the prize by weight, and validation.
	Pure: no Roblox APIs; random numbers come in as a function returning [0, 1).
]]

local GiftRules = require("./GiftRules")
local Types = require("../Types")

type SpinState = Types.SpinState
type SpinConfig = Types.SpinConfig
type SpinSegment = Types.SpinSegment

local SpinRules = {}

export type Source = "free" | "banked"

-- The highest Config/Spin.paidBankFull may go (a bank that full takes minutes to spin through).
SpinRules.MAX_PAID_BANK_FULL = 200
-- Receipts that could still land on a bank at paidBankFull (retries building up while a player is away, several
-- prompts open at once): validatePacks keeps that many of the biggest pack under the save's limit.
SpinRules.RECEIPT_BACKLOG = 50

-- Which spin a player would use now: the free one when it is ready, else a banked one; nil when there is none.
function SpinRules.source(state: SpinState, now: number): Source?
	if now >= state.nextFreeAt then
		return "free"
	elseif state.spins > 0 then
		return "banked"
	end
	return nil
end

-- Uses one spin from `source` (SpinRules.source): the free one starts its timer again, a banked one is spent.
function SpinRules.consume(state: SpinState, source: Source, now: number, config: SpinConfig)
	if source == "free" then
		state.nextFreeAt = now + config.freeEverySeconds
	else
		state.spins = math.max(0, state.spins - 1)
	end
	state.total += 1
end

-- Banks `count` spins up to config.maxBanked; returns how many did not fit (the caller pays those as cash).
function SpinRules.bank(state: SpinState, count: number, config: SpinConfig): number
	local room = math.max(0, config.maxBanked - state.spins)
	local banked = math.min(room, count)
	state.spins += banked
	return count - banked
end

-- Banks every spin a Lucky Spin pack paid for, past maxBanked and past paidBankFull if need be: a purchase is never
-- lost or clipped. (Buying is refused while the bank holds paidBankFull or more, StoreRules.purchaseRefusal, but two
-- receipts can still land together; validatePacks keeps far more than that under the save's limit.)
function SpinRules.bankPaid(state: SpinState, count: number)
	state.spins += math.max(0, math.floor(count))
end

-- Each segment's chance (weight / total), in order.
function SpinRules.chances(segments: { SpinSegment }): { number }
	local total = 0
	for _, segment in segments do
		total += math.max(0, segment.weight)
	end
	local chances: { number } = {}
	for _, segment in segments do
		table.insert(chances, if total > 0 then math.max(0, segment.weight) / total else 0)
	end
	return chances
end

-- Picks a segment index by weight. Draws exactly one number.
function SpinRules.pick(segments: { SpinSegment }, random: () -> number): number
	local roll = random()
	local running = 0
	local chances = SpinRules.chances(segments)
	for index, chance in chances do
		running += chance
		if roll < running then
			return index
		end
	end
	return #segments
end

-- Problems with Config/Spin (an empty list means valid). `mutations` are the known mutation ids.
function SpinRules.validate(config: SpinConfig, mutations: { [string]: any }): { string }
	local problems: { string } = {}
	if not (config.freeEverySeconds >= 3600 and config.freeEverySeconds <= 7 * 86400) then
		table.insert(problems, "freeEverySeconds must be between an hour and a week")
	end
	if not (config.maxBanked >= 1 and config.maxBanked <= 1000 and config.maxBanked % 1 == 0) then
		table.insert(problems, "maxBanked must be a whole number from 1 to 1000")
	end
	if
		not (
			config.paidBankFull >= config.maxBanked
			and config.paidBankFull <= SpinRules.MAX_PAID_BANK_FULL
			and config.paidBankFull % 1 == 0
		)
	then
		table.insert(problems, `paidBankFull must be a whole number from maxBanked to {SpinRules.MAX_PAID_BANK_FULL}`)
	end
	for _, message in
		GiftRules.rewardProblems({
			kind = "cash",
			incomeSeconds = config.bankedOverflow.incomeSeconds,
			minimum = config.bankedOverflow.minimum,
		}, "bankedOverflow", mutations, false)
	do
		table.insert(problems, message)
	end
	if #config.segments < 2 or #config.segments > 12 then
		table.insert(problems, "the reel needs 2 to 12 segments")
	end
	local ids: { [string]: boolean } = {}
	local total = 0
	for index, segment in config.segments do
		local name = `segment {segment.id}`
		if segment.id == "" or ids[segment.id] then
			table.insert(problems, `segment {index} needs a unique id`)
		end
		ids[segment.id] = true
		if segment.label == "" or #segment.label > 14 then
			table.insert(problems, `{name} needs a label of at most 14 characters`)
		end
		if segment.icon == "" then
			table.insert(problems, `{name} needs an icon`)
		end
		if string.match(segment.color, "^#%x%x%x%x%x%x$") == nil then
			table.insert(problems, `{name} color must be #RRGGBB`)
		end
		if not (segment.weight > 0) then
			table.insert(problems, `{name} weight must be above 0`)
		else
			total += segment.weight
		end
		for _, message in GiftRules.rewardProblems(segment.reward, name, mutations, false) do
			table.insert(problems, message)
		end
	end
	if not (total > 0) then
		table.insert(problems, "the weights add up to nothing")
	end
	return problems
end

-- Problems with the Lucky Spin packs for sale (`counts`: spins per pack, Config/Monetization) given Config/Spin and
-- `saveLimit`, the most spins a save keeps (DataSchema.MAX_BANKED_SPINS): a pack's spins must never be clipped, so even
-- RECEIPT_BACKLOG of the biggest pack landing on a bank at paidBankFull stays under it.
function SpinRules.validatePacks(counts: { number }, config: SpinConfig, saveLimit: number): { string }
	local problems: { string } = {}
	local biggest = 0
	for index, count in counts do
		if not (count >= 1 and count <= 100 and count % 1 == 0) then
			table.insert(problems, `pack {index} must give a whole number of spins from 1 to 100`)
		else
			biggest = math.max(biggest, count)
		end
	end
	local worst = config.paidBankFull - 1 + SpinRules.RECEIPT_BACKLOG * biggest
	if not (worst <= saveLimit) then
		table.insert(
			problems,
			`{SpinRules.RECEIPT_BACKLOG} packs of {biggest} on a full bank reach {worst} spins, over the save's {saveLimit}`
		)
	end
	return problems
end

return SpinRules
