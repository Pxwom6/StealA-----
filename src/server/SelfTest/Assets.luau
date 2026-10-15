--!strict
--[[
	Self-test section Assets: every asset the game uses loads in the real engine. Offline nothing can tell whether an
	audio id was deleted or made private; this is where that shows first.

	The ids come from every module in ReplicatedStorage.Shared.Config (any string that names an asset, wherever it is:
	Config/Sounds' effects and music today, a texture or decal added to a config later) and from what the game has
	built: particle textures, decals, images, meshes, skies and sounds under Workspace (players' characters left
	out), Lighting, SoundService, StarterGui and ReplicatedStorage.CreatureModels (custom models). Each id is
	requested once with ContentProvider:PreloadAsync and its per-asset callback, all at the same time, through a
	throwaway instance of the right kind (a Sound for audio, a Decal for an image...). Anything that doesn't come back
	Enum.AssetFetchStatus.Success is a problem, named by its config key, e.g.
	"Sounds.music.halloween.id rbxassetid://1848232312: Failure". A failure the callback reports is asked about once
	more with GetAssetFetchStatus (the callback has been seen to report Failure for audio that loaded).
]]

local ContentProvider = game:GetService("ContentProvider")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local StarterGui = game:GetService("StarterGui")

local Kit = require(script.Parent.Kit)

type Kind = "audio" | "image" | "mesh" | "animation"
type Asset = { id: string, kind: Kind, key: string, places: number, fromConfig: boolean, status: string? }
type Content = { property: string, kind: Kind }

local SKY: { Content } = {}
for _, face in { "SkyboxBk", "SkyboxDn", "SkyboxFt", "SkyboxLf", "SkyboxRt", "SkyboxUp", "SunTextureId" } do
	table.insert(SKY, { property = face, kind = "image" })
end
table.insert(SKY, { property = "MoonTextureId", kind = "image" })

-- Instance properties that name content, by class.
local CONTENT: { [string]: { Content } } = {
	Sound = { { property = "SoundId", kind = "audio" } },
	ParticleEmitter = { { property = "Texture", kind = "image" } },
	Beam = { { property = "Texture", kind = "image" } },
	Trail = { { property = "Texture", kind = "image" } },
	Decal = { { property = "Texture", kind = "image" } },
	Texture = { { property = "Texture", kind = "image" } },
	ImageLabel = { { property = "Image", kind = "image" } },
	ImageButton = {
		{ property = "Image", kind = "image" },
		{ property = "HoverImage", kind = "image" },
		{ property = "PressedImage", kind = "image" },
	},
	MeshPart = { { property = "MeshId", kind = "mesh" }, { property = "TextureID", kind = "image" } },
	SpecialMesh = { { property = "MeshId", kind = "mesh" }, { property = "TextureId", kind = "image" } },
	Sky = SKY,
	Animation = { { property = "AnimationId", kind = "animation" } },
}

-- A string that names an asset (thumbnails, rbxthumb://, are made on demand and left out).
local function isAsset(text: string): boolean
	return string.match(text, "^rbxassetid://%d+$") ~= nil
		or string.match(text, "^rbxasset://.") ~= nil
		or string.match(text, "^https?://www%.roblox%.com/asset/%?id=%d+$") ~= nil
end

-- What a config string is, from where it is: anything in Config/Sounds or under a key about sound is audio.
local function kindFromKey(key: string): Kind
	local lower = string.lower(key)
	if
		string.sub(lower, 1, 7) == "sounds."
		or string.find(lower, "sound", 1, true)
		or string.find(lower, "music", 1, true)
		or string.find(lower, "audio", 1, true)
	then
		return "audio"
	elseif string.find(lower, "mesh", 1, true) then
		return "mesh"
	elseif string.find(lower, "anim", 1, true) then
		return "animation"
	end
	return "image"
end

-- Every asset string in `value`, with its path ("Sounds.music.lobby.id"), keys in a stable order.
local function walk(
	value: unknown,
	path: string,
	depth: number,
	seen: { [any]: boolean },
	found: (string, string) -> ()
)
	if type(value) == "string" then
		if isAsset(value) then
			found(path, value)
		end
		return
	end
	if type(value) ~= "table" or depth > 12 or seen[value] then
		return
	end
	seen[value] = true
	local keys: { any } = {}
	for key in value :: { [any]: unknown } do
		table.insert(keys, key)
	end
	table.sort(keys, function(a: any, b: any): boolean
		if type(a) == "number" and type(b) == "number" then
			return a < b
		end
		return tostring(a) < tostring(b)
	end)
	for _, key in keys do
		local step = if type(key) == "number" then `[{key}]` else `.{tostring(key)}`
		walk((value :: any)[key], path .. step, depth + 1, seen, found)
	end
end

local function collect(): ({ Asset }, number)
	local list: { Asset } = {}
	local byId: { [string]: Asset } = {}
	local function add(key: string, id: string, kind: Kind, fromConfig: boolean)
		local existing = byId[id]
		if existing then
			existing.places += 1
			return
		end
		local asset: Asset = { id = id, kind = kind, key = key, places = 1, fromConfig = fromConfig }
		byId[id] = asset
		table.insert(list, asset)
	end

	-- Every config module, by name.
	local config = ReplicatedStorage:FindFirstChild("Shared")
	config = if config then config:FindFirstChild("Config") else nil
	local modules: { ModuleScript } = {}
	if config then
		for _, child in config:GetChildren() do
			if child:IsA("ModuleScript") then
				table.insert(modules, child)
			end
		end
	end
	table.sort(modules, function(a: ModuleScript, b: ModuleScript): boolean
		return a.Name < b.Name
	end)
	for _, module in modules do
		local ok, value = pcall(require, module)
		if ok then
			walk(value, module.Name, 0, {}, function(path: string, id: string)
				add(path, id, kindFromKey(path), true)
			end)
		end
	end
	local fromConfig = #list

	-- What the game has built (players' characters are their own avatars: left out).
	local skip: { [Instance]: boolean } = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character then
			for _, descendant in character:GetDescendants() do
				skip[descendant] = true
			end
		end
	end
	local roots: { Instance } = { workspace, Lighting, SoundService, StarterGui }
	local models = ReplicatedStorage:FindFirstChild("CreatureModels")
	if models and typeof(models) == "Instance" then -- (offline it is a stand-in for the empty Rojo folder)
		table.insert(roots, models)
	end
	for _, root in roots do
		for _, descendant in root:GetDescendants() do
			local properties = CONTENT[descendant.ClassName]
			if properties == nil or skip[descendant] then
				continue
			end
			for _, content in properties do
				local ok, value = pcall(function(): unknown
					return (descendant :: any)[content.property]
				end)
				if ok and type(value) == "string" and isAsset(value) then
					add(`{descendant:GetFullName()}.{content.property}`, value, content.kind, false)
				end
			end
		end
	end
	return list, fromConfig
end

-- A throwaway instance that names `asset`, for PreloadAsync (which takes instances).
local function holderFor(asset: Asset): Instance
	if asset.kind == "audio" then
		local sound = Instance.new("Sound")
		sound.SoundId = asset.id
		return sound
	elseif asset.kind == "mesh" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.FileMesh
		mesh.MeshId = asset.id
		return mesh
	elseif asset.kind == "animation" then
		local animation = Instance.new("Animation")
		animation.AnimationId = asset.id
		return animation
	end
	local decal = Instance.new("Decal")
	decal.Texture = asset.id
	return decal
end

-- Requests `asset` and records its final status.
local function fetch(asset: Asset)
	local holder = holderFor(asset)
	local status: string? = nil
	local ok, err = pcall(function()
		ContentProvider:PreloadAsync({ holder }, function(_contentId: string, fetchStatus: Enum.AssetFetchStatus)
			if status == nil or fetchStatus ~= Enum.AssetFetchStatus.Success then
				status = fetchStatus.Name
			end
		end)
	end)
	if not ok then
		status = `PreloadAsync failed ({Kit.short(tostring(err), 80)})`
	end
	if status ~= "Success" then
		local asked, now = pcall(function(): Enum.AssetFetchStatus
			return ContentProvider:GetAssetFetchStatus(asset.id)
		end)
		if asked and now == Enum.AssetFetchStatus.Success then
			status = "Success"
		end
	end
	holder:Destroy()
	asset.status = status or "None (no answer)"
end

local Assets: Kit.Section = {
	name = "Assets",
	run = function(ctx: Kit.Context): string
		local mark = ctx.mark()
		local assets, fromConfig = collect()
		if fromConfig == 0 then
			ctx.problem("no asset ids found in ReplicatedStorage.Shared.Config (Config/Sounds should have some)")
		end
		for _, asset in assets do
			task.spawn(fetch, asset)
		end
		local deadline = os.clock() + ctx.options.assetTimeoutSeconds
		local function allDone(): boolean
			for _, asset in assets do
				if asset.status == nil then
					return false
				end
			end
			return true
		end
		while not allDone() and os.clock() < deadline do
			task.wait(0.05)
		end
		local failed: { Asset } = {}
		local builtIn, builtInLoaded = 0, 0
		for _, asset in assets do
			asset.status = asset.status or `TimedOut (no answer in {ctx.options.assetTimeoutSeconds} s)`
			if asset.status ~= "Success" then
				table.insert(failed, asset)
			end
			if string.sub(asset.id, 1, 11) == "rbxasset://" then
				builtIn += 1
				builtInLoaded += if asset.status == "Success" then 1 else 0
			end
		end
		if #failed == #assets and #assets > 1 and builtIn > 0 and builtInLoaded == 0 then
			-- Not even the files that ship with Roblox: it is the request, not the assets.
			ctx.problem(
				`nothing loaded, not even Roblox's own files: ContentProvider can't fetch here ({failed[1].id}: `
					.. `{failed[1].status}; see the Output)`
			)
		else
			for _, asset in failed do
				local more = if asset.places > 1 then ` (+{asset.places - 1} more uses)` else ""
				ctx.problem(`{asset.key} {asset.id}: {asset.status}{more}`)
			end
		end
		-- What the engine logged about the assets it couldn't load says the same as the lines above.
		for _, message in ctx.take(mark) do
			local lower = string.lower(message.text)
			if string.find(lower, "asset", 1, true) or string.find(lower, "sound", 1, true) then
				ctx.note(`logged while loading: {message.text}`)
			else
				ctx.problem(`{message.kind}: {message.text}`)
			end
		end
		local built = #assets - fromConfig
		if #failed > 0 then
			return `{#failed} of {#assets} assets did not load`
		end
		return `{#assets} assets loaded ({fromConfig} from Config, {built} in what the game built)`
	end,
}

return Assets
