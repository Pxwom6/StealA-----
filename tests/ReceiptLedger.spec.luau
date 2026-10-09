--!strict
local T = require("./TestKit")
local ReceiptLedger = require("../src/shared/Logic/ReceiptLedger")

type FakeData = {
	cash: number,
	history: { string },
	stats: { robuxSpent: number },
	processedReceipts: { string },
}

type FakeProfile = {
	active: boolean,
	data: FakeData,
	saved: { string },
	grants: number,
	saves: number,
	failNextSaves: number,
	prepareErrors: number,
	applyErrors: number,
	endSessionOnSave: boolean,
}

local function newProfile(): FakeProfile
	return {
		active = true,
		data = { cash = 50, history = {}, stats = { robuxSpent = 0 }, processedReceipts = {} },
		saved = {},
		grants = 0,
		saves = 0,
		failNextSaves = 0,
		prepareErrors = 0,
		applyErrors = 0,
		endSessionOnSave = false,
	}
end

local function deps(p: FakeProfile): ReceiptLedger.ProcessDeps
	return {
		isActive = function(): boolean
			return p.active
		end,
		liveIds = function(): { string }
			return p.data.processedReceipts
		end,
		savedIds = function(): { string }?
			return p.saved
		end,
		data = function(): { [string]: any }
			return (p.data :: any) :: { [string]: any }
		end,
		prepare = function(): () -> ()
			if p.prepareErrors > 0 then
				p.prepareErrors -= 1
				error("lookup failed")
			end
			local amount = 100
			return function()
				p.data.cash += amount
				table.insert(p.data.history, "cash pack")
				if p.applyErrors > 0 then
					p.applyErrors -= 1
					error("grant failed halfway")
				end
				p.data.stats.robuxSpent += 10
				p.grants += 1
			end
		end,
		saveAndWait = function()
			p.saves += 1
			if p.failNextSaves > 0 then
				p.failNextSaves -= 1
				return
			end
			p.saved = table.clone(p.data.processedReceipts)
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
		T.expect(table.find(p.data.processedReceipts, "P2") ~= nil).toBe(true)
		T.expect(table.find(p.saved, "P2")).toBeNil()
		-- Roblox retries; saves work again now.
		p.failNextSaves = 0
		T.expect(ReceiptLedger.process("P2", 100, deps(p))).toBe("PurchaseGranted")
		T.expect(p.grants).toBe(1)
	end)

	T.it("records and changes nothing when the lookups fail, and grants on the retry", function()
		local p = newProfile()
		p.prepareErrors = 1
		T.expect(ReceiptLedger.process("P3", 100, deps(p))).toBe("NotProcessedYet")
		T.expect(p.grants).toBe(0)
		T.expect(#p.data.processedReceipts).toBe(0)
		T.expect(p.data.cash).toBe(50)
		T.expect(ReceiptLedger.process("P3", 100, deps(p))).toBe("PurchaseGranted")
		T.expect(p.grants).toBe(1)
	end)

	T.it("a grant that fails after partly changing the save is rolled back, so the retry applies it once", function()
		local p = newProfile()
		local before = {
			cash = p.data.cash,
			history = table.clone(p.data.history),
			stats = table.clone(p.data.stats),
			processedReceipts = table.clone(p.data.processedReceipts),
		}
		local historyTable = p.data.history
		p.applyErrors = 1
		T.expect(ReceiptLedger.process("P6", 100, deps(p))).toBe("NotProcessedYet")
		T.expect(p.data).toEqual(before) -- the half-applied cash and history entry are gone
		T.expect(p.data.history).toBe(historyTable) -- restored in place: table identities are kept

		-- Roblox retries: the product is applied exactly once.
		T.expect(ReceiptLedger.process("P6", 100, deps(p))).toBe("PurchaseGranted")
		T.expect(p.data.cash).toBe(150)
		T.expect(p.data.history).toEqual({ "cash pack" })
		T.expect(p.data.stats.robuxSpent).toBe(10)
		T.expect(p.data.processedReceipts).toEqual({ "P6" })
		T.expect(ReceiptLedger.process("P6", 100, deps(p))).toBe("PurchaseGranted")
		T.expect(p.data.cash).toBe(150)
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
		other.data.processedReceipts = table.clone(p.saved)
		other.saved = table.clone(p.saved)
		T.expect(ReceiptLedger.process("P5", 100, deps(other))).toBe("PurchaseGranted")
		T.expect(other.grants).toBe(0)
	end)
end)

T.describe("ReceiptLedger.quote", function()
	T.it("a cash pack retried after a rebirth pays the amount fixed when the purchase was first seen", function()
		local quotes: { ReceiptLedger.Quote } = {}
		local income = 5000
		local function amount(): number
			return income * 60
		end
		T.expect(ReceiptLedger.quote(quotes, "P1", amount, 100)).toBe(300000)
		income = 2 -- the player rebirths before Roblox retries the receipt
		T.expect(ReceiptLedger.quote(quotes, "P1", amount, 100)).toBe(300000)
		T.expect(ReceiptLedger.quote(quotes, "P2", amount, 100)).toBe(120) -- a new purchase uses the new income
		T.expect(#quotes).toBe(2)
	end)

	T.it("keeps a bounded list", function()
		local quotes: { ReceiptLedger.Quote } = {}
		for i = 1, 5 do
			ReceiptLedger.quote(quotes, `P{i}`, function(): number
				return i
			end, 3)
		end
		T.expect(#quotes).toBe(3)
		T.expect(quotes[1].purchaseId).toBe("P3")
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
