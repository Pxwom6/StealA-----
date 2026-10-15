--!strict
--[[
	Snack Attack rules (Config/Boss): how much health the giant Snackling has, who shares the reward and how much, and
	validation. Pure: no Roblox APIs. The server (BossService) counts the hits.
]]

local EconomyMath = require("./EconomyMath")
local Types = require("../Types")

type BossConfig = Types.BossConfig

local BossRules = {}

-- Its health with `players` in the server when it appears.
function BossRules.maxHp(config: BossConfig, players: number): number
	return math.max(config.minHp, config.hpPerPlayer * math.max(1, math.floor(players)))
end

export type Share = { key: string, hits: number, share: number }

-- Everyone who landed at least minHits, with their share of all the hits, the top hitter first (ties: the smaller
-- key, so every run agrees).
function BossRules.shares(config: BossConfig, hits: { [string]: number }): { Share }
	local total = 0
	for _, count in hits do
		total += count
	end
	local list: { Share } = {}
	if total <= 0 then
		return list
	end
	for key, count in hits do
		if count >= config.minHits then
			table.insert(list, { key = key, hits = count, share = count / total })
		end
	end
	table.sort(list, function(a: Share, b: Share): boolean
		if a.hits ~= b.hits then
			return a.hits > b.hits
		end
		return a.key < b.key
	end)
	return list
end

-- What a helper with `share` of the hits is paid, from their steady income per second.
function BossRules.cash(config: BossConfig, share: number, income: number): number
	local seconds = config.cash.baseSeconds + config.cash.shareSeconds * math.clamp(share, 0, 1)
	return EconomyMath.cashPackAmount(income, { incomeSeconds = seconds, minimum = config.cash.minimum })
end

-- Whether a hit seen at `now` starts a new flinch on a client whose last one started at `lastStart` (seconds, one
-- clock): never with Reduce effects (`reduced`), and at most once every `flinch.gapSeconds`, so the giant can't
-- flash faster than that however many players hit it.
function BossRules.startsFlinch(config: BossConfig, lastStart: number, now: number, reduced: boolean): boolean
	return not reduced and now - lastStart >= config.flinch.gapSeconds
end

-- The red fill's transparency `since` seconds after a flinch started: strongest (`flinch.peakFill`) at once, then
-- fading back to none (1) over `flinch.seconds`: a soft pulse, not an on/off blink.
function BossRules.flinchFill(config: BossConfig, since: number): number
	local flinch = config.flinch
	if not (since >= 0 and since < flinch.seconds) then
		return 1
	end
	return flinch.peakFill + (1 - flinch.peakFill) * (since / flinch.seconds)
end

-- How long `players` hitting as fast as the server counts take to bring it down (seconds), for the balance notes.
function BossRules.fastestTakedown(config: BossConfig, players: number): number
	return BossRules.maxHp(config, players) / (config.hitsPerSecond * math.max(1, players))
end

-- Problems with Config/Boss (an empty list means valid). `rarityIds`: the configured rarities.
function BossRules.validate(config: BossConfig, rarityIds: { [string]: boolean }): { string }
	local problems: { string } = {}
	local function problem(message: string)
		table.insert(problems, message)
	end
	local function range(value: number, low: number, high: number, what: string)
		if not (value >= low and value <= high) then
			problem(`{what} must be between {low} and {high}`)
		end
	end
	range(config.hpPerPlayer, 10, 1000, "hpPerPlayer")
	range(config.minHp, 10, 5000, "minHp")
	range(config.hitsPerSecond, 1, 15, "hitsPerSecond")
	if not (config.burst >= config.hitsPerSecond and config.burst <= 30) then
		problem("burst must be at least hitsPerSecond and at most 30")
	end
	range(config.reach, 10, 80, "reach")
	range(config.lifetimeSeconds, 20, 280, "lifetimeSeconds")
	range(config.scale, 1.5, 6, "scale")
	range(config.hoverHeight, 4, 30, "hoverHeight")
	if #config.rarities == 0 then
		problem("rarities needs at least one tier")
	end
	for _, id in config.rarities do
		if not rarityIds[id] then
			problem(`rarities lists unknown tier {id}`)
		end
	end
	range(config.minHits, 1, 100, "minHits")
	range(config.cash.baseSeconds, 0, 600, "cash.baseSeconds")
	range(config.cash.shareSeconds, 0, 600, "cash.shareSeconds")
	if not (config.cash.minimum >= 0) then
		problem("cash.minimum must be 0 or more")
	end
	range(config.luck, 1, 6, "luck")
	range(config.mutationChance, 1, 4, "mutationChance")
	-- photosensitivity: flashing stays at two a second or fewer (well under the usual limit of three), and soft
	range(config.flinch.seconds, 0.05, 0.4, "flinch.seconds")
	range(config.flinch.gapSeconds, 0.5, 5, "flinch.gapSeconds (at most 2 flashes a second)")
	if not (config.flinch.seconds < config.flinch.gapSeconds) then
		problem("flinch.seconds must be shorter than flinch.gapSeconds")
	end
	range(config.flinch.peakFill, 0.5, 1, "flinch.peakFill (never more than half-opaque)")
	-- the whole server hitting flat out must be able to bring it down in time
	if BossRules.fastestTakedown(config, 1) > config.lifetimeSeconds * 0.6 then
		problem("one player hitting flat out must be able to take it down in well under its lifetime")
	end
	return problems
end

return BossRules
