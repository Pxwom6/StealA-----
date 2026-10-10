--!strict
--[[
	The stealing / defending experience on the client:
	  * "Steal" hold prompts on other players' podiums (hidden while that base is locked or shielded)
	  * a big red TAG! button whenever a thief is within reach (thumb-sized, above the jump button)
	  * while YOU carry: "Run home!" banner and a golden beam pointing to your base
	  * when YOU are robbed: flashing red alert, alarm, and a red beam pointing at the thief
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Gameplay = require(ReplicatedStorage.Shared.Config.Gameplay)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local GameData = require(ReplicatedStorage.Shared.GameData)
local Net = require(ReplicatedStorage.Shared.Net)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local StealRules = require(ReplicatedStorage.Shared.Logic.StealRules)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local HudController = require(script.Parent.HudController)
local InteractionController = require(script.Parent.InteractionController)
local NotificationController = require(script.Parent.NotificationController)
local PlotController = require(script.Parent.PlotController)
local SoundPlayer = require(script.Parent.SoundPlayer)
local StateStore = require(script.Parent.StateStore)

local StealController = {}

local localPlayer = Players.LocalPlayer
local CFG = Gameplay.steal

local tagButton: TextButton
local tagTargetUserId: number? = nil
local carryBanner: Frame
local alertFrame: Frame
local alertLabel: TextLabel
local wiredPrompts: { [ProximityPrompt]: boolean } = {}
local carryBeam: Beam? = nil
local alertBeam: Beam? = nil
local alertThiefId: number? = nil

local function myRoot(): BasePart?
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function isProtected(plot: Model): boolean
	local now = workspace:GetServerTimeNow()
	local lockedUntil = plot:GetAttribute("LockedUntil")
	local graceUntil = plot:GetAttribute("GraceUntil")
	return (type(lockedUntil) == "number" and lockedUntil > now) or (type(graceUntil) == "number" and graceUntil > now)
end

local function makeBeam(from: BasePart, to: BasePart, color: Color3): Beam
	local a0 = Instance.new("Attachment")
	a0.Name = "BeamStart"
	a0.Parent = from
	local a1 = Instance.new("Attachment")
	a1.Name = "BeamEnd"
	a1.Parent = to
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0 = 0.6
	beam.Width1 = 0.6
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.Color = ColorSequence.new(color)
	beam.Transparency = NumberSequence.new(0.2)
	beam.Parent = from
	return beam
end

local function destroyBeam(beam: Beam?)
	if beam then
		local a0, a1 = beam.Attachment0, beam.Attachment1
		beam:Destroy()
		if a0 then
			a0:Destroy()
		end
		if a1 then
			a1:Destroy()
		end
	end
end

-- Claims prompts on other players' podiums and turns them into hold-to-steal prompts.
local function stealHook(podium: Model, plot: Model, prompt: ProximityPrompt): boolean
	local ownerId = plot:GetAttribute("OwnerUserId")
	if type(ownerId) ~= "number" or ownerId == 0 then
		return false
	end
	local creatureId = podium:GetAttribute("CreatureId")
	local def = if type(creatureId) == "string" then GameData.catalog.creatures[creatureId] else nil
	if def == nil then
		return false
	end
	prompt:SetAttribute("Role", "Steal")
	prompt.ActionText = Theme.text.stealAction
	prompt.ObjectText = GameData.displayName(def, InteractionController.variantOf(podium))
	prompt.HoldDuration = CFG.holdSeconds
	prompt.MaxActivationDistance = CFG.grabRange - 2
	prompt.Enabled = not isProtected(plot)
	if not wiredPrompts[prompt] then
		wiredPrompts[prompt] = true
		local function ids(): (any, any)
			return plot:GetAttribute("PlotIndex"), podium:GetAttribute("PodiumIndex")
		end
		prompt.PromptButtonHoldBegan:Connect(function()
			if prompt:GetAttribute("Role") == "Steal" then
				local plotIndex, podiumIndex = ids()
				Net.get("StealBegin"):FireServer(plotIndex, podiumIndex)
			end
		end)
		prompt.Triggered:Connect(function()
			if prompt:GetAttribute("Role") == "Steal" then
				local plotIndex, podiumIndex = ids()
				Net.get("StealConfirm"):FireServer(plotIndex, podiumIndex)
			end
		end)
	end
	return true
end

-- Finds the nearest other player carrying a creature within tag range.
local function nearestThief(): Player?
	local root = myRoot()
	if root == nil then
		return nil
	end
	local best: Player? = nil
	local bestDistance = CFG.tagRange - 1
	for _, other in Players:GetPlayers() do
		if other == localPlayer then
			continue
		end
		local carrying = other:GetAttribute("Carrying")
		if type(carrying) ~= "string" or carrying == "" then
			continue
		end
		local character = other.Character
		local otherRoot = character and character:FindFirstChild("HumanoidRootPart")
		if otherRoot and otherRoot:IsA("BasePart") then
			-- Same reach rule as the server: horizontal range plus a vertical allowance.
			local offset = otherRoot.Position - root.Position
			local horizontal = Vector3.new(offset.X, 0, offset.Z).Magnitude
			if
				horizontal <= bestDistance
				and StealRules.withinTagReach(horizontal, offset.Y, CFG.tagRange - 1, CFG.tagVerticalAllowance)
			then
				best = other
				bestDistance = horizontal
			end
		end
	end
	return best
end

local function updateTagButton()
	local thief = nearestThief()
	tagTargetUserId = if thief then thief.UserId else nil
	if (thief ~= nil) ~= tagButton.Visible then
		tagButton.Visible = thief ~= nil
		if thief then
			UiKit.popIn(tagButton)
		end
	end
end

local function setCarrying(creatureId: string)
	local carrying = creatureId ~= ""
	carryBanner.Visible = carrying
	if carrying and carryBeam == nil then
		local root = myRoot()
		local plot = PlotController.myPlot()
		local sign = plot and plot:FindFirstChild("Sign")
		if root and sign and sign:IsA("BasePart") then
			carryBeam = makeBeam(root, sign, UiTheme.palette("gold"))
		end
		SoundPlayer.world("stealStart")
	elseif not carrying and carryBeam then
		destroyBeam(carryBeam)
		carryBeam = nil
	end
end

local function clearAlert()
	alertThiefId = nil
	alertFrame.Visible = false
	destroyBeam(alertBeam)
	alertBeam = nil
end

local function onStealAlert(payload: { thiefUserId: number, thiefName: string, creatureId: string, text: string })
	alertThiefId = payload.thiefUserId
	alertLabel.Text = payload.text
	alertFrame.Visible = true
	UiKit.popIn(alertFrame)
	SoundPlayer.world("alarm")
	destroyBeam(alertBeam)
	alertBeam = nil
	local thief = Players:GetPlayerByUserId(payload.thiefUserId)
	local root = myRoot()
	local thiefRoot = thief and thief.Character and thief.Character:FindFirstChild("HumanoidRootPart")
	if root and thiefRoot and thiefRoot:IsA("BasePart") then
		alertBeam = makeBeam(root, thiefRoot, UiTheme.palette("danger"))
	end
end

local function build()
	local screen = HudController.screen()
	tagButton = UiKit.button({
		Name = "TagButton",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(120, 120),
		BackgroundColor3 = UiTheme.palette("danger"),
		Text = Theme.text.tagButton,
		Visible = false,
		Parent = HudController.actionArea(),
	}, function()
		if tagTargetUserId then
			Net.get("TagThief"):FireServer(tagTargetUserId)
		end
	end)
	local corner = tagButton:FindFirstChildOfClass("UICorner")
	if corner then
		corner.CornerRadius = UDim.new(0.5, 0)
	end

	carryBanner = UiKit.panel({
		Name = "CarryBanner",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -60),
		Size = UDim2.fromOffset(320, 46),
		BackgroundColor3 = UiTheme.palette("gold"),
		Visible = false,
		Parent = screen,
	})
	UiKit.label({
		Text = Theme.text.stealStarted,
		Size = UDim2.new(1, -16, 1, -8),
		Position = UDim2.fromOffset(8, 4),
		Parent = carryBanner,
	})

	alertFrame = UiKit.panel({
		Name = "StealAlert",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 230),
		Size = UDim2.fromOffset(420, 52),
		BackgroundColor3 = UiTheme.palette("danger"),
		Visible = false,
		Parent = screen,
	})
	alertLabel = UiKit.label({
		Size = UDim2.new(1, -16, 1, -8),
		Position = UDim2.fromOffset(8, 4),
		Parent = alertFrame,
	})
	-- Flash the alert while visible.
	task.spawn(function()
		while true do
			task.wait(0.4)
			if alertFrame.Visible then
				local flash = TweenService:Create(alertFrame, TweenInfo.new(0.2), { BackgroundTransparency = 0.4 })
				flash:Play()
				flash.Completed:Wait()
				TweenService:Create(alertFrame, TweenInfo.new(0.2), { BackgroundTransparency = 0 }):Play()
			end
		end
	end)
