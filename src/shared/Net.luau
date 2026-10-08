--!strict
--[[
	RemoteEvent registry. The server creates every remote in ReplicatedStorage.Remotes at startup; clients wait
	for them. Remote names are a closed set so a typo is a type error, not a silent nil.

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
	| "DevGrantProduct"

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
	"DevGrantProduct",
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
}

local FOLDER_NAME = "Remotes"

local Net = {}
Net.clientToServer = CLIENT_TO_SERVER
Net.serverToClient = SERVER_TO_CLIENT

-- Server only: creates the Remotes folder and every RemoteEvent. Safe to call once at startup.
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
	local function ensure(name: string)
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
	local folder = if RunService:IsServer()
		then ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		else ReplicatedStorage:WaitForChild(FOLDER_NAME)
	assert(folder ~= nil, "Remotes folder missing; call Net.createAll() on the server first")
	local remote = if RunService:IsServer() then folder:FindFirstChild(name) else folder:WaitForChild(name)
	assert(remote ~= nil and remote:IsA("RemoteEvent"), `missing remote {name}`)
	return remote
end

return Net
