--!strict
--[[
	The pre-launch server fixes, offline (CI runs it after the server test):
	    lune run tools/worldsim/prelaunch.luau

	Boots the whole server like tools/worldsim/server.luau, with the clock virtual (Sim.virtualClock: the game's
	os.clock and os.time follow the simulated server time) and the date set to mid-October 2026, before every
	seasonal event. Random modifiers and the map rotation are switched off, so only the commands below change them.
	Then it plays each fixed review finding through the real remotes, chat commands and receipt path (DECISIONS.md
	"Pre-launch fixes (server)"): a huge RedeemCode argument, event codes before their events, Server Luck and
	PolicyService, prize luck without the bought boost, a pass "purchase" Roblox doesn't confirm, Sugar Rush ending
	mid-carry, Jackpot and saved or paid values, a cash pack bought while a thief carries a Snackling off, a runaway
	caught by a carrying thief with one free podium, modifier change grace (sale price, tag reach), a teleport onto a
	supply crate, analytics keys and SKUs, baseFull in the state, core loops surviving an error, and a player's
	CharacterAdded connection after they leave. It fails on any error, any unexpected warning, or any check below.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local task = require("@lune/task")
local Sim = require("./Sim")
local MockProfileStore = require("./MockProfileStore")

local Vector3 = roblox.Vector3
local OCTOBER_15_2026 = 1792023721

Sim.mock("ServerPackages/ProfileStore.lua", MockProfileStore)
Sim.virtualClock = true
Sim.now = OCTOBER_15_2026
Sim.shared("Config/Modifiers").schedule.enabled = false -- only /mod starts one
Sim.shared("Config/MapThemes").rotation.enabled = false -- no map votes in the middle of a scenario

-- Players, by UserId. Alice, Carol, Rita and Bob join first and get plots 1-4 in that order, so Bob's base is at the far
-- end of the row from Alice's: a long, straight run home.
local ALICE, BOB, CAROL, RITA, ED, PAT, OLLY = 4001, 4002, 4003, 4005, 4006, 4007, 4008
Sim.policies[RITA] = { ArePaidRandomItemsRestricted = true }
Sim.policies[ED] = "error"

-- Warnings the server is expected to give here: online-only services, the policy refusals, and the errors this test
-- throws into the core loops on purpose.
local EXPECTED_WARNINGS = {
	"MessagingService.SubscribeAsync is not available offline",
	"Rita may not buy paid random items",
	"could not look up Ed's policy",
	"injected failure",
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
		print(`pre-launch test: {#failures} problem(s)`)
		process.exit(1)
	end
	print("pre-launch test: no problems")
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
local LiveOpsService = Sim.server("Services/LiveOpsService")
local PositionTracker = Sim.server("Services/PositionTracker")
local Replication = Sim.server("Services/Replication")
local DropService = Sim.server("Services/DropService")
local GameData = Sim.shared("GameData")
local Gameplay = Sim.shared("Config/Gameplay")
local Drops = Sim.shared("Config/Drops")
local Modifiers = Sim.shared("Config/Modifiers")
local Monetization = Sim.shared("Config/Monetization")
local Theme = Sim.shared("Config/Theme")
local PaidRandomItems = Sim.shared("Logic/PaidRandomItems")
local workspace = Sim.workspace()

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

local function root(player: any): any
	return (player.Character :: any).HumanoidRootPart
end

local function humanoid(player: any): any
	return (player.Character :: any):FindFirstChildOfClass("Humanoid")
end

-- Moves a player somewhere, then lets enough server time pass for every movement check to trust them again (as if
-- they had walked there): the tracker sees and flags the jump, then more than a steal's 10 s pass.
local function teleport(player: any, position: any)
	Sim.moveCharacter(player, position)
	Sim.advance(1.5)
	task.wait(0.4)
	Sim.advance(11)
	task.wait(0.4)
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

local function chat(player: any, text: string)
	Sim.chat(player, text)
	task.wait(0.1)
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

-- Spawns `creatureId` on the belt, puts `player` beside it and buys it. Returns the cash it cost: cash paid in
-- meanwhile doesn't count (an achievement the buy earns pays on AchievementService's one-second loop, which can land
-- inside the wait; everything paid goes through EconomyService.addCash, which counts it in totalEarned).
local function buy(player: any, creatureId: string): number
	chat(player, `/spawn {creatureId}`)
	local item = lastBeltItem(creatureId)
	assert(item, `no {creatureId} on the belt`)
	local belt = Sim.server("Services/BeltService").belt()
	Sim.moveCharacter(player, Vector3.new(belt.startX + 2, 3, Gameplay.belt.width / 2 + 3))
	local session = sessionOf(player)
	local before, earned = session.data.cash, session.data.stats.totalEarned
	Sim.fireServer(player, "BuyBeltItem", item.id)
	task.wait(0.1)
	return before - session.data.cash + (session.data.stats.totalEarned - earned)
end

-- `thief` grabs the Snackling on `victim`'s podium `podiumIndex` (standing next to it, trusted). Returns the carry.
local function grab(thief: any, victim: any, podiumIndex: number): any
	local thiefSession, victimSession = sessionOf(thief), sessionOf(victim)
	local podium = PlotService.podium(victimSession.plot, podiumIndex)
	teleport(thief, podium.base.Position + Vector3.new(4, 2, 0))
	Sim.fireServer(thief, "StealBegin", victimSession.plot, podiumIndex)
	task.wait(0.05)
	Sim.advance(Gameplay.steal.holdSeconds + 0.05)
	task.wait(0.05)
	Sim.fireServer(thief, "StealConfirm", victimSession.plot, podiumIndex)
	task.wait(0.1)
	return thiefSession.carry
end

-- Walks a carrying `thief` home the way an honest client does: at the WalkSpeed the server gave it, 0.2 s late (a
-- new speed reaches the client after a round trip), along `route`. `onStep(elapsed)` runs before every 0.1 s step.
-- Returns "delivered", "cancelled" or "still carrying" (after `limit` seconds).
local function walkHome(thief: any, route: { any }, limit: number, onStep: ((number) -> ())?): string
	local session = sessionOf(thief)
	local latency, dt = 0.2, 0.1
	local speeds: { { t: number, speed: number } } = { { t = 0, speed = humanoid(thief).WalkSpeed } }
	local position = root(thief).Position
	local leg, elapsed = 1, 0
	local steals = session.data.stats.steals -- a delivery counts one
	while elapsed < limit do
		if onStep then
			onStep(elapsed)
		end
		local current = humanoid(thief).WalkSpeed
		if current ~= speeds[#speeds].speed then
			table.insert(speeds, { t = elapsed, speed = current })
		end
		local speed = speeds[1].speed
		for _, entry in speeds do
			if entry.t <= elapsed - latency then
				speed = entry.speed
			end
		end
		local budget = speed * dt
		while budget > 1e-9 and leg <= #route do
			local target = route[leg]
			local offset = Vector3.new(target.X - position.X, 0, target.Z - position.Z)
			if offset.Magnitude <= budget then
				position = Vector3.new(target.X, position.Y, target.Z)
				budget -= offset.Magnitude
				leg += 1
			else
				position += offset.Unit * budget
				budget = 0
			end
		end
		Sim.moveCharacter(thief, position)
		Sim.advance(dt)
		elapsed += dt
		task.wait(0.07)
		if session.carry == nil then
			return if session.data.stats.steals > steals then "delivered" else "cancelled"
		end
	end
	return "still carrying"
end

-- Sells the Snackling on `player`'s first podium (standing at it), to make room.
local function sellOne(player: any)
	local session = sessionOf(player)
	local record = session.data.creatures[1]
	Sim.moveCharacter(player, PlotService.podium(session.plot, record.podium).base.Position)
	Sim.fireServer(player, "SellCreature", record.podium)
	task.wait(0.1)
end

-- The way home from `victim`'s base to `thief`'s, at the height `y`: out of the victim's entrance, along the
-- walkway, into the thief's base.
local function routeHome(thief: any, victim: any, y: number): { any }
	local from = PlotService.refs(sessionOf(victim).plot)
	local to = PlotService.refs(sessionOf(thief).plot)
	local inside = to.spawnCFrame.Position
	return {
		Vector3.new(from.exitPosition.X, y, from.exitPosition.Z),
		Vector3.new(to.exitPosition.X, y, to.exitPosition.Z),
		Vector3.new(inside.X, y, inside.Z),
	}
end

local function scenario()
	print("pre-launch test:")
	local alice = join(ALICE, "Alice")
	local carol = join(CAROL, "Carol")
	local rita = join(RITA, "Rita")
	local bob = join(BOB, "Bob")
	local a, b, c = sessionOf(alice), sessionOf(bob), sessionOf(carol)
	check(a.plot == 1 and b.plot == 4, `Alice and Bob are at the two ends of a row (plots {a.plot} and {b.plot})`)
	chat(alice, "/noshield") -- every new-player shield ends: stealing is allowed

	-- 1. RedeemCode: a huge argument is refused before any pattern runs ----------------------------------------------
	local started = os.clock()
	Sim.fireServer(carol, "RedeemCode", "a" .. string.rep(" ", 32000) .. "b")
	local took = os.clock() - started
	task.wait(0.05)
	check(took < 0.25, `RedeemCode with 32,000 spaces is answered at once ({math.floor(took * 1000)} ms; was 7 s)`)
	check(lastToast(CAROL) == Theme.text.codeInvalid, "and refused as not a code")

	-- 6. Event codes wait for their events (mid-October: Halloween starts on the 23rd) -----------------------------------
	local creatures = #c.data.creatures
	Sim.fireServer(carol, "RedeemCode", "SPOOKY26")
	task.wait(0.1)
	check(#c.data.creatures == creatures, "SPOOKY26 gives nothing before Halloween starts")
	check(lastToast(CAROL) == Theme.text.codeUnknown, "and answers like an unknown code")
	check(c.data.flags.code_SPOOKY26 == nil, "and is not used up")
	local cash = c.data.cash
	Sim.fireServer(carol, "RedeemCode", "WELCOME")
	task.wait(0.1)
	check(c.data.cash > cash, "a code without a start date works")

	-- 2. Server Luck and PolicyService ------------------------------------------------------------------------------
	local ed = join(ED, "Ed")
	task.wait(1.3) -- Ed's lookup fails, waits a second and fails again
	check(alice:GetAttribute(PaidRandomItems.ATTRIBUTE) == true, "a player whose policy allows paid random items")
	check(rita:GetAttribute(PaidRandomItems.ATTRIBUTE) == false, "a player whose policy restricts them")
	check(ed:GetAttribute(PaidRandomItems.ATTRIBUTE) == false, "a failed lookup counts as restricted")
	local ritaHistory = #sessionOf(rita).data.purchaseHistory
	Sim.fireServer(rita, "DevGrantProduct", "ServerLuck")
	task.wait(0.2)
	check(workspace:GetAttribute("PurchasedLuckEndsAt") == 0, "Server Luck is not granted to a restricted player")
	check(#sessionOf(rita).data.purchaseHistory == ritaHistory, "and nothing is recorded as bought")
	Sim.fireServer(alice, "DevGrantProduct", "ServerLuck")
	task.wait(0.2)
	check(
		(workspace:GetAttribute("PurchasedLuckEndsAt") :: number) > Sim.now,
		"it is granted where the policy allows it"
	)
	check(
		LiveOpsService.luckMultiplier() == Monetization.perks.serverLuckMultiplier,
		"the belt rolls at the bought luck"
	)
	check(LiveOpsService.prizeLuckMultiplier() == 1, "prize Snacklings roll without it")
	chat(alice, "/mod luckyBreeze")
	local breeze = Modifiers.modifiers.luckyBreeze.effects.luck
	check(LiveOpsService.prizeLuckMultiplier() == breeze, `a modifier's luck still counts for prizes (x{breeze})`)
	chat(alice, "/mod off")

	-- 5. A game pass "purchase" is granted only when Roblox confirms it ----------------------------------------------
	local pat = join(PAT, "Pat")
	local p = sessionOf(pat)
	local Marketplace = Sim.service("MarketplaceService")
	Marketplace.PromptGamePassPurchaseFinished:Fire(pat, Monetization.passes.DoubleCash.id, true)
	task.wait(0.1)
	check(p.passes.DoubleCash == false, "a pass Roblox says Pat doesn't own is not granted")
	Sim.ownedPasses[PAT] = { [Monetization.passes.VIP.id] = true }
	Marketplace.PromptGamePassPurchaseFinished:Fire(pat, Monetization.passes.VIP.id, true)
	task.wait(0.1)
	check(p.passes.VIP == true and pat:GetAttribute("VIP") == true, "a pass Roblox confirms is granted at once")

	-- 3. Sugar Rush ending mid-carry: an honest thief still gets home -----------------------------------------------------
	EconomyService.giveCreature(a, "pizza_pup", nil)
	local target = a.data.creatures[#a.data.creatures]
	chat(alice, "/mod sugarRush")
	local carry = grab(bob, alice, target.podium)
	check(carry ~= nil, "Bob grabs a Snackling during Sugar Rush")
	if carry then
		local rushEnded = false
		local outcome = walkHome(bob, routeHome(bob, alice, root(bob).Position.Y), 60, function(elapsed: number)
			if not rushEnded and elapsed >= 10 then
				rushEnded = true
				chat(alice, "/mod off") -- ten seconds into the run home
			end
		end)
		check(outcome == "delivered", `Sugar Rush ending mid-carry doesn't cancel him ({outcome})`)
	end

	-- 4. Jackpot raises live income only ----------------------------------------------------------------------------------
	for _ = 1, 3 do
		EconomyService.giveCreature(a, "pizza_pup", nil)
	end
	task.wait(0.1)
	local income, reward, best = a.incomePerSecond, a.rewardIncome, a.data.stats.bestCashPerSecond
	local daily = Replication.snapshot(a).daily.reward
	chat(alice, "/mod jackpot")
	check(
		math.abs(a.incomePerSecond - income * 2) < 1e-6,
		`Jackpot doubles live income ({income} -> {a.incomePerSecond})`
	)
	check(a.rewardIncome == reward, "but not the income rewards are sized from")
	check(a.data.stats.bestCashPerSecond == best, "nor the saved best cash/sec (the global leaderboard)")
	check(Replication.snapshot(a).daily.reward == daily, "nor the daily reward")
	chat(alice, "/mod off")

	-- Offline earnings: Olly comes back after two hours, once with a Jackpot running and once without.
	local olly = join(OLLY, "Olly")
	for _ = 1, 3 do
		EconomyService.giveCreature(sessionOf(olly), "pizza_pup", nil)
	end
	local function comeBack(modifier: string?): number
		Sim.removePlayer(olly)
		task.wait(0.3)
		MockProfileStore.saves[`Player_{OLLY}`].lastSeen = math.floor(Sim.now) - 7200 -- the server's os.time
		chat(alice, if modifier then `/mod {modifier}` else "/mod off")
		olly = join(OLLY, "Olly")
		local list = Sim.received(OLLY, "WelcomeBack")
		local last = list[#list]
		return if last then last[1].amount else -1
	end
	local plain = comeBack(nil)
	local jackpot = comeBack("jackpot")
	chat(alice, "/mod off")
	check(plain > 0 and jackpot == plain, `offline earnings don't double during a Jackpot ({plain}, {jackpot})`)

	-- 7. A player who left keeps no CharacterAdded connection (it held their session) --------------------------------------
	Sim.removePlayer(olly)
	task.wait(0.3)
	chat(alice, "/mod sugarRush") -- a new character of a player still here would get 25% more speed
	local ghost = Sim.spawnCharacter(olly, Vector3.new(0, 3, 0))
	task.wait(0.2)
	local ghostHumanoid = ghost:FindFirstChildOfClass("Humanoid")
	check(ghostHumanoid.WalkSpeed == Gameplay.walkSpeed, "the game no longer hears a departed player's CharacterAdded")
	chat(alice, "/mod off")
	local project = serde.decode("json", fs.readFile("default.project.json"))
	check(
		project.tree.Workspace["$properties"].PlayerCharacterDestroyBehavior == "Enabled",
		"Rojo builds destroy characters and players that left (PlayerCharacterDestroyBehavior)"
	)

	-- 9. A cash pack bought while a thief carries the buyer's best Snackling off pays what the card showed ----------------
	EconomyService.giveCreature(a, "croissant_kraken", nil) -- a Secret: most of Alice's income
	local secret = a.data.creatures[#a.data.creatures]
	local shown = EconomyService.cashPackAmount(a, "CashBite")
	carry = grab(bob, alice, secret.podium)
	check(carry ~= nil and carry.creatureId == "croissant_kraken", "Bob grabs Alice's Secret")
	check(EconomyService.cashPackAmount(a, "CashBite") == shown, "the pack is still worth what its card showed")
	cash = a.data.cash
	Sim.fireServer(alice, "DevGrantProduct", "CashBite")
	task.wait(0.2)
	local quotes = a.data.cashPackQuotes
	local quoted = if #quotes > 0 then quotes[#quotes].amount else -1
	check(quoted == shown and a.data.cash - cash >= shown, `and the receipt pays it ({quoted} of {shown})`)

	-- 10. A runaway caught by a carrying thief with one free podium is sold: the Secret still gets home ------------------
	while EconomyService.freePodium(b) and #b.data.creatures < b.capacity - 1 do
		EconomyService.giveCreature(b, "pizza_pup", nil)
	end
	check(#b.data.creatures == b.capacity - 1, `Bob has one free podium ({#b.data.creatures}/{b.capacity})`)
	local bobCreatures, bobCash = #b.data.creatures, b.data.cash
	local released = false
	local outcome = walkHome(bob, routeHome(bob, alice, root(bob).Position.Y), 60, function(elapsed: number)
		if not released and elapsed >= 1 then
			released = true
			DropService.releaseRunaway(root(bob).Position + Vector3.new(1.5, 0, 0)) -- right in his path
			task.wait(0.3)
			check(#b.data.creatures == bobCreatures and b.data.cash > bobCash, "the runaway he brushes is sold")
		end
	end)
	check(outcome == "delivered", `and the Secret he carries lands in his base ({outcome})`)

	-- 11. Just after a modifier ends, the kinder of the old and new values -------------------------------------------------
	chat(alice, "/cash 10000000")
	local def = GameData.catalog.creatures.pizza_pup
	chat(alice, "/mod clearanceSale")
	chat(alice, "/mod off")
	local paid = buy(alice, "pizza_pup")
	check(
		paid == math.floor(GameData.price(def, nil) * 0.7 + 0.5),
		`a buy right after a sale ends pays its price ({paid})`
	)
	Sim.advance(Modifiers.schedule.changeGraceSeconds + 0.1)
	task.wait(0.1)
	paid = buy(alice, "pizza_pup")
	check(paid == GameData.price(def, nil), `and a moment later the full price ({paid})`)

	-- Snack Patrol: a tag at its longer reach just after it ends still counts.
	sellOne(bob) -- his base filled up with the Secret: make room for another steal
	EconomyService.giveCreature(a, "pizza_pup", nil)
	local bait = a.data.creatures[#a.data.creatures]
	local baitPodium = PlotService.podium(a.plot, bait.podium)
	teleport(carol, baitPodium.base.Position + Vector3.new(4, 2, 16))
	carry = grab(bob, alice, bait.podium)
	check(carry ~= nil, "Bob grabs another one")
	local gap = (root(carol).Position - root(bob).Position) * Vector3.new(1, 0, 1)
	check(gap.Magnitude > Gameplay.steal.tagRange, `Carol stands {math.floor(gap.Magnitude)} studs from him`)
	Sim.fireServer(carol, "TagThief", BOB)
	task.wait(0.1)
	check(b.carry ~= nil, "beyond the normal tag reach")
	chat(alice, "/mod snackPatrol")
	chat(alice, "/mod off")
	Sim.fireServer(carol, "TagThief", BOB)
	task.wait(0.1)
	check(b.carry == nil, "a tag at Snack Patrol's reach just after it ends counts")

	-- 8. A teleport onto a supply crate doesn't win it ----------------------------------------------------------------------
	chat(alice, "/mod supplyDrop")
	task.wait(0.4) -- the drop schedule starts when DropService next looks (every 0.25 s)
	Sim.advance(Modifiers.modifiers.supplyDrop.drops.firstSeconds + 0.5)
	task.wait(0.4)
	Sim.advance(Drops.crate.fallSeconds + 0.5)
	task.wait(0.4)
	local crateId, crate = next(DropService.crateModels())
	check(crate ~= nil and crate:GetAttribute("Landed") == true, "a crate lands")
	if crate then
		local box = (crate :: any).Crate
		teleport(carol, Vector3.new(if box.Position.X > 0 then -140 else 140, box.Position.Y + 1, -box.Position.Z))
		Sim.moveCharacter(carol, box.Position + Vector3.new(3, 1, 0)) -- one jump onto it
		task.wait(0.4)
		Sim.advance(2.1)
		task.wait(0.4)
		local function tryOpen()
			Sim.fireServer(carol, "CrateBegin", crateId)
			task.wait(0.05)
			Sim.advance(Drops.crate.holdSeconds + 0.05)
			task.wait(0.05)
			Sim.fireServer(carol, "CrateOpen", crateId)
			task.wait(0.1)
		end
		tryOpen()
		check((DropService.counts()) == 1, "a teleporter can't open it a few seconds later")
		Sim.advance(Gameplay.tracking.stealTeleportSeconds)
		task.wait(0.4)
		tryOpen()
		check((DropService.counts()) == 0, "only after as long as a steal waits")
	end
	chat(alice, "/mod off")

	-- 13. Analytics: only known keys in breakdown fields, rarity ids as SKUs ----------------------------------------------
	-- Whether Pat's ClientEvents logged `event` (a store funnel step name, or a custom event name) with `value` as its
	-- first breakdown field.
	local function logged(event: string, value: string): boolean
		for _, entry in Sim.analytics do
			local args = entry.args
			local name = if entry.method == "LogFunnelStepEvent"
				then args[5]
				elseif entry.method == "LogCustomEvent" then args[2]
				else nil
			if name == event then
				for _, arg in args do
					-- the custom fields are a plain table (the player is an instance wrapper)
					if type(arg) == "table" and getmetatable(arg) == nil and arg.CustomField01 == value then
						return true
					end
				end
			end
		end
		return false
	end
	Sim.fireServer(pat, "ClientEvent", "store_product_clicked", "somethingNew")
	Sim.fireServer(pat, "ClientEvent", "store_product_clicked", "ServerLuck")
	Sim.fireServer(pat, "ClientEvent", "cash_offer_clicked", "ServerLuck")
	Sim.fireServer(pat, "ClientEvent", "cash_offer_clicked", "CashBag")
	task.wait(0.1)
	check(not logged("ProductPrompted", "somethingNew"), "an unknown store key is not logged")
	check(logged("ProductPrompted", "ServerLuck"), "a known one is")
	check(not logged("cash_offer_clicked", "ServerLuck"), "a cash offer click only logs cash packs")
	check(logged("cash_offer_clicked", "CashBag"), "and does log them")
	local function lastShopSku(): any
		local sku = nil
		for _, entry in Sim.analytics do
			if entry.method == "LogEconomyEvent" and entry.args[6] == "Shop" then
				sku = entry.args[7]
			end
		end
		return sku
	end
	buy(alice, "pizza_pup")
	check(lastShopSku() == def.rarity, `a belt purchase's SKU is its rarity ({tostring(lastShopSku())})`)

	-- 14. baseFull in the state the client gets -------------------------------------------------------------------------
	local function lastState(userId: number): any
		local list = Sim.received(userId, "StateUpdate")
		return list[#list][1]
	end
	while EconomyService.freePodium(p) do
		EconomyService.giveCreature(p, "pizza_pup", nil)
	end
	task.wait(0.4)
	check(lastState(PAT).baseFull == true, "a full base says baseFull")
	sellOne(pat)
	task.wait(0.3)
	check(lastState(PAT).baseFull == false, "and stops saying it once a podium is free")

	-- 12. Core loops survive an error -------------------------------------------------------------------------------------
	local function failOnce(module: any, name: string)
		local original = module[name]
		module[name] = function()
			module[name] = original
			error("injected failure")
		end
	end
	failOnce(Replication, "flush")
	Replication.markDirty(a)
	task.wait(0.5)
	local updates = #Sim.received(ALICE, "StateUpdate")
	Replication.markDirty(a)
	task.wait(0.5)
	check(#Sim.received(ALICE, "StateUpdate") > updates, "state updates carry on after one fails")
	failOnce(PositionTracker, "record")
	task.wait(0.4)
	Sim.advance(1)
	task.wait(0.6)
	check(a.walk ~= nil and a.walk.lastT >= Sim.now - 0.5, "position samples carry on after one fails")
	failOnce(PlotService, "setStored")
	Sim.advance(1)
	task.wait(1.2)
	local stored = a.data.creatures[1].stored
	Sim.advance(1)
	task.wait(1.2)
	check(a.data.creatures[1].stored > stored, "income ticks carry on after one fails")

	-- 6 (again). On Halloween's first day SPOOKY26 works -------------------------------------------------------------------
	local Codes = Sim.server("Codes")
	Sim.advance(Codes.SPOOKY26.startsAt - Sim.now)
	task.wait(1.2)
	creatures = #c.data.creatures
	Sim.fireServer(carol, "RedeemCode", "SPOOKY26")
	task.wait(0.1)
	check(#c.data.creatures == creatures + 1, "SPOOKY26 works once Halloween has started")

	-- 6 (and the Harvest Feast). It comes on by date alone, with its decorations, and FEAST26 works from then -----------
	Sim.advance(Codes.FEAST26.startsAt - 1 - Sim.now)
	task.wait(1.2)
	check(workspace:GetAttribute("SeasonTheme") == "", "Halloween's decorations came down when it ended")
	Sim.fireServer(carol, "RedeemCode", "FEAST26")
	task.wait(0.1)
	check(c.data.flags.code_FEAST26 == nil, "FEAST26 gives nothing the second before the Harvest Feast")
	Sim.advance(1)
	task.wait(1.2)
	check(
		workspace:GetAttribute("SeasonTheme") == "harvest",
		"the Harvest Feast decorations go up on 20 November by themselves"
	)
	check(workspace:GetAttribute("EventBannerId") == "Harvest2026", "and its banner shows")
	creatures = #c.data.creatures
	Sim.fireServer(carol, "RedeemCode", "FEAST26")
	task.wait(0.1)
	local gift = c.data.creatures[#c.data.creatures]
	check(
		#c.data.creatures == creatures + 1 and gift.id == "cranberry_crane" and gift.variant == "maple",
		"FEAST26 gives a Maple Cranberry Crane once the Harvest Feast has started"
	)

	-- One seasonal event at a time (DECISIONS.md #58): an admin's /event takes over from the scheduled one, which
	-- steps aside, and comes back by its dates when the admin's ends --------------------------------------------------
	local BeltService = Sim.server("Services/BeltService")
	chat(alice, "/event Winter2026 5")
	task.wait(1.2)
	check(workspace:GetAttribute("SeasonTheme") == "winter", "an admin's /event Winter2026 takes over from the feast")
	check(
		BeltService.mutationConditions().Harvest2026 == nil and workspace:GetAttribute("EventBannerId") == "Winter2026",
		"the Harvest Feast steps aside: no Maple rolls, and Winter's banner shows"
	)
	chat(alice, "/event off")
	task.wait(1.2)
	check(
		workspace:GetAttribute("SeasonTheme") == "harvest" and BeltService.mutationConditions().Harvest2026 == true,
		"/event off brings the Harvest Feast back, its dates still say so"
	)
	chat(alice, "/event Winter2026 5")
	task.wait(1.2)
	check(workspace:GetAttribute("SeasonTheme") == "winter", "the next /event takes over again")
	Sim.advance(5 * 60 + 1)
	task.wait(1.2)
	check(workspace:GetAttribute("SeasonTheme") == "harvest", "and the feast comes back when that one runs out")

	print(`  ({math.floor(Sim.now - OCTOBER_15_2026)} s of server time)`)
end

local passed, problem = pcall(scenario :: () -> ...any)
if not passed then
	print(`  FAIL the scenario stopped: {problem}`)
	table.insert(failures, tostring(problem))
end
finish()
