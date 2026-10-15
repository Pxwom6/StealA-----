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
Monetization.passes.AutoCollect.id = AUTO_COLLECT_PASS

local ALICE, BOB, CAROL = 6001, 6002, 6003
Sim.ownedPasses[BOB] = { [AUTO_COLLECT_PASS] = true } -- Bob bought it before: it is his from the moment he joins

local EXPECTED_WARNINGS = {
	"MessagingService.SubscribeAsync is not available offline",
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

local function scenario()
	print("store test:")
	autoCollect()
	print(`  ({math.floor(Sim.now - OCTOBER_15_2026)} s of server time)`)
end

local passed, problem = pcall(scenario :: () -> ...any)
if not passed then
	print(`  FAIL the scenario stopped: {problem}`)
	table.insert(failures, tostring(problem))
end
finish()
