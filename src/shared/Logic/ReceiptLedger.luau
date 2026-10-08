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
	  3. A grant that throws records nothing and returns NotProcessedYet.

	The Roblox-specific parts (profile, saving, waiting) are injected, so this whole flow is unit-tested.
	Pure: no Roblox APIs.
]]

local Types = require("../Types")

export type Decision = "PurchaseGranted" | "NotProcessedYet"
export type PurchaseRecord = Types.PurchaseRecord

export type ProcessDeps = {
	isActive: () -> boolean, -- is the player's profile session still active on this server?
	liveIds: () -> { string }, -- profile.Data.processedReceipts (mutable)
	savedIds: () -> { string }?, -- profile.LastSavedData.processedReceipts
	grant: () -> (), -- applies the product to profile.Data; must not yield; may error
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

function ReceiptLedger.process(purchaseId: string, cap: number, deps: ProcessDeps): Decision
	if not deps.isActive() then
		return "NotProcessedYet"
	end
	if ReceiptLedger.contains(deps.savedIds(), purchaseId) then
		return "PurchaseGranted"
	end

	if not ReceiptLedger.contains(deps.liveIds(), purchaseId) then
		-- Grant and record together, with no yield in between.
		local ok = pcall(deps.grant)
		if not ok then
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
