--!strict
--[[
	The review round 3 server fixes, offline (CI runs it after the review 2 test):
	    lune run tools/worldsim/review3.luau

	Boots the whole server like tools/worldsim/review2.luau, with the clock virtual (Sim.virtualClock) in mid-October
	2026, random modifiers and the map rotation off. Then it plays each fixed finding of the third review that needs
	a server (DECISIONS.md "Final pre-launch pass") through the real remotes and chat commands:

	  * "Need $X more?" (CashOfferService): nothing in a player's first 10 minutes of play; then only a small pack, at
	    most one offer per 3 minutes; a gap of 45 s of income or less is told in seconds; one no small pack covers
	    gets the plain toast

	It fails on any error, any unexpected warning, or any check below.
]]

local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")
local Sim = require("./Sim")
local MockProfileStore = require("./MockProfileStore")

local Vector3 = roblox.Vector3
local OCTOBER_15_2026 = 1792023721

local KIM = 9301

Sim.mock("ServerPackages/ProfileStore.lua", MockProfileStore)
Sim.virtualClock = true
Sim.now = OCTOBER_15_2026
Sim.shared("Config/Modifiers").schedule.enabled = false -- only /mod starts one
Sim.shared("Config/MapThemes").rotation.enabled = false

local EXPECTED_WARNINGS = { "MessagingService.SubscribeAsync is not available offline" }

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
		print(`review 3 test: {#failures} problem(s)`)
		process.exit(1)
	end
	print("review 3 test: no problems")
	process.exit(0)
end

local booted, bootError = pcall(function()
	Sim.require("ServerScriptService", "Server")
end)
if not booted then
	print(`the server failed to boot: {bootError}`)
	process.exit(1)
end

local Sessions = Sim.server("Services/Sessions")
local PlotService = Sim.server("Services/PlotService")
local EconomyService = Sim.server("Services/EconomyService")
local GameData = Sim.shared("GameData")
local Gameplay = Sim.shared("Config/Gameplay")
local Theme = Sim.shared("Config/Theme")
local Format = Sim.shared("Logic/Format")

local function join(userId: number, name: string): any
	local player = Sim.addPlayer(userId, name)
	task.wait(0.2)
	local session = Sessions.get(player)
	assert(session, `{name} has no session`)
	Sim.spawnCharacter(player, PlotService.refs(session.plot).spawnCFrame.Position)
	Sim.fireServer(player, "ClientReady")
	task.wait(0.2)
	return player
end

local function chat(player: any, text: string)
	Sim.chat(player, text)
	task.wait(0.1)
end

local function toasts(userId: number): { string }
	local list = {}
	for _, args in Sim.received(userId, "Notify") do
		table.insert(list, args[1].text)
	end
	return list
end

