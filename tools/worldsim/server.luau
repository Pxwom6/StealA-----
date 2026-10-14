--!strict
--[[
	The whole server, offline (CI runs it after the world smoke test):
	    lune run tools/worldsim/server.luau

	Boots src/server/init.server.luau in the Roblox stand-in (tools/worldsim/Sim) with ProfileStore replaced by an
	in-memory store, then plays a short session with two fake players through the real remotes and chat commands:
	join, buy from the belt, every server modifier's effect where it applies (belt prices, speed, locks, steals),
	weather (the sky and the mutation it unlocks), a map change and a map vote, a base lock, and leaving with the save
	written. It fails on any error, any
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
	Sim.fireServer(alice, "CrateOpen", crateId)
	task.wait(0.1)
	check(#aliceSession.data.creatures == 2, "nobody else gets it")

	-- Coins rain on the walkways; walking through one collects it
	Sim.chat(alice, "/mod coinRain")
	task.wait(0.4)
	Sim.advance(Modifiers.modifiers.coinRain.drops.firstSeconds + 0.5)
	task.wait(0.4)
	local _, coinCount = DropService.counts()
	check(coinCount == Drops.coins.perWave, `Coin Rain: coins fall ({coinCount})`)
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
