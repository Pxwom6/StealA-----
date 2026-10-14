--!strict
--[[
	Drops on this client (the server side is DropService; what they hold is Config/Drops):

	  * Supply crates: a 📦 marker over every crate, falling or landed, that shows from far away, and once it has
	    landed a hold prompt ("Open", Drops.crate.holdSeconds). The hold sends CrateBegin when it starts and CrateOpen
	    when it completes; the server decides who gets it. A thud when one lands near you, and a burst of sparkles in
	    the Snackling's rarity colour (and a sting) when you open one.
	  * Coins: they spin and bob (here only; they stay still with Reduce effects). The server picks one up for you
	    as you walk through it; the "+$X" pop and the coin sound are the usual collect effect (NotificationController).
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Drops = require(ReplicatedStorage.Shared.Config.Drops)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local Net = require(ReplicatedStorage.Shared.Net)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local ClientSettings = require(script.Parent.ClientSettings)
local NotificationController = require(script.Parent.NotificationController)
local SoundPlayer = require(script.Parent.SoundPlayer)

local DropController = {}

-- Must match DropService.CRATE_TAG / COIN_TAG.
local CRATE_TAG = "SupplyCrate"
local COIN_TAG = "DropCoin"
local SPIN_SPEED = 3 -- radians per second
local BOB_HEIGHT = 0.3
local THUD_DISTANCE = 120

local coinBases: { [BasePart]: CFrame } = {}

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
	RunService.RenderStepped:Connect(spin)
	Net.get("Effect").OnClientEvent:Connect(function(payload: { kind: string, position: Vector3?, rarity: string? })
		local position = payload.position
		if payload.kind ~= "crate" or position == nil then
			return
		end
		local color = if type(payload.rarity) == "string"
			then UiTheme.rarityColor(payload.rarity)
			else UiTheme.palette("gold")
		NotificationController.sparkle(position + Vector3.new(0, 2, 0), color)
		SoundPlayer.world("crateOpen")
	end)
end

return DropController
