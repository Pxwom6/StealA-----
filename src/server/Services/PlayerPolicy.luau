--!strict
--[[
	Each player's Roblox policy (PolicyService), for paid items with a random effect (Logic/PaidRandomItems): Server
	Luck today, paid Lucky Spin packs later.

	On join the policy is looked up in a pcall (one retry); a lookup that still fails counts as restricted, and is
	tried again in the background every minute or so. The answer is published as the player attribute
	PaidRandomItems.ATTRIBUTE, which the store reads (a paid random item's card shows as blocked unless it is true).
	A receipt for such an item asks paidRandomItemsAllowed first (MonetizationService): a player who may not buy one
	never gets it, even from a client that went around the store.
]]

local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PaidRandomItems = require(ReplicatedStorage.Shared.Logic.PaidRandomItems)

local PlayerPolicy = {}

local RETRY_DELAY_SECONDS = 1
local RECHECK_SECONDS = 60
local MAX_RECHECKS = 5

-- The answers so far: true = allowed, false = restricted (or the lookup failed). Missing while the first lookup runs.
local allowed: { [Player]: boolean } = {}

-- Asks Roblox (twice at most). Returns whether paid random items are allowed and whether Roblox answered at all.
local function ask(player: Player): (boolean, boolean)
	for attempt = 1, 2 do
		local ok, info = pcall(function(): { [string]: any }
			return PolicyService:GetPolicyInfoForPlayerAsync(player)
		end)
		if ok then
			return PaidRandomItems.allowedByPolicy(true, info), true
		end
		if attempt == 1 then
			task.wait(RETRY_DELAY_SECONDS)
		end
	end
	return false, false
end

local function publish(player: Player, isAllowed: boolean)
	if player.Parent ~= Players then
		return
	end
	allowed[player] = isAllowed
	player:SetAttribute(PaidRandomItems.ATTRIBUTE, isAllowed)
end

-- Looks the player's policy up now and publishes it. A failed lookup publishes "restricted" and, from the join
-- lookup, is retried in the background. Returns whether paid random items are allowed.
function PlayerPolicy.check(player: Player, retryInBackground: boolean?): boolean
	local isAllowed, answered = ask(player)
	publish(player, isAllowed)
	if not answered then
		warn(`[PlayerPolicy] could not look up {player.Name}'s policy: paid random items stay blocked for now`)
		if retryInBackground then
			task.spawn(function()
				for _ = 1, MAX_RECHECKS do
					task.wait(RECHECK_SECONDS)
					if player.Parent ~= Players then
						return
					end
					local nowAllowed, nowAnswered = ask(player)
					if nowAnswered then
						publish(player, nowAllowed)
						return
					end
				end
			end)
		end
	end
	return isAllowed
end

-- Whether `player` may buy a paid random item. Waits for a lookup if none has answered yet (may yield): call it
-- before the check-and-grant step, never inside it.
function PlayerPolicy.paidRandomItemsAllowed(player: Player): boolean
	local known = allowed[player]
	if known ~= nil then
		return known
	end
	return PlayerPolicy.check(player, false)
end

function PlayerPolicy.start()
	Players.PlayerAdded:Connect(function(player: Player)
		PlayerPolicy.check(player, true)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		allowed[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(PlayerPolicy.check, player, true)
	end
end

return PlayerPolicy
