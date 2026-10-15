--!strict
local T = require("./TestKit")
local Catalog = require("../src/shared/Logic/Catalog")
local HostRules = require("../src/shared/Logic/HostRules")
local Creatures = require("../src/shared/Config/Creatures")
local Host = require("../src/shared/Config/Host")
local LiveOps = require("../src/shared/Config/LiveOps")
local MapThemes = require("../src/shared/Config/MapThemes")
local Modifiers = require("../src/shared/Config/Modifiers")
local Mutations = require("../src/shared/Config/Mutations")
local Rarities = require("../src/shared/Config/Rarities")
local Theme = require("../src/shared/Config/Theme")
local Types = require("../src/shared/Types")

local catalog = Catalog.build(Creatures, Rarities, Mutations)
local events: { [string]: boolean } = {}
for _, event in LiveOps.events do
	events[event.id] = true
end
local known: HostRules.Known = {
	maps = MapThemes.themes,
	modifiers = Modifiers.modifiers,
	creatures = catalog.creatures,
	mutations = catalog.mutations,
	events = events,
}

local ADMIN = 723735722
local OWNER = 5005
local base: HostRules.RoleInput =
	{ userId = 0, studio = false, admins = { ADMIN }, privateServerId = "", privateServerOwnerId = 0 }

local function roleOf(userId: number, overrides: { [string]: any }?): HostRules.Role
	local input = table.clone(base)
	input.userId = userId
	local extra: { [string]: any } = overrides or {}
	for key, value in extra do
		(input :: any)[key] = value
	end
	return HostRules.role(input)
end

local function command(kind: any, args: any): HostRules.Command?
	return HostRules.command(kind, args, known, Host)
end

local function weatherUnlocks(): { [string]: boolean }
	local unlocks: { [string]: boolean } = {}
	for _, mutation in Mutations do
		if mutation.modifierId then
			unlocks[mutation.modifierId] = true
		end
	end
	return unlocks
end

T.describe("HostRules.role", function()
	T.it("makes the configured admins admins, in any server", function()
		T.expect(roleOf(ADMIN)).toBe("admin")
		T.expect(roleOf(ADMIN, { privateServerId = "ps", privateServerOwnerId = OWNER })).toBe("admin")
	end)
	T.it("makes anyone an admin in Studio, as the dev commands do", function()
		T.expect(roleOf(42, { studio = true })).toBe("admin")
	end)
	T.it("makes a private server's owner its owner", function()
		T.expect(roleOf(OWNER, { privateServerId = "ps", privateServerOwnerId = OWNER })).toBe("owner")
	end)
	T.it("gives nobody else anything", function()
		T.expect(roleOf(42)).toBe("none")
		T.expect(roleOf(42, { privateServerId = "ps", privateServerOwnerId = OWNER })).toBe("none")
		-- a reserved server has a PrivateServerId but owner 0; a public server has no PrivateServerId
		T.expect(roleOf(0, { privateServerId = "reserved", privateServerOwnerId = 0 })).toBe("none")
		T.expect(roleOf(OWNER, { privateServerId = "", privateServerOwnerId = OWNER })).toBe("none")
	end)
end)

