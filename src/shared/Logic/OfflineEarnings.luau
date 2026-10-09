--!strict
--[[
	Offline earnings paid on rejoin. Capped, reduced-rate, and robust to clock skew (a lastSeen in the future or
	missing pays nothing). Pure: no requires, no Roblox APIs.
]]

export type OfflineConfig = { rate: number, capSeconds: number, minSecondsAway: number }
export type OfflineResult = { secondsAway: number, paidSeconds: number, amount: number }

local OfflineEarnings = {}

function OfflineEarnings.compute(
	lastSeen: number,
	now: number,
	incomePerSecond: number,
	cfg: OfflineConfig,
	capBonusSeconds: number?
): OfflineResult
	local none = { secondsAway = 0, paidSeconds = 0, amount = 0 }
	if lastSeen ~= lastSeen or lastSeen <= 0 or now < lastSeen then
		return none
	end
	if incomePerSecond ~= incomePerSecond or incomePerSecond <= 0 or incomePerSecond == math.huge then
		return none
	end
	local away = now - lastSeen
	if away < cfg.minSecondsAway then
		return { secondsAway = away, paidSeconds = 0, amount = 0 }
	end
	local cap = cfg.capSeconds + math.max(0, capBonusSeconds or 0)
	local paid = math.min(away, cap)
	return {
		secondsAway = away,
		paidSeconds = paid,
		amount = math.floor(paid * incomePerSecond * math.clamp(cfg.rate, 0, 1)),
	}
end

return OfflineEarnings
