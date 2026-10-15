--!strict
--[[
	Base-lock UI: the in-world lock button prompt and status board on YOUR base, plus a HUD button that always
	shows lock state ("Lock ready" / "Locked 0:42" / "Lock in 0:30"), in the top-right row beside Friends and the gear
	(a full 44 px target, clear of the prompts in the middle of the screen; Logic/ScreenLayout). The HUD button can't
	lock: a tap says what to do (Logic/LockRules.pillTap): "Walk to the 🔒 button at your door" when the lock can be
	used, or "Lock ready in 1:12 · Instant Lock is in the Shop" while it recharges, and a second tap within a few
	seconds of that calls `onPillTappedWhileRecharging` (the store opens on Instant Lock). Never the Shop during the
	first-time tutorial.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local Net = require(ReplicatedStorage.Shared.Net)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local LockRules = require(ReplicatedStorage.Shared.Logic.LockRules)
local ScreenLayout = require(ReplicatedStorage.Shared.Logic.ScreenLayout)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local HudController = require(script.Parent.HudController)
local PlotController = require(script.Parent.PlotController)
local NotificationController = require(script.Parent.NotificationController)
local SoundPlayer = require(script.Parent.SoundPlayer)
local StateStore = require(script.Parent.StateStore)

local LockController = {}

local pill: TextButton
local pillLabel: TextLabel
local prompt: ProximityPrompt? = nil
local boardLabel: TextLabel? = nil
local wiredButton: BasePart? = nil
-- A second tap this soon (seconds) after the "recharging · Instant Lock is in the Shop" toast opens the Shop.
local SHOP_TAP_SECONDS = 4
local shopHintAt: number? = nil -- server time of that toast

LockController.onPillTappedWhileRecharging = function() end :: () -> ()

type LockView = { text: string, color: Color3, recharging: boolean }

local function describe(): LockView
	local state = StateStore.get()
	if state == nil then
		return { text = Theme.text.lockPillReady, color = UiTheme.palette("lock"), recharging = false }
	end
	local now = workspace:GetServerTimeNow()
	if state.lockedUntil > now then
		return {
			text = Format.template(Theme.text.lockPillLocked, { time = Format.clock(state.lockedUntil - now) }),
			color = UiTheme.palette("lock"),
			recharging = false,
		}
	elseif state.lockCooldownUntil > now then
		local text =
			Format.template(Theme.text.lockPillCooldown, { time = Format.clock(state.lockCooldownUntil - now) })
		if state.lockTokens > 0 then
			-- A token can skip the recharge, but never the open window right after a lock.
			text = if state.lockVulnerableUntil > now
				then Format.template(
					Theme.text.lockPillCooldown,
					{ time = Format.clock(state.lockVulnerableUntil - now) }
				)
				else Format.template(Theme.text.lockPillToken, { count = state.lockTokens })
		end
		return { text = text, color = UiTheme.palette("panelLight"), recharging = true }
	end
	return { text = Theme.text.lockPillReady, color = UiTheme.palette("success"), recharging = false }
end

local function wireLockButton()
	local plot = PlotController.myPlot()
	local button = plot and plot:FindFirstChild("LockButton")
	if button == nil or not button:IsA("BasePart") or button == wiredButton then
		return
	end
	if prompt then
		prompt:Destroy()
	end
	wiredButton = button
	local newPrompt = UiKit.new("ProximityPrompt", {
		Name = "LockPrompt",
		ActionText = Theme.text.lockAction,
		HoldDuration = 0,
		RequiresLineOfSight = false,
		MaxActivationDistance = 10,
		KeyboardKeyCode = Enum.KeyCode.E,
		Parent = button,
	}) :: ProximityPrompt
	newPrompt.Triggered:Connect(function()
		Net.get("LockBase"):FireServer()
	end)
	prompt = newPrompt
	local board = UiKit.new("BillboardGui", {
		Name = "LockBoard",
		Size = UDim2.fromOffset(170, 44),
		StudsOffsetWorldSpace = Vector3.new(0, 4, 0),
		MaxDistance = 80,
		LightInfluence = 0,
		Parent = button,
	}) :: BillboardGui
	boardLabel = UiKit.label({ Size = UDim2.fromScale(1, 1), Parent = board })
end

local function update()
	wireLockButton()
	local view = describe()
	pillLabel.Text = "🔒 " .. view.text
	pill.BackgroundColor3 = view.color
	local label = boardLabel
	local state = StateStore.get()
	if label and state then
		local now = workspace:GetServerTimeNow()
		if state.lockedUntil > now then
			label.Text = Format.template(Theme.text.lockButtonLocked, { time = Format.clock(state.lockedUntil - now) })
		elseif state.lockCooldownUntil > now and (state.lockTokens <= 0 or state.lockVulnerableUntil > now) then
			local readyAt = if state.lockTokens > 0 then state.lockVulnerableUntil else state.lockCooldownUntil
			label.Text = Format.template(Theme.text.lockButtonCooldown, { time = Format.clock(readyAt - now) })
		else
			label.Text = Theme.text.lockButtonReady
		end
	end
end

-- The HUD button was tapped: where to lock, how long it recharges, or (a second tap soon after) the Shop.
local function onPillTapped()
	local state = StateStore.get()
	if state == nil then
		return
	end
	local now = workspace:GetServerTimeNow()
	local tap = LockRules.pillTap({
		now = now,
		lockedUntil = state.lockedUntil,
		cooldownUntil = state.lockCooldownUntil,
		vulnerableUntil = state.lockVulnerableUntil,
		tokens = state.lockTokens,
		inTutorial = state.tutorial.step ~= "",
		lastHintAt = shopHintAt,
		repeatSeconds = SHOP_TAP_SECONDS,
	})
	shopHintAt = nil
	if tap.openShop then
		LockController.onPillTappedWhileRecharging()
	elseif tap.kind == "walk" then
		NotificationController.toast(Theme.text.lockPillWalk, "info")
	elseif tap.kind == "locked" then
		NotificationController.toast(Theme.text.lockAction .. ": " .. describe().text, "info")
	else
		local time = Format.clock(math.ceil(tap.seconds))
		if tap.shop then
			shopHintAt = now
			NotificationController.toast(Format.template(Theme.text.lockPillWaitShop, { time = time }), "info")
		else
			NotificationController.toast(Format.template(Theme.text.lockPillWait, { time = time }), "info")
		end
	end
end

function LockController.start()
	local corner = ScreenLayout.SIZE.corner
	pill = UiKit.button({
		Name = "LockButton",
		Size = UDim2.fromOffset(corner.lock, corner.button),
		BackgroundColor3 = UiTheme.palette("success"),
	}, onPillTapped)
	-- Two lines when it needs them ("🔒 Instant / lock x2"), so the text stays big.
	pillLabel = UiKit.label({ Size = UDim2.fromScale(1, 1), TextWrapped = true, Parent = pill })
	HudController.place("lock", pill)

	Net.get("Effect").OnClientEvent:Connect(function(payload: { kind: string, position: Vector3? })
		if payload.kind == "lock" and payload.position then
			NotificationController.sparkle(payload.position, UiTheme.palette("lock"))
			SoundPlayer.world("lock")
		end
	end)
	StateStore.onChange(function()
		update()
	end)
	task.spawn(function()
		while true do
			task.wait(0.25)
			update()
		end
	end)
end

return LockController
