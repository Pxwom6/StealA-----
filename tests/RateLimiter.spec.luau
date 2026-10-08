--!strict
local T = require("./TestKit")
local RateLimiter = require("../src/shared/Logic/RateLimiter")

T.describe("RateLimiter", function()
	T.it("allows a burst then blocks", function()
		local limiter = RateLimiter.new(3, 1)
		T.expect(RateLimiter.allow(limiter, "p", 0)).toBe(true)
		T.expect(RateLimiter.allow(limiter, "p", 0)).toBe(true)
		T.expect(RateLimiter.allow(limiter, "p", 0)).toBe(true)
		T.expect(RateLimiter.allow(limiter, "p", 0)).toBe(false)
	end)
	T.it("refills over time up to the burst size", function()
		local limiter = RateLimiter.new(2, 2)
		RateLimiter.allow(limiter, "p", 0)
		RateLimiter.allow(limiter, "p", 0)
		T.expect(RateLimiter.allow(limiter, "p", 0.25)).toBe(false)
		T.expect(RateLimiter.allow(limiter, "p", 0.5)).toBe(true)
		-- a long pause never stores more than `burst` tokens
		local allowed = 0
		for _ = 1, 10 do
			if RateLimiter.allow(limiter, "p", 100) then
				allowed += 1
			end
		end
		T.expect(allowed).toBe(2)
	end)
	T.it("keeps players independent", function()
		local limiter = RateLimiter.new(1, 0.1)
		T.expect(RateLimiter.allow(limiter, "a", 0)).toBe(true)
		T.expect(RateLimiter.allow(limiter, "a", 0)).toBe(false)
		T.expect(RateLimiter.allow(limiter, "b", 0)).toBe(true)
	end)
	T.it("does not grant tokens when the clock goes backwards", function()
		local limiter = RateLimiter.new(1, 1)
		T.expect(RateLimiter.allow(limiter, "p", 100)).toBe(true)
		T.expect(RateLimiter.allow(limiter, "p", 50)).toBe(false)
		T.expect(RateLimiter.allow(limiter, "p", 100.5)).toBe(false)
		T.expect(RateLimiter.allow(limiter, "p", 101)).toBe(true)
	end)
	T.it("forgets a key", function()
		local limiter = RateLimiter.new(1, 0.01)
		RateLimiter.allow(limiter, "p", 0)
		RateLimiter.forget(limiter, "p")
		T.expect(RateLimiter.allow(limiter, "p", 0)).toBe(true)
	end)
end)

return nil
