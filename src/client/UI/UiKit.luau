--!strict
--[[
	Tiny UI toolkit: declarative instance creation, the game's chunky visual style, and phone-first scaling.

	Layouts are authored in offsets for a ~540px-tall reference screen. A UIScale on every ScreenGui scales
	them to the device (clamped so touch targets never drop below ~48px on small phones), and ScreenInsets
	keeps everything inside notches / home indicators.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UiTheme = require(ReplicatedStorage.Shared.UiTheme)

local UiKit = {}

local REFERENCE_HEIGHT = 540
local MIN_SCALE = 0.85
local MAX_SCALE = 1.35

export type Props = { [string]: any }

-- Creates an instance, applies props, parents children. `Parent` is applied last.
function UiKit.new(className: string, props: Props?, children: { Instance }?): Instance
	local instance = Instance.new(className)
	local parent: Instance? = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				(instance :: any)[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

function UiKit.corner(radius: number?): UICorner
	return UiKit.new("UICorner", { CornerRadius = UDim.new(0, radius or 14) }) :: UICorner
end

function UiKit.stroke(thickness: number?, color: Color3?): UIStroke
	return UiKit.new("UIStroke", {
		Thickness = thickness or 3,
		Color = color or UiTheme.palette("stroke"),
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}) :: UIStroke
end

function UiKit.textStroke(thickness: number?): UIStroke
	return UiKit.new("UIStroke", {
		Thickness = thickness or 2,
		Color = UiTheme.palette("stroke"),
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
	}) :: UIStroke
end

function UiKit.padding(pixels: number): UIPadding
	local p = UDim.new(0, pixels)
	return UiKit.new("UIPadding", { PaddingTop = p, PaddingBottom = p, PaddingLeft = p, PaddingRight = p }) :: UIPadding
end

function UiKit.scaleFor(viewport: Vector2): number
	return math.clamp(viewport.Y / REFERENCE_HEIGHT, MIN_SCALE, MAX_SCALE)
end

-- A ScreenGui in PlayerGui with safe-area insets and automatic device scaling.
function UiKit.screen(name: string, displayOrder: number?): ScreenGui
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = UiKit.new("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = displayOrder or 0,
	}) :: ScreenGui
	local scale = UiKit.new("UIScale", { Parent = gui }) :: UIScale
	local camera = workspace.CurrentCamera
	local function update()
		scale.Scale = UiKit.scaleFor(camera.ViewportSize)
	end
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	update()
	gui.Parent = playerGui
	return gui
end

function UiKit.label(props: Props): TextLabel
	local defaults: Props = {
		BackgroundTransparency = 1,
		FontFace = UiTheme.displayFont,
		TextColor3 = UiTheme.palette("text"),
		TextScaled = true,
		Size = UDim2.fromOffset(200, 32),
	}
	for key, value in props do
		defaults[key] = value
	end
	local label = UiKit.new("TextLabel", defaults) :: TextLabel
	UiKit.textStroke(2).Parent = label
	return label
end

-- Presses shrink slightly then spring back: every tap gets visible feedback.
function UiKit.addPressFeedback(button: GuiButton)
	local scale = UiKit.new("UIScale", { Parent = button }) :: UIScale
	local info = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	button.MouseButton1Down:Connect(function()
		TweenService:Create(scale, info, { Scale = 0.92 }):Play()
	end)
	local function release()
		TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
			:Play()
	end
	button.MouseButton1Up:Connect(release)
	button.MouseLeave:Connect(release)
end

-- Big chunky button. `onActivated` fires on tap/click. The text lives in a child "Label" (so the button's own
-- UIStroke can be the border); change it later with UiKit.setButtonText.
function UiKit.button(props: Props, onActivated: () -> ()): TextButton
	local text = if type(props.Text) == "string" then props.Text else ""
	local defaults: Props = {
		AutoButtonColor = false,
		BackgroundColor3 = UiTheme.palette("primary"),
		Size = UDim2.fromOffset(160, 56),
	}
	for key, value in props do
		if key ~= "Text" then
			defaults[key] = value
		end
	end
	defaults.Text = ""
	local button = UiKit.new("TextButton", defaults) :: TextButton
	UiKit.corner(14).Parent = button
	UiKit.stroke(3).Parent = button
	UiKit.label({ Name = "Label", Text = text, Size = UDim2.fromScale(1, 1), Parent = button })
	UiKit.new("UIPadding", {
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 6),
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
		Parent = button,
	})
	UiKit.addPressFeedback(button)
	button.Activated:Connect(onActivated)
	return button
end

function UiKit.setButtonText(button: TextButton, text: string)
	local label = button:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

function UiKit.panel(props: Props): Frame
	local defaults: Props = {
		BackgroundColor3 = UiTheme.palette("panel"),
		Size = UDim2.fromOffset(300, 200),
	}
	for key, value in props do
		defaults[key] = value
	end
	local frame = UiKit.new("Frame", defaults) :: Frame
	UiKit.corner(18).Parent = frame
	UiKit.stroke(4).Parent = frame
	return frame
end

-- Pops an element in (scale from 0.6 with a slight overshoot).
function UiKit.popIn(target: GuiObject)
	local scale = target:FindFirstChildOfClass("UIScale") or UiKit.new("UIScale", { Parent = target }) :: UIScale
	local uiScale = scale :: UIScale
	uiScale.Scale = 0.6
	TweenService:Create(uiScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
end

return UiKit
