--!strict
--[[
	Daily login reward streak, by UTC day. Claiming on consecutive days grows the streak; missing a day resets it
	to 1. Rewards cycle through the configured slots. Pure: no Roblox APIs.
]]

local Types = require("../Types")

export type DailyState = Types.DailyState
export type DailySlot = { minimum: number, incomeMinutes: number }
export type DailyStatus = {
	canClaim: boolean,
	nextStreak: number, -- the streak value the next claim will produce
	secondsUntilNext: number, -- 0 when claimable now
	today: number,
}

local SECONDS_PER_DAY = 86400

local DailyStreak = {}

function DailyStreak.dayIndex(unixSeconds: number): number
	return math.floor(unixSeconds / SECONDS_PER_DAY)
end

function DailyStreak.status(state: DailyState, now: number): DailyStatus
	local today = DailyStreak.dayIndex(now)
	if state.lastClaimDay == today then
		return {
			canClaim = false,
			nextStreak = state.streak + 1,
			secondsUntilNext = (today + 1) * SECONDS_PER_DAY - now,
			today = today,
		}
	elseif state.lastClaimDay == today - 1 then
		return { canClaim = true, nextStreak = state.streak + 1, secondsUntilNext = 0, today = today }
	elseif state.lastClaimDay > today then
		-- Saved day is in the future (clock skew). Treat as "claimed today" rather than paying again.
		return { canClaim = false, nextStreak = 1, secondsUntilNext = SECONDS_PER_DAY, today = today }
	end
	return { canClaim = true, nextStreak = 1, secondsUntilNext = 0, today = today }
end

-- Returns the new state, or nil if nothing can be claimed right now.
function DailyStreak.claim(state: DailyState, now: number): DailyState?
	local s = DailyStreak.status(state, now)
	if not s.canClaim then
		return nil
	end
	return { streak = s.nextStreak, lastClaimDay = s.today }
end

-- 1-based slot in the reward cycle for a given streak.
function DailyStreak.slot(streak: number, cycleLength: number): number
	return ((math.max(1, streak) - 1) % math.max(1, cycleLength)) + 1
end

function DailyStreak.rewardAmount(slot: DailySlot, incomePerSecond: number): number
	local income = if incomePerSecond == incomePerSecond then math.max(0, incomePerSecond) else 0
	return math.floor(math.max(slot.minimum, income * slot.incomeMinutes * 60))
end

return DailyStreak
