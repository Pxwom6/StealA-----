--!strict
--[[
	The always-on HUD, laid out for thumbs on a landscape phone. Logic/ScreenLayout decides where everything goes and
	tools/layoutCheck.luau checks it on five screens (DECISIONS.md #47); this controller builds the cash pill, the
	feature buttons and the action area, and puts every HUD element the other controllers hand it (HudController.place)
	exactly where ScreenLayout.layout says: again whenever one of them shows or hides, the screen changes size, or
	Roblox's player list or top bar does.

	  top centre    the cash pill (cash, cash/sec under it) in Roblox's top bar strip; under it one band: the tutorial
	                banner, or the "Need $X more?" strip, or the status pills (event, the running modifier, luck)
	  top right     lock, 👥 Friends and ⚙ settings (under Roblox's top-left buttons when the player list fills the
	                corner on computers)
	  top left      Shop, Rebirth, Rewards and Snackdex in a 2x2 grid under Roblox's top-left buttons
	  right         the action area (the TAG! button), above the jump button
	  bottom        the map vote, between the thumbstick and the jump button
	  middle        nothing tappable: that is where the character and the Buy / Steal prompts are

	Numbers count up instead of jumping so progress always feels alive, and the cash pill pulses on every change.
]]

local GuiService = game:GetService("GuiService")
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

local SIZE = ScreenLayout.SIZE
-- The feature buttons by LayoutOrder (HudController.addSideButton).
local SIDE_IDS = { "shop", "rebirth", "rewards", "snackdex" }
-- The status pills sit in their own frame, hidden while the band shows the tutorial or a cash offer.
local STATUS_IDS = { event = true, modifier = true, luck = true }

local screen: ScreenGui
local statusFrame: Frame
local actionArea: Frame
local cashLabel: TextLabel
local incomeLabel: TextLabel
local cashPill: Frame

local placed: { [string]: GuiObject } = {}
local layoutListeners: { () -> () } = {}
local currentDevice: ScreenLayout.Device? = nil
local currentLayout: ScreenLayout.Layout? = nil
local relayoutPending = false
local lastPlayerList = -1

local displayedCash = 0
local targetCash = 0
local lastCash: number? = nil

function HudController.screen(): ScreenGui
	return screen
end

-- Bottom-right container above the jump button for big contextual buttons (the TAG! button, centred in it).
function HudController.actionArea(): Frame
	return actionArea
end

-- Width in pixels of Roblox's player list on this screen: 0 on phones (it starts hidden) or when it is switched off.
-- `assumeShown` = true measures it as if shown (e.g. while the tutorial hides it).
local function playerListPixels(assumeShown: boolean?): number
	local viewport = workspace.CurrentCamera.ViewportSize
	local enabled = assumeShown == true or StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.PlayerList)
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local stats = Players.LocalPlayer:FindFirstChild("leaderstats")
	local statCount = if stats then #stats:GetChildren() else 0
	return ScreenLayout.playerListWidth(enabled, touchOnly, viewport.X, viewport.Y, statCount)
end

-- This screen as Logic/ScreenLayout sees it: its size, safe area, touch controls, Roblox's top bar (GuiService) and
-- player list.
function HudController.device(assumePlayerListShown: boolean?): ScreenLayout.Device
	local viewport = workspace.CurrentCamera.ViewportSize
	local position, size = screen.AbsolutePosition, screen.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		position, size = Vector2.zero, viewport -- not laid out yet
	end
	local free = GuiService.TopbarInset -- the part of Roblox's top bar its own buttons leave free
	local hasFree = free.Width > 0
	return ScreenLayout.device({
		name = "this screen",
		widthPx = viewport.X,
		heightPx = viewport.Y,
		touch = UserInputService.TouchEnabled,
		insetLeftPx = math.max(0, position.X),
		insetRightPx = math.max(0, viewport.X - position.X - size.X),
		insetBottomPx = math.max(0, viewport.Y - size.Y),
		playerListPx = playerListPixels(assumePlayerListShown),
		topBarPx = UiKit.topBarPixels(),
		topBarLeftPx = if hasFree then free.Min.X else nil,
		topBarRightPx = if hasFree then free.Max.X else nil,
	})
end

local function hudState(): ScreenLayout.HudState
	local function shown(id: string): boolean
		local object: GuiObject? = placed[id]
		return object ~= nil and object.Visible and object.Parent ~= nil
	end
	local tutorial: GuiObject? = placed.tutorial
	return {
		tutorial = if tutorial and tutorial.Visible
			then (if tutorial:GetAttribute("Tip") == true then "full" else "compact")
			else nil,
		cashOffer = shown("cashOffer"),
		event = shown("event"),
		modifier = shown("modifier"),
		luck = shown("luck"),
		vote = shown("vote"),
		friends = shown("friends"),
	}
end

-- Places `object` on rect `r` whatever its AnchorPoint (placed elements are anchored at their centre, so pop-ins and
-- presses scale around it).
local function setRect(object: GuiObject, r: ScreenLayout.Rect)
	local anchor = object.AnchorPoint
	local position = UDim2.fromOffset(r.x + r.w * anchor.X, r.y + r.h * anchor.Y)
	local size = UDim2.fromOffset(r.w, r.h)
	if object.Position ~= position then
		object.Position = position
	end
	if object.Size ~= size then
		object.Size = size
	end
end

