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
	  * toasts that can wait (TutorialService.notifyWhenQuiet): an achievement reached in the first-time tutorial is
	    paid at once, but its toast comes 3 s after the tutorial's "You're ready!"; after a skip, at once
	  * the new-player shield ending (LockService): one toast when its time is up, or at once when it is ended early;
	    never for a returning player who had none
	  * finding gadgets (GadgetService): one toast when the first gadget becomes affordable, never during the
	    tutorial, once per account (a rejoin too)

	It fails on any error, any unexpected warning, or any check below.
]]

local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")
local Sim = require("./Sim")
local MockProfileStore = require("./MockProfileStore")

local Vector3 = roblox.Vector3
local OCTOBER_15_2026 = 1792023721

local KIM, NIA, PIA = 9301, 9302, 9303
local OLA, UMA, VAL = 9304, 9305, 9306
local WES = 9307

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

-- Spawns `creatureId` on the belt (dev command), puts `player` beside it and buys it (with cash for it).
local function buyFromBelt(player: any, creatureId: string)
	chat(player, `/spawn {creatureId}`)
	local item = lastBeltItem(creatureId)
	assert(item, `no {creatureId} on the belt`)
	local belt = Sim.server("Services/BeltService").belt()
	Sim.moveCharacter(player, Vector3.new(belt.startX + 2, 3, Gameplay.belt.width / 2 + 3))
	local session = Sessions.get(player)
	session.data.cash = math.max(session.data.cash, GameData.price(GameData.catalog.creatures[creatureId], nil))
	Sim.fireServer(player, "BuyBeltItem", item.id)
	task.wait(0.1)
end

-- Whether a toast sent to `userId` after the first `from` contains `text`; and at which index (0: none).
local function toldAt(userId: number, from: number, text: string): number
	local list = toasts(userId)
	for index = from + 1, #list do
		if string.find(list[index], text, 1, true) then
			return index
		end
	end
	return 0
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

-- Toasts that can wait ------------------------------------------------------------------------------------------------

local function toastsWait()
	print("Toasts that can wait:")
	local TutorialService = Sim.server("Services/TutorialService")
	local AchievementService = Sim.server("Services/AchievementService")
	local Tutorial = Sim.shared("Config/Tutorial")
	local UiTheme = Sim.shared("UiTheme")
	local firstBite = "Achievement: First Bite!"
	local nia = join(NIA, "Nia") -- brand new: in the first-time tutorial
	local n = Sessions.get(nia)
	check(n.tutorial ~= nil and n.tutorial.stepId == "buy", "Nia starts the first-time tutorial")
	buyFromBelt(nia, "pizza_pup")
	AchievementService.check(n) -- (what its one-second loop does for her)
	local cash = n.data.cash
	check(n.data.flags.ach_firstBite == true, "her first Snackling earns First Bite, paid at once")
	check(toldAt(NIA, 0, firstBite) == 0, "but its toast waits: the tutorial has the screen")
	-- the rest of the tutorial, as the services report it
	for _, step in { "collect", "lock", "steal" } do
		TutorialService.record(n, step)
	end
	local ready = Format.template(Theme.text.tutorialComplete, { amount = UiTheme.cash(Tutorial.reward) })
	local readyAt = toldAt(NIA, 0, ready)
	check(n.tutorial == nil and readyAt > 0, `she completes it: "{ready}"`)
	check(n.data.cash == cash + Tutorial.reward, "and its reward is paid")
	Sim.advance(Tutorial.quietSeconds - 0.5)
	task.wait(1.2) -- the tutorial's 1 Hz pass runs
	check(toldAt(NIA, 0, firstBite) == 0, `{Tutorial.quietSeconds - 0.5} s later the achievement's toast still waits`)
	Sim.advance(1)
	task.wait(1.2)
	local biteAt = toldAt(NIA, 0, firstBite)
	check(biteAt > readyAt, `{Tutorial.quietSeconds} s after "You're ready!", the achievement's toast comes`)
	check(toldAt(NIA, biteAt, firstBite) == 0, "once")

	-- A skipped tutorial holds nothing back after the skip
	local pia = join(PIA, "Pia")
	local p = Sessions.get(pia)
	buyFromBelt(pia, "pizza_pup")
	AchievementService.check(p)
	check(p.data.flags.ach_firstBite == true and toldAt(PIA, 0, firstBite) == 0, "Pia's First Bite waits too")
	Sim.fireServer(pia, "SkipTutorial")
	task.wait(1.2)
	check(toldAt(PIA, 0, firstBite) > 0, "she skips the tutorial: it comes at the next pass")
	AchievementService.check(p)
	check(toldAt(PIA, toldAt(PIA, 0, firstBite), firstBite) == 0, "once")
	for _, player in { nia, pia } do
		Sim.removePlayer(player)
	end
	task.wait(0.3)
