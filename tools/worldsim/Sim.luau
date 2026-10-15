--!strict
--[[
	A small stand-in for a Roblox server, so the game's Roblox-side modules can run offline with Lune (no Studio).

	Instances, datatypes and enums come from Lune's built-in roblox library. This adds what it doesn't implement and
	the map code uses: Terrain fills (recorded, so a preview can draw them), positions derived from CFrames, model
	pivots, attribute-changed signals, `workspace:GetServerTimeNow()`, the services the game asks for (TweenService
	finishes every tween at once, RunService says "Studio server", CollectionService keeps tags in a table...), and the
	`Random` / `TweenInfo` globals. A loader maps the Rojo tree in default.project.json to the files in src/, so
	`require(script.Parent.X)`, `require(ReplicatedStorage.Shared.Config.Y)` and the shared modules'
	`require("../Types")` all work as in the game.

	The game's code sees every instance through a thin wrapper (one per instance, so `==` and table keys behave):
	Lune refuses to read properties Roblox computes, such as BasePart.Position, and the wrapper derives those.

	It is not a game server: there are no players, physics or remotes. It runs what builds the world (MapBuilder,
	SceneryBuilder, the world themes, seasonal decorations) so CI can catch runtime errors there
	(tools/worldsim/smoke.luau) and the result can be exported for an offline 3D preview (tools/worldsim/export.luau).
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local task = require("@lune/task")

local Sim = {}

-- Server time returned by workspace:GetServerTimeNow(). Move it forward with Sim.advance.
Sim.now = 1_800_000_000
Sim.isStudio = true
-- When on, the game's os.clock() and os.time() follow Sim.now too, so what the game times with os.clock (the carry
-- budget, rate limits, income ticks) and dates with os.time (codes, daily rewards) moves only when the test moves
-- it. Set it before booting the server.
Sim.virtualClock = false
-- Game passes each fake player owns: Sim.ownedPasses[userId][passId] = true (nobody owns any by default).
Sim.ownedPasses = {} :: { [number]: { [number]: boolean } }
-- PolicyService answers per fake player: Sim.policies[userId] = the policy table, or "error" for a failed lookup.
-- Default: nothing restricted.
Sim.policies = {} :: { [number]: any }
-- What the game logged with AnalyticsService, oldest first: { method = "LogCustomEvent", args = { ... } }.
Sim.analytics = {} :: { { method: string, args: { any } } }
-- Everything the game sent to `warn` (a smoke test fails on any).
Sim.warnings = {} :: { string }
-- Terrain calls in order: { op = "FillBall", args = { ... } }.
Sim.terrainOps = {} :: { { op: string, args: { any } } }
-- Terrain:SetMaterialColor by material name.
Sim.terrainColors = {} :: { [string]: any }

local realGame = roblox.Instance.new("DataModel")
local realWorkspace = realGame:GetService("Workspace")

-- Signals ----------------------------------------------------------------------------------------------------------

export type Signal = {
	Connect: (self: any, listener: (...any) -> ()) -> any,
	Once: (self: any, listener: (...any) -> ()) -> any,
	Wait: (self: any) -> ...any,
	Fire: (self: any, ...any) -> (),
}

function Sim.signal(): Signal
	local listeners: { (...any) -> () } = {}
	local signal = {}
	function signal.Connect(_self: any, listener: (...any) -> ()): any
		table.insert(listeners, listener)
		local connection = { Connected = true }
		function connection.Disconnect(_: any)
			connection.Connected = false
			local index = table.find(listeners, listener)
			if index then
				table.remove(listeners, index)
			end
		end
		return connection
	end
	function signal.Once(self: any, listener: (...any) -> ()): any
		local connection: any
		connection = signal.Connect(self, function(...: any)
			connection:Disconnect()
			listener(...)
		end)
		return connection
	end
	function signal.Wait(_self: any): ...any
		error("Signal:Wait is not supported offline")
	end
	-- Like Roblox, each listener runs in its own thread: an error in one doesn't stop the others or the firer.
	function signal.Fire(_self: any, ...: any)
		for _, listener in table.clone(listeners) do
			task.spawn(listener, ...)
		end
	end
	return signal :: any
end

-- Methods Lune's roblox library doesn't implement (they receive the real instance) ------------------------------------

local function recordTerrain(op: string): (any, ...any) -> ()
	return function(_self: any, ...: any)
		table.insert(Sim.terrainOps, { op = op, args = table.pack(...) :: any })
	end
end
for _, op in { "FillBlock", "FillBall", "FillCylinder", "FillWedge", "ReplaceMaterial", "Clear" } do
	roblox.implementMethod("Terrain", op, recordTerrain(op))
end
roblox.implementMethod("Terrain", "SetMaterialColor", function(_self: any, material: any, color: any)
	Sim.terrainColors[material.Name] = color
end)
roblox.implementMethod("Terrain", "GetMaterialColor", function(_self: any, material: any): any
	return Sim.terrainColors[material.Name] or roblox.Color3.new(0.5, 0.5, 0.5)
end)

roblox.implementMethod("Workspace", "GetServerTimeNow", function(_self: any): number
	return Sim.now
end)

local function pivotOf(instance: any): any
	if instance:IsA("BasePart") then
		return instance.CFrame
	end
	local primary = instance.PrimaryPart
	if primary then
		return primary.CFrame
	end
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("BasePart") then
			return descendant.CFrame
		end
	end
	return roblox.CFrame.new()
end
roblox.implementMethod("PVInstance", "GetPivot", pivotOf)
roblox.implementMethod("PVInstance", "PivotTo", function(self: any, target: any)
	local delta = target * pivotOf(self):Inverse()
	if self:IsA("BasePart") then
		self.CFrame = delta * self.CFrame
	end
	for _, descendant in self:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CFrame = delta * descendant.CFrame
		end
	end
end)

-- A model's bounding box, axis-aligned in world space (Roblox orients it by the pivot; close enough offline).
local function boundingBox(model: any): (any, any)
	local min = roblox.Vector3.new(math.huge, math.huge, math.huge)
	local max = roblox.Vector3.new(-math.huge, -math.huge, -math.huge)
	local any = false
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			any = true
			local cf, size = descendant.CFrame, descendant.Size
			for _, sx in { -0.5, 0.5 } do
				for _, sy in { -0.5, 0.5 } do
					for _, sz in { -0.5, 0.5 } do
						local corner = cf * roblox.Vector3.new(size.X * sx, size.Y * sy, size.Z * sz)
						min = roblox.Vector3.new(
							math.min(min.X, corner.X),
							math.min(min.Y, corner.Y),
							math.min(min.Z, corner.Z)
						)
						max = roblox.Vector3.new(
							math.max(max.X, corner.X),
							math.max(max.Y, corner.Y),
							math.max(max.Z, corner.Z)
						)
					end
				end
			end
		end
	end
	if not any then
		return roblox.CFrame.new(), roblox.Vector3.zero
	end
	return roblox.CFrame.new((min + max) / 2), max - min
end
roblox.implementMethod("Model", "GetBoundingBox", boundingBox)
roblox.implementMethod("Model", "GetExtentsSize", function(self: any): any
	local _, size = boundingBox(self)
	return size
end)

-- Attribute / property signals: real objects, but nothing fires them offline.
local attributeSignals: { [any]: { [string]: Signal } } = setmetatable({}, { __mode = "k" }) :: any
roblox.implementMethod("Instance", "GetAttributeChangedSignal", function(self: any, name: string): any
	local byName = attributeSignals[self] or {}
	attributeSignals[self] = byName
	byName[name] = byName[name] or Sim.signal()
	return byName[name]
end)
-- Everything exists already offline (nothing streams in), so waiting for a child is finding it.
roblox.implementMethod("Instance", "WaitForChild", function(self: any, name: string, _timeout: number?): any
	return self:FindFirstChild(name)
end)
roblox.implementMethod("Instance", "GetPropertyChangedSignal", function(_self: any, _name: string): any
	return Sim.signal()
end)
for _, event in { "Changed", "AncestryChanged", "Destroying", "ChildAdded", "ChildRemoved", "DescendantAdded" } do
	roblox.implementProperty("Instance", event, function(_self: any): any
		return Sim.signal()
	end)
end
-- Events the game connects to and the offline server fires itself, one signal per instance and event.
local instanceSignals: { [any]: { [string]: Signal } } = setmetatable({}, { __mode = "k" }) :: any
local function instanceSignal(real: any, name: string): Signal
	local byName = instanceSignals[real] or {}
	instanceSignals[real] = byName
	byName[name] = byName[name] or Sim.signal()
	return byName[name]
end
for _, entry in
	{
		{ "TextChatCommand", "Triggered" },
		{ "RemoteEvent", "OnServerEvent" },
		{ "RemoteEvent", "OnClientEvent" },
		{ "Player", "CharacterAdded" },
		{ "Player", "CharacterRemoving" },
		{ "Humanoid", "Died" },
		{ "ClickDetector", "MouseClick" },
	}
do
	roblox.implementProperty(entry[1], entry[2], function(self: any): any
		return instanceSignal(self, entry[2])
	end)
end

-- What the server sent to clients: { remote = name, player = userId (0 = everyone), args = { ... } }.
Sim.sent = {} :: { { remote: string, player: number, args: { any } } }
roblox.implementMethod("RemoteEvent", "FireClient", function(self: any, player: any, ...: any)
	table.insert(Sim.sent, { remote = self.Name, player = player.UserId, args = table.pack(...) :: any })
end)
roblox.implementMethod("RemoteEvent", "FireAllClients", function(self: any, ...: any)
	table.insert(Sim.sent, { remote = self.Name, player = 0, args = table.pack(...) :: any })
end)

-- Instance wrappers ------------------------------------------------------------------------------------------------

local wrappers: { [any]: any } = setmetatable({}, { __mode = "k" }) :: any -- real instance -> wrapper
local reals: { [any]: any } = setmetatable({}, { __mode = "k" }) :: any -- wrapper -> real instance

local wrap: (value: any) -> any
local unwrap: (value: any) -> any

local function wrapAll(...: any): ...any
	local values = table.pack(...)
	for i = 1, values.n do
		values[i] = wrap(values[i])
	end
	return table.unpack(values, 1, values.n)
end

local function unwrapAll(...: any): ...any
	local values = table.pack(...)
	for i = 1, values.n do
		values[i] = unwrap(values[i])
	end
	return table.unpack(values, 1, values.n)
end

-- Reads Roblox derives from other properties, which Lune can't answer. nil = not one of those.
local function derivedRead(real: any, key: string): any
	if key == "Position" and real:IsA("BasePart") then
		return real.CFrame.Position
	elseif key == "Orientation" and real:IsA("BasePart") then
		local x, y, z = real.CFrame:ToOrientation()
		return roblox.Vector3.new(math.deg(x), math.deg(y), math.deg(z))
	elseif (key == "WorldCFrame" or key == "WorldPosition") and real:IsA("Attachment") then
		local parent = real.Parent
		local world = if parent and parent:IsA("BasePart") then parent.CFrame * real.CFrame else real.CFrame
		return if key == "WorldCFrame" then world else world.Position
	end
	return nil
end

local function derivedWrite(real: any, key: string, value: any): boolean
	if key == "Position" and real:IsA("BasePart") then
		real.CFrame = real.CFrame.Rotation + value
		return true
	elseif key == "WorldCFrame" and real:IsA("Attachment") then
		local parent = real.Parent
		real.CFrame = if parent and parent:IsA("BasePart") then parent.CFrame:Inverse() * value else value
		return true
	elseif key == "WorldPosition" and real:IsA("Attachment") then
		local parent = real.Parent
		local world = roblox.CFrame.new(value)
		real.CFrame = if parent and parent:IsA("BasePart") then parent.CFrame:Inverse() * world else world
		return true
	end
	return false
end

local instanceMeta: any = {}
instanceMeta.__index = function(wrapper: any, key: string): any
	local real = reals[wrapper]
	local derived = derivedRead(real, key)
	if derived ~= nil then
		return derived
	end
	local value = real[key]
	if type(value) == "function" then
		return function(_self: any, ...: any): ...any
			return wrapAll(value(real, unwrapAll(...)))
		end
	end
	return wrap(value)
end
instanceMeta.__newindex = function(wrapper: any, key: string, value: any)
	local real = reals[wrapper]
	if not derivedWrite(real, key, value) then
		real[key] = unwrap(value)
	end
end
instanceMeta.__tostring = function(wrapper: any): string
	return tostring(reals[wrapper])
end

-- typeof, without the type checker reading the comparison as a Roblox type refinement (tools are checked without
-- Roblox's definitions).
local function kindOf(value: any): string
	return typeof(value)
end

wrap = function(value: any): any
	if kindOf(value) == "Instance" then
		local wrapper = wrappers[value]
		if wrapper == nil then
			wrapper = setmetatable({}, instanceMeta)
			wrappers[value] = wrapper
			reals[wrapper] = value
		end
		return wrapper
	elseif type(value) == "table" and getmetatable(value) == nil and kindOf(value[1]) == "Instance" then
		local list = {}
		for index, item in value do
			list[index] = wrap(item)
		end
		return list
	end
	return value
end

unwrap = function(value: any): any
	if type(value) == "table" then
		local real = reals[value]
		if real ~= nil then
			return real
		end
	end
	return value
end

-- The real Lune instance behind what the game's code holds.
function Sim.real(value: any): any
	return unwrap(value)
end

local Instance = {
	new = function(className: string, parent: any?): any
		local real = roblox.Instance.new(className)
		if parent ~= nil then
			real.Parent = unwrap(parent)
		end
		return wrap(real)
	end,
}
-- The game's Instance.new, for tests that make instances of their own (wrapped like the game's).
Sim.Instance = Instance

-- Globals ----------------------------------------------------------------------------------------------------------

-- Roblox's Random, as a Park-Miller generator (same seed, same numbers; not Roblox's exact sequence).
local Random = {}
Random.__index = Random

