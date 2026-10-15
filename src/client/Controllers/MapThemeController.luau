--!strict
--[[
	Map themes on the client (the server side is MapThemeService):

	  * The vote strip at the bottom of the screen while a vote runs, between the thumbstick and the jump button
	    (Logic/ScreenLayout.voteStrip; HudController places it): "Vote for the next map! 0:32" over one button per
	    candidate (icon, the name on up to two lines, its signature mutation, votes so far). Tapping one sends the
	    VoteMap intent; the player's pick is outlined and can be changed until the vote ends.
	  * The title card when the map changes: the map's icon, name, tagline and signature mutation ("Molten Snacklings
	    appear on this map!") drop in under the top stack for a few seconds (the server's "Welcome to ..."
	    announcement goes to chat only; see NotificationController).

	Everything comes from workspace attributes (MapTheme, MapVoteEndsAt, MapVoteCandidates, MapVoteCounts). The vote
	stays hidden during the first-time tutorial (and until the first state says there is none, so a new player never
	sees it flash), and while carrying a Snackling home (the carry banner is there then).
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
local ScreenLayout = require(ReplicatedStorage.Shared.Logic.ScreenLayout)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local HudController = require(script.Parent.HudController)
local SoundPlayer = require(script.Parent.SoundPlayer)
local StateStore = require(script.Parent.StateStore)

local MapThemeController = {}

local VOTE = ScreenLayout.SIZE.vote
local VOTE_TEXT = ScreenLayout.TEXT.vote
local TITLE = ScreenLayout.SIZE.titleCard
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

-- The vote waits while the first-time tutorial runs, until the first state arrives (a brand-new player joining
-- mid-vote would see it pop in with a sound, then vanish), and while carrying a Snackling home.
local function voteHidden(): boolean
	local state = StateStore.get()
	return state == nil or state.tutorial.step ~= "" or state.carrying ~= ""
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
	-- Equal shares of the strip, as Logic/ScreenLayout.voteChoice measures them.
	local count = math.max(1, #candidates)
	local share = UDim2.new(1 / count, -VOTE.choiceGap * (count - 1) / count, 1, 0)
	for index, id in candidates do
		local theme = MapThemes.themes[id]
		if theme == nil then
			continue
		end
		local button = UiKit.button({
			Name = id,
			LayoutOrder = index,
			Size = share,
			BackgroundColor3 = UiTheme.color(theme.accentColor),
			Parent = choices,
		}, function()
			vote(id)
		end)
		-- Narrow padding: the name gets the button's whole width (two lines, never under 12; tests/ScreenLayout.spec).
		local padding = button:FindFirstChildOfClass("UIPadding")
		if padding then
			padding.PaddingLeft = UDim.new(0, VOTE_TEXT.padX)
			padding.PaddingRight = UDim.new(0, VOTE_TEXT.padX)
			padding.PaddingTop = UDim.new(0, VOTE_TEXT.padY)
			padding.PaddingBottom = UDim.new(0, VOTE_TEXT.padY)
		end
		UiKit.label({
			Name = "Icon",
			Text = theme.icon,
			Size = UDim2.new(1, 0, 0, VOTE_TEXT.icon),
			Parent = button,
		})
		local name = UiKit.label({
			Name = "MapName",
			Text = theme.displayName,
			TextWrapped = true,
			Size = UDim2.new(1, 0, 0, VOTE_TEXT.name),
			Position = UDim2.fromOffset(0, VOTE_TEXT.icon),
			Parent = button,
		})
		UiKit.new("UITextSizeConstraint", {
			MinTextSize = ScreenLayout.TEXT.minSize,
			MaxTextSize = 18,
			Parent = name,
		})
		local signature = MutationRules.forMap(Mutations, id)
		if signature then
			UiKit.label({
				Name = "Mutation",
				Text = Format.template(Theme.text.mapVoteMutation, { mutation = signature.displayName }),
				Size = UDim2.new(1, 0, 0, VOTE_TEXT.mutation),
				Position = UDim2.fromOffset(0, VOTE_TEXT.icon + VOTE_TEXT.name),
				Parent = button,
			})
		end
		-- Votes so far, in the button's top-right corner.
		local badge = UiKit.new("Frame", {
			Name = "Votes",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 2, 0, -6),
			Size = UDim2.fromOffset(24, 22),
			BackgroundColor3 = UiTheme.palette("panel"),
			ZIndex = 2,
			Parent = button,
		}) :: Frame
		UiKit.corner(11).Parent = badge
		UiKit.stroke(2).Parent = badge
		UiKit.label({ Name = "Count", Text = "0", Size = UDim2.fromScale(1, 1), Parent = badge })
		UiKit.label({
			Name = "Check",
			Text = "✓",
			AnchorPoint = Vector2.new(0, 0),
			Position = UDim2.fromOffset(-2, -6),
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
	card.Visible = running and not voteHidden()
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
	-- Under the top stack, clear of the buttons beside it (Logic/ScreenLayout).
	local height = if signature then TITLE.h else 96
	local top = HudController.stackBottom() + ScreenLayout.GAP
	local x, width = HudController.overlaySpan(TITLE.w, height, top)
	local titleCard = UiKit.panel({
		Name = "MapTitleCard",
		Position = UDim2.fromOffset(x, top),
		Size = UDim2.fromOffset(width, height),
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
		Size = UDim2.fromOffset(VOTE.maxW, VOTE.header + VOTE.gap + VOTE.choice),
		BackgroundTransparency = 1,
		Visible = false,
	}) :: Frame
	header = UiKit.label({
		Name = "Header",
		Text = "",
		Size = UDim2.new(1, 0, 0, VOTE.header),
		TextColor3 = UiTheme.palette("gold"),
		Parent = card,
	})
	choices = UiKit.new("Frame", {
		Name = "Choices",
		Position = UDim2.fromOffset(0, VOTE.header + VOTE.gap),
		Size = UDim2.new(1, 0, 0, VOTE.choice),
		BackgroundTransparency = 1,
		Parent = card,
	}) :: Frame
	UiKit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, VOTE.choiceGap),
		Parent = choices,
	})
	HudController.place("vote", card)

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
