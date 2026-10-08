--!strict
--[[
	The saved player data: type, template, versioned migration and sanitising.

	`migrate` upgrades older saves step by step (bump SCHEMA_VERSION and add a step when the shape changes).
	`sanitise` repairs anything out of range so a corrupted or hand-edited save can never crash the server or
	hand out impossible values (NaN cash, unknown creatures, two creatures on one podium...).
	Pure: no Roblox APIs.
]]

local Types = require("../Types")

export type CreatureRecord = Types.CreatureRecord
export type PurchaseRecord = Types.PurchaseRecord
export type Stats = Types.Stats
export type PlayerData = Types.PlayerData

export type SanitiseRules = {
	isValidCreature: (id: string) -> boolean,
	maxPodiums: number,
	maxPodiumUpgrades: number,
	maxRebirths: number,
	maxReceipts: number,
	maxHistory: number,
}

local SCHEMA_VERSION = 1

local DataSchema = {}
DataSchema.VERSION = SCHEMA_VERSION

function DataSchema.template(startingCash: number): PlayerData
	return {
		version = SCHEMA_VERSION,
		cash = startingCash,
		creatures = {},
		nextUid = 1,
		podiumUpgrades = 0,
		rebirths = 0,
		rebirthMultiplier = 1,
		lockTokens = 0,
		processedReceipts = {},
		purchaseHistory = {},
		daily = { streak = 0, lastClaimDay = -1 },
		stats = {
			steals = 0,
			timesStolenFrom = 0,
			beltPurchases = 0,
			playTime = 0,
			bestCashPerSecond = 0,
			robuxSpent = 0,
			totalEarned = 0,
		},
		flags = {},
		firstJoin = 0,
		lastSeen = 0,
	}
end

local function finite(value: unknown, fallback: number): number
	if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
		return value
	end
	return fallback
end

local function wholeInRange(value: unknown, min: number, max: number, fallback: number): number
	return math.clamp(math.floor(finite(value, fallback)), min, max)
end

-- Upgrades `raw` in place to the current schema version and returns it.
-- Version 0 → 1 is the initial shape; future steps go here, e.g.
--   if data.version < 2 then data.newField = default; data.version = 2 end
function DataSchema.migrate(raw: { [string]: any }): { [string]: any }
	local version = finite(raw.version, 0)
	if version < 1 then
		raw.version = 1
	end
	return raw
end

