--!strict
--[[
	The store additions, offline (CI runs it after the gadgets test):
	    lune run tools/worldsim/store.luau

	Boots the whole server like tools/worldsim/server.luau with the clock virtual (Sim.virtualClock) and random
	modifiers and the map rotation off. The new items get made-up Creator Hub ids before the server starts, so
	everything runs the way it will live: passes through UserOwnsGamePassAsync, products through the real
	MarketplaceService.ProcessReceipt with fake receipts (DECISIONS.md "Store additions"):

	  * Auto Collect pays every pad from across the map, quietly, every few seconds, through the pad path; a
	    player without it gets nothing from afar; the Snack Magnet shows "AUTO" for its owners and stays unused.
	  * Lucky Spin packs: asked for, approved, then a 3-spin receipt banks 3 spins once, retried at once and after a
	    rejoin; a full bank refuses before the prompt, and a receipt that lands anyway banks every spin past the caps;
	    a player whose policy restricts paid random items (or whose lookup failed) is refused before the prompt and at
	    the receipt.
	  * The Starter Pack: its offer comes due at 30 minutes of play (and once shown never again); bought once, its
	    fixed contents land (income-sized cash, a Golden Cupcake Cub on a podium, Fizzy Soda and Banana Peel), a retry
	    adds nothing, a second purchase is refused before the prompt, and a second receipt anyway pays the whole pack's
	    worth in cash only; an owned gadget is paid as its price, and a base filled since the prompt gets the
	    Snackling's price.

	It fails on any error, any unexpected warning, or any check.
]]

local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")
local Sim = require("./Sim")
local MockProfileStore = require("./MockProfileStore")

local Vector3 = roblox.Vector3
local OCTOBER_15_2026 = 1792023721

Sim.mock("ServerPackages/ProfileStore.lua", MockProfileStore)
Sim.virtualClock = true
Sim.now = OCTOBER_15_2026
Sim.shared("Config/Modifiers").schedule.enabled = false -- only /mod starts one
Sim.shared("Config/MapThemes").rotation.enabled = false

-- Made-up Creator Hub ids, so nothing goes through Studio's test grants.
local Monetization = Sim.shared("Config/Monetization")
local AUTO_COLLECT_PASS = 990001
local SPINS_3, SPINS_10 = 990101, 990102
local STARTER = 990201
Monetization.passes.AutoCollect.id = AUTO_COLLECT_PASS
Monetization.products.LuckySpins3.id = SPINS_3
Monetization.products.LuckySpins10.id = SPINS_10
Monetization.products.StarterPack.id = STARTER

local ALICE, BOB, CAROL, DAN, RITA, ED, FAY, GUS, HAL = 6001, 6002, 6003, 6004, 6005, 6006, 6007, 6008, 6009
Sim.ownedPasses[BOB] = { [AUTO_COLLECT_PASS] = true } -- Bob bought it before: it is his from the moment he joins
Sim.policies[RITA] = { ArePaidRandomItemsRestricted = true }
Sim.policies[ED] = "error"

local EXPECTED_WARNINGS = {
	"MessagingService.SubscribeAsync is not available offline",
	"Rita may not buy paid random items",
	"Ed may not buy paid random items",
	"could not look up Ed's policy",
	"Fay bought the Starter Pack again", -- the second receipt, on purpose
}

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
		print(`store test: {#failures} problem(s)`)
		process.exit(1)
	end
	print("store test: no problems")
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
local Gadgets = Sim.shared("Config/Gadgets")
local Theme = Sim.shared("Config/Theme")
local Marketplace = Sim.service("MarketplaceService")

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

local function chat(player: any, text: string)
	Sim.chat(player, text)
	task.wait(0.1)
end

-- Lets server time pass in one-second steps, as if everyone stood still. The game's loops wait in real time (the
-- income tick every 1 s, the Auto Collect check every 0.5 s), so each step also lets a little more than half a real
-- second go by: every step gets an Auto Collect check, and income lands every other step for the time that passed.
local function wait(seconds: number)
	local left = seconds
	while left > 1e-9 do
		local step = math.min(left, 1)
		Sim.advance(step)
		task.wait(0.55)
		left -= step
	end
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

