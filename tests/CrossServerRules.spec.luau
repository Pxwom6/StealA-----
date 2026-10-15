--!strict
local serde = require("@lune/serde")
local T = require("./TestKit")
local Catalog = require("../src/shared/Logic/Catalog")
local CrossServerRules = require("../src/shared/Logic/CrossServerRules")
local HostRules = require("../src/shared/Logic/HostRules")
local Creatures = require("../src/shared/Config/Creatures")
local Host = require("../src/shared/Config/Host")
local Mutations = require("../src/shared/Config/Mutations")
local Rarities = require("../src/shared/Config/Rarities")
local Types = require("../src/shared/Types")

local catalog = Catalog.build(Creatures, Rarities, Mutations)
local messaging = Host.messaging
local VERSION = messaging.version
local GUID = "6F9619FF-8B86-D011-B42D-00C04FC964FF"

-- What a receiver gets: the message as JSON, decoded (as MessagingService and HttpService do it).
local function overTheWire(message: any): any
	return serde.decode("json", serde.encode("json", message))
end

local function sample(): CrossServerRules.Message
	return CrossServerRules.message("luck", { multiplier = 2, minutes = 15 }, 723735722, GUID, 1000, VERSION)
end

-- The first Snackling of a rarity in the catalogue.
local function creatureOf(rarity: string): Types.CreatureDef
	for _, def in catalog.creatureList do
		if def.rarity == rarity and def.eventId == nil then
			return def
		end
	end
	error(`no {rarity} Snackling`)
end

