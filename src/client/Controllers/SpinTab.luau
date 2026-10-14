--!strict
--[[
	The Rewards panel's Spin tab (the Lucky Spin; server: SpinService, config: Config/Spin): a reel of prize tiles
	under a gold marker, a SPIN! button and when the next free spin comes. The server picks the prize; when its answer
	(SpinResult) arrives the reel spins and slows down onto that tile, then the prize shows as a toast. If the panel was
	closed meanwhile, the toast shows at once. "Odds" lists every prize's chance.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Spin = require(ReplicatedStorage.Shared.Config.Spin)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local Net = require(ReplicatedStorage.Shared.Net)
local Types = require(ReplicatedStorage.Shared.Types)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
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

type Built = {
	reel: Frame,
	strip: Frame,
	button: TextButton,
	status: TextLabel,
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

local function oddsText(): string
	local parts: { string } = {}
	for index, chance in SpinRules.chances(Spin.segments) do
		table.insert(parts, `{Spin.segments[index].label} {Format.percent(chance)}`)
	end
	return `{Theme.text.spinOdds}: {table.concat(parts, " · ")}`
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
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.new(0, 4, 1, 0),
		BackgroundColor3 = UiTheme.palette("gold"),
		ZIndex = 3,
		Parent = reel,
	})
	local status = UiKit.label({
		Name = "Status",
		Text = "",
		FontFace = UiTheme.bodyFont,
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.fromOffset(0, REEL_HEIGHT + 72),
		TextColor3 = UiTheme.palette("textDim"),
		Parent = content,
	})
	local button = UiKit.button({
		Name = "Spin",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, REEL_HEIGHT + 10),
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
		SoundPlayer.ui("open")
		Net.get("Spin"):FireServer()
		-- Unlocks itself if the server never answers (a refused spin).
		task.delay(SPIN_SECONDS + 2, function()
			if built == current then
				current.spinning = false
			end
		end)
	end)
	UiKit.button({
		Name = "Odds",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -4, 0, REEL_HEIGHT + 20),
		Size = UDim2.fromOffset(84, 36),
		BackgroundColor3 = UiTheme.palette("panelLight"),
		Text = Theme.text.spinOdds,
		Parent = content,
	}, function()
		NotificationController.toast(oddsText(), "info")
	end)

	local state = StateStore.get()
	fill(strip, if state then state.spin.rewards else {}, nil, 1)
	built = { reel = reel, strip = strip, button = button, status = status, spinning = false }

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
