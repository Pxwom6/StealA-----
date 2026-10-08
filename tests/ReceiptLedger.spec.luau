--!strict
local T = require("./TestKit")
local ReceiptLedger = require("../src/shared/Logic/ReceiptLedger")

type FakeProfile = {
	active: boolean,
	live: { string },
	saved: { string },
	grants: number,
	saves: number,
	failNextSaves: number,
	grantErrors: number,
	endSessionOnSave: boolean,
}

local function newProfile(): FakeProfile
	return {
		active = true,
		live = {},
		saved = {},
		grants = 0,
		saves = 0,
		failNextSaves = 0,
		grantErrors = 0,
		endSessionOnSave = false,
	}
end

local function deps(p: FakeProfile): ReceiptLedger.ProcessDeps
	return {
		isActive = function(): boolean
			return p.active
		end,
		liveIds = function(): { string }
			return p.live
		end,
		savedIds = function(): { string }?
			return p.saved
		end,
		grant = function()
			if p.grantErrors > 0 then
				p.grantErrors -= 1
				error("grant failed")
			end
			p.grants += 1
		end,
		saveAndWait = function()
			p.saves += 1
			if p.failNextSaves > 0 then
				p.failNextSaves -= 1
				return
			end
			p.saved = table.clone(p.live)
			if p.endSessionOnSave then
				p.active = false
			end
		end,
		maxSaveAttempts = 3,
	}
end

T.describe("ReceiptLedger.process", function()
	T.it("grants once and only reports PurchaseGranted after the save contains the id", function()
		local p = newProfile()
		T.expect(ReceiptLedger.process("P1", 100, deps(p))).toBe("PurchaseGranted")
		T.expect(p.grants).toBe(1)
		T.expect(table.find(p.saved, "P1") ~= nil).toBe(true)
	end)

	T.it("never grants twice for the same PurchaseId", function()
		local p = newProfile()
		ReceiptLedger.process("P1", 100, deps(p))
		T.expect(ReceiptLedger.process("P1", 100, deps(p))).toBe("PurchaseGranted")
		T.expect(ReceiptLedger.process("P1", 100, deps(p))).toBe("PurchaseGranted")
		T.expect(p.grants).toBe(1)
	end)

	T.it("returns NotProcessedYet while saves keep failing, then completes on retry without re-granting", function()
		local p = newProfile()
		p.failNextSaves = 5
		T.expect(ReceiptLedger.process("P2", 100, deps(p))).toBe("NotProcessedYet")
		T.expect(p.grants).toBe(1)
		T.expect(table.find(p.live, "P2") ~= nil).toBe(true)
		T.expect(table.find(p.saved, "P2")).toBeNil()
		-- Roblox retries; saves work again now.
		p.failNextSaves = 0
		T.expect(ReceiptLedger.process("P2", 100, deps(p))).toBe("PurchaseGranted")
		T.expect(p.grants).toBe(1)
	end)

	T.it("records nothing when the grant throws, and grants on the retry", function()
		local p = newProfile()
		p.grantErrors = 1
		T.expect(ReceiptLedger.process("P3", 100, deps(p))).toBe("NotProcessedYet")
		T.expect(p.grants).toBe(0)
		T.expect(#p.live).toBe(0)
		T.expect(ReceiptLedger.process("P3", 100, deps(p))).toBe("PurchaseGranted")
		T.expect(p.grants).toBe(1)
	end)

	T.it("does nothing for an inactive session", function()
		local p = newProfile()
		p.active = false
		T.expect(ReceiptLedger.process("P4", 100, deps(p))).toBe("NotProcessedYet")
		T.expect(p.grants).toBe(0)
	end)

	T.it("survives the session ending mid-wait: the next server sees the saved id and does not re-grant", function()
		local p = newProfile()
		p.failNextSaves = 1
		p.endSessionOnSave = true
		-- first save fails (still active), second save succeeds but ends the session
		local first = ReceiptLedger.process("P5", 100, deps(p))
		T.expect(first == "PurchaseGranted" or first == "NotProcessedYet").toBe(true)
		T.expect(p.grants).toBe(1)
		-- "another server" loads the saved data
		local other = newProfile()
		other.live = table.clone(p.saved)
		other.saved = table.clone(p.saved)
		T.expect(ReceiptLedger.process("P5", 100, deps(other))).toBe("PurchaseGranted")
		T.expect(other.grants).toBe(0)
	end)
end)

T.describe("ReceiptLedger.record / appendHistory", function()
	T.it("keeps a bounded ring of ids without duplicates", function()
		local ids: { string } = {}
		for i = 1, 5 do
			ReceiptLedger.record(ids, `id{i}`, 3)
		end
		T.expect(ids).toEqual({ "id3", "id4", "id5" })
		ReceiptLedger.record(ids, "id5", 3)
		T.expect(#ids).toBe(3)
	end)
	T.it("bounds the purchase history", function()
		local history: { ReceiptLedger.PurchaseRecord } = {}
		for i = 1, 4 do
			ReceiptLedger.appendHistory(
				history,
				{ purchaseId = `p{i}`, productId = 1, key = "CashSmall", robux = 49, at = i },
				2
			)
		end
		T.expect(#history).toBe(2)
		T.expect(history[1].purchaseId).toBe("p3")
	end)
end)

return nil
