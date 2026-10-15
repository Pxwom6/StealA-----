--!strict
--[[
	The host panel, cross-server LiveOps and shout-outs, offline (CI runs it after the server test):
	    lune run tools/worldsim/host.luau

	Boots the whole server like tools/worldsim/server.luau, but as a live server (not Studio, so only Config/LiveOps
	admins and a private server's owner may host), with the MessagingService stand-in (Sim.messaging: publishes are
	recorded and come back to this server, Sim.deliver brings messages "from other servers"). Then, through the real
	HostAction intent:
	  * an admin switches the map, runs a modifier, drops a Snackling that appears on the belt, gifts everyone, starts
	    luck and an event, sends a filtered message, turns rotation off and on and starts a vote;
	  * a normal player is refused all of it, silently;
	  * an "All servers" action is published once as a versioned message and runs here once; another server's
	    message runs once and is ignored when it is a copy, stale, from the future, malformed, from a non-admin or a
	    per-server action; with MessagingService down it still runs here and says so; the send cap and the intent's
	    rate limit hold;
	  * a private server's owner switches the map but can't again within the cooldown, never reaches other servers,
	    runs only hostable modifiers and stops only their own (and their cooldown holds, even after rejoining), and is
	    refused everything else;
	  * a Secret pull publishes one shout-out (an admin drop none), the publish limit holds, and shout-outs from other
	    servers show at most one per interval, never to a player in the tutorial.
	It fails on any error, any unexpected warning, or any check below.
]]

local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local task = require("@lune/task")
local Sim = require("./Sim")
local MockProfileStore = require("./MockProfileStore")

Sim.isStudio = false -- a live server: only admins and a private server's owner may host
Sim.mock("ServerPackages/ProfileStore.lua", MockProfileStore)
Sim.filter = function(text: string): string
	return (string.gsub(text, "darn", "####"))
end

-- Warnings the scenario causes on purpose.
local EXPECTED_WARNINGS = { "[CrossServer] could not send" }

local failures: { string } = {}
local function check(ok: boolean, message: string)
	if ok then
		print(`  ok   {message}`)
	else
		print(`  FAIL {message}`)
		table.insert(failures, message)
	end
end

local function finish()
	for _, message in Sim.warnings do
		local expected = false
		for _, pattern in EXPECTED_WARNINGS do
			if string.find(message, pattern, 1, true) then
				expected = true
			end
		end
		if not expected then
			table.insert(failures, `warning: {message}`)
			print(`  FAIL warning: {message}`)
		end
	end
	if #failures > 0 then
		print(`host test: {#failures} problem(s)`)
		process.exit(1)
	end
	print("host test: no problems")
	process.exit(0)
end

local ok, err = pcall(function()
	Sim.require("ServerScriptService", "Server")
end)
if not ok then
	print(`the server failed to boot: {err}`)
	process.exit(1)
end

local Analytics = Sim.server("Services/Analytics")
local BeltService = Sim.server("Services/BeltService")
local CrossServer = Sim.server("Services/CrossServer")
local EconomyService = Sim.server("Services/EconomyService")
local HostService = Sim.server("Services/HostService")
local MapThemeService = Sim.server("Services/MapThemeService")
local ModifierService = Sim.server("Services/ModifierService")
local PlotService = Sim.server("Services/PlotService")
local PrizeService = Sim.server("Services/PrizeService")
local Sessions = Sim.server("Services/Sessions")
local GameData = Sim.shared("GameData")
local Gameplay = Sim.shared("Config/Gameplay")
local Host = Sim.shared("Config/Host")
local MapThemes = Sim.shared("Config/MapThemes")
local Theme = Sim.shared("Config/Theme")
local HostRules = Sim.shared("Logic/HostRules")
local workspace = Sim.workspace()

local ADMIN = 723735722 -- Config/LiveOps.adminUserIds
local ALICE = 3003
local OWNER = 2002
local HOST_TOPIC = Host.messaging.hostTopic
local SHOUT_TOPIC = Host.messaging.shoutTopic

-- Every analytics custom event the server logs.
local logged: { { name: string, value: any, fields: { string }? } } = {}
local realCustom = Analytics.custom
Analytics.custom = function(session: any, name: string, value: number?, fields: { string }?)
	table.insert(logged, { name = name, value = value, fields = fields })
	realCustom(session, name, value, fields)
