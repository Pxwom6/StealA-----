--!strict
--[[
	Map themes on the client (the server side is MapThemeService):

	  * The vote card, in the HUD's top stack while a vote runs: "Vote for the next map! 0:32" over one button per
	    candidate (icon, name, its signature mutation, votes so far). Tapping one sends the VoteMap intent; the player's
	    pick is outlined and can be changed until the vote ends.
	  * The title card when the map changes: the map's icon, name, tagline and signature mutation ("Molten Snacklings
	    appear on this map!") drop in under the top stack for a few seconds (the server's "Welcome to ..."
	    announcement goes to chat only; see NotificationController).

	Everything comes from workspace attributes (MapTheme, MapVoteEndsAt, MapVoteCandidates, MapVoteCounts). The vote card
	stays hidden during the first-time tutorial.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local MapThemes = require(ReplicatedStorage.Shared.Config.MapThemes)
local Mutations = require(ReplicatedStorage.Shared.Config.Mutations)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local Net = require(ReplicatedStorage.Shared.Net)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local MutationRules = require(ReplicatedStorage.Shared.Logic.MutationRules)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local HudController = require(script.Parent.HudController)
local SoundPlayer = require(script.Parent.SoundPlayer)
local StateStore = require(script.Parent.StateStore)

local MapThemeController = {}

local CARD_WIDTH = 290
local CHOICE_HEIGHT = 68
local CHOICE_GAP = 6
local TITLE_SECONDS = 4

local card: Frame
local header: TextLabel
local choices: Frame
local choiceButtons: { [string]: TextButton } = {}
local shownCandidates = ""
local myVote: string? = nil
local voteEndsAt = 0
local lastTheme: string? = nil

local function attribute(name: string): any
	return workspace:GetAttribute(name)
end

local function split(text: string): { string }
	local list: { string } = {}
	for item in string.gmatch(text, "[^,]+") do
		table.insert(list, item)
	end
	return list
end

local function inTutorial(): boolean
	local state = StateStore.get()
	return state ~= nil and state.tutorial.step ~= ""
end

local function vote(themeId: string)
	if myVote == themeId then
		return
	end
	myVote = themeId
	Net.get("VoteMap"):FireServer(themeId)
	for id, button in choiceButtons do
		local stroke = button:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = if id == themeId then UiTheme.palette("text") else UiTheme.palette("stroke")
			stroke.Thickness = if id == themeId then UiKit.STROKE.thick + 1 else UiKit.STROKE.normal
		end
		local check = button:FindFirstChild("Check")
		if check and check:IsA("GuiObject") then
			check.Visible = id == themeId
		end
	end
end

-- (Re)builds the buttons for a new ballot.
local function buildChoices(candidates: { string })
	for _, child in choices:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	choiceButtons = {}
	myVote = nil
	local width = (CARD_WIDTH - CHOICE_GAP * (#candidates - 1)) / math.max(1, #candidates)
	for index, id in candidates do
		local theme = MapThemes.themes[id]
		if theme == nil then
			continue
		end
		local button = UiKit.button({
			Name = id,
			LayoutOrder = index,
			Size = UDim2.fromOffset(width, CHOICE_HEIGHT),
			BackgroundColor3 = UiTheme.color(theme.accentColor),
			Parent = choices,
		}, function()
			vote(id)
		end)
		UiKit.label({
			Name = "Icon",
			Text = theme.icon,
			Size = UDim2.new(1, 0, 0, 24),
			Parent = button,
		})
		UiKit.label({
			Name = "MapName",
			Text = theme.displayName,
			Size = UDim2.new(1, 0, 0, 16),
			Position = UDim2.fromOffset(0, 26),
			Parent = button,
		})
		local signature = MutationRules.forMap(Mutations, id)
		if signature then
			UiKit.label({
				Name = "Mutation",
				Text = Format.template(Theme.text.mapVoteMutation, { mutation = signature.displayName }),
				Size = UDim2.new(1, -6, 0, 16),
				Position = UDim2.fromOffset(3, 46),
				Parent = button,
			})
		end
		local badge = UiKit.new("Frame", {
			Name = "Votes",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 8, 0, -12),
			Size = UDim2.fromOffset(24, 22),
			BackgroundColor3 = UiTheme.palette("panel"),
			Parent = button,
		}) :: Frame
		UiKit.corner(11).Parent = badge
		UiKit.stroke(2).Parent = badge
		UiKit.label({ Name = "Count", Text = "0", Size = UDim2.fromScale(1, 1), Parent = badge })
		UiKit.label({
			Name = "Check",
			Text = "✓",
			AnchorPoint = Vector2.new(0, 0),
			Position = UDim2.fromOffset(-10, -12),
			Size = UDim2.fromOffset(22, 22),
			TextColor3 = UiTheme.palette("success"),
			Visible = false,
			Parent = button,
		})
		choiceButtons[id] = button
	end
end

local function refreshCounts(candidates: { string })
	local counts = split(tostring(attribute("MapVoteCounts") or ""))
	for index, id in candidates do
		local button = choiceButtons[id]
		local badge = button and button:FindFirstChild("Votes")
		local count = badge and badge:FindFirstChild("Count")
		if count and count:IsA("TextLabel") then
			count.Text = Format.template(Theme.text.mapVoteCount, { votes = counts[index] or "0" })
		end
	end
end

local function refreshVote()
	local endsAt = attribute("MapVoteEndsAt")
	local candidatesText = attribute("MapVoteCandidates")
	local running = type(endsAt) == "number"
		and endsAt > workspace:GetServerTimeNow()
		and type(candidatesText) == "string"
		and candidatesText ~= ""
	voteEndsAt = if running then endsAt :: number else 0
	local wasVisible = card.Visible
	card.Visible = running and not inTutorial()
	if not running then
		shownCandidates = ""
		return
	end
	local candidates = split(candidatesText :: string)
	if candidatesText ~= shownCandidates then
		shownCandidates = candidatesText :: string
		buildChoices(candidates)
	end
	refreshCounts(candidates)
	if card.Visible and not wasVisible then
		UiKit.popIn(card)
		SoundPlayer.ui("open")
	end
end

local function updateCountdown()
	if card.Visible and voteEndsAt > 0 then
		local remaining = math.max(0, voteEndsAt - workspace:GetServerTimeNow())
		header.Text = Format.template(Theme.text.mapVoteTitle, { time = Format.clock(remaining) })
		if remaining <= 0 then
			refreshVote()
		end
	end
end

-- The new map's name drops in under the top stack, then fades away.
local function showTitleCard(themeId: string)
	local theme = MapThemes.themes[themeId]
	if theme == nil then
		return
	end
	local accent = UiTheme.color(theme.accentColor)
	local signature = MutationRules.forMap(Mutations, themeId)
	local screen = HudController.screen()
	local titleCard = UiKit.panel({
		Name = "MapTitleCard",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 150),
		Size = UDim2.fromOffset(400, if signature then 120 else 96),
		BackgroundColor3 = accent,
		Parent = screen,
	})
	UiKit.new("UIGradient", {
		Color = ColorSequence.new(accent, accent:Lerp(Color3.new(0, 0, 0), 0.35)),
		Rotation = 90,
		Parent = titleCard,
	})
	UiKit.label({
		Name = "Subtitle",
		Text = Theme.text.mapCardSubtitle,
		Size = UDim2.new(1, -20, 0, 18),
		Position = UDim2.fromOffset(10, 6),
		TextColor3 = UiTheme.palette("gold"),
		Parent = titleCard,
	})
	UiKit.label({
		Name = "Title",
		Text = `{theme.icon} {string.upper(theme.displayName)}`,
		Size = UDim2.new(1, -20, 0, 40),
		Position = UDim2.fromOffset(10, 24),
		Parent = titleCard,
	})
	UiKit.label({
		Name = "Tagline",
		Text = theme.tagline,
		FontFace = UiTheme.bodyFont,
		Size = UDim2.new(1, -20, 0, 20),
		Position = UDim2.fromOffset(10, 68),
		Parent = titleCard,
	})
	if signature then
		UiKit.label({
			Name = "Mutation",
			Text = Format.template(Theme.text.mapCardMutation, { mutation = signature.displayName }),
			Size = UDim2.new(1, -20, 0, 20),
			Position = UDim2.fromOffset(10, 92),
			TextColor3 = UiTheme.palette("gold"),
			Parent = titleCard,
		})
	end
	UiKit.popIn(titleCard)
	SoundPlayer.world("mapChange")
	task.delay(TITLE_SECONDS, function()
		if titleCard.Parent then
			UiKit.popOut(titleCard)
		end
	end)
end

local function onThemeChanged()
	local themeId = attribute("MapTheme")
	if type(themeId) ~= "string" then
		return
	end
	if lastTheme ~= nil and themeId ~= lastTheme then
		showTitleCard(themeId)
	end
	lastTheme = themeId
	refreshVote()
end

function MapThemeController.start()
	card = UiKit.new("Frame", {
		Name = "MapVote",
		LayoutOrder = HudController.TOP_ORDER.mapVote,
		Size = UDim2.fromOffset(CARD_WIDTH, 26 + CHOICE_HEIGHT + 8),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = HudController.topStack(),
	}) :: Frame
	header = UiKit.label({
		Name = "Header",
		Text = "",
		Size = UDim2.new(1, 0, 0, 22),
		TextColor3 = UiTheme.palette("gold"),
		Parent = card,
	})
	choices = UiKit.new("Frame", {
		Name = "Choices",
		Position = UDim2.fromOffset(0, 30),
		Size = UDim2.new(1, 0, 0, CHOICE_HEIGHT),
		BackgroundTransparency = 1,
		Parent = card,
	}) :: Frame
	UiKit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, CHOICE_GAP),
		Parent = choices,
	})

	for _, name in { "MapVoteEndsAt", "MapVoteCandidates", "MapVoteCounts" } do
		workspace:GetAttributeChangedSignal(name):Connect(refreshVote)
	end
	workspace:GetAttributeChangedSignal("MapTheme"):Connect(onThemeChanged)
	StateStore.onChange(function()
		refreshVote()
	end)
	onThemeChanged()
	task.spawn(function()
		while true do
			updateCountdown()
			task.wait(0.25)
		end
	end)
	-- The card's title pulses gently while the vote runs.
	TweenService:Create(header, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		TextTransparency = 0.15,
	}):Play()
end

return MapThemeController
