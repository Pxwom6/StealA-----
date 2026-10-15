--!strict
--[[
	The review round 2 server fixes, offline (CI runs it after the pre-launch test):
	    lune run tools/worldsim/review2.luau

	Boots the whole server like tools/worldsim/prelaunch.luau, with the clock virtual (Sim.virtualClock) in mid-October
	2026, random modifiers and the map rotation off. Then it plays each fixed finding of the second review (DECISIONS.md
	"Review round 2 fixes") through the real remotes and chat commands:

	  * a drop modifier started again while it runs plans its drops again for the new length (Supply Drop, Snack
	    Attack), instead of finishing the old five minutes' schedule and going quiet
	  * a private server's owner goes through the maps no faster than the rotation: a map switch every 20 minutes,
	    a map counted as played on after 3 minutes on it (so switching every minute for 23 minutes earns no map
	    achievement), a map's signature mutation rolling only for its turn's 20 minutes even with the rotation off;
	    and the random schedule's modifiers run to their end (an owner stops or replaces only their own)
	  * a Snack Attack giant's health counts only the players playing: not idle ones, nor new players still in the
	    first-time tutorial (who walk about but can't be expected to help)

	It runs as a live server (not Studio): Ada is an admin (Config/LiveOps.adminUserIds), and the server is Owen's
	private server. It fails on any error, any unexpected warning, or any check below.
]]

local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")
local Sim = require("./Sim")
local MockProfileStore = require("./MockProfileStore")

local OCTOBER_15_2026 = 1792023721

local ADA, OWEN, GUS = 8001, 8002, 8003
local MAX, ZOE, NED, IVY = 8004, 8005, 8006, 8007

Sim.mock("ServerPackages/ProfileStore.lua", MockProfileStore)
Sim.isStudio = false -- a live server: only admins and the private server's owner may host
Sim.virtualClock = true
Sim.now = OCTOBER_15_2026
Sim.shared("Config/Modifiers").schedule.enabled = false -- only /mod (and the scenarios) start one
Sim.shared("Config/MapThemes").rotation.enabled = false
Sim.shared("Config/LiveOps").adminUserIds = { ADA }
Sim.gameProperties.PrivateServerId = "private-review2"
Sim.gameProperties.PrivateServerOwnerId = OWEN

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
		print(`review 2 test: {#failures} problem(s)`)
		process.exit(1)
	end
	print("review 2 test: no problems")
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
local Modifiers = Sim.shared("Config/Modifiers")
local DropRules = Sim.shared("Logic/DropRules")

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

-- Lets `seconds` of server time pass in one-second steps; `each` runs after every step.
local function run(seconds: number, each: (() -> ())?)
	for _ = 1, math.ceil(seconds) do
		Sim.advance(1)
		task.wait(0.03)
		if each then
			each()
		end
	end
end

-- A drop modifier started again while it runs (an admin's "All servers" Supply Drop reaching a server whose schedule
-- had just rolled one) plans its drops again for the new length: before, the HUD counted down 30 minutes while the
-- crates stopped with the first five.
local function dropRestart(ada: any)
	print("A drop modifier started again:")
	local DropService = Sim.server("Services/DropService")
	local BossService = Sim.server("Services/BossService")
	local seen: { [any]: boolean } = {}
	local function count(): number
		local n = 0
		for _ in seen do
			n += 1
		end
		return n
	end
	local function watchCrates()
		for id in DropService.crateModels() do
			seen[id] = true
		end
	end
	chat(ada, "/mod supplyDrop 5")
	run(60, watchCrates)
	check(count() == 1, `Supply Drop: one crate in its first minute ({count()})`)
	chat(ada, "/mod supplyDrop 30") -- started again for 30 minutes
	local drops = Modifiers.modifiers.supplyDrop.drops
	run(470, watchCrates)
	local planned = #DropRules.times(drops, 470)
	check(
		count() == 1 + planned,
		`it plans its crates again from the restart: {count()} crates (1 + {planned}; the old plan stopped at 4)`
	)
	chat(ada, "/mod off")
	run(100)

	-- Snack Attack: giants keep coming for the new length too
	local giants: { [any]: boolean } = {}
	local function watchGiants()
		local giant = BossService.current()
		if giant then
			giants[giant] = true
		end
	end
	chat(ada, "/mod snackAttack 5")
	run(30, watchGiants)
	chat(ada, "/mod snackAttack 30")
	run(620, watchGiants)
	local seenGiants = 0
	for _ in giants do
		seenGiants += 1
	end
	-- the first giant is still up when it starts again (so the new plan's first is skipped), then one every 100 s:
	-- six or more, where the old plan sent two more and stopped
	check(seenGiants >= 6, `Snack Attack started again for 30 minutes keeps sending giants ({seenGiants})`)
	chat(ada, "/mod off")
	run(80)
end

-- Moves server time on in big steps (nothing here needs the game's loops but the modifier's, which `settle` lets run).
local function jump(seconds: number)
	Sim.advance(seconds)
	task.wait(0.05)
end
local function settle()
	task.wait(1.1) -- ModifierService and MapThemeService check once a (real) second
end

local function toasts(userId: number): { string }
	local list = {}
	for _, args in Sim.received(userId, "Notify") do
		table.insert(list, args[1].text)
	end
	return list
end

-- A private server's owner, with a guest: the maps at the rotation's pace, and the schedule's modifiers left alone.
local function ownerPace()
	print("A private server's owner:")
	local MapThemeService = Sim.server("Services/MapThemeService")
	local ModifierService = Sim.server("Services/ModifierService")
	local AchievementService = Sim.server("Services/AchievementService")
	local BeltService = Sim.server("Services/BeltService")
	local MapThemes = Sim.shared("Config/MapThemes")
	local Theme = Sim.shared("Config/Theme")
	local MutationRules = Sim.shared("Logic/MutationRules")
	local workspace = Sim.workspace()
	local owen = join(OWEN, "Owen")
	local gus = join(GUS, "Gus")
	for _, player in { owen, gus } do
		Sim.fireServer(player, "SkipTutorial")
	end
	task.wait(0.1)
	local o, g = Sessions.get(owen), Sessions.get(gus)

	-- The random schedule's modifier runs to its end: no cutting it short (the next random roll would come sooner),
	-- and no starting a hostable one over it.
	ModifierService.startModifier("quickHands", Modifiers.schedule.durationSeconds, true, "schedule")
	Sim.fireServer(owen, "HostAction", "modStop", "server", {})
	task.wait(0.1)
	check(ModifierService.current() == "quickHands", "the schedule's Quick Hands: the owner can't stop it")
	check(
		toasts(OWEN)[#toasts(OWEN)] == Theme.text.hostRefusedNotYours,
		`and is told why ({toasts(OWEN)[#toasts(OWEN)]})`
	)
	Sim.fireServer(owen, "HostAction", "modStart", "server", { id = "sugarRush", minutes = 5 })
	task.wait(0.1)
	check(ModifierService.current() == "quickHands", "nor end it by starting Sugar Rush over it")
	jump(Modifiers.schedule.durationSeconds + 1)
	settle()
	check(ModifierService.current() == nil, "it ends when its time is up")
	Sim.fireServer(owen, "HostAction", "modStart", "server", { id = "sugarRush", minutes = 5 })
	task.wait(0.1)
	check(
		ModifierService.current() == "sugarRush" and workspace:GetAttribute("ModifierByOwner") == true,
		"then the owner starts Sugar Rush, theirs (ModifierByOwner)"
	)
	Sim.fireServer(owen, "HostAction", "modStop", "server", {})
	task.wait(0.1)
	check(ModifierService.current() == nil, "and may stop it")

	-- Maps: one switch per rotation turn, credit after three minutes on a map
	local first = MapThemeService.current()
	local mapA, mapB = nil, nil
	for _, id in MapThemes.order do
		if id ~= first then
			if mapA == nil then
				mapA = id
			elseif mapB == nil then
				mapB = id
			end
		end
	end
	assert(mapA and mapB, "two other maps")
	AchievementService.check(g)
	Sim.fireServer(owen, "HostAction", "mapRotation", "server", { on = false })
	Sim.fireServer(owen, "HostAction", "mapSwitch", "server", { id = mapA })
	task.wait(0.1)
	check(MapThemeService.current() == mapA, `the owner switches to {mapA}`)
	AchievementService.check(g) -- Gus is seen on it from now
	local keyA = MutationRules.mapKey(mapA)
	check(BeltService.mutationConditions()[keyA] == true, `{mapA}'s signature mutation rolls`)
	jump(61)
	Sim.fireServer(owen, "HostAction", "mapSwitch", "server", { id = mapB })
	task.wait(0.1)
	check(MapThemeService.current() == mapA, "a minute later another switch waits for the rotation's turn")
	check(string.find(toasts(OWEN)[#toasts(OWEN)], "Wait", 1, true) ~= nil, `told so ({toasts(OWEN)[#toasts(OWEN)]})`)
	AchievementService.check(g)
	local flagA = "map_" .. mapA
	check(g.data.flags[flagA] == nil, "a minute on a map doesn't count as playing on it")
	jump(MapThemes.rotation.creditSeconds - 60)
	AchievementService.check(g)
	check(g.data.flags[flagA] == true, "three minutes on it do")

	-- With the rotation off the map stays, but its mutation only rolls for the turn the rotation would give it
	jump(MapThemes.rotation.mapSeconds - MapThemes.rotation.creditSeconds - 30)
	check(BeltService.mutationConditions()[keyA] == true, "nineteen minutes in, it still rolls")
	jump(60)
	check(MapThemeService.current() == mapA, "with the rotation off the map stays")
	check(BeltService.mutationConditions()[keyA] == nil, "but after its 20 minutes its signature mutation stops")
	Sim.fireServer(owen, "HostAction", "mapSwitch", "server", { id = mapB })
	task.wait(0.1)
	check(MapThemeService.current() == mapB, "after the rotation's turn the owner may switch again")
	check(
		BeltService.mutationConditions()[MutationRules.mapKey(mapB)] == true,
		`and {mapB}'s mutation rolls for its turn`
	)

	-- The reviewer's farm: a switch attempt every minute for 23 minutes earns the guest no map achievement
	local maps = 0
	for _ = 1, 23 do
		for _, id in MapThemes.order do
			if id ~= MapThemeService.current() then
				Sim.fireServer(owen, "HostAction", "mapSwitch", "server", { id = id })
				break
			end
		end
		task.wait(0.05)
		jump(61)
		AchievementService.check(g)
		AchievementService.check(o)
	end
	for key in g.data.flags do
		if string.sub(key, 1, 4) == "map_" then
			maps += 1
		end
	end
	check(
		maps <= 4 and g.data.flags.ach_explorer == nil and g.data.flags.ach_globetrotter == nil,
		`switching every minute for 23 minutes: {maps} maps played on, no Explorer or Globetrotter (was all 23)`
	)
	Sim.fireServer(owen, "HostAction", "mapRotation", "server", { on = true })
	task.wait(0.1)
end

-- Snack Attack's health counts the players playing when a giant appears. Before, every player in the server counted:
-- with six idle or tutorial players the two playing faced 720 hits in 75 s, more than they can land.
local function giantHealth(ada: any)
	print("Snack Attack's health:")
	local BossService = Sim.server("Services/BossService")
	local Boss = Sim.shared("Config/Boss")
	local BossRules = Sim.shared("Logic/BossRules")
	local max, zoe, ned = join(MAX, "Max"), join(ZOE, "Zoe"), join(NED, "Ned")
	for _, player in { max, zoe, ned } do
		Sim.fireServer(player, "SkipTutorial")
	end
	local ivy = join(IVY, "Ivy") -- brand new: in the first-time tutorial
	task.wait(0.1)
	check(Sessions.get(ivy).tutorial ~= nil and Sessions.get(ned).tutorial == nil, "Ivy is in the tutorial, Ned isn't")
	-- Max goes under the belt's middle to hit it (the tracker flags the jump, then trusts him again)
	Sim.moveCharacter(max, roblox.Vector3.new(6, 3, 16))
	jump(1.5)
	task.wait(0.4)
	jump(11)
	task.wait(0.4)
	-- walking: three quarters of a stud each second, always on, so every sample the position tracker takes (a few a
	-- real second, many server seconds apart here) sees them move
	local walkers: { any } = {}
	local function walk()
		for _, player in walkers do
			Sim.moveCharacter(player, player.Character.HumanoidRootPart.Position + roblox.Vector3.new(0.75, 0, 0))
		end
	end
	local function giantHp(): number
		local giant = BossService.current()
		return if giant then giant:GetAttribute("MaxHP") else -1
	end
	-- BossService looks at the clock every 0.1 real seconds, and `run` moves a server second every 0.03: on its own it
	-- would plan the giants a few server seconds after the modifier started, or not have put up one due just before a
	-- check. A real-time pause (the server clock stands still) lets it catch up.
	local function catchUp()
		task.wait(0.3)
	end

	-- The first giant: Max, Zoe and Ivy walking, Ned standing idle (as are Ada, Owen and Gus)
	walkers = { max, zoe, ivy }
	walk()
	task.wait(0.4)
	chat(ada, "/mod snackAttack 5")
	catchUp()
	run(Modifiers.modifiers.snackAttack.drops.firstSeconds + 2, walk)
	catchUp()
	check(
		giantHp() == BossRules.maxHp(Boss, 2),
		`the first giant has health for the 2 playing, Max and Zoe ({giantHp()}; it was 7 players' worth, `
			.. `{BossRules.maxHp(Boss, 7)})`
	)

	-- The second: Max stands still but hits the first one, Zoe stops (idle for over a minute when it comes), Ned
	-- walks now and Ivy has finished the tutorial
	walkers = { ned, ivy }
	Sim.fireServer(ivy, "SkipTutorial")
	run(Boss.lifetimeSeconds - 15, walk)
	local first = BossService.current()
	local clicker = if first then first:FindFirstChildWhichIsA("ClickDetector", true) else nil
	for _ = 1, Boss.burst do
		if clicker then
			Sim.click(max, clicker)
		end
	end
	check(BossService.hitsBy(max) > 0, `Max hits the first giant standing still ({BossService.hitsBy(max)} hits)`)
	local secondAt = Modifiers.modifiers.snackAttack.drops.firstSeconds
		+ Modifiers.modifiers.snackAttack.drops.everySeconds
	local elapsed = Modifiers.modifiers.snackAttack.drops.firstSeconds + 2 + Boss.lifetimeSeconds - 15
	run(secondAt - elapsed + 2, walk)
	catchUp()
	check(
		BossService.current() ~= first and giantHp() == BossRules.maxHp(Boss, 3),
		`the second counts Max (his hits), Ned and Ivy, not Zoe ({giantHp()}, {BossRules.maxHp(Boss, 3)})`
	)
	chat(ada, "/mod off")
	run(Boss.lifetimeSeconds + 5)
	for _, player in { max, zoe, ned, ivy } do
		Sim.removePlayer(player)
	end
	task.wait(0.3)
end

local function scenario()
	print("review 2 test:")
	local ada = join(ADA, "Ada")
	Sim.fireServer(ada, "SkipTutorial")
	task.wait(0.1)
	dropRestart(ada)
	ownerPace()
	giantHealth(ada)
	print(`  ({math.floor(Sim.now - OCTOBER_15_2026)} s of server time)`)
end

local passed, problem = pcall(scenario :: () -> ...any)
if not passed then
	print(`  FAIL the scenario stopped: {problem}`)
	table.insert(failures, tostring(problem))
end
finish()
