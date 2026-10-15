--!strict
--[[
	Auto Collect (a game pass, Config/Monetization.passes.AutoCollect): the cash waiting on an owner's active pads is
	collected for them every `Monetization.perks.autoCollectSeconds`, wherever they are, through the same path as
	walking over a pad (server/Services/AutoCollectService, EconomyService.collectPad).

	The timing rule: the first collect comes at the first check after the pass is on (a join, a purchase), then one
	every interval. A clock that went backwards (or NaN) counts as due, so a player is never stuck waiting.

	Pure: no Roblox APIs; times come in as seconds on one clock (the server uses os.clock()).
]]

local AutoCollectRules = {}

-- The interval Config/Monetization may set (seconds): fast enough to feel automatic, slow enough to stay cheap.
AutoCollectRules.LIMITS = table.freeze({ min = 2, max = 30 })

-- Whether an Auto Collect is due at `now`, the last one having run at `lastAt` (nil: none yet this session).
function AutoCollectRules.due(lastAt: number?, now: number, interval: number): boolean
	if lastAt == nil then
		return true
	end
	local elapsed = now - lastAt
	if elapsed ~= elapsed or elapsed < 0 then
		return true -- NaN, or the clock went backwards
	end
	return elapsed >= interval
end

-- Seconds until the next Auto Collect (0 when due now).
function AutoCollectRules.remaining(lastAt: number?, now: number, interval: number): number
	if AutoCollectRules.due(lastAt, now, interval) then
		return 0
	end
	return interval - (now - (lastAt :: number))
end

-- Problems with the configured interval (an empty list means valid).
function AutoCollectRules.validate(intervalSeconds: number): { string }
	local problems: { string } = {}
	local limits = AutoCollectRules.LIMITS
	if not (intervalSeconds >= limits.min and intervalSeconds <= limits.max) then
		table.insert(problems, `autoCollectSeconds must be between {limits.min} and {limits.max}`)
	end
	return problems
end

return AutoCollectRules
