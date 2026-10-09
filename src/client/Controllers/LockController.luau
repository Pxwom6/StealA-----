--!strict
--[[
	Base-lock UI: the in-world lock button prompt and status board on YOUR base, plus a HUD pill that always
	shows lock state ("Lock ready" / "Locked 0:42" / "Lock in 0:30"). Tapping the pill while the lock recharges
	calls `onPillTappedWhileRecharging` (the store uses it to offer Instant Lock).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local Net = require(ReplicatedStorage.Shared.Net)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
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
			text = Format.template(Theme.text.lockPillToken, { count = state.lockTokens })
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
		elseif state.lockCooldownUntil > now and state.lockTokens <= 0 then
			label.Text =
				Format.template(Theme.text.lockButtonCooldown, { time = Format.clock(state.lockCooldownUntil - now) })
		else
			label.Text = Theme.text.lockButtonReady
		end
	end
end

function LockController.start()
	pill = UiKit.button({
		Name = "LockPill",
		LayoutOrder = 4,
		Size = UDim2.fromOffset(210, 34),
		BackgroundColor3 = UiTheme.palette("success"),
		Parent = HudController.topStack(),
	}, function()
		local view = describe()
		if view.recharging then
			LockController.onPillTappedWhileRecharging()
		else
			NotificationController.toast(Theme.text.lockAction .. ": " .. view.text, "info")
		end
	end)
	pillLabel = UiKit.label({ Size = UDim2.fromScale(1, 1), Parent = pill })

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
