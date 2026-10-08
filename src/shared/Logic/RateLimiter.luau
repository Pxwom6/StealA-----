--!strict
--[[
	Token-bucket rate limiter. One limiter per remote; buckets are keyed by player (UserId as string).
	The clock is passed in so tests can control time. Pure: no requires, no Roblox APIs.

	local limiter = RateLimiter.new(4, 2)       -- burst of 4, refills 2 tokens / second
	if RateLimiter.allow(limiter, "12345", os.clock()) then ... end
]]

export type Bucket = { tokens: number, updatedAt: number }
export type Limiter = { burst: number, perSecond: number, buckets: { [string]: Bucket } }

local RateLimiter = {}

function RateLimiter.new(burst: number, perSecond: number): Limiter
	assert(burst >= 1, "burst must be >= 1")
	assert(perSecond > 0, "perSecond must be > 0")
	return { burst = burst, perSecond = perSecond, buckets = {} }
end

-- Consumes one token for `key` and returns true, or returns false if the bucket is empty.
function RateLimiter.allow(limiter: Limiter, key: string, now: number): boolean
	local bucket = limiter.buckets[key]
	if bucket == nil then
		bucket = { tokens = limiter.burst, updatedAt = now }
		limiter.buckets[key] = bucket
	end
	-- A clock that goes backwards never grants extra tokens.
	local elapsed = math.max(0, now - bucket.updatedAt)
	bucket.tokens = math.min(limiter.burst, bucket.tokens + elapsed * limiter.perSecond)
	bucket.updatedAt = math.max(bucket.updatedAt, now)
	if bucket.tokens >= 1 then
		bucket.tokens -= 1
		return true
	end
	return false
end

function RateLimiter.forget(limiter: Limiter, key: string)
	limiter.buckets[key] = nil
end

return RateLimiter
