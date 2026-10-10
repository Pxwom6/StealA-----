--!strict
--[[
	Centered modal dialog: dimmed backdrop (tap outside to close), title bar, a 52px close button in the corner
	(easy thumb target), and a body frame for content. Only one modal is open at a time.

	Opening fades the backdrop in and pops the panel (with its drop shadow) in with a page-turn sound; closing fades
	the backdrop out and shrinks the panel away. A closing dialog stops taking input at once, so the next dialog (or
	the game) gets every tap.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local UiKit = require(script.Parent.UiKit)
local SoundPlayer = require(script.Parent.Parent.Controllers.SoundPlayer)

local Modal = {}

export type ModalHandle = {
	root: Frame,
	panel: TextButton,
	body: Frame,
	close: () -> (),
	isOpen: () -> boolean,
}

local BACKDROP_TRANSPARENCY = 0.45
local FADE_SECONDS = 0.18

local screen: ScreenGui? = nil
local current: ModalHandle? = nil

local function getScreen(): ScreenGui
	if screen == nil then
		screen = UiKit.screen("Modals", 10)
	end
	return screen :: ScreenGui
end

function Modal.closeCurrent()
	if current then
		current.close()
	end
end

-- Opens a modal of `size` (reference pixels) with a title. `onClose` runs once when it closes.
-- Keep heights <= 340 so modals fit a landscape phone after UiKit's minimum scale.
function Modal.open(title: string, size: Vector2, onClose: (() -> ())?): ModalHandle
	Modal.closeCurrent()
	local open = true
	local root = UiKit.new("Frame", {
		Name = "ModalRoot",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = getScreen(),
	}) :: Frame
	TweenService:Create(root, TweenInfo.new(FADE_SECONDS), { BackgroundTransparency = BACKDROP_TRANSPARENCY }):Play()
	local backdrop = UiKit.new("TextButton", {
		Name = "Backdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Parent = root,
	}) :: TextButton

	-- Panel and shadow share a container, so they pop in and out together.
	local container = UiKit.new("Frame", {
		Name = "PanelContainer",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = root,
	}) :: Frame
	-- The panel is a (text-less) button so taps on its labels and empty space land on it instead of falling
	-- through to the backdrop, which would close the dialog. Plain Frames/labels do not sink input.
	local panel = UiKit.new("TextButton", {
		Name = "Panel",
		AutoButtonColor = false,
		Text = "",
		BackgroundColor3 = UiTheme.palette("panel"),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = container,
	}) :: TextButton
	UiKit.corner(UiKit.RADIUS.large).Parent = panel
	UiKit.stroke(UiKit.STROKE.thick).Parent = panel
	UiKit.shadow(panel)
	UiKit.label({
		Name = "Title",
		Text = title,
		Size = UDim2.new(1, -120, 0, 44),
		Position = UDim2.fromOffset(60, 8),
		TextColor3 = UiTheme.palette("gold"),
		Parent = panel,
	})
	local body = UiKit.new("Frame", {
		Name = "Body",
		Position = UDim2.fromOffset(16, 58),
		Size = UDim2.new(1, -32, 1, -72),
		BackgroundTransparency = 1,
		Parent = panel,
	}) :: Frame

	local handle: ModalHandle
	local function close()
		if not open then
			return
		end
		open = false
		if current == handle then
			current = nil
		end
		-- Out of the way at once (no more taps, under any new dialog), then animate away.
		root.Interactable = false
		root.ZIndex = 1
		TweenService:Create(root, TweenInfo.new(FADE_SECONDS), { BackgroundTransparency = 1 }):Play()
		UiKit.popOut(container, function()
			root:Destroy()
		end)
		if onClose then
			onClose()
		end
	end
	local closeButton = UiKit.button({
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.fromOffset(52, 52),
		BackgroundColor3 = UiTheme.palette("danger"),
		Text = "X",
		Parent = panel,
	}, close)
	closeButton.ZIndex = 5
	backdrop.Activated:Connect(close)

	handle = {
		root = root,
		panel = panel,
		body = body,
		close = close,
		isOpen = function(): boolean
			return open
		end,
	}
	current = handle
	UiKit.popIn(container)
	SoundPlayer.ui("open")
	return handle
end

return Modal