function Random.new(seed: number?): any
	local state = math.floor(seed or (os.clock() * 1e6)) % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	return setmetatable({ state = state }, Random)
end

function Random.NextNumber(self: any, min: number?, max: number?): number
	self.state = (self.state * 16807) % 2147483647
	local unit = (self.state - 1) / 2147483646
	local low, high = min or 0, max or 1
	return low + (high - low) * unit
end

function Random.NextInteger(self: any, min: number, max: number): number
	return math.min(max, min + math.floor(Random.NextNumber(self) * (max - min + 1)))
end

function Random.Clone(self: any): any
	return setmetatable({ state = self.state }, Random)
end

local TweenInfo = {}
function TweenInfo.new(
	time: number?,
	style: any?,
	direction: any?,
	repeatCount: number?,
	reverses: boolean?,
	delay: number?
): any
	return {
		Time = time or 1,
		EasingStyle = style,
		EasingDirection = direction,
		RepeatCount = repeatCount or 0,
		Reverses = reverses or false,
		DelayTime = delay or 0,
	}
end

-- Services ---------------------------------------------------------------------------------------------------------

-- Tweens finish the moment they are played.
local TweenService = {}
function TweenService.Create(_self: any, instance: any, _info: any, goals: { [string]: any }): any
	local tween = { Completed = Sim.signal(), PlaybackState = "Begin" }
	function tween.Play(_: any)
		for key, value in goals do
			instance[key] = value
		end
		tween.PlaybackState = "Completed"
		tween.Completed:Fire("Completed")
	end
	function tween.Cancel(_: any)
		tween.PlaybackState = "Cancelled"
	end
	function tween.Pause(_: any) end
	function tween.Destroy(_: any) end
	return tween