T.describe("HostRules actions", function()
	T.it("lists every action once, in ORDER and in ACTIONS", function()
		local count = 0
		for kind in HostRules.ACTIONS do
			count += 1
			T.expect(table.find(HostRules.ORDER, kind) ~= nil).toBe(true)
		end
		T.expect(#HostRules.ORDER).toBe(count)
	end)
	T.it("refuses anything that is not an action", function()
		for _, kind in { "teleport", "", "MAPSWITCH", "__index", 5, true, {} } :: { any } do
			T.expect(command(kind, {})).toBeNil()
		end
		T.expect(command(nil, nil)).toBeNil()
	end)
	T.it("refuses arguments that are not a table", function()
		T.expect(command("mapVote", "all")).toBeNil()
		T.expect(command("gift", 5)).toBeNil()
		T.expect(command("mapVote", nil)).toEqual({ kind = "mapVote" })
	end)
end)

T.describe("HostRules.command arguments", function()
	T.it("switches only to a known map", function()
		T.expect(command("mapSwitch", { id = "candy" })).toEqual({ kind = "mapSwitch", id = "candy" })
		T.expect(command("mapSwitch", { id = "atlantis" })).toBeNil()
		T.expect(command("mapSwitch", { id = 3 })).toBeNil()
		T.expect(command("mapSwitch", { id = { "candy" } })).toBeNil()
		T.expect(command("mapSwitch", {})).toBeNil()
	end)
	T.it("turns rotation on or off with a real boolean", function()
		T.expect(command("mapRotation", { on = false })).toEqual({ kind = "mapRotation", on = false })
		T.expect(command("mapRotation", { on = "false" })).toBeNil()
		T.expect(command("mapRotation", {})).toBeNil()
	end)
	T.it("starts a known modifier for /mod's 0.25-60 minutes (5 when left out)", function()
		T.expect(command("modStart", { id = "rushHour" })).toEqual({ kind = "modStart", id = "rushHour", minutes = 5 })
		T.expect((command("modStart", { id = "rushHour", minutes = 0 }) :: any).minutes).toBe(0.25)
		T.expect((command("modStart", { id = "rushHour", minutes = 1e9 }) :: any).minutes).toBe(60)
		T.expect((command("modStart", { id = "rushHour", minutes = 1.1 }) :: any).minutes).toBe(1)
		T.expect((command("modStart", { id = "rushHour", minutes = 2.4 }) :: any).minutes).toBe(2.5)
		T.expect(command("modStart", { id = "rushHour", minutes = 0 / 0 })).toBeNil()
		T.expect(command("modStart", { id = "rushHour", minutes = math.huge })).toBeNil()
		T.expect(command("modStart", { id = "rushHour", minutes = "5" })).toBeNil()
		T.expect(command("modStart", { id = "rocketJump" })).toBeNil()
	end)
	T.it("drops a known Snackling, plain or with a known mutation", function()
		T.expect(command("beltDrop", { id = "pizza_pup" })).toEqual({ kind = "beltDrop", id = "pizza_pup" })
		T.expect(command("beltDrop", { id = "pizza_pup", mutation = "" }))
			.toEqual({ kind = "beltDrop", id = "pizza_pup" })
		T.expect(command("beltDrop", { id = "pizza_pup", mutation = "rainbow" })).toEqual({
			kind = "beltDrop",
			id = "pizza_pup",
			mutation = "rainbow",
		})
		T.expect(command("beltDrop", { id = "pizza_pup", mutation = "plaid" })).toBeNil()
		T.expect(command("beltDrop", { id = "pizza_pup", mutation = 1 })).toBeNil()
		T.expect(command("beltDrop", { id = "golden" })).toBeNil()
	end)
	T.it("clamps luck to /luck's limits (2x for 15 minutes when left out)", function()
		T.expect(command("luck", {})).toEqual({ kind = "luck", multiplier = 2, minutes = 15 })
		local big = command("luck", { multiplier = 100, minutes = 1e7 }) :: HostRules.Command
		T.expect(big.multiplier).toBe(LiveOps.limits.maxLuckMultiplier)
		T.expect(big.minutes).toBe(24 * 60)
		local small = command("luck", { multiplier = 0.2, minutes = 0 }) :: HostRules.Command
		T.expect(small.multiplier).toBe(1)
		T.expect(small.minutes).toBe(1)
		T.expect((command("luck", { multiplier = 2.34 }) :: any).multiplier).toBe(2.3)
		T.expect((command("luck", { minutes = 7.9 }) :: any).minutes).toBe(8)
		T.expect(command("luck", { multiplier = -math.huge })).toBeNil()
		T.expect(command("luck", { minutes = 0 / 0 })).toBeNil()
	end)
	T.it("starts a configured event, for its own length or /event's 1 minute to 7 days", function()
		T.expect(command("eventStart", { id = "Halloween2026" })).toEqual({ kind = "eventStart", id = "Halloween2026" })
		T.expect((command("eventStart", { id = "Halloween2026", minutes = 1e9 }) :: any).minutes).toBe(7 * 24 * 60)
		T.expect((command("eventStart", { id = "Halloween2026", minutes = 0.2 }) :: any).minutes).toBe(1)
		T.expect(command("eventStart", { id = "Christmas1999" })).toBeNil()
		T.expect(command("eventStart", {})).toBeNil()
	end)
	T.it("ends every started event, or a known one", function()
		T.expect(command("eventStop", {})).toEqual({ kind = "eventStop" })
		T.expect(command("eventStop", { id = "" })).toEqual({ kind = "eventStop" })
		T.expect(command("eventStop", { id = "Winter2026" })).toEqual({ kind = "eventStop", id = "Winter2026" })
		T.expect(command("eventStop", { id = "nope" })).toBeNil()
	end)
	T.it("gifts 1 to 30 minutes of income (5 when left out)", function()
		T.expect(command("gift", {})).toEqual({ kind = "gift", minutes = 5 })
		T.expect((command("gift", { minutes = 0 }) :: any).minutes).toBe(1)
		T.expect((command("gift", { minutes = 600 }) :: any).minutes).toBe(Host.limits.giftMinutes.max)
		T.expect(command("gift", { minutes = "lots" })).toBeNil()
	end)
	T.it("broadcasts trimmed, single-line text up to /announce's 120 characters", function()
		T.expect(command("broadcast", { text = "  Hello!  " })).toEqual({ kind = "broadcast", text = "Hello!" })
		T.expect((command("broadcast", { text = "two\nlines\0" }) :: any).text).toBe("two lines")
		T.expect(command("broadcast", { text = string.rep("a", 120) }) ~= nil).toBe(true)
		T.expect(command("broadcast", { text = string.rep("a", 121) })).toBeNil()
		-- characters, not bytes: 120 emoji (4 bytes each) are fine
		T.expect(command("broadcast", { text = string.rep("🎉", 120) }) ~= nil).toBe(true)
		T.expect(command("broadcast", { text = string.rep("🎉", 121) })).toBeNil()
		T.expect(command("broadcast", { text = "   " })).toBeNil()
		T.expect(command("broadcast", { text = "\255\254" })).toBeNil()
		T.expect(command("broadcast", { text = 5 })).toBeNil()
	end)
	T.it("survives the trip to another server: a command built from its own args is the same command", function()
		local commands: { HostRules.Command } = {
			{ kind = "mapSwitch", id = "volcano" },
			{ kind = "mapVote" },
			{ kind = "mapRotation", on = true },
			{ kind = "modStart", id = "goldenHour", minutes = 2.5 },
			{ kind = "modStop" },
			{ kind = "beltDrop", id = "pizza_pup", mutation = "diamond" },
			{ kind = "luck", multiplier = 3, minutes = 30 },
			{ kind = "eventStart", id = "Winter2026", minutes = 60 },
			{ kind = "eventStop", id = "Winter2026" },
			{ kind = "gift", minutes = 10 },
			{ kind = "broadcast", text = "Admin abuse in 5 minutes!" },
		}
		T.expect(#commands).toBe(#HostRules.ORDER)
		for _, original in commands do
			T.expect(command(original.kind, HostRules.args(original))).toEqual(original)
		end
	end)
end)

T.describe("HostRules.check", function()
	local everything: { HostRules.Command } = {
		{ kind = "mapSwitch", id = "candy" },
		{ kind = "mapVote" },
		{ kind = "mapRotation", on = false },
		{ kind = "modStart", id = "luckyBreeze", minutes = 5 },
		{ kind = "modStop" },
		{ kind = "beltDrop", id = "pizza_pup" },
		{ kind = "luck", multiplier = 2, minutes = 15 },
		{ kind = "eventStart", id = "Winter2026" },
		{ kind = "eventStop" },
		{ kind = "gift", minutes = 5 },
		{ kind = "broadcast", text = "hi" },
	}
	T.it("lets admins do everything, here or in every server", function()
		for _, cmd in everything do
			T.expect(HostRules.check("admin", cmd, "server", Modifiers.modifiers, "jackpot")).toBeNil()
			T.expect(HostRules.check("admin", cmd, "all", Modifiers.modifiers, "jackpot")).toBeNil()
		end
	end)
	T.it("refuses everything to everyone else", function()
		for _, cmd in everything do
			T.expect(HostRules.check("none", cmd, "server", Modifiers.modifiers, nil)).toBe("notAllowed")
		end
	end)
	T.it("lets a private server's owner switch the map and turn rotation on or off", function()
		T.expect(HostRules.check("owner", { kind = "mapSwitch", id = "candy" }, "server", Modifiers.modifiers, nil))
			.toBeNil()
		T.expect(HostRules.check("owner", { kind = "mapRotation", on = false }, "server", Modifiers.modifiers, nil))
			.toBeNil()
	end)
	T.it("lets an owner start and stop only hostable modifiers", function()
		T.expect(HostRules.check("owner", { kind = "modStart", id = "sugarRush" }, "server", Modifiers.modifiers, nil))
			.toBeNil()
		T.expect(
			HostRules.check("owner", { kind = "modStart", id = "luckyBreeze" }, "server", Modifiers.modifiers, nil)
		)
			.toBe("notHostable")
		T.expect(HostRules.check("owner", { kind = "modStop" }, "server", Modifiers.modifiers, "fortress")).toBeNil()
		T.expect(HostRules.check("owner", { kind = "modStop" }, "server", Modifiers.modifiers, "jackpot"))
			.toBe("notHostable")
		T.expect(HostRules.check("owner", { kind = "modStop" }, "server", Modifiers.modifiers, nil)).toBeNil()
	end)
	T.it("keeps belt drops, boosts, events, gifts, messages and votes for admins", function()
		for _, kind in { "mapVote", "beltDrop", "luck", "eventStart", "eventStop", "gift", "broadcast" } do
			for _, cmd in everything do
				if cmd.kind == kind then
					T.expect(HostRules.check("owner", cmd, "server", Modifiers.modifiers, nil)).toBe("adminOnly")
				end
			end
		end
	end)
	T.it("never lets an owner reach other servers", function()
		T.expect(HostRules.check("owner", { kind = "mapSwitch", id = "candy" }, "all", Modifiers.modifiers, nil))
			.toBe("adminOnly")
		T.expect(HostRules.check("owner", { kind = "modStart", id = "sugarRush" }, "all", Modifiers.modifiers, nil))
			.toBe("adminOnly")
	end)
	T.it("keeps rotation in this server whatever the scope", function()
		T.expect(HostRules.effectiveScope({ kind = "mapRotation", on = true }, "all")).toBe("server")
		T.expect(HostRules.effectiveScope({ kind = "mapSwitch", id = "candy" }, "all")).toBe("all")
		T.expect(HostRules.effectiveScope({ kind = "gift", minutes = 5 }, "server")).toBe("server")
	end)
	T.it("has a line of text for every refusal", function()
		for _, key in HostRules.REFUSALS do
			local textKey = "hostRefused" .. string.upper(string.sub(key, 1, 1)) .. string.sub(key, 2)
			T.expect(type((Theme.text :: any)[textKey])).toBe("string")
		end
	end)
end)

T.describe("HostRules cooldowns", function()
	T.it("gives owners about a minute between map switches and ten between modifiers", function()
		local group, seconds = HostRules.cooldown("owner", "mapSwitch", Host)
		T.expect(group).toBe("map")
		T.expect(seconds).toBe(60)
		group, seconds = HostRules.cooldown("owner", "modStart", Host)
		T.expect(group).toBe("modifier")
		T.expect(seconds).toBe(600)
		T.expect((HostRules.cooldown("owner", "mapRotation", Host))).toBeNil()
		T.expect((HostRules.cooldown("owner", "modStop", Host))).toBeNil()
	end)
	T.it("gives admins none but a short one on gifts (a double tap never pays twice)", function()
		T.expect((HostRules.cooldown("admin", "mapSwitch", Host))).toBeNil()
		T.expect((HostRules.cooldown("admin", "modStart", Host))).toBeNil()
		local group, seconds = HostRules.cooldown("admin", "gift", Host)
		T.expect(group).toBe("gift")
		T.expect(seconds).toBe(Host.admin.giftCooldownSeconds)
	end)
	T.it("holds until its time is up", function()
		local cooldowns: HostRules.Cooldowns = {}
		T.expect(HostRules.waitSeconds(cooldowns, "map", 1000)).toBe(0)
		HostRules.startCooldown(cooldowns, "map", 60, 1000)
		T.expect(HostRules.waitSeconds(cooldowns, "map", 1000)).toBe(60)
		T.expect(HostRules.waitSeconds(cooldowns, "map", 1059)).toBe(1)
		T.expect(HostRules.waitSeconds(cooldowns, "map", 1060)).toBe(0)
		T.expect(HostRules.waitSeconds(cooldowns, "modifier", 1000)).toBe(0)
	end)
	T.it("tells the client the role and when each cooldown is ready", function()
		local cooldowns: HostRules.Cooldowns = { map = 1060 }
		local view = HostRules.view("owner", false, cooldowns)
		T.expect(view.role).toBe("owner")
		T.expect(view.mapReadyAt).toBe(1060)
		T.expect(view.modifierReadyAt).toBe(0)
		T.expect(HostRules.view("none", false, {}).role).toBe("")
		T.expect(HostRules.view("admin", true, {}).studio).toBe(true)
	end)
end)

T.describe("HostRules.giftAmount", function()
	T.it("pays minutes of steady income like a cash pack, never below the minimum", function()
		T.expect(HostRules.giftAmount(0, 5, Host)).toBe(5 * Host.gift.minimumPerMinute)
		T.expect(HostRules.giftAmount(1000, 10, Host)).toBe(600000)
		T.expect(HostRules.giftAmount(0 / 0, 5, Host)).toBe(5 * Host.gift.minimumPerMinute)
	end)
end)

T.describe("Config/Host", function()
	T.it("validates", function()
		local problems = HostRules.validate(Host, LiveOps.limits.maxLuckMultiplier)
		if #problems > 0 then
			print(table.concat(problems, "\n"))
		end
		T.expect(#problems).toBe(0)
	end)
	T.it("keeps the limits the chat commands have always had", function()
		T.expect(Host.limits.modifierMinutes.min).toBe(0.25)
		T.expect(Host.limits.modifierMinutes.max).toBe(60)
		T.expect(Host.limits.luckMinutes.min).toBe(1)
		T.expect(Host.limits.luckMinutes.max).toBe(24 * 60)
		T.expect(Host.limits.eventMinutes.max).toBe(7 * 24 * 60)
		T.expect(Host.limits.luckMultiplier.max).toBe(LiveOps.limits.maxLuckMultiplier)
		T.expect(Host.limits.broadcastLength).toBe(120)
	end)
	T.it("catches broken numbers", function()
		local broken = table.clone(Host) :: any
		broken.limits = table.clone(Host.limits)
		broken.limits.luckMultiplier = { min = 1, max = 10, default = 2 }
		broken.limits.giftMinutes = { min = 5, max = 1 }
		broken.messaging = table.clone(Host.messaging)
		broken.messaging.shoutTopic = Host.messaging.hostTopic
		broken.messaging.maxBytes = 5000
		local problems = HostRules.validate(broken, LiveOps.limits.maxLuckMultiplier)
		T.expect(#problems).toBeAtLeast(4)
	end)
	T.it("only lets owners start modifiers that leave the economy alone", function()
		local problems = HostRules.hostableProblems(Modifiers, weatherUnlocks())
		if #problems > 0 then
			print(table.concat(problems, "\n"))
		end
		T.expect(#problems).toBe(0)
	end)
	T.it("ships the four chase twists as the hostable set", function()
		local hostable: { string } = {}
		for _, id in Modifiers.order do
			if Modifiers.modifiers[id].hostable then
				table.insert(hostable, id)
			end
		end
		T.expect(hostable).toEqual({ "sugarRush", "quickHands", "fortress", "snackPatrol" })
	end)
	T.it("refuses a hostable modifier that touches luck, mutations, income, prices, the belt or drops", function()
		local unlocks = weatherUnlocks()
		for _, id in
			{ "luckyBreeze", "goldenHour", "cashSplash", "clearanceSale", "rushHour", "supplyDrop", "thunderstorm" }
		do
			local config = table.clone(Modifiers) :: Types.ModifiersConfig
			config.modifiers = table.clone(Modifiers.modifiers)
			local def = table.clone(config.modifiers[id])
			def.hostable = true
			config.modifiers[id] = def
			T.expect(#HostRules.hostableProblems(config, unlocks)).toBe(1)
		end
	end)
	T.it("needs at least one hostable modifier", function()
		local config = table.clone(Modifiers) :: Types.ModifiersConfig
		config.modifiers = {}
		for id, def in Modifiers.modifiers do
			local copy = table.clone(def)
			copy.hostable = nil
			config.modifiers[id] = copy
		end
		T.expect(#HostRules.hostableProblems(config, {})).toBe(1)
	end)
	T.it("names real rarities and mutations for shout-outs", function()
		T.expect(catalog.rarities[Host.shoutouts.rarity] ~= nil).toBe(true)
		T.expect(catalog.rarities[Host.shoutouts.mutatedRarity] ~= nil).toBe(true)
		for _, id in Host.shoutouts.mutations do
			T.expect(catalog.mutations[id] ~= nil).toBe(true)
		end
	end)
end)

return nil
