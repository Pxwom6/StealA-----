--!strict
--[[
	Checks studio/SyncFromGitHub.luau (the Studio command-bar script that pulls the code from GitHub) offline:
	    rojo build default.project.json -o build/sync.rbxl
	    lune run tools/syncTest.luau build/sync.rbxl

	GitHub is played by this checkout: the file list and every file come from disk. Three runs, each compared with the
	Rojo build of the same files (class and Source of every instance under the three synced roots):
	  1. a place without any of the game's code (all three roots missing): the sync builds everything;
	  2. a place with an obsolete script and a folder that became a script: the obsolete one is reported and kept, the
	     wrong class is fixed with its children kept;
	  3. the same with REMOVE_STALE on: the result matches the build exactly.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local task = require("@lune/task")

local placePath = process.args[1] or "build/sync.rbxl"
local SCRIPT = "studio/SyncFromGitHub.luau"
local SHA = "0123456789abcdef"
local ROOTS = { "src/shared", "src/server", "src/client" }

local failures: { string } = {}
local function check(ok: boolean, message: string)
	print(`  {if ok then "ok  " else "FAIL"} {message}`)
	if not ok then
		table.insert(failures, message)
	end
end

-- Every file under the synced roots, as GitHub's tree API lists them.
local function listFiles(): { { path: string, type: string } }
	local list: { { path: string, type: string } } = {}
	local function walk(directory: string)
		for _, name in fs.readDir(directory) do
			local path = `{directory}/{name}`
			if fs.isDir(path) then
				walk(path)
			else
				table.insert(list, { path = path, type = "blob" })
			end
		end
	end
	for _, root in ROOTS do
		walk(root)
	end
	table.insert(list, { path = "README.md", type = "blob" }) -- files outside the roots are ignored
	return list
end

type Result = { output: { string }, requests: number, waypoints: number }

-- Runs the sync script against `game` with GitHub served from disk.
local function runSync(game: any, removeStale: boolean): Result
	local tree = listFiles()
	local result: Result = { output = {}, requests = 0, waypoints = 0 }
	local fakeHttp = {
		HttpEnabled = true,
		GetAsync = function(_, url: string): string
			result.requests += 1
			if string.find(url, "/commits/", 1, true) then
				return serde.encode("json", { sha = SHA, commit = { message = "Sync test\n\ndetails" } })
			elseif string.find(url, "/git/trees/", 1, true) then
				return serde.encode("json", { sha = "tree", truncated = false, tree = tree })
			end
			local path = string.match(url, `^https://raw%.githubusercontent%.com/[^/]+/[^/]+/{SHA}/(.+)$`)
			assert(path, `unexpected url {url}`)
			task.wait()
			return fs.readFile(path)
		end,
		JSONDecode = function(_, text: string): any
			return serde.decode("json", text)
		end,
	}
	local fakes: { [string]: any } = {
		HttpService = fakeHttp,
		ChangeHistoryService = {
			SetWaypoint = function()
				result.waypoints += 1
			end,
		},
		ScriptEditorService = {
			UpdateSourceAsync = function()
				error("no script editor offline")
			end,
		},
	}
	local proxy = setmetatable({}, {
		__index = function(_, key: string): any
			if key == "GetService" then
				return function(_, name: string): any
					return fakes[name] or game:GetService(name)
				end
			end
			return game[key]
		end,
	})
	local function capture(prefix: string): (...any) -> ()
		return function(...: any)
			local parts: { string } = {}
			for _, value in { ... } do
				table.insert(parts, tostring(value))
			end
			table.insert(result.output, prefix .. table.concat(parts, " "))
		end
	end
	local source = fs.readFile(SCRIPT)
	if removeStale then
		source = string.gsub(source, "local REMOVE_STALE = false", "local REMOVE_STALE = true")
	end
	local chunk = luau.load(source, {
		debugName = "SyncFromGitHub",
		environment = {
			game = proxy,
			task = task,
			Instance = roblox.Instance,
			print = capture(""),
			warn = capture("WARN "),
		},
	})
	chunk()
	return result
end

-- path -> class (and Source) of everything under the three synced roots.
local function snapshot(game: any): { [string]: string }
	local map: { [string]: string } = {}
	local function walk(instance: any, path: string)
		local entry: string = instance.ClassName
		if instance:IsA("LuaSourceContainer") then
			entry ..= "\n" .. instance.Source
		end
		map[path] = entry
		for _, child in instance:GetChildren() do
			walk(child, `{path}/{child.Name}`)
		end
	end
	for _, root in
		{
			game:GetService("ReplicatedStorage"):FindFirstChild("Shared"),
			game:GetService("ServerScriptService"):FindFirstChild("Server"),
			game:GetService("StarterPlayer").StarterPlayerScripts:FindFirstChild("Client"),
		}
	do
		walk(root, root:GetFullName())
	end
	return map
end

-- Paths that differ from the build: missing, different, or extra.
local function differences(game: any, expected: { [string]: string }): { string }
	local actual = snapshot(game)
	local list: { string } = {}
	for path, entry in expected do
		if actual[path] == nil then
			table.insert(list, `missing {path}`)
		elseif actual[path] ~= entry then
			table.insert(list, `different {path}`)
		end
	end
	for path in actual do
		if expected[path] == nil then
			table.insert(list, `extra {path}`)
		end
	end
	table.sort(list)
	return list
end

local function fresh(): any
	return roblox.deserializePlace(fs.readFile(placePath))
end

local function contains(output: { string }, text: string): boolean
	for _, line in output do
		if string.find(line, text, 1, true) then
			return true
		end
	end
	return false
end

local expected = snapshot(fresh())
local fileCount = #listFiles() - 1

print("studio sync test:")

-- 1. Nothing synced yet.
local empty = fresh()
empty:GetService("ReplicatedStorage").Shared:Destroy()
empty:GetService("ServerScriptService").Server:Destroy()
empty:GetService("StarterPlayer").StarterPlayerScripts.Client:Destroy()
local first = runSync(empty, false)
local diff = differences(empty, expected)
check(#diff == 0, `an empty place gets every script, exactly as Rojo builds it ({#diff} differences)`)
check(first.requests == fileCount + 2, `two API calls and one download per file ({first.requests})`)
check(contains(first.output, `{fileCount} added`), "and reports them as added")
check(first.waypoints == 2, "inside one undo step")

-- 2. A stale script and a wrong class.
local function damaged(): any
	local game = fresh()
	local shared = game:GetService("ReplicatedStorage").Shared
	local obsolete = roblox.Instance.new("ModuleScript")
	obsolete.Name = "Obsolete"
	obsolete.Parent = shared.Logic
	local wrong = roblox.Instance.new("ModuleScript")
	wrong.Name = "Config"
	for _, child in shared.Config:GetChildren() do
		child.Parent = wrong
	end
	shared.Config:Destroy()
	wrong.Parent = shared
	return game
end
local kept = damaged()
local second = runSync(kept, false)
diff = differences(kept, expected)
check(
	#diff == 1 and diff[1] == "extra ReplicatedStorage.Shared/Logic/Obsolete",
	`a script no longer in the repo is kept ({table.concat(diff, ", ")})`
)
check(contains(second.output, "Shared.Logic.Obsolete"), "and named in the Output")
check(contains(second.output, "Shared.Config: ModuleScript -> Folder"), "a wrong class is fixed, children kept")
check(contains(second.output, `{fileCount} already up to date`), "unchanged scripts are left alone")

-- 3. The same with REMOVE_STALE.
local cleaned = damaged()
runSync(cleaned, true)
diff = differences(cleaned, expected)
check(#diff == 0, `REMOVE_STALE removes it ({#diff} differences)`)

if #failures > 0 then
	print(`studio sync test: {#failures} problem(s)`)
	process.exit(1)
end
print("studio sync test: no problems")
