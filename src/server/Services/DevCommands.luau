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
	  /gallery [mutationId] every Snackling in labelled rows past the north boundary wall (and you, in front of them), to
	                        check and screenshot the models, e.g. /gallery, /gallery golden; /gallery off removes it
	  /sky <clockTime>      preview the lighting at another time of day, e.g. /sky 18 (dusk); everyone in the session
	                        sees it, until the next map or season change sets the lighting again
	  /quests reset         re-roll today's daily quests (new picks, progress and claims start over)
	  /dex fill <rarity>    mark every Snackling of a tier discovered except one, and clear that tier's reward, so
	                        buying the missing one (the toast names it; /spawn it) tests completion; e.g. /dex fill
	                        common. "event" fills the Event section the same way (it has no reward)
	  /playtime <minutes>   add minutes to today's playtime (unlocks playtime gifts), e.g. /playtime 60
	  /spins <n>            bank n Lucky Spins, e.g. /spins 5; /spins free makes the free spin ready now
	  /runaway [here]       a Snackling escapes now, as in Great Escape (far from everyone); /runaway here lets it out
	                        right beside you, to test catching it

	Map themes (MapThemeService; admins can use these in live servers too, that server only):
	  /map <id>             switch to that map now, e.g. /map candy, /map volcano
	  /map vote             start a 20-second vote for the next map
	  /map list             every map id (the current one in brackets)

	The LiveOps admin commands (LiveOpsService) also work for anyone in Studio, only in that session:
	  /event <eventId> [minutes], /event off [eventId], /luck <multiplier> <minutes>, /announce <text>
	  e.g. /event Halloween2026 2  (Halloween theme, event Snacklings and Haunted for 2 minutes, then it ends itself)
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local GameData = require(ReplicatedStorage.Shared.GameData)
local SnackdexRules = require(ReplicatedStorage.Shared.Logic.SnackdexRules)

local BeltService = require(script.Parent.BeltService)
local DevGallery = require(script.Parent.DevGallery)
local DropService = require(script.Parent.DropService)
local EconomyService = require(script.Parent.EconomyService)
local GiftService = require(script.Parent.GiftService)
local LockService = require(script.Parent.LockService)
local Replication = require(script.Parent.Replication)
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

-- A mutation id typed in chat, matched case-insensitively ("/spawn pizza_pup Golden").
local function mutationId(text: string): string?
	for id in GameData.catalog.mutations do
		if string.lower(id) == string.lower(text) then
			return id
		end
	end
	return nil
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
		local variant: string? = nil
		if mutationArg then
			variant = mutationId(mutationArg)
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
	add("gallery", function(player: Player, args: { string })
		local arg = args[1]
		if arg and string.lower(arg) == "off" then
			DevGallery.clear()
			Remotes.notify(player, "[Studio] gallery removed", "info")
			return
		end
		local variant = if arg then mutationId(arg) else nil
		if arg and variant == nil then
			Remotes.notify(player, `[Studio] unknown mutation {arg}`, "error")
			return
		end
		local view, count = DevGallery.build(GameData.mutation(variant))
		local character = player.Character
		if character then
			character:PivotTo(view)
		end
		Remotes.notify(player, `[Studio] gallery: {count} Snacklings{if variant then ` ({variant})` else ""}`, "info")
	end)
	add("sky", function(player: Player, args: { string })
		local clockTime = tonumber(args[1])
		if clockTime and clockTime >= 0 and clockTime <= 24 then
			Lighting.ClockTime = clockTime
			Remotes.notify(player, `[Studio] ClockTime {clockTime}`, "info")
		else
			Remotes.notify(player, "[Studio] /sky <0-24>", "error")
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
	add("playtime", function(player: Player, args: { string })
		local session = Sessions.get(player)
		local minutes = tonumber(args[1])
		if session and minutes and minutes > 0 and minutes <= 24 * 60 then
			GiftService.addPlaytime(session, minutes * 60)
			Replication.markDirty(session)
			Remotes.notify(player, `[Studio] +{minutes} min of playtime today`, "info")
		end
	end)
	add("spins", function(player: Player, args: { string })
		local session = Sessions.get(player)
		if session == nil then
			return
		end
		if args[1] == "free" then
			session.data.spin.nextFreeAt = 0
		else
			local count = tonumber(args[1])
			if count == nil or count < 1 or count > 100 then
				Remotes.notify(player, "[Studio] usage: /spins <n> | /spins free", "error")
				return
			end
			session.data.spin.spins += math.floor(count)
		end
		Replication.markDirty(session)
		Remotes.notify(player, "[Studio] spins updated", "info")
	end)
	add("runaway", function(player: Player, args: { string })
		local session = Sessions.get(player)
		local root = if session then Sessions.rootPart(session) else nil
		local here = args[1] == "here" and root ~= nil
		local at = if here and root then root.Position + root.CFrame.LookVector * 6 else nil
		if DropService.releaseRunaway(at) == nil then
			Remotes.notify(player, "[Studio] no Snackling could escape", "error")
		end
	end)
	print(
		"[DevCommands] Studio commands enabled: /cash <n>, /spawn <creatureId> [mutationId], /noshield, /friends <n|off>,"
			.. " /tutorial, /gallery [mutationId|off], /sky <clockTime>,"
			.. " /quests reset, /dex fill <rarity|event>, /map <id|vote|list>, /playtime <min>, /spins <n|free>,"
			.. " /runaway [here]"
			.. " (LiveOps: /event <id> [minutes], /event off, /luck <x> <min>)"
	)
end

return DevCommands
