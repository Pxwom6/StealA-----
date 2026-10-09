--!strict
--[[
	The saved player data: type, template, versioned migration and sanitising.

	`migrate` upgrades older saves step by step. Bump SCHEMA_VERSION in EVERY release that adds, removes, renames or
	changes the meaning of any saved key (top-level or nested), even when its migrate step is empty: a server never
	loads a save with a newer version (isFromNewerVersion), and that check is the only thing stopping a server still
	running the old release from dropping keys it doesn't know. SCHEMA_VERSION must never go down in a published build,
	and a rollback must keep this module (and Types.PlayerData) as they are.
	`sanitise` repairs anything out of range so a corrupted or hand-edited save can never crash the server or
	hand out impossible values (NaN cash, two creatures on one podium...). A creature whose id is no longer in the
	config is never deleted: it moves to `quarantine` and comes back once the id exists again. Nor is a creature whose
	podium is invalid or taken: it moves to the lowest free podium within the base capacity, or waits in quarantine
	until a later load finds a free podium.
	Pure: no Roblox APIs.
]]

local Types = require("../Types")

export type CreatureRecord = Types.CreatureRecord
export type PurchaseRecord = Types.PurchaseRecord
export type ReceiptQuote = Types.ReceiptQuote
export type Stats = Types.Stats
export type PlayerData = Types.PlayerData

export type SanitiseRules = {
	isValidCreature: (id: string) -> boolean,
	maxPodiums: number,
	maxPodiumUpgrades: number,
	startingPodiums: number, -- with podiumUpgrades: the base capacity a relocated creature may be moved within
	maxRebirths: number,
	maxReceipts: number,
	maxHistory: number,
}

local SCHEMA_VERSION = 2

local DataSchema = {}
DataSchema.VERSION = SCHEMA_VERSION

