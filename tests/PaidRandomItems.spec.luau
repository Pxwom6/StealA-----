--!strict
local T = require("./TestKit")
local PaidRandomItems = require("../src/shared/Logic/PaidRandomItems")

T.describe("PaidRandomItems (Roblox's Paid Random Items policy)", function()
	T.it("allows them only on a clear 'not restricted' from PolicyService", function()
		T.expect(PaidRandomItems.allowedByPolicy(true, { ArePaidRandomItemsRestricted = false })).toBe(true)
		T.expect(PaidRandomItems.allowedByPolicy(true, { ArePaidRandomItemsRestricted = true })).toBe(false)
	end)

	T.it("treats a failed or odd lookup as restricted", function()
		T.expect(PaidRandomItems.allowedByPolicy(false, "HTTP 500")).toBe(false)
		T.expect(PaidRandomItems.allowedByPolicy(true, nil)).toBe(false)
		T.expect(PaidRandomItems.allowedByPolicy(true, {})).toBe(false)
		T.expect(PaidRandomItems.allowedByPolicy(true, { ArePaidRandomItemsRestricted = "no" })).toBe(false)
	end)

	T.it(
		"lets the store offer them only when the player attribute says so (not while it is being looked up)",
		function()
			T.expect(PaidRandomItems.allowedByAttribute(true)).toBe(true)
			T.expect(PaidRandomItems.allowedByAttribute(false)).toBe(false)
			T.expect(PaidRandomItems.allowedByAttribute(nil)).toBe(false)
			T.expect(PaidRandomItems.allowedByAttribute(1)).toBe(false)
			T.expect(PaidRandomItems.ATTRIBUTE).toBe("PaidRandomItemsAllowed")
		end
	)
end)

return nil