-- The toasts sent to `userId` after the first `from`.
local function toastsSince(userId: number, from: number): { string }
	local list = toasts(userId)
	return table.move(list, from + 1, #list, 1, {})
end

-- The newest belt item of `creatureId` the server announced.
local function lastBeltItem(creatureId: string): any
	local found = nil
	for _, args in Sim.received(0, "BeltSpawn") do
		if args[1].creatureId == creatureId then
			found = args[1]
		end
	end
	return found
end

-- "Need $X more?" -------------------------------------------------------------------------------------------------

local function cashOffer()
	print('"Need $X more?":')
	local CashOfferRules = Sim.shared("Logic/CashOfferRules")
	local EconomyMath = Sim.shared("Logic/EconomyMath")
	local Economy = Sim.shared("Config/Economy")
	local cfg = Sim.shared("Config/Monetization").cashOffer
	local kim = join(KIM, "Kim")
	local k = Sessions.get(kim)
	Sim.fireServer(kim, "SkipTutorial")
	task.wait(0.1)
	EconomyService.giveCreature(k, "taco_turtle", nil) -- some income: $65/s
	Sim.server("Services/AchievementService").check(k) -- what that earned is paid now, not during the taps
	local income = k.incomePerSecond
	check(income > 0, `Kim earns \${income}/s`)
	-- the cheapest regular Snackling dearer than the Snack Pack pays at her income, plus a margin
	local smallest = EconomyMath.cashPackAmount(k.packIncome, Economy.cashPacks.CashSmall)
	local def = nil
	for _, candidate in GameData.catalog.creatureList do
		local price = GameData.price(candidate, nil)
		if candidate.eventId == nil and price > smallest * 2 and (def == nil or price < GameData.price(def, nil)) then
			def = candidate
		end
	end
	assert(def, "a dear enough Snackling")
	local price = GameData.price(def, nil)
	local offers = 0
	-- Kim taps Buy on it with `gap` too little cash. Returns the toasts it brought and whether an offer came.
	local function tapShort(gap: number): ({ string }, any)
		-- BuyBeltItem's rate limit refills a tap every half second (on os.clock, which follows server time here)
		Sim.advance(0.6)
		chat(kim, `/spawn {def.id}`)
		local item = lastBeltItem(def.id)
		assert(item, `no {def.id} on the belt`)
		-- server time stands still: the item sits where the belt starts
		local belt = Sim.server("Services/BeltService").belt()
		Sim.moveCharacter(kim, Vector3.new(belt.startX + 2, 3, Gameplay.belt.width / 2 + 3))
		k.data.cash = price - gap
		local told = #toasts(KIM)
		Sim.fireServer(kim, "BuyBeltItem", item.id)
		task.wait(0.1)
		local received = Sim.received(KIM, "CashOffer")
		local offer = if #received > offers then received[#received][1] else nil
		offers = #received
		return toastsSince(KIM, told), offer
	end

	-- A new player: no offer in the first 10 minutes of play, whatever the gap
	k.data.stats.playTime = 0
	local said, offer = tapShort(math.floor(100 * income))
	check(offer == nil, "in her first minutes of play a purchase she can't afford brings no offer")
	check(table.find(said, Theme.text.notEnoughCash) ~= nil, `just "Not enough cash!" ({said[1]})`)
	k.data.stats.playTime = cfg.minPlaySeconds - 5
	said, offer = tapShort(math.floor(100 * income))
	check(offer == nil and table.find(said, Theme.text.notEnoughCash) ~= nil, "nor at nine minutes fifty-five")

	-- After 10 minutes: the cheapest small pack that covers the gap, then nothing for 3 minutes
	k.data.stats.playTime = cfg.minPlaySeconds
	said, offer = tapShort(math.floor(100 * income))
	local expected = CashOfferRules.pick(
		math.floor(100 * income),
		k.packIncome,
		cfg.packs,
		Sim.shared("Config/Monetization").products,
		Economy.cashPacks,
		true
	)
	check(
		offer ~= nil and expected ~= nil and offer.key == expected.key and table.find(cfg.packs, offer.key) ~= nil,
		`after 10 minutes, 100 s of income short: the {offer and offer.key} offer, a small pack`
	)
	check(table.find(said, Theme.text.notEnoughCash) == nil, "instead of the toast")
	said, offer = tapShort(math.floor(100 * income))
	check(
		offer == nil and table.find(said, Theme.text.notEnoughCash) ~= nil,
		"tapping again at once: no second offer, the toast"
	)
	Sim.advance(cfg.cooldownSeconds - 10 - 2 * 0.6) -- (each tap lets 0.6 s pass)
	said, offer = tapShort(math.floor(100 * income))
	check(offer == nil and table.find(said, Theme.text.notEnoughCash) ~= nil, "nor 2 m 50 s later")
	Sim.advance(10)
	said, offer = tapShort(math.floor(100 * income))
	check(offer ~= nil, "3 minutes after the last offer, another")

	-- A small gap: the seconds of income, never an offer
	k.cashOfferAt = -math.huge
	local gap = math.floor(30 * income)
	said, offer = tapShort(gap)
	local seconds = CashOfferRules.waitSeconds(gap, income, cfg)
	local waitText = Format.template(Theme.text.notEnoughCashWait, { seconds = seconds or -1 })
	check(
		offer == nil and seconds == 30 and table.find(said, waitText) ~= nil,
		`30 s of income short: no offer, the seconds instead ({waitText})`
	)
	gap = math.floor(cfg.smallGapSeconds * income)
	said, offer = tapShort(gap)
	waitText = Format.template(Theme.text.notEnoughCashWait, { seconds = CashOfferRules.waitSeconds(gap, income, cfg) })
	check(offer == nil and table.find(said, waitText) ~= nil, `45 s of income short: the seconds too ({waitText})`)

	-- A gap no small pack covers: the plain toast (the store's bigger packs are never offered)
	said, offer = tapShort(smallest + 1000)
	check(
		offer == nil and table.find(said, Theme.text.notEnoughCash) ~= nil,
		"a gap only a big pack covers: just the toast"
	)
	Sim.removePlayer(kim)
	task.wait(0.3)
end

local function scenario()
	print("review 3 test:")
	cashOffer()
	print(`  ({math.floor(Sim.now - OCTOBER_15_2026)} s of server time)`)
end

local passed, problem = pcall(scenario :: () -> ...any)
if not passed then
	print(`  FAIL the scenario stopped: {problem}`)
	table.insert(failures, tostring(problem))
end
finish()
