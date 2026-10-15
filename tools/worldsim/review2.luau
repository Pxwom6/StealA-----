--!strict
--[[
	The review round 2 server fixes, offline (CI runs it after the pre-launch test):
	    lune run tools/worldsim/review2.luau

	Boots the whole server like tools/worldsim/prelaunch.luau, with the clock virtual (Sim.virtualClock) in mid-October
	2026, random modifiers and the map rotation off. Then it plays each fixed finding of the second review (DECISIONS.md
	"Review round 2 fixes") through the real remotes and chat commands:

	  * a drop modifier started again while it runs plans its drops again for the new length (Supply Drop, Snack
	    Attack), instead of finishing the old five minutes' schedule and going quiet

	It fails on any error, any unexpected warning, or any check below.
]]

local process = require("@lune/process")
local task = require("@lune/task")
local Sim = require("./Sim")
local MockProfileStore = require("./MockProfileStore")

local OCTOBER_15_2026 = 1792023721

Sim.mock("ServerPackages/ProfileStore.lua", MockProfileStore)
Sim.virtualClock = true
Sim.now = OCTOBER_15_2026
Sim.shared("Config/Modifiers").schedule.enabled = false -- only /mod (and the scenarios) start one
Sim.shared("Config/MapThemes").rotation.enabled = false

local ADA = 8001

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

local function scenario()
	print("review 2 test:")
	local ada = join(ADA, "Ada")
	Sim.fireServer(ada, "SkipTutorial")
	task.wait(0.1)
	dropRestart(ada)
	print(`  ({math.floor(Sim.now - OCTOBER_15_2026)} s of server time)`)
end

local passed, problem = pcall(scenario :: () -> ...any)
if not passed then
	print(`  FAIL the scenario stopped: {problem}`)
	table.insert(failures, tostring(problem))
end
finish()