end

-- The new-player shield ending -------------------------------------------------------------------------------------

local function shieldEnds()
	print("The new-player shield ending:")
	local DataSchema = Sim.shared("Logic/DataSchema")
	local Economy = Sim.shared("Config/Economy")
	local gone = Theme.text.shieldGone
	local ola = join(OLA, "Ola") -- brand new: shielded for her first minutes of play
	local o = Sessions.get(ola)
	Sim.fireServer(ola, "SkipTutorial")
	task.wait(0.1)
	check(o.graceUntil > Sim.now, `Ola joins with the new-player shield ({math.floor(o.graceUntil - Sim.now)} s)`)
	Sim.advance(o.graceUntil - Sim.now - 1)
	task.wait(1.2) -- LockService's 1 Hz pass
	check(toldAt(OLA, 0, gone) == 0 and o.graceUntil > 0, "a second before it ends: nothing yet")
	Sim.advance(1.5)
	task.wait(1.2)
	local at = toldAt(OLA, 0, gone)
	check(at > 0 and o.graceUntil == 0, `when it ends she is told: "{gone}"`)
	check(PlotService.world().plots[o.plot].model:GetAttribute("GraceUntil") == 0, "and her base's shield is off")
	Sim.advance(30)
	task.wait(1.2)
	check(toldAt(OLA, at, gone) == 0, "only once")

	-- Ended early (a steal, or /noshield in Studio): told at once
	local uma = join(UMA, "Uma")
	Sim.fireServer(uma, "SkipTutorial")
	chat(uma, "/noshield")
	at = toldAt(UMA, 0, gone)
	check(at > 0 and Sessions.get(uma).graceUntil == 0, "a shield ended early is told at once")
	Sim.advance(300)
	task.wait(1.2)
	check(toldAt(UMA, at, gone) == 0, "and only then")

	-- A returning player with no shield left never hears it
	local save = DataSchema.template(Economy.startingCash)
	save.stats.playTime = 3600
	save.flags.tutorial_done = true
	save.firstJoin = OCTOBER_15_2026 - 86400
	MockProfileStore.saves[`Player_{VAL}`] = save
	local val = join(VAL, "Val")
	check(Sessions.get(val).graceUntil == 0, "Val, back after an hour of play, has no shield")
	Sim.advance(300)
	task.wait(1.2)
	check(toldAt(VAL, 0, gone) == 0, "and never hears that it is gone")
	for _, player in { ola, uma, val } do
		Sim.removePlayer(player)
	end
	task.wait(0.3)
end

-- Finding gadgets -----------------------------------------------------------------------------------------------------

local function gadgetTip()
	print("Finding gadgets:")
	local Gadgets = Sim.shared("Config/Gadgets")
	local GadgetRules = Sim.shared("Logic/GadgetRules")
	local UiTheme = Sim.shared("UiTheme")
	local soda = Gadgets.gadgets.soda
	local tip = Format.template(Theme.text.gadgetTip, { icon = soda.icon, name = UiTheme.text(soda.nameKey) })
	local wes = join(WES, "Wes") -- brand new: in the first-time tutorial
	local w = Sessions.get(wes)
	w.data.cash = soda.price
	task.wait(1.2) -- GadgetService looks once a second
	check(toldAt(WES, 0, tip) == 0, "during the tutorial Wes hears nothing about gadgets, cash or not")
	Sim.fireServer(wes, "SkipTutorial")
	w.data.cash = soda.price - 1
	task.wait(1.2)
	check(toldAt(WES, 0, tip) == 0, "after it, $1 short of a Fizzy Soda: nothing yet")
	w.data.cash = soda.price
	task.wait(1.2)
	local at = toldAt(WES, 0, tip)
	check(at > 0 and w.data.flags[GadgetRules.TIP_FLAG] == true, `once he can buy one: "{tip}"`)
	w.data.cash = 1e9
	task.wait(1.2)
	check(toldAt(WES, at, "with cash!") == 0, "never again, whatever he can afford")
	Sim.removePlayer(wes)
	task.wait(0.3)
	wes = join(WES, "Wes")
	Sessions.get(wes).data.cash = 1e9
	task.wait(1.2)
	check(toldAt(WES, at, "with cash!") == 0, "nor after a rejoin (the flag is in his save)")
	Sim.removePlayer(wes)
	task.wait(0.3)
end

local function scenario()
	print("review 3 test:")
	cashOffer()
	toastsWait()
	shieldEnds()
	gadgetTip()
	print(`  ({math.floor(Sim.now - OCTOBER_15_2026)} s of server time)`)
end

local passed, problem = pcall(scenario :: () -> ...any)
if not passed then
	print(`  FAIL the scenario stopped: {problem}`)
	table.insert(failures, tostring(problem))
end
finish()
