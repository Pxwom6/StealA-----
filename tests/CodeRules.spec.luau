--!strict
local T = require("./TestKit")
local Catalog = require("../src/shared/Logic/Catalog")
local CodeRules = require("../src/shared/Logic/CodeRules")
local Creatures = require("../src/shared/Config/Creatures")
local LiveOps = require("../src/shared/Config/LiveOps")
local Mutations = require("../src/shared/Config/Mutations")
local Rarities = require("../src/shared/Config/Rarities")
local Types = require("../src/shared/Types")
local Codes = require("../src/server/Codes") :: Types.CodesConfig

local catalog = Catalog.build(Creatures, Rarities, Mutations)

local CONFIG: Types.CodesConfig = {
	HELLO = { reward = { kind = "cash", incomeSeconds = 60, minimum = 100 } },
	PUP = { reward = { kind = "creature", creatureId = "pizza_pup", variant = "golden" } },
	OLD = { reward = { kind = "cash", incomeSeconds = 60, minimum = 100 }, expiresAt = 1700000000 },
	SOON = { reward = { kind = "cash", incomeSeconds = 60, minimum = 100 }, startsAt = 1900000000 },
}

T.describe("CodeRules: the real codes", function()
	T.it("are valid", function()
		local problems = CodeRules.validate(Codes, catalog.creatures, catalog.mutations)
		if #problems > 0 then
			print(table.concat(problems, "\n"))
		end
		T.expect(#problems).toBe(0)
	end)

	T.it("hand out an event's Snacklings and mutations only while that event runs", function()
		local events: { [string]: Types.EventDef } = {}
		for _, event in LiveOps.events do
			events[event.id] = event
		end
		local checked = 0
		for code, def in Codes do
			local reward = def.reward :: any
			local eventIds: { string } = {}
			if reward.kind == "creature" then
				local creature = catalog.creatures[reward.creatureId]
				if creature.eventId then
					table.insert(eventIds, creature.eventId)
				end
				local mutation = if reward.variant then catalog.mutations[reward.variant] else nil
				if mutation and mutation.eventId then
					table.insert(eventIds, mutation.eventId)
				end
			end
			for _, eventId in eventIds do
				local event = events[eventId]
				local ok = event ~= nil
					and def.startsAt ~= nil
					and def.startsAt >= event.startsAt
					and def.expiresAt ~= nil
					and def.expiresAt <= event.endsAt
				if not ok then
					print(`code {code} must start no earlier than {eventId} and expire by its end`)
				end
				T.expect(ok).toBe(true)
				checked += 1
			end
		end
		T.expect(checked).toBeAtLeast(8) -- SPOOKY26, JINGLE26, LOVE27 and EGGHUNT27: a Snackling and a mutation each
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

	T.it("refuses anything longer than a code with a few spaces around it, before trimming", function()
		local padding = (CodeRules.MAX_TYPED_LENGTH - #"WELCOME") // 2
		local fits = string.rep(" ", padding) .. "welcome" .. string.rep(" ", padding)
		T.expect(#fits).toBeAtMost(CodeRules.MAX_TYPED_LENGTH)
		T.expect(CodeRules.normalize(fits)).toBe("WELCOME")
		T.expect(CodeRules.normalize(fits .. string.rep(" ", CodeRules.MAX_TYPED_LENGTH))).toBeNil()
	end)

	T.it("answers at once for a huge run of spaces (the trim used to take 28 s on 64 KB)", function()
		local started = os.clock()
		T.expect(CodeRules.normalize("a" .. string.rep(" ", 64000) .. "b")).toBeNil()
		T.expect(CodeRules.normalize(string.rep(" ", 200000))).toBeNil()
		T.expect(os.clock() - started).toBeLessThan(0.05)
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

	T.it("works from the moment it starts, and before that answers like an unknown code", function()
		T.expect(select(3, CodeRules.check(CONFIG, "soon", {}, 1899999999))).toBe("unknown")
		local def, code, refusal = CodeRules.check(CONFIG, "soon", {}, 1900000000)
		T.expect(def ~= nil).toBe(true)
		T.expect(code).toBe("SOON")
		T.expect(refusal).toBeNil()
	end)

	T.it("keeps the real event codes shut before their events (they all worked in October 2026)", function()
		local october15 = 1792023721
		for _, code in { "SPOOKY26", "JINGLE26", "HAPPY2027", "LOVE27", "EGGHUNT27" } do
			T.expect(select(3, CodeRules.check(Codes, code, {}, october15))).toBe("unknown")
			local starts = Codes[code].startsAt :: number
			T.expect((CodeRules.check(Codes, code, {}, starts)) ~= nil).toBe(true)
		end
		T.expect((CodeRules.check(Codes, "WELCOME", {}, october15)) ~= nil).toBe(true)
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
		T.expect(problems({ X = { reward = CONFIG.HELLO.reward, startsAt = 20261231 } })).toBe(1)
		T.expect(problems({ X = { reward = CONFIG.HELLO.reward, startsAt = 1800000000, expiresAt = 1800000000 } }))
			.toBe(1)
		T.expect(problems({ X = { reward = CONFIG.HELLO.reward, startsAt = 1800000000, expiresAt = 1800003600 } }))
			.toBe(0)
	end)
end)

return nil
