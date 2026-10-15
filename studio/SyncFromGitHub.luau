--!strict
--[[
	Steal a Snackling: bring this place's code up to date with GitHub, from inside Roblox Studio.

	  1. Home > Game Settings > Security: turn on "Allow HTTP Requests" (turn it off again afterwards if you like).
	  2. View > Command Bar. Paste this whole file into it and press Enter.
	  3. Read the Output window, play-test, then File > Publish to Roblox.

	It asks GitHub for the latest commit and its file list (two small API calls), downloads every .luau file under
	src/ from that exact commit (raw.githubusercontent.com) and creates or updates the matching scripts the way Rojo
	maps them (default.project.json):
	    src/shared -> ReplicatedStorage.Shared
	    src/server -> ServerScriptService.Server
	    src/client -> StarterPlayer.StarterPlayerScripts.Client
	A folder's init.server.luau / init.client.luau / init.luau is that folder's own script; Foo.server.luau becomes a
	Script, Foo.client.luau a LocalScript, Foo.luau a ModuleScript, and any other folder a Folder.

	Scripts in those three places that are no longer in the repo are listed in the Output, and deleted only when
	REMOVE_STALE is true. Nothing else changes: the map is built by the code at run time, and
	ReplicatedStorage.CreatureModels, ServerScriptService.ServerPackages and the place's settings stay as they are.
	Edit > Undo (Ctrl+Z / Cmd+Z) takes the whole sync back.

	Running it twice is harmless: unchanged scripts are left alone.

	A private repo (recommended before the game goes public: README "Before publishing") only serves its files with a
	GitHub token. Make a fine-grained personal access token (GitHub > Settings > Developer settings > Personal access
	tokens > Fine-grained tokens) for this one repository, with read-only "Contents" access and a short expiry. Paste
	it between the quotes of GITHUB_TOKEN below in the copy you paste into the Command Bar, never in this file in the
	repo or in a script in the place. It is sent only to GitHub (an Authorization header) and the place keeps no copy,
	but Studio's Command Bar history does on that computer: that is why it should be read-only and expire soon. With
	GITHUB_TOKEN empty (a public repo) no token is sent.
]]

local REPO = "Pxwom6/StealA-----"
local BRANCH = "main"
local REMOVE_STALE = false
local PARALLEL = 8 -- downloads at once
local GITHUB_TOKEN = "" -- only for a private repo: see the header (paste it in the Command Bar copy only)

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local HttpService = game:GetService("HttpService")
local ScriptEditorService = game:GetService("ScriptEditorService")

type Root = { prefix: string, parent: Instance, name: string }

local ROOTS: { Root } = {
	{ prefix = "src/shared/", parent = game:GetService("ReplicatedStorage"), name = "Shared" },
	{ prefix = "src/server/", parent = game:GetService("ServerScriptService"), name = "Server" },
	{
		prefix = "src/client/",
		parent = game:GetService("StarterPlayer"):FindFirstChildOfClass("StarterPlayerScripts") :: Instance,
		name = "Client",
	},
}

-- One instance the repo needs: its path below the root ("" is the root itself), its class, and the file whose text
-- is its Source (scripts only).
type Node = { path: string, name: string, class: string, file: string? }

local HEADERS = if GITHUB_TOKEN ~= "" then { Authorization = `token {GITHUB_TOKEN}` } else nil

local function get(url: string): string
	local ok, result = pcall(function(): string
		return HttpService:GetAsync(url, true, HEADERS)
	end)
	if not ok then
		error(`could not download {url}\n  {result}`, 0)
	end
	return result
end

-- "Services/Foo.server.luau" -> ("Services", "Foo", "Script"); "init.luau" -> ("", "init", "ModuleScript")
local function describe(relative: string): (string, string, string)
	local directory, file = string.match(relative, "^(.*)/([^/]+)$")
	if directory == nil then
		directory, file = "", relative
	end
	local base = string.gsub(file :: string, "%.luau?$", "")
	local class = "ModuleScript"
	if string.sub(base, -7) == ".server" then
		base, class = string.sub(base, 1, -8), "Script"
	elseif string.sub(base, -7) == ".client" then
		base, class = string.sub(base, 1, -8), "LocalScript"
	end
	return directory :: string, base, class
end

local function join(directory: string, name: string): string
	return if directory == "" then name else `{directory}/{name}`
end

local function lastSegment(path: string): string
	return string.match(path, "([^/]+)$") or path
end

