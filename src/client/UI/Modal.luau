--!strict
--[[
	Centered modal dialog: dimmed backdrop (tap outside to close), title bar, a 52px close button in the corner
	(easy thumb target), and a body frame for content. Only one modal is open at a time.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local UiKit = require(script.Parent.UiKit)

local Modal = {}

export type ModalHandle = {
	root: Frame,
	panel: Frame,
	body: Frame,
	close: () -> (),
	isOpen: () -> boolean,
}

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
		BackgroundTransparency = 0.45,
		Parent = getScreen(),
	}) :: Frame
	local backdrop = UiKit.new("TextButton", {
		Name = "Backdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Parent = root,
	}) :: TextButton

	local panel = UiKit.panel({
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size.X, size.Y),
		Parent = root,
	})
	-- Never taller / wider than the screen allows (in reference pixels).
	UiKit.new("UISizeConstraint", { MaxSize = Vector2.new(size.X, size.Y), Parent = panel })
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
		root:Destroy()
		if current == handle then
			current = nil
		end
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
	UiKit.popIn(panel)
	return handle
end

return Modal
