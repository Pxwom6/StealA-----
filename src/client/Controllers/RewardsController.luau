--!strict
--[[
	Retention UI:
	  * "Welcome back — you earned X" popup after offline earnings
	  * Daily streak: side button with a badge, a 7-day track, one-tap claim; opens itself once per session when
	    a reward is waiting (after the welcome popup)
	  * HUD pill for server luck boosts and live events, with countdown
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
local luckPill: Frame
local luckLabel: TextLabel
local autoOpenedDaily = false
local welcomeOpen = false

function RewardsController.openDaily()
	local state = StateStore.get()
	if state == nil then
		return
	end
	local daily = state.daily
	local modal = Modal.open(Theme.text.dailyTitle, Vector2.new(600, 330))
	local track = UiKit.new("Frame", {
		Size = UDim2.new(1, 0, 0, 150),
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
		Position = UDim2.fromOffset(0, 160),
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
		Size = UDim2.new(1, 0, 0, 44),
		Position = UDim2.fromOffset(0, 92),
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

local function updateLuckPill()
	local multiplier = workspace:GetAttribute("LuckMultiplier")
	local endsAt = workspace:GetAttribute("LuckEndsAt")
	local banner = workspace:GetAttribute("EventBanner")
	local now = workspace:GetServerTimeNow()
	local hasLuck = type(multiplier) == "number" and multiplier > 1
	local hasBanner = type(banner) == "string" and banner ~= ""
	luckPill.Visible = hasLuck or hasBanner
	if hasLuck then
		local remaining = if type(endsAt) == "number" then math.max(0, endsAt - now) else 0
		luckLabel.Text = Format.template(Theme.text.luckBanner, {
			multiplier = Format.number(multiplier :: number),
			time = Format.clock(remaining),
		})
	elseif hasBanner then
		luckLabel.Text = banner :: string
	end
end

function RewardsController.start()
	dailyButton = HudController.addSideButton(3, "🎁", Theme.text.dailyButton, UiTheme.palette("gold"), function()
		SoundPlayer.ui("click")
		RewardsController.openDaily()
	end)

	luckPill = UiKit.panel({
		Name = "LuckPill",
		LayoutOrder = 3,
		Size = UDim2.fromOffset(230, 32),
		BackgroundColor3 = UiTheme.palette("luck"),
		Visible = false,
		Parent = HudController.topStack(),
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
			updateLuckPill()
			task.wait(0.5)
		end
	end)
end

return RewardsController
