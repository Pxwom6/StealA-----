--!strict
local T = require("./TestKit")
local Catalog = require("../src/shared/Logic/Catalog")
local CodeRules = require("../src/shared/Logic/CodeRules")
local Creatures = require("../src/shared/Config/Creatures")
local Mutations = require("../src/shared/Config/Mutations")
local Rarities = require("../src/shared/Config/Rarities")
local Types = require("../src/shared/Types")
local Codes = require("../src/server/Codes") :: Types.CodesConfig

local catalog = Catalog.build(Creatures, Rarities, Mutations)

local CONFIG: Types.CodesConfig = {
	HELLO = { reward = { kind = "cash", incomeSeconds = 60, minimum = 100 } },
	PUP = { reward = { kind = "creature", creatureId = "pizza_pup", variant = "golden" } },
	OLD = { reward = { kind = "cash", incomeSeconds = 60, minimum = 100 }, expiresAt = 1700000000 },
}

T.describe("CodeRules: the real codes", function()
	T.it("are valid", function()
		local problems = CodeRules.validate(Codes, catalog.creatures, catalog.mutations)
		if #problems > 0 then
			print(table.concat(problems, "\n"))
		end
		T.expect(#problems).toBe(0)
	end)
end)

T.describe("CodeRules.normalize", function()
	T.it("accepts letters and digits in any case, trimming spaces around them", function()
		T.expect(CodeRules.normalize("welcome")).toBe("WELCOME")
		T.expect(CodeRules.normalize("  Snack2026 ")).toBe("SNACK2026")
	end)

	T.it("refuses anything else", function()
		T.expect(CodeRules.normalize("")).toBeNil()
		T.expect(CodeRules.normalize("   ")).toBeNil()
		T.expect(CodeRules.normalize("two words")).toBeNil()
		T.expect(CodeRules.normalize("DROP;TABLE")).toBeNil()
		T.expect(CodeRules.normalize(string.rep("A", CodeRules.MAX_LENGTH + 1))).toBeNil()
		T.expect(CodeRules.normalize(42)).toBeNil()
		T.expect(CodeRules.normalize(nil)).toBeNil()
	end)
end)

T.describe("CodeRules.check", function()
	T.it("finds a code typed in any case", function()
		local def, code, refusal = CodeRules.check(CONFIG, "hello", {}, 1800000000)
		T.expect(def ~= nil).toBe(true)
		T.expect(code).toBe("HELLO")
		T.expect(refusal).toBeNil()
	end)

	T.it("says why a code can't be redeemed", function()
		T.expect(select(3, CodeRules.check(CONFIG, "he llo", {}, 1800000000))).toBe("invalid")
		T.expect(select(3, CodeRules.check(CONFIG, "NOPE", {}, 1800000000))).toBe("unknown")
		T.expect(select(3, CodeRules.check(CONFIG, "old", {}, 1800000000))).toBe("expired")
		local flags = { [CodeRules.flagKey("HELLO")] = true }
		T.expect(select(3, CodeRules.check(CONFIG, "Hello", flags, 1800000000))).toBe("used")
	end)

	T.it("works until the moment it expires", function()
		T.expect((CodeRules.check(CONFIG, "OLD", {}, 1699999999)) ~= nil).toBe(true)
		T.expect((CodeRules.check(CONFIG, "OLD", {}, 1700000000))).toBeNil()
	end)
end)

T.describe("CodeRules.validate", function()
	local function problems(config: any): number
		return #CodeRules.validate(config, catalog.creatures, catalog.mutations)
	end

	T.it("accepts a good config", function()
		T.expect(problems(CONFIG)).toBe(0)
	end)

	T.it("refuses lower-case or odd codes, unknown Snacklings and mutations, and broken rewards", function()
		T.expect(problems({ hello = CONFIG.HELLO })).toBe(1)
		T.expect(problems({ ["A-B"] = CONFIG.HELLO })).toBe(1)
		T.expect(problems({ X = { reward = { kind = "creature", creatureId = "dragon" } } })).toBe(1)
		T.expect(problems({ X = { reward = { kind = "creature", creatureId = "pizza_pup", variant = "plaid" } } }))
			.toBe(1)
		T.expect(problems({ X = { reward = { kind = "cash", incomeSeconds = 0, minimum = 10 } } })).toBe(1)
		T.expect(problems({ X = { reward = { kind = "gems" } } })).toBe(1)
		T.expect(problems({ X = { reward = CONFIG.HELLO.reward, expiresAt = 20261231 } })).toBe(1)
	end)
end)

return nil