end

local RunService = {
	Heartbeat = Sim.signal(),
	Stepped = Sim.signal(),
	RenderStepped = Sim.signal(),
	PostSimulation = Sim.signal(),
}
function RunService.IsStudio(_self: any): boolean
	return Sim.isStudio
end
function RunService.IsServer(_self: any): boolean
	return true
end
function RunService.IsClient(_self: any): boolean
	return false
end
function RunService.IsRunning(_self: any): boolean
	return true
end

-- Players: the real (Lune) Players service holds the fake players, so `player.Parent == Players` holds as in the game.
local realPlayers = realGame:GetService("Players")
local Players: any = {
	PlayerAdded = Sim.signal(),
	PlayerRemoving = Sim.signal(),
	MaxPlayers = 8,
	LocalPlayer = nil,
}
function Players.GetPlayers(_self: any): { any }
	local list = {}
	for _, child in realPlayers:GetChildren() do
		if child:IsA("Player") then
			table.insert(list, wrap(child))
		end
	end
	return list
end
function Players.GetPlayerByUserId(_self: any, userId: number): any
	for _, child in realPlayers:GetChildren() do
		if child:IsA("Player") and child.UserId == userId then
			return wrap(child)
		end
	end
	return nil
end
function Players.GetFriendsAsync(_self: any, _userId: number): any
	error("Players.GetFriendsAsync is not available offline")
