--!strict
--[[
	Gadget effects on this client, for every player (GadgetService publishes the times as Player attributes, server
	time):

	  GadgetSpeedUntil  a Fizzy Soda is running: fizzy bubbles stream off the player (fewer with Reduce effects)
	  SlippedUntil      slipped on a banana peel: dizzy stars spin over their head; the local player sits down with a
	                    bump and gets up when it ends (the server holds their speed at 0 meanwhile)

	The Bubble Shield's bubble and the peels are parts the server makes, so everyone sees the same thing. One-shot cues
	come as Effect: "gadget" (you used one: its sound and a burst in its colour), "slip" (everyone: a slide sound near
	it and a burst on the peel), "shieldBlock" (your tag bounced off a bubble). Bursts honour Reduce effects
	(NotificationController.sparkle).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Gadgets = require(ReplicatedStorage.Shared.Config.Gadgets)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local Net = require(ReplicatedStorage.Shared.Net)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local ClientSettings = require(script.Parent.ClientSettings)
local NotificationController = require(script.Parent.NotificationController)
local SoundPlayer = require(script.Parent.SoundPlayer)

local GadgetFxController = {}

local SPEED_ATTRIBUTE = "GadgetSpeedUntil"
local SLIP_ATTRIBUTE = "SlippedUntil"
local CHECK_SECONDS = 0.2
local HEARING_RANGE = 80 -- studs: a slip further away than this makes no sound here
local FIZZ_RATE = 26
local FIZZ_RATE_REDUCED = 6
-- The sound each kind of gadget makes when used (Config/Sounds world slots).
local USE_SOUNDS: { [string]: string } = {
	speed = "gadgetFizz",
	peel = "gadgetPeel",
	shield = "gadgetShield",
	magnet = "gadgetMagnet",
}

local localPlayer = Players.LocalPlayer

type Fx = { fizz: ParticleEmitter?, dizzy: BillboardGui? }

local active: { [Player]: Fx } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function timeAttribute(player: Player, name: string): number
	local value = player:GetAttribute(name)
	return if type(value) == "number" then value else 0
end

local function partOf(player: Player, name: string): BasePart?
	local character = player.Character
	local part = character and character:FindFirstChild(name)
	return if part and part:IsA("BasePart") then part else nil
end

local function makeFizz(root: BasePart, color: Color3): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "GadgetFizz"
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	emitter.LightEmission = 0.6
	emitter.Size = NumberSequence.new(0.35, 0)
	emitter.Lifetime = NumberRange.new(0.5, 0.9)
	emitter.Speed = NumberRange.new(2, 4)
	emitter.SpreadAngle = Vector2.new(50, 50)
	emitter.Acceleration = Vector3.new(0, 6, 0) -- bubbles rise
	emitter.Rate = if ClientSettings.reduceEffects() then FIZZ_RATE_REDUCED else FIZZ_RATE
	emitter.Parent = root
	return emitter
end

local function makeDizzy(head: BasePart): BillboardGui
	local gui = UiKit.new("BillboardGui", {
		Name = "GadgetDizzy",
		Size = UDim2.fromOffset(70, 40),
		StudsOffsetWorldSpace = Vector3.new(0, 2.2, 0),
		AlwaysOnTop = true,
		MaxDistance = 120,
		LightInfluence = 0,
		Parent = head,
	}) :: BillboardGui
	UiKit.label({ Text = Theme.text.gadgetDizzy, Size = UDim2.fromScale(1, 1), Parent = gui })
	return gui
end

local function soda(): Color3
	for _, id in Gadgets.order do
		local def = Gadgets.gadgets[id]
		if def.kind == "speed" then
			return UiTheme.color(def.color)
		end
	end
	return UiTheme.palette("primary")
end

-- Puts on (or takes off) `player`'s effects to match their attributes now.
local function refresh(player: Player)
	local t = now()
	local fx: Fx = active[player] or { fizz = nil, dizzy = nil }
	local speeding = timeAttribute(player, SPEED_ATTRIBUTE) > t
	local root = partOf(player, "HumanoidRootPart")
	if speeding and root and (fx.fizz == nil or fx.fizz.Parent ~= root) then
		if fx.fizz then
			fx.fizz:Destroy()
		end
		fx.fizz = makeFizz(root, soda())
	elseif not speeding and fx.fizz then
		fx.fizz:Destroy()
		fx.fizz = nil
	end
	local slipped = timeAttribute(player, SLIP_ATTRIBUTE) > t
	local head = partOf(player, "Head")
	if slipped and head and (fx.dizzy == nil or fx.dizzy.Parent ~= head) then
		if fx.dizzy then
			fx.dizzy:Destroy()
		end
		fx.dizzy = makeDizzy(head)
	elseif not slipped and fx.dizzy then
		fx.dizzy:Destroy()
		fx.dizzy = nil
	end
	if fx.fizz or fx.dizzy then
		active[player] = fx
	else
		active[player] = nil
	end
end

local function watch(player: Player)
	for _, name in { SPEED_ATTRIBUTE, SLIP_ATTRIBUTE } do
		player:GetAttributeChangedSignal(name):Connect(function()
			refresh(player)
		end)
	end
	refresh(player)
end

-- The local player slipped: they sit down with a bump, and get up when the slip ends.
local function sitDown(untilT: number)
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		return
	end
	humanoid.Sit = true
	task.delay(math.max(0.1, untilT - now()), function()
		if humanoid.Parent and humanoid.Sit and timeAttribute(localPlayer, SLIP_ATTRIBUTE) <= now() + 0.05 then
			humanoid.Sit = false
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end)
end

local function nearMe(position: Vector3): boolean
	local root = partOf(localPlayer, "HumanoidRootPart")
	return root ~= nil and (root.Position - position).Magnitude <= HEARING_RANGE
end

type EffectPayload = {
	kind: string,
	position: Vector3?,
	gadget: string?,
	userId: number?,
	ownerUserId: number?,
}

local function onEffect(payload: EffectPayload)
	local position = payload.position
	if payload.kind == "gadget" then
		local def = if payload.gadget then Gadgets.gadgets[payload.gadget] else nil
		if def then
			SoundPlayer.world(USE_SOUNDS[def.kind] or "gadgetFizz")
			if position then
				NotificationController.sparkle(position, UiTheme.color(def.color))
			end
		end
	elseif payload.kind == "slip" and position then
		local mine = payload.userId == localPlayer.UserId or payload.ownerUserId == localPlayer.UserId
		if mine or nearMe(position) then
			SoundPlayer.world("slip")
		end
		NotificationController.sparkle(position, UiTheme.palette("gold"))
		if payload.userId == localPlayer.UserId then
			sitDown(timeAttribute(localPlayer, SLIP_ATTRIBUTE))
		end
	elseif payload.kind == "shieldBlock" and position then
		SoundPlayer.world("shieldBlock")
		for _, id in Gadgets.order do
			if Gadgets.gadgets[id].kind == "shield" then
				NotificationController.sparkle(position, UiTheme.color(Gadgets.gadgets[id].color))
			end
		end
	end
end

function GadgetFxController.start()
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(player: Player)
		local fx = active[player]
		if fx then
			if fx.fizz then
				fx.fizz:Destroy()
			end
			if fx.dizzy then
				fx.dizzy:Destroy()
			end
		end
		active[player] = nil
	end)
	-- Reduce effects switched on or off: running fizz follows at once.
	ClientSettings.onChanged(function()
		for _, fx in active do
			if fx.fizz then
				fx.fizz.Rate = if ClientSettings.reduceEffects() then FIZZ_RATE_REDUCED else FIZZ_RATE
			end
		end
	end)
	Net.get("Effect").OnClientEvent:Connect(onEffect)
	-- Effects end with their time (server time, no attribute change then) and follow a respawned character.
	task.spawn(function()
		while true do
			task.wait(CHECK_SECONDS)
			for player in active do
				refresh(player)
			end
			for _, player in Players:GetPlayers() do
				if active[player] == nil then
					local t = now()
					if timeAttribute(player, SPEED_ATTRIBUTE) > t or timeAttribute(player, SLIP_ATTRIBUTE) > t then
						refresh(player)
					end
				end
			end
		end
	end)
end

return GadgetFxController
