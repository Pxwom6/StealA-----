--!strict
--[[
	Retention UI:
	  * "Welcome back — you earned X" popup after offline earnings
	  * Daily streak: side button with a badge, a 7-day track, one-tap claim; opens itself once per session when
	    a reward is waiting (after the welcome popup)
	  * HUD pills for live events (banner + "Halloween ends in 3d 4h", in the event's theme colour) and server luck
	    (multiplier + time until it next changes), from LiveOpsService's workspace attributes
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local Net = require(ReplicatedStorage.Shared.Net)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local DailyStreak = require(ReplicatedStorage.Shared.Logic.DailyStreak)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local Modal = require(script.Parent.Parent.UI.Modal)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local HudController = require(script.Parent.HudController)
local NotificationController = require(script.Parent.NotificationController)
local SoundPlayer = require(script.Parent.SoundPlayer)
local StateStore = require(script.Parent.StateStore)

local RewardsController = {}

local dailyButton: HudController.SideButton
local pillStack: Frame
local luckPill: Frame
local luckLabel: TextLabel
local eventPill: Frame
local eventLabel: TextLabel
local eventCountdown: TextLabel
local autoOpenedDaily = false
local welcomeOpen = false

function RewardsController.openDaily()
	local state = StateStore.get()
	if state == nil then
		return
	end
	local daily = state.daily
	local modal = Modal.open(Theme.text.dailyTitle, Vector2.new(600, 320))
	local track = UiKit.new("Frame", {
		Size = UDim2.new(1, 0, 0, 124),
		BackgroundTransparency = 1,
		Parent = modal.body,
	}) :: Frame
	UiKit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 6),
		Parent = track,
	})
	local cycle = #Economy.daily
	local currentSlot = DailyStreak.slot(daily.nextStreak, cycle)
	for slot = 1, cycle do
		local isNext = slot == currentSlot
		local claimedThisCycle = slot < currentSlot
		local cell = UiKit.panel({
			Size = UDim2.new(1 / cycle, -6, 1, 0),
			BackgroundColor3 = if isNext
				then UiTheme.palette("gold")
				elseif claimedThisCycle then UiTheme.palette("success")
				else UiTheme.palette("panelLight"),
			Parent = track,
		})
		UiKit.label({ Text = `Day {slot}`, Size = UDim2.fromScale(1, 0.3), Parent = cell })
		UiKit.label({
			Text = if claimedThisCycle then "✓" else "🎁",
			Size = UDim2.fromScale(1, 0.4),
			Position = UDim2.fromScale(0, 0.3),
			Parent = cell,
		})
		if isNext then
			UiKit.label({
				Text = UiTheme.cash(daily.reward),
				Size = UDim2.fromScale(1, 0.28),
				Position = UDim2.fromScale(0, 0.7),
				Parent = cell,
			})
		end
	end
	UiKit.label({
		Text = Format.template(Theme.text.dailyBody, { day = daily.streak }),
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.fromOffset(0, 130),
		TextColor3 = UiTheme.palette("textDim"),
		Parent = modal.body,
	})
	UiKit.button({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromOffset(260, 60),
		BackgroundColor3 = if daily.canClaim then UiTheme.palette("success") else UiTheme.palette("panelLight"),
		Text = if daily.canClaim
			then `{Theme.text.claim} {UiTheme.cash(daily.reward)}`
			else Format.clock(daily.secondsUntilNext),
		Parent = modal.body,
	}, function()
		if daily.canClaim then
			Net.get("ClaimDaily"):FireServer()
			SoundPlayer.ui("claim")
			modal.close()
		end
	end)
end

local function showWelcome(payload: { amount: number, seconds: number })
	welcomeOpen = true
	local modal = Modal.open(Theme.text.welcomeBackTitle, Vector2.new(480, 260), function()
		welcomeOpen = false
		local state = StateStore.get()
		if state and state.daily.canClaim and not autoOpenedDaily then
			autoOpenedDaily = true
			RewardsController.openDaily()
		end
	end)
	UiKit.label({
		Text = Format.template(Theme.text.welcomeBackBody, {
			amount = UiTheme.cash(payload.amount),
			duration = Format.duration(payload.seconds),
		}),
		FontFace = UiTheme.bodyFont,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 90),
		Parent = modal.body,
	})
	UiKit.label({
		Text = "+" .. UiTheme.cash(payload.amount),
		TextColor3 = UiTheme.palette("cash"),
		Size = UDim2.new(1, 0, 0, 40),
		Position = UDim2.fromOffset(0, 86),
		Parent = modal.body,
	})
	UiKit.button({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromOffset(220, 56),
		BackgroundColor3 = UiTheme.palette("success"),
		Text = Theme.text.ok,
		Parent = modal.body,
	}, modal.close)
	SoundPlayer.ui("claim")
