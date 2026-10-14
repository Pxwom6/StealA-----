--!strict
--[[
	Drops on this client (the server side is DropService; what they hold is Config/Drops):

	  * Supply crates: a 📦 marker over every crate, falling or landed, that shows from far away, and once it has
	    landed a hold prompt ("Open", Drops.crate.holdSeconds). The hold sends CrateBegin when it starts and CrateOpen
	    when it completes; the server decides who gets it. A thud when one lands near you, and a burst of sparkles in
	    the Snackling's rarity colour (and a sting) when you open one.
	  * Coins: they spin and bob (here only; they stay still with Reduce effects). The server picks one up for you
	    as you walk through it; the "+$X" pop and the coin sound are the usual collect effect (NotificationController).
	  * Runaways (Great Escape): the server publishes each leg of the run as one attribute (DropRules.encodeLeg) and
	    this client moves the Snackling along it every frame (DropRules.legPosition, the same position the server
	    checks catches against), easing into each new leg, hopping as it runs (IdleMotion.run; it glides with Reduce
	    effects) and jumping high when it crosses the belt. A "Catch me!" marker with its name in its rarity colour
	    shows from far away, and a burst of sparkles marks the catch.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Drops = require(ReplicatedStorage.Shared.Config.Drops)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local CreatureVisuals = require(ReplicatedStorage.Shared.CreatureVisuals)
local GameData = require(ReplicatedStorage.Shared.GameData)
local Net = require(ReplicatedStorage.Shared.Net)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local DropRules = require(ReplicatedStorage.Shared.Logic.DropRules)
local IdleMotion = require(ReplicatedStorage.Shared.Logic.IdleMotion)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local ClientSettings = require(script.Parent.ClientSettings)
local NotificationController = require(script.Parent.NotificationController)
local SoundPlayer = require(script.Parent.SoundPlayer)

local DropController = {}

-- Must match DropService.CRATE_TAG / COIN_TAG / RUNAWAY_TAG.
local CRATE_TAG = "SupplyCrate"
local COIN_TAG = "DropCoin"
local RUNAWAY_TAG = "Runaway"
local SPIN_SPEED = 3 -- radians per second
local BOB_HEIGHT = 0.3
local THUD_DISTANCE = 120
local BELT_HOP = 3.5 -- studs: a runaway's jump over the belt
local CATCH_UP = 18 -- how quickly a runaway's drawn position eases onto a new leg (per second)

local coinBases: { [BasePart]: CFrame } = {}

type Runner = {
	model: Model,
	groundY: number, -- the walkway under its feet (where the server put its pivot)
	leg: DropRules.Leg?,
	facing: Vector3,
	phase: number,
	height: number,
	squash: { CreatureVisuals.SquashPart },
	shownX: number?, -- where it is drawn (eases toward its leg)
	shownZ: number?,
}

local runners: { [Model]: Runner } = {}

local function addMarker(box: BasePart)
	if box:FindFirstChild("CrateMarker") then
		return
	end
	local board = UiKit.new("BillboardGui", {
		Name = "CrateMarker",
		Size = UDim2.fromOffset(46, 46),
		StudsOffsetWorldSpace = Vector3.new(0, 5, 0),
		AlwaysOnTop = true,
		MaxDistance = 500,
		LightInfluence = 0,
		Parent = box,
	}) :: BillboardGui
	UiKit.label({
		Name = "Icon",
		Text = Theme.text.crateMarker,
		Size = UDim2.fromScale(1, 1),
		TextScaled = true,
		Parent = board,
	})
end

local function addPrompt(box: BasePart, id: number)
	if box:FindFirstChild("CratePrompt") then
		return
	end
	local prompt = UiKit.new("ProximityPrompt", {
		Name = "CratePrompt",
		ActionText = Theme.text.crateAction,
		ObjectText = Theme.text.crateObject,
		HoldDuration = Drops.crate.holdSeconds,
		MaxActivationDistance = Drops.crate.openRange,
		RequiresLineOfSight = false,
		KeyboardKeyCode = Enum.KeyCode.E,
		Parent = box,
	}) :: ProximityPrompt
	prompt.PromptButtonHoldBegan:Connect(function()
		Net.get("CrateBegin"):FireServer(id)
	end)
	prompt.Triggered:Connect(function()
		Net.get("CrateOpen"):FireServer(id)
	end)
end

local function onCrate(instance: Instance)
	if not instance:IsA("Model") then
		return
	end
	local model = instance
	task.spawn(function()
		local found = model:WaitForChild("Crate", 10)
		local id = model:GetAttribute("CrateId")
		if found == nil or not found:IsA("BasePart") or type(id) ~= "number" then
			return
		end
		local box = found
		addMarker(box)
		local function onLanded(thud: boolean): boolean
			if model:GetAttribute("Landed") ~= true then
				return false
			end
			addPrompt(box, id)
			local camera = workspace.CurrentCamera
			if thud and camera and (camera.Focus.Position - box.Position).Magnitude < THUD_DISTANCE then
				SoundPlayer.world("crateLand")
			end
			return true
		end
		if not onLanded(false) then
			local connection: RBXScriptConnection? = nil
			connection = model:GetAttributeChangedSignal("Landed"):Connect(function()
				if onLanded(true) and connection then
					connection:Disconnect()
				end
			end)
		end
	end)
end

local function onCoin(instance: Instance)
	if instance:IsA("BasePart") then
		coinBases[instance] = instance.CFrame
	end
end

-- A runaway Snackling: follow its legs, mark it, trail sparkles in its rarity colour.
local function onRunaway(instance: Instance)
	if not instance:IsA("Model") or runners[instance] then
		return
	end
	local model = instance
	local pivot = model:GetPivot()
	local id = model:GetAttribute("RunawayId")
	local runner: Runner = {
		model = model,
		groundY = pivot.Position.Y,
		leg = nil,
		facing = pivot.LookVector,
		phase = IdleMotion.phaseOf(if type(id) == "number" then id else 0),
		height = CreatureVisuals.height(model),
		squash = CreatureVisuals.squashParts(model),
	}
	local function readLeg()
		local text = model:GetAttribute("Leg")
		local leg = if type(text) == "string" then DropRules.decodeLeg(text) else nil
		if leg then
			local dx, dz = leg.toX - leg.fromX, leg.toZ - leg.fromZ
			if dx * dx + dz * dz > 0.01 then
				runner.facing = Vector3.new(dx, 0, dz).Unit
			end
			runner.leg = leg
		end
	end
	readLeg()
	model:GetAttributeChangedSignal("Leg"):Connect(readLeg)
	runners[model] = runner

	local rarityId = model:GetAttribute("Rarity")
	local creatureId = model:GetAttribute("CreatureId")
	local variant = model:GetAttribute("Variant")
	local def = if type(creatureId) == "string" then GameData.catalog.creatures[creatureId] else nil
	local color = if type(rarityId) == "string" then UiTheme.rarityColor(rarityId) else UiTheme.palette("gold")
	local root = model.PrimaryPart
	if root == nil then
		return
	end
	local board = UiKit.new("BillboardGui", {
		Name = "RunawayMarker",
		Size = UDim2.fromOffset(200, 52),
		StudsOffsetWorldSpace = Vector3.new(0, runner.height + 2.5, 0),
		AlwaysOnTop = true,
		MaxDistance = 600,
		LightInfluence = 0,
		Parent = root,
	}) :: BillboardGui
	UiKit.label({
		Name = "Call",
		Text = Theme.text.runawayMarker,
		Size = UDim2.new(1, 0, 0.55, 0),
		TextScaled = true,
		Parent = board,
	})
	if def then
		local rarity = GameData.catalog.rarities[def.rarity]
		UiKit.label({
			Name = "Name",
			Text = `{rarity.displayName} {GameData.displayName(def, if type(variant) == "string" then variant else nil)}`,
			TextColor3 = color,
			Size = UDim2.new(1, 0, 0.45, 0),
			Position = UDim2.fromScale(0, 0.55),
			TextScaled = true,
			Parent = board,
		})
	end
	local highlight = Instance.new("Highlight")
	highlight.Name = "RunawayGlow"
	highlight.FillColor = color
	highlight.FillTransparency = 0.8
	highlight.OutlineColor = color
	highlight.OutlineTransparency = 0.1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = model
	if not ClientSettings.reduceEffects() then
		local trail = Instance.new("ParticleEmitter")
		trail.Name = "RunawayTrail"
		trail.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		trail.Color = ColorSequence.new(color)
		trail.LightEmission = 0.8
		trail.Size = NumberSequence.new(0.35, 0)
		trail.Speed = NumberRange.new(0.5, 1.5)
		trail.SpreadAngle = Vector2.new(180, 180)
		trail.Lifetime = NumberRange.new(0.4, 0.8)
		trail.Rate = 14
		trail.Parent = root
	end
end

local STILL: IdleMotion.Pose = { lift = 0, squash = 0, roll = 0, yaw = 0 }

local function run(dt: number)
	if next(runners) == nil then
		return
	end
	local now = workspace:GetServerTimeNow()
	local reduced = ClientSettings.reduceEffects()
	local ease = math.min(1, dt * CATCH_UP)
	for model, runner in runners do
		if model.Parent == nil then
			runners[model] = nil
			continue
		end
		local leg = runner.leg
		if leg == nil then
			continue
		end
		local x, z, moving = DropRules.legPosition(leg, now)
		local shownX, shownZ = runner.shownX, runner.shownZ
		if shownX == nil or shownZ == nil or math.abs(shownX - x) + math.abs(shownZ - z) > 12 then
			shownX, shownZ = x, z
		else
			shownX += (x - shownX) * ease
			shownZ += (z - shownZ) * ease
		end
		runner.shownX, runner.shownZ = shownX, shownZ
		local pose = if reduced
			then STILL
			elseif moving then IdleMotion.run(now, runner.phase)
			else IdleMotion.podium(now, runner.phase, runner.height)
		local jump = if moving and DropRules.crossesBelt(leg)
			then math.sin(math.pi * DropRules.legProgress(leg, now)) * BELT_HOP
			else 0
		local position = Vector3.new(shownX, runner.groundY + pose.lift + jump, shownZ)
		model:PivotTo(CFrame.lookAt(position, position + runner.facing) * CFrame.Angles(0, pose.yaw, pose.roll))
		CreatureVisuals.applySquash(runner.squash, pose.squash)
	end
end

local function spin()
	if ClientSettings.reduceEffects() then
		return
	end
	local t = os.clock()
	for coin, base in coinBases do
		if coin.Parent == nil then
			coinBases[coin] = nil
			continue
		end
		local phase = base.Position.X * 0.37
		coin.CFrame = base
			* CFrame.new(0, math.sin(t * 2 + phase) * BOB_HEIGHT, 0)
			* CFrame.Angles(0, t * SPIN_SPEED + phase, 0)
	end
end

function DropController.start()
	CollectionService:GetInstanceAddedSignal(CRATE_TAG):Connect(onCrate)
	for _, instance in CollectionService:GetTagged(CRATE_TAG) do
		onCrate(instance)
	end
	CollectionService:GetInstanceAddedSignal(COIN_TAG):Connect(onCoin)
	CollectionService:GetInstanceRemovedSignal(COIN_TAG):Connect(function(instance: Instance)
		if instance:IsA("BasePart") then
			coinBases[instance] = nil
		end
	end)
	for _, instance in CollectionService:GetTagged(COIN_TAG) do
		onCoin(instance)
	end
	CollectionService:GetInstanceAddedSignal(RUNAWAY_TAG):Connect(onRunaway)
	CollectionService:GetInstanceRemovedSignal(RUNAWAY_TAG):Connect(function(instance: Instance)
		if instance:IsA("Model") then
			runners[instance] = nil
		end
	end)
	for _, instance in CollectionService:GetTagged(RUNAWAY_TAG) do
		onRunaway(instance)
	end
	RunService.RenderStepped:Connect(spin)
	RunService.RenderStepped:Connect(run)
	Net.get("Effect").OnClientEvent:Connect(function(payload: { kind: string, position: Vector3?, rarity: string? })
		local position = payload.position
		if (payload.kind ~= "crate" and payload.kind ~= "runaway") or position == nil then
			return
		end
		local color = if type(payload.rarity) == "string"
			then UiTheme.rarityColor(payload.rarity)
			else UiTheme.palette("gold")
		NotificationController.sparkle(position + Vector3.new(0, 2, 0), color)
		local camera = workspace.CurrentCamera
		if payload.kind == "crate" or (camera and (camera.Focus.Position - position).Magnitude < THUD_DISTANCE) then
			SoundPlayer.world("crateOpen")
		end
	end)
end

return DropController
