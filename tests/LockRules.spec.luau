--!strict
local T = require("./TestKit")
local LockRules = require("../src/shared/Logic/LockRules")

local cfg = { cooldownSeconds = 90, minVulnerableSeconds = 30 }

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
		local state = LockRules.newState()
		local lockedSeconds, openSeconds = 0, 0
		for now = 0, 36000 do -- ten hours, one attempt per second, infinite tokens
			if LockRules.isLocked(state, now) then
				lockedSeconds += 1
			else
				openSeconds += 1
				local attempt = LockRules.tryLock(state, now, 60, cfg, true)
				if attempt.ok then
					state = attempt.state
				end
			end
		end
		local openShare = openSeconds / (openSeconds + lockedSeconds)
		T.expect(openShare).toBeAtLeast(30 / 90 - 0.01) -- 30s open per 60s locked
	end)

	T.it("unlocking early keeps the cooldown", function()
		local state = LockRules.tryLock(LockRules.newState(), 0, 60, cfg, false).state
		local unlocked = LockRules.unlock(state, 20, cfg)
		T.expect(LockRules.isLocked(unlocked, 21)).toBe(false)
		T.expect(LockRules.status(unlocked, 21)).toBe("Cooldown")
		T.expect(LockRules.tryLock(unlocked, 40, 60, cfg, true).reason).toBe("vulnerable")
	end)

	T.it("duration adds rebirth and pass bonuses", function()
		T.expect(LockRules.duration(60, 10, 30)).toBe(100)
		T.expect(LockRules.duration(60, -5, 0)).toBe(60)
	end)
end)

return nil