function DataSchema.template(startingCash: number): PlayerData
	return {
		version = SCHEMA_VERSION,
		cash = startingCash,
		creatures = {},
		quarantine = {},
		nextUid = 1,
		podiumUpgrades = 0,
		rebirths = 0,
		rebirthMultiplier = 1,
		lockTokens = 0,
		lockTimers = { cooldownUntil = 0, vulnerableUntil = 0 },
		processedReceipts = {},
		cashPackQuotes = {},
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

-- True when `raw` was written by a newer release (a schema version this server does not know). Such a save must not
-- be used here: sanitising it would drop the fields this server doesn't know about, and saving would wipe them.
function DataSchema.isFromNewerVersion(raw: { [string]: any }): boolean
	return finite(raw.version, 0) > SCHEMA_VERSION
end

-- Upgrades `raw` in place to the current schema version and returns it, one step per version. A save from a newer
-- release is returned untouched.
function DataSchema.migrate(raw: { [string]: any }): { [string]: any }
	local version = finite(raw.version, 0)
	if version < 1 then -- the initial shape
		version = 1
	end
	if version < 2 then -- v2: lock timers persist, unknown creatures are quarantined, cash pack quotes
		if type(raw.lockTimers) ~= "table" then
			raw.lockTimers = { cooldownUntil = 0, vulnerableUntil = 0 }
		end
		if type(raw.quarantine) ~= "table" then
			raw.quarantine = {}
		end
		if type(raw.cashPackQuotes) ~= "table" then
			raw.cashPackQuotes = {}
		end
		version = 2
	end
	raw.version = version
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
	local quarantine: { CreatureRecord } = {}
	local usedPodiums: { [number]: boolean } = {}
	local usedUids: { [string]: boolean } = {}
	local nextUid = wholeInRange(raw.nextUid, 1, 2 ^ 50, 1)
	-- New uids are tostring(nextUid): keep the counter above every numeric uid already in the save, so a counter that
	-- fell behind (corruption, an old bug) can never hand out a uid that is already taken.
	for _, list in { raw.creatures, raw.quarantine } do
		if type(list) == "table" then
			for _, entry in list do
				local uid = if type(entry) == "table" then tonumber(entry.uid) else nil
				if uid and uid == math.floor(uid) and uid >= nextUid and uid < 2 ^ 50 then
					nextUid = uid + 1
				end
			end
		end
	end

	-- Any saved creature entry as a record (fields repaired), or nil when it isn't a creature at all.
	local function toRecord(entry: unknown): CreatureRecord?
		if type(entry) ~= "table" then
			return nil
		end
		local e = entry :: { [string]: any }
		if type(e.id) ~= "string" or #e.id == 0 or #e.id > 64 then
			return nil
		end
		return {
			uid = if type(e.uid) == "string" then e.uid else "",
			id = e.id,
			podium = finite(e.podium, 0),
			acquiredAt = finite(e.acquiredAt, 0),
			stored = math.max(0, finite(e.stored, 0)),
			variant = if type(e.variant) == "string" then e.variant else nil,
		}
	end
	local function isFreePodium(podium: number): boolean
		return podium == math.floor(podium) and podium >= 1 and podium <= rules.maxPodiums and not usedPodiums[podium]
	end
	local function place(record: CreatureRecord, podium: number)
		if record.uid == "" or usedUids[record.uid] or #record.uid > 32 then
			record.uid = tostring(nextUid)
			nextUid += 1
			fix("reassigned uid")
		end
		usedPodiums[podium] = true
		usedUids[record.uid] = true
		record.podium = podium
		table.insert(creatures, record)
	end

	-- Valid creatures that still need a podium: ones whose podium is invalid or taken, and quarantined ones whose
	-- id exists again. Placed after every creature that already has a good podium.
	local homeless: { CreatureRecord } = {}
	if type(raw.creatures) == "table" then
		for _, entry in raw.creatures do
			local record = toRecord(entry)
			if record == nil then
				fix("creature entry is not a creature")
			elseif not rules.isValidCreature(record.id) then
				fix(`quarantined unknown creature {record.id}`)
				table.insert(quarantine, record)
			elseif not isFreePodium(record.podium) then
				fix(`bad podium for {record.id}`)
				table.insert(homeless, record)
			else
				place(record, record.podium)
			end
		end
	end
	if type(raw.quarantine) == "table" then
		for _, entry in raw.quarantine do
			local record = toRecord(entry)
			if record == nil then
				fix("quarantine entry is not a creature")
			elseif not rules.isValidCreature(record.id) then
				table.insert(quarantine, record)
			else
				fix(`restoring quarantined creature {record.id}`)
				table.insert(homeless, record)
			end
		end
	end

	-- Back on its own podium if that is free, else the lowest free podium within the base capacity (podium upgrades,
	-- not pass bonuses: passes aren't known here), else safely in quarantine. Sanitising never deletes a creature.
	local podiumUpgrades = wholeInRange(raw.podiumUpgrades, 0, rules.maxPodiumUpgrades, 0)
	local baseCapacity = math.clamp(rules.startingPodiums + podiumUpgrades, 0, rules.maxPodiums)
	for _, record in homeless do
		local podium: number? = if isFreePodium(record.podium) then record.podium else nil
		for candidate = 1, baseCapacity do
			if podium ~= nil then
				break
			end
			if isFreePodium(candidate) then
				podium = candidate
			end
		end
		if podium then
			place(record, podium)
		else
			table.insert(quarantine, record)
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

	local quotes: { ReceiptQuote } = {}
	if type(raw.cashPackQuotes) == "table" then
		for _, entry in raw.cashPackQuotes do
			local amount = if type(entry) == "table" then entry.amount else nil
			if type(entry) == "table" and type(entry.purchaseId) == "string" and finite(amount, 0 / 0) == amount then
				table.insert(quotes, { purchaseId = entry.purchaseId, amount = math.max(0, amount) })
			end
		end
	end
	while #quotes > rules.maxReceipts do
		table.remove(quotes, 1)
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
	local rawLock = if type(raw.lockTimers) == "table" then raw.lockTimers else {}

	local data: PlayerData = {
		version = SCHEMA_VERSION,
		cash = math.max(0, cash),
		creatures = creatures,
		quarantine = quarantine,
		nextUid = nextUid,
		podiumUpgrades = podiumUpgrades,
		rebirths = rebirths,
		rebirthMultiplier = math.max(1, finite(raw.rebirthMultiplier, template.rebirthMultiplier)),
		lockTokens = wholeInRange(raw.lockTokens, 0, 1000, 0),
		lockTimers = {
			cooldownUntil = math.max(0, finite(rawLock.cooldownUntil, 0)),
			vulnerableUntil = math.max(0, finite(rawLock.vulnerableUntil, 0)),
		},
		processedReceipts = receipts,
		cashPackQuotes = quotes,
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
-- so the table identity ProfileStore holds stays the same. Refuses (returns false, changes nothing) when `target`
-- was written by a newer release: its unknown keys are real data, not junk.
function DataSchema.applyInPlace(target: { [string]: any }, clean: PlayerData): boolean
	if DataSchema.isFromNewerVersion(target) then
		return false
	end
	local cleanMap = (clean :: any) :: { [string]: any }
	for key in target do
		if cleanMap[key] == nil then
			target[key] = nil
		end
	end
	for key, value in cleanMap do
		target[key] = value
	end
	return true
end

return DataSchema
