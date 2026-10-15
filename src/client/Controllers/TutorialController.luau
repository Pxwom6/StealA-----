--!strict
--[[
	First-time tutorial UI. The server decides the step (TutorialService → StateUpdate `tutorial`); this controller only
	shows it, and Skip sends the SkipTutorial intent.

	* Banner right under the cash pill, in the HUD's band (HudController places it; the status pills, the vote and
	  the Friends button wait for the tutorial to end, Logic/ScreenLayout): a "1/4" badge, one short line and a Skip
	  button; the steal step adds a one-line tip about the new-player shield, not while carrying (fitBanner).
	* 3D guide: a glowing beam from the player's feet to the target with pulses flowing toward it, a bouncing arrow
	  above the target that shows through walls, and a highlight on the target. Targets (Logic/TutorialRules):
	  buy → the nearest belt item you can afford (re-picked every frame as items move, sell or fall off); collect →
	  your pad with the most cash (if you have no Snackling left, back to the belt); lock → your lock button;
	  steal → no guide (any base will do).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local Gameplay = require(ReplicatedStorage.Shared.Config.Gameplay)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local Tutorial = require(ReplicatedStorage.Shared.Config.Tutorial)
local GameData = require(ReplicatedStorage.Shared.GameData)
local Net = require(ReplicatedStorage.Shared.Net)
local Types = require(ReplicatedStorage.Shared.Types)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local BeltMath = require(ReplicatedStorage.Shared.Logic.BeltMath)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local ModifierRules = require(ReplicatedStorage.Shared.Logic.ModifierRules)
local ScreenLayout = require(ReplicatedStorage.Shared.Logic.ScreenLayout)
local TutorialRules = require(ReplicatedStorage.Shared.Logic.TutorialRules)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local BeltController = require(script.Parent.BeltController)
local HudController = require(script.Parent.HudController)
local ModifierController = require(script.Parent.ModifierController)
local NotificationController = require(script.Parent.NotificationController)
local PlotController = require(script.Parent.PlotController)
local SoundPlayer = require(script.Parent.SoundPlayer)
local StateStore = require(script.Parent.StateStore)

local TutorialController = {}

-- Banner size in reference pixels (UiKit scales it to the device); HudController sets its width (Logic/ScreenLayout).
local SIZE = ScreenLayout.SIZE
local BANNER_HEIGHT = SIZE.tutorial.h
local TIP_HEIGHT = SIZE.tutorial.tip
local CARRY_BANNER_GAP = 4 -- the banner stays this far above the carry banner
local SCREEN_BOTTOM_MARGIN = 8 -- and this far above the bottom of the screen

-- Guide look.
local BEAM_WIDTH = 1.3
local BEAM_PULSES = 4 -- bright pulses along the beam at once
local BEAM_PULSE_SPEED = 1.2 -- pulses per second flowing toward the target
local BEAM_KEYPOINTS = 20 -- NumberSequence maximum
local BEAM_HIDE_DISTANCE = 6 -- hide the beam (keep the arrow) once this close
local FEET_OFFSET = Vector3.new(0, -2.4, 0) -- root part → just above the ground
-- The arrow hangs `arrowHeight` studs above its target, then `arrowLift` of its own height higher on screen (so it
-- clears the target's billboard at any distance) and bounces by ARROW_BOUNCE of its height.
local ARROW_BOUNCE = 0.3
local HIDDEN_BELOW_Y = -400 -- pooled belt models are parked at y = -500

type Target = {
	adornee: PVInstance?, -- followed every frame (belt items move); nil for a fixed point
	point: Vector3?,
	arrowHeight: number, -- studs above the target (e.g. where its billboard is)
	arrowLift: number, -- extra lift in arrow heights (screen space)
	textKey: string?, -- overrides the step's banner line (e.g. "collect" with nothing to collect: buy first)
}

local localPlayer = Players.LocalPlayer
local belt = BeltMath.centered(Gameplay.belt.length, Gameplay.belt.travelSeconds)

local banner: Frame
local badgeLabel: TextLabel
local lineLabel: TextLabel
local tipLabel: TextLabel

local guideFolder: Folder
local startAnchor: Part
local endAnchor: Part
local beam: Beam
local arrowGui: BillboardGui
local highlight: Highlight

local step = "" -- the step the server says we are on ("" = no tutorial)
local hidPlayerList = false -- we switched Roblox's player list off so the banner's Skip stays reachable
local skippedStep = "" -- the step Skip was pressed on (hidden until the server moves on)
local beltTargetId: number? = nil
local renderConnection: RBXScriptConnection? = nil
local fitKey = "" -- what fitBanner last decided for (the step, carrying, the screen)

local function myRoot(): BasePart?
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function anchorPart(name: string): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.one * 0.2
	part.Parent = guideFolder
	return part
end

-- A downward arrow drawn with frames (no image asset needed): a shaft and two arms meeting at the tip.
local function buildArrow(parent: BillboardGui)
	local color = UiTheme.palette("tutorial")
	local function bar(name: string, size: Vector2, center: Vector2, rotation: number)
		local frame = UiKit.new("Frame", {
			Name = name,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(size.X, size.Y),
			Position = UDim2.fromOffset(center.X, center.Y),
			Rotation = rotation,
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Parent = parent,
		})
		UiKit.corner(6).Parent = frame
		UiKit.stroke(3).Parent = frame
	end
	-- 56 x 70 box, tip at (28, 64); each arm is 34 long, so its centre sits 12 px up and across from the tip.
	bar("Shaft", Vector2.new(14, 50), Vector2.new(28, 33), 0)
	bar("LeftArm", Vector2.new(14, 34), Vector2.new(16, 52), -45)
	bar("RightArm", Vector2.new(14, 34), Vector2.new(40, 52), 45)
end

local function buildGuide()
	guideFolder = Instance.new("Folder")
	guideFolder.Name = "TutorialGuide"
	guideFolder.Parent = workspace
	startAnchor = anchorPart("GuideStart")
	endAnchor = anchorPart("GuideEnd")
	local a0 = Instance.new("Attachment")
	a0.Parent = startAnchor
	local a1 = Instance.new("Attachment")
	a1.Parent = endAnchor
	local color = UiTheme.palette("tutorial")
	beam = UiKit.new("Beam", {
		Name = "GuideBeam",
		Attachment0 = a0,
		Attachment1 = a1,
		Width0 = BEAM_WIDTH,
		Width1 = BEAM_WIDTH,
		FaceCamera = true,
		LightEmission = 1,
		LightInfluence = 0,
		Segments = 40,
		Color = ColorSequence.new(color),
		Enabled = false,
		Parent = startAnchor,
	}) :: Beam
	arrowGui = UiKit.new("BillboardGui", {
		Name = "GuideArrow",
		Size = UDim2.fromOffset(56, 70),
		AlwaysOnTop = true,
		LightInfluence = 0,
		Enabled = false,
		Parent = endAnchor,
	}) :: BillboardGui
	buildArrow(arrowGui)
	highlight = UiKit.new("Highlight", {
		Name = "GuideHighlight",
		FillColor = color,
		FillTransparency = 0.7,
		OutlineColor = color,
		OutlineTransparency = 0,
		DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
		Enabled = false,
		Parent = guideFolder,
	}) :: Highlight
end

-- Pulses flowing from the player (0) to the target (1), as a transparency curve along the beam.
local function pulseSequence(phase: number): NumberSequence
	local keypoints: { NumberSequenceKeypoint } = {}
	for i = 0, BEAM_KEYPOINTS - 1 do
		local t = i / (BEAM_KEYPOINTS - 1)
		local wave = 0.5 + 0.5 * math.cos((t * BEAM_PULSES - phase) * 2 * math.pi)
		table.insert(keypoints, NumberSequenceKeypoint.new(t, 0.8 - 0.65 * wave))
	end
	return NumberSequence.new(keypoints)
end

local function beltTarget(root: BasePart, state: Types.ClientState): Target?
	local now = workspace:GetServerTimeNow()
	local candidates: { TutorialRules.BeltCandidate } = {}
	local models: { [number]: BeltController.ItemView } = {}
	for _, view in BeltController.items() do
		local def = GameData.catalog.creatures[view.item.creatureId]
		local position = view.model:GetPivot().Position
		if def and position.Y > HIDDEN_BELOW_Y then
			models[view.item.id] = view
			table.insert(candidates, {
				id = view.item.id,
				price = ModifierRules.beltPrice(GameData.price(def, view.variant), ModifierController.effects()),
				x = position.X,
				z = position.Z,
				secondsLeft = belt.travelSeconds - (now - view.item.spawnAt),
			})
		end
	end
	local position = root.Position
	beltTargetId =
		TutorialRules.pickBeltItem(candidates, state.cash, position.X, position.Z, beltTargetId, Tutorial.belt)
	local view = if beltTargetId then models[beltTargetId] else nil
	if view then
		-- Above the item's name / price billboard (up to ~130 px tall with a mutation row).
		return { adornee = view.model :: PVInstance, arrowHeight = view.labelHeight, arrowLift = 1.5, textKey = nil }
	end
	-- Nothing affordable right now: point at the nearest spot on the belt (it runs along X, see BeltMath.centered).
	local x = math.clamp(position.X, belt.startX, belt.startX + belt.length)
	return {
		point = Vector3.new(x, Gameplay.belt.surfaceY, belt.startZ),
		arrowHeight = 2,
		arrowLift = 0.5,
		textKey = nil,
	}
end

local function collectTarget(root: BasePart, state: Types.ClientState): Target?
	local plot = PlotController.myPlot()
	local podiums = plot and plot:FindFirstChild("Podiums")
	if podiums == nil then
		return nil
	end
	local candidates: { TutorialRules.PodiumCandidate } = {}
	local pads: { [number]: BasePart } = {}
	for _, podium in podiums:GetChildren() do
		local index = podium:GetAttribute("PodiumIndex")
		local creatureId = podium:GetAttribute("CreatureId")
		local stored = podium:GetAttribute("Stored")
		local pad = podium:FindFirstChild("Pad")
		if type(index) == "number" and pad and pad:IsA("BasePart") then
			pads[index] = pad
			table.insert(candidates, {
				index = index,
				occupied = type(creatureId) == "string"
					and creatureId ~= ""
					and podium:GetAttribute("BeingStolen") ~= true,
				stored = if type(stored) == "number" then stored else 0,
			})
		end
	end
	local index = TutorialRules.pickCollectPodium(candidates)
	if index and pads[index] then
		return { adornee = pads[index] :: PVInstance, arrowHeight = 1, arrowLift = 0.5, textKey = nil }
	end
	-- No Snackling to collect from (sold or stolen): buy one first.
	local target = beltTarget(root, state)
	if target then
		target.textKey = TutorialRules.TEXT_KEYS.buy
	end
	return target
end

local function lockTarget(): Target?
	local plot = PlotController.myPlot()
	local button = plot and plot:FindFirstChild("LockButton")
	if button and button:IsA("BasePart") then
		-- Above the lock board (LockController: 44 px, 4 studs up).
		return { adornee = button :: PVInstance, arrowHeight = 4, arrowLift = 1, textKey = nil }
	end
	return nil
end

local function currentTarget(root: BasePart, state: Types.ClientState): Target?
	if step == "buy" then
		return beltTarget(root, state)
	elseif step == "collect" then
		return collectTarget(root, state)
	elseif step == "lock" then
		return lockTarget()
	end
	return nil -- steal: banner only
end

local function hideGuide()
	beam.Enabled = false
	arrowGui.Enabled = false
	highlight.Enabled = false
	highlight.Adornee = nil
end

local function setLine(textKey: string)
	local text = UiTheme.text(textKey)
	if lineLabel.Text ~= text then
		lineLabel.Text = text
	end
end

-- Roblox draws its player list (top right on computers) above every game UI. When even the narrowest banner would
-- run under it, the list is switched off while the banner shows and back on afterwards (only if we switched it off).
local function setPlayerListHidden(hide: boolean)
	if hide == hidPlayerList then
		return
	end
	if hide then
		if StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.PlayerList) then
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
			hidPlayerList = true
		end
	else
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, true)
		hidPlayerList = false
	end
	HudController.relayout()
