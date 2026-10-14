--!strict
--[[
	Map themes (Config/MapThemes): which map this server is on, and the vote for the next one.

	A server starts on MapThemeRules.firstMap (MapBuilder builds it dressed that way). With rotation on, the map
	changes every `rotation.mapSeconds`; for the last `rotation.voteSeconds` before that a vote runs on a few candidates
	(MapThemeRules.candidates, never the current map): one vote per player (the VoteMap intent; changing your mind is
	fine, only players still in the server count) and the winner (MapThemeRules.winner: most votes, a tie or no votes
	settled at random) becomes the map. The change itself is MapBuilder.restyle: the ground and walkway recoloured, the
	scenery rebuilt, the lighting faded. Nothing that plays changes, and nobody is moved.

	Clients read it all from workspace attributes: MapTheme (id), MapThemeEndsAt (server time of the next change; 0 =
	no rotation), MapVoteEndsAt (0 = no vote running), MapVoteCandidates ("candy,winter,desert") and MapVoteCounts
	("2,0,1").

	Commands, this server only: /map <id> switches now, /map vote starts a vote, /map list. Anyone in Studio; in live
	servers the admins in Config/LiveOps.adminUserIds.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local LiveOps = require(ReplicatedStorage.Shared.Config.LiveOps)
local MapThemes = require(ReplicatedStorage.Shared.Config.MapThemes)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local Guard = require(ReplicatedStorage.Shared.Logic.Guard)
local MapThemeRules = require(ReplicatedStorage.Shared.Logic.MapThemeRules)
local Analytics = require(script.Parent.Analytics)
local Announcer = require(script.Parent.Announcer)
local MapBuilder = require(script.Parent.MapBuilder)
local Remotes = require(script.Parent.Remotes)
local Sessions = require(script.Parent.Sessions)

local MapThemeService = {}

type Vote = { endsAt: number, candidates: { string }, votes: { [number]: string } }

local random = Random.new()
local current = MapThemes.order[1]
local switchAt = 0
local vote: Vote? = nil
local published = ""

local function nextRandom(): number
	return random:NextNumber()
end

local function now(): number
	return workspace:GetServerTimeNow()
end

-- The map a new server starts on. MapBuilder.build is called with it, then start() with the same id.
function MapThemeService.firstMap(): string
	return MapThemeRules.firstMap(MapThemes, nextRandom)
end

function MapThemeService.current(): string
	return current
end

-- Only votes of players still in the server count.
local function liveVotes(running: Vote): { [number]: string }
	local result: { [number]: string } = {}
	for userId, choice in running.votes do
		if Players:GetPlayerByUserId(userId) then
			result[userId] = choice
		end
	end
	return result
end

local function publish()
	local running = vote
	local counts: { number } = if running then MapThemeRules.counts(running.candidates, liveVotes(running)) else {}
	local countText: { string } = {}
	for _, count in counts do
		table.insert(countText, tostring(count))
	end
	local state = {
		theme = current,
		endsAt = if MapThemes.rotation.enabled or running then switchAt else 0,
		voteEndsAt = if running then running.endsAt else 0,
		candidates = if running then table.concat(running.candidates, ",") else "",
		counts = table.concat(countText, ","),
	}
	local key = `{state.theme}|{state.endsAt}|{state.voteEndsAt}|{state.candidates}|{state.counts}`
	if key == published then
		return
	end
	published = key
	workspace:SetAttribute("MapTheme", state.theme)
	workspace:SetAttribute("MapThemeEndsAt", state.endsAt)
	workspace:SetAttribute("MapVoteEndsAt", state.voteEndsAt)
	workspace:SetAttribute("MapVoteCandidates", state.candidates)
	workspace:SetAttribute("MapVoteCounts", state.counts)
end

-- Changes the map now (any vote running is dropped). `announce` shows the banner to everyone.
function MapThemeService.switchTo(themeId: string, announce: boolean)
	local theme = MapThemes.themes[themeId]
	if theme == nil then
		return
	end
	vote = nil
	switchAt = now() + MapThemes.rotation.mapSeconds
	if themeId ~= current then
		current = themeId
		local ok, err = pcall(MapBuilder.restyle, themeId, MapThemes.transitionSeconds)
		if not ok then
			warn(`[MapThemes] restyling as {themeId} failed: {err}`)
		end
		if announce then
			Announcer.broadcast({
				text = Format.template(Theme.text.mapChanged, { icon = theme.icon, map = theme.displayName }),
				color = theme.accentColor,
				kind = "map",
			})
		end
	end
	publish()
end

-- Starts a vote for the next map, ending in `seconds` (default rotation.voteSeconds), when the map changes.
function MapThemeService.openVote(seconds: number?)
	local candidates = MapThemeRules.candidates(MapThemes, current, MapThemes.rotation.candidates, nextRandom)
	if #candidates == 0 then
		return
	end
	local endsAt = now() + math.max(5, seconds or MapThemes.rotation.voteSeconds)
	vote = { endsAt = endsAt, candidates = candidates, votes = {} }
	switchAt = endsAt
	publish()
end

local function closeVote()
	local running = vote
	if running == nil then
		return
	end
	local winner = MapThemeRules.winner(running.candidates, liveVotes(running), nextRandom)
	vote = nil
	if winner then
		MapThemeService.switchTo(winner, true)
	else
		switchAt = now() + MapThemes.rotation.mapSeconds
		publish()
	end
end

local function step()
	local t = now()
	local running = vote
	if running then
		if t >= running.endsAt then
			closeVote()
		end
	elseif MapThemes.rotation.enabled and t >= MapThemeRules.voteOpensAt(switchAt, MapThemes.rotation) then
		MapThemeService.openVote(switchAt - t)
	end
	publish()
end

local function onVote(player: Player, choiceArg: unknown)
	local running = vote
	if running == nil then
		return
	end
	local choice = Guard.oneOf(choiceArg, running.candidates)
	if choice == nil then
		return
	end
	local first = running.votes[player.UserId] == nil
	running.votes[player.UserId] = choice
	publish()
	local session = Sessions.get(player)
	if session and first then
		Analytics.custom(session, "map_vote", table.find(running.candidates, choice), { choice, current })
	end
end

-- Chat commands ------------------------------------------------------------------------------------------------------

local function isAdmin(userId: number): boolean
	return RunService:IsStudio() or table.find(LiveOps.adminUserIds, userId) ~= nil
end

local function onCommand(player: Player, args: { string })
	local first = string.lower(args[1] or "")
	if first == "list" or first == "" then
		local names: { string } = {}
		for _, id in MapThemes.order do
			table.insert(names, if id == current then `[{id}]` else id)
		end
		Remotes.notify(player, `Maps: {table.concat(names, ", ")}`, "info")
	elseif first == "vote" then
		MapThemeService.openVote(if RunService:IsStudio() then 20 else nil)
		Remotes.notify(player, "Map vote started", "info")
	elseif MapThemes.themes[first] then
		MapThemeService.switchTo(first, true)
	else
		Remotes.notify(player, "Usage: /map <id> | /map vote | /map list", "error")
	end
end

local function addCommand()
	local command = Instance.new("TextChatCommand")
	command.Name = "MapThemes"
	command.PrimaryAlias = "/map"
	command.AutocompleteVisible = false
	command.Parent = TextChatService
	command.Triggered:Connect(function(source: TextSource, text: string)
		if not isAdmin(source.UserId) then
			return
		end
		local player = Players:GetPlayerByUserId(source.UserId)
		if player == nil then
			return
		end
		local args: { string } = {}
		for word in string.gmatch(text, "%S+") do
			table.insert(args, word)
		end
		table.remove(args, 1)
		onCommand(player, args)
	end)
end

-- Starts the rotation. `firstMap` is the map MapBuilder.build was dressed as.
function MapThemeService.start(firstMap: string)
	current = if MapThemes.themes[firstMap] then firstMap else MapThemes.order[1]
	switchAt = now() + MapThemes.rotation.mapSeconds
	publish()
	Remotes.onIntent("VoteMap", onVote)
	addCommand()
	task.spawn(function()
		while true do
			task.wait(1)
			local ok, err = pcall(step :: () -> ...any)
			if not ok then
				warn(`[MapThemes] {err}`)
			end
		end
	end)
end

return MapThemeService