end
function Players.GetUserThumbnailAsync(_self: any, _userId: number, _type: any, _size: any): (string, boolean)
	return "", true
end

local tagged: { [string]: { [any]: boolean } } = {}
local CollectionService = {}
function CollectionService.AddTag(_self: any, instance: any, tag: string)
	tagged[tag] = tagged[tag] or {}
	tagged[tag][instance] = true
end
function CollectionService.RemoveTag(_self: any, instance: any, tag: string)
	if tagged[tag] then
		tagged[tag][instance] = nil
	end
end
function CollectionService.HasTag(_self: any, instance: any, tag: string): boolean
	return tagged[tag] ~= nil and tagged[tag][instance] == true
end
function CollectionService.GetTagged(_self: any, tag: string): { any }
	local list = {}
	local set: { [any]: boolean } = tagged[tag] or {}
	for instance in set do
		table.insert(list, instance)
	end
	return list
end
function CollectionService.GetInstanceAddedSignal(_self: any, _tag: string): any
	return Sim.signal()
end
function CollectionService.GetInstanceRemovedSignal(_self: any, _tag: string): any
	return Sim.signal()
end

local HttpService = {}
function HttpService.JSONEncode(_self: any, value: any): string
	return serde.encode("json", value)
end
function HttpService.JSONDecode(_self: any, text: string): any
	return serde.decode("json", text)
end
local guid = 0
function HttpService.GenerateGUID(_self: any, wrapInBraces: boolean?): string
	guid += 1
	local id = string.format("00000000-0000-4000-8000-%012d", guid)
	return if wrapInBraces == false then id else `\{{id}\}`
end

-- A service the offline server can't provide: its events are quiet signals, its functions throw (the game pcalls
-- every online call, so it carries on as it would during an outage), and plain fields can be assigned.
local function unavailable(name: string): any
	local signals: { [string]: Signal } = {}
	return setmetatable({}, {
		__index = function(_, key: string): any
			for _, suffix in { "Finished", "Added", "Removed", "Changed", "Triggered", "Joined", "Left" } do
				if string.sub(key, -#suffix) == suffix then
					signals[key] = signals[key] or Sim.signal()
					return signals[key]
				end
			end
			return function()
				error(`{name}.{key} is not available offline`)
			end
		end,
	})
end

-- The Rojo tree ----------------------------------------------------------------------------------------------------

-- A script or folder of the project, by where Rojo syncs it from. Indexing a child, `.Parent`, `.Name`,
-- FindFirstChild / WaitForChild / GetChildren work like the synced instances; `require` accepts it.
type Ref = { __fs: string, __dir: string?, __name: string, __parent: any }

local refMeta: any = {}

-- Lune's file calls yield, and lookups happen inside metamethods (which can't), so the project's files are indexed
-- once up front.
local knownFiles: { [string]: boolean } = {}
local knownDirs: { [string]: { string } } = {}
-- Nested Rojo projects (Wally packages): a folder whose default.project.json points its root at one file.
local nestedProjects: { [string]: string } = {}

local function scan(dir: string)
	if knownDirs[dir] or not fs.isDir(dir) then
		return
	end
	local entries = fs.readDir(dir)
	table.sort(entries)
	knownDirs[dir] = entries
	local projectFile = `{dir}/default.project.json`
	if fs.isFile(projectFile) then
		local source = fs.readFile(projectFile)
		local ok, project = pcall(function(): any
			return serde.decode("json", source)
		end)
		local root = if ok
				and type(project) == "table"
				and type(project.tree) == "table"
			then project.tree["$path"]
			else nil
		if type(root) == "string" and fs.isFile(`{dir}/{root}`) then
			nestedProjects[dir] = `{dir}/{root}`
		end
	end
	for _, entry in entries do
		local path = `{dir}/{entry}`
		if fs.isDir(path) then
			scan(path)
		else
			knownFiles[path] = true
		end
	end
end

local function isFile(path: string): boolean
	return knownFiles[path] == true
end

local function isDir(path: string): boolean
	return knownDirs[path] ~= nil
end

local SCRIPT_SUFFIXES = { ".luau", ".server.luau", ".client.luau", ".lua", ".server.lua", ".client.lua" }
local INIT_FILES =
	{ "init.luau", "init.server.luau", "init.client.luau", "init.lua", "init.server.lua", "init.client.lua" }

local function makeRef(fsPath: string, dir: string?, name: string, parent: any): Ref
	return setmetatable({ __fs = fsPath, __dir = dir, __name = name, __parent = parent }, refMeta) :: any
end

-- A folder of the project: a script when it has an init file (or is a nested project of one file), else a plain
-- folder (empty __fs).
local function dirRef(dir: string, name: string, parent: any): Ref
	local nested = nestedProjects[dir]
	if nested then
		return makeRef(nested, nil, name, parent)
	end
	for _, init in INIT_FILES do
		if isFile(`{dir}/{init}`) then
			return makeRef(`{dir}/{init}`, dir, name, parent)
		end
	end
	return makeRef("", dir, name, parent)
end

local function childRef(ref: Ref, name: string): Ref?
	local dir = ref.__dir
	if dir == nil then
		return nil
	end
	for _, suffix in SCRIPT_SUFFIXES do
		local path = `{dir}/{name}{suffix}`
		if isFile(path) then
			return makeRef(path, nil, name, ref)
		end
	end
	if isDir(`{dir}/{name}`) then
		return dirRef(`{dir}/{name}`, name, ref)
	end
	return nil
end

