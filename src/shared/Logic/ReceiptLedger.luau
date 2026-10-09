--!strict
--[[
	Idempotent developer-product receipt handling.

	Roblox may call ProcessReceipt for the same purchase more than once (retries, rejoins, other servers).
	Rules implemented here:
	  1. Each PurchaseId is recorded in the player's save, in the SAME synchronous step as the grant, so a
	     retry finds it and never grants twice.
	  2. PurchaseGranted is only returned once the PurchaseId is present in the LAST SUCCESSFULLY SAVED copy of
	     the data. Until then we keep asking for saves; if the session ends first we return NotProcessedYet and
	     Roblox retries later (the retry sees the id and does not grant again).
	  3. A grant is two steps. `prepare` does every lookup and calculation and changes nothing; if it throws,
	     nothing happened. It returns `apply`, which only writes the results (no yields, nothing that can fail).
	     If `apply` throws anyway, the save is rolled back to exactly what it was before, so a retry never
	     applies half a grant twice. Either way the PurchaseId is not recorded and we return NotProcessedYet.

	The Roblox-specific parts (profile, saving, waiting) are injected, so this whole flow is unit-tested.
	Pure: no Roblox APIs.
]]

local Types = require("../Types")

export type Decision = "PurchaseGranted" | "NotProcessedYet"
export type PurchaseRecord = Types.PurchaseRecord
export type Quote = Types.ReceiptQuote

export type ProcessDeps = {
	isActive: () -> boolean, -- is the player's profile session still active on this server?
	liveIds: () -> { string }, -- profile.Data.processedReceipts (mutable)
	savedIds: () -> { string }?, -- profile.LastSavedData.processedReceipts
	data: () -> { [string]: any }, -- profile.Data: what `apply` writes to (rolled back if it fails)
	prepare: () -> () -> (), -- lookups + calculations, changes nothing, may error; returns `apply`
	saveAndWait: () -> (), -- requests a save and yields until it completes (or the session ends)
	maxSaveAttempts: number,
}

local ReceiptLedger = {}

function ReceiptLedger.contains(ids: { string }?, purchaseId: string): boolean
	if ids == nil then
		return false
	end
	return table.find(ids, purchaseId) ~= nil
end

-- Appends a PurchaseId, dropping the oldest entries beyond `cap`. No-op if already present.
function ReceiptLedger.record(ids: { string }, purchaseId: string, cap: number)
	if table.find(ids, purchaseId) ~= nil then
		return
	end
	table.insert(ids, purchaseId)
	while #ids > math.max(1, cap) do
		table.remove(ids, 1)
	end
end

function ReceiptLedger.appendHistory(history: { PurchaseRecord }, entry: PurchaseRecord, cap: number)
	table.insert(history, entry)
	while #history > math.max(1, cap) do
		table.remove(history, 1)
	end
end

-- The amount owed for a purchase whose size depends on the buyer's state (cash packs), fixed the first time the
-- purchase is quoted: a later retry pays the same even if that state changed meanwhile (e.g. a rebirth). Records
-- the quote in `quotes` (bounded to `cap`).
function ReceiptLedger.quote(quotes: { Quote }, purchaseId: string, compute: () -> number, cap: number): number
	for _, quote in quotes do
		if quote.purchaseId == purchaseId then
			return quote.amount
		end
	end
	local amount = compute()
	table.insert(quotes, { purchaseId = purchaseId, amount = amount })
	while #quotes > math.max(1, cap) do
		table.remove(quotes, 1)
	end
	return amount
end

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, inner in value do
		copy[key] = deepCopy(inner)
	end
	return copy
end

-- Makes `target` equal to `snapshot` again without replacing any table that already exists in it.
local function restoreInPlace(target: { [any]: any }, snapshot: { [any]: any })
	for key in target do
		if snapshot[key] == nil then
			target[key] = nil
		end
	end
	for key, value in snapshot do
		local current = target[key]
		if type(value) == "table" and type(current) == "table" then
			restoreInPlace(current, value)
		else
			target[key] = value
		end
	end
end

-- Runs `prepare` then its `apply` on `data`, all or nothing: returns false (and `data` is unchanged) if either
-- throws.
function ReceiptLedger.applyAtomically(data: { [string]: any }, prepare: () -> () -> ()): boolean
	local prepared, apply = pcall(prepare)
	if not prepared then
		return false
	end
	local snapshot = deepCopy(data)
	if not pcall(apply) then
		restoreInPlace(data, snapshot)
		return false
	end
	return true
end

function ReceiptLedger.process(purchaseId: string, cap: number, deps: ProcessDeps): Decision
	if not deps.isActive() then
		return "NotProcessedYet"
	end
	if ReceiptLedger.contains(deps.savedIds(), purchaseId) then
		return "PurchaseGranted"
	end

	if not ReceiptLedger.contains(deps.liveIds(), purchaseId) then
		-- Grant and record together, with no yield in between.
		if not ReceiptLedger.applyAtomically(deps.data(), deps.prepare) then
			return "NotProcessedYet"
		end
		ReceiptLedger.record(deps.liveIds(), purchaseId, cap)
	end

	for _ = 1, deps.maxSaveAttempts do
		if not deps.isActive() then
			return "NotProcessedYet"
		end
		deps.saveAndWait()
		if ReceiptLedger.contains(deps.savedIds(), purchaseId) then
			return "PurchaseGranted"
		end
	end
	return "NotProcessedYet"
end

return ReceiptLedger
