--!strict
--[[
	The gateway every client intent passes through:
	  1. per-player token-bucket rate limit (Config/Gameplay.rateLimits) — excess calls are dropped
	  2. the handler runs inside pcall, so garbage arguments can never break the server
	Handlers receive raw `unknown` arguments and must validate them with Logic/Guard before use.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Gameplay = require(ReplicatedStorage.Shared.Config.Gameplay)
local RateLimiter = require(ReplicatedStorage.Shared.Logic.RateLimiter)

local Remotes = {}

local limiters: { RateLimiter.Limiter } = {}
local droppedCount: { [number]: number } = {}
local DROP_WARN_THRESHOLD = 50

function Remotes.start()
	Net.createAll()
	-- Periodically report players who hammer remotes (possible exploit), then reset the counters.
	task.spawn(function()
		while true do
			task.wait(60)
			for userId, count in droppedCount do
				if count >= DROP_WARN_THRESHOLD then
					warn(`[Remotes] user {userId} exceeded rate limits {count} times in the last minute`)
				end
			end
			table.clear(droppedCount)
		end
	end)
end

export type Handler = (player: Player, ...unknown) -> ()

function Remotes.onIntent(name: Net.ClientToServer, handler: Handler)
	local cfg = Gameplay.rateLimits[name]
	assert(cfg ~= nil, `no rate limit configured for {name}`)
	local limiter = RateLimiter.new(cfg.burst, cfg.perSecond)
	table.insert(limiters, limiter)
	Net.get(name).OnServerEvent:Connect(function(player: Player, ...: any)
		if not RateLimiter.allow(limiter, tostring(player.UserId), os.clock()) then
			droppedCount[player.UserId] = (droppedCount[player.UserId] or 0) + 1
			return
		end
		local ok, err = pcall(handler :: (...any) -> ...any, player, ...)
		if not ok then
			warn(`[Remotes] {name} handler error for {player.Name}: {err}`)
		end
	end)
end

function Remotes.fire(player: Player, name: Net.ServerToClient, ...: any)
	Net.get(name):FireClient(player, ...)
end

function Remotes.fireAll(name: Net.ServerToClient, ...: any)
	Net.get(name):FireAllClients(...)
end

function Remotes.notify(player: Player, text: string, kind: string?)
	Remotes.fire(player, "Notify", { text = text, kind = kind or "info" })
end

function Remotes.forget(player: Player)
	local key = tostring(player.UserId)
	for _, limiter in limiters do
		RateLimiter.forget(limiter, key)
	end
	droppedCount[player.UserId] = nil
end

return Remotes