-- Whether a toast sent to `userId` after the first `from` contains `text`.
local function toldSince(userId: number, from: number, text: string): boolean
	local list = toasts(userId)
	for index = from + 1, #list do
		if string.find(list[index], text, 1, true) then
			return true
		end
	end
	return false
end

-- The "collect" Effects sent to `userId` from index `from` on.
local function collectsSince(userId: number, from: number): { any }
	local list = {}
	local effects = Sim.received(userId, "Effect")
	for index = from + 1, #effects do
		local payload = effects[index][1]
		if payload.kind == "collect" then
			table.insert(list, payload)
		end
	end
	return list
end

-- A receipt from Roblox through the real MarketplaceService.ProcessReceipt. Returns the decision's name.
local function receipt(userId: number, productId: number, purchaseId: string, robux: number): string
	local decision = Marketplace.ProcessReceipt({
		PlayerId = userId,
		ProductId = productId,
		PurchaseId = purchaseId,
		CurrencySpent = robux,
		PlaceIdWherePurchased = 0,
	})
	return decision.Name
end

-- Custom analytics events logged as `name`, oldest first: their breakdown fields.
local function logged(name: string): { { [string]: any } }
	local list = {}
	for _, entry in Sim.analytics do
		if entry.method == "LogCustomEvent" and entry.args[2] == name then
			table.insert(list, (entry.args[4] or {}) :: any)
		end
	end
	return list
end

-- Store funnel steps logged as `step` ("ProductPrompted"...), oldest first: their breakdown fields.
local function funnel(step: string): { { [string]: any } }
	local list = {}
	for _, entry in Sim.analytics do
		if entry.method == "LogFunnelStepEvent" and entry.args[5] == step then
			table.insert(list, (entry.args[6] or {}) :: any)
		end
	end
	return list
end

-- The products the server approved for `userId` (PurchaseApproved), oldest first.
local function approvals(userId: number): { string }
	local list = {}
	for _, args in Sim.received(userId, "PurchaseApproved") do
		table.insert(list, args[1].key)
	end
	return list
end

local function storedOf(session: any): number
	local total = 0
	for _, record in session.data.creatures do
		total += math.floor(record.stored)
	end
	return total
end