-- Repairs every field into range. Returns the cleaned data and a list of what was fixed (for logging).
function DataSchema.sanitise(
	raw: { [string]: any },
	startingCash: number,
	rules: SanitiseRules
): (PlayerData, { string })
	local fixes: { string } = {}
	local template = DataSchema.template(startingCash)

	local function fix(message: string)
		table.insert(fixes, message)
	end

	local cash = finite(raw.cash, startingCash)
	if cash ~= raw.cash or cash < 0 then
		fix("cash")
	end

	local rebirths = wholeInRange(raw.rebirths, 0, rules.maxRebirths, 0)
	local creatures: { CreatureRecord } = {}
	local usedPodiums: { [number]: boolean } = {}
	local usedUids: { [string]: boolean } = {}
	local nextUid = wholeInRange(raw.nextUid, 1, 2 ^ 50, 1)
	if type(raw.creatures) == "table" then
		for _, entry in raw.creatures do
			if type(entry) ~= "table" then
				fix("creature entry not a table")
				continue
			end
			local id = entry.id
			if type(id) ~= "string" or not rules.isValidCreature(id) then
				fix(`unknown creature {tostring(id)}`)
				continue
			end
			local podium = finite(entry.podium, 0)
			if podium ~= math.floor(podium) or podium < 1 or podium > rules.maxPodiums or usedPodiums[podium] then
				fix(`bad podium for {id}`)
				continue
			end
			local uid = entry.uid
			if type(uid) ~= "string" or usedUids[uid] or #uid > 32 then
				uid = tostring(nextUid)
				nextUid += 1
				fix("reassigned uid")
			end
			usedPodiums[podium] = true
			usedUids[uid :: string] = true
			table.insert(creatures, {
				uid = uid :: string,
				id = id,
				podium = podium,
				acquiredAt = finite(entry.acquiredAt, 0),
				stored = math.max(0, finite(entry.stored, 0)),
				variant = if type(entry.variant) == "string" then entry.variant else nil,
			})
		end
	end

	local receipts: { string } = {}
	if type(raw.processedReceipts) == "table" then
		for _, id in raw.processedReceipts do
			if type(id) == "string" then
				table.insert(receipts, id)
			end
		end
	end
	while #receipts > rules.maxReceipts do
		table.remove(receipts, 1)
	end

	local history: { PurchaseRecord } = {}
	if type(raw.purchaseHistory) == "table" then
		for _, entry in raw.purchaseHistory do
			if type(entry) == "table" and type(entry.purchaseId) == "string" then
				table.insert(history, {
					purchaseId = entry.purchaseId,
					productId = finite(entry.productId, 0),
					key = if type(entry.key) == "string" then entry.key else "",
					robux = finite(entry.robux, 0),
					at = finite(entry.at, 0),
				})
			end
		end
	end
	while #history > rules.maxHistory do
		table.remove(history, 1)
	end

	local rawStats = if type(raw.stats) == "table" then raw.stats else {}
	local stats: Stats = {
		steals = wholeInRange(rawStats.steals, 0, 2 ^ 50, 0),
		timesStolenFrom = wholeInRange(rawStats.timesStolenFrom, 0, 2 ^ 50, 0),
		beltPurchases = wholeInRange(rawStats.beltPurchases, 0, 2 ^ 50, 0),
		playTime = math.max(0, finite(rawStats.playTime, 0)),
		bestCashPerSecond = math.max(0, finite(rawStats.bestCashPerSecond, 0)),
		robuxSpent = math.max(0, finite(rawStats.robuxSpent, 0)),
		totalEarned = math.max(0, finite(rawStats.totalEarned, 0)),
	}

	local flags: { [string]: boolean } = {}
	if type(raw.flags) == "table" then
		for key, value in raw.flags do
			if type(key) == "string" and value == true then
				flags[key] = true
			end
		end
	end

	local rawDaily = if type(raw.daily) == "table" then raw.daily else {}

	local data: PlayerData = {
		version = SCHEMA_VERSION,
		cash = math.max(0, cash),
		creatures = creatures,
		nextUid = nextUid,
		podiumUpgrades = wholeInRange(raw.podiumUpgrades, 0, rules.maxPodiumUpgrades, 0),
		rebirths = rebirths,
		rebirthMultiplier = math.max(1, finite(raw.rebirthMultiplier, template.rebirthMultiplier)),
		lockTokens = wholeInRange(raw.lockTokens, 0, 1000, 0),
		processedReceipts = receipts,
		purchaseHistory = history,
		daily = {
			streak = wholeInRange(rawDaily.streak, 0, 100000, 0),
			lastClaimDay = math.floor(finite(rawDaily.lastClaimDay, -1)),
		},
		stats = stats,
		flags = flags,
		firstJoin = finite(raw.firstJoin, 0),
		lastSeen = finite(raw.lastSeen, 0),
	}
	return data, fixes
end

-- Writes every field of `clean` into `target` (the live ProfileStore table) and removes unknown keys,
-- so the table identity ProfileStore holds stays the same.
function DataSchema.applyInPlace(target: { [string]: any }, clean: PlayerData)
	local cleanMap = (clean :: any) :: { [string]: any }
	for key in target do
		if cleanMap[key] == nil then
			target[key] = nil
		end
	end
	for key, value in cleanMap do
		target[key] = value
	end
end

return DataSchema