local function children(ref: Ref): { Ref }
	local list: { Ref } = {}
	local dir = ref.__dir
	if dir == nil then
		return list
	end
	local entries: { string } = knownDirs[dir] or {}
	for _, entry in entries do
		local name: string? = nil
		if isDir(`{dir}/{entry}`) then
			name = entry
		else
			for _, suffix in { ".server.luau", ".client.luau", ".luau", ".server.lua", ".client.lua", ".lua" } do
				if string.sub(entry, -#suffix) == suffix and not string.match(entry, "^init%.") then
					name = string.sub(entry, 1, -#suffix - 1)
					break
				end
			end
		end
		if name then
			local child = childRef(ref, name)
			if child then
				table.insert(list, child)
			end
		end
	end
	return list
end

refMeta.__index = function(ref: Ref, key: string): any
	if string.sub(key, 1, 2) == "__" then
		return nil -- a ref's own fields (__dir of a plain folder is nil)
	elseif key == "Name" then
		return ref.__name
	elseif key == "Parent" then
		return ref.__parent
	elseif key == "FindFirstChild" or key == "WaitForChild" then
		return function(self: Ref, name: string): Ref?
			return childRef(self, name)
		end
	elseif key == "GetChildren" then
		return children
	elseif key == "IsA" then
		return function(self: Ref, className: string): boolean
			return (className == "ModuleScript" or className == "LuaSourceContainer") and self.__fs ~= ""
		end
	elseif key == "GetFullName" then
		return function(self: Ref): string
			return if self.__fs ~= "" then self.__fs else self.__dir or self.__name
		end
	end
	local child = childRef(ref, key)
	if child == nil then
		error(`{key} is not a valid member of {ref.__dir or ref.__fs}`, 2)
	end
	return child
end
refMeta.__tostring = function(ref: Ref): string
	return ref.__name
end

-- A service the project syncs into: its Rojo children first, then the instance's own members.
local function hybrid(instance: any, rojoChildren: { [string]: Ref }): any
	return setmetatable({}, {
		__index = function(_, key: string): any
			local child = rojoChildren[key]
			if child then
				return child
			end
			if key == "FindFirstChild" or key == "WaitForChild" then
				return function(_self: any, name: string): any
					return rojoChildren[name] or instance:FindFirstChild(name)
				end
			end
			local value = instance[key]
			if type(value) == "function" then
				return function(_self: any, ...: any): ...any
					return value(instance, ...)
				end
			end
			return value
		end,
		__newindex = function(_, key: string, value: any)
			instance[key] = value
		end,
	})
end

local function readProject(): { [string]: { [string]: Ref } }
	local project = serde.decode("json", fs.readFile("default.project.json"))
	-- Index every folder the project syncs from.
	local function index(node: { [string]: any })
		for key, child in node do
			if type(child) ~= "table" then
				continue
			end
			local path = child["$path"]
			if type(path) == "string" then
				scan(path)
			elseif type(path) == "table" and type(path.optional) == "string" then
				scan(path.optional)
			end
			if string.sub(key, 1, 1) ~= "$" then
				index(child)
			end
		end
	end
	index(project.tree)

	local services: { [string]: { [string]: Ref } } = {}
	local function walk(node: { [string]: any }, parentRef: any, into: { [string]: Ref })
		for key, child in node do
			if string.sub(key, 1, 1) == "$" or type(child) ~= "table" then
				continue
			end
			local path = child["$path"]
			if type(path) == "string" and isDir(path) then
				into[key] = dirRef(path, key, parentRef)
			elseif type(path) == "table" and type(path.optional) == "string" and isDir(path.optional) then
				into[key] = dirRef(path.optional, key, parentRef)
			elseif path == nil then
				-- A plain container (e.g. StarterPlayerScripts): a folder ref with only the project's children.
				local folder = makeRef("", nil, key, parentRef)
				local nested: { [string]: Ref } = {}
				walk(child, folder, nested)
				local folderMeta = table.clone(refMeta)
				folderMeta.__index = function(ref: Ref, name: string): any
					if nested[name] then
						return nested[name]
					end
					return refMeta.__index(ref, name)
				end
				-- A plain container holds only what the project puts in it (e.g. CreatureModels starts empty).
				local findChild = function(_self: Ref, name: string): Ref?
					return nested[name]
				end
				folderMeta.__index = function(ref: Ref, name: string): any
					if string.sub(name, 1, 2) == "__" then
						return nil
					elseif nested[name] then
						return nested[name]
					elseif name == "FindFirstChild" or name == "WaitForChild" then
						return findChild
					elseif name == "GetChildren" then
						return function(_self: Ref): { Ref }
							local list = {}
							for _, child in nested do
								table.insert(list, child)
							end
							return list
						end
					end
					return refMeta.__index(ref, name)
				end
				into[key] = setmetatable(folder :: any, folderMeta) :: any
			end
		end
	end
	for serviceName, node in project.tree do
		if string.sub(serviceName, 1, 1) ~= "$" and type(node) == "table" then
			local into: { [string]: Ref } = {}
			walk(node, nil, into)
			services[serviceName] = into
		end
	end
	return services
end

local projectChildren = readProject()

-- The Players stub is the face of the real Players service (and falls back to its members).
setmetatable(Players, {
	__index = function(_, key: string): any
		local value = wrap(realPlayers)[key]
		return value
	end,
})
wrappers[realPlayers] = Players
reals[Players] = realPlayers

-- Services that answer offline: passes from Sim.ownedPasses, policies from Sim.policies, analytics are recorded.
local MarketplaceService: any = unavailable("MarketplaceService")
function MarketplaceService.UserOwnsGamePassAsync(_self: any, userId: number, passId: number): boolean
	local owned = Sim.ownedPasses[userId]
	return owned ~= nil and owned[passId] == true
end
local PolicyService: any = unavailable("PolicyService")
function PolicyService.GetPolicyInfoForPlayerAsync(_self: any, player: any): { [string]: any }
	local policy = Sim.policies[unwrap(player).UserId]
	if policy == "error" then
		error("PolicyService could not be reached")
	end
	return policy or { ArePaidRandomItemsRestricted = false, AreAdsAllowed = true, AllowedExternalLinkReferences = {} }
end
local AnalyticsService: any = setmetatable({}, {
	__index = function(_, key: string): any
		return function(_self: any, ...: any)
			table.insert(Sim.analytics, { method = key, args = table.pack(...) :: any })
		end
	end,
})

local serviceStubs: { [string]: any } = {
	TweenService = TweenService,
	RunService = RunService,
	Players = Players,
	CollectionService = CollectionService,
	HttpService = HttpService,
	DataStoreService = unavailable("DataStoreService"),
	MessagingService = unavailable("MessagingService"),
	MarketplaceService = MarketplaceService,
	PolicyService = PolicyService,
	BadgeService = unavailable("BadgeService"),
	SocialService = unavailable("SocialService"),
	GroupService = unavailable("GroupService"),
	AnalyticsService = AnalyticsService,
	TextService = unavailable("TextService"),
}

local services: { [string]: any } = {}

local function getService(_self: any, name: string): any
	if services[name] then
		return services[name]
	end
	local service = serviceStubs[name]
	if service == nil then
		local real = realGame:GetService(name)
		local instance = wrap(real)
		local rojo = projectChildren[name]
		if rojo then
			-- The service's one face for the game's code: parenting to it, comparing with it and reading it back all
			-- give the same object.
			service = hybrid(instance, rojo)
			wrappers[real] = service
			reals[service] = real
		else
			service = instance
		end
	end
	services[name] = service
	return service
end

-- DataModel properties a place file doesn't store (Lune can't read them): what a fresh Studio session would say.
local GAME_PROPERTIES: { [string]: any } = {
	PlaceId = 0,
	GameId = 0,
	CreatorId = 0,
	PlaceVersion = 0,
	JobId = "",
	PrivateServerId = "",
	PrivateServerOwnerId = 0,
}

-- Functions game:BindToClose registered (Sim.close runs them).
local closeCallbacks: { () -> () } = {}

local gameProxy = setmetatable({}, {
	__index = function(_, key: string): any
		if key == "GetService" or key == "FindService" then
			return getService
		elseif key == "Workspace" then
			return wrap(realWorkspace)
		elseif key == "IsLoaded" then
			return function(): boolean
				return true
			end
		elseif key == "BindToClose" then
			return function(_self: any, callback: () -> ())
				table.insert(closeCallbacks, callback)
			end
		elseif GAME_PROPERTIES[key] ~= nil then
			return GAME_PROPERTIES[key]
		end
		return wrap(realGame)[key]
	end,
})

-- Loading modules --------------------------------------------------------------------------------------------------

local cache: { [string]: any } = {}
local loading: { [string]: boolean } = {}

-- The game's `os`: the real one, except that clock() and time() follow Sim.now while Sim.virtualClock is on. The
-- virtual clock() counts from a fixed point long before any Sim.now, so it stays positive whatever Sim.now a test
-- starts from, and moves exactly with it.
local VIRTUAL_CLOCK_ORIGIN = 1_000_000_000
local realClock = os.clock
local gameOs = setmetatable({
	clock = function(): number
		if Sim.virtualClock then
			return Sim.now - VIRTUAL_CLOCK_ORIGIN
		end
		return realClock()
	end,
	time = function(date: any?): number
		if date ~= nil then
			return os.time(date)
		end
		if Sim.virtualClock then
			return math.floor(Sim.now)
		end
		return os.time()
	end,
}, { __index = os })

local globals: { [string]: any } = {
	game = gameProxy,
	os = gameOs,
	workspace = wrap(realWorkspace),
	Instance = Instance,
	Vector3 = roblox.Vector3,
	Vector2 = roblox.Vector2,
	CFrame = roblox.CFrame,
	Color3 = roblox.Color3,
	BrickColor = roblox.BrickColor,
	UDim = roblox.UDim,
	UDim2 = roblox.UDim2,
	Rect = roblox.Rect,
	Ray = roblox.Ray,
	Enum = roblox.Enum,
	Font = roblox.Font,
	NumberRange = roblox.NumberRange,
	NumberSequence = roblox.NumberSequence,
	NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
	ColorSequence = roblox.ColorSequence,
	ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
	PhysicalProperties = roblox.PhysicalProperties,
	Random = Random,
	TweenInfo = TweenInfo,
	task = task,
	tick = gameOs.clock,
	typeof = function(value: any): string
		return if reals[value] ~= nil then "Instance" else kindOf(value)
	end,
	warn = function(...: any)
		local parts = {}
		for i = 1, select("#", ...) do
			table.insert(parts, tostring((select(i, ...))))
		end
		local text = table.concat(parts, " ")
		table.insert(Sim.warnings, text)
		print(`[warn] {text}`)
	end,
}

local function normalise(path: string): string
	local out: { string } = {}
	for segment in string.gmatch(path, "[^/]+") do
		if segment == ".." then
			assert(#out > 0, `path escapes the repo: {path}`)
			table.remove(out)
		elseif segment ~= "." then
			table.insert(out, segment)
		end
	end
	return table.concat(out, "/")
end

local function dirname(path: string): string
	return string.match(path, "^(.*)/[^/]*$") or "."
end

local load: (ref: Ref) -> any

local function requireString(from: Ref, target: string): any
	local base = dirname(from.__fs)
	local path = normalise(`{base}/{target}`)
	local name = string.match(path, "[^/]+$") or path
	for _, suffix in { ".luau", ".lua" } do
		if isFile(`{path}{suffix}`) then
			return load(makeRef(`{path}{suffix}`, nil, name, nil))
		end
	end
	if isDir(path) then
		return load(dirRef(path, name, nil))
	end
	error(`cannot require "{target}" from {from.__fs}`, 3)
end

load = function(ref: Ref): any
	local path = ref.__fs
	assert(path ~= "", `{ref.__name} is a folder, not a script`)
	if cache[path] ~= nil then
		return cache[path]
	end
	assert(not loading[path], `cyclic require of {path}`)
	loading[path] = true
	local env = table.clone(globals)
	env.script = ref
	env.require = function(target: any): any
		if type(target) == "string" then
			return requireString(ref, target)
		end
		return load(target)
	end
	local chunk = luau.load(fs.readFile(path), { debugName = path, environment = env })
	local result = chunk()
	cache[path] = if result == nil then true else result
	loading[path] = nil
	return result
end

-- Requires a project module by its place in the Rojo tree, e.g. Sim.require("ServerScriptService", "Server",
-- "Services", "MapBuilder").
function Sim.require(serviceName: string, ...: string): any
	local ref: any = getService(nil, serviceName)
	for _, name in { ... } do
		ref = ref[name]
	end
	return load(ref)
end

-- A server module by its path under src/server, e.g. Sim.server("Services/MapBuilder").
function Sim.server(path: string): any
	return Sim.require("ServerScriptService", "Server", table.unpack(string.split(path, "/")))
end

-- A shared module by its path under src/shared, e.g. Sim.shared("Config/Gameplay").
function Sim.shared(path: string): any
	return Sim.require("ReplicatedStorage", "Shared", table.unpack(string.split(path, "/")))
end

function Sim.game(): any
	return gameProxy
end

function Sim.workspace(): any
	return wrap(realWorkspace)
end

function Sim.service(name: string): any
	return getService(nil, name)
end

-- Replaces a module before anything requires it, e.g. ProfileStore with tools/worldsim/MockProfileStore.
function Sim.mock(fsPath: string, value: any)
	cache[fsPath] = value
end

-- Runs what game:BindToClose registered (a server shutting down).
function Sim.close()
	for _, callback in closeCallbacks do
		callback()
	end
end

-- Fake players -------------------------------------------------------------------------------------------------------

-- A player joins (PlayerAdded fires; the game loads their save, gives them a plot...).
function Sim.addPlayer(userId: number, name: string): any
	local player = roblox.Instance.new("Player")
	player.Name = name
	pcall(function()
		player.DisplayName = name
	end)
	player.UserId = userId
	player.Parent = realPlayers
	local wrapped = wrap(player)
	Players.PlayerAdded:Fire(wrapped)
	return wrapped
end

-- Gives a player a minimal character (root part, head, humanoid) at `position`, as if it just spawned.
function Sim.spawnCharacter(player: any, position: any): any
	local real = unwrap(player)
	local model = roblox.Instance.new("Model")
	model.Name = real.Name
	local root = roblox.Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = roblox.Vector3.new(2, 2, 1)
	root.CFrame = roblox.CFrame.new(position)
	root.Parent = model
	local head = roblox.Instance.new("Part")
	head.Name = "Head"
	head.Size = roblox.Vector3.new(2, 1, 1)
	head.CFrame = roblox.CFrame.new(position + roblox.Vector3.new(0, 1.5, 0))
	head.Parent = model
	local humanoid = roblox.Instance.new("Humanoid")
	humanoid.MaxHealth = 100
	humanoid.Health = 100
	humanoid.WalkSpeed = 16
	humanoid.Parent = model
	model.PrimaryPart = root
	model.Parent = realWorkspace
	real.Character = model
	instanceSignal(real, "CharacterAdded"):Fire(wrap(model))
	return wrap(model)
end

-- Moves a player's character (as if they walked there).
function Sim.moveCharacter(player: any, position: any)
	local character = unwrap(player).Character
	if character then
		character:PivotTo(roblox.CFrame.new(position))
	end
end

-- A player leaves.
function Sim.removePlayer(player: any)
	Players.PlayerRemoving:Fire(player)
	unwrap(player).Parent = nil
end

-- A client intent: fires the remote's OnServerEvent as that player.
function Sim.fireServer(player: any, remoteName: string, ...: any)
	local remotes = realGame:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
	local remote = remotes and remotes:FindFirstChild(remoteName)
	assert(remote, `no remote {remoteName}`)
	instanceSignal(remote, "OnServerEvent"):Fire(player, ...)
end

-- `player` clicks (or taps) a ClickDetector the server made.
function Sim.click(player: any, clickDetector: any)
	instanceSignal(unwrap(clickDetector), "MouseClick"):Fire(player)
end

-- A chat command typed by `player` (e.g. "/mod rushHour").
function Sim.chat(player: any, text: string)
	local alias = string.match(text, "^(%S+)")
	for _, command in realGame:GetService("TextChatService"):GetDescendants() do
		if command:IsA("TextChatCommand") and command.PrimaryAlias == alias then
			instanceSignal(command, "Triggered"):Fire({ UserId = unwrap(player).UserId }, text)
		end
	end
end

-- Everything sent to `userId` (or to everyone) on `remote`, oldest first: each entry's args.
function Sim.received(userId: number, remote: string): { { any } }
	local list = {}
	for _, entry in Sim.sent do
		if entry.remote == remote and (entry.player == userId or entry.player == 0) then
			table.insert(list, entry.args)
		end
	end
	return list
end

-- Moves server time forward and lets anything task.delay / task.defer scheduled run.
function Sim.advance(seconds: number)
	Sim.now += seconds
	task.wait(0)
end

-- Export -----------------------------------------------------------------------------------------------------------

local function round(n: number, places: number): number
	local scale = 10 ^ places
	return math.floor(n * scale + 0.5) / scale
end

local function color(c: any): { number }
	return { round(c.R, 3), round(c.G, 3), round(c.B, 3) }
end

local function vector(v: any): { number }
	return { round(v.X, 3), round(v.Y, 3), round(v.Z, 3) }
end

local function cframe(cf: any): { number }
	local out = {}
	for _, n in { cf:GetComponents() } do
		table.insert(out, round(n, 4))
	end
	return out
end

local function exportArg(value: any): any
	local kind = kindOf(value)
	if kind == "CFrame" then
		return { cframe = cframe(value) }
	elseif kind == "Vector3" then
		return { vector = vector(value) }
	elseif kind == "EnumItem" then
		return { enum = value.Name }
	elseif kind == "Region3" then
		return { region = { cframe(value.CFrame), vector(value.Size) } }
	end
	return value
end

local TERRAIN_MATERIALS = {
	"Grass",
	"Sand",
	"Rock",
	"Snow",
	"Ground",
	"Mud",
	"Basalt",
	"CrackedLava",
	"Glacier",
	"Ice",
	"Salt",
	"Sandstone",
	"Slate",
	"LeafyGrass",
	"Limestone",
	"Asphalt",
	"Pavement",
	"Brick",
	"Cobblestone",
	"Concrete",
	"WoodPlanks",
}

-- Every visible part under `root` (default: workspace), the lights, the lighting and the terrain calls, as plain data
-- for the preview renderer. Invisible parts (Transparency 1: colliders, barriers, a locked plot's force field) are
-- left out.
function Sim.exportWorld(root: any?): { [string]: any }
	local parts = {}
	local lights = {}
	for _, instance in unwrap(root or realWorkspace):GetDescendants() do
		if instance:IsA("BasePart") and instance.ClassName ~= "Terrain" and instance.Transparency < 0.99 then
			local shape = "Block"
			if instance.ClassName == "WedgePart" then
				shape = "Wedge"
			elseif instance.ClassName == "CornerWedgePart" then
				shape = "CornerWedge"
			elseif instance:IsA("Part") then
				shape = instance.Shape.Name
			end
			local mesh = instance:FindFirstChildOfClass("SpecialMesh")
			if mesh and mesh.MeshType.Name == "Sphere" then
				shape = "Ball"
			end
			table.insert(parts, {
				name = instance.Name,
				shape = shape,
				size = vector(instance.Size),
				cf = cframe(instance.CFrame),
				color = color(instance.Color),
				material = instance.Material.Name,
				transparency = round(instance.Transparency, 3),
			})
		elseif instance:IsA("PointLight") or instance:IsA("SpotLight") then
			local parent = instance.Parent
			if parent and parent:IsA("BasePart") then
				table.insert(lights, {
					position = vector(parent.CFrame.Position),
					color = color(instance.Color),
					range = instance.Range,
					brightness = instance.Brightness,
				})
			end
		end
	end

	local Lighting = realGame:GetService("Lighting")
	local lighting: { [string]: any } = {
		clockTime = Lighting.ClockTime,
		latitude = Lighting.GeographicLatitude,
		brightness = Lighting.Brightness,
		ambient = color(Lighting.Ambient),
		outdoorAmbient = color(Lighting.OutdoorAmbient),
		colorShiftTop = color(Lighting.ColorShift_Top),
		exposure = Lighting.ExposureCompensation,
	}
	for _, child in Lighting:GetChildren() do
		if child:IsA("Atmosphere") then
			lighting.atmosphere = {
				density = child.Density,
				offset = child.Offset,
				color = color(child.Color),
				decay = color(child.Decay),
				glare = child.Glare,
				haze = child.Haze,
			}
		elseif child:IsA("ColorCorrectionEffect") and child.Enabled then
			lighting.colorCorrection = lighting.colorCorrection or {}
			table.insert(lighting.colorCorrection, {
				tint = color(child.TintColor),
				brightness = child.Brightness,
				contrast = child.Contrast,
				saturation = child.Saturation,
			})
		elseif child:IsA("Sky") then
			lighting.sky = { starCount = child.StarCount, sunSize = child.SunAngularSize }
		end
	end
	local terrain = realWorkspace.Terrain
	local clouds = terrain:FindFirstChildOfClass("Clouds")
	if clouds and clouds.Enabled then
		lighting.clouds = { cover = clouds.Cover, density = clouds.Density, color = color(clouds.Color) }
	end

	local ops = {}
	for _, op in Sim.terrainOps do
		local args = {}
		for i = 1, (op.args :: any).n or #op.args do
			table.insert(args, exportArg(op.args[i]))
		end
		table.insert(ops, { op = op.op, args = args })
	end
	-- Lune implements the terrain colours itself (they are saved in place files), so read them back from the terrain.
	local materialColors = {}
	for name, c in Sim.terrainColors do
		materialColors[name] = color(c)
	end
	for _, name in TERRAIN_MATERIALS do
		local ok, c = pcall(function(): any
			return terrain:GetMaterialColor((roblox.Enum.Material :: any)[name])
		end)
		if ok and c then
			materialColors[name] = color(c)
		end
	end

	return {
		parts = parts,
		lights = lights,
		lighting = lighting,
		terrain = {
			ops = ops,
			materialColors = materialColors,
			waterColor = color(terrain.WaterColor),
			waterTransparency = terrain.WaterTransparency,
		},
	}
end

return Sim