end

local function sessionOf(player: any): any
	return Sessions.get(player)
end

local function join(userId: number, name: string): any
	local player = Sim.addPlayer(userId, name)
	task.wait(0.2)
	local session = sessionOf(player)
	assert(session, `{name} has no session`)
	Sim.spawnCharacter(player, PlotService.refs(session.plot).spawnCFrame.Position)
	Sim.fireServer(player, "ClientReady")
	task.wait(0.2)
	return player
end

-- Sends HostAction like the panel does, never faster than the intent's rate limit lets through (this mirrors the
-- server's token bucket, so every action here is really handled; the limit itself is checked on its own below).
local limit = Gameplay.rateLimits.HostAction
type Bucket = { tokens: number, at: number }
local buckets: { [number]: Bucket } = {}
local function act(player: any, kind: any, scope: any, args: any)
	local userId: number = player.UserId
	local bucket: Bucket = buckets[userId] or { tokens = limit.burst :: number, at = os.clock() }
	buckets[userId] = bucket
	local function refill()
		local t = os.clock()
		bucket.tokens = math.min(limit.burst, bucket.tokens + (t - bucket.at) * limit.perSecond)
		bucket.at = t
	end
	refill()
	if bucket.tokens < 1.05 then
		task.wait((1.05 - bucket.tokens) / limit.perSecond + 0.05)
		refill()
	end
	bucket.tokens -= 1
	Sim.fireServer(player, "HostAction", kind, scope, args)
	task.wait(0.05)
end

local function toasts(userId: number): { string }
	local list = {}
	for _, args in Sim.received(userId, "Notify") do
		table.insert(list, args[1].text)
	end
	return list
end