-- Every instance one root needs, keyed by path.
local function plan(root: Root, files: { string }): { [string]: Node }
	local nodes: { [string]: Node } = {}
	local function folder(path: string)
		if nodes[path] == nil then
			nodes[path] = { path = path, name = if path == "" then root.name else lastSegment(path), class = "Folder" }
			if path ~= "" then
				folder(string.match(path, "^(.*)/[^/]+$") or "")
			end
		end
	end
	folder("")
	for _, file in files do
		local directory, base, class = describe(string.sub(file, #root.prefix + 1))
		folder(directory)
		if base == "init" then
			-- the folder itself is this script
			local node = nodes[directory]
			node.class = class
			node.file = file
		else
			local path = join(directory, base)
			nodes[path] = { path = path, name = base, class = class, file = file }
		end
	end
	return nodes
end

-- The child `name` of `parent` with class `class`: reused when it already is one; otherwise a new one takes its
-- place (keeping its children).
local function ensure(parent: Instance, name: string, class: string, report: { string }): Instance
	local existing = parent:FindFirstChild(name)
	if existing and existing.ClassName == class then
		return existing
	end
	local created = Instance.new(class)
	created.Name = name
	if existing then
		for _, child in existing:GetChildren() do
			child.Parent = created
		end
		table.insert(report, `{existing:GetFullName()}: {existing.ClassName} -> {class}`)
		existing:Destroy()
	end
	created.Parent = parent
	return created
end

local function setSource(script: Instance, source: string)
	local ok = pcall(function()
		ScriptEditorService:UpdateSourceAsync(script :: LuaSourceContainer, function(): string
			return source
		end)
	end)
	if not ok then
		(script :: any).Source = source
	end
end

local function sync()
	local readable, enabled = pcall(function(): boolean
		return HttpService.HttpEnabled
	end)
	if readable and not enabled then
		warn("[Sync] HTTP requests look switched off: Home > Game Settings > Security > Allow HTTP Requests.")
	end
	local commit = HttpService:JSONDecode(get(`https://api.github.com/repos/{REPO}/commits/{BRANCH}`))
	local sha: string = commit.sha
	local message: string = string.split(commit.commit.message, "\n")[1]
	print(`[Sync] {REPO} @ {string.sub(sha, 1, 7)}: {message}`)
	local listing = HttpService:JSONDecode(get(`https://api.github.com/repos/{REPO}/git/trees/{sha}?recursive=1`))
	if listing.truncated then
		error("[Sync] GitHub cut the file list short; nothing was changed", 0)
	end

	-- What each root needs.
	local plans: { { root: Root, nodes: { [string]: Node } } } = {}
	local total = 0
	for _, root in ROOTS do
		local files: { string } = {}
		for _, entry in listing.tree do
			local path: string = entry.path
			if
				entry.type == "blob"
				and string.sub(path, 1, #root.prefix) == root.prefix
				and string.match(path, "%.luau?$")
			then
				table.insert(files, path)
			end
		end
		if #files == 0 then
			error(`[Sync] no files under {root.prefix} at {sha}; nothing was changed`, 0)
		end
		total += #files
		table.insert(plans, { root = root, nodes = plan(root, files) })
	end

	-- Download everything first, so a failed download changes nothing.
	local wanted: { string } = {}
	for _, entry in plans do
		for _, node in entry.nodes do
			if node.file then
				table.insert(wanted, node.file :: string)
			end
		end
	end
	local sources: { [string]: string } = {}
	local failures: { string } = {}
	local nextIndex, active = 1, 0
	print(`[Sync] downloading {#wanted} files...`)
	while nextIndex <= #wanted or active > 0 do
		while active < PARALLEL and nextIndex <= #wanted do
			local file = wanted[nextIndex]
			nextIndex += 1
			active += 1
			task.spawn(function()
				local ok, result = pcall(get, `https://raw.githubusercontent.com/{REPO}/{sha}/{file}`)
				if ok then
					sources[file] = result
				else
					table.insert(failures, tostring(result))
				end
				active -= 1
			end)
		end
		task.wait()
	end
	if #failures > 0 then
		error(`[Sync] {#failures} downloads failed; nothing was changed\n{table.concat(failures, "\n")}`, 0)
	end

	-- Apply, parents before children.
	ChangeHistoryService:SetWaypoint("Before syncing from GitHub")
	local added, updated, unchanged = 0, 0, 0
	local classChanges: { string } = {}
	local stale: { string } = {}
	for _, entry in plans do
		local root, nodes = entry.root, entry.nodes
		local ordered: { Node } = {}
		for _, node in nodes do
			table.insert(ordered, node)
		end
		table.sort(ordered, function(a: Node, b: Node): boolean
			local depthA = if a.path == "" then 0 else #string.split(a.path, "/")
			local depthB = if b.path == "" then 0 else #string.split(b.path, "/")
			return depthA < depthB or (depthA == depthB and a.path < b.path)
		end)
		local instances: { [string]: Instance } = {}
		for _, node in ordered do
			local parent = if node.path == ""
				then root.parent
				else instances[string.match(node.path, "^(.*)/[^/]+$") or ""]
			local existed = parent:FindFirstChild(node.name) ~= nil
			local instance = ensure(parent, node.name, node.class, classChanges)
			instances[node.path] = instance
			local file = node.file
			if file then
				local source = sources[file]
				if (instance :: any).Source == source then
					unchanged += 1
				else
					setSource(instance, source)
					if existed then
						updated += 1
					else
						added += 1
					end
				end
			end
		end
		-- Scripts and folders the repo no longer has.
		local expected: { [Instance]: boolean } = {}
		for _, instance in instances do
			expected[instance] = true
		end
		for _, descendant in instances[""]:GetDescendants() do
			if (descendant:IsA("LuaSourceContainer") or descendant:IsA("Folder")) and not expected[descendant] then
				table.insert(stale, descendant:GetFullName())
				if REMOVE_STALE then
					descendant:Destroy()
				end
			end
		end
	end
	ChangeHistoryService:SetWaypoint("Synced from GitHub")

	print(`[Sync] done: {added} added, {updated} updated, {unchanged} already up to date ({total} files)`)
	for _, line in classChanges do
		print(`[Sync] changed class: {line}`)
	end
	if #stale > 0 then
		local verb = if REMOVE_STALE then "removed" else "not in the repo (set REMOVE_STALE = true to remove)"
		warn(`[Sync] {#stale} {verb}:\n  {table.concat(stale, "\n  ")}`)
	end
	print("[Sync] now play-test, then File > Publish to Roblox")
end

local ok, err = pcall(sync :: () -> ...any)
if not ok then
	warn(err)
end