end

-- How the banner shows (DECISIONS.md #21, #47): with the steal step's tip (how long your shield lasts, or what yellow
-- shields are) when not carrying, else one line; hidden only if even that couldn't stay above the carry banner (it
-- always can now: the banner is the band under the cash). On computers Roblox's player list is switched off while the
-- centred banner would run under it (Logic/ScreenLayout.tutorialDevice), so Skip is always reachable. Decided again
-- only when the step, carrying or the screen change; the tip's countdown ticks every frame.
local function fitBanner(state: Types.ClientState)
	local carrying = state.carrying ~= ""
	local device = HudController.device(true) -- as if the player list showed, so hiding it never undoes the decision
	local key = `{step}|{carrying}|{device.width}|{device.height}|{device.playerList}`
	if key ~= fitKey then
		fitKey = key
		local bottom = if carrying
			then device.height - SIZE.carry.bottom - SIZE.carry.h - CARRY_BANNER_GAP
			else device.height - SCREEN_BOTTOM_MARGIN
		local mode = TutorialRules.bannerMode(
			bottom - ScreenLayout.bandTop(device),
			BANNER_HEIGHT + TIP_HEIGHT,
			BANNER_HEIGHT,
			step == "steal" and not carrying
		)
		banner:SetAttribute("Tip", mode == "full")
		tipLabel.Visible = mode == "full"
		banner.Visible = mode ~= "hidden"
		setPlayerListHidden(
			banner.Visible and device.playerList > 0 and ScreenLayout.tutorialDevice(device).playerList == 0
		)
	end
	if tipLabel.Visible then
		local remaining = state.graceUntil - workspace:GetServerTimeNow()
		tipLabel.Text = if remaining > 0
			then Format.template(Theme.text.tutorialShieldTip, { time = Format.clock(remaining) })
			else Theme.text.tutorialShieldOtherTip
	end