local function relayout()
	relayoutPending = false
	local device = HudController.device()
	local layout = ScreenLayout.layout(device, hudState())
	currentDevice, currentLayout = device, layout
	lastPlayerList = device.playerList
	statusFrame.Visible = layout.statusShown
	setRect(cashPill, layout.byId.cash)
	setRect(actionArea, ScreenLayout.actionArea(device))
	for id, object in placed do
		local r = if id == "vote" then ScreenLayout.voteStrip(device) else layout.byId[id]
		if r then
			setRect(object, r)
		end
	end
	for _, listener in layoutListeners do
		task.spawn(listener)
	end
end

-- Lays the HUD out again at the end of this frame (many changes in one frame make one pass).
function HudController.relayout()
	if not relayoutPending then
		relayoutPending = true
		task.defer(relayout)
	end
end

-- Hands a HUD element to the layout under `id` (an id of Logic/ScreenLayout.layout: "lock", "friends", "gear",
-- "tutorial", "cashOffer", "event", "modifier", "luck", or "vote" for the vote strip). It is parented to the HUD and
-- placed and sized from then on; it shows and hides itself (Visible), and the tutorial banner says whether its tip
-- shows with the attribute Tip. A newer object under the same id replaces it; destroying it frees its place.
function HudController.place(id: string, object: GuiObject)
	placed[id] = object
	object.AnchorPoint = Vector2.new(0.5, 0.5)
	object.Parent = if STATUS_IDS[id] then statusFrame else screen
	object:GetPropertyChangedSignal("Visible"):Connect(HudController.relayout)
	object.Destroying:Connect(function()
		if placed[id] == object then
			placed[id] = nil
		end
		HudController.relayout()
	end)
	if id == "tutorial" then
		object:GetAttributeChangedSignal("Tip"):Connect(HudController.relayout)
	end
	HudController.relayout()
end

-- The layout as last placed (worked out now if there is none yet).
function HudController.layout(): (ScreenLayout.Device, ScreenLayout.Layout)
	if currentDevice == nil or currentLayout == nil then
		relayout()
	end
	return currentDevice :: ScreenLayout.Device, currentLayout :: ScreenLayout.Layout
end

-- Where the top stack ends (UI units): things that drop in over the HUD go just below it.
function HudController.stackBottom(): number
	local _, layout = HudController.layout()
	return layout.stackBottom
end

-- x and width for something `w` x `h` dropping in over the HUD at `top` (UI units): centred under the stack and clear
-- of the buttons beside it (announcement banners, the map title card, the steal alert).
function HudController.overlaySpan(w: number, h: number, top: number): (number, number)
	local device, layout = HudController.layout()
	return ScreenLayout.overlaySpan(device, layout, w, h, top)
end

-- Calls `listener` after every layout pass.
function HudController.onLayout(listener: () -> ())
	table.insert(layoutListeners, listener)
end

export type SideButton = { button: TextButton, badge: Frame }

-- Adds a feature button to the 2x2 grid (`order`: 1 Shop, 2 Rebirth, 3 Rewards, 4 Snackdex). The badge is a red dot
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
		Size = UDim2.fromOffset(SIZE.side.w, SIZE.side.h),
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
	-- Inside the corner: the top row is right under Roblox's top bar, which draws above the game's UI.
	local badge = UiKit.new("Frame", {
		Name = "Badge",
		Size = UDim2.fromOffset(18, 18),
		Position = UDim2.new(1, -14, 0, -4),
		BackgroundColor3 = UiTheme.palette("danger"),
		Visible = false,
		ZIndex = 3,
		Parent = button,
	}) :: Frame
	UiKit.corner(9).Parent = badge
	UiKit.stroke(2).Parent = badge
	HudController.place(SIDE_IDS[order] or `side{order}`, button)
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
	screen = UiKit.screen("Hud", 1, Enum.ScreenInsets.DeviceSafeInsets)

	cashPill = UiKit.panel({
		Name = "Cash",
		AnchorPoint = Vector2.new(0.5, 0.5), -- it pulses around its centre
		Size = UDim2.fromOffset(SIZE.cash.w, SIZE.cash.h),
		BackgroundColor3 = UiTheme.palette("panel"),
		Parent = screen,
	})
	cashLabel = UiKit.label({
		Name = "Amount",
		Size = UDim2.new(1, -16, 0, SIZE.cash.amount),
		Position = UDim2.fromOffset(8, 2),
		Text = UiTheme.cash(0),
		Parent = cashPill,
	})
	incomeLabel = UiKit.label({
		Name = "Income",
		Size = UDim2.new(1, -16, 0, SIZE.cash.income),
		Position = UDim2.fromOffset(8, 2 + SIZE.cash.amount),
		TextColor3 = UiTheme.palette("cash"),
		Text = UiTheme.perSecond(0),
		Parent = cashPill,
	})

	-- The status pills (RewardsController, ModifierController) are placed one by one; this frame hides them together.
	statusFrame = UiKit.new("Frame", {
		Name = "Status",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = screen,
	}) :: Frame

	actionArea = UiKit.new("Frame", {
		Name = "ActionArea",
		Size = UDim2.fromOffset(150, 150),
		BackgroundTransparency = 1,
		Parent = screen,
	}) :: Frame
end

function HudController.start()
	build()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(HudController.relayout)
	screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(HudController.relayout)
	screen:GetPropertyChangedSignal("AbsolutePosition"):Connect(HudController.relayout)
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(HudController.relayout)
	-- Roblox's player list can be switched on and off (and gains columns) with no event to listen to.
	task.spawn(function()
		while true do
			task.wait(1)
			local list = playerListPixels() / UiKit.scaleFor(workspace.CurrentCamera.ViewportSize)
			if math.abs(list - lastPlayerList) > 0.01 then
				HudController.relayout()
			end
		end
	end)
	HudController.relayout()

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
