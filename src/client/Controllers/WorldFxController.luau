--!strict
--[[
	Ambient world animation, all on the client and cheap:
	  * the belt's chevrons slide along at the items' speed (one BulkMoveTo of ~70 parts per frame; the belt's ends are
	    inside the factory intake and the chute, so they wrap around out of sight)
	  * the Snack Factory's cog turns, the chute's warning lights blink (2 Hz)

	Settings > Reduce effects (ClientSettings) stops all of that and, on this device only, switches off every particle
	emitter / sparkles / smoke / fire in the world (factory smoke, fountain spray, rarity sparkles, mutations...,
	including ones that appear later) plus Bloom and SunRays. Turning it back off restores exactly what it changed.
]]

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local ClientSettings = require(script.Parent.ClientSettings)

local WorldFxController = {}

local chevronParts: { BasePart } = {}
local chevronBase: { CFrame } = {}
local chevronFrames: { CFrame } = {}
local chevronSpacing = 8
local chevronSpeed = 0

local cog: Model? = nil
local cogPivot = CFrame.identity
local cogSpinSpeed = 0
local cogAngle = 0

local blinkers: { BasePart } = {}

local reduced = false
-- What Reduce effects switched off, to switch back on later (weak keys: destroyed instances drop out).
local switchedOff: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local EMITTER_CLASSES = { "ParticleEmitter", "Sparkles", "Smoke", "Fire" }

local function isEmitter(instance: Instance): boolean
	for _, className in EMITTER_CLASSES do
		if instance:IsA(className) then
			return true
		end
	end
	return false
end

local function switchOff(instance: Instance)
	local effect = instance :: any
	if effect.Enabled then
		effect.Enabled = false
		switchedOff[instance] = true
	end
end

local function applyReduced(on: boolean)
	if on == reduced then
		return
	end
	reduced = on
	if on then
		for _, descendant in workspace:GetDescendants() do
			if isEmitter(descendant) then
				switchOff(descendant)
			end
		end
		for _, child in Lighting:GetChildren() do
			if child:IsA("BloomEffect") or child:IsA("SunRaysEffect") then
				switchOff(child)
			end
		end
		-- Chevrons back to rest.
		if #chevronParts > 0 then
			workspace:BulkMoveTo(chevronParts, chevronBase, Enum.BulkMoveMode.FireCFrameChanged)
		end
	else
		for instance in switchedOff do
			if instance.Parent then
				(instance :: any).Enabled = true
			end
		end
		table.clear(switchedOff)
	end
end

local function findChevrons()
	local map = workspace:WaitForChild("Map")
	local conveyor = map:WaitForChild("Conveyor")
	local folder = conveyor:WaitForChild("Chevrons")
	local spacing = folder:GetAttribute("Spacing")
	local speed = folder:GetAttribute("Speed")
	chevronSpacing = if type(spacing) == "number" and spacing > 0 then spacing else 8
	chevronSpeed = if type(speed) == "number" then speed else 0
	for _, child in folder:GetChildren() do
		if child:IsA("BasePart") then
			table.insert(chevronParts, child)
			table.insert(chevronBase, child.CFrame)
			table.insert(chevronFrames, child.CFrame)
		end
	end
end

local function findFactoryBits()
	local scenery = workspace:WaitForChild("Map"):WaitForChild("Scenery")
	local factory = scenery:WaitForChild("SnackFactory")
	local found = factory:WaitForChild("Cog", 10)
	if found and found:IsA("Model") then
		cog = found
		cogPivot = found:GetPivot()
		local speed = found:GetAttribute("SpinSpeed")
		cogSpinSpeed = if type(speed) == "number" then speed else 0
	end
	local chute = scenery:WaitForChild("Chute")
	for _, child in chute:GetChildren() do
		if child:IsA("BasePart") and child:GetAttribute("Blink") == true then
			table.insert(blinkers, child)
		end
	end
end

local function step(dt: number)
	if reduced then
		return
	end
	if #chevronParts > 0 and chevronSpeed > 0 then
		local offset = Vector3.new((workspace:GetServerTimeNow() * chevronSpeed) % chevronSpacing, 0, 0)
		for i, base in chevronBase do
			chevronFrames[i] = base + offset
		end
		workspace:BulkMoveTo(chevronParts, chevronFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	local turning = cog
	if turning and cogSpinSpeed ~= 0 then
		cogAngle = (cogAngle + dt * cogSpinSpeed) % (math.pi * 2)
		turning:PivotTo(cogPivot * CFrame.Angles(cogAngle, 0, 0))
	end
end

function WorldFxController.start()
	task.spawn(findChevrons)
	task.spawn(findFactoryBits)
	workspace.DescendantAdded:Connect(function(descendant)
		if reduced and isEmitter(descendant) then
			-- Let whoever created it finish setting it up first.
			task.defer(switchOff, descendant)
		end
	end)
	ClientSettings.onChanged(function(settings)
		applyReduced(settings.reduceEffects)
	end)
	applyReduced(ClientSettings.reduceEffects())
	RunService.RenderStepped:Connect(step)
	task.spawn(function()
		local lit = true
		while true do
			task.wait(0.5)
			lit = not lit
			if not reduced then
				for _, light in blinkers do
					light.Transparency = if lit then 0 else 0.7
				end
			end
		end
	end)
end

return WorldFxController
