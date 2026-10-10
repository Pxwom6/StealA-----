--!strict
--[[
	Studio-only chat commands for playtesting. They are never registered in live servers.

	  /cash <amount>        add cash to yourself              e.g. /cash 30000000  (test rebirth)
	  /spawn <creatureId>   put a creature on the belt now    e.g. /spawn gelato_griffin
	  /noshield             end new-player protection for everyone (so a 2-player test can steal right away)
	  /friends <n|off>      pretend n Roblox friends are in your server (Studio test players can't be friends)
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local BeltService = require(script.Parent.BeltService)
local EconomyService = require(script.Parent.EconomyService)
local LockService = require(script.Parent.LockService)
local Remotes = require(script.Parent.Remotes)
local Sessions = require(script.Parent.Sessions)
local SocialService = require(script.Parent.SocialService)

local DevCommands = {}

local function add(alias: string, handler: (player: Player, args: { string }) -> ())
	local command = Instance.new("TextChatCommand")
	command.Name = "Dev" .. alias
	command.PrimaryAlias = "/" .. alias
	command.AutocompleteVisible = false
	command.Parent = TextChatService
	command.Triggered:Connect(function(source: TextSource, text: string)
		local player = Players:GetPlayerByUserId(source.UserId)
		if player == nil then
			return
		end
		local args: { string } = {}
		for word in string.gmatch(text, "%S+") do
			table.insert(args, word)
		end
		table.remove(args, 1)
		handler(player, args)
	end)
end

function DevCommands.start()
	if not RunService:IsStudio() then
		return
	end
	add("cash", function(player: Player, args: { string })
		local session = Sessions.get(player)
		local amount = tonumber(args[1])
		if session and amount and amount > 0 and amount < 1e15 then
			EconomyService.addCash(session, amount)
			Remotes.notify(player, `[Studio] +{amount} cash`, "info")
		end
	end)
	add("spawn", function(player: Player, args: { string })
		if args[1] then
			BeltService.spawnCreature(args[1])
			Remotes.notify(player, `[Studio] spawned {args[1]}`, "info")
		end
	end)
	add("noshield", function(player: Player)
		for _, session in Sessions.all() do
			LockService.endGrace(session)
		end
		Remotes.notify(player, "[Studio] new-player shields removed", "info")
	end)
	add("friends", function(player: Player, args: { string })
		local session = Sessions.get(player)
		local count = tonumber(args[1])
		if session == nil then
			return
		end
		if count and count >= 0 and count <= 7 then
			SocialService.devSetFriends(session, math.floor(count))
			Remotes.notify(player, `[Studio] pretending {math.floor(count)} friends are here`, "info")
		else
			SocialService.devSetFriends(session, nil)
			Remotes.notify(player, "[Studio] back to real friends", "info")
		end
	end)
	print("[DevCommands] Studio commands enabled: /cash <n>, /spawn <creatureId>, /noshield, /friends <n|off>")
end

return DevCommands
