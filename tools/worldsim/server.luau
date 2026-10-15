--!strict
--[[
	The whole server, offline (CI runs it after the world smoke test):
	    lune run tools/worldsim/server.luau

	Boots src/server/init.server.luau in the Roblox stand-in (tools/worldsim/Sim) with ProfileStore replaced by an
	in-memory store, then plays a short session with two fake players through the real remotes and chat commands:
	join, buy from the belt, every server modifier's effect where it applies (belt prices, speed, locks, steals),
	weather (the sky and the mutation it unlocks), drops, codes, gifts and the Lucky Spin, achievements, a base lock, a
	map change and a map vote, the seasonal events switched on and off (each one's decorations, lighting and mutation),
	and leaving with the save written. It fails on any error, any
	unexpected warning, or any check below. Server time only moves when the test moves it (Sim.advance).
]]

local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")
local Sim = require("./Sim")
local MockProfileStore = require("./MockProfileStore")

Sim.mock("ServerPackages/ProfileStore.lua", MockProfileStore)

-- Warnings the offline server is expected to give (online-only services).
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
		print(`server test: {#failures} problem(s)`)
		process.exit(1)
	end
	print("server test: no problems")
	process.exit(0)
end

local ok, err = pcall(function()
	Sim.require("ServerScriptService", "Server")
end)
if not ok then
	print(`the server failed to boot: {err}`)
	process.exit(1)
end

local Sessions = Sim.server("Services/Sessions")
local PlotService = Sim.server("Services/PlotService")
local ModifierService = Sim.server("Services/ModifierService")
local GameData = Sim.shared("GameData")
local Gameplay = Sim.shared("Config/Gameplay")
local MapThemes = Sim.shared("Config/MapThemes")
local Modifiers = Sim.shared("Config/Modifiers")
local MutationRules = Sim.shared("Logic/MutationRules")
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

-- Moves a player somewhere far, then lets enough (server) time pass for the movement checks to trust them again,
-- as if they had walked there: the server's own settle window after it placed them ends, the tracker sees (and flags)
-- the jump, and then several seconds of standing still pass.
local function teleport(player: any, position: any)
	Sim.moveCharacter(player, position)
	Sim.advance(1.5)
	task.wait(0.4)
	Sim.advance(11)
	task.wait(0.4)
end

-- The newest belt item of `creatureId` the server announced.
local function lastBeltItem(creatureId: string): any
	local found = nil
	for _, args in Sim.received(0, "BeltSpawn") do
		local item = args[1]
		if item.creatureId == creatureId then
			found = item
		end
	end
	return found
end

-- Spawns `creatureId` on the belt (dev command), walks `player` to it and buys it. Returns the cash it cost.
local function buy(player: any, creatureId: string): number
	Sim.chat(player, `/spawn {creatureId}`)
	task.wait(0.1)
	local item = lastBeltItem(creatureId)
	assert(item, `no {creatureId} on the belt`)
	-- Server time doesn't move: the item sits where the belt starts.
	local belt = Sim.server("Services/BeltService").belt()
	Sim.moveCharacter(player, roblox.Vector3.new(belt.startX + 2, 3, Gameplay.belt.width / 2 + 3))
	local session = sessionOf(player)
	local before = session.data.cash
	Sim.fireServer(player, "BuyBeltItem", item.id)
	task.wait(0.1)
	return before - session.data.cash
end

local function scenario()
	print("server test:")
	local alice = join(1001, "Alice")
	local bob = join(1002, "Bob")
	local aliceSession = sessionOf(alice)
	local bobSession = sessionOf(bob)
	check(
		aliceSession.plot ~= 0 and bobSession.plot ~= 0 and aliceSession.plot ~= bobSession.plot,
		"both players got a plot"
	)
	check(#Sim.received(1001, "StateUpdate") > 0, "the client got its state")

	-- Buying from the belt ------------------------------------------------------------------------------------------------
	Sim.chat(alice, "/cash 1000000")
	task.wait(0.1)
	local creatureId = "pizza_pup"
	local def = GameData.catalog.creatures[creatureId]
	local paid = buy(alice, creatureId)
	check(paid == GameData.price(def, nil), `a belt purchase costs the price ({paid})`)
	check(#aliceSession.data.creatures == 1, "the Snackling landed in the base")

	-- Modifiers -----------------------------------------------------------------------------------------------------------
	Sim.chat(alice, "/mod clearanceSale")
	task.wait(0.1)
	check(workspace:GetAttribute("Modifier") == "clearanceSale", "a modifier starts by command")
	paid = buy(alice, creatureId)
	check(paid == math.floor(GameData.price(def, nil) * 0.7 + 0.5), `the sale price is charged ({paid})`)

	local humanoid = (alice.Character :: any):FindFirstChildOfClass("Humanoid")
	Sim.chat(alice, "/mod sugarRush")
	task.wait(0.1)
	check(humanoid.WalkSpeed == Gameplay.walkSpeed * 1.25, `Sugar Rush speeds everyone up ({humanoid.WalkSpeed})`)
	check(ModifierService.walkSpeedAllowance() >= 1.25, "the movement checks allow the new speed")
	Sim.chat(alice, "/mod off")
	task.wait(0.1)
	check(humanoid.WalkSpeed == Gameplay.walkSpeed, "speed comes back when it ends")
	check(ModifierService.walkSpeedAllowance() >= 1.25, "and the checks keep the old speed for a moment")

	Sim.chat(alice, "/mod fortress")
	task.wait(0.1)
	check(aliceSession.lockDuration > Gameplay.lock.durationSeconds * 1.4, "Fortress makes locks longer")
	Sim.chat(alice, "/mod luckyBreeze")
	task.wait(0.1)
	check((workspace:GetAttribute("LuckMultiplier") :: number) >= 2, "Lucky Breeze raises the server luck")
	Sim.chat(alice, "/mod off")
	task.wait(1.2)
	check(workspace:GetAttribute("LuckMultiplier") == 1, "the luck goes when it ends")
	check(aliceSession.lockDuration == Gameplay.lock.durationSeconds, "lock length back to normal")

	-- Weather: a storm darkens the sky and lets Electric Snacklings roll; the map's own mutation always can.
	local BeltService = Sim.server("Services/BeltService")
	local Lighting = Sim.service("Lighting")
	local mapTheme = workspace:GetAttribute("MapTheme")
	local mapKey = MutationRules.mapKey(mapTheme)
	local stormKey = MutationRules.modifierKey("thunderstorm")
	check(BeltService.mutationConditions()[mapKey] == true, `the map's signature mutation can roll ({mapTheme})`)
	check(BeltService.mutationConditions()[stormKey] == nil, "no storm, no Electric Snacklings")
	Sim.chat(alice, "/mod thunderstorm")
	task.wait(0.1)
	check(BeltService.mutationConditions()[stormKey] == true, "a storm lets Electric Snacklings roll")
	local storm = Modifiers.modifiers.thunderstorm.lighting
	check(math.abs(Lighting.ClockTime - storm.clockTime) < 1e-3, `the storm changes the sky ({Lighting.ClockTime})`)
	Sim.chat(alice, "/spawn pizza_pup electric")
	task.wait(0.1)
	local electric = lastBeltItem("pizza_pup")
	check(electric ~= nil and electric.variant == "electric", "an Electric Snackling rides the belt")
	Sim.chat(alice, "/mod off")
	task.wait(0.1)
	check(BeltService.mutationConditions()[stormKey] == nil, "the storm's mutation goes with it")
	local mapLighting = MapThemes.themes[mapTheme].lighting
	check(math.abs(Lighting.ClockTime - mapLighting.clockTime) < 1e-3, "and the map's sky comes back")

	-- Drops: a supply crate parachutes onto the walkway and the first player to hold it open wins it ---------------------
	local DropService = Sim.server("Services/DropService")
	local Drops = Sim.shared("Config/Drops")
	Sim.chat(alice, "/mod supplyDrop")
	task.wait(0.4)
	Sim.advance(Modifiers.modifiers.supplyDrop.drops.firstSeconds + 0.5)
	task.wait(0.4)
	check((DropService.counts()) == 1, "Supply Drop: a crate falls")
	Sim.advance(Drops.crate.fallSeconds + 0.5)
	task.wait(0.4)
	local crateId, crate = next(DropService.crateModels())
	check(crate ~= nil and crate:GetAttribute("Landed") == true, "the crate lands on the walkway")
	local box = (crate :: any).Crate
	check(math.abs(box.Position.Z) > Gameplay.belt.width / 2, "beside the belt, not on it")
	teleport(bob, box.Position + roblox.Vector3.new(3, 1, 0))
	local bobCreatures = #bobSession.data.creatures
	local bobCash = bobSession.data.cash
	Sim.fireServer(bob, "CrateOpen", crateId)
	task.wait(0.1)
	check((DropService.counts()) == 1, "it does not open without holding")
	Sim.fireServer(bob, "CrateBegin", crateId)
	task.wait(0.05)
	Sim.advance(Drops.crate.holdSeconds)
	Sim.fireServer(bob, "CrateOpen", crateId)
	task.wait(0.1)
	check((DropService.counts()) == 0, "holding it open takes the crate")
	check(#bobSession.data.creatures == bobCreatures + 1, "a Snackling lands in the opener's base")
	check(bobSession.data.cash > bobCash, "plus some cash")
	check(bobSession.data.flags.did_crate == true, "and it counts for Crate Cracker")
	Sim.fireServer(alice, "CrateOpen", crateId)
	task.wait(0.1)
	check(#aliceSession.data.creatures == 2, "nobody else gets it")

	-- Coins rain on the walkways; walking through one collects it
	-- (Bob still stands on the walkway by the crate, so a coin may land on him and be collected at once.)
	local function coinsCollected(): number
		local count = 0
		for _, entry in Sim.received(1002, "Effect") do
			if type(entry[1]) == "table" and entry[1].kind == "collect" then
				count += 1
			end
		end
		return count
	end
	local collectedBefore = coinsCollected()
	Sim.chat(alice, "/mod coinRain")
	task.wait(0.4)
	Sim.advance(Modifiers.modifiers.coinRain.drops.firstSeconds + 0.5)
	task.wait(0.4)
	local _, coinCount = DropService.counts()
	local landedOnBob = coinsCollected() - collectedBefore
	check(
		coinCount + landedOnBob == Drops.coins.perWave,
		`Coin Rain: coins fall ({coinCount}, and {landedOnBob} on Bob)`
	)
	local coin = nil
	for _, child in workspace.Drops:GetChildren() do
		if child.Name == "Coin" then
			coin = child
		end
	end
	bobCash = bobSession.data.cash
	teleport(bob, coin.Position - roblox.Vector3.new(0, Drops.coins.height - 2.5, 0))
	task.wait(0.3)
	local _, coinsLeft = DropService.counts()
	check(coinsLeft < coinCount, "walking through a coin picks it up")
	check(bobSession.data.cash > bobCash, "and pays")
	Sim.advance(Drops.coins.lifetimeSeconds)
	task.wait(0.4)
	Sim.chat(alice, "/mod off")
	task.wait(0.4)
	_, coinsLeft = DropService.counts()
	check(coinsLeft == 0, "uncollected coins disappear")

	-- Great Escape: a Snackling escapes far from everyone and runs; walking into one catches it
	Sim.chat(alice, "/mod greatEscape")
	task.wait(0.4)
	Sim.advance(Modifiers.modifiers.greatEscape.drops.firstSeconds + 0.5)
	task.wait(0.4)
	local _, _, runawayCount = DropService.counts()
	check(runawayCount == 1, "Great Escape: a Snackling escapes")
	local runner = nil
	for _, child in workspace.Drops:GetChildren() do
		if child:GetAttribute("RunawayId") ~= nil then
			runner = child
		end
	end
	check(runner ~= nil and type(runner:GetAttribute("Leg")) == "string", "its run is published as one attribute")
	local startedAt = DropService.runawayPosition(runner)
	local nearestPlayer = math.huge
	for _, player in { alice, bob } do
		local root = (player.Character :: any).HumanoidRootPart
		local offset = root.Position - startedAt
		nearestPlayer = math.min(nearestPlayer, roblox.Vector3.new(offset.X, 0, offset.Z).Magnitude)
	end
	check(nearestPlayer > 25, `it appears far from everyone ({math.floor(nearestPlayer)} studs)`)
	-- (it wanders at random while nobody is near, so it may come back towards where it started: look at how far it
	-- got on the way)
	local farthest = 0
	for _ = 1, 12 do
		Sim.advance(0.5)
		task.wait(0.12)
		local at = DropService.runawayPosition(runner)
		if at then
			farthest = math.max(farthest, (at - startedAt).Magnitude)
		end
	end
	local nowAt = DropService.runawayPosition(runner)
	check(nowAt ~= nil and farthest > 2, `it runs off ({math.floor(farthest)} studs)`)
	check(math.abs(nowAt.X) <= Drops.area.maxX + 1e-6, "and stays along the walkways")
	local bobRoot = (bob.Character :: any).HumanoidRootPart
	local bobBefore = #bobSession.data.creatures
	local bobCashBefore = bobSession.data.cash
	DropService.releaseRunaway(bobRoot.Position + roblox.Vector3.new(2, 0, 1))
	task.wait(0.3)
	_, _, runawayCount = DropService.counts()
	check(
		#bobSession.data.creatures == bobBefore + 1 or bobSession.data.cash > bobCashBefore,
		"walking into a runaway catches it"
	)
	check(runawayCount == 1, "and only that one")
	check(bobSession.data.flags.did_runaway == true, "catching it counts for Gotcha!")
	Sim.chat(alice, "/mod off")
	task.wait(0.2)
	for _ = 1, 4 do
		Sim.advance(Drops.runaway.lifetimeSeconds / 4)
		task.wait(0.15)
	end
	_, _, runawayCount = DropService.counts()
	check(runawayCount == 0, "an uncaught one gets away in the end")

	-- Snack Attack: a giant Snackling over the belt; tapping it together takes it down and pays everyone who helped
	local BossService = Sim.server("Services/BossService")
	local Boss = Sim.shared("Config/Boss")
	Sim.chat(alice, "/mod snackAttack")
	task.wait(0.4)
	Sim.advance(Modifiers.modifiers.snackAttack.drops.firstSeconds + 0.5)
	task.wait(0.4)
	local giant = BossService.current()
	check(giant ~= nil, "Snack Attack: a giant Snackling appears")
	local maxHp = giant:GetAttribute("MaxHP")
	check(maxHp == math.max(Boss.minHp, Boss.hpPerPlayer * 2), `with health for the two players here ({maxHp})`)
	check(giant:GetPivot().Position.Y > Gameplay.belt.surfaceY + 4, "hovering over the belt")
	local clicker = giant:FindFirstChildOfClass("ClickDetector")
	check(clicker ~= nil and clicker.MaxActivationDistance == Boss.reach, "anyone in reach can tap it")
	-- Bob walks right under it; Alice stays far away at her base
	teleport(bob, roblox.Vector3.new(6, 3, 16))
	local bobBeforeBoss = bobSession.data.cash
	local aliceBeforeBoss = aliceSession.data.cash
	Sim.click(alice, clicker)
	check(BossService.hitsBy(alice) == 0, "a tap from out of reach doesn't count")
	for _ = 1, 40 do
		Sim.click(bob, clicker)
	end
	check(
		BossService.hitsBy(bob) <= Boss.burst + 1,
		`taps beyond the rate limit don't count ({BossService.hitsBy(bob)})`
	)
	Sim.chat(alice, "/mod off")
	task.wait(0.2)
	for _ = 1, 4 do
		Sim.advance(Boss.lifetimeSeconds / 4)
		task.wait(0.15)
	end
	check(BossService.current() == nil, "not taken down in time, it flies off")
	check(bobSession.data.cash == bobBeforeBoss, "and nobody is paid")
	-- a small one (/boss 20): Bob taps at the rate the server counts until it goes down
	Sim.chat(alice, "/boss 20")
	task.wait(0.2)
	giant = BossService.current()
	clicker = if giant then giant:FindFirstChildOfClass("ClickDetector") else nil
	check(clicker ~= nil and giant:GetAttribute("MaxHP") == 20, "/boss 20 sends a quick one")
	local rounds = 0
	while BossService.current() ~= nil and rounds < 60 do
		rounds += 1
		Sim.click(bob, clicker)
		task.wait(1 / Boss.hitsPerSecond + 0.01)
	end
	check(BossService.current() == nil, `tapping it takes it down ({rounds} taps)`)
	check(bobSession.data.cash > bobBeforeBoss, "the helper is paid")
	check(aliceSession.data.cash == aliceBeforeBoss, "and the one who never hit it is not")
	check(
		bobSession.data.flags.did_snackAttack == true and bobSession.data.flags.did_snackAttackTop == true,
		"the takedown counts for Giant Slayer and MVP"
	)
	check(aliceSession.data.flags.did_snackAttack == nil, "but not for a player who never hit it")

	-- Northern Lights and Heatwave: their skies, and their mutations only while they run
	for _, id in { "northernLights", "heatwave" } do
		local key = MutationRules.modifierKey(id)
		Sim.chat(alice, `/mod {id}`)
		task.wait(0.1)
		check(BeltService.mutationConditions()[key] == true, `{id} lets its mutation roll`)
		local sky = Modifiers.modifiers[id].lighting
		check(math.abs(Lighting.ClockTime - sky.clockTime) < 1e-3, `{id} changes the sky ({Lighting.ClockTime})`)
		Sim.chat(alice, "/mod off")
		task.wait(0.1)
		check(BeltService.mutationConditions()[key] == nil, `and its mutation goes with it`)
	end

	-- Stealing (with Quick Hands) and tagging --------------------------------------------------------------------------------
	Sim.chat(bob, "/noshield")
	local record = aliceSession.data.creatures[1]
	local podium = PlotService.podium(aliceSession.plot, record.podium)
	teleport(bob, podium.base.Position + roblox.Vector3.new(3, 2, 0))
	Sim.chat(alice, "/mod quickHands")
	task.wait(0.1)
	Sim.fireServer(bob, "StealBegin", aliceSession.plot, record.podium)
	task.wait(0.05)
	Sim.advance(Gameplay.steal.holdSeconds * 0.5) -- half the usual hold
	Sim.fireServer(bob, "StealConfirm", aliceSession.plot, record.podium)
	task.wait(0.1)
	check(bobSession.carry ~= nil, "Quick Hands: a steal takes half the hold time")
	local bobHumanoid = (bob.Character :: any):FindFirstChildOfClass("Humanoid")
	check(
		math.abs(bobHumanoid.WalkSpeed - Gameplay.walkSpeed * Gameplay.steal.carrySpeedMultiplier) < 1e-6,
		`the thief slows down ({bobHumanoid.WalkSpeed})`
	)
	teleport(alice, (bob.Character :: any).HumanoidRootPart.Position + roblox.Vector3.new(4, 0, 0))
	Sim.fireServer(alice, "TagThief", 1002)
	task.wait(0.1)
	check(bobSession.carry == nil, "tagging the thief sends the Snackling home")
	check(#aliceSession.data.creatures == 2, "and the owner keeps it")
	Sim.chat(alice, "/mod off")
	task.wait(0.1)

	-- Redeem codes ------------------------------------------------------------------------------------------------------
	local function lastToast(userId: number): string
		local list = Sim.received(userId, "Notify")
		local last = list[#list]
		return if last then last[1].text else ""
	end
	local cash = bobSession.data.cash
	Sim.fireServer(bob, "RedeemCode", " welcome ")
	task.wait(0.1)
	check(bobSession.data.cash > cash, "a code pays (typed in lower case, with spaces)")
	cash = bobSession.data.cash
	Sim.fireServer(bob, "RedeemCode", "WELCOME")
	task.wait(0.1)
	check(bobSession.data.cash == cash, "but only once per account")
	check(string.find(lastToast(1002), "already", 1, true) ~= nil, `and says so ({lastToast(1002)})`)
	Sim.fireServer(bob, "RedeemCode", "NOTACODE")
	task.wait(0.1)
	check(string.find(lastToast(1002), "exist", 1, true) ~= nil, "an unknown code is refused")
	-- (Alice: Bob has used up his burst of tries; the rate limit allows one more every 5 s.)
	local aliceOwned = #aliceSession.data.creatures
	Sim.fireServer(alice, "RedeemCode", "snacktime")
	task.wait(0.1)
	local newest = aliceSession.data.creatures[#aliceSession.data.creatures]
	check(
		#aliceSession.data.creatures == aliceOwned + 1 and newest.variant == "golden",
		"a Snackling code puts a Golden Snackling in the base"
	)

	-- Playtime gifts and the Lucky Spin -----------------------------------------------------------------------------------
	local Gifts = Sim.shared("Config/Gifts")
	check(#Sim.received(1001, "StateUpdate") > 0, "gifts: the state carries them")
	Sim.fireServer(alice, "ClaimGift", 1)
	task.wait(0.1)
	check(#aliceSession.data.gifts.claimed == 0, "a gift stays locked before its time")
	Sim.chat(alice, `/playtime {Gifts.ladder[2].minutes}`)
	task.wait(0.1)
	cash = aliceSession.data.cash
	Sim.fireServer(alice, "ClaimGift", 1)
	task.wait(0.1)
	check(aliceSession.data.cash > cash, "the first gift pays once its minutes are played")
	Sim.fireServer(alice, "ClaimGift", 1)
	Sim.fireServer(alice, "ClaimGift", 2)
	task.wait(0.1)
	check(#aliceSession.data.gifts.claimed == 2, "each gift pays once")
	check(aliceSession.data.spin.spins == 1, "the second gift banks a Lucky Spin")

	-- A brand-new player's free spin is ready, then the banked one; then none.
	local spinCash, spinCreatures = aliceSession.data.cash, #aliceSession.data.creatures
	Sim.fireServer(alice, "Spin")
	task.wait(0.1)
	local results = Sim.received(1001, "SpinResult")
	check(#results == 1 and type(results[1][1].index) == "number", "the free spin turns the reel")
	check(
		aliceSession.data.cash > spinCash or #aliceSession.data.creatures > spinCreatures,
		"and pays its prize at once"
	)
	check(aliceSession.data.spin.nextFreeAt > os.time(), "the next free spin waits")
	Sim.fireServer(alice, "Spin")
	task.wait(0.1)
	check(#Sim.received(1001, "SpinResult") == 1, "one spin at a time while the reel runs")

	-- Achievements: reached ones pay once, and the map you're on counts -------------------------------------------------
	task.wait(1.3) -- the achievement check runs every second for players something just happened to
	local flags = aliceSession.data.flags
	check(flags.ach_firstBite == true, "First Bite is paid after the first purchase")
	check(flags.ach_stickyFingers == nil, "Sticky Fingers waits for a steal (Alice never stole)")
	check(bobSession.data.flags.ach_stickyFingers == nil, "nor Bob: his steal was tagged, so it never landed")
	check(flags["map_" .. workspace:GetAttribute("MapTheme")] == true, "the current map is recorded")
	local bobFlags = bobSession.data.flags
	check(
		bobFlags.ach_crateCracker and bobFlags.ach_gotcha and bobFlags.ach_giantSlayer and bobFlags.ach_mvp,
		"Bob's crate, runaway and Snack Attack paid their achievements"
	)
	cash = aliceSession.data.cash
	Sim.server("Services/AchievementService").check(aliceSession)
	check(aliceSession.data.cash == cash, "nothing pays twice")
	Sim.fireServer(alice, "GetAchievements")
	task.wait(0.1)
	local sync = Sim.received(1001, "AchievementSync")
	check(
		#sync == 1 and #sync[1][1] == #Sim.shared("Config/Achievements").list,
		"the Trophies tab gets every achievement"
	)

	-- Locking -------------------------------------------------------------------------------------------------------------
	local lockButton = PlotService.refs(aliceSession.plot).lockButton
	Sim.moveCharacter(alice, lockButton.Position + roblox.Vector3.new(0, 3, 0))
	Sim.fireServer(alice, "LockBase")
	task.wait(0.1)
	check(aliceSession.lock.lockedUntil > workspace:GetServerTimeNow(), "the base locks")

	-- Map themes ----------------------------------------------------------------------------------------------------------
	local before = workspace:GetAttribute("MapTheme")
	local target = if before == "candy" then "winter" else "candy"
	Sim.chat(alice, `/map {target}`)
	task.wait(0.2)
	check(workspace:GetAttribute("MapTheme") == target, `/map switches the map to {target}`)
	check(
		(workspace.Map.Scenery :: any):GetAttribute("MapTheme") == MapThemes.themes[target].displayName,
		"the scenery was rebuilt"
	)

	Sim.chat(alice, "/map vote")
	task.wait(0.1)
	local candidates = string.split(workspace:GetAttribute("MapVoteCandidates") :: string, ",")
	check(#candidates == MapThemes.rotation.candidates, "a vote offers the configured number of maps")
	Sim.fireServer(alice, "VoteMap", candidates[2])
	Sim.fireServer(bob, "VoteMap", candidates[2])
	Sim.fireServer(bob, "VoteMap", "notAMap")
	task.wait(0.1)
	check(workspace:GetAttribute("MapVoteCounts") == (if #candidates == 3 then "0,2,0" else "0,2"), "votes are counted")
	Sim.advance(30)
	task.wait(1.2)
	check(workspace:GetAttribute("MapTheme") == candidates[2], `the most voted map wins ({candidates[2]})`)
	check(workspace:GetAttribute("MapVoteEndsAt") == 0, "the vote is over")

	-- Seasonal events: `/event` switches a theme on (decorations, lighting, its weather), its Snacklings and mutation
	-- can spawn, and `/event off` takes it all away again ------------------------------------------------------------
	local Seasons = Sim.shared("Config/Seasons")
	local mapNow = workspace:GetAttribute("MapTheme")
	-- The seasonal decorations: how many parts, how many could get in anyone's way, and how many of each name.
	local function decorCounts(): (number, number, { [string]: number })
		local decor = workspace:FindFirstChild("SeasonDecor")
		local parts, inTheWay = 0, 0
		local names: { [string]: number } = {}
		if decor then
			for _, descendant in decor:GetDescendants() do
				if descendant:IsA("BasePart") then
					parts += 1
					names[descendant.Name] = (names[descendant.Name] or 0) + 1
					if
						descendant.CanCollide
						or descendant.CanTouch
						or descendant.CanQuery
						or not descendant.Anchored
					then
						inTheWay += 1
					end
				end
			end
		end
		return parts, inTheWay, names
	end
	Sim.chat(alice, "/event Winter2026 5")
	task.wait(1.2)
	check(workspace:GetAttribute("SeasonTheme") == "winter", "/event Winter2026 switches the winter theme on")
	local decorParts, inTheWay, byName = decorCounts()
	-- 24 presents by the bases + 6 at the belt, 6 trees, 4 snowmen, 8 snowflakes, 16 drifts, 64 bulbs: 380 parts
	-- (tests/SeasonRules.spec.luau pins the same layout)
	check(decorParts == 380, `the winter decorations are built ({decorParts} parts)`)
	check(
		byName.Present == 30 and byName.Tier == 24 and byName.Snowball == 12 and byName.Snowdrift == 16,
		"presents, trees, snowmen and drifts, each built from the parts the budget counts"
	)
	check(inTheWay == 0, "every decoration is anchored and never collides, touches or blocks a raycast")
	local winterLighting = Seasons.themes.winter.lighting
	check(math.abs(Lighting.ClockTime - winterLighting.clockTime) < 1e-3, "the winter mood lights the map")
	Sim.chat(alice, "/spawn peppermint_puffin festive")
	task.wait(0.1)
	local festive = lastBeltItem("peppermint_puffin")
	check(festive ~= nil and festive.variant == "festive", "a Festive Peppermint Puffin rides the belt")
	check(BeltService.mutationConditions().Winter2026 == true, "Festive Snacklings can roll while the event runs")
	Sim.chat(alice, "/event off")
	task.wait(1.2)
	check(workspace:GetAttribute("SeasonTheme") == "", "/event off ends the theme")
	check(workspace:FindFirstChild("SeasonDecor") == nil, "and takes the decorations away")
	check(BeltService.mutationConditions().Winter2026 == nil, "and the Festive mutation with it")
	local mapSky = MapThemes.themes[mapNow].lighting
	check(math.abs(Lighting.ClockTime - mapSky.clockTime) < 1e-3, "the map's own sky comes back")

	Sim.chat(alice, "/event Valentine2027 5")
	task.wait(1.2)
	check(workspace:GetAttribute("SeasonTheme") == "valentine", "/event Valentine2027 switches the valentine theme on")
	decorParts, inTheWay, byName = decorCounts()
	-- 16 rose pots by the bases + 6 at the belt, 64 bulbs, 6 lamps, 14 heart balloons, 4 giant hearts: 280 parts
	-- (tests/SeasonRules.spec.luau pins the same layout)
	check(decorParts == 280, `the valentine decorations are built ({decorParts} parts)`)
	check(
		byName.RosePot == 22
			and byName.Rose == 66
			and byName.HeartBalloon == 42
			and byName.GiantHeart == 12
			and byName.ArrowShaft == 4,
		"roses, heart balloons and giant hearts, each built from the parts the budget counts"
	)
	check(inTheWay == 0, "and none of them gets in anyone's way")
	local valentineLighting = Seasons.themes.valentine.lighting
	check(math.abs(Lighting.ClockTime - valentineLighting.clockTime) < 1e-3, "the rosy mood lights the map")
	Sim.chat(alice, "/spawn rose_petal_pegasus sweetheart")
	task.wait(0.1)
	local sweetheart = lastBeltItem("rose_petal_pegasus")
	check(sweetheart ~= nil and sweetheart.variant == "sweetheart", "a Sweetheart Rose Petal Pegasus rides the belt")
	check(BeltService.mutationConditions().Valentine2027 == true, "Sweetheart Snacklings can roll while it runs")
	Sim.chat(alice, "/event off")
	task.wait(1.2)
	check(workspace:FindFirstChild("SeasonDecor") == nil, "/event off takes the hearts and roses away")
	check(BeltService.mutationConditions().Valentine2027 == nil, "and the Sweetheart mutation with them")

	Sim.chat(alice, "/event Easter2027 5")
	task.wait(1.2)
	check(workspace:GetAttribute("SeasonTheme") == "spring", "/event Easter2027 switches the spring theme on")
	decorParts, inTheWay, byName = decorCounts()
	-- 16 painted eggs by the bases + 6 at the belt, 64 bulbs, 6 lamps, 6 blossom trees, 16 butterflies, 4 chocolate
	-- bunnies: 330 parts (tests/SeasonRules.spec.luau pins the same layout)
	check(decorParts == 330, `the spring decorations are built ({decorParts} parts)`)
	check(
		byName.EasterEgg == 22
			and byName.EggBand == 44
			and byName.EggDot == 44
			and byName.BunnyBody == 4
			and byName.BunnyEar == 8
			and byName.Blossom == 24
			and byName.ButterflyWing == 32,
		"eggs, chocolate bunnies, blossom trees and butterflies, each built from the parts the budget counts"
	)
	check(inTheWay == 0, "and none of them gets in anyone's way")
	local springLighting = Seasons.themes.spring.lighting
	check(math.abs(Lighting.ClockTime - springLighting.clockTime) < 1e-3, "a bright spring morning lights the map")
	Sim.chat(alice, "/spawn jelly_bean_jackalope pastel")
	task.wait(0.1)
	local pastel = lastBeltItem("jelly_bean_jackalope")
	check(pastel ~= nil and pastel.variant == "pastel", "a Pastel Jelly Bean Jackalope rides the belt")
	check(BeltService.mutationConditions().Easter2027 == true, "Pastel Snacklings can roll while it runs")
	Sim.chat(alice, "/event off")
	task.wait(1.2)
	check(workspace:FindFirstChild("SeasonDecor") == nil, "/event off takes the eggs and bunnies away")
	check(BeltService.mutationConditions().Easter2027 == nil, "and the Pastel mutation with them")

	Sim.chat(alice, "/event Harvest2026 5")
	task.wait(1.2)
	check(workspace:GetAttribute("SeasonTheme") == "harvest", "/event Harvest2026 switches the harvest theme on")
	decorParts, inTheWay, byName = decorCounts()
	-- 16 plain pumpkins and 16 hay bales by the bases, 6 cornucopias at the belt, 48 bulbs, 6 lanterns, 6 scarecrows,
	-- 4 giant corn stalks: 386 parts (tests/SeasonRules.spec.luau pins the same layout)
	check(decorParts == 386, `the harvest decorations are built ({decorParts} parts)`)
	check(
		byName.Pumpkin == 16
			and byName.PumpkinLeaf == 16
			and byName.HayBale == 16
			and byName.Twine == 32
			and byName.SackHead == 6
			and byName.Smile == 12
			and byName.Wicker == 18
			and byName.Produce == 24
			and byName.CornStalk == 4
			and byName.CornLeaf == 16,
		"pumpkins, hay bales, scarecrows, cornucopias and corn stalks, each built from the parts the budget counts"
	)
	check(byName.Eye == nil and byName.Mouth == nil, "the harvest pumpkins are plain, not carved")
	check(inTheWay == 0, "and none of them gets in anyone's way")
	local harvestLighting = Seasons.themes.harvest.lighting
	check(math.abs(Lighting.ClockTime - harvestLighting.clockTime) < 1e-3, "a golden late afternoon lights the map")
	Sim.chat(alice, "/spawn cornucopia_kirin maple")
	task.wait(0.1)
	local maple = lastBeltItem("cornucopia_kirin")
	check(maple ~= nil and maple.variant == "maple", "a Maple Cornucopia Kirin rides the belt")
	check(BeltService.mutationConditions().Harvest2026 == true, "Maple Snacklings can roll while it runs")
	Sim.chat(alice, "/event off")
	task.wait(1.2)
	check(workspace:FindFirstChild("SeasonDecor") == nil, "/event off takes the pumpkins and scarecrows away")
	check(BeltService.mutationConditions().Harvest2026 == nil, "and the Maple mutation with them")
	check(math.abs(Lighting.ClockTime - mapSky.clockTime) < 1e-3, "and the map's own sky comes back")

	-- Leaving -------------------------------------------------------------------------------------------------------------
	local owned = #aliceSession.data.creatures
	Sim.removePlayer(alice)
	task.wait(0.3)
	local save = MockProfileStore.saves["Player_1001"]
	check(save ~= nil and #save.creatures == owned, "leaving saves the Snacklings")
	check(Sessions.get(alice) == nil, "the session ends")
end

local passed, problem = pcall(scenario :: () -> ...any)
if not passed then
	print(`  FAIL the scenario stopped: {problem}`)
	table.insert(failures, tostring(problem))
end
finish()
