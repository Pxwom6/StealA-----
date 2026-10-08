--!strict
--[[
	Rebirth dialog. Shows the exact trade-off before anything happens:
	  YOU LOSE          all cash, every Snackling (and their cash/sec)
	  YOU KEEP FOREVER  earnings multiplier x1.5 → x2, base lock 60s → 65s; podiums, passes and stats stay
	plus a progress bar to the requirement. Confirming takes two taps (young audience: no accidental resets).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local Net = require(ReplicatedStorage.Shared.Net)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local RebirthMath = require(ReplicatedStorage.Shared.Logic.RebirthMath)
local Modal = require(script.Parent.Parent.UI.Modal)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local HudController = require(script.Parent.HudController)
local NotificationController = require(script.Parent.NotificationController)
local SoundPlayer = require(script.Parent.SoundPlayer)
local StateStore = require(script.Parent.StateStore)

local RebirthController = {}

local CFG = Economy.rebirth

local sideButton: HudController.SideButton

local function previewFor(state: StateStore.ClientState): RebirthMath.Preview
	local baseLock = state.lockDuration - RebirthMath.lockBonusFor(state.rebirths, CFG)
	return RebirthMath.preview({
		cash = state.cash,
		rebirths = state.rebirths,
		rebirthMultiplier = state.rebirthMultiplier,
		creatureCount = state.creatureCount,
		incomePerSecond = state.income,
		baseLockSeconds = baseLock,
	}, CFG)
end

local function row(parent: Instance, order: number, text: string, color: Color3?): TextLabel
	return UiKit.label({
		LayoutOrder = order,
		Text = text,
		Size = UDim2.new(1, 0, 0, 30),
		TextColor3 = color or UiTheme.palette("text"),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = parent,
	})
end

local function column(parent: Instance, title: string, color: Color3, position: UDim2): Frame
	local frame = UiKit.panel({
		Size = UDim2.new(0.5, -6, 0, 200),
		Position = position,
		BackgroundColor3 = UiTheme.palette("panelLight"),
		Parent = parent,
	})
	UiKit.padding(10).Parent = frame
	UiKit.new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4), Parent = frame })
	row(frame, 0, title, color)
	return frame
end

function RebirthController.open()
	local state = StateStore.get()
	if state == nil then
		return
	end
	local preview = previewFor(state)
	local modal = Modal.open(Theme.text.rebirthTitle, Vector2.new(560, 400))
	local body = modal.body

	local lose = column(body, Theme.text.rebirthLose, UiTheme.palette("danger"), UDim2.fromOffset(0, 0))
	row(lose, 1, Format.template(Theme.text.rebirthLoseCash, { amount = UiTheme.cash(preview.loseCash) }))
	row(
		lose,
		2,
		Format.template(Theme.text.rebirthLoseCreatures, {
			count = preview.loseCreatures,
			income = UiTheme.cash(preview.loseIncomePerSecond),
		})
	)

	local gain = column(body, Theme.text.rebirthGain, UiTheme.palette("success"), UDim2.new(0.5, 6, 0, 0))
	row(
		gain,
		1,
		Format.template(Theme.text.rebirthGainMultiplier, {
			from = Format.number(preview.multiplierFrom),
			to = Format.number(preview.multiplierTo),
		}),
		UiTheme.palette("gold")
	)
	row(
		gain,
		2,
		Format.template(Theme.text.rebirthGainLock, { from = preview.lockFrom, to = preview.lockTo }),
		UiTheme.palette("lock")
	)
	local keepRow = row(gain, 3, Theme.text.rebirthKeep, UiTheme.palette("textDim"))
	keepRow.Size = UDim2.new(1, 0, 0, 44)
	keepRow.TextWrapped = true

	-- Requirement progress bar
	local cost = preview.cost
	local progress = if cost and cost > 0 then math.clamp(state.cash / cost, 0, 1) else 1
	local bar = UiKit.panel({
		Position = UDim2.fromOffset(0, 212),
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundColor3 = UiTheme.palette("stroke"),
		Parent = body,
	})
	local fill = UiKit.new("Frame", {
		Size = UDim2.fromScale(progress, 1),
		BackgroundColor3 = UiTheme.palette("success"),
		Parent = bar,
	}) :: Frame
	UiKit.corner(18).Parent = fill
	UiKit.label({
		Size = UDim2.fromScale(1, 1),
		Text = if cost
			then `{UiTheme.cash(math.min(state.cash, cost))} / {UiTheme.cash(cost)}`
			else Theme.text.rebirthMax,
		ZIndex = 3,
		Parent = bar,
	})

	local armed = false
	local confirm: TextButton
	confirm = UiKit.button({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromOffset(260, 60),
		BackgroundColor3 = if preview.canRebirth then UiTheme.palette("primary") else UiTheme.palette("panelLight"),
		Text = if preview.canRebirth
			then Theme.text.rebirthConfirm
			elseif cost then Format.template(Theme.text.rebirthNeed, { amount = UiTheme.cash(cost) })
			else Theme.text.rebirthMax,
		Parent = body,
	}, function()
		if not preview.canRebirth then
			SoundPlayer.ui("error")
			return
		end
		if not armed then
			armed = true
			confirm.Text = "Tap again to confirm!"
			confirm.BackgroundColor3 = UiTheme.palette("danger")
			task.delay(3, function()
				if armed and modal.isOpen() then
					armed = false
					confirm.Text = Theme.text.rebirthConfirm
					confirm.BackgroundColor3 = UiTheme.palette("primary")
				end
			end)
			return
		end
		Net.get("Rebirth"):FireServer()
		modal.close()
	end)
end

function RebirthController.start()
	sideButton = HudController.addSideButton(
		2,
		"♻️",
		Theme.text.rebirthButton,
		UiTheme.palette("secondary"),
		function()
			SoundPlayer.ui("click")
			RebirthController.open()
		end
	)
	StateStore.onChange(function(state)
		sideButton.badge.Visible = state.rebirthCost >= 0 and state.cash >= state.rebirthCost
	end)
	Net.get("Effect").OnClientEvent:Connect(function(payload: { kind: string, position: Vector3? })
		if payload.kind == "rebirth" and payload.position then
			NotificationController.sparkle(payload.position, UiTheme.palette("gold"))
			SoundPlayer.world("rebirth")
		end
	end)
end

return RebirthController
