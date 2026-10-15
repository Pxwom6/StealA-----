--!strict
--[[
	The Studio self-test, offline (CI runs it):
	    lune run tools/selfTestOffline.luau

	Runs studio/SelfTest.luau and src/server/SelfTest end to end against the offline server (tools/worldsim/Sim), and
	studio/SelfTestClient.luau against a stand-in HUD, so CI proves both run without errors and say what they should.
	Modelled on tools/syncTest.luau: the paste is loaded where the Command Bar would run it, with the offline server as
	`game`, and the Script it makes runs as Roblox runs one parented into ServerScriptService (Sim.runScript).

	Stand-ins: ContentProvider answers each asset request (Success, or Failure for the ids a run breaks; one id is
	misreported by the callback and right in GetAssetFetchStatus); LogService is the Sim's (what the game prints and
	warns, and what a run logs on purpose). A background clock moves server time 5x faster than real time, so a drop
	modifier drops within seconds; the runner's attributes make the other waits short.

	  1. Where the paste must refuse (the edit view, the client view, outside Studio, no module, already running, Studio
	     API access on, a Command Bar that can't set a Script's Source, a Script Studio never runs): one line each,
	     nothing starts and nothing is left behind.
	  2. A clean run with one player: every section ok, "SELFTEST DONE: 0 problem(s), 0 warning(s)" although Studio's
	     API-access-off messages were logged before and during it (left out, and counted apart), a summary of at most
	     12 lines, the report in ServerStorage.SelfTestReport, and the session back as it was.
	  3. A run with a fault in every section, and an error and a repeated warning logged before it: each is found under
	     its section, by its key; the log is read only since the last run; the summary lists the first three; the
	     session still comes back. Then only some sections, nothing loading at all, and PolicyService not answering.
	  4. The HUD companion on a 667x375 phone HUD laid out by ScreenLayout itself: all ok; then with the lock moved and
	     a label shrunk: both found.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")
local Sim = require("./worldsim/Sim")
local MockProfileStore = require("./worldsim/MockProfileStore")

Sim.mock("ServerPackages/ProfileStore.lua", MockProfileStore)

local SERVER_PASTE = "studio/SelfTest.luau"
local CLIENT_PASTE = "studio/SelfTestClient.luau"
local RUNNER_NAME = "SnacklingSelfTest"
local CLOCK_SPEED = 5 -- server seconds per real second
local FAST: { [string]: any } = {
	holdSeconds = 0.05,
	settleSeconds = 0.05,
	assetTimeoutSeconds = 3,
	dropMarginSeconds = 3,
	batch = 40,
}
local SECTIONS = { "Assets", "Maps", "Modifiers", "Events", "Snacklings", "Remotes", "Players" }
local Status = roblox.Enum.AssetFetchStatus

local failures: { string } = {}
local function check(ok: boolean, message: string)
	print(`  {if ok then "ok  " else "FAIL"} {message}`)
	if not ok then
		table.insert(failures, message)
	end
end

local function finish()
	if #failures > 0 then
		print(`self-test offline: {#failures} problem(s)`)
		process.exit(1)
	end
	print("self-test offline: no problems")
	process.exit(0)
end

local function joinArgs(...: any): string
	local parts = {}
	for i = 1, select("#", ...) do
		table.insert(parts, tostring((select(i, ...))))
	end
	return table.concat(parts, " ")
end

-- Every line the self-test wrote (it starts each with SELFTEST), in order.
local output: { string } = {}
Sim.logOut:Connect(function(text: string, _messageType: any)
	if string.sub(text, 1, 8) == "SELFTEST" then
		table.insert(output, text)
	end
end)

local function has(lines: { string }, text: string): boolean
	for _, entry in lines do
		if string.find(entry, text, 1, true) then
			return true
		end
	end
	return false
end

local function indexOf(lines: { string }, text: string): number?
	for index, entry in lines do
		if string.find(entry, text, 1, true) then
			return index
		end
	end
	return nil
end

-- ContentProvider ------------------------------------------------------------------------------------------------------

local broken: { [string]: boolean } = {} -- requests that fail
local allBroken = false -- every request fails (nothing can be fetched from here)
local misreported: { [string]: boolean } = {} -- the callback says Failure, GetAssetFetchStatus says Success
local requested: { [string]: boolean } = {}

local function contentOf(real: any): string
	for _, property in { "SoundId", "Texture", "MeshId", "AnimationId" } do
		local ok, value = pcall(function(): any
			return real[property]
		end)
		if ok and type(value) == "string" and value ~= "" then
			return value
		end
	end
	return ""
end

local ContentProvider: any = {}
function ContentProvider.PreloadAsync(_self: any, list: { any }, callback: ((string, any) -> ())?)
	for _, item in list do
		local id = contentOf(Sim.real(item))
		requested[id] = true
		task.wait(0.01)
		if callback then
			callback(id, if allBroken or broken[id] or misreported[id] then Status.Failure else Status.Success)
		end
	end
end
function ContentProvider.GetAssetFetchStatus(_self: any, id: string): any
	return if allBroken or broken[id] then Status.Failure else Status.Success
end
Sim.setService("ContentProvider", ContentProvider)

-- The offline server, with one player ------------------------------------------------------------------------------

local booted, bootError = pcall(function()
	Sim.require("ServerScriptService", "Server")
end)
if not booted then
	print(`the server failed to boot: {bootError}`)
	process.exit(1)
end

local Sessions = Sim.server("Services/Sessions")
local PlotService = Sim.server("Services/PlotService")
local MapThemeService = Sim.server("Services/MapThemeService")
local ModifierService = Sim.server("Services/ModifierService")
local SeasonService = Sim.server("Services/SeasonService")
local LiveOpsService = Sim.server("Services/LiveOpsService")
local DropService = Sim.server("Services/DropService")
local BossService = Sim.server("Services/BossService")
local MapBuilder = Sim.server("Services/MapBuilder")
local CreatureVisuals = Sim.shared("CreatureVisuals")
local GameData = Sim.shared("GameData")
local MapThemes = Sim.shared("Config/MapThemes")
local Seasons = Sim.shared("Config/Seasons")
local workspace = Sim.workspace()
local ServerScriptService = Sim.service("ServerScriptService")
local ServerStorage = Sim.service("ServerStorage")
local RunService = Sim.service("RunService")

local player = Sim.addPlayer(1001, "Leo")
task.wait(0.2)
local session = Sessions.get(player)
assert(session, "Leo has no session")
Sim.spawnCharacter(player, PlotService.refs(session.plot).spawnCFrame.Position)
Sim.fireServer(player, "ClientReady")
task.wait(0.3)

-- Server time runs on, faster than real time (drops come on the server clock).
task.spawn(function()
	local last = os.clock()
	while true do
		task.wait(0.02)
		local now = os.clock()
		Sim.now += (now - last) * CLOCK_SPEED
		last = now
	end
end)

-- Pastes studio/SelfTest.luau into the "Command Bar" (with `game` = `gameValue`, default the offline server's), then
-- runs the Script it made, if any, as Roblox would (its attributes from `attributes`, default FAST). Returns the lines
-- the self-test wrote and whether a runner was made.
local function runPaste(gameValue: any?, attributes: { [string]: any }?): ({ string }, boolean)
	local first = #output + 1
	local env = {
		game = gameValue or Sim.game(),
		Instance = Sim.Instance,
		task = task,
		print = function(...: any)
			Sim.log(joinArgs(...), roblox.Enum.MessageType.MessageOutput)
		end,
		warn = function(...: any)
			Sim.log(joinArgs(...), roblox.Enum.MessageType.MessageWarning)
		end,
	}
	luau.load(fs.readFile(SERVER_PASTE), { debugName = "SelfTest.luau", environment = env })()
	local runner = ServerScriptService:FindFirstChild(RUNNER_NAME)
	if runner then
		for key, value in attributes or FAST do
			runner:SetAttribute(key, value)
		end
		Sim.runScript(runner)
	end
	return table.move(output, first, #output, 1, {}), runner ~= nil
end

local function report(): string
	local value = ServerStorage:FindFirstChild("SelfTestReport")
	return if value then value.Value else ""
end

-- The session as a player would find it: map, modifier, seasonal theme, leftovers.
local function sessionState(): string
	local crates, coins, runaways = DropService.counts()
	return table.concat({
		`map {MapThemeService.current()}`,
		`modifier {ModifierService.current() or "none"}`,
		`season {SeasonService.currentTheme() or "none"}`,
		`drops {crates + coins + runaways}`,
		`giant {if BossService.current() then "yes" else "no"}`,
		`test models {if workspace:FindFirstChild("SelfTestSnacklings") then "yes" else "no"}`,
		`runner {if ServerScriptService:FindFirstChild(RUNNER_NAME) then "yes" else "no"}`,
	}, ", ")
end

local function seasonalEventsRunning(): number
	local count = 0
	for eventId in LiveOpsService.activeEventIds() do
		if Seasons.eventThemes[eventId] then
			count += 1
		end
	end
	return count
end

-- 1. Where it must refuse ------------------------------------------------------------------------------------------

local function scenario()
	print("self-test offline:")
	local quiet = sessionState()

	local isRunning = RunService.IsRunning
	RunService.IsRunning = function(): boolean
		return false
	end
	local lines, started = runPaste()
	RunService.IsRunning = isRunning
	check(
		has(lines, "this ran in Studio's edit view") and has(lines, "Toggle Server View") and not started,
		"in the edit view it says to Play and toggle to the server view"
	)

	local isClient = RunService.IsClient
	RunService.IsClient = function(): boolean
		return true
	end
	lines, started = runPaste()
	RunService.IsClient = isClient
	check(
		has(lines, "this ran on the client view") and not started,
		"on the client view it says to toggle to the server view"
	)

	Sim.isStudio = false
	lines, started = runPaste()
	Sim.isStudio = true
	check(has(lines, "Studio only") and not started, "outside Studio it refuses")

	local bare = setmetatable({}, {
		__index = function(_, key: string): any
			if key == "GetService" then
				return function(_self: any, name: string): any
					if name == "ServerScriptService" then
						return {
							FindFirstChild = function(): any
								return nil
							end,
						}
					end
					return Sim.game():GetService(name)
				end
			end
			return Sim.game()[key]
		end,
	})
	lines, started = runPaste(bare)
	check(has(lines, "sync the latest code") and not started, "without the module it says to sync first")

	local busy = Sim.Instance.new("Script")
	busy.Name = RUNNER_NAME
	busy.Parent = ServerScriptService
	local before = #output
	luau.load(fs.readFile(SERVER_PASTE), {
		environment = {
			game = Sim.game(),
			Instance = Sim.Instance,
			print = function(...: any)
				Sim.log(joinArgs(...), roblox.Enum.MessageType.MessageOutput)
			end,
		},
	})()
	busy:Destroy()
	check(has(table.move(output, before + 1, #output, 1, {}), "already running"), "a second paste waits for the first")

	-- (ProfileStore's DataStoreState is "Access" when Studio API access is on; the mock has none, so it is added here)
	local store: any = MockProfileStore
	store.DataStoreState = "Access"
	lines = runPaste()
	store.DataStoreState = nil
	check(has(lines, "Studio API access is on"), "with Studio API access on it refuses")
	check(report() == "", "and writes no report")
	check(sessionState() == quiet, `nothing changed ({sessionState()})`)

	-- A Command Bar that can't set a Script's Source: said in one line, nothing left behind.
	local stubborn = {
		new = function(className: string): any
			local made = Sim.Instance.new(className)
			return setmetatable({}, {
				__index = function(_, key: string): any
					return made[key]
				end,
				__newindex = function(_, key: string, value: any)
					if key ~= "Source" then
						made[key] = value
					end
				end,
			})
		end,
	}
	local source = fs.readFile(SERVER_PASTE)
	before = #output
	luau.load(source, {
		environment = {
			game = Sim.game(),
			Instance = stubborn,
			task = task,
			print = function(...: any)
				Sim.log(joinArgs(...), roblox.Enum.MessageType.MessageOutput)
			end,
		},
	})()
	check(
		has(table.move(output, before + 1, #output, 1, {}), "could not make the test's Script here"),
		"a Command Bar that can't set the Script's Source says so"
	)
	check(ServerScriptService:FindFirstChild(RUNNER_NAME) == nil, "and leaves no Script behind")

	-- A Script Studio never runs: after a moment the paste says so and takes it away.
	local quick = string.gsub(source, "local START_SECONDS = 5", "local START_SECONDS = 0.3")
	before = #output
	luau.load(quick, {
		environment = {
			game = Sim.game(),
			Instance = Sim.Instance,
			task = task,
			print = function(...: any)
				Sim.log(joinArgs(...), roblox.Enum.MessageType.MessageOutput)
			end,
			warn = function(...: any)
				Sim.log(joinArgs(...), roblox.Enum.MessageType.MessageWarning)
			end,
		},
	})()
	task.wait(0.6)
	check(
		has(table.move(output, before + 1, #output, 1, {}), "didn't start within"),
		"a Script Studio never runs is reported"
	)
	check(ServerScriptService:FindFirstChild(RUNNER_NAME) == nil, "and removed")

	-- 2. A clean run ---------------------------------------------------------------------------------------------------

	local startMap = MapThemeService.current()
	-- What Studio logs with API access off is no problem: two such lines before the run, one while a modifier runs.
	local MessageType = roblox.Enum.MessageType
	Sim.log(
		"DataStoreService: StudioAccessToApisNotAllowed: Studio access to APIs is not allowed.",
		MessageType.MessageError
	)
	Sim.log(
		"[PlayerLifecycle] Max Players is 12 but there are only 8 plots: extra players...",
		MessageType.MessageWarning
	)
	local startModifier = ModifierService.startModifier
	ModifierService.startModifier = function(id: string, seconds: number, announce: boolean)
		startModifier(id, seconds, announce)
		if id == "rushHour" then
			Sim.log("[Leaderboards] write failed (cash): StudioAccessToApisNotAllowed", MessageType.MessageWarning)
		end
	end
	local started2 = os.clock()
	lines = runPaste()
	ModifierService.startModifier = startModifier
	print(`  (the clean run took {string.format("%.1f", os.clock() - started2)} s)`)
	for _, name in SECTIONS do
		check(has(lines, `SELFTEST {name}: ok`), `{name} section: ok`)
	end
	check(has(lines, "SELFTEST DONE: 0 problem(s), 0 warning(s)"), "SELFTEST DONE: 0 problem(s), 0 warning(s)")
	check(has(lines, "3 Studio message(s) ignored"), "Studio's API-access-off messages are left out, and counted apart")
	local summary = indexOf(lines, "===== summary")
	check(summary ~= nil and #lines - (summary :: number) + 1 <= 12, "the summary is at most 12 lines")
	local beforeSummary = table.move(lines, 1, (summary or 1) - 1, 1, {})
	for _, name in SECTIONS do
		local count = 0
		for _, entry in beforeSummary do
			if string.find(entry, `SELFTEST {name}: `, 1, true) then
				count += 1
			end
		end
		check(count == 1, `{name} printed one line while it ran ({count})`)
	end
	local text = report()
	check(string.find(text, "DONE: 0 problem(s)", 1, true) ~= nil, "the full report is in ServerStorage.SelfTestReport")
	check(
		requested["rbxassetid://15675032796"] == true and requested["rbxassetid://1842203609"] == true,
		"Config/Sounds' effects and music were requested"
	)
	check(
		requested["rbxasset://textures/particles/sparkles_main.dds"] == true,
		"and the particle textures the game built"
	)
	check(MapThemeService.current() == startMap, `back on the first map ({MapThemeService.current()})`)
	check(sessionState() == quiet, `the session is as it was ({sessionState()})`)
	check(seasonalEventsRunning() == 0, "no seasonal event left running")
	for _, line in lines do
		if string.find(line, "FAIL", 1, true) or string.find(line, "DONE", 1, true) then
			print(`    {line}`)
		end
	end

	-- 3. A fault in every section ----------------------------------------------------------------------------------------

	broken["rbxassetid://1848232312"] = true -- Sounds.music.halloween
	misreported["rbxassetid://15675032796"] = true -- the click: misreported by the callback only
	local ground = workspace.Map.Ground
	local decal = Sim.Instance.new("Decal")
	decal.Texture = "rbxassetid://999"
	decal.Parent = ground
	broken["rbxassetid://999"] = true

	-- What the server logged before this run (and only since the last one): an error, and a warning twice.
	Sim.log("[Boot] the shop failed to start", MessageType.MessageError)
	Sim.log("[Boot] slow start", MessageType.MessageWarning)
	Sim.log("[Boot] slow start", MessageType.MessageWarning)

	local brokenMap = if MapThemes.order[1] ~= startMap then MapThemes.order[1] else MapThemes.order[2]
	local restyle = MapBuilder.restyle
	MapBuilder.restyle = function(themeId: string, seconds: number): number
		local parts = restyle(themeId, seconds)
		if themeId == brokenMap then
			Sim.log("Workspace.Map.Scenery: a broken landmark", roblox.Enum.MessageType.MessageError)
		end
		return parts
	end
	ModifierService.startModifier = function(id: string, seconds: number, announce: boolean)
		startModifier(id, seconds, announce)
		if id == "goldenHour" then
			Sim.log("[Modifiers] a sparkle went missing", roblox.Enum.MessageType.MessageWarning)
		end
	end
	local startEventNow = LiveOpsService.startEventNow
	LiveOpsService.startEventNow = function(event: any, seconds: number)
		startEventNow(event, seconds)
		local decor = workspace:FindFirstChild("SeasonDecor")
		if event.id == "Winter2026" and decor then
			for _, descendant in decor:GetDescendants() do
				if descendant:IsA("BasePart") then
					descendant.CanCollide = true
					break
				end
			end
		end
	end
	local floater = GameData.catalog.creatureList[2].id
	local build = CreatureVisuals.build
	CreatureVisuals.build = function(def: any, rarity: any, options: any): any
		local model = build(def, rarity, options)
		if def.id == floater and options.mutation == nil then
			for _, part in model:GetDescendants() do
				if part:IsA("BasePart") and part ~= model.PrimaryPart then
					part.CFrame += roblox.Vector3.new(0, 0.5, 0)
				end
			end
		end
		return model
	end
	local remotes = Sim.service("ReplicatedStorage"):FindFirstChild("Remotes")
	local whatsNew = remotes:FindFirstChild("WhatsNew")
	whatsNew.Parent = nil
	session.ready = false

	lines = runPaste()

	session.ready = true
	whatsNew.Parent = remotes
	CreatureVisuals.build = build
	LiveOpsService.startEventNow = startEventNow
	ModifierService.startModifier = startModifier
	MapBuilder.restyle = restyle
	decal:Destroy()
	table.clear(broken)
	table.clear(misreported)

	text = report()
	local expected = {
		{ "Before the test", "error: [Boot] the shop failed to start" },
		{ "Assets", "Sounds.music.halloween.id rbxassetid://1848232312: Failure" },
		{ "Assets", "Workspace.Map.Ground.Decal.Texture rbxassetid://999: Failure" },
		{ "Maps", `{brokenMap}: error: Workspace.Map.Scenery: a broken landmark` },
		{ "Modifiers", "goldenHour: warning: [Modifiers] a sparkle went missing" },
		{ "Events", "Winter2026: 1 decoration parts could get in the way" },
		{ "Snacklings", `{floater}: floats 0.50 studs above its feet` },
		{ "Remotes", "1 remotes are missing: WhatsNew" },
		{ "Players", "Leo's client never asked for its state (ClientReady)" },
	}
	for _, entry in expected do
		check(string.find(text, `[{entry[1]}] {entry[2]}`, 1, true) ~= nil, `{entry[1]} finds: {entry[2]}`)
		if entry[1] ~= "Before the test" then
			check(has(lines, `SELFTEST {entry[1]}: FAIL`), `and its line says FAIL`)
		end
	end
	check(
		string.find(text, "[Before the test] warning: [Boot] slow start (x2)", 1, true) ~= nil,
		"a warning logged before the test is a warning, once with its count"
	)
	check(
		not string.find(text, "Max Players is 12", 1, true),
		"what an earlier run read from the log is not read again"
	)
	check(not has(lines, "ignored"), "so no Studio message is left out this time")
	check(not string.find(text, "15675032796", 1, true), "an asset only the callback misreported is not a problem")
	check(
		has(lines, `SELFTEST DONE: {#expected} problem(s), 1 warning(s)`),
		`SELFTEST DONE: {#expected} problem(s), 1 warning(s): nothing else`
	)
	summary = indexOf(lines, "===== summary")
	check(summary ~= nil and #lines - (summary :: number) + 1 <= 12, "the summary is still at most 12 lines")
	check(has(lines, "SELFTEST   1. Before the test: "), "and lists the first problems under DONE")
	check(MapThemeService.current() == startMap, "back on the first map after a failing run")
	check(sessionState() == quiet, `and the session is as it was ({sessionState()})`)
	for _, line in lines do
		if string.find(line, "DONE", 1, true) or string.find(line, "   ", 1, true) then
			print(`    {line}`)
		end
	end

	-- Some sections only, and two things Studio may do: fetch nothing at all, and not answer PolicyService.
	local function only(sections: string): { [string]: any }
		local attributes = table.clone(FAST)
		attributes.sections = sections
		return attributes
	end
	allBroken = true
	lines = runPaste(nil, only("Assets"))
	allBroken = false
	check(
		has(lines, "SELFTEST Assets: FAIL nothing loaded, not even Roblox's own files"),
		"when nothing loads at all it says so, once"
	)
	check(has(lines, "SELFTEST DONE: 1 problem(s)"), "as one problem")
	check(not has(lines, "SELFTEST Maps:"), "and runs only the sections asked for")
	Sim.policies[1001] = "error"
	lines = runPaste(nil, only("Remotes"))
	Sim.policies[1001] = nil
	check(
		has(lines, "SELFTEST Remotes: ok") and has(lines, "PolicyService failed for 1 (restricted, as expected)"),
		"PolicyService failing in Studio degrades the way the code expects"
	)
	check(sessionState() == quiet, "and nothing is left behind")
end

local passed, problem = pcall(scenario :: () -> ...any)
if not passed then
	print(`  FAIL the server scenario stopped: {problem}`)
	table.insert(failures, tostring(problem))
end

-- 4. The HUD companion ---------------------------------------------------------------------------------------------

local ScreenLayout = Sim.shared("Logic/ScreenLayout")
local TextFit = Sim.shared("Logic/TextFit")

local CLASSES: { [string]: { string } } = {
	ScreenGui = { "ScreenGui", "LayerCollector", "GuiBase2d" },
	Frame = { "Frame", "GuiObject", "GuiBase2d" },
	TextButton = { "TextButton", "GuiButton", "GuiObject", "GuiBase2d" },
	TextLabel = { "TextLabel", "GuiObject", "GuiBase2d" },
	UIScale = { "UIScale", "UIComponent" },
	PlayerGui = { "PlayerGui", "BasePlayerGui" },
	Folder = { "Folder" },
	IntValue = { "IntValue", "ValueBase" },
	Player = { "Player" },
}

-- A stand-in for a GuiObject (or the few other instances the companion reads): Roblox lays nothing out offline.
local function fake(className: string, props: { [string]: any }?): any
	local object: any = { ClassName = className, Name = className, Visible = true, Parent = nil }
	local children: { any } = {}
	local attributes: { [string]: any } = {}
	local given: { [string]: any } = props or {}
	for key, value in given do
		object[key] = value
	end
	function object.IsA(_self: any, name: string): boolean
		return name == "Instance" or table.find(CLASSES[className] or { className }, name) ~= nil
	end
	function object.GetChildren(_self: any): { any }
		return table.clone(children)
	end
	function object.GetDescendants(_self: any): { any }
		local list = {}
		for _, child in children do
			table.insert(list, child)
			for _, descendant in child:GetDescendants() do
				table.insert(list, descendant)
			end
		end
		return list
	end
	function object.FindFirstChild(_self: any, name: string): any
		for _, child in children do
			if child.Name == name then
				return child
			end
		end
		return nil
	end
	function object.FindFirstChildOfClass(_self: any, name: string): any
		for _, child in children do
			if child.ClassName == name then
				return child
			end
		end
		return nil
	end
	function object.GetAttribute(_self: any, name: string): any
		return attributes[name]
	end
	function object.SetAttribute(_self: any, name: string, value: any)
		attributes[name] = value
	end
	function object.Destroy(self: any)
		local parent = self.Parent
		if parent then
			parent:_remove(self)
		end
	end
	function object._add(_self: any, child: any)
		child.Parent = object
		table.insert(children, child)
	end
	function object._remove(_self: any, child: any)
		local index = table.find(children, child)
		if index then
			table.remove(children, index)
		end
	end
	return object
end

local SPEC = { name = "667x375 phone", widthPx = 667, heightPx = 375, touch = true, topBarLeftPx = 150 }
local device = ScreenLayout.device({
	name = "this screen",
	widthPx = SPEC.widthPx,
	heightPx = SPEC.heightPx,
	touch = true,
	insetLeftPx = 0,
	insetRightPx = 0,
	insetBottomPx = 0,
	playerListPx = 0,
	topBarPx = 58,
	topBarLeftPx = 150,
	topBarRightPx = 667,
})
local STATE = { friends = true, event = true, modifier = true, luck = true, tag = true, gadgets = 2 }
local layout = ScreenLayout.layout(device, STATE)
local TEXTS: { [string]: string } = {
	cash = "$1.25M",
	lock = "Lock",
	friends = "👥",
	gear = "⚙",
	shop = "Shop",
	rebirth = "Rebirth",
	rewards = "Rewards",
	snackdex = "Snackdex",
	event = "Halloween ends in 3d 4h",
	modifier = "Golden Hour 4:59",
	luck = "Server Luck x2",
	gadget1 = "🥤",
	gadget2 = "🍌",
	tag = "TAG!",
}

-- A placed element at `r` (UI units) with a label that fills it the way TextScaled would.
local function element(className: string, id: string?, r: any, text: string?): any
	local px = ScreenLayout.toPx(device, r)
	local object = fake(className, {
		Name = id or className,
		AbsolutePosition = roblox.Vector2.new(px.x, px.y),
		AbsoluteSize = roblox.Vector2.new(px.w, px.h),
		Text = if className == "TextButton" then "" else nil, -- (UiKit buttons keep their text in a Label)
	})
	if id then
		object:SetAttribute("HudId", id)
	end
	object:_add(fake("UIScale", { Scale = 1 }))
	if text then
		local w, h = r.w - 16, r.h - 12
		local size = TextFit.fit(text, w, h, false)
		local label = fake("TextLabel", {
			Name = "Label",
			Text = text,
			RichText = false,
			TextScaled = true,
			TextWrapped = false,
			TextFits = true,
			AbsolutePosition = roblox.Vector2.new(px.x + 8 * device.scale, px.y + 6 * device.scale),
			AbsoluteSize = roblox.Vector2.new(w * device.scale, h * device.scale),
			TextBounds = roblox.Vector2.new(
				TextFit.width(text, size) * device.scale,
				size * TextFit.LINE_HEIGHT * device.scale
			),
		})
		object:_add(label)
	end
	return object
end

local function clientHud(): (any, { [string]: any })
	local hud = fake("ScreenGui", {
		Name = "Hud",
		Enabled = true,
		AbsolutePosition = roblox.Vector2.zero,
		AbsoluteSize = roblox.Vector2.new(SPEC.widthPx, SPEC.heightPx),
	})
	hud:_add(fake("UIScale", { Scale = device.scale }))
	local byId: { [string]: any } = {}
	for _, id in { "cash", "lock", "friends", "gear", "shop", "rebirth", "rewards", "snackdex", "gadget1", "gadget2" } do
		local object = element("Frame", id, layout.byId[id], TEXTS[id])
		hud:_add(object)
		byId[id] = object
	end
	local status = fake("Frame", { Name = "Status" })
	hud:_add(status)
	for _, id in { "event", "modifier", "luck" } do
		local object = element("Frame", id, layout.byId[id], TEXTS[id])
		status:_add(object)
		byId[id] = object
	end
	local area = element("Frame", "actionArea", ScreenLayout.actionArea(device), nil)
	hud:_add(area)
	local tag = element("TextButton", nil, layout.byId.tag, TEXTS.tag)
	tag.Name = "TagButton"
	area:_add(tag)
	byId.tag = tag
	return hud, byId
end

local function runClient(hud: any): { string }
	local lines: { string } = {}
	local function capture(...: any)
		table.insert(lines, joinArgs(...))
	end
	local playerGui = fake("PlayerGui", { Name = "PlayerGui" })
	playerGui:_add(hud)
	local stats = fake("Folder", { Name = "leaderstats" })
	stats:_add(fake("IntValue", { Name = "Cash" }))
	stats:_add(fake("IntValue", { Name = "Steals" }))
	local localPlayer = fake("Player", { Name = "Leo" })
	localPlayer:_add(playerGui)
	localPlayer:_add(stats)
	local markers = { ScreenLayout = { marker = "ScreenLayout" }, TextFit = { marker = "TextFit" } }
	local logic = { ScreenLayout = markers.ScreenLayout, TextFit = markers.TextFit }
	function logic.FindFirstChild(_self: any, name: string): any
		return (markers :: any)[name]
	end
	local shared = { Logic = logic }
	function shared.FindFirstChild(_self: any, name: string): any
		return if name == "Logic" then logic else nil
	end
	local services: { [string]: any } = {
		GuiService = {
			TopbarInset = roblox.Rect.new(150, 0, SPEC.widthPx, 58),
			GetGuiInset = function(): (any, any)
				return roblox.Vector2.new(0, 58), roblox.Vector2.zero
			end,
		},
		Players = { LocalPlayer = localPlayer },
		ReplicatedStorage = {
			Shared = shared,
			FindFirstChild = function(_self: any, name: string): any
				return if name == "Shared" then shared else nil
			end,
		},
		RunService = {
			IsRunning = function(): boolean
				return true
			end,
			IsClient = function(): boolean
				return true
			end,
		},
		StarterGui = {
			GetCoreGuiEnabled = function(): boolean
				return true
			end,
		},
		UserInputService = { TouchEnabled = true, KeyboardEnabled = false },
	}
	local env = {
		game = {
			GetService = function(_self: any, name: string): any
				return services[name]
			end,
		},
		workspace = { CurrentCamera = { ViewportSize = roblox.Vector2.new(SPEC.widthPx, SPEC.heightPx) } },
		Instance = {
			new = function(className: string): any
				-- The text probe: its TextBounds in pixels, like Roblox's with a UIScale on the screen.
				local probe = fake(className, { TextSize = 14 })
				return setmetatable({}, {
					__index = function(_, key: string): any
						if key == "TextBounds" then
							return roblox.Vector2.new(20, probe.TextSize * TextFit.LINE_HEIGHT * device.scale)
						elseif key == "Destroy" then
							return function()
								if probe.Parent then
									probe.Parent:_remove(probe)
								end
							end
						end
						return probe[key]
					end,
					__newindex = function(_, key: string, value: any)
						if key == "Parent" then
							value:_add(probe)
						else
							probe[key] = value
						end
					end,
				})
			end,
		},
		Vector2 = roblox.Vector2,
		UDim2 = roblox.UDim2,
		Enum = roblox.Enum,
		task = task,
		print = capture,
		warn = capture,
		require = function(target: any): any
			if target == markers.ScreenLayout then
				return ScreenLayout
			elseif target == markers.TextFit then
				return TextFit
			end
			error("the HUD companion should only require ScreenLayout and TextFit")
		end,
	}
	luau.load(fs.readFile(CLIENT_PASTE), { debugName = "SelfTestClient.luau", environment = env })()
	return lines
end

print("self-test offline (HUD companion):")
local clientOk, clientError = pcall(function()
	local hud = clientHud()
	local lines = runClient(hud)
	check(has(lines, "SELFTEST client: 667x375 px, UI scale 0.85, touch yes"), "it describes the screen")
	check(
		has(lines, "Placement: ok 15 elements where ScreenLayout puts them"),
		"every element is where the layout says"
	)
	check(has(lines, "Layout: ok"), "nothing overlaps, is off screen or in the play zone")
	check(has(lines, "Text: ok 14 labels"), "every label reads")
	check(has(lines, "SELFTEST client DONE: 0 problem(s), 0 warning(s)"), "SELFTEST client DONE: 0 problem(s)")
	for _, line in lines do
		print(`    {line}`)
	end

	local moved, byId = clientHud()
	local lock = byId.lock
	lock.AbsolutePosition += roblox.Vector2.new(20, 0)
	local label = byId.shop:FindFirstChild("Label")
	label.TextBounds = roblox.Vector2.new(20, 6)
	lines = runClient(moved)
	check(has(lines, "Placement: FAIL lock is 20 px off"), "a frame 20 px from its place is found")
	check(has(lines, "Text: FAIL") and has(lines, "is tiny"), "and a tiny label")
	check(has(lines, "SELFTEST client DONE: "), "with a verdict at the end")
	for _, line in lines do
		if string.find(line, "FAIL", 1, true) or string.find(line, "DONE", 1, true) then
			print(`    {line}`)
		end
	end
end)
if not clientOk then
	print(`  FAIL the HUD companion scenario stopped: {clientError}`)
	table.insert(failures, tostring(clientError))
end

finish()