end

function StealController.start()
	build()
	InteractionController.addForeignPodiumHook(stealHook)

	StateStore.onChange(function(state)
		setCarrying(state.carrying)
	end)
	Net.get("StealAlert").OnClientEvent:Connect(onStealAlert)
	Net.get("Effect").OnClientEvent:Connect(function(payload: { kind: string, position: Vector3? })
		if payload.kind == "tag" and payload.position then
			NotificationController.sparkle(payload.position, UiTheme.palette("danger"))
			SoundPlayer.world("tagged")
		elseif payload.kind == "tagged" then
			SoundPlayer.world("tagged")
		elseif payload.kind == "stolen" and payload.position then
			NotificationController.sparkle(payload.position, UiTheme.palette("gold"))
			SoundPlayer.world("stealSuccess")
		end
	end)

	task.spawn(function()
		while true do
			task.wait(0.1)
			updateTagButton()
			if alertThiefId then
				local thief = Players:GetPlayerByUserId(alertThiefId)
				local carrying = thief and thief:GetAttribute("Carrying")
				if thief == nil or type(carrying) ~= "string" or carrying == "" then
					clearAlert()
				end
			end
		end
	end)
	-- Locks and shields expire on a timer, so re-evaluate prompt visibility once a second.
	task.spawn(function()
		while true do
			task.wait(1)
			InteractionController.refreshAll()
		end
	end)
end

return StealController
