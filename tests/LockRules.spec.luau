--!strict
local T = require("./TestKit")
local LockRules = require("../src/shared/Logic/LockRules")
local Economy = require("../src/shared/Config/Economy")
local Gameplay = require("../src/shared/Config/Gameplay")
local Monetization = require("../src/shared/Config/Monetization")

local cfg = { cooldownSeconds = 90, minVulnerableSeconds = 30 }

-- Spams lock attempts once a second for ten hours with unlimited tokens; returns the share of time left open.
local function openShareWithUnlimitedTokens(duration: number, config: LockRules.LockConfig): number
	local state = LockRules.newState()
	local lockedSeconds, openSeconds = 0, 0
	for now = 0, 36000 do
		if LockRules.isLocked(state, now) then
			lockedSeconds += 1
		else
			openSeconds += 1
			local attempt = LockRules.tryLock(state, now, duration, config, true)
			if attempt.ok then
				state = attempt.state
			end
		end
	end
	return openSeconds / (openSeconds + lockedSeconds)
end

T.describe("LockRules", function()
	T.it("locks when ready and reports remaining time", function()
		local attempt = LockRules.tryLock(LockRules.newState(), 100, 60, cfg, false)
		T.expect(attempt.ok).toBe(true)
		T.expect(attempt.usedToken).toBe(false)
		T.expect(LockRules.isLocked(attempt.state, 159)).toBe(true)
		T.expect(LockRules.isLocked(attempt.state, 160)).toBe(false)
		T.expect(LockRules.remaining(attempt.state, 130)).toBe(30)
		T.expect(LockRules.status(attempt.state, 130)).toBe("Locked")
		T.expect(LockRules.status(attempt.state, 200)).toBe("Cooldown")
		T.expect(LockRules.status(attempt.state, 250)).toBe("Ready")
	end)

	T.it("refuses while locked or on cooldown without a token", function()
		local state = LockRules.tryLock(LockRules.newState(), 0, 60, cfg, false).state
		local whileLocked = LockRules.tryLock(state, 10, 60, cfg, true)
		T.expect(whileLocked.ok).toBe(false)
		T.expect(whileLocked.reason).toBe("locked")
		local onCooldown = LockRules.tryLock(state, 100, 60, cfg, false)
		T.expect(onCooldown.ok).toBe(false)
		T.expect(onCooldown.reason).toBe("cooldown")
		T.expect(onCooldown.waitSeconds).toBe(50)
	end)

	T.it("a token skips the cooldown but never the minimum open window", function()
		local state = LockRules.tryLock(LockRules.newState(), 0, 60, cfg, false).state
		local tooSoon = LockRules.tryLock(state, 75, 60, cfg, true)
		T.expect(tooSoon.ok).toBe(false)
		T.expect(tooSoon.reason).toBe("vulnerable")
		T.expect(tooSoon.waitSeconds).toBe(15)
		local withToken = LockRules.tryLock(state, 90, 60, cfg, true)
		T.expect(withToken.ok).toBe(true)
		T.expect(withToken.usedToken).toBe(true)
	end)

	T.it("does not spend a token when the free lock is available", function()
		local state = LockRules.tryLock(LockRules.newState(), 0, 60, cfg, false).state
		local free = LockRules.tryLock(state, 150, 60, cfg, true)
		T.expect(free.ok).toBe(true)
		T.expect(free.usedToken).toBe(false)
	end)

	T.it("fairness: unlimited tokens still leave the base open a guaranteed share of the time", function()
		T.expect(openShareWithUnlimitedTokens(60, cfg)).toBeAtLeast(30 / 90 - 0.01) -- 30s open per 60s locked
	end)

	T.it("fairness holds for the longest possible lock (max rebirth bonus + Longer Lock pass)", function()
		local longest = LockRules.duration(
			Gameplay.lock.durationSeconds,
			Economy.rebirth.maxLockBonus,
			Monetization.perks.longerLockSeconds
		)
		T.expect(longest).toBeGreaterThan(Gameplay.lock.durationSeconds)
		T.expect(openShareWithUnlimitedTokens(longest, Gameplay.lock)).toBeAtLeast(1 / 3 - 0.01)
		for _, duration in { 1, 30, 61, 100, 150, 240, 600 } do
			T.expect(openShareWithUnlimitedTokens(duration, cfg)).toBeAtLeast(1 / 3 - 0.01)
		end
	end)

	T.it("the open window after a lock is at least half the lock, and the free cooldown never ends sooner", function()
		local long = LockRules.tryLock(LockRules.newState(), 0, 150, cfg, false).state
		T.expect(long.vulnerableUntil - long.lockedUntil).toBe(75)
		T.expect(long.cooldownUntil - long.lockedUntil).toBe(90)
		T.expect(LockRules.tryLock(long, 150 + 74, 150, cfg, true).reason).toBe("vulnerable")
		T.expect(LockRules.tryLock(long, 150 + 75, 150, cfg, true).ok).toBe(true)

		local huge = LockRules.tryLock(LockRules.newState(), 0, 400, cfg, false).state
		T.expect(huge.vulnerableUntil - huge.lockedUntil).toBe(200)
		T.expect(huge.cooldownUntil - huge.lockedUntil).toBe(200) -- no free lock inside the open window either
		T.expect(LockRules.tryLock(huge, 400 + 199, 400, cfg, false).ok).toBe(false)

		-- Ending a long lock early (owner left) keeps its longer window.
		local ended = LockRules.unlock(long, 10)
		T.expect(ended.vulnerableUntil).toBe(10 + 75)
		T.expect(ended.cooldownUntil).toBe(10 + 90)
	end)

	T.it("unlocking early keeps the cooldown", function()
		local state = LockRules.tryLock(LockRules.newState(), 0, 60, cfg, false).state
		local unlocked = LockRules.unlock(state, 20)
		T.expect(LockRules.isLocked(unlocked, 21)).toBe(false)
		T.expect(LockRules.status(unlocked, 21)).toBe("Cooldown")
		T.expect(LockRules.tryLock(unlocked, 40, 60, cfg, true).reason).toBe("vulnerable")
	end)

	T.it("leaving and rejoining keeps the cooldown and the open window", function()
		-- Server clock and wall clock differ on purpose: the save must hold wall-clock times.
		local state = LockRules.tryLock(LockRules.newState(), 1000, 60, cfg, false).state
		local leftAt, wallAtLeave = 1010, 50000
		local saved = LockRules.toSaved(LockRules.unlock(state, leftAt), leftAt, wallAtLeave)
		T.expect(saved.cooldownUntil).toBe(wallAtLeave + 90)
		T.expect(saved.vulnerableUntil).toBe(wallAtLeave + 30)

		-- Rejoin 20 s later on another server whose clock reads 7000.
		local restored = LockRules.fromSaved(saved, 7000, wallAtLeave + 20, 1000)
		T.expect(LockRules.isLocked(restored, 7000)).toBe(false)
		T.expect(LockRules.status(restored, 7000)).toBe("Cooldown")
		local noToken = LockRules.tryLock(restored, 7000, 60, cfg, false)
		T.expect(noToken.ok).toBe(false)
		T.expect(noToken.reason).toBe("cooldown")
		T.expect(noToken.waitSeconds).toBe(70)
		local withToken = LockRules.tryLock(restored, 7000, 60, cfg, true)
		T.expect(withToken.reason).toBe("vulnerable")
		T.expect(withToken.waitSeconds).toBe(10)
	end)

	T.it("saved timers that ran out while away restore as ready", function()
		local state = LockRules.tryLock(LockRules.newState(), 0, 60, cfg, false).state
		local saved = LockRules.toSaved(state, 10, 500)
		local restored = LockRules.fromSaved(saved, 0, 500 + 3600, 1000)
		T.expect(LockRules.status(restored, 0)).toBe("Ready")
		T.expect(LockRules.tryLock(restored, 0, 60, cfg, false).ok).toBe(true)
		T.expect(LockRules.toSaved(LockRules.newState(), 10, 500)).toEqual({ cooldownUntil = 0, vulnerableUntil = 0 })
	end)

	T.it("restored timers are capped (bad clocks or values)", function()
		local restored = LockRules.fromSaved({ cooldownUntil = 1e12, vulnerableUntil = 0 / 0 }, 100, 0, 150)
		T.expect(restored.cooldownUntil).toBe(250)
		T.expect(restored.vulnerableUntil).toBe(0)
	end)

	T.it("duration adds rebirth and pass bonuses", function()
		T.expect(LockRules.duration(60, 10, 30)).toBe(100)
		T.expect(LockRules.duration(60, -5, 0)).toBe(60)
	end)
end)

return nil
