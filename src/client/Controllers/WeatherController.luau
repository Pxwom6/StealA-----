--!strict
--[[
	Weather for the current map theme (Config/MapThemes `weather`): particles drifting around this player's camera —
	snow, embers, falling leaves, fireflies, candy sprinkles, desert dust, petals, stardust, pollen, feathers, bubbles
	or rain. One invisible box follows the camera
	(it lives under the Camera, so only this client has it) and its emitter fills the air around you, which is far
	cheaper than covering the whole map.

	A weather modifier (Config/Modifiers: Thunderstorm, Meteor Shower, Toxic Fog) replaces the map's particles with its
	own (rain, glowing spores) while it runs, and adds its sky effect: lightning (a far-off bolt, a soft flash of this
	client's screen and a rumble of thunder every 6-14 seconds) or shooting stars streaking across the sky. The server
	changes the lighting itself (ModifierService).

	Off with Settings > Reduce effects (only the thunder stays), and while there is no weather. The kinds come from the
	server through the workspace attributes MapTheme and Modifier.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local MapThemes = require(ReplicatedStorage.Shared.Config.MapThemes)
local Modifiers = require(ReplicatedStorage.Shared.Config.Modifiers)
local Types = require(ReplicatedStorage.Shared.Types)
local ClientSettings = require(script.Parent.ClientSettings)
local SoundPlayer = require(script.Parent.SoundPlayer)

local WeatherController = {}

local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

-- Lightning: seconds between strikes, how bright the screen flashes (a gentle lift, at most two quick pulses: well
-- under three flashes a second), and how far away the bolts land.
local STRIKE_GAP = NumberRange.new(6, 14)
local FLASH_BRIGHTNESS = 0.25
local BOLT_DISTANCE = NumberRange.new(170, 280)
-- Shooting stars: seconds between them, and where they start relative to the camera's focus.
local METEOR_GAP = NumberRange.new(0.5, 1.4)
local METEOR_SPREAD = 170
local METEOR_HEIGHT = NumberRange.new(110, 170)

local random = Random.new()

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
	-- Thin streaks falling fast: squashed into lines and turned along their fall.
	rain = {
		boxSize = Vector3.new(110, 1, 110),
		offset = Vector3.new(0, 40, 0),
		props = {
			Texture = SMOKE,
			Color = colours({ Color3.fromRGB(190, 205, 225) }),
			Size = sequence({ { 0, 0.15 }, { 1, 0.15 } }),
			Squash = sequence({ { 0, 2.5 }, { 1, 2.5 } }),
			Orientation = Enum.ParticleOrientation.VelocityParallel,
			Transparency = sequence({ { 0, 0.35 }, { 0.9, 0.35 }, { 1, 1 } }),
			Speed = NumberRange.new(60, 70),
			SpreadAngle = Vector2.new(4, 4),
			Acceleration = Vector3.new(2, 0, 1),
			Lifetime = NumberRange.new(0.7, 0.9),
			Rate = 320,
			EmissionDirection = Enum.NormalId.Bottom,
		},
	},
	-- Twinkling stars hanging all around (Cookie Moon).
	stardust = {
		boxSize = Vector3.new(100, 30, 100),
		offset = Vector3.new(0, 10, 0),
		props = {
			Texture = SPARKLE,
			Color = colours({ Color3.fromRGB(255, 255, 255), Color3.fromRGB(190, 200, 255) }),
			LightEmission = 1,
			Size = sequence({ { 0, 0 }, { 0.5, 0.32 }, { 1, 0 } }),
			Speed = NumberRange.new(0.2, 0.6),
			SpreadAngle = Vector2.new(180, 180),
			Lifetime = NumberRange.new(3, 5),
			Rate = 26,
			EmissionDirection = Enum.NormalId.Top,
		},
	},
	-- Golden pollen floating in warm air (Mango Rainforest).
	pollen = {
		boxSize = Vector3.new(90, 12, 90),
		offset = Vector3.new(0, -1, 0),
		props = {
			Texture = SPARKLE,
			Color = colours({ Color3.fromRGB(232, 242, 122), Color3.fromRGB(184, 224, 90) }),
			LightEmission = 0.4,
			Size = sequence({ { 0, 0 }, { 0.2, 0.24 }, { 0.8, 0.2 }, { 1, 0 } }),
			Speed = NumberRange.new(0.3, 1),
			SpreadAngle = Vector2.new(180, 180),
			Acceleration = Vector3.new(0.6, 0.15, 0.3),
			Drag = 0.4,
			Lifetime = NumberRange.new(6, 9),
			Rate = 18,
			EmissionDirection = Enum.NormalId.Top,
		},
	},
	-- Soft white feathers drifting down (Cloud Nine).
	feathers = {
		boxSize = Vector3.new(110, 1, 110),
		offset = Vector3.new(0, 30, 0),
		props = {
			Texture = SPARKLE,
			Color = colours({ Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 244, 200) }),
			Size = sequence({ { 0, 0.5 }, { 1, 0.42 } }),
			Transparency = sequence({ { 0, 0.05 }, { 0.85, 0.1 }, { 1, 1 } }),
			Speed = NumberRange.new(1.5, 3),
			SpreadAngle = Vector2.new(30, 30),
			Acceleration = Vector3.new(0.8, -0.2, 0.4),
			Lifetime = NumberRange.new(8, 10),
			Rate = 12,
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-60, 60),
			EmissionDirection = Enum.NormalId.Bottom,
		},
	},
	-- Bubbles rising from the sea floor (Sushi Reef).
	bubbles = {
		boxSize = Vector3.new(100, 1, 100),
		offset = Vector3.new(0, -6, 0),
		props = {
			Texture = SMOKE,
			Color = colours({ Color3.fromRGB(216, 246, 255) }),
			Size = sequence({ { 0, 0.25 }, { 1, 0.45 } }),
			Transparency = sequence({ { 0, 0.35 }, { 0.85, 0.45 }, { 1, 1 } }),
			Speed = NumberRange.new(3, 5),
			SpreadAngle = Vector2.new(10, 10),
			Acceleration = Vector3.new(0.3, 0.5, 0.2),
			Lifetime = NumberRange.new(6, 8),
			Rate = 30,
			EmissionDirection = Enum.NormalId.Top,
		},
	},
	-- Glowing green spores floating up through the fog.
	spores = {
		boxSize = Vector3.new(90, 12, 90),
		offset = Vector3.new(0, -2, 0),
		props = {
			Texture = SPARKLE,
			Color = colours({ Color3.fromRGB(160, 255, 110), Color3.fromRGB(80, 255, 130) }),
			LightEmission = 1,
			Size = sequence({ { 0, 0 }, { 0.2, 0.35 }, { 0.8, 0.3 }, { 1, 0 } }),
			Speed = NumberRange.new(0.4, 1.2),
			SpreadAngle = Vector2.new(180, 180),
			Acceleration = Vector3.new(0.4, 0.6, 0.2),
			Drag = 0.4,
			Lifetime = NumberRange.new(5, 8),
			Rate = 22,
			EmissionDirection = Enum.NormalId.Top,
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

local function runningModifier(): Types.ModifierDef?
	local id = workspace:GetAttribute("Modifier")
	return if type(id) == "string" then Modifiers.modifiers[id] else nil
end

-- The modifier's weather while one with weather runs, else the map's.
local function currentKind(): Types.WeatherKind
	local modifier = runningModifier()
	if modifier and modifier.weather then
		return modifier.weather
	end
	local themeId = workspace:GetAttribute("MapTheme")
	local theme = if type(themeId) == "string" then MapThemes.themes[themeId] else nil
	return if theme then theme.weather else "none"
end

-- Sky effects --------------------------------------------------------------------------------------------------------

local skyFolder: Folder? = nil
local flash: ColorCorrectionEffect? = nil
local skyEffect: Types.SkyEffect? = nil
local skyToken = 0

local function folder(): Folder
	local existing = skyFolder
	if existing and existing.Parent then
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = "SkyEffects"
	created.Parent = workspace.CurrentCamera
	skyFolder = created
	return created
end

local function glowPart(name: string, size: Vector3, color: Color3, cframe: CFrame): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Size = size
	part.CFrame = cframe
	return part
end

-- A jagged bolt from the clouds to the ground, far from the camera, gone in a blink.
local function bolt(focus: Vector3)
	local angle = random:NextNumber(0, math.pi * 2)
	local distance = random:NextNumber(BOLT_DISTANCE.Min, BOLT_DISTANCE.Max)
	local x = focus.X + math.cos(angle) * distance
	local z = focus.Z + math.sin(angle) * distance
	local model = Instance.new("Model")
	model.Name = "Bolt"
	local top = Vector3.new(x, focus.Y + 190, z)
	local color = Color3.fromRGB(225, 245, 255)
	while top.Y > 2 do
		local bottom = Vector3.new(
			top.X + random:NextNumber(-14, 14),
			math.max(0, top.Y - random:NextNumber(24, 40)),
			top.Z + random:NextNumber(-14, 14)
		)
		local length = (bottom - top).Magnitude
		local mid = (top + bottom) / 2
		glowPart("Segment", Vector3.new(0.9, 0.9, length), color, CFrame.lookAt(mid, bottom)).Parent = model
		top = bottom
	end
	model.Parent = folder()
	task.delay(0.22, function()
		model:Destroy()
	end)
end

-- One strike: a bolt and a soft flash of this client's screen (unless effects are reduced), then thunder.
local function strike()
	if not ClientSettings.reduceEffects() then
		local camera = workspace.CurrentCamera
		bolt(camera.Focus.Position)
		local effect = flash
		if effect == nil or effect.Parent == nil then
			local created = Instance.new("ColorCorrectionEffect")
			created.Name = "LightningFlash" -- this client's own: it never reaches the server or other players
			created.Brightness = 0
			created.Parent = Lighting
			flash = created
			effect = created
		end
		local correction = effect :: ColorCorrectionEffect
		for _ = 1, random:NextInteger(1, 2) do
			correction.Brightness = FLASH_BRIGHTNESS
			TweenService:Create(correction, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Brightness = 0,
			}):Play()
			task.wait(0.24)
		end
	end
	task.wait(random:NextNumber(0.3, 1.3))
	SoundPlayer.world("thunder")
end

-- A shooting star: a glowing ball with a fading trail, crossing part of the sky.
local function meteor()
	local camera = workspace.CurrentCamera
	local focus = camera.Focus.Position
	local start = focus
		+ Vector3.new(
			random:NextNumber(-METEOR_SPREAD, METEOR_SPREAD),
			random:NextNumber(METEOR_HEIGHT.Min, METEOR_HEIGHT.Max),
			random:NextNumber(-METEOR_SPREAD, METEOR_SPREAD)
		)
	local heading = random:NextNumber(0, math.pi * 2)
	local direction = Vector3.new(math.cos(heading), -0.45, math.sin(heading)).Unit
	local distance = random:NextNumber(90, 150)
	local seconds = distance / random:NextNumber(110, 160)
	local head = glowPart(
		"Meteor",
		Vector3.new(1.4, 1.4, 1.4),
		Color3.fromRGB(255, 236, 190),
		CFrame.lookAt(start, start + direction)
	)
	head.Shape = Enum.PartType.Ball
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.6, 0)
	a0.Parent = head
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.6, 0)
	a1.Parent = head
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.45
	trail.LightEmission = 1
	trail.FaceCamera = true
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 240, 200), Color3.fromRGB(160, 120, 255))
	trail.Transparency = NumberSequence.new(0, 1)
	trail.WidthScale = NumberSequence.new(1, 0)
	trail.Parent = head
	head.Parent = folder()
	local tween = TweenService:Create(head, TweenInfo.new(seconds, Enum.EasingStyle.Linear), {
		CFrame = head.CFrame + direction * distance,
	})
	tween.Completed:Once(function()
		head.Transparency = 1
		task.delay(trail.Lifetime, function()
			head:Destroy()
		end)
	end)
	tween:Play()
end

-- Starts (or stops, with nil) the running sky effect's loop.
local function setSkyEffect(effect: Types.SkyEffect?)
	if effect == skyEffect then
		return
	end
	skyEffect = effect
	skyToken += 1
	local token = skyToken
	if effect == nil then
		return
	end
	task.spawn(function()
		while token == skyToken do
			if effect == "lightning" then
				task.wait(random:NextNumber(STRIKE_GAP.Min, STRIKE_GAP.Max))
				if token == skyToken then
					strike()
				end
			else
				task.wait(random:NextNumber(METEOR_GAP.Min, METEOR_GAP.Max))
				if token == skyToken and not ClientSettings.reduceEffects() then
					meteor()
				end
			end
		end
	end)
end

local function refresh()
	clear()
	local modifier = runningModifier()
	setSkyEffect(if modifier then modifier.skyEffect else nil)
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
	workspace:GetAttributeChangedSignal("Modifier"):Connect(refresh)
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
