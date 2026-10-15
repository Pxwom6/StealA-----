--!strict
--[[
	The Studio self-test (README "Studio self-test", DECISIONS.md #57): exercises the game in the real engine during a
	Play test and prints a verdict that fits on one screen. studio/SelfTest.luau starts it from the Command Bar.

	Why a module the paste starts: code run in the Command Bar gets its own copies of the modules it requires, not the
	ones the running game uses, so a Command Bar paste calling MapThemeService.switchTo would drive a copy that never
	started. The paste makes a Script in ServerScriptService instead, which runs like the game's own scripts and calls
	SelfTest.run(script); `require` there returns the live services. Nothing requires this module otherwise: it never
	runs in a live server (and refuses to, outside Studio).

	run(runner):
	  1. Refuses outside Studio, with Studio API access on (the game would save what the test makes happen into real
	     data: a map played on, coins picked up), when the services aren't the running game's, or when a run is going.
	  2. Reads what the server logged before the test (LogService:GetLogHistory: since the server started, or since the
	     last run): an error is a problem, a warning a warning. Then captures LogService.MessageOut for the whole run:
	     every Error and Warning, and other output with "error" in it. An error or a warning logged while a section runs
	     counts against it, as in the offline tests (the game's loops turn the errors they catch into warnings). What
	     Studio logs with API access off that says nothing about the game (Kit.STUDIO_NOISE) is listed apart and never
	     counted; its own lines start with "SELFTEST" and are left out.
	  3. Runs the sections in pcall, timed, each printing `SELFTEST <section>: ok|FAIL <short detail>`: Assets, Maps,
	     Modifiers, Events, Snacklings, Remotes, Players (SelfTest/*.luau). A running modifier is ended first.
	  4. Puts the session back (each section's clean-up steps, in reverse): the first map, modifiers and events ended,
	     drops and test models gone. Checks that it is.
	  5. Prints the summary (at most 12 lines) ending with `SELFTEST DONE: <n> problem(s), <m> warning(s)` and the
	     first problems, and writes the full report to the StringValue ServerStorage.SelfTestReport.

	It never touches a DataStore or a save, never publishes, never teleports. The runner's attributes can change the
	timings (Kit.Options; the offline harness, tools/selfTestOffline.luau, makes them short) and `sections` ("Maps,Events")
	runs only some.
]]

local LogService = game:GetService("LogService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local MapThemeService = require(script.Parent.Services.MapThemeService)
local ModifierService = require(script.Parent.Services.ModifierService)
local SeasonService = require(script.Parent.Services.SeasonService)
local Sessions = require(script.Parent.Services.Sessions)
local Kit = require(script.Kit)

local SelfTest = {}

SelfTest.PREFIX = "SELFTEST"
SelfTest.REPORT_NAME = "SelfTestReport"

local PREFIX = SelfTest.PREFIX
local MAX_MESSAGES = 300 -- logged messages kept for the report
local SUMMARY_PROBLEMS = 3 -- problems listed under the DONE line
local BEFORE = "Before the test"

local SECTIONS: { Kit.Section } = {
	require(script.Assets),
	require(script.Maps),
	require(script.Modifiers),
	require(script.Events),
	require(script.Snacklings),
	require(script.Remotes),
	require(script.Players),
}

SelfTest.DEFAULTS = table.freeze({
	holdSeconds = 2,
	settleSeconds = 0.3,
	assetTimeoutSeconds = 20,
	dropMarginSeconds = 5,
	batch = 16,
})

type Entry = { section: string, text: string }
type LogEntry = { message: string, messageType: Enum.MessageType, timestamp: number }

local running = false
-- The last log entry a run saw, so the next run reads only what came after it.
local lastSeen: { message: string, timestamp: number }? = nil

local function attributeNumber(runner: Instance?, name: string, default: number): number
	local value = if runner then runner:GetAttribute(name) else nil
	if type(value) == "number" and value == value and value >= 0 and value < math.huge then
		return value
	end
	return default
end

local function optionsFrom(runner: Instance?): Kit.Options
	local defaults = SelfTest.DEFAULTS
	local options: Kit.Options = {
		holdSeconds = attributeNumber(runner, "holdSeconds", defaults.holdSeconds),
		settleSeconds = attributeNumber(runner, "settleSeconds", defaults.settleSeconds),
		assetTimeoutSeconds = attributeNumber(runner, "assetTimeoutSeconds", defaults.assetTimeoutSeconds),
		dropMarginSeconds = attributeNumber(runner, "dropMarginSeconds", defaults.dropMarginSeconds),
		batch = attributeNumber(runner, "batch", defaults.batch),
	}
	local only = if runner then runner:GetAttribute("sections") else nil
	if type(only) == "string" and only ~= "" then
		local set: { [string]: boolean } = {}
		for name in string.gmatch(only, "[^,%s]+") do
			set[name] = true
		end
		options.sections = set
	end
	return options
end

-- Whether ProfileStore can reach the real DataStores (Studio API access on): then anything the game saves during
-- the test would land in real data. Reads ProfileStore's own state (no DataStore call).
local function apiAccessOn(): boolean
	local packages = ServerScriptService:FindFirstChild("ServerPackages")
	local module = if packages then packages:FindFirstChild("ProfileStore") else nil
	if module == nil or not module:IsA("ModuleScript") then
		return false
	end
	local ok, store = pcall(require, module)
	return ok and type(store) == "table" and (store :: any).DataStoreState == "Access"
end

-- Whether the services this module sees are the running game's (not fresh copies, as the Command Bar would get).
local function liveServices(): boolean
	if MapThemeService.current() ~= workspace:GetAttribute("MapTheme") then
		return false
	end
	return #Players:GetPlayers() == 0 or #Sessions.all() > 0
end

-- Why the test can't run here, or nil.
local function refusal(): string?
	if not RunService:IsStudio() then
		return "Studio only: it switches maps, modifiers and events for the whole server."
	elseif running then
		return "already running: wait for SELFTEST DONE."
	elseif apiAccessOn() then
		return "Studio API access is on, so the game would save to real data. Game Settings > Security: turn off "
			.. "Enable Studio Access to API Services, then Play and paste studio/SelfTest.luau again."
	elseif not liveServices() then
		return "these are not the running game's services. Start it by pasting studio/SelfTest.luau into the Command "
			.. "Bar on the server view (Test > Toggle Server View) during Play, not by requiring this module."
	end
	return nil
end

local function logHistory(): { LogEntry }
	local ok, entries = pcall(function(): any
		return LogService:GetLogHistory()
	end)
	return if ok and type(entries) == "table" then entries :: { LogEntry } else {}
end

-- What the server logged since the last run (everything, the first time).
local function unseenHistory(): { LogEntry }
	local entries = logHistory()
	local first = 1
	local seen = lastSeen
	if seen then
		for index = #entries, 1, -1 do
			local entry = entries[index]
			if entry.message == seen.message and entry.timestamp == seen.timestamp then
				first = index + 1
				break
			end
		end
	end
	return table.move(entries, first, #entries, 1, {})
end

local function rememberLastSeen()
	local entries = logHistory()
	local last = entries[#entries]
	lastSeen = if last then { message = last.message, timestamp = last.timestamp } else nil
end

local function writeReport(text: string)
	local existing = ServerStorage:FindFirstChild(SelfTest.REPORT_NAME)
	local value: StringValue
	if existing and existing:IsA("StringValue") then
		value = existing
	else
		if existing then
			existing:Destroy()
		end
		value = Instance.new("StringValue")
		value.Name = SelfTest.REPORT_NAME
		value.Parent = ServerStorage
	end
	value.Value = text
end

local function seconds(value: number): string
	return string.format("%.1f s", value)
end

local function runAll(options: Kit.Options)
	local started = os.clock()
	local problems: { Entry } = {}
	local warnings: { Entry } = {}
	local notes: { Entry } = {}
	local messages: { Kit.Message } = {}
	local noise: { Entry } = {}
	local repeats: { [string]: number } = {} -- before the test: how often each message came
	local dropped = 0
	local cleanups: { () -> () } = {}
	local current = BEFORE

	-- One logged message: left out (own lines, noise to its own list), or kept under the section running now.
	local function record(message: string, messageType: Enum.MessageType)
		if string.sub(message, 1, #PREFIX) == PREFIX then
			return
		end
		local kind: Kit.MessageKind? = nil
		if messageType == Enum.MessageType.MessageError then
			kind = "error"
		elseif messageType == Enum.MessageType.MessageWarning then
			kind = "warning"
		elseif string.find(string.lower(message), "error", 1, true) then
			kind = "output"
		end
		if kind == nil then
			return
		end
		local text = Kit.short(message, 300)
		if Kit.isStudioNoise(message) then
			if #noise < MAX_MESSAGES then
				table.insert(noise, { section = current, text = `{kind}: {text}` })
			end
			return
		end
		if current == BEFORE then
			local key = `{kind}|{text}`
			if repeats[key] then
				repeats[key] += 1
				return
			end
			repeats[key] = 1
		end
		if #messages >= MAX_MESSAGES then
			dropped += 1
			return
		end
		table.insert(messages, { text = text, kind = kind, section = current, handled = false })
	end

	for _, entry in unseenHistory() do
		record(entry.message, entry.messageType)
	end
	local connection = LogService.MessageOut:Connect(record)

	local function contextFor(name: string): Kit.Context
		return {
			options = options,
			section = name,
			problem = function(text: string)
				table.insert(problems, { section = name, text = Kit.short(text, 240) })
			end,
			warning = function(text: string)
				table.insert(warnings, { section = name, text = Kit.short(text, 240) })
			end,
			note = function(text: string)
				table.insert(notes, { section = name, text = Kit.short(text, 240) })
			end,
			mark = function(): number
				return #messages
			end,
			take = function(mark: number): { Kit.Message }
				local taken: { Kit.Message } = {}
				for index = mark + 1, #messages do
					local message = messages[index]
					if not message.handled and message.kind ~= "output" then
						message.handled = true
						table.insert(taken, message)
					end
				end
				return taken
			end,
			onCleanup = function(step: () -> ())
				table.insert(cleanups, step)
			end,
			now = function(): number
				return workspace:GetServerTimeNow()
			end,
		}
	end

	-- Whatever was logged under `name` and not taken: errors and warnings are its problems, other output a warning.
	-- Before the test only an error is a problem: the warnings came from playing, not from anything the test did.
	local function settle(name: string)
		local ctx = contextFor(name)
		for _, message in messages do
			if message.section == name and not message.handled then
				message.handled = true
				local count = repeats[`{message.kind}|{message.text}`] or 1
				local text = if count > 1 then `{message.text} (x{count})` else message.text
				if message.kind == "output" then
					ctx.warning(`logged: {text}`)
				elseif message.kind == "warning" and name == BEFORE then
					ctx.warning(`warning: {text}`)
				else
					ctx.problem(`{message.kind}: {text}`)
				end
			end
		end
	end
	settle(BEFORE)

	local startMap = MapThemeService.current()
	local startSeason = SeasonService.currentTheme()
	local startCtx = contextFor("Start")
	current = "Start"
	local runningModifier = ModifierService.current()
	if runningModifier then
		Kit.endModifier()
		startCtx.note(`{runningModifier} was running: ended so every section starts from a quiet server`)
	end
	local chosen: { Kit.Section } = {}
	for _, section in SECTIONS do
		if options.sections == nil or (options.sections :: { [string]: boolean })[section.name] then
			table.insert(chosen, section)
		end
	end
	local length = if #chosen == #SECTIONS then ", about 2 minutes" else ""
	print(`{PREFIX}: started ({#chosen} section(s){length}). The summary ends with "{PREFIX} DONE".`)

	local lines: { string } = {}
	for _, section in chosen do
		current = section.name
		local ctx = contextFor(section.name)
		local before = #problems
		local sectionStarted = os.clock()
		local ok, result = pcall(section.run, ctx)
		local took = seconds(os.clock() - sectionStarted)
		if not ok then
			ctx.problem(`stopped: {Kit.short(tostring(result))}`)
		end
		settle(section.name)
		current = "Between sections"
		local own = #problems - before
		local line
		if own == 0 then
			line = `{PREFIX} {section.name}: ok {result} ({took})`
			print(line)
		else
			local more = if own > 1 then ` (+{own - 1} more)` else ""
			line = `{PREFIX} {section.name}: FAIL {Kit.short(problems[before + 1].text, 110)}{more} ({took})`
			warn(line)
		end
		table.insert(lines, line)
	end

	-- Put the session back, then check it is.
	current = "Cleanup"
	for index = #cleanups, 1, -1 do
		local ok, err = pcall(cleanups[index] :: () -> ...any)
		if not ok then
			table.insert(problems, { section = "Cleanup", text = `a clean-up step failed: {Kit.short(tostring(err))}` })
		end
	end
	local cleanupCtx = contextFor("Cleanup")
	if MapThemeService.current() ~= startMap then
		cleanupCtx.problem(`the map is {MapThemeService.current()}, not {startMap} as before the test`)
	end
	if ModifierService.current() ~= nil then
		cleanupCtx.problem(`{ModifierService.current()} is still running`)
	end
	if SeasonService.currentTheme() ~= startSeason then
		cleanupCtx.problem(`the seasonal theme is {SeasonService.currentTheme()}, not {startSeason} as before`)
	end
	if workspace:FindFirstChild("SelfTestSnacklings") then
		cleanupCtx.problem("the test's Snackling models are still in the workspace")
	end
	task.wait(0.1) -- anything the clean-up logs reaches the capture
	connection:Disconnect()
	settle("Cleanup")
	settle("Between sections")
	settle("Start")
	if dropped > 0 then
		table.insert(warnings, { section = "Log", text = `{dropped} more messages were logged than the report keeps` })
	end

	-- The summary: at most 12 lines, the verdict and the first problems last.
	local total = seconds(os.clock() - started)
	local ignored = if #noise > 0 then `, {#noise} Studio message(s) ignored` else ""
	print(`{PREFIX} ===== summary: {#lines} sections in {total}{ignored}; report: ServerStorage.{SelfTest.REPORT_NAME}`)
	for _, line in lines do
		if string.find(line, ": FAIL ", 1, true) then
			warn(line)
		else
			print(line)
		end
	end
	local done = `{PREFIX} DONE: {#problems} problem(s), {#warnings} warning(s)`
	if #problems > 0 then
		warn(done)
		for index = 1, math.min(SUMMARY_PROBLEMS, #problems) do
			local entry = problems[index]
			warn(`{PREFIX}   {index}. {entry.section}: {Kit.short(entry.text, 140)}`)
		end
	else
		print(done)
		for index = 1, math.min(SUMMARY_PROBLEMS, #warnings) do
			local entry = warnings[index]
			print(`{PREFIX}   warning {index}. {entry.section}: {Kit.short(entry.text, 130)}`)
		end
	end

	-- The full report.
	local names: { string } = {}
	for _, player in Players:GetPlayers() do
		table.insert(names, player.Name)
	end
	local report: { string } = {
		`Steal a Snackling self-test, {os.date("!%Y-%m-%d %H:%M:%S")} UTC, {total}`,
		`Place {game.PlaceId} version {game.PlaceVersion}; map at the start: {startMap}; players: {if #names > 0
			then table.concat(names, ", ")
			else "none"}`,
		"",
	}
	for _, line in lines do
		table.insert(report, line)
	end
	table.insert(report, done)
	local function block(title: string, list: { Entry })
		if #list == 0 then
			return
		end
		table.insert(report, "")
		table.insert(report, `{title} ({#list}):`)
		for _, entry in list do
			table.insert(report, `  [{entry.section}] {entry.text}`)
		end
	end
	block("Problems", problems)
	block("Warnings", warnings)
	block("Notes", notes)
	if #messages > 0 then
		table.insert(report, "")
		table.insert(report, `Logged by the server ({#messages}: errors, warnings and output with "error"):`)
		for _, message in messages do
			table.insert(report, `  [{message.section}] {message.kind}: {message.text}`)
		end
	end
	block("Studio messages left out (expected with Studio API access off; not counted)", noise)
	writeReport(table.concat(report, "\n"))
end

-- Runs the whole self-test (see the header). `runner` is the Script studio/SelfTest.luau made: its attributes may
-- change the timings. Never throws.
function SelfTest.run(runner: Instance?)
	if runner then
		runner:SetAttribute("Started", true) -- the paste watches for it
	end
	local reason = refusal()
	if reason then
		print(`{PREFIX}: {reason}`)
		return
	end
	running = true
	local ok, err = pcall(runAll :: (Kit.Options) -> ...any, optionsFrom(runner))
	rememberLastSeen()
	running = false
	if not ok then
		warn(`{PREFIX} DONE: the self-test itself failed: {Kit.short(tostring(err), 300)}`)
	end
end

return SelfTest
