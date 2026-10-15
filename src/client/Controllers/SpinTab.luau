--!strict
--[[
	The Rewards panel's Spin tab (the Lucky Spin; server: SpinService, config: Config/Spin): a reel of prize tiles
	under a gold marker, a SPIN! button and when the next free spin comes. The server picks the prize; when its answer
	(SpinResult) arrives the reel spins and slows down onto that tile, then the prize shows as a toast (above the
	dialog: NotificationController). If the panel was closed meanwhile, the toast shows at once.

	"Odds" swaps the reel for a grid of every prize with its exact chance (readable at a glance, unlike a toast), and
	"Back" returns. While the base is full a warning says Snackling prizes will be sold.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Spin = require(ReplicatedStorage.Shared.Config.Spin)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local Net = require(ReplicatedStorage.Shared.Net)
local Types = require(ReplicatedStorage.Shared.Types)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local ScreenLayout = require(ReplicatedStorage.Shared.Logic.ScreenLayout)
local SpinRules = require(ReplicatedStorage.Shared.Logic.SpinRules)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local NotificationController = require(script.Parent.NotificationController)
local SoundPlayer = require(script.Parent.SoundPlayer)
local StateStore = require(script.Parent.StateStore)

local SpinTab = {}

local REEL_HEIGHT = 112
local TILE = 100
local TILE_GAP = 8
local PITCH = TILE + TILE_GAP
local STRIP_TILES = 34 -- the winner sits near the end, so the reel runs a good way first
local SPIN_SECONDS = 3.6 -- under SpinService.REEL_SECONDS
local BUTTON_ROW = REEL_HEIGHT + 10 -- the SPIN! button, the Odds button and the base-full warning
local ODDS_SIZE = Vector2.new(100, 52) -- a full 44 px touch target on phones
-- The base-full warning, left of the SPIN! button (tests/ScreenLayout.spec keeps its text readable).
local WARNING = ScreenLayout.TEXT.prizesBaseFull.spin
local ODDS_COLUMNS = 4
local ODDS_GAP = 6

type Built = {
	reel: Frame,
	strip: Frame,
	odds: Frame,
	oddsButton: TextButton,
	button: TextButton,
	status: TextLabel,
	warning: TextLabel,
	spinning: boolean,
}

local built: Built? = nil
local random = Random.new()

local function tile(segment: Types.SpinSegment, cash: number, order: number, parent: Instance): Frame
	local frame = UiKit.panel({
		Name = segment.id,
		LayoutOrder = order,
		Size = UDim2.fromOffset(TILE, TILE),
		BackgroundColor3 = UiTheme.color(segment.color),
		Parent = parent,
	})
	UiKit.label({
		Name = "Icon",
		Text = segment.icon,
		Size = UDim2.new(1, 0, 0, 44),
		Position = UDim2.fromOffset(0, 6),
		Parent = frame,
	})
	UiKit.label({
		Name = "Label",
		Text = if cash > 0 then UiTheme.cash(cash) else segment.label,
		Size = UDim2.new(1, -8, 0, 30),
		Position = UDim2.fromOffset(4, 56),
		Parent = frame,
	})
	return frame
end

-- Fills the strip with tiles: `winner` (an index into Spin.segments) at `at`, random ones elsewhere.
local function fill(strip: Frame, rewards: { number }, winner: number?, at: number)
	for _, child in strip:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local chances = SpinRules.chances(Spin.segments)
	for order = 1, STRIP_TILES do
		local index: number
		if order == at and winner then
			index = winner
		else
			-- Weighted like the real odds, so rare prizes look rare on the reel too.
			local roll, running = random:NextNumber(), 0
			index = #Spin.segments
			for candidate, chance in chances do
				running += chance
				if roll < running then
					index = candidate
					break
				end
			end
		end
		tile(Spin.segments[index], rewards[index] or 0, order, strip)
	end
end

-- The strip's X that puts tile `at`'s centre (plus `jitter` px) under the marker.
local function stripX(reelWidth: number, at: number, jitter: number): number
	return reelWidth / 2 - ((at - 1) * PITCH + TILE / 2) - jitter
end

-- Every prize with its exact chance, in a grid over the reel's place.
local function buildOdds(content: Frame): Frame
	local odds = UiKit.panel({
		Name = "Odds",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 2),
		Size = UDim2.new(1, -8, 0, REEL_HEIGHT),
		BackgroundColor3 = UiTheme.palette("stroke"),
		Visible = false,
		ZIndex = 4,
		Parent = content,
	})
	local count = #Spin.segments
	local rows = math.max(1, math.ceil(count / ODDS_COLUMNS))
	local cellWidth = UDim.new(1 / ODDS_COLUMNS, -ODDS_GAP * (ODDS_COLUMNS + 1) / ODDS_COLUMNS)
	local cellHeight = (REEL_HEIGHT - ODDS_GAP * (rows + 1)) / rows
	for index, chance in SpinRules.chances(Spin.segments) do
		local segment = Spin.segments[index]
		local column = (index - 1) % ODDS_COLUMNS
		local row = (index - 1) // ODDS_COLUMNS
		local cell = UiKit.new("Frame", {
			Name = segment.id,
			-- Columns `gap` apart and from the edges: x = gap + column * (cell width + gap).
			Position = UDim2.new(
				column / ODDS_COLUMNS,
				ODDS_GAP - column * ODDS_GAP / ODDS_COLUMNS,
				0,
				ODDS_GAP + row * (cellHeight + ODDS_GAP)
			),
			Size = UDim2.new(cellWidth.Scale, cellWidth.Offset, 0, cellHeight),
			BackgroundColor3 = UiTheme.color(segment.color),
			ZIndex = 5,
			Parent = odds,
		}) :: Frame
		UiKit.corner(UiKit.RADIUS.small).Parent = cell
		UiKit.label({
			Name = "Prize",
			Text = `{segment.icon} {segment.label}`,
			Size = UDim2.new(1, -8, 0.52, 0),
			Position = UDim2.fromOffset(4, 2),
			ZIndex = 6,
			Parent = cell,
		})
		UiKit.label({
			Name = "Chance",
			Text = Format.percent(chance),
			Size = UDim2.new(1, -8, 0.42, 0),
			Position = UDim2.new(0, 4, 0.55, 0),
			ZIndex = 6,
			Parent = cell,
		})
	end
	return odds
end

local function showOdds(current: Built, shown: boolean)
	current.odds.Visible = shown
	UiKit.setButtonText(current.oddsButton, if shown then Theme.text.spinOddsBack else Theme.text.spinOdds)
end

-- Builds the tab into `content`; returns its refresh.
function SpinTab.build(content: Frame): (state: Types.ClientState) -> ()
	local reel = UiKit.panel({
		Name = "Reel",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 2),
		Size = UDim2.new(1, -8, 0, REEL_HEIGHT),
		BackgroundColor3 = UiTheme.palette("stroke"),
		ClipsDescendants = true,
		Parent = content,
	})
	local strip = UiKit.new("Frame", {
		Name = "Strip",
		Position = UDim2.fromOffset(0, (REEL_HEIGHT - TILE) / 2),
		Size = UDim2.fromOffset(STRIP_TILES * PITCH, TILE),
		BackgroundTransparency = 1,
		Parent = reel,
	}) :: Frame
	UiKit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, TILE_GAP),
		Parent = strip,
	})
	UiKit.new("Frame", {
		Name = "Marker",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(0, 4, 1, 0),
		BackgroundColor3 = UiTheme.palette("gold"),
		ZIndex = 3,
		Parent = reel,
	})
	local odds = buildOdds(content)
	local status = UiKit.label({
		Name = "Status",
		Text = "",
		FontFace = UiTheme.bodyFont,
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.fromOffset(0, REEL_HEIGHT + 72),
		TextColor3 = UiTheme.palette("textDim"),
		Parent = content,
	})
	local warning = UiKit.label({
		Name = "BaseFull",
		Text = Theme.text.prizesBaseFull,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(4, BUTTON_ROW),
		Size = UDim2.fromOffset(WARNING.w, WARNING.h),
		TextColor3 = UiTheme.palette("danger"),
		Visible = false,
		Parent = content,
	})
	local button = UiKit.button({
		Name = "Spin",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, BUTTON_ROW),
		Size = UDim2.fromOffset(240, 56),
		BackgroundColor3 = UiTheme.palette("panel"),
		Text = Theme.text.spinButton,
		Parent = content,
	}, function()
		local current = built
		local latest = StateStore.get()
		if current == nil or current.spinning or latest == nil then
			return
		end
		if not latest.spin.ready then
			NotificationController.toast(Theme.text.spinNotReady, "info")
			return
		end
		current.spinning = true
		showOdds(current, false)
		SoundPlayer.ui("open")
		Net.get("Spin"):FireServer()
		-- Unlocks itself if the server never answers (a refused spin).
		task.delay(SPIN_SECONDS + 2, function()
			if built == current then
				current.spinning = false
			end
		end)
	end)
	local oddsButton = UiKit.button({
		Name = "OddsButton",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -4, 0, BUTTON_ROW + 2),
		Size = UDim2.fromOffset(ODDS_SIZE.X, ODDS_SIZE.Y),
		BackgroundColor3 = UiTheme.palette("panelLight"),
		Text = Theme.text.spinOdds,
		Parent = content,
	}, function()
		local current = built
		if current then
			showOdds(current, not current.odds.Visible)
		end
	end)

	local state = StateStore.get()
	fill(strip, if state then state.spin.rewards else {}, nil, 1)
	built = {
		reel = reel,
		strip = strip,
		odds = odds,
		oddsButton = oddsButton,
		button = button,
		status = status,
		warning = warning,
		spinning = false,
	}

	return function(latest: Types.ClientState)
		local view = latest.spin
		local current = built
		if current == nil then
			return
		end
		local now = workspace:GetServerTimeNow()
		local freeReady = now >= view.nextFreeAt
		current.button.BackgroundColor3 = if view.ready and not current.spinning
			then UiTheme.palette("success")
			else UiTheme.palette("panel")
		UiKit.setButtonText(
			current.button,
			if not freeReady and view.spins > 0
				then Format.template(Theme.text.spinButtonBanked, { count = view.spins })
				else Theme.text.spinButton
		)
		local free = if freeReady
			then ""
			else Format.template(Theme.text.spinFreeIn, { time = Format.clock(view.nextFreeAt - now) })
		local banked = if view.spins > 0 then Format.template(Theme.text.spinBanked, { count = view.spins }) else ""
		current.status.Text = if free ~= "" and banked ~= "" then `{free} · {banked}` else free .. banked
		current.warning.Visible = latest.baseFull
	end