local function lastToast(userId: number): string
	local list = toasts(userId)
	return list[#list] or ""
end

local function announcements(userId: number, kind: string?): { any }
	local list = {}
	for _, args in Sim.received(userId, "Announce") do
		if kind == nil or args[1].kind == kind then
			table.insert(list, args[1])
		end
	end
	return list
end

-- (Times are read from the services, not from workspace attributes: Lune keeps number attributes as 32-bit floats,
-- which round a server time of 1.8e9 to a multiple of 128 s. Roblox keeps them as doubles.)

-- The host view the player's client got last (StateUpdate goes out at most 5 times a second).
local function hostView(userId: number): any
	task.wait(1 / Gameplay.replicationHz + 0.05)
	local list = Sim.received(userId, "StateUpdate")
	local last = list[#list]
	return if last then last[1].host else nil
end

local function beltSpawns(creatureId: string): number
	local count = 0
	for _, args in Sim.received(0, "BeltSpawn") do
		if args[1].creatureId == creatureId then
			count += 1
		end
	end
	return count
end

local function lastBeltItem(creatureId: string): any
	local found = nil
	for _, args in Sim.received(0, "BeltSpawn") do
		if args[1].creatureId == creatureId then
			found = args[1]
		end
	end
	return found
end

-- Walks `player` to belt item `item` and buys it.
local function buyItem(player: any, item: any)
	local belt = BeltService.belt()
	Sim.moveCharacter(player, roblox.Vector3.new(belt.startX + 2, 3, Gameplay.belt.width / 2 + 3))
	Sim.fireServer(player, "BuyBeltItem", item.id)
	task.wait(0.1)
end

-- Puts `creatureId` (with `variant`) on the belt as the game would, without an admin, and has `player` buy it.
local function pull(player: any, creatureId: string, variant: string?)
	BeltService.spawnCreature(creatureId, variant)
	task.wait(0.05)
	buyItem(player, lastBeltItem(creatureId))
end

-- The messages this server published on `topic`, decoded.
local function published(topic: string): { any }
	local list = {}
	for _, entry in Sim.messaging.published do
		if entry.topic == topic then
			table.insert(list, serde.decode("json", entry.data))
		end
	end
	return list
end

local guid = 0
-- A message from another server on `topic` (fields overridden by `overrides`), delivered here. Returns its JSON.
local function fromAnotherServer(topic: string, kind: string, args: any, overrides: { [string]: any }?): string
	guid += 1
	local message: { [string]: any } = {
		v = Host.messaging.version,
		kind = kind,
		args = args,
		from = ADMIN,
		id = string.format("AAAAAAAA-0000-4000-8000-%012d", guid),
		at = Sim.now,
	}
	local extra: { [string]: any } = overrides or {}
	for key, value in extra do
		message[key] = value
	end
	local json = serde.encode("json", message)
	Sim.deliver(topic, json)
	task.wait(0.1)
	return json
end

local function firstOf(rarity: string): any
	for _, def in GameData.catalog.creatureList do
		if def.rarity == rarity and def.eventId == nil then
			return def
		end
	end
	error(`no {rarity} Snackling`)
end

local function anotherMap(than: string): string
	for _, id in MapThemes.order do
		if id ~= than then
			return id
		end
	end
	error("only one map")
end

local function scenario()
	print("host test:")
	local leo = join(ADMIN, "Leo")
	local alice = join(ALICE, "Alice")
	local leoSession, aliceSession = sessionOf(leo), sessionOf(alice)
	Sim.fireServer(leo, "SkipTutorial")
	Sim.fireServer(alice, "SkipTutorial")
	task.wait(0.3)
	check(leoSession.tutorial == nil and aliceSession.tutorial == nil, "both skipped the first-time tutorial")
	check(
		CrossServer.subscribed("host") and CrossServer.subscribed("shout"),
		"the server listens for admin actions and shout-outs"
	)
	local secret, mythic, common = firstOf("Secret"), firstOf("Mythic"), firstOf("Common")

	-- Who may host ---------------------------------------------------------------------------------------------------
	check(hostView(ADMIN) ~= nil and hostView(ADMIN).role == "admin", "the admin's client is told it may host")
	check(hostView(ALICE) ~= nil and hostView(ALICE).role == "", "a normal player's client hears nothing (no row)")

	-- An admin, this server ------------------------------------------------------------------------------------------
	local startMap = workspace:GetAttribute("MapTheme")
	local target = anotherMap(startMap)
	act(leo, "mapSwitch", "server", { id = target })
	check(workspace:GetAttribute("MapTheme") == target, `the admin switches the map ({target})`)
	local entry = logged[#logged]
	check(
		entry ~= nil
			and entry.name == "host_action"
			and entry.fields ~= nil
			and entry.fields[1] == "mapSwitch"
			and entry.fields[2] == "admin"
			and entry.fields[3] == target,
		"and it is logged as a host_action analytics event (action, who, what)"
	)

	act(leo, "modStart", "server", { id = "rushHour", minutes = 2 })
	local endsIn = ModifierService.endsAt() - Sim.now
	check(workspace:GetAttribute("Modifier") == "rushHour", "the admin starts a modifier")
	check(math.abs(endsIn - 120) < 1, `for the minutes asked ({endsIn} s)`)
	act(leo, "modStop", "server", {})
	check(workspace:GetAttribute("Modifier") == "", "and stops it")

	local spawns = beltSpawns(secret.id)
	act(leo, "beltDrop", "server", { id = secret.id, mutation = "rainbow" })
	local dropped = lastBeltItem(secret.id)
	check(
		beltSpawns(secret.id) == spawns + 1 and dropped.variant == "rainbow",
		`an admin drop puts a Rainbow {secret.displayName} on the belt`
	)
	local banners = announcements(ALICE, "drop")
	check(
		#banners > 0 and string.find(banners[#banners].text, "ADMIN DROP", 1, true) ~= nil,
		`announced to the server ({if #banners > 0 then banners[#banners].text else "none"})`
	)

	local aliceCash, leoCash = aliceSession.data.cash, leoSession.data.cash
	local aliceGift = HostRules.giftAmount(aliceSession.packIncome, 5, Host)
	act(leo, "gift", "server", { minutes = 5 })
	check(
		aliceSession.data.cash == aliceCash + aliceGift,
		`"Gift everyone" pays Alice 5 minutes of income ({aliceGift})`
	)
	check(leoSession.data.cash > leoCash, "and the admin too")
	check(string.find(lastToast(ALICE), "gift from the host", 1, true) ~= nil, "with a toast")
	aliceCash = aliceSession.data.cash
	act(leo, "gift", "server", { minutes = 5 })
	check(aliceSession.data.cash == aliceCash, "a second gift right away (a double tap) pays nothing")
	check(string.find(lastToast(ADMIN), "Wait", 1, true) ~= nil, `and the admin is told to wait ({lastToast(ADMIN)})`)

	act(leo, "luck", "server", { multiplier = 3, minutes = 10 })
	check(workspace:GetAttribute("LuckMultiplier") == 3, "the admin starts 3x luck")
	act(leo, "eventStart", "server", { id = "Winter2026", minutes = 5 })
	task.wait(0.2)
	check(
		string.find(workspace:GetAttribute("ActiveEventIds") :: string, "Winter2026", 1, true) ~= nil,
		"starts a configured event"
	)
	act(leo, "eventStop", "server", {})
	task.wait(0.2)
	check(string.find(workspace:GetAttribute("ActiveEventIds") :: string, "Winter2026", 1, true) == nil, "and ends it")
	act(leo, "broadcast", "server", { text = "  Party at the darn belt!  " })
	local said = announcements(ALICE, "admin")
	check(
		#said > 0 and said[#said].text == "Party at the #### belt!",
		`a message goes out filtered and trimmed ({if #said > 0 then said[#said].text else "none"})`
	)
	act(leo, "mapRotation", "server", { on = false })
	check(workspace:GetAttribute("MapRotation") == false, "rotation off for this server")
	check(workspace:GetAttribute("MapThemeEndsAt") == 0, "so no next map is coming")
	act(leo, "mapRotation", "server", { on = true })
	check(workspace:GetAttribute("MapRotation") == true, "and back on")
	act(leo, "mapVote", "server", {})
	check(workspace:GetAttribute("MapVoteEndsAt") ~= 0, "the admin starts a map vote")

	local mapNow = workspace:GetAttribute("MapTheme")
	act(leo, "mapSwitch", "server", { id = "atlantis" })
	check(workspace:GetAttribute("MapTheme") == mapNow, "an unknown map is refused")
	check(lastToast(ADMIN) == Theme.text.hostInvalid, "with a toast")
	act(leo, "modStart", "server", { id = "rushHour", minutes = 0 / 0 })
	check(workspace:GetAttribute("Modifier") == "", "NaN minutes are refused")
	act(leo, "teleport", "server", {})
	act(leo, "mapSwitch", "everywhere", { id = target })
	check(lastToast(ADMIN) == Theme.text.hostInvalid, "so are an unknown action and an unknown scope")

	-- A normal player: nothing ---------------------------------------------------------------------------------------
	-- Everything a host action could change (the belt keeps spawning on its own, so only host banners count).
	local function snapshot(): string
		local hostBanners = 0
		for _, banner in announcements(0) do
			if
				banner.kind == "drop"
				or banner.kind == "admin"
				or banner.kind == "luck"
				or banner.kind == "modifier"
			then
				hostBanners += 1
			end
		end
		return table.concat({
			tostring(MapThemeService.current()),
			tostring(MapThemeService.rotationOn()),
			tostring(workspace:GetAttribute("MapVoteEndsAt")),
			tostring(ModifierService.current()),
			tostring(workspace:GetAttribute("LuckMultiplier")),
			tostring(workspace:GetAttribute("ActiveEventIds")),
			tostring(hostBanners),
			tostring(aliceSession.data.cash),
			tostring(leoSession.data.cash),
			tostring(#Sim.messaging.published),
		}, "|")
	end
	local before = snapshot()
	local aliceToasts = #toasts(ALICE)
	local tries: { { any } } = {
		{ "mapSwitch", { id = startMap } },
		{ "mapVote", {} },
		{ "mapRotation", { on = false } },
		{ "modStart", { id = "sugarRush" } },
		{ "modStop", {} },
		{ "beltDrop", { id = secret.id } },
		{ "luck", { multiplier = 6, minutes = 60 } },
		{ "eventStart", { id = "Winter2026" } },
		{ "eventStop", {} },
		{ "gift", { minutes = 30 } },
		{ "broadcast", { text = "free robux" } },
	}
	for _, try in tries do
		act(alice, try[1], "server", try[2])
		act(alice, try[1], "all", try[2])
	end
	check(snapshot() == before, "a normal player is refused every action, here and for every server")
	check(#toasts(ALICE) == aliceToasts, "and told nothing at all")

	-- All servers ----------------------------------------------------------------------------------------------------
	Sim.advance(Host.admin.giftCooldownSeconds + 1)
	aliceCash = aliceSession.data.cash
	local gift = HostRules.giftAmount(aliceSession.packIncome, 2, Host)
	act(leo, "gift", "all", { minutes = 2 })
	task.wait(0.2) -- this server's own copy comes back
	local sent = published(HOST_TOPIC)
	local message = sent[1]
	check(#sent == 1, "an All-servers action is published once")
	check(
		message ~= nil
			and message.v == Host.messaging.version
			and message.kind == "gift"
			and message.args.minutes == 2
			and message.from == ADMIN
			and type(message.id) == "string"
			and #message.id == 36
			and math.abs(message.at - Sim.now) < 1,
		"as one small versioned message: kind, args, sender, a GUID and the server time"
	)
	check(aliceSession.data.cash == aliceCash + gift, "it runs here once, even after its own copy came back")
	check(string.find(lastToast(ADMIN), "every server", 1, true) ~= nil, "and the admin hears it went out")
	Sim.deliver(HOST_TOPIC, Sim.messaging.published[#Sim.messaging.published].data)
	task.wait(0.1)
	check(aliceSession.data.cash == aliceCash + gift, "a copy delivered again is ignored")

	spawns = beltSpawns(secret.id)
	local json = fromAnotherServer(HOST_TOPIC, "beltDrop", { id = secret.id })
	check(beltSpawns(secret.id) == spawns + 1, "another server's admin drop lands on this belt")
	Sim.deliver(HOST_TOPIC, json)
	task.wait(0.1)
	check(beltSpawns(secret.id) == spawns + 1, "once, however often the message arrives")
	fromAnotherServer(HOST_TOPIC, "beltDrop", { id = secret.id }, { at = Sim.now - Host.messaging.maxAgeSeconds - 5 })
	check(beltSpawns(secret.id) == spawns + 1, "a message older than a minute is ignored")
	fromAnotherServer(HOST_TOPIC, "beltDrop", { id = secret.id }, { at = Sim.now + 120 })
	check(beltSpawns(secret.id) == spawns + 1, "so is one from the future")
	fromAnotherServer(HOST_TOPIC, "beltDrop", { id = secret.id }, { from = ALICE })
	check(beltSpawns(secret.id) == spawns + 1, "and one an admin didn't send")
	fromAnotherServer(HOST_TOPIC, "beltDrop", { id = secret.id }, { v = Host.messaging.version + 1 })
	check(beltSpawns(secret.id) == spawns + 1, "and one of another version")
	mapNow = workspace:GetAttribute("MapTheme")
	fromAnotherServer(HOST_TOPIC, "mapSwitch", { id = "atlantis" })
	check(workspace:GetAttribute("MapTheme") == mapNow, "arguments are validated again on arrival (no such map)")
	fromAnotherServer(HOST_TOPIC, "mapRotation", { on = false })
	check(workspace:GetAttribute("MapRotation") == true, "rotation is per server: never set from another one")
	fromAnotherServer(HOST_TOPIC, "modStart", { id = "fortress", minutes = 1e9 })
	endsIn = ModifierService.endsAt() - Sim.now
	check(
		workspace:GetAttribute("Modifier") == "fortress" and math.abs(endsIn - 3600) < 1,
		`and clamped to the same limits ({endsIn} s)`
	)

	Sim.messaging.online = false
	local switchTo = anotherMap(workspace:GetAttribute("MapTheme"))
	act(leo, "mapSwitch", "all", { id = switchTo })
	task.wait(0.2)
	check(workspace:GetAttribute("MapTheme") == switchTo, "with MessagingService down an All-servers action runs here")
	check(lastToast(ADMIN) == Theme.text.hostAllFailed, "and the admin is told it ran in this server only")
	Sim.messaging.online = true

	Sim.advance(120) -- the send cap refills
	local count = #published(HOST_TOPIC)
	for _ = 1, Host.messaging.sendBurst + 1 do
		act(leo, "mapVote", "all", {})
	end
	check(#published(HOST_TOPIC) == count + Host.messaging.sendBurst, "the send cap holds")
	check(lastToast(ADMIN) == Theme.text.hostAllBusy, "and says to wait a moment")

	task.wait(limit.burst / limit.perSecond + 0.3) -- the intent's bucket fills up
	spawns = beltSpawns(common.id)
	for _ = 1, limit.burst * 2 do
		Sim.fireServer(leo, "HostAction", "beltDrop", "server", { id = common.id })
	end
	task.wait(0.1)
	buckets[ADMIN] = { tokens = 0, at = os.clock() }
	check(beltSpawns(common.id) - spawns == limit.burst, `the intent's rate limit drops a burst of taps beyond it`)

	-- A private server's owner -------------------------------------------------------------------------------------------
	Sim.gameProperties.PrivateServerId = "private-test"
	Sim.gameProperties.PrivateServerOwnerId = OWNER
	local owen = join(OWNER, "Owen") -- stays in the first-time tutorial
	local owenSession = sessionOf(owen)
	check(hostView(OWNER) ~= nil and hostView(OWNER).role == "owner", "a private server's owner may host")
	check(HostService.role(ALICE) == "none", "other players in it still may not")
	act(leo, "modStop", "server", {})
	mapNow = workspace:GetAttribute("MapTheme")
	target = anotherMap(mapNow)
	act(owen, "mapSwitch", "server", { id = target })
	check(workspace:GetAttribute("MapTheme") == target, "the owner switches the map")
	local readyIn = hostView(OWNER).mapReadyAt - Sim.now
	check(math.abs(readyIn - Host.owner.mapCooldownSeconds) < 1, `and their client sees the cooldown ({readyIn} s)`)
	act(owen, "mapSwitch", "server", { id = mapNow })
	check(workspace:GetAttribute("MapTheme") == target, "but not again within the cooldown")
	check(string.find(lastToast(OWNER), "Wait", 1, true) ~= nil, `(told: {lastToast(OWNER)})`)
	Sim.advance(Host.owner.mapCooldownSeconds + 1)
	act(owen, "mapSwitch", "server", { id = mapNow })
	check(workspace:GetAttribute("MapTheme") == mapNow, "after it, again")
	count = #Sim.messaging.published
	Sim.advance(Host.owner.mapCooldownSeconds + 1)
	act(owen, "mapSwitch", "all", { id = target })
	check(workspace:GetAttribute("MapTheme") == mapNow and #Sim.messaging.published == count, "never for every server")
	check(lastToast(OWNER) == Theme.text.hostRefusedAdminOnly, "(admins only)")
	act(owen, "mapRotation", "server", { on = false })
	check(workspace:GetAttribute("MapRotation") == false, "the owner turns rotation off")
	-- forty minutes went by: the schedule may be running one (its loop looks once a second), which only an admin
	-- may stop (review2.luau)
	task.wait(1.1)
	act(leo, "modStop", "server", {})

	act(owen, "modStart", "server", { id = "luckyBreeze" })
	check(workspace:GetAttribute("Modifier") == "", "a modifier that touches the economy is refused")
	check(lastToast(OWNER) == Theme.text.hostRefusedNotHostable, "(not hostable)")
	act(owen, "modStart", "server", { id = "sugarRush", minutes = 5 })
	check(workspace:GetAttribute("Modifier") == "sugarRush", "a hostable one runs")
	act(owen, "modStart", "server", { id = "fortress" })
	check(workspace:GetAttribute("Modifier") == "sugarRush", "but not another within ten minutes")
	act(owen, "modStop", "server", {})
	check(workspace:GetAttribute("Modifier") == "", "the owner stops their own")
	act(leo, "modStart", "server", { id = "jackpot" })
	act(owen, "modStop", "server", {})
	check(workspace:GetAttribute("Modifier") == "jackpot", "but not one they couldn't have started")
	act(leo, "modStop", "server", {})

	before = snapshot()
	for _, try in tries do
		if try[1] ~= "mapSwitch" and try[1] ~= "mapRotation" and try[1] ~= "modStart" and try[1] ~= "modStop" then
			act(owen, try[1], "server", try[2])
			check(lastToast(OWNER) == Theme.text.hostRefusedAdminOnly, `the owner can't {try[1]}`)
		end
	end
	check(snapshot() == before, "and nothing changed")

	Sim.removePlayer(owen)
	task.wait(0.3)
	owen = join(OWNER, "Owen")
	owenSession = sessionOf(owen)
	act(owen, "modStart", "server", { id = "fortress" })
	check(workspace:GetAttribute("Modifier") == "", "leaving and rejoining doesn't reset the cooldown")
	Sim.advance(Host.owner.modifierCooldownSeconds + 1)
	task.wait(1.1)
	act(leo, "modStop", "server", {}) -- (the schedule's, if it started one meanwhile)
	act(owen, "modStart", "server", { id = "fortress" })
	check(workspace:GetAttribute("Modifier") == "fortress", "after ten minutes the owner may start another")
	act(owen, "modStop", "server", {})

	-- Shout-outs ---------------------------------------------------------------------------------------------------------
	EconomyService.addCash(aliceSession, 1e15)
	Sim.advance(Host.shoutouts.publishEverySeconds + 1)
	pull(alice, secret.id)
	task.wait(0.2)
	local shouts = published(SHOUT_TOPIC)
	local shout = shouts[1]
	check(#shouts == 1, "Alice's Secret from the belt publishes a shout-out")
	check(
		shout ~= nil
			and shout.kind == "shoutout"
			and shout.args.name == "Alice"
			and shout.args.creature == secret.id
			and shout.args.mutation == nil
			and shout.from == ALICE,
		"naming her and the Snackling, nothing more"
	)
	check(#announcements(ALICE, "shoutout") == 0, "this server doesn't shout its own find back at itself")
	pull(alice, secret.id)
	check(#published(SHOUT_TOPIC) == 1, "another Secret within 30 s publishes nothing")
	Sim.advance(Host.shoutouts.publishEverySeconds + 1)
	act(leo, "beltDrop", "server", { id = secret.id })
	buyItem(alice, lastBeltItem(secret.id))
	check(#published(SHOUT_TOPIC) == 1, "an admin drop is no rare pull")
	pull(alice, mythic.id)
	check(#published(SHOUT_TOPIC) == 1, "nor a plain Mythic")
	pull(alice, mythic.id, "rainbow")
	shouts = published(SHOUT_TOPIC)
	check(#shouts == 2 and shouts[2].args.mutation == "rainbow", "but a Rainbow Mythic is")
	Sim.advance(Host.shoutouts.publishEverySeconds + 1)
	PrizeService.giveOrSell(aliceSession, secret, nil, "SupplyCrate")
	check(#published(SHOUT_TOPIC) == 3, "and so is a Secret from a crate (any prize)")

	local leoShouts, aliceShouts = #announcements(ADMIN, "shoutout"), #announcements(ALICE, "shoutout")
	check(owenSession.tutorial ~= nil, "Owen is still in the first-time tutorial")
	fromAnotherServer(SHOUT_TOPIC, "shoutout", { name = "Bob", creature = secret.id })
	local seen = announcements(ALICE, "shoutout")
	local expected = `🌍 Bob found a SECRET {secret.displayName} in another server!`
	check(
		#seen == aliceShouts + 1 and seen[#seen].text == expected,
		`another server's shout-out shows here ({if #seen > 0 then seen[#seen].text else "none"})`
	)
	check(#announcements(ADMIN, "shoutout") == leoShouts + 1, "to everyone")
	check(#announcements(OWNER, "shoutout") == 0, "but a player in the tutorial")
	fromAnotherServer(SHOUT_TOPIC, "shoutout", { name = "Cara", creature = secret.id })
	check(#announcements(ALICE, "shoutout") == aliceShouts + 1, "a second within 20 s isn't shown")
	Sim.advance(Host.shoutouts.showEverySeconds + 1)
	fromAnotherServer(SHOUT_TOPIC, "shoutout", { name = "Dan", creature = "made_up_snackling" })
	fromAnotherServer(SHOUT_TOPIC, "shoutout", { name = "Dan", creature = common.id })
	fromAnotherServer(SHOUT_TOPIC, "shoutout", { name = string.rep("D", 40), creature = secret.id })
	check(
		#announcements(ALICE, "shoutout") == aliceShouts + 1,
		"nor one naming no real Snackling, a dull one or no name"
	)
	fromAnotherServer(SHOUT_TOPIC, "shoutout", { name = "Dan", creature = mythic.id, mutation = "diamond" })
	seen = announcements(ALICE, "shoutout")
	check(#seen == aliceShouts + 2, `after 20 s the next one shows ({if #seen > 0 then seen[#seen].text else "none"})`)
end

local passed, problem = pcall(scenario :: () -> ...any)
if not passed then
	print(`  FAIL the scenario stopped: {problem}`)
	table.insert(failures, tostring(problem))
end
finish()