end

-- "12:34" under an hour, "1d 6h" / "2h 15m" for long events.
local function countdown(seconds: number): string
	return if seconds < 3600 then Format.clock(seconds) else Format.duration(seconds)
end

local function updateLiveOpsPills()
	local now = workspace:GetServerTimeNow()

	local multiplier = workspace:GetAttribute("LuckMultiplier")
	local luckEndsAt = workspace:GetAttribute("LuckEndsAt")
	local hasLuck = type(multiplier) == "number" and multiplier > 1
	luckPill.Visible = hasLuck
	if hasLuck then
		local remaining = if type(luckEndsAt) == "number" then math.max(0, luckEndsAt - now) else 0
		luckLabel.Text = Format.template(Theme.text.luckBanner, {
			multiplier = Format.number(multiplier :: number),
			time = countdown(remaining),
		})
	end

	local banner = workspace:GetAttribute("EventBanner")
	local hasBanner = type(banner) == "string" and banner ~= ""
	eventPill.Visible = hasBanner
	if hasBanner then
		local bannerId = workspace:GetAttribute("EventBannerId")
		local title = workspace:GetAttribute("EventTitle")
		local endsAt = workspace:GetAttribute("EventEndsAt")
		eventLabel.Text = banner :: string
		eventPill.BackgroundColor3 = UiTheme.eventColor(if type(bannerId) == "string" then bannerId else nil)
		local remaining = if type(endsAt) == "number" then math.max(0, endsAt - now) else 0
		eventCountdown.Text = Format.template(Theme.text.eventEndsIn, {
			event = if type(title) == "string" and title ~= "" then title else Theme.text.eventFallbackTitle,
			time = Format.duration(remaining),
		})
	end
	pillStack.Visible = hasLuck or hasBanner
end

function RewardsController.start()
	dailyButton = HudController.addSideButton(3, "🎁", Theme.text.dailyButton, UiTheme.palette("gold"), function()
		SoundPlayer.ui("click")
		RewardsController.openDaily()
	end)

	-- LiveOps pills share one slot in the HUD's top stack: the event banner with its countdown, then server luck.
	pillStack = UiKit.new("Frame", {
		Name = "LiveOpsPills",
		LayoutOrder = 3,
		Size = UDim2.fromOffset(300, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Visible = false,
		Parent = HudController.topStack(),
	}) :: Frame
	UiKit.new("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 4),
		Parent = pillStack,
	})
	eventPill = UiKit.panel({
		Name = "EventPill",
		LayoutOrder = 1,
		Size = UDim2.fromOffset(290, 48),
		BackgroundColor3 = UiTheme.palette("event"),
		Visible = false,
		Parent = pillStack,
	})
	eventLabel = UiKit.label({
		Name = "Banner",
		Size = UDim2.new(1, -16, 0, 24),
		Position = UDim2.fromOffset(8, 3),
		Parent = eventPill,
	})
	eventCountdown = UiKit.label({
		Name = "Countdown",
		FontFace = UiTheme.bodyFont,
		Size = UDim2.new(1, -16, 0, 17),
		Position = UDim2.fromOffset(8, 27),
		Parent = eventPill,
	})
	luckPill = UiKit.panel({
		Name = "LuckPill",
		LayoutOrder = 2,
		Size = UDim2.fromOffset(230, 32),
		BackgroundColor3 = UiTheme.palette("luck"),
		Visible = false,
		Parent = pillStack,
	})
	luckLabel = UiKit.label({ Size = UDim2.new(1, -12, 1, -6), Position = UDim2.fromOffset(6, 3), Parent = luckPill })

	Net.get("WelcomeBack").OnClientEvent:Connect(showWelcome)
	StateStore.onChange(function(state)
		dailyButton.badge.Visible = state.daily.canClaim
		if state.daily.canClaim and not autoOpenedDaily and not welcomeOpen then
			-- Give the welcome popup a moment to arrive first.
			task.delay(2.5, function()
				local latest = StateStore.get()
				if latest and latest.daily.canClaim and not autoOpenedDaily and not welcomeOpen then
					autoOpenedDaily = true
					RewardsController.openDaily()
				end
			end)
		end
	end)
	Net.get("Effect").OnClientEvent:Connect(function(payload: { kind: string, position: Vector3? })
		if payload.kind == "daily" and payload.position then
			NotificationController.sparkle(payload.position, UiTheme.palette("gold"))
		end
	end)
	task.spawn(function()
		while true do
			updateLiveOpsPills()
			task.wait(0.5)
		end
	end)
end

return RewardsController
