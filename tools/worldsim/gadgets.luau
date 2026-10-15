--!strict
--[[
	The gadgets, offline (CI runs it after the server tests):
	    lune run tools/worldsim/gadgets.luau

	Boots the whole server like tools/worldsim/server.luau with the clock virtual (Sim.virtualClock) and random
	modifiers and the map rotation off, then plays every gadget through the real remotes (DECISIONS.md "Gadgets"):
	buying (not enough cash, success, already owned), the tutorial, Fizzy Soda speeds and the movement checks that must
	accept them (walking, and a thief running a dead-straight line home, where the carry's straight-line cap is
	strict; a cheater at the same speed without a soda is caught) and its cooldown, the soda under Sugar Rush (the cap),
	Banana Peels (refused outside your base, the owner never slips, a thief carrying your Snackling drops it and it
	goes home, a shield doesn't help, a new one replaces it and keeps its button's ring, it expires), the Bubble Shield
	against tags, the Snack Magnet from across the map and its cooldown, Gadget Frenzy's shorter recharges (and their
	floors), and gadgets kept through a rebirth. It fails on any error, any unexpected warning, or any check.

	Alice (plot 1) is the owner. Bob joins fifth and gets plot 5, straight across the belt from hers.
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

local ALICE, CAROL, DAN, EVE, BOB = 5001, 5002, 5003, 5004, 5005

local EXPECTED_WARNINGS = {
	"MessagingService.SubscribeAsync is not available offline",
	"dropped carry for Carol: implausible movement speed", -- the cheater, on purpose
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
		print(`gadgets test: {#failures} problem(s)`)
		process.exit(1)
	end
	print("gadgets test: no problems")
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
local GadgetService = Sim.server("Services/GadgetService")
local Movement = Sim.server("Services/Movement")
local PositionTracker = Sim.server("Services/PositionTracker")
local Gadgets = Sim.shared("Config/Gadgets")
local Gameplay = Sim.shared("Config/Gameplay")
local Theme = Sim.shared("Config/Theme")
local Format = Sim.shared("Logic/Format")
local workspace = Sim.workspace()

local SODA, PEEL, SHIELD, MAGNET =
	Gadgets.gadgets.soda, Gadgets.gadgets.peel, Gadgets.gadgets.shield, Gadgets.gadgets.magnet
local CARRY = Gameplay.steal.carrySpeedMultiplier

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

local function chat(player: any, text: string)
	Sim.chat(player, text)
	task.wait(0.1)
end

-- Lets server time pass in steps, as if everyone stood still (the server's loops run in between).
local function wait(seconds: number)
	local left = seconds
	while left > 0 do
		local step = math.min(left, 2)
		Sim.advance(step)
		task.wait(0.15) -- the server's 0.1 s loops (peels, gadget speeds) get to run
		left -= step
	end
end

-- Moves a player somewhere, then lets enough server time pass for every movement check to trust them again.
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

local function use(player: any, id: string)
	Sim.fireServer(player, "UseGadget", id)
	task.wait(0.1)
end

-- A purchase, a second after the last one (BuyGadget is rate-limited: 3 at once, then 1 a second).
local function buy(player: any, id: string)
	Sim.advance(1.1)
	Sim.fireServer(player, "BuyGadget", id)
	task.wait(0.1)
end

-- What the analytics logged as `name` (custom events), oldest first: their fields.
local function logged(name: string): { { [string]: any } }
	local list = {}
	for _, entry in Sim.analytics do
		if entry.method == "LogCustomEvent" and entry.args[2] == name then
			table.insert(list, (entry.args[4] or {}) :: any)
		end
	end
	return list
end

-- Walks `player` in `direction` (horizontal) the way an honest client does: at the WalkSpeed the server gave it, 0.2 s
-- late (a new speed reaches the client after a round trip), or at `speed` when given (a cheater), for `seconds` or
-- until `stop()` says so. Returns the server time it walked.
local function walk(player: any, direction: any, seconds: number, speed: number?, stop: (() -> boolean)?): number
	local latency, dt = 0.2, 0.1
	local unit = Vector3.new(direction.X, 0, direction.Z).Unit
	local speeds: { { t: number, speed: number } } = { { t = 0, speed = humanoid(player).WalkSpeed } }
	local position = root(player).Position
	local elapsed = 0
	while elapsed < seconds - 1e-9 do
		local current = humanoid(player).WalkSpeed
		if current ~= speeds[#speeds].speed then
			table.insert(speeds, { t = elapsed, speed = current })
		end
		local now = speeds[1].speed
		for _, entry in speeds do
			if entry.t <= elapsed - latency then
				now = entry.speed
			end
		end
		position += unit * (speed or now) * dt
		Sim.moveCharacter(player, position)
		Sim.advance(dt)
		elapsed += dt
		task.wait(0.07)
		if stop and stop() then
			break
		end
	end
	return elapsed
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

local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-6
end

local function peelOf(userId: number): any
	return GadgetService.peelModels()[userId]
end

local function scenario()
	print("gadgets test:")
	local alice = join(ALICE, "Alice")
	local carol = join(CAROL, "Carol")
	local dan = join(DAN, "Dan")
	join(EVE, "Eve")
	local bob = join(BOB, "Bob")
	local a, b, c, d = sessionOf(alice), sessionOf(bob), sessionOf(carol), sessionOf(dan)
	check(a.plot == 1 and b.plot == 5, `Alice and Bob face each other across the belt (plots {a.plot} and {b.plot})`)

	-- Buying -------------------------------------------------------------------------------------------------------
	local startCash = a.data.cash
	buy(alice, "soda")
	check(a.data.flags.gadget_soda == nil, `not enough cash: no Fizzy Soda (${startCash} < ${SODA.price})`)
	check(a.data.cash == startCash and lastToast(ALICE) == Theme.text.notEnoughCash, 'and "Not enough cash!"')
	buy(alice, "rocketBoots")
	check(a.data.cash == startCash, "an unknown gadget buys nothing")
	chat(alice, "/cash 10000000")
	local before = a.data.cash
	buy(alice, "soda")
	check(a.data.flags.gadget_soda == true, "with the cash: the Fizzy Soda is hers (flag gadget_soda)")
	check(before - a.data.cash == SODA.price, `for exactly its price ({before - a.data.cash})`)
	task.wait(0.3) -- the next state update
	local states = Sim.received(ALICE, "StateUpdate")
	local view = states[#states][1].gadgets
	check(view.owned[1] == "soda", "her state lists it, so its button shows")
	before = a.data.cash
	buy(alice, "soda")
	check(a.data.cash == before and lastToast(ALICE) == Theme.text.gadgetAlreadyOwned, "already owned: paid once")
	for _, id in { "peel", "shield", "magnet" } do
		buy(alice, id)
	end
	check(a.data.flags.gadget_peel and a.data.flags.gadget_shield and a.data.flags.gadget_magnet, "she buys the rest")
	local bought = logged("gadget_bought")
	check(#bought == 4 and bought[1].CustomField01 == "soda", "each purchase is logged with the gadget's key")
	chat(bob, "/cash 10000000")
	for _, id in { "soda", "shield", "magnet" } do
		buy(bob, id)
	end

	-- Not during the tutorial ------------------------------------------------------------------------------------------
	check(a.tutorial ~= nil, "Alice is a brand-new player: her tutorial is running")
	use(alice, "soda")
	check(a.gadgets.readyAt.soda == nil and lastToast(ALICE) == Theme.text.gadgetTutorial, "no gadgets in the tutorial")
	for _, player in Sim.service("Players"):GetPlayers() do
		Sim.fireServer(player, "SkipTutorial")
	end
	task.wait(0.1)
	check(a.tutorial == nil and b.tutorial == nil, "everyone skips it")
	chat(alice, "/noshield") -- every new-player shield ends: stealing is allowed

	-- Fizzy Soda: faster, and the movement checks follow -------------------------------------------------------------
	local walkway = Vector3.new(-120, 3, 15) -- the north walkway, along the belt
	teleport(alice, walkway)
	local flaggedBefore = a.flaggedAt
	use(alice, "soda")
	check(near(humanoid(alice).WalkSpeed, Gameplay.walkSpeed * SODA.speedMultiplier), "the soda speeds Alice up")
	check(near(Movement.allowance(a), SODA.speedMultiplier), "and the movement checks allow that speed")
	check(alice:GetAttribute("GadgetSpeedUntil") == a.gadgets.speedUntil, "everyone sees her fizz (attribute)")
	walk(alice, Vector3.new(1, 0, 0), SODA.durationSeconds + 2) -- through the end of it, with the client's lag
	check(near(humanoid(alice).WalkSpeed, Gameplay.walkSpeed), "after 6 s she walks at the normal speed again")
	check(a.flaggedAt == flaggedBefore, "running at the soda's speed and just after is never flagged")
	check(PositionTracker.isTrusted(a, root(alice).Position), "and her position is trusted (she can tag at once)")
	check(Movement.allowance(a) >= SODA.speedMultiplier - 1e-9, "the checks keep the soda's speed a moment longer")
	wait(Gadgets.speedGraceSeconds)
	check(near(Movement.allowance(a), 1), "and then go back to normal")
	use(alice, "soda")
	check(string.find(lastToast(ALICE), "recharges", 1, true) ~= nil, `its cooldown holds ({lastToast(ALICE)})`)
	check(near(humanoid(alice).WalkSpeed, Gameplay.walkSpeed), "and gives no speed")

	-- With Sugar Rush: capped
	wait(SODA.cooldownSeconds)
	chat(alice, "/mod sugarRush")
	use(alice, "soda")
	check(
		near(humanoid(alice).WalkSpeed, Gameplay.walkSpeed * Gadgets.maxSpeedMultiplier),
		`Sugar Rush and the soda together are capped at x{Gadgets.maxSpeedMultiplier} ({humanoid(alice).WalkSpeed})`
	)
	check(Movement.allowance(a) <= Gadgets.maxSpeedMultiplier + 1e-9, "and so are the movement checks")
	chat(alice, "/mod off")
	wait(SODA.durationSeconds + Gadgets.speedGraceSeconds)

	-- A thief on soda runs a dead-straight line home: the carry's straight-line cap allows the soda's speed ------------
	for _ = 1, 3 do
		EconomyService.giveCreature(a, "pizza_pup", nil)
	end
	local carry = grab(bob, alice, 1)
	check(carry ~= nil, "Bob grabs Alice's Snackling")
	use(bob, "soda")
	check(
		near(humanoid(bob).WalkSpeed, Gameplay.walkSpeed * SODA.speedMultiplier * CARRY),
		`the soda works while carrying, on top of the carry slowdown ({humanoid(bob).WalkSpeed})`
	)
	local steals = b.data.stats.steals
	local home = -1 -- straight towards the belt and on into his base across it
	walk(bob, Vector3.new(0, 0, home), 15, nil, function(): boolean
		return b.carry == nil
	end)
	check(b.data.stats.steals == steals + 1, "he gets home with it: the movement checks accepted the soda")
	-- The same run without a soda is a speed hack, and is caught.
	carry = grab(carol, alice, 2)
	check(carry ~= nil, "Carol grabs another one, without a soda")
	local cheat = Gameplay.walkSpeed * SODA.speedMultiplier * CARRY
	walk(carol, Vector3.new(0, 0, home), 10, cheat, function(): boolean
		return c.carry == nil
	end)
	check(
		c.carry == nil and c.data.stats.steals == 0,
		"running that fast without one drops the Snackling (the check is real)"
	)
	check(#a.data.creatures == 2, "Alice lost one Snackling to Bob, none to Carol")

	-- Banana Peel ------------------------------------------------------------------------------------------------------
	local plot = PlotService.refs(a.plot)
	teleport(alice, walkway)
	use(alice, "peel")
	check(peelOf(ALICE) == nil and a.gadgets.readyAt.peel == nil, "a peel outside her base is refused, nothing used")
	check(lastToast(ALICE) == Theme.text.peelOutsideBase, "and she is told why")
	-- On the way from her first Snackling's podium to the back of her base, where Bob will run with it.
	local record = a.data.creatures[1]
	local grabAt = PlotService.podium(a.plot, record.podium).base.Position + Vector3.new(4, 2, 0)
	local spot = Vector3.new(grabAt.X, plot.floorY + 3, grabAt.Z + 10)
	teleport(alice, spot)
	use(alice, "peel")
	local peel = peelOf(ALICE)
	check(peel ~= nil, "inside her base it goes down at her feet")
	local inTheWay = 0
	if peel then
		check(math.abs(peel:GetPivot().Position.Y - plot.floorY) < 1, "on her base's floor")
		for _, part in peel:GetDescendants() do
			if part:IsA("BasePart") and (part.CanCollide or part.CanTouch or part.CanQuery or not part.Anchored) then
				inTheWay += 1
			end
		end
	end
	check(inTheWay == 0, "anchored, and it never collides, touches or blocks a ray")
	walk(alice, Vector3.new(0, 0, 1), 1)
	walk(alice, Vector3.new(0, 0, -1), 1) -- back and forth over it
	check(peelOf(ALICE) ~= nil and not near(humanoid(alice).WalkSpeed, 0), "the owner never slips on her own peel")

	-- A shielded thief carrying her Snackling runs over it: it still trips him.
	wait(Gameplay.steal.thiefCooldownAfterTagSeconds)
	carry = grab(bob, alice, record.podium)
	check(carry ~= nil, "Bob grabs another Snackling")
	use(bob, "shield")
	check(b.gadgets.shieldUntil > Sim.now, "and puts his Bubble Shield up")
	walk(bob, Vector3.new(0, 0, 1), 3, nil, function(): boolean
		return b.carry == nil
	end)
	check(b.carry == nil, "stepping on the peel, he slips: a shield doesn't stop a peel")
	check(PlotService.isBusy(a.plot, record.podium) == false, "the Snackling runs home to its podium")
	check(#a.data.creatures == 2, "and stays Alice's")
	check(near(humanoid(bob).WalkSpeed, 0), `Bob can't move for a moment ({humanoid(bob).WalkSpeed})`)
	check((bob:GetAttribute("SlippedUntil") :: number) > Sim.now, "and everyone sees him dizzy (attribute)")
	check(peelOf(ALICE) == nil, "the peel is used up")
	check(
		lastToast(BOB) == Format.template(Theme.text.stealFailedSlipped, { creature = "Pizza Pup" }),
		`he is told what happened ({lastToast(BOB)})`
	)
	check(
		string.find(lastToast(ALICE), Theme.text.peelTagger, 1, true) ~= nil,
		`and Alice hears her peel saved it ({lastToast(ALICE)})`
	)
	check(b.stealCooldownUntil > Sim.now, "he has to wait before stealing again, as after a tag")
	local drops = logged("gadget_effect")
	check(#drops >= 1 and drops[#drops].CustomField02 == "peelDrop", "logged as a peel drop")
	wait(PEEL.slipSeconds + 0.3)
	check(near(humanoid(bob).WalkSpeed, Gameplay.walkSpeed), "the slip wears off")

	-- Anyone else slips too, carrying or not: Bob is still standing there when she drops the next one.
	wait(PEEL.cooldownSeconds)
	use(alice, "peel")
	task.wait(0.2)
	check(peelOf(ALICE) == nil and near(humanoid(bob).WalkSpeed, 0), "a visitor standing on it slips at once")
	check(
		lastToast(ALICE) == Format.template(Theme.text.peelSlippedOwner, { player = "Bob" }),
		`and Alice hears about it ({lastToast(ALICE)})`
	)
	check(#a.data.creatures == 2 and b.carry == nil, "nothing else happens: he carried nothing")

	-- One peel at a time, and it expires
	teleport(bob, PlotService.refs(b.plot).spawnCFrame.Position) -- home, away from her base
	wait(PEEL.cooldownSeconds)
	use(alice, "peel")
	check(peelOf(ALICE) ~= nil, `after its cooldown she drops another ({lastToast(ALICE)})`)
	-- after another cooldown a new one replaces it, and her button's "running" ring is the new peel's (review 2:
	-- taking the old one away cleared the ring GadgetRules.use had just started)
	local older = peelOf(ALICE)
	wait(PEEL.cooldownSeconds)
	use(alice, "peel")
	local newer = peelOf(ALICE)
	local lying = 0
	for _, child in workspace.Gadgets:GetChildren() do
		if child.Name == "BananaPeel" then
			lying += 1
		end
	end
	check(newer ~= nil and newer ~= older and lying == 1, `a new peel replaces the one lying there ({lying} lying)`)
	local ring = a.gadgets.activeUntil.peel
	check(
		newer ~= nil and ring ~= nil and math.abs(ring - newer:GetAttribute("ExpiresAt")) < 0.01,
		`and her button shows the new one running until it goes ({ring})`
	)
	wait(PEEL.durationSeconds - 2)
	check(peelOf(ALICE) ~= nil, "it lies there until its time is up")
	wait(3)
	check(peelOf(ALICE) == nil and workspace.Gadgets:FindFirstChild("BananaPeel") == nil, "then it goes")
	check(a.gadgets.activeUntil.peel == nil, "and its ring with it")

	-- Bubble Shield: no tags until it pops ------------------------------------------------------------------------------
	wait(SHIELD.cooldownSeconds)
	local target = a.data.creatures[1]
	teleport(alice, PlotService.podium(a.plot, target.podium).base.Position + Vector3.new(9, 2, 0))
	carry = grab(bob, alice, target.podium)
	check(carry ~= nil, "Bob grabs again, with Alice right there")
	use(bob, "shield")
	local bubble = (bob.Character :: any):FindFirstChild("GadgetShield")
	check(
		bubble ~= nil and bubble.Massless and not bubble.CanCollide and not bubble.CanTouch and not bubble.CanQuery,
		"a bubble everyone can see wraps him, and it gets in nobody's way"
	)
	Sim.fireServer(alice, "TagThief", BOB)
	task.wait(0.1)
	check(b.carry ~= nil, "Alice's tag bounces off the bubble")
	check(lastToast(ALICE) == Theme.text.shieldBlocked, 'and she sees "Shielded!"')
	wait(SHIELD.durationSeconds)
	Sim.fireServer(alice, "TagThief", BOB)
	task.wait(0.2)
	check(b.carry == nil, "once it pops, her tag lands and the Snackling goes home")
	check((bob.Character :: any):FindFirstChild("GadgetShield") == nil, "and the bubble is gone")

	-- Snack Magnet: every pad from anywhere -----------------------------------------------------------------------------
	teleport(alice, Vector3.new(130, 3, -15)) -- the far end of the other walkway; income piles up meanwhile
	local stored = 0
	for _, entry in a.data.creatures do
		stored += math.floor(entry.stored)
	end
	local collects = #Sim.received(ALICE, "Effect")
	before = a.data.cash
	use(alice, "magnet")
	check(
		stored > 0 and a.data.cash - before == stored,
		`the magnet collects every pad from across the map (${stored})`
	)
	local effects = Sim.received(ALICE, "Effect")
	local pads = 0
	for index = collects + 1, #effects do
		if effects[index][1].kind == "collect" then
			pads += 1
		end
	end
	check(pads == #a.data.creatures, `each pad shows its "+$" as if she walked over it ({pads})`)
	wait(3)
	before = a.data.cash
	use(alice, "magnet")
	check(a.data.cash == before, "its cooldown holds")
	wait(MAGNET.cooldownSeconds)
	before = a.data.cash
	use(alice, "magnet")
	check(a.data.cash > before, "and then it works again")
	chat(dan, "/gadgets") -- Studio: every gadget
	use(dan, "magnet")
	check(d.gadgets.readyAt.magnet == nil, "with nothing to collect it isn't used up")
	check(lastToast(DAN) == Theme.text.magnetEmpty, "and says so")

	-- Gadget Frenzy: recharges halved, never under the fairness floors; one already recharging catches up -------------
	use(bob, "shield")
	local shieldUsed = Sim.now
	check(near(b.gadgets.readyAt.shield, shieldUsed + SHIELD.cooldownSeconds), "a shield recharges in its own time")
	wait(10)
	chat(alice, "/mod gadgetFrenzy")
	task.wait(0.2)
	local left = SHIELD.cooldownSeconds - 10
	check(
		near(b.gadgets.readyAt.shield, shieldUsed + 10 + left / 2),
		`Gadget Frenzy: a recharge already running finishes twice as fast ({b.gadgets.readyAt.shield - Sim.now} s left)`
	)
	task.wait(0.3) -- the next state update
	local frenzyStates = Sim.received(BOB, "StateUpdate")
	local frenzyView = frenzyStates[#frenzyStates][1].gadgets
	check(
		near(frenzyView.readyAt.shield, b.gadgets.readyAt.shield) and near(frenzyView.usedAt.shield, shieldUsed),
		"and his button is told (its disc runs from when he used it)"
	)
	use(bob, "soda")
	check(
		near(b.gadgets.readyAt.soda - Sim.now, 3 * SODA.durationSeconds),
		`a soda used now recharges in {3 * SODA.durationSeconds} s, not {SODA.cooldownSeconds / 2}: on a third of the time at most`
	)
	check(
		near(humanoid(bob).WalkSpeed, Gameplay.walkSpeed * SODA.speedMultiplier),
		"and runs exactly as fast as ever (the speed caps are untouched)"
	)
	use(dan, "shield")
	local danUsed = Sim.now
	check(
		near(d.gadgets.readyAt.shield - danUsed, SHIELD.cooldownSeconds / 2),
		"a shield used now recharges in half the time"
	)
	check(near(d.gadgets.shieldUntil - danUsed, SHIELD.durationSeconds), "and lasts just as long as ever")
	chat(alice, "/mod off")
	task.wait(0.2)
	check(
		near(d.gadgets.readyAt.shield - danUsed, SHIELD.cooldownSeconds / 2),
		"when it ends, recharges keep whatever they had left"
	)

	-- Kept through a rebirth -----------------------------------------------------------------------------------------
	chat(alice, "/cash 30000000")
	Sim.fireServer(alice, "Rebirth")
	task.wait(0.2)
	check(a.data.rebirths == 1 and #a.data.creatures == 0, "Alice rebirths")
	check(
		a.data.flags.gadget_soda
			and a.data.flags.gadget_peel
			and a.data.flags.gadget_shield
			and a.data.flags.gadget_magnet,
		"and keeps every gadget"
	)
	check(#logged("gadget_used") >= 8, "every use is logged with the gadget's key")

	-- Leaving -----------------------------------------------------------------------------------------------------------
	wait(PEEL.cooldownSeconds)
	teleport(alice, spot)
	use(alice, "peel")
	check(peelOf(ALICE) ~= nil, "a last peel")
	Sim.removePlayer(alice)
	task.wait(0.3)
	check(peelOf(ALICE) == nil, "goes when its owner leaves")
	local save = MockProfileStore.saves[`Player_{ALICE}`]
	check(save ~= nil and save.flags.gadget_magnet == true, "and her gadgets are in her save")
end

local passed, problem = pcall(scenario :: () -> ...any)
if not passed then
	print(`  FAIL the scenario stopped: {problem}`)
	table.insert(failures, tostring(problem))
end
finish()
