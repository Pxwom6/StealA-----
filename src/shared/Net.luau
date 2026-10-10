--!strict
--[[
	RemoteEvent registry. The server creates every remote in ReplicatedStorage.Remotes at startup (Studio-only test
	hooks such as DevGrantProduct only in Studio); clients wait for them. Remote names are a closed set so a typo is
	a type error, not a silent nil.

	Client → server remotes are INTENTS only ("buy item 17"). The server validates everything; see
	server/Services/Remotes.luau for the rate-limit + guard wrapper every handler goes through.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

export type ClientToServer =
	"ClientReady"
	| "BuyBeltItem"
	| "BuyPodium"
	| "SellCreature"
	| "StealBegin"
	| "StealConfirm"
	| "TagThief"
	| "LockBase"
	| "Rebirth"
	| "ClaimDaily"
	| "ClientEvent"
	| "CheckGroup"
	| "InvitePrompted"
	| "SkipTutorial"
	| "DevGrantProduct"
	| "ClaimQuest"

export type ServerToClient =
	"StateUpdate"
	| "BeltSnapshot"
	| "BeltSpawn"
	| "BeltRemove"
	| "Notify"
	| "Announce"
	| "WelcomeBack"
	| "StealAlert"
	| "Effect"
	| "SnackdexSync"

export type RemoteName = ClientToServer | ServerToClient

local CLIENT_TO_SERVER: { ClientToServer } = {
	"ClientReady",
	"BuyBeltItem",
	"BuyPodium",
	"SellCreature",
	"StealBegin",
	"StealConfirm",
	"TagThief",
	"LockBase",
	"Rebirth",
	"ClaimDaily",
	"ClientEvent",
	"CheckGroup",
	"InvitePrompted",
	"SkipTutorial",
	"DevGrantProduct",
	"ClaimQuest",
}

local SERVER_TO_CLIENT: { ServerToClient } = {
	"StateUpdate",
	"BeltSnapshot",
	"BeltSpawn",
	"BeltRemove",
	"Notify",
	"Announce",
	"WelcomeBack",
	"StealAlert",
	"Effect",
	"SnackdexSync",
}

local FOLDER_NAME = "Remotes"

-- Test hooks: these remotes are only created in Studio, so live servers expose no way to call them at all.
local STUDIO_ONLY: { [string]: boolean } = { DevGrantProduct = true }

local Net = {}
Net.clientToServer = CLIENT_TO_SERVER
Net.serverToClient = SERVER_TO_CLIENT

-- Server only: creates the Remotes folder and every RemoteEvent (STUDIO_ONLY ones only in Studio). Safe to call
-- once at startup.
function Net.createAll(): Folder
	assert(RunService:IsServer(), "Net.createAll is server-only")
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if folder == nil then
		local newFolder = Instance.new("Folder")
		newFolder.Name = FOLDER_NAME
		newFolder.Parent = ReplicatedStorage
		folder = newFolder
	end
	local remotes = folder :: Folder
	local isStudio = RunService:IsStudio()
	local function ensure(name: string)
		if STUDIO_ONLY[name] and not isStudio then
			return
		end
		if remotes:FindFirstChild(name) == nil then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = remotes
		end
	end
	for _, name in CLIENT_TO_SERVER do
		ensure(name)
	end
	for _, name in SERVER_TO_CLIENT do
		ensure(name)
	end
	return remotes
end

function Net.get(name: RemoteName): RemoteEvent
	assert(not STUDIO_ONLY[name] or RunService:IsStudio(), `{name} is a Studio-only remote`)
	local folder = if RunService:IsServer()
		then ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		else ReplicatedStorage:WaitForChild(FOLDER_NAME)
	assert(folder ~= nil, "Remotes folder missing; call Net.createAll() on the server first")
	local remote = if RunService:IsServer() then folder:FindFirstChild(name) else folder:WaitForChild(name)
	assert(remote ~= nil and remote:IsA("RemoteEvent"), `missing remote {name}`)
	return remote
end

return Net
