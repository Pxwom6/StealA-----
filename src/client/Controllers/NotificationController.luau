--!strict
--[[
	Feedback layer: toasts (Notify), floating world numbers (Effect), and loud server-wide announcement banners
	(Announce) that also land in chat as system messages.
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage.Shared.Net)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local SoundPlayer = require(script.Parent.SoundPlayer)

local NotificationController = {}

local MAX_TOASTS = 3
local TOAST_SECONDS = 2.6
local BANNER_SECONDS = 4.5

local screen: ScreenGui
local toastList: Frame
local bannerQueue: { { text: string, rarity: string? } } = {}
local bannerBusy = false
local toastCounter = 0

local KIND_COLORS: { [string]: string } = {
	success = "success",
	error = "danger",
	info = "panelLight",
	warning = "primary",
}

function NotificationController.toast(text: string, kind: string?)
	local colorKey = KIND_COLORS[kind or "info"] or "panelLight"
	toastCounter += 1
	local toast = UiKit.panel({
		Name = "Toast",
		Size = UDim2.fromOffset(340, 40),
		BackgroundColor3 = UiTheme.palette(colorKey),
		LayoutOrder = -toastCounter,
		Parent = toastList,
	})
	UiKit.label({
		Text = text,
		Size = UDim2.new(1, -16, 1, -8),
		Position = UDim2.fromOffset(8, 4),
		Parent = toast,
	})
	UiKit.popIn(toast)
	if kind == "error" then
		SoundPlayer.ui("error")
	end
	local toasts = {}
	for _, child in toastList:GetChildren() do
		if child:IsA("Frame") then
			table.insert(toasts, child)
		end
	end
	if #toasts > MAX_TOASTS then
		table.sort(toasts, function(a: Frame, b: Frame): boolean
			return a.LayoutOrder > b.LayoutOrder
		end)
		toasts[1]:Destroy()
	end
	task.delay(TOAST_SECONDS, function()
		if toast.Parent then
			toast:Destroy()
		end
	end)
end

-- Floating "+$123" (or any text) rising from a world position.
function NotificationController.floatText(position: Vector3, text: string, color: Color3)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.2
	anchor.Position = position + Vector3.new(0, 3, 0)
	anchor.Parent = workspace
	local gui = UiKit.new("BillboardGui", {
		Size = UDim2.fromOffset(200, 50),
		AlwaysOnTop = true,
		LightInfluence = 0,
		Parent = anchor,
	}) :: BillboardGui
	local label = UiKit.label({
		Text = text,
		Size = UDim2.fromScale(1, 1),
		TextColor3 = color,
		Parent = gui,
	})
	TweenService:Create(gui, TweenInfo.new(1.1, Enum.EasingStyle.Quad), { StudsOffset = Vector3.new(0, 4, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		TextTransparency = 1,
	}):Play()
	Debris:AddItem(anchor, 1.2)
end

function NotificationController.sparkle(position: Vector3, color: Color3)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Position = position
	anchor.Parent = workspace
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.Speed = NumberRange.new(6, 12)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Lifetime = NumberRange.new(0.5, 0.9)
	emitter.Size = NumberSequence.new(0.6, 0)
	emitter.Rate = 0
	emitter.Parent = anchor
	emitter:Emit(30)
	Debris:AddItem(anchor, 1.5)
end

local function systemChat(text: string)
	local ok, err = pcall(function()
		local channels = TextChatService:FindFirstChild("TextChannels")
		local system = channels and channels:FindFirstChild("RBXSystem")
		if system and system:IsA("TextChannel") then
			system:DisplaySystemMessage(text)
		end
	end)
	if not ok then
		warn(`[Notifications] system chat failed: {err}`)
	end
end

local function showNextBanner()
	if bannerBusy or #bannerQueue == 0 then
		return
	end
	bannerBusy = true
	local entry = table.remove(bannerQueue, 1) :: { text: string, rarity: string? }
	local color = if entry.rarity then UiTheme.rarityColor(entry.rarity) else UiTheme.palette("primary")
	local banner = UiKit.panel({
		Name = "Announcement",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, -80),
		Size = UDim2.fromOffset(560, 64),
		BackgroundColor3 = color,
		Parent = screen,
	})
	UiKit.new("UIGradient", {
		Color = ColorSequence.new(color, color:Lerp(Color3.new(1, 1, 1), 0.35)),
		Rotation = 90,
		Parent = banner,
	})
	UiKit.label({
		Text = entry.text,
		Size = UDim2.new(1, -24, 1, -12),
		Position = UDim2.fromOffset(12, 6),
		Parent = banner,
	})
	SoundPlayer.world("announce")
	TweenService:Create(
		banner,
		TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.5, 0, 0, 150) }
	):Play()
	task.delay(BANNER_SECONDS, function()
		local tween = TweenService:Create(banner, TweenInfo.new(0.25), { Position = UDim2.new(0.5, 0, 0, -80) })
		tween:Play()
		tween.Completed:Wait()
		banner:Destroy()
		bannerBusy = false
		showNextBanner()
	end)
end

function NotificationController.announce(text: string, rarity: string?)
	table.insert(bannerQueue, { text = text, rarity = rarity })
	systemChat(text)
	showNextBanner()
end

function NotificationController.start()
	screen = UiKit.screen("Notifications", 5)
	toastList = UiKit.new("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -110),
		Size = UDim2.fromOffset(360, 150),
		BackgroundTransparency = 1,
		Parent = screen,
	}) :: Frame
	UiKit.new("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 6),
		Parent = toastList,
	})

	Net.get("Notify").OnClientEvent:Connect(function(payload: { text: string, kind: string? })
		NotificationController.toast(payload.text, payload.kind)
		if payload.kind == "success" then
			SoundPlayer.ui("purchase")
		end
	end)
	Net.get("Announce").OnClientEvent:Connect(function(payload: { text: string, rarity: string? })
		NotificationController.announce(payload.text, payload.rarity)
	end)
	Net.get("Effect").OnClientEvent:Connect(function(payload: { kind: string, amount: number?, position: Vector3? })
		local position = payload.position
		if position == nil then
			return
		end
		if payload.kind == "collect" and payload.amount then
			NotificationController.floatText(position, "+" .. UiTheme.cash(payload.amount), UiTheme.palette("cash"))
			SoundPlayer.world("collect")
		elseif payload.kind == "podium" then
			NotificationController.sparkle(position + Vector3.new(0, 2, 0), UiTheme.palette("gold"))
		end
	end)
end

return NotificationController