local function autoCollect()
	print("Auto Collect:")
	local alice = join(ALICE, "Alice")
	local bob = join(BOB, "Bob")
	local carol = join(CAROL, "Carol")
	local a, b, c = sessionOf(alice), sessionOf(bob), sessionOf(carol)
	for _, player in Sim.service("Players"):GetPlayers() do
		Sim.fireServer(player, "SkipTutorial")
	end
	task.wait(0.1)
	check(b.passes.AutoCollect == true, "a pass Roblox says Bob owns is his on joining")
	check(a.passes.AutoCollect == false and c.passes.AutoCollect == false, "Alice and Carol don't have it")
	for _, session in { a, b, c } do
		for _ = 1, 3 do
			EconomyService.giveCreature(session, "pizza_pup", nil)
		end
	end
	-- Everyone stands across the map from their base: the far end of the other walkway.
	for _, player in { alice, bob, carol } do
		Sim.moveCharacter(player, Vector3.new(130, 3, -15))
	end
	local carolCash = c.data.cash
	wait(10)

	local aliceCash, aliceStored = a.data.cash, storedOf(a)
	check(aliceStored > 0, `income piles up on Alice's pads (${aliceStored})`)
	wait(10)
	check(a.data.cash == aliceCash, "without the pass nothing reaches her from afar")

	-- Bob has been collected all along, from across the map.
	local bobCash = b.data.cash
	local effectsBefore = #Sim.received(BOB, "Effect")
	local toastsBefore = #toasts(BOB)
	wait(Monetization.perks.autoCollectSeconds)
	local collects = collectsSince(BOB, effectsBefore)
	check(b.data.cash > bobCash, "Bob's pads are collected from across the map")
	local quiet, shown = #collects > 0, 0
	for _, payload in collects do
		quiet = quiet and payload.quiet == true
		shown += payload.amount
	end
	check(shown == b.data.cash - bobCash, `every dollar of it through the pad path ($ {shown})`)
	check(#collects >= 3 and quiet, `the pad path's "+$" over each pad, marked quiet ({#collects} pads)`)
	check(#toasts(BOB) == toastsBefore, "and no toast")

	-- The timing: once per interval, never twice in one (Logic/AutoCollectRules.due; exact in its unit tests).
	local interval = Monetization.perks.autoCollectSeconds
	local last = b.data.cash
	local at: { number } = {}
	for _ = 1, 4 * interval do
		wait(1)
		if b.data.cash > last then
			table.insert(at, Sim.now)
			last = b.data.cash
		end
	end
	local closest = math.huge
	for index = 2, #at do
		closest = math.min(closest, at[index] - at[index - 1])
	end
	check(
		#at >= 3 and #at <= 4 and closest >= interval - 1e-6,
		`one collect every {interval} s, never sooner ({#at} in {4 * interval} s, {closest} s apart at least)`
	)

	-- Alice buys the pass in-game: Roblox confirms it, and her pads come to her at the next check.
	Sim.ownedPasses[ALICE] = { [AUTO_COLLECT_PASS] = true }
	Marketplace.PromptGamePassPurchaseFinished:Fire(alice, AUTO_COLLECT_PASS, true)
	task.wait(0.1)
	check(a.passes.AutoCollect == true, "Alice buys Auto Collect; Roblox confirms it")
	check(
		string.find(lastToast(ALICE), Theme.store.AutoCollect.name, 1, true) ~= nil,
		`and she hears so ({lastToast(ALICE)})`
	)
	aliceCash, aliceStored = a.data.cash, storedOf(a)
	wait(1.5)
	check(a.data.cash - aliceCash >= aliceStored, `within a second her pads pay out (${a.data.cash - aliceCash})`)
	check(c.data.cash == carolCash and storedOf(c) > 0, "Carol's cash still waits on her pads")
	local states = Sim.received(ALICE, "StateUpdate")
	check(states[#states][1].passes.AutoCollect == true, "her client knows (the magnet button shows AUTO)")

	-- The Snack Magnet: unused for pass owners, and not sold to them.
	chat(alice, "/gadgets") -- Studio: own every gadget, recharged
	wait(3) -- something waits on the pads again
	Sim.fireServer(alice, "UseGadget", "magnet")
	task.wait(0.1)
	check(a.gadgets.readyAt.magnet == nil, "Alice's magnet isn't used: its cooldown never starts")
	check(lastToast(ALICE) == Theme.text.magnetAuto, `it says why ({lastToast(ALICE)})`)
	chat(bob, "/cash 100000000")
	local before = b.data.cash
	Sim.fireServer(bob, "BuyGadget", "magnet")
	task.wait(0.1)
	check(b.data.flags.gadget_magnet == nil and b.data.cash == before, "Bob isn't sold a magnet for $2.5M")
	check(lastToast(BOB) == Theme.text.magnetAuto, "and is told why")
	Sim.fireServer(carol, "BuyGadget", "magnet")
	task.wait(0.1)
	check(lastToast(CAROL) == Theme.text.notEnoughCash, "everyone else buys it as before")
	check(Gadgets.gadgets.magnet.kind == "magnet", "(the magnet is the gadget the pass covers)")
end

local function spinPacks()
	print("Lucky Spin packs:")
	local dan = join(DAN, "Dan")
	local d = sessionOf(dan)
	task.wait(0.2)
	check(dan:GetAttribute("PaidRandomItemsAllowed") == true, "Dan's policy allows paid random items")
	local spins = d.data.spin.spins

	-- Asking first: the server approves, and only then does the client open Roblox's prompt.
	Sim.fireServer(dan, "RequestPurchase", "LuckySpins3", "spin")
	task.wait(0.1)
	local approved = approvals(DAN)
	check(approved[#approved] == "LuckySpins3", "Dan asks to buy 3 Lucky Spins from the Spin tab: approved")
	local prompted = funnel("ProductPrompted")
	local last: { [string]: any } = prompted[#prompted] or {}
	check(
		last.CustomField01 == "LuckySpins3" and last.CustomField02 == "spin",
		"logged as the store funnel's ProductPrompted, with where it was tapped"
	)
	check(d.data.spin.spins == spins, "asking gives nothing by itself")

	-- The receipt: 3 spins, once, however often Roblox retries it.
	check(receipt(DAN, SPINS_3, "spin-receipt-1", 25) == "PurchaseGranted", "the receipt is granted")
	check(d.data.spin.spins == spins + 3, `3 spins banked ({spins} -> {d.data.spin.spins})`)
	check(receipt(DAN, SPINS_3, "spin-receipt-1", 25) == "PurchaseGranted", "Roblox retries the same receipt")
	check(d.data.spin.spins == spins + 3, "and it banks nothing more")
	check(string.find(lastToast(DAN), "+3 Lucky Spins", 1, true) ~= nil, `Dan hears so ({lastToast(DAN)})`)
	local bought = logged("product_purchased")
	check(#bought == 1 and bought[1].CustomField01 == "LuckySpins3", "one purchase logged, with its key")
	Sim.removePlayer(dan)
	task.wait(0.3)
	check(receipt(DAN, SPINS_3, "spin-receipt-1", 25) == "NotProcessedYet", "while he is away it waits")
	dan = join(DAN, "Dan")
	d = sessionOf(dan)
	check(receipt(DAN, SPINS_3, "spin-receipt-1", 25) == "PurchaseGranted", "after a rejoin it is answered")
	check(d.data.spin.spins == spins + 3, `from his save, still 3 spins once ({d.data.spin.spins})`)
	local history = 0
	for _, entry in d.data.purchaseHistory do
		if entry.purchaseId == "spin-receipt-1" then
			history += 1
		end
	end
	check(history == 1, "and one entry in his purchase history")

	-- A very full bank: refused before the prompt, and a receipt that lands anyway is never clipped.
	local full = Sim.shared("Config/Spin").paidBankFull
	d.data.spin.spins = full
	local approvedBefore = #approvals(DAN)
	Sim.advance(3)
	Sim.fireServer(dan, "RequestPurchase", "LuckySpins10", "store")
	task.wait(0.1)
	check(#approvals(DAN) == approvedBefore, `with {full} spins banked the 10-pack isn't approved`)
	check(
		lastToast(DAN) == Sim.shared("Logic/Format").template(Theme.text.spinPackBankFull, { count = full }),
		`he is told why ({lastToast(DAN)})`
	)
	local refused = logged("product_refused")
	check(
		#refused >= 1
			and refused[#refused].CustomField01 == "LuckySpins10"
			and refused[#refused].CustomField02 == "bankFull",
		"logged as refused, with the reason"
	)
	check(receipt(DAN, SPINS_10, "spin-receipt-2", 69) == "PurchaseGranted", "a 10-pack receipt lands anyway")
	check(d.data.spin.spins == full + 10, `every spin is banked, past both caps ({d.data.spin.spins})`)

	-- Views: the Spin tab's pack buttons, once per session.
	Sim.fireServer(dan, "ClientEvent", "store_viewed", "spin")
	Sim.fireServer(dan, "ClientEvent", "store_viewed", "spin")
	Sim.fireServer(dan, "ClientEvent", "store_viewed", "somewhere")
	task.wait(0.1)
	local views = 0
	for _, fields in logged("product_viewed") do
		if fields.CustomField02 == "spin" then
			views += 1
		end
	end
	check(views == 2, `each pack's view in the Spin tab is logged once ({views})`)

	-- Restricted players: refused before the prompt and at the receipt.
	local rita = join(RITA, "Rita")
	local ed = join(ED, "Ed")
	task.wait(1.3) -- Ed's lookup fails, waits a second and fails again
	local r, e = sessionOf(rita), sessionOf(ed)
	for _, entry in { { rita, r, RITA, "Rita" }, { ed, e, ED, "Ed" } } do
		local player, session, userId, name = entry[1], entry[2], entry[3], entry[4]
		local before = session.data.spin.spins
		Sim.fireServer(player, "RequestPurchase", "LuckySpins3", "spin")
		task.wait(0.1)
		check(#approvals(userId) == 0, `{name} is refused before the prompt`)
		check(lastToast(userId) == Theme.text.storeRandomRestricted, `and told why ({lastToast(userId)})`)
		check(
			receipt(userId, SPINS_3, `restricted-{userId}`, 25) == "NotProcessedYet",
			`a receipt for {name} is not granted`
		)
		check(
			session.data.spin.spins == before and #session.data.purchaseHistory == 0,
			"and nothing is banked or recorded"
		)
	end
end

local function lastState(userId: number): any
	local list = Sim.received(userId, "StateUpdate")
	return list[#list][1]
end

local function starterPack()
	print("Starter Pack:")
	-- Bases for the newcomers below: everyone but Dan goes (8 bases, 8 players).
	for _, player in Sim.service("Players"):GetPlayers() do
		if player.UserId ~= DAN then
			Sim.removePlayer(player)
		end
	end
	task.wait(0.3)
	local GameData = Sim.shared("GameData")
	local config = Monetization.starterPack
	local fay = join(FAY, "Fay")
	local f = sessionOf(fay)
	Sim.fireServer(fay, "SkipTutorial")
	task.wait(0.4)
	check(lastState(FAY).store.starterOffer == false, "a new player gets no Starter Pack offer")
	check(lastState(FAY).store.starterOwned == false, "and it is in her Shop")

	-- The offer comes due with play time alone (no other state update needed), and once shown never again.
	f.data.stats.playTime = config.offer.afterPlaySeconds
	wait(10) -- StoreService looks every 5 s
	check(lastState(FAY).store.starterOffer == true, "after 30 minutes of play its offer card is due")
	Sim.fireServer(fay, "ClientEvent", "store_viewed", "offer")
	task.wait(0.4)
	check(f.data.flags.starter_offer == true, "her client shows it: flagged once for her account")
	check(lastState(FAY).store.starterOffer == false, "so it is never due again")
	local offerViews = 0
	for _, fields in logged("product_viewed") do
		if fields.CustomField01 == "StarterPack" and fields.CustomField02 == "offer" then
			offerViews += 1
		end
	end
	check(offerViews == 1, "its view is logged")

	-- Bought once: fixed contents.
	Sim.fireServer(fay, "RequestPurchase", "StarterPack", "offer")
	task.wait(0.1)
	local approved = approvals(FAY)
	check(approved[#approved] == "StarterPack", "she asks to buy it: approved")
	local cash, creatures = f.data.cash, #f.data.creatures
	local toastsBefore = #toasts(FAY)
	check(receipt(FAY, STARTER, "starter-1", 49) == "PurchaseGranted", "the receipt is granted")
	task.wait(0.2)
	local quoted = Sim.shared("Logic/StarterPackRules").cash(config, 0)
	check(f.data.cash - cash == quoted, `its cash: her income is 0, so the floor (+{f.data.cash - cash})`)
	local record = f.data.creatures[#f.data.creatures]
	check(
		#f.data.creatures == creatures + 1 and record.id == config.creatureId and record.variant == config.variant,
		`a {GameData.displayName(GameData.catalog.creatures[config.creatureId], config.variant)} on a podium`
	)
	check(f.data.flags.gadget_soda == true and f.data.flags.gadget_peel == true, "Fizzy Soda and Banana Peel unlocked")
	check(f.data.flags.starter_pack == true, "bought: flagged once for her account")
	task.wait(0.4)
	check(lastState(FAY).store.starterOwned == true, "her Shop hides it")
	local gadgets = lastState(FAY).gadgets.owned
	check(table.find(gadgets, "soda") ~= nil and table.find(gadgets, "peel") ~= nil, "the gadget buttons appear")
	check(f.data.snackdex.creatures[config.creatureId] == true, "the Snackdex sees the Snackling (acquired)")
	check(toldSince(FAY, toastsBefore, "Starter Pack!"), "she hears so")

	cash, creatures = f.data.cash, #f.data.creatures
	check(receipt(FAY, STARTER, "starter-1", 49) == "PurchaseGranted", "Roblox retries the receipt")
	check(f.data.cash == cash and #f.data.creatures == creatures, "and nothing more is given")

	-- A second purchase: refused before the prompt; a receipt anyway pays the whole pack in cash only.
	local approvedBefore = #approvals(FAY)
	Sim.advance(3)
	Sim.fireServer(fay, "RequestPurchase", "StarterPack", "store")
	task.wait(0.1)
	check(#approvals(FAY) == approvedBefore, "a second purchase is refused before the prompt")
	check(lastToast(FAY) == Theme.text.starterOwned, `she is told why ({lastToast(FAY)})`)
	local def = GameData.catalog.creatures[config.creatureId]
	-- sized at the second receipt: her income now includes the pack's own Snackling
	local worth = Sim.shared("Logic/StarterPackRules").cash(config, f.packIncome)
		+ GameData.price(def, config.variant)
		+ Gadgets.gadgets.soda.price
		+ Gadgets.gadgets.peel.price
	check(receipt(FAY, STARTER, "starter-2", 49) == "PurchaseGranted", "a second receipt lands anyway")
	check(f.data.cash - cash == worth, `it pays the whole pack's worth in cash (+{f.data.cash - cash} = {worth})`)
	check(#f.data.creatures == creatures, "and nothing else: no second Snackling")
	local duplicates = logged("starter_pack_duplicate")
	check(#duplicates == 1, "logged as a duplicate")

	-- A gadget already owned is paid as its price; a base filled since the prompt gets the Snackling's price.
	local gus = join(GUS, "Gus")
	local g = sessionOf(gus)
	Sim.fireServer(gus, "SkipTutorial")
	chat(gus, "/cash 100000")
	Sim.advance(1.1)
	Sim.fireServer(gus, "BuyGadget", "soda")
	task.wait(0.1)
	check(g.data.flags.gadget_soda == true, "Gus bought a Fizzy Soda with cash")
	while EconomyService.freePodium(g) do
		EconomyService.giveCreature(g, "pizza_pup", nil)
	end
	local gusToasts = #toasts(GUS)
	Sim.fireServer(gus, "RequestPurchase", "StarterPack", "store")
	task.wait(0.1)
	check(
		#approvals(GUS) == 0 and toldSince(GUS, gusToasts, Theme.text.starterBaseFull),
		"with a full base: refused, and why"
	)
	cash, creatures = g.data.cash, #g.data.creatures
	check(receipt(GUS, STARTER, "starter-3", 49) == "PurchaseGranted", "a receipt lands anyway")
	local expected = Sim.shared("Logic/StarterPackRules").cash(config, g.packIncome)
		+ Gadgets.gadgets.soda.price
		+ GameData.price(def, config.variant)
	check(
		g.data.cash - cash == expected and #g.data.creatures == creatures,
		`the soda he owns and the Snackling with no room are paid as cash (+{g.data.cash - cash} = {expected})`
	)
	check(g.data.flags.gadget_peel == true and g.data.flags.starter_pack == true, "the Banana Peel is unlocked")

	-- Hal joins after buying it elsewhere: his Shop never shows it, nor its offer.
	MockProfileStore.saves[`Player_{HAL}`] = nil
	local hal = join(HAL, "Hal")
	local h = sessionOf(hal)
	h.data.flags.starter_pack = true
	h.data.stats.playTime = config.offer.afterPlaySeconds
	Sim.fireServer(hal, "SkipTutorial")
	wait(6)
	check(
		lastState(HAL).store.starterOwned == true and lastState(HAL).store.starterOffer == false,
		"an owner is never offered it"
	)
end

local function scenario()
	print("store test:")
	autoCollect()
	spinPacks()
	starterPack()
	print(`  ({math.floor(Sim.now - OCTOBER_15_2026)} s of server time)`)
end

local passed, problem = pcall(scenario :: () -> ...any)
if not passed then
	print(`  FAIL the scenario stopped: {problem}`)
	table.insert(failures, tostring(problem))
end
finish()