end

local function render()
	local state = StateStore.get()
	local root = myRoot()
	if state == nil then
		hideGuide()
		return
	end
	fitBanner(state)
	-- While carrying a stolen Snackling the carry banner and its beam home take over.
	local target = if root and state.carrying == "" then currentTarget(root, state) else nil
	setLine((target and target.textKey) or TutorialRules.TEXT_KEYS[step] or "")
	if root == nil or target == nil then
		hideGuide()
		return
	end
	local adornee = target.adornee
	local position: Vector3
	if adornee then
		if adornee.Parent == nil then
			hideGuide()
			return
		end
		position = adornee:GetPivot().Position
	else
		position = target.point or root.Position
	end
	if position.Y < HIDDEN_BELOW_Y then
		hideGuide()
		return
	end
	local clock = os.clock()
	startAnchor.Position = root.Position + FEET_OFFSET
	endAnchor.Position = position
	local near = (Vector3.new(position.X, 0, position.Z) - Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude
		< BEAM_HIDE_DISTANCE
	beam.Enabled = not near
	if beam.Enabled then
		beam.Transparency = pulseSequence(clock * BEAM_PULSE_SPEED)
	end
	arrowGui.StudsOffsetWorldSpace = Vector3.new(0, target.arrowHeight, 0)
	arrowGui.SizeOffset = Vector2.new(0, target.arrowLift + math.abs(math.sin(clock * math.pi * 1.5)) * ARROW_BOUNCE)
	arrowGui.Enabled = true
	local highlightTarget: Instance? = adornee
	highlight.Adornee = highlightTarget
	highlight.Enabled = highlightTarget ~= nil
end

local function setStep(newStep: string, view: Types.TutorialView)
	local visible = newStep ~= "" and newStep ~= skippedStep
	if newStep ~= step then
		step = newStep
		beltTargetId = nil
		fitKey = ""
		if visible then
			badgeLabel.Text = Format.template(Theme.text.tutorialStepBadge, { index = view.index, count = view.count })
			setLine(TutorialRules.TEXT_KEYS[newStep] or "")
			local state = StateStore.get()
			if state then
				fitBanner(state)
			end
			UiKit.popIn(banner)
		end
	end
	if not visible then
		fitKey = ""
		banner.Visible = false
		setPlayerListHidden(false)
		if renderConnection then
			renderConnection:Disconnect()
			renderConnection = nil
		end
		hideGuide()
	elseif renderConnection == nil then
		renderConnection = RunService.RenderStepped:Connect(render)
	end
end

local function buildBanner()
	banner = UiKit.panel({
		Name = "TutorialBanner",
		Size = UDim2.fromOffset(SIZE.tutorial.w, BANNER_HEIGHT),
		BackgroundColor3 = UiTheme.palette("panel"),
		Visible = false,
	})
	local stroke = banner:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = UiTheme.palette("tutorial")
	end

	local badge = UiKit.new("Frame", {
		Name = "StepBadge",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(10, BANNER_HEIGHT / 2),
		Size = UDim2.fromOffset(46, 46),
		BackgroundColor3 = UiTheme.palette("tutorial"),
		Parent = banner,
	}) :: Frame
	UiKit.corner(23).Parent = badge
	UiKit.stroke(3).Parent = badge
	badgeLabel = UiKit.label({
		Size = UDim2.new(1, -8, 1, -14),
		Position = UDim2.fromOffset(4, 7),
		Text = "",
		Parent = badge,
	})

	-- One line, as large as fits (two lines on the narrowest phones), left of Skip.
	local skipRoom = SIZE.skip.inset + SIZE.skip.w + 8
	lineLabel = UiKit.label({
		Name = "Line",
		Position = UDim2.fromOffset(66, 6),
		Size = UDim2.new(1, -66 - skipRoom, 0, BANNER_HEIGHT - 12),
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
		Parent = banner,
	})
	UiKit.new("UITextSizeConstraint", { MaxTextSize = 28, MinTextSize = 14, Parent = lineLabel })

	tipLabel = UiKit.label({
		Name = "Tip",
		Position = UDim2.fromOffset(66, BANNER_HEIGHT - 6),
		Size = UDim2.new(1, -66 - 12, 0, TIP_HEIGHT - 4),
		FontFace = UiTheme.bodyFont,
		TextColor3 = UiTheme.palette("tutorial"),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
		Visible = false,
		Parent = banner,
	})

	UiKit.button({
		Name = "Skip",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -SIZE.skip.inset, 0, BANNER_HEIGHT / 2),
		Size = UDim2.fromOffset(SIZE.skip.w, SIZE.skip.h),
		BackgroundColor3 = UiTheme.palette("panelLight"),
		Text = Theme.text.tutorialSkip,
		Parent = banner,
	}, function()
		if step == "" then
			return
		end
		SoundPlayer.ui("click")
		-- Hidden right away; the server ends the tutorial (no reward) and the next StateUpdate confirms it.
		skippedStep = step
		local state = StateStore.get()
		if state then
			setStep(step, state.tutorial)
		end
		Net.get("SkipTutorial"):FireServer()
	end)
	HudController.place("tutorial", banner)
end

function TutorialController.start()
	buildBanner()
	buildGuide()
	StateStore.onChange(function(state)
		local view = state.tutorial
		if view.step ~= skippedStep then
			skippedStep = "" -- the server moved on (or Skip never arrived and a new step began)
		end
		setStep(view.step, view)
	end)
	Net.get("Effect").OnClientEvent:Connect(function(payload: { kind: string, position: Vector3? })
		if payload.kind == "tutorialComplete" then
			local root = myRoot()
			local position = payload.position or (root and root.Position)
			if position then
				NotificationController.sparkle(position + Vector3.new(0, 2, 0), UiTheme.palette("tutorial"))
			end -- the "You're ready!" toast (Notify, success) plays the sound
		end
	end)
end

return TutorialController
