--!strict
--[[
	The always-on HUD, laid out for thumbs on a landscape phone:

	  top centre    cash (animated count-up) + cash/sec, then the tutorial banner and status pills (event + luck, lock,
	                social) stacked below in TOP_ORDER, so nothing in the stack can overlap
	  left middle   feature buttons (Shop, Rebirth, Rewards, Snackdex) — other controllers add them, in LayoutOrder
	  right, above the jump button   contextual action area (e.g. the big TAG! button)

	Numbers count up instead of jumping so progress always feels alive, and the cash pill pulses on every change.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local StateStore = require(script.Parent.StateStore)

local HudController = {}

local screen: ScreenGui
local topStack: Frame
local sideColumn: Frame
local actionArea: Frame
local cashLabel: TextLabel
local incomeLabel: TextLabel
local cashPill: Frame

-- Left column (reference px): four 76x58 buttons with 6 px gaps are 250 tall, the same footprint as the three 74 px
-- buttons before (246). Centred at 42% of the height: at 667x375 (about 785x373 under the top bar, UI scale 0.85) the
-- column spans y 32-282 and x 10-86 (badges reach x 94), clear of the top stack (x >= 242), the tutorial banner
-- (x >= 182) and the movement thumbstick in the bottom-left corner. Keep it at most four buttons tall: a fifth feature
-- belongs in an existing panel (as the daily rewards and quests share Rewards).
local SIDE_BUTTON_SIZE = Vector2.new(76, 58)
local SIDE_BUTTON_GAP = 6

local displayedCash = 0
local targetCash = 0
local lastCash: number? = nil

function HudController.screen(): ScreenGui
	return screen
end

-- Slots in the top stack, top to bottom (LayoutOrder). Each controller adds its pill at its own slot.
HudController.TOP_ORDER = table.freeze({
	cash = 1,
	income = 2,
	tutorial = 3, -- right under the cash: where a new player looks first
	liveOps = 4, -- event banner + countdown, server luck
	lock = 5,
	social = 6,
})

-- Container below the cash readout for status pills (luck, lock...). Children sort by LayoutOrder (TOP_ORDER).
function HudController.topStack(): Frame
	return topStack
end

-- Bottom-right container above the jump button for big contextual buttons.
function HudController.actionArea(): Frame
	return actionArea
end

export type SideButton = { button: TextButton, badge: Frame }

-- Adds a feature button to the left column (`order`: 1 Shop, 2 Rebirth, 3 Rewards, 4 Snackdex). The badge is a red dot
-- for "something to claim / new".
function HudController.addSideButton(
	order: number,
	icon: string,
	caption: string,
	color: Color3,
	onTap: () -> ()
): SideButton
	local button = UiKit.button({
		Name = caption,
		LayoutOrder = order,
		Size = UDim2.fromOffset(SIDE_BUTTON_SIZE.X, SIDE_BUTTON_SIZE.Y),
		BackgroundColor3 = color,
		Text = "",
	}, onTap)
	UiKit.label({
		Name = "Icon",
		Text = icon,
		Size = UDim2.fromScale(1, 0.56),
		Parent = button,
	})
	UiKit.label({
		Name = "Caption",
		Text = caption,
		Size = UDim2.fromScale(1, 0.4),
		Position = UDim2.fromScale(0, 0.6),
		Parent = button,
	})
	local badge = UiKit.new("Frame", {
		Name = "Badge",
		Size = UDim2.fromOffset(20, 20),
		Position = UDim2.new(1, -12, 0, -8),
		BackgroundColor3 = UiTheme.palette("danger"),
		Visible = false,
		Parent = button,
	}) :: Frame
	UiKit.corner(10).Parent = badge
	UiKit.stroke(2).Parent = badge
	button.Parent = sideColumn
	return { button = button, badge = badge }
end

local function pulse(target: GuiObject, color: Color3)
	local scale = target:FindFirstChild("PulseScale") :: UIScale?
	if scale == nil then
		local newScale = UiKit.new("UIScale", { Name = "PulseScale", Parent = target }) :: UIScale
		scale = newScale
	end
	local s = scale :: UIScale
	s.Scale = 1.08
	TweenService:Create(s, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	cashLabel.TextColor3 = color
	TweenService:Create(cashLabel, TweenInfo.new(0.5), { TextColor3 = UiTheme.palette("text") }):Play()
end

local function build()
	screen = UiKit.screen("Hud", 1)

	topStack = UiKit.new("Frame", {
		Name = "TopStack",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.fromOffset(300, 280),
		BackgroundTransparency = 1,
		Parent = screen,
	}) :: Frame
	UiKit.new("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 4),
		Parent = topStack,
	})

	cashPill = UiKit.panel({
		Name = "Cash",
		LayoutOrder = HudController.TOP_ORDER.cash,
		Size = UDim2.fromOffset(250, 58),
		BackgroundColor3 = UiTheme.palette("panel"),
		Parent = topStack,
	})
	cashLabel = UiKit.label({
		Name = "Amount",
		Size = UDim2.new(1, -16, 1, -8),
		Position = UDim2.fromOffset(8, 4),
		Text = UiTheme.cash(0),
		Parent = cashPill,
	})
	incomeLabel = UiKit.label({
		Name = "Income",
		LayoutOrder = HudController.TOP_ORDER.income,
		Size = UDim2.fromOffset(250, 26),
		TextColor3 = UiTheme.palette("cash"),
		Text = UiTheme.perSecond(0),
		Parent = topStack,
	})

	sideColumn = UiKit.new("Frame", {
		Name = "SideColumn",
		AnchorPoint = Vector2.new(0, 0.5),
		-- Slightly above centre: the bottom-left of a phone belongs to the movement thumbstick.
		Position = UDim2.new(0, 10, 0.42, 0),
		Size = UDim2.fromOffset(80, 270),
		BackgroundTransparency = 1,
		Parent = screen,
	}) :: Frame
	UiKit.new("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, SIDE_BUTTON_GAP),
		Parent = sideColumn,
	})

	actionArea = UiKit.new("Frame", {
		Name = "ActionArea",
		AnchorPoint = Vector2.new(1, 1),
		-- Sits above/left of the mobile jump button.
		Position = UDim2.new(1, -24, 1, -170),
		Size = UDim2.fromOffset(150, 150),
		BackgroundTransparency = 1,
		Parent = screen,
	}) :: Frame
end

function HudController.start()
	build()
	StateStore.onChange(function(state)
		targetCash = state.cash
		incomeLabel.Text = UiTheme.perSecond(state.income)
		if lastCash ~= nil and state.cash ~= lastCash then
			pulse(cashPill, if state.cash > lastCash then UiTheme.palette("cash") else UiTheme.palette("danger"))
		end
		if lastCash == nil then
			-- First update: show the real balance straight away. Without this the label kept its "$0" placeholder
			-- until cash first changed, because displayed and target cash start out equal.
			displayedCash = state.cash
			cashLabel.Text = UiTheme.cash(math.floor(state.cash))
		end
		lastCash = state.cash
	end)
	RunService.RenderStepped:Connect(function(dt: number)
		if displayedCash ~= targetCash then
			local diff = targetCash - displayedCash
			if math.abs(diff) < 1 then
				displayedCash = targetCash
			else
				displayedCash += diff * math.min(1, dt * 10)
			end
			cashLabel.Text = UiTheme.cash(math.floor(displayedCash))
		end
	end)
end

return HudController
