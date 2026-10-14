--!strict
--[[
	Weather for the current map theme (Config/MapThemes `weather`): particles drifting around this player's camera —
	snow, embers, falling leaves, fireflies, candy sprinkles, desert dust or petals. One invisible box follows the camera
	(it lives under the Camera, so only this client has it) and its emitter fills the air around you, which is far
	cheaper than covering the whole map.

	Off with Settings > Reduce effects, and while the map has no weather. The kind comes from the server through the
	workspace attribute MapTheme.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MapThemes = require(ReplicatedStorage.Shared.Config.MapThemes)
local Types = require(ReplicatedStorage.Shared.Types)
local ClientSettings = require(script.Parent.ClientSettings)

local WeatherController = {}

local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

type Recipe = {
	boxSize: Vector3, -- the emitting volume around the camera
	offset: Vector3, -- where the box sits relative to the camera's focus
	props: { [string]: any }, -- ParticleEmitter properties
}

local function sequence(keys: { { number } }): NumberSequence
	local points: { NumberSequenceKeypoint } = {}
	for _, key in keys do
		table.insert(points, NumberSequenceKeypoint.new(key[1], key[2]))
	end
	return NumberSequence.new(points)
end

local function colours(list: { Color3 }): ColorSequence
	if #list == 1 then
		return ColorSequence.new(list[1])
	end
	local points: { ColorSequenceKeypoint } = {}
	for index, color in list do
		table.insert(points, ColorSequenceKeypoint.new((index - 1) / (#list - 1), color))
	end
	return ColorSequence.new(points)
end

local RECIPES: { [Types.WeatherKind]: Recipe } = {
	snow = {
		boxSize = Vector3.new(110, 1, 110),
		offset = Vector3.new(0, 34, 0),
		props = {
			Texture = SMOKE,
			Color = colours({ Color3.fromRGB(255, 255, 255) }),
			Size = sequence({ { 0, 0.45 }, { 1, 0.35 } }),
			Transparency = sequence({ { 0, 0.15 }, { 0.85, 0.15 }, { 1, 1 } }),
			Speed = NumberRange.new(5, 8),
			SpreadAngle = Vector2.new(25, 25),
			Acceleration = Vector3.new(1.2, 0, 0.6),
			Lifetime = NumberRange.new(6, 8),
			Rate = 70,
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-40, 40),
			EmissionDirection = Enum.NormalId.Bottom,
		},
	},
	embers = {
		boxSize = Vector3.new(100, 16, 100),
		offset = Vector3.new(0, -4, 0),
		props = {
			Texture = SPARKLE,
			Color = colours({ Color3.fromRGB(255, 190, 80), Color3.fromRGB(255, 90, 30), Color3.fromRGB(180, 40, 20) }),
			LightEmission = 1,
			Size = sequence({ { 0, 0.32 }, { 1, 0.05 } }),
			Transparency = sequence({ { 0, 0 }, { 1, 0.6 } }),
			Speed = NumberRange.new(2, 5),
			SpreadAngle = Vector2.new(35, 35),
			Acceleration = Vector3.new(0.8, 1.2, 0.4),
			Drag = 0.3,
			Lifetime = NumberRange.new(4, 7),
			Rate = 30,
			EmissionDirection = Enum.NormalId.Top,
		},
	},
	leaves = {
		boxSize = Vector3.new(110, 1, 110),
		offset = Vector3.new(0, 30, 0),
		props = {
			Texture = SPARKLE,
			Color = colours({ Color3.fromRGB(232, 118, 46), Color3.fromRGB(242, 179, 58), Color3.fromRGB(194, 69, 42) }),
			Size = sequence({ { 0, 0.6 }, { 1, 0.5 } }),
			Transparency = sequence({ { 0, 0.05 }, { 0.85, 0.1 }, { 1, 1 } }),
			Speed = NumberRange.new(3, 5),
			SpreadAngle = Vector2.new(30, 30),
			Acceleration = Vector3.new(2.5, -0.5, 1),
			Lifetime = NumberRange.new(7, 9),
			Rate = 18,
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-120, 120),
			EmissionDirection = Enum.NormalId.Bottom,
		},
	},
	fireflies = {
		boxSize = Vector3.new(90, 10, 90),
		offset = Vector3.new(0, -3, 0),
		props = {
			Texture = SPARKLE,
			Color = colours({ Color3.fromRGB(230, 255, 120) }),
			LightEmission = 1,
			Size = sequence({ { 0, 0 }, { 0.2, 0.45 }, { 0.5, 0.2 }, { 0.8, 0.45 }, { 1, 0 } }),
			Speed = NumberRange.new(0.5, 1.5),
			SpreadAngle = Vector2.new(180, 180),
			Drag = 0.5,
			Lifetime = NumberRange.new(4, 7),
			Rate = 14,
			EmissionDirection = Enum.NormalId.Top,
		},
	},
	sprinkles = {
		boxSize = Vector3.new(100, 1, 100),
		offset = Vector3.new(0, 30, 0),
		props = {
			Texture = SPARKLE,
			Color = colours({
				Color3.fromRGB(255, 92, 138),
				Color3.fromRGB(255, 210, 63),
				Color3.fromRGB(124, 217, 255),
				Color3.fromRGB(182, 120, 255),
			}),
			LightEmission = 0.3,
			Size = sequence({ { 0, 0.28 }, { 1, 0.22 } }),
			Speed = NumberRange.new(4, 7),
			SpreadAngle = Vector2.new(20, 20),
			Lifetime = NumberRange.new(5, 7),
			Rate = 40,
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-200, 200),
			EmissionDirection = Enum.NormalId.Bottom,
		},
	},
	dust = {
		boxSize = Vector3.new(110, 12, 110),
		offset = Vector3.new(0, 0, 0),
		props = {
			Texture = SMOKE,
			Color = colours({ Color3.fromRGB(232, 201, 138) }),
			Size = sequence({ { 0, 1.5 }, { 1, 3.5 } }),
			Transparency = sequence({ { 0, 1 }, { 0.3, 0.85 }, { 0.7, 0.88 }, { 1, 1 } }),
			Speed = NumberRange.new(1, 3),
			SpreadAngle = Vector2.new(60, 60),
			Acceleration = Vector3.new(3, 0.2, 1),
			Lifetime = NumberRange.new(6, 9),
			Rate = 8,
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-20, 20),
			EmissionDirection = Enum.NormalId.Top,
		},
	},
	petals = {
		boxSize = Vector3.new(110, 1, 110),
		offset = Vector3.new(0, 30, 0),
		props = {
			Texture = SPARKLE,
			Color = colours({ Color3.fromRGB(255, 160, 200), Color3.fromRGB(255, 255, 255) }),
			Size = sequence({ { 0, 0.42 }, { 1, 0.36 } }),
			Transparency = sequence({ { 0, 0.1 }, { 0.85, 0.1 }, { 1, 1 } }),
			Speed = NumberRange.new(2.5, 4),
			SpreadAngle = Vector2.new(30, 30),
			Acceleration = Vector3.new(2, -0.3, 1.2),
			Lifetime = NumberRange.new(7, 9),
			Rate = 16,
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-90, 90),
			EmissionDirection = Enum.NormalId.Bottom,
		},
	},
}

