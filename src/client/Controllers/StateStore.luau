--!strict
--[[
	Latest player state from the server (batched StateUpdate). Controllers subscribe with onChange.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Types = require(ReplicatedStorage.Shared.Types)

export type ClientState = Types.ClientState

local StateStore = {}

local current: ClientState? = nil
local listeners: { (ClientState) -> () } = {}

function StateStore.get(): ClientState?
	return current
end

-- Calls `listener` now (if state exists) and on every update.
function StateStore.onChange(listener: (ClientState) -> ())
	table.insert(listeners, listener)
	if current then
		task.spawn(listener, current)
	end
end

function StateStore.start()
	Net.get("StateUpdate").OnClientEvent:Connect(function(state: ClientState)
		current = state
		for _, listener in listeners do
			task.spawn(listener, state)
		end
	end)
end

function StateStore.serverNow(): number
	return workspace:GetServerTimeNow()
end

return StateStore
