--!strict
--[[
	Studio-only chat commands for playtesting. They are never registered in live servers.

	  /cash <amount>        add cash to yourself              e.g. /cash 30000000  (test rebirth)
	  /spawn <creatureId> [mutationId]
	                        put a creature on the belt now    e.g. /spawn gelato_griffin, /spawn pizza_pup golden
	                        works for event creatures and event mutations whether or not their event is running,
	                        e.g. /spawn jack_o_lantern_latte haunted
	  /noshield             end new-player protection for everyone (so a 2-player test can steal right away)
	  /friends <n|off>      pretend n Roblox friends are in your server (Studio test players can't be friends)
	  /tutorial             start the first-time tutorial again (clears your tutorial progress; it pays the reward
	                        again when completed, Studio only)
	  /quests reset         re-roll today's daily quests (new picks, progress and claims start over)
	  /dex fill <rarity>    mark every Snackling of a tier discovered except one, and clear that tier's reward, so
	                        buying the missing one (the toast names it; /spawn it) tests completion; e.g. /dex fill
	                        common. "event" fills the Event section the same way (it has no reward)

	The LiveOps admin commands (LiveOpsService) also work for anyone in Studio, only in that session:
	  /event <eventId> [minutes], /event off [eventId], /luck <multiplier> <minutes>, /announce <text>
	  e.g. /event Halloween2026 2  (Halloween theme, event Snacklings and Haunted for 2 minutes, then it ends itself)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local GameData = require(ReplicatedStorage.Shared.GameData)
local SnackdexRules = require(ReplicatedStorage.Shared.Logic.SnackdexRules)

local BeltService = require(script.Parent.BeltService)
local EconomyService = require(script.Parent.EconomyService)
local LockService = require(script.Parent.LockService)
local QuestService = require(script.Parent.QuestService)
local Remotes = require(script.Parent.Remotes)
local Sessions = require(script.Parent.Sessions)
local SnackdexService = require(script.Parent.SnackdexService)
local SocialService = require(script.Parent.SocialService)
local TutorialService = require(script.Parent.TutorialService)

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
		local creatureId, mutationArg = args[1], args[2]
		if creatureId == nil then
			return
		end
		if GameData.catalog.creatures[creatureId] == nil then
			Remotes.notify(player, `[Studio] unknown creature {creatureId}`, "error")
			return
		end
		-- Mutation ids are matched case-insensitively ("/spawn pizza_pup Golden").
		local variant: string? = nil
		if mutationArg then
			for id in GameData.catalog.mutations do
				if string.lower(id) == string.lower(mutationArg) then
					variant = id
				end
			end
			if variant == nil then
				Remotes.notify(player, `[Studio] unknown mutation {mutationArg}`, "error")
				return
			end
		end
		BeltService.spawnCreature(creatureId, variant)
		Remotes.notify(player, `[Studio] spawned {creatureId}{if variant then ` ({variant})` else ""}`, "info")
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
	add("tutorial", function(player: Player)
		local session = Sessions.get(player)
		if session then
			TutorialService.restart(session)
			Remotes.notify(player, "[Studio] tutorial restarted", "info")
		end
	end)
	add("quests", function(player: Player, args: { string })
		local session = Sessions.get(player)
		if session == nil then
			return
		end
		if args[1] ~= "reset" then
			Remotes.notify(player, "[Studio] usage: /quests reset", "error")
			return
		end
		QuestService.devReset(session)
		Remotes.notify(player, "[Studio] today's quests re-rolled", "info")
	end)
	add("dex", function(player: Player, args: { string })
		local session = Sessions.get(player)
		if session == nil then
			return
		end
		-- The section by rarity id or name, any case ("common", "secret"), or "event".
		local wanted = string.lower(args[2] or "")
		local sectionId: string? = if wanted == string.lower(SnackdexRules.EVENT_SECTION)
			then SnackdexRules.EVENT_SECTION
			else nil
		for _, rarity in GameData.catalog.rarityList do
			if string.lower(rarity.id) == wanted or string.lower(rarity.displayName) == wanted then
				sectionId = rarity.id
			end
		end
		if args[1] ~= "fill" or sectionId == nil then
			Remotes.notify(player, "[Studio] usage: /dex fill <rarity|event>", "error")
			return
		end
		local leftOut = SnackdexService.devFill(session, sectionId)
		if leftOut then
			Remotes.notify(
				player,
				`[Studio] {sectionId}: all but {leftOut.displayName} found. /spawn {leftOut.id}`,
				"info"
			)
		else
			Remotes.notify(player, `[Studio] {sectionId} has no Snacklings`, "error")
		end
	end)
	print(
		"[DevCommands] Studio commands enabled: /cash <n>, /spawn <creatureId> [mutationId], /noshield, /friends <n|off>,"
			.. " /tutorial, /quests reset, /dex fill <rarity|event>"
			.. " (LiveOps: /event <id> [minutes], /event off, /luck <x> <min>)"
	)
end

return DevCommands