local box: Part? = nil
local recipe: Recipe? = nil

local function clear()
	if box then
		box:Destroy()
		box = nil
	end
	recipe = nil
end

local function currentKind(): Types.WeatherKind
	local themeId = workspace:GetAttribute("MapTheme")
	local theme = if type(themeId) == "string" then MapThemes.themes[themeId] else nil
	return if theme then theme.weather else "none"
end

local function refresh()
	clear()
	if ClientSettings.reduceEffects() then
		return
	end
	local chosen = RECIPES[currentKind()]
	if chosen == nil then
		return
	end
	local part = Instance.new("Part")
	part.Name = "Weather"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = chosen.boxSize
	part.CastShadow = false
	local emitter = Instance.new("ParticleEmitter")
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	emitter.LightInfluence = 0.6
	for key, value in chosen.props do
		(emitter :: any)[key] = value
	end
	emitter.Parent = part
	part.Parent = workspace.CurrentCamera
	box = part
	recipe = chosen
end

function WeatherController.start()
	workspace:GetAttributeChangedSignal("MapTheme"):Connect(refresh)
	local reduced = ClientSettings.reduceEffects()
	ClientSettings.onChanged(function(settings)
		if settings.reduceEffects ~= reduced then
			reduced = settings.reduceEffects
			refresh()
		end
	end)
	refresh()
	RunService.RenderStepped:Connect(function()
		local part, chosen = box, recipe
		if part == nil or chosen == nil then
			return
		end
		local camera = workspace.CurrentCamera
		local focus = camera.Focus.Position
		part.CFrame = CFrame.new(focus + chosen.offset)
	end)
end

return WeatherController