T.describe("CrossServerRules messages", function()
	T.it("decode what was sent, through JSON", function()
		local decoded = CrossServerRules.decode(overTheWire(sample()), VERSION)
		T.expect(decoded).toEqual(sample())
	end)
	T.it("keep a message with no args", function()
		local message = CrossServerRules.message("mapVote", {}, 1, GUID, 5, VERSION)
		local decoded = CrossServerRules.decode(overTheWire(message), VERSION) :: CrossServerRules.Message
		T.expect(decoded.kind).toBe("mapVote")
		T.expect((next(decoded.args))).toBeNil()
	end)
	T.it("refuse another version, a missing or bad field", function()
		local function without(key: string, value: any): any
			local copy = table.clone(sample()) :: any
			copy[key] = value
			return overTheWire(copy)
		end
		T.expect(CrossServerRules.decode(overTheWire(sample()), VERSION + 1)).toBeNil()
		T.expect(CrossServerRules.decode(without("kind", nil), VERSION)).toBeNil()
		T.expect(CrossServerRules.decode(without("kind", string.rep("k", 33)), VERSION)).toBeNil()
		T.expect(CrossServerRules.decode(without("from", 1.5), VERSION)).toBeNil()
		T.expect(CrossServerRules.decode(without("from", "723735722"), VERSION)).toBeNil()
		T.expect(CrossServerRules.decode(without("id", "short"), VERSION)).toBeNil()
		T.expect(CrossServerRules.decode(without("at", "now"), VERSION)).toBeNil()
		T.expect(CrossServerRules.decode(without("args", "x"), VERSION)).toBeNil()
		T.expect(CrossServerRules.decode("not a table", VERSION)).toBeNil()
		T.expect(CrossServerRules.decode(nil, VERSION)).toBeNil()
	end)
	T.it("refuse args that are not a few plain values under short names", function()
		local function withArgs(args: any): any
			local copy = table.clone(sample()) :: any
			copy.args = args
			return copy -- not through JSON: a table can hold what JSON can't
		end
		T.expect(CrossServerRules.decode(withArgs({ nested = { 1 } }), VERSION)).toBeNil()
		T.expect(CrossServerRules.decode(withArgs({ [1] = "array" }), VERSION)).toBeNil()
		T.expect(CrossServerRules.decode(withArgs({ [string.rep("k", 17)] = 1 }), VERSION)).toBeNil()
		T.expect(CrossServerRules.decode(withArgs({ text = string.rep("x", 501) }), VERSION)).toBeNil()
		T.expect(CrossServerRules.decode(withArgs({ n = 0 / 0 }), VERSION)).toBeNil()
		T.expect(CrossServerRules.decode(withArgs({ n = math.huge }), VERSION)).toBeNil()
		local many: { [string]: number } = {}
		for i = 1, CrossServerRules.MAX_ARGS + 1 do
			many["k" .. i] = i
		end
		T.expect(CrossServerRules.decode(withArgs(many), VERSION)).toBeNil()
		T.expect(CrossServerRules.decode(withArgs({ on = true, minutes = 2, id = "x" }), VERSION) ~= nil).toBe(true)
	end)
	T.it("stay well under Roblox's 1 KB, even for the longest message", function()
		local text = string.rep("🎉", Host.limits.broadcastLength)
		local command = HostRules.command("broadcast", { text = text }, {
			maps = {},
			modifiers = {},
			creatures = {},
			mutations = {},
			events = {},
		}, Host) :: HostRules.Command
		local message = CrossServerRules.message("broadcast", HostRules.args(command), 723735722, GUID, 1.8e9, VERSION)
		local encoded = serde.encode("json", message)
		T.expect(#encoded).toBeAtMost(messaging.maxBytes)
		T.expect(CrossServerRules.decode(serde.decode("json", encoded), VERSION) ~= nil).toBe(true)
	end)
end)

T.describe("CrossServerRules.accept", function()
	T.it("acts on a fresh message once, then calls copies duplicates", function()
		local seen = CrossServerRules.newSeen()
		T.expect(CrossServerRules.accept(seen, sample(), 1000, messaging)).toBeNil()
		T.expect(CrossServerRules.accept(seen, sample(), 1001, messaging)).toBe("duplicate")
		T.expect(CrossServerRules.hasSeen(seen, GUID)).toBe(true)
	end)
	T.it("ignores messages older than about a minute", function()
		local seen = CrossServerRules.newSeen()
		T.expect(CrossServerRules.accept(seen, sample(), 1000 + messaging.maxAgeSeconds, messaging)).toBeNil()
		local late = CrossServerRules.newSeen()
		T.expect(CrossServerRules.accept(late, sample(), 1000 + messaging.maxAgeSeconds + 1, messaging)).toBe("stale")
		T.expect(CrossServerRules.hasSeen(late, GUID)).toBe(false)
	end)
	T.it("forgives a little clock skew but not a message from the future", function()
		local seen = CrossServerRules.newSeen()
		T.expect(CrossServerRules.accept(seen, sample(), 995, messaging)).toBeNil()
		local ahead = CrossServerRules.newSeen()
		T.expect(CrossServerRules.accept(ahead, sample(), 1000 - messaging.maxFutureSeconds - 1, messaging))
			.toBe("future")
	end)
	T.it("remembers a bounded number of ids, oldest forgotten first", function()
		local seen = CrossServerRules.newSeen()
		for i = 1, 300 do
			CrossServerRules.remember(seen, `id-{i}-xxxxxxxx`, 1000, 256, 60)
		end
		T.expect(#seen.order).toBe(256)
		T.expect(CrossServerRules.hasSeen(seen, "id-1-xxxxxxxx")).toBe(false)
		T.expect(CrossServerRules.hasSeen(seen, "id-300-xxxxxxxx")).toBe(true)
	end)
	T.it("forgets ids once a copy could no longer be accepted anyway", function()
		local seen = CrossServerRules.newSeen()
		CrossServerRules.remember(seen, "old-xxxxxxxx", 1000, 256, 60)
		CrossServerRules.remember(seen, "new-xxxxxxxx", 1061, 256, 60)
		T.expect(CrossServerRules.hasSeen(seen, "old-xxxxxxxx")).toBe(false)
		T.expect(CrossServerRules.hasSeen(seen, "new-xxxxxxxx")).toBe(true)
		T.expect(CrossServerRules.keepSeconds(messaging)).toBeGreaterThan(messaging.maxAgeSeconds)
	end)
end)

T.describe("CrossServerRules shout-outs", function()
	local shoutouts = Host.shoutouts
	local function worthy(rarity: string, variant: string?): boolean
		return CrossServerRules.isShoutworthy(rarity, variant, catalog.rarities, shoutouts)
	end
	T.it("shout about any Secret", function()
		T.expect(worthy("Secret", nil)).toBe(true)
		T.expect(worthy("Secret", "golden")).toBe(true)
	end)
	T.it("shout about a Diamond or Rainbow Mythic, and not a plain or Golden one", function()
		T.expect(worthy("Mythic", "diamond")).toBe(true)
		T.expect(worthy("Mythic", "rainbow")).toBe(true)
		T.expect(worthy("Mythic", nil)).toBe(false)
		T.expect(worthy("Mythic", "golden")).toBe(false)
	end)
	T.it("stay quiet about anything rarer only in mutation", function()
		T.expect(worthy("Legendary", "rainbow")).toBe(false)
		T.expect(worthy("Common", "rainbow")).toBe(false)
		T.expect(worthy("Mystery", nil)).toBe(false)
	end)
	T.it("are rate limited: once per interval", function()
		T.expect(CrossServerRules.due(-math.huge, 0, shoutouts.publishEverySeconds)).toBe(true)
		T.expect(CrossServerRules.due(100, 100 + shoutouts.publishEverySeconds - 1, shoutouts.publishEverySeconds))
			.toBe(false)
		T.expect(CrossServerRules.due(100, 100 + shoutouts.publishEverySeconds, shoutouts.publishEverySeconds))
			.toBe(true)
		T.expect(shoutouts.publishEverySeconds).toBe(30)
		T.expect(shoutouts.showEverySeconds).toBe(20)
	end)
	T.it("carry a clean display name", function()
		T.expect(CrossServerRules.cleanName("  Bob ")).toBe("Bob")
		T.expect(CrossServerRules.cleanName("Bo\nb")).toBe("Bob")
		T.expect(CrossServerRules.cleanName(string.rep("a", 20))).toBe(string.rep("a", 20))
		T.expect(CrossServerRules.cleanName(string.rep("a", 21))).toBeNil()
		T.expect(CrossServerRules.cleanName("")).toBeNil()
		T.expect(CrossServerRules.cleanName(42)).toBeNil()
	end)
	T.it("arrive as who found which Snackling, checked against the receiver's catalogue", function()
		local secret = creatureOf("Secret")
		local mythic = creatureOf("Mythic")
		local function read(args: CrossServerRules.Args): CrossServerRules.Shout?
			return CrossServerRules.readShout(args, catalog.creatures, catalog.mutations, catalog.rarities, shoutouts)
		end
		T.expect(read(CrossServerRules.shoutArgs("Bob", secret.id, nil)))
			.toEqual({ name = "Bob", creatureId = secret.id })
		T.expect(read(CrossServerRules.shoutArgs("Bob", mythic.id, "rainbow"))).toEqual({
			name = "Bob",
			creatureId = mythic.id,
			variant = "rainbow",
		})
		T.expect(read(CrossServerRules.shoutArgs("Bob", "made_up", nil))).toBeNil()
		T.expect(read(CrossServerRules.shoutArgs("Bob", secret.id, "plaid"))).toBeNil()
		T.expect(read(CrossServerRules.shoutArgs("Bob", mythic.id, nil))).toBeNil()
		T.expect(read(CrossServerRules.shoutArgs(string.rep("x", 30), secret.id, nil))).toBeNil()
		T.expect(read({ name = "Bob", creature = 5 })).toBeNil()
	end)
end)

return nil