end

-- Forgets the built tab (the panel closed or switched tabs).
function SpinTab.clear()
	built = nil
end

local function onResult(payload: { index: number, text: string })
	local current = built
	local index = payload.index
	if current == nil or current.reel.Parent == nil or Spin.segments[index] == nil then
		if built and built.reel.Parent == nil then
			built = nil
		end
		NotificationController.toast(payload.text, "success")
		SoundPlayer.ui("claim")
		return
	end
	current.spinning = true
	showOdds(current, false) -- the reel shows the prize
	local state = StateStore.get()
	local at = STRIP_TILES - 3
	fill(current.strip, if state then state.spin.rewards else {}, index, at)
	local width = current.reel.AbsoluteSize.X / math.max(0.01, UiKit.scaleFor(workspace.CurrentCamera.ViewportSize))
	current.strip.Position = UDim2.fromOffset(stripX(width, 3, 0), (REEL_HEIGHT - TILE) / 2)
	local target = stripX(width, at, random:NextNumber(-TILE * 0.3, TILE * 0.3))
	local tween = TweenService:Create(
		current.strip,
		TweenInfo.new(SPIN_SECONDS, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Position = UDim2.fromOffset(target, (REEL_HEIGHT - TILE) / 2) }
	)
	tween.Completed:Once(function()
		NotificationController.toast(payload.text, "success")
		SoundPlayer.ui("claim")
		if built == current then
			current.spinning = false
		end
	end)
	tween:Play()
end

function SpinTab.start()
	Net.get("SpinResult").OnClientEvent:Connect(onResult)
end

return SpinTab
