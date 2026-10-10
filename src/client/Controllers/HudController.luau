--!strict
--[[
	The always-on HUD, laid out for thumbs on a landscape phone:

	  top centre    cash (animated count-up) + cash/sec, then the tutorial banner and status pills (event + luck, lock,
	                social) stacked below in TOP_ORDER, so nothing in the stack can overlap
	  left middle   round feature buttons (Shop, Rebirth, Daily...) — other controllers add them
	  right, above the jump button   contextual action area (e.g. the big TAG! button)
	  top right     the settings gear (SettingsController) and nothing else: on computers Roblox's player list sits
	                there, drawn above all game UI, so the gear goes left of it (playerListWidth, Logic/ScreenLayout)

	Numbers count up instead of jumping so progress always feels alive, and the cash pill pulses on every change.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local ScreenLayout = require(ReplicatedStorage.Shared.Logic.ScreenLayout)
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

-- Width (HUD reference units) that Roblox's player list takes from the right edge: 0 on phones (it starts hidden)
-- or when it is switched off. `assumeShown` = true measures it as if shown (e.g. while the tutorial hides it).
function HudController.playerListWidth(assumeShown: boolean?): number
	local viewport = workspace.CurrentCamera.ViewportSize
	local enabled = assumeShown == true or StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.PlayerList)
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local stats = Players.LocalPlayer:FindFirstChild("leaderstats")
	local statCount = if stats then #stats:GetChildren() else 0
	local pixels = ScreenLayout.playerListWidth(enabled, touchOnly, viewport.X, viewport.Y, statCount)
	return pixels / UiKit.scaleFor(viewport)
end

export type SideButton = { button: TextButton, badge: Frame }

-- Adds a round feature button to the left column.
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
		Size = UDim2.fromOffset(74, 74),
		BackgroundColor3 = color,
		Text = "",
	}, onTap)
	UiKit.label({
		Name = "Icon",
		Text = icon,
		Size = UDim2.fromScale(1, 0.62),
		Parent = button,
	})
	UiKit.label({
		Name = "Caption",
		Text = caption,
		Size = UDim2.fromScale(1, 0.32),
		Position = UDim2.fromScale(0, 0.66),
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
		Padding = UDim.new(0, 12),
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
