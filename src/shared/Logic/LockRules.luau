--!strict
--[[
	Base-lock state machine.

	  Ready ──lock──▶ Locked (duration) ──▶ Cooldown ──▶ Ready
	                                   └─ tokens (paid Instant Lock) may skip the rest of the cooldown, but
	                                      never the open window right after a lock ends: `minVulnerableSeconds`,
	                                      or half the lock's duration when that is longer (see `windows`).

	That open window is the fairness guarantee: however long the lock and however much is spent, a base is open
	at least a third of the time. Pure: no requires, no Roblox APIs. Times are server timestamps in seconds.
]]

export type LockState = {
	lockedUntil: number,
	cooldownUntil: number,
	vulnerableUntil: number,
}

export type LockConfig = {
	cooldownSeconds: number,
	minVulnerableSeconds: number,
}

export type Status = "Locked" | "Cooldown" | "Ready"

-- Lock timers as kept in the save: wall-clock (os.time) seconds, so they survive leaving and joining any server.
export type SavedTimers = { cooldownUntil: number, vulnerableUntil: number }

export type LockAttempt = {
	ok: boolean,
	usedToken: boolean,
	reason: string?, -- "locked" | "cooldown" | "vulnerable"
	waitSeconds: number,
	state: LockState,
}

local LockRules = {}

function LockRules.newState(): LockState
	return { lockedUntil = 0, cooldownUntil = 0, vulnerableUntil = 0 }
end

function LockRules.isLocked(state: LockState, now: number): boolean
	return now < state.lockedUntil
end

function LockRules.remaining(state: LockState, now: number): number
	return math.max(0, state.lockedUntil - now)
end

function LockRules.status(state: LockState, now: number): Status
	if now < state.lockedUntil then
		return "Locked"
	elseif now < state.cooldownUntil then
		return "Cooldown"
	end
	return "Ready"
end

function LockRules.duration(baseSeconds: number, rebirthBonus: number, passBonus: number): number
	return math.max(1, baseSeconds + math.max(0, rebirthBonus) + math.max(0, passBonus))
end

-- For a lock of `duration` seconds: how long the base must then stay open (no token can skip it) and how long the
-- free lock recharges. The open window is at least half the lock, so open time >= 1/3 of the total even for the
-- longest lock with unlimited tokens; the recharge is never shorter than the open window.
function LockRules.windows(duration: number, cfg: LockConfig): (number, number)
	local open = math.max(cfg.minVulnerableSeconds, duration / 2)
	return open, math.max(cfg.cooldownSeconds, open)
end

-- Attempts to lock. Uses a token only when the free lock is on cooldown and the minimum open window has passed.
function LockRules.tryLock(
	state: LockState,
	now: number,
	duration: number,
	cfg: LockConfig,
	hasToken: boolean
): LockAttempt
	if now < state.lockedUntil then
		return { ok = false, usedToken = false, reason = "locked", waitSeconds = state.lockedUntil - now, state = state }
	end

	local usedToken = false
	if now < state.cooldownUntil then
		if not hasToken then
			return {
				ok = false,
				usedToken = false,
				reason = "cooldown",
				waitSeconds = state.cooldownUntil - now,
				state = state,
			}
		end
		if now < state.vulnerableUntil then
			return {
				ok = false,
				usedToken = false,
				reason = "vulnerable",
				waitSeconds = state.vulnerableUntil - now,
				state = state,
			}
		end
		usedToken = true
	end

	local lockedUntil = now + duration
	local openSeconds, cooldownSeconds = LockRules.windows(duration, cfg)
	return {
		ok = true,
		usedToken = usedToken,
		reason = nil,
		waitSeconds = 0,
		state = {
			lockedUntil = lockedUntil,
			cooldownUntil = lockedUntil + cooldownSeconds,
			vulnerableUntil = lockedUntil + openSeconds,
		},
	}
end

-- Ends a lock early (e.g. the owner left). The cooldown and open window still follow, as long as they would have
-- after the full lock, so leaving/rejoining can't be abused.
function LockRules.unlock(state: LockState, now: number): LockState
	if now >= state.lockedUntil then
		return state
	end
	return {
		lockedUntil = now,
		cooldownUntil = now + (state.cooldownUntil - state.lockedUntil),
		vulnerableUntil = now + (state.vulnerableUntil - state.lockedUntil),
	}
end

-- Converts live timers (server clock) into wall-clock timers for the save. Timers already over are saved as 0.
function LockRules.toSaved(state: LockState, serverNow: number, wallNow: number): SavedTimers
	local function convert(at: number): number
		return if at > serverNow then wallNow + (at - serverNow) else 0
	end
	return { cooldownUntil = convert(state.cooldownUntil), vulnerableUntil = convert(state.vulnerableUntil) }
end

-- Restores saved timers on join, so leaving and rejoining never resets the cooldown or the open window. The base
-- starts unlocked (a lock never outlives its owner's visit); each timer keeps its remaining wall-clock time, capped
-- at `maxSeconds` so a skewed clock or a bad value can't block locking for long.
function LockRules.fromSaved(saved: SavedTimers, serverNow: number, wallNow: number, maxSeconds: number): LockState
	local function convert(at: number): number
		local remaining = at - wallNow
		if not (remaining > 0) then -- also catches NaN
			return 0
		end
		return serverNow + math.min(remaining, math.max(0, maxSeconds))
	end
	return {
		lockedUntil = 0,
		cooldownUntil = convert(saved.cooldownUntil),
		vulnerableUntil = convert(saved.vulnerableUntil),
	}
end

return LockRules
