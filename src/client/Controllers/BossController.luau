--!strict
--[[
	Snack Attack on this client (the server side is BossService; Config/Boss): the giant Snackling over the belt.

	  * A health bar with its name in its rarity colour and the seconds left floats above it, visible from anywhere on
	    the map, with a hint for the player's last input ("Tap to hit!", "Click to hit!", or aim and press R2 on a
	    gamepad: Roblox's default controls click a ClickDetector under the screen's centre dot with R2); a red outline
	    marks it.
	  * It bobs and slowly turns, so both walkways see its face (here only: the server keeps it where it put it; it
	    holds still with Reduce effects).
	  * Your own taps (the ClickDetector on its invisible Hitbox part, the only part of it a pointer can hit) pop a
	    sound and a sparkle; hits anyone lands make it flinch (a soft red pulse and a squash, at most twice a second
	    however fast it is hit, and neither with Reduce effects: BossRules.startsFlinch), and its health bar follows
	    the server's HP attribute.
	  * Taken down: a big sparkle burst in its rarity colour and a sting (the server's "bossDown" effect).
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Boss = require(ReplicatedStorage.Shared.Config.Boss)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local CreatureVisuals = require(ReplicatedStorage.Shared.CreatureVisuals)
local GameData = require(ReplicatedStorage.Shared.GameData)
local Net = require(ReplicatedStorage.Shared.Net)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local BossRules = require(ReplicatedStorage.Shared.Logic.BossRules)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local ClientSettings = require(script.Parent.ClientSettings)
local NotificationController = require(script.Parent.NotificationController)
local SoundPlayer = require(script.Parent.SoundPlayer)

local BossController = {}

-- Must match BossService.TAG.
local TAG = "SnackBoss"
local BOB_HEIGHT = 0.9 -- studs
local BOB_SPEED = 1.3 -- radians per second
local TURN_SPEED = 0.35 -- radians per second
local FLINCH_SQUASH = -0.07 -- for Config/Boss `flinch.seconds` after a hit

type Giant = {
	model: Model,
	base: CFrame, -- where the server put its pivot
	height: number,
	squash: { CreatureVisuals.SquashPart },
	fill: Frame,
	hpLabel: TextLabel,
	timeLabel: TextLabel,
	highlight: Highlight,
	lastHp: number,
	flinchAt: number, -- os.clock() when the last flinch started
	turn: number,
}

local giants: { [Model]: Giant } = {}

local GAMEPADS: { [EnumItem]: boolean } = {}
for _, inputType in Enum.UserInputType:GetEnumItems() do
	if string.sub(inputType.Name, 1, 7) == "Gamepad" then
		GAMEPADS[inputType] = true
	end
end
local MOUSE: { [EnumItem]: boolean } = {
	[Enum.UserInputType.MouseButton1] = true,
	[Enum.UserInputType.MouseButton2] = true,
	[Enum.UserInputType.MouseButton3] = true,
	[Enum.UserInputType.MouseMovement] = true,
	[Enum.UserInputType.MouseWheel] = true,
	[Enum.UserInputType.Keyboard] = true,
}

-- The hint under the health bar for how this player last played: a tap, a click, or R2 on a gamepad (aimed with the
-- camera: R2 clicks what is under the screen's centre dot). Before any input, what the device has decides.
local function hintFor(inputType: EnumItem): string
	if GAMEPADS[inputType] then
		return Theme.text.bossHintGamepad
	elseif inputType == Enum.UserInputType.Touch then
		return Theme.text.bossHint
	elseif MOUSE[inputType] or UserInputService.MouseEnabled then
		return Theme.text.bossHintClick
	elseif UserInputService.GamepadEnabled and not UserInputService.TouchEnabled then
		return Theme.text.bossHintGamepad
	end
	return Theme.text.bossHint
end

local hint = Theme.text.bossHint

local function healthBar(model: Model, height: number, def: any): (Frame, TextLabel, TextLabel)
	local root = model.PrimaryPart :: BasePart
	local board = UiKit.new("BillboardGui", {
		Name = "BossBar",
		Size = UDim2.fromOffset(260, 74),
		StudsOffsetWorldSpace = Vector3.new(0, height * 0.6 + 3, 0),
		AlwaysOnTop = true,
		MaxDistance = 900,
		LightInfluence = 0,
		Parent = root,
	}) :: BillboardGui
	local color = if def then UiTheme.rarityColor(def.rarity) else UiTheme.palette("danger")
	UiKit.label({
		Name = "Title",
		Text = if def then Format.template(Theme.text.bossName, { creature = GameData.displayName(def, nil) }) else "",
		TextColor3 = color,
		Size = UDim2.fromScale(1, 0.36),
		Parent = board,
	})
	local back = UiKit.new("Frame", {
		Name = "Bar",
		BackgroundColor3 = Color3.fromRGB(30, 26, 40),
		Size = UDim2.fromScale(1, 0.3),
		Position = UDim2.fromScale(0, 0.38),
		Parent = board,
	}) :: Frame
	UiKit.corner(8).Parent = back
	UiKit.stroke(2, Color3.fromRGB(20, 18, 28)).Parent = back
	local fill = UiKit.new("Frame", {
		Name = "Fill",
		BackgroundColor3 = UiTheme.palette("danger"),
		Size = UDim2.fromScale(1, 1),
		Parent = back,
	}) :: Frame
	UiKit.corner(8).Parent = fill
	local hpLabel = UiKit.label({
		Name = "Hp",
		Text = "",
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = back,
	})
	local timeLabel = UiKit.label({
		Name = "Hint",
		Text = hint,
		Size = UDim2.fromScale(1, 0.3),
		Position = UDim2.fromScale(0, 0.7),
		Parent = board,
	})
	return fill, hpLabel, timeLabel
end

local function onGiant(instance: Instance)
	if not instance:IsA("Model") or giants[instance] then
		return
	end
	local model = instance
	local root = model.PrimaryPart
	if root == nil then
		return
	end
	local creatureId = model:GetAttribute("CreatureId")
	local def = if type(creatureId) == "string" then GameData.catalog.creatures[creatureId] else nil
	local heightAttribute = model:GetAttribute("Height")
	local height = if type(heightAttribute) == "number" then heightAttribute else CreatureVisuals.height(model)
	local fill, hpLabel, timeLabel = healthBar(model, height, def)
	local highlight = Instance.new("Highlight")
	highlight.Name = "BossGlow"
	highlight.FillColor = UiTheme.palette("danger")
	highlight.FillTransparency = 1
	highlight.OutlineColor = UiTheme.palette("danger")
	highlight.OutlineTransparency = 0.2
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = model
	local maxHp = model:GetAttribute("MaxHP")
	giants[model] = {
		model = model,
		base = model:GetPivot(),
		height = height,
		squash = CreatureVisuals.squashParts(model),
		fill = fill,
		hpLabel = hpLabel,
		timeLabel = timeLabel,
		highlight = highlight,
		lastHp = if type(maxHp) == "number" then maxHp else 0,
		flinchAt = -math.huge,
		turn = 0,
	}
	-- your own taps: a pop and a sparkle where you hit (the server decides whether it counted)
	local clicker = model:FindFirstChildWhichIsA("ClickDetector", true)
	if clicker then
		clicker.MouseClick:Connect(function()
			SoundPlayer.world("bossHit")
			if not ClientSettings.reduceEffects() then
				local at = root.Position + Vector3.new(0, height * 0.2, 0)
				NotificationController.sparkle(at, UiTheme.palette("gold"))
			end
		end)
	end
end

local function step(dt: number)
	if next(giants) == nil then
		return
	end
	local clock = os.clock()
	local serverNow = workspace:GetServerTimeNow()
	local reduced = ClientSettings.reduceEffects()
	for model, giant in giants do
		if model.Parent == nil then
			giants[model] = nil
			continue
		end
		local hp = model:GetAttribute("HP")
		local maxHp = model:GetAttribute("MaxHP")
		if type(hp) == "number" and type(maxHp) == "number" and maxHp > 0 then
			-- hits come in 0.1 s steps from everyone: a new flinch at most twice a second, none with Reduce effects
			if hp < giant.lastHp and BossRules.startsFlinch(Boss, giant.flinchAt, clock, reduced) then
				giant.flinchAt = clock
			end
			giant.lastHp = hp
			giant.fill.Size = UDim2.fromScale(math.clamp(hp / maxHp, 0, 1), 1)
			giant.hpLabel.Text = `{math.max(0, math.ceil(hp))} / {maxHp}`
		end
		local endsAt = model:GetAttribute("EndsAt")
		if type(endsAt) == "number" then
			local left = math.max(0, math.ceil(endsAt - serverNow))
			giant.timeLabel.Text = `{hint}  ⏱ {left}s`
		end
		local since = clock - giant.flinchAt
		local flinching = not reduced and since < Boss.flinch.seconds
		giant.highlight.FillTransparency = if flinching then BossRules.flinchFill(Boss, since) else 1
		if reduced then
			continue
		end
		giant.turn += dt * TURN_SPEED
		local bob = math.sin(clock * BOB_SPEED) * BOB_HEIGHT
		model:PivotTo(giant.base * CFrame.new(0, bob, 0) * CFrame.Angles(0, giant.turn, 0))
		CreatureVisuals.applySquash(giant.squash, if flinching then FLINCH_SQUASH else 0)
	end
end

function BossController.start()
	hint = hintFor(UserInputService:GetLastInputType())
	UserInputService.LastInputTypeChanged:Connect(function(inputType: Enum.UserInputType)
		hint = hintFor(inputType)
	end)
	CollectionService:GetInstanceAddedSignal(TAG):Connect(onGiant)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(instance: Instance)
		if instance:IsA("Model") then
			giants[instance] = nil
		end
	end)
	for _, instance in CollectionService:GetTagged(TAG) do
		onGiant(instance)
	end
	RunService.RenderStepped:Connect(step)
	Net.get("Effect").OnClientEvent:Connect(function(payload: { kind: string, position: Vector3?, rarity: string? })
		local position = payload.position
		if payload.kind ~= "bossDown" or position == nil then
			return
		end
		local color = if type(payload.rarity) == "string"
			then UiTheme.rarityColor(payload.rarity)
			else UiTheme.palette("gold")
		for i = 0, 2 do
			NotificationController.sparkle(position + Vector3.new(0, i * 3, 0), color)
		end
		SoundPlayer.world("bossDown")
	end)
end

return BossController
