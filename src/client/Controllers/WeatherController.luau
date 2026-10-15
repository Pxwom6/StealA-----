--!strict
--[[
	Weather for the current map theme (Config/MapThemes `weather`): particles drifting around this player's camera —
	snow, embers, falling leaves, fireflies, candy sprinkles, desert dust, petals, stardust, pollen, feathers, bubbles,
	chocolate shavings, confetti, lemonade fizz, heat shimmer, spring blossom, popping popcorn, breakfast steam, barbecue
	smoke or rain. One invisible box follows the camera
	(it lives under the Camera, so only this client has it) and its emitter fills the air around you, which is far
	cheaper than covering the whole map.

	A weather modifier (Config/Modifiers: Thunderstorm, Meteor Shower, Toxic Fog, Northern Lights, Heatwave, Eclipse)
	replaces the map's particles with its own (rain, glowing spores, heat shimmer) while it runs, and adds its sky
	effect: lightning (a far-off bolt, a soft flash of this client's screen and a rumble of thunder every 6-14
	seconds), shooting stars streaking across the sky, an aurora (ribbons of light all around the sky, swaying and
	shimmering), or the eclipsed sun (a black disc in a ring of fire where the sun was: as it starts, the disc slides
	across the bright sun, then its streamers turn slowly). The server changes the lighting itself (ModifierService),
	and an eclipse's takes the sky's own sun away.

	A seasonal theme with weather of its own (Config/Seasons, e.g. Winter's snow) replaces the map's particles while
	it is on; a weather modifier still wins over it.

	Off with Settings > Reduce effects (only the thunder stays, and the eclipsed sun, standing still), and while there
	is no weather. The kinds come from the server through the workspace attributes MapTheme, SeasonTheme and Modifier.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local MapThemes = require(ReplicatedStorage.Shared.Config.MapThemes)
local Modifiers = require(ReplicatedStorage.Shared.Config.Modifiers)
local Seasons = require(ReplicatedStorage.Shared.Config.Seasons)
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
-- Aurora: ribbons around the camera (yaw of each ribbon's middle in degrees, its distance and height, its colours
-- end to end), how long and tall they are, and how fast they sway and shimmer.
local AURORA_RIBBONS = {
	{ yaw = 0, distance = 270, height = 110, colors = { "#3CF0B4", "#2EE8E0", "#9A6BFF" } },
	{ yaw = 72, distance = 290, height = 125, colors = { "#7CFF9A", "#3CF0B4", "#2EC8E8" } },
	{ yaw = 144, distance = 280, height = 115, colors = { "#3CF0B4", "#B07CFF", "#FF7CC8" } },
	{ yaw = 216, distance = 285, height = 100, colors = { "#2EE8A8", "#2EC8E8", "#7C9AFF" } },
	{ yaw = 288, distance = 265, height = 130, colors = { "#9AFF7C", "#3CF0B4", "#9A6BFF" } },
}
local AURORA_LENGTH = 380
local AURORA_WIDTH = 60
local AURORA_SWAY = 70 -- studs the ribbons bend
local AURORA_STEP = 1 / 20
-- Eclipse: a billboard far out in the sun's direction (so it keeps its size and place as the camera moves), its side a
-- share of that distance. Every size below is a share of the billboard: a soft glow from gold through rose to violet,
-- long pale streamers, a rim going from gold to white-hot, the dark disc, and one bright bead on the rim. It slides in
-- over ECLIPSE_IN_SECONDS (the time the lighting takes to darken, ModifierService) and the streamers turn ECLIPSE_TURN
-- degrees a second; with Reduce effects it stands still, already eclipsed.
local ECLIPSE_DISTANCE = 1200
local ECLIPSE_SPAN = 0.32
local ECLIPSE_MOON = 0.27
local ECLIPSE_MOON_COLOR = "#0B0814"
local ECLIPSE_SUN_COLOR = "#FFF6DC"
local ECLIPSE_GLOW = {
	{ size = 1, color = "#7A3CE0", transparency = 0.9 },
	{ size = 0.78, color = "#C84DFF", transparency = 0.84 },
	{ size = 0.6, color = "#FF5FA0", transparency = 0.74 },
	{ size = 0.47, color = "#FF8F57", transparency = 0.6 },
	{ size = 0.37, color = "#FFC870", transparency = 0.4 },
	{ size = 0.31, color = "#FFE9B0", transparency = 0.15 },
}
local ECLIPSE_RIM = { { size = 0.292, color = "#FFB347" }, { size = 0.281, color = "#FFF8E8" } }
local ECLIPSE_STREAMERS = {
	{ angle = 12, length = 0.95, width = 0.02 },
	{ angle = 58, length = 0.72, width = 0.015 },
	{ angle = 103, length = 0.88, width = 0.018 },
	{ angle = 141, length = 0.66, width = 0.013 },
	{ angle = 172, length = 0.8, width = 0.016 },
}
local ECLIPSE_STREAMER_COLOR = "#FFE9B8"
local ECLIPSE_STREAMER_FADE =
	{ { 0, 1 }, { 0.22, 0.75 }, { 0.38, 0.25 }, { 0.5, 0.15 }, { 0.62, 0.25 }, { 0.78, 0.75 }, { 1, 1 } }
local ECLIPSE_BEAD = { angle = 140, size = 0.034, glow = 0.1 } -- upper left: the last of the sun as the disc arrives
local ECLIPSE_IN_SECONDS = 4
local ECLIPSE_TURN = 1.5
local ECLIPSE_STEP = 1 / 20
-- When it starts, the light changes first (the sun moving to where the eclipse will be): the eclipse waits until the
-- time of day has stood still this long (at most ECLIPSE_SETTLE_MAX), then starts there; the server hides the sky's own
-- sun a moment later (WorldLighting).
local ECLIPSE_SETTLE = 0.5
local ECLIPSE_SETTLE_MAX = 8

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
	-- Chocolate shavings curling down, dark and white.
	shavings = {
		boxSize = Vector3.new(110, 1, 110),
		offset = Vector3.new(0, 30, 0),
		props = {
			Texture = SPARKLE,
			Color = colours({ Color3.fromRGB(110, 62, 34), Color3.fromRGB(150, 98, 60), Color3.fromRGB(246, 234, 216) }),
			Size = sequence({ { 0, 0.5 }, { 1, 0.42 } }),
			Transparency = sequence({ { 0, 0.05 }, { 0.85, 0.1 }, { 1, 1 } }),
			Speed = NumberRange.new(3, 5),
			SpreadAngle = Vector2.new(30, 30),
			Acceleration = Vector3.new(1.2, -0.6, 0.8),
			Lifetime = NumberRange.new(7, 9),
			Rate = 16,
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-160, 160),
			EmissionDirection = Enum.NormalId.Bottom,
		},
	},
	-- Carnival confetti fluttering down in bright colours.
	confetti = {
		boxSize = Vector3.new(100, 1, 100),
		offset = Vector3.new(0, 30, 0),
		props = {
			Texture = SPARKLE,
			Color = colours({
				Color3.fromRGB(255, 92, 138),
				Color3.fromRGB(255, 210, 63),
				Color3.fromRGB(77, 168, 255),
				Color3.fromRGB(61, 220, 132),
				Color3.fromRGB(182, 120, 255),
			}),
			LightEmission = 0.25,
			Size = sequence({ { 0, 0.36 }, { 1, 0.3 } }),
			Speed = NumberRange.new(2.5, 4.5),
			SpreadAngle = Vector2.new(35, 35),
			Acceleration = Vector3.new(0.8, -0.4, 0.5),
			Drag = 0.4,
			Lifetime = NumberRange.new(7, 9),
			Rate = 30,
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-260, 260),
			EmissionDirection = Enum.NormalId.Bottom,
		},
	},
	-- Lemonade fizz: tiny bubbles rising everywhere, catching the sun.
	fizz = {
		boxSize = Vector3.new(100, 10, 100),
		offset = Vector3.new(0, -4, 0),
		props = {
			Texture = SPARKLE,
			Color = colours({ Color3.fromRGB(255, 250, 220), Color3.fromRGB(255, 233, 122) }),
			LightEmission = 0.5,
			Size = sequence({ { 0, 0.1 }, { 0.5, 0.22 }, { 1, 0 } }),
			Speed = NumberRange.new(2, 4),
			SpreadAngle = Vector2.new(15, 15),
			Acceleration = Vector3.new(0.2, 1.2, 0.1),
			Lifetime = NumberRange.new(3, 5),
			Rate = 45,
			EmissionDirection = Enum.NormalId.Top,
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
	-- Heat shimmer: faint wavy wisps rising off the ground on a blazing day (Heatwave).
	heat = {
		boxSize = Vector3.new(100, 2, 100),
		offset = Vector3.new(0, -5, 0),
		props = {
			Texture = SMOKE,
			Color = colours({ Color3.fromRGB(255, 244, 224) }),
			Size = sequence({ { 0, 1.5 }, { 1, 4 } }),
			Transparency = sequence({ { 0, 1 }, { 0.3, 0.88 }, { 0.7, 0.9 }, { 1, 1 } }),
			Speed = NumberRange.new(2, 4),
			SpreadAngle = Vector2.new(10, 10),
			Acceleration = Vector3.new(0, 0.8, 0),
			Lifetime = NumberRange.new(2.5, 4),
			Rate = 20,
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-30, 30),
			EmissionDirection = Enum.NormalId.Top,
		},
	},
	-- Spring blossom (Easter): soft petals in pale pink, white, lilac and lemon, drifting down slowly and swirling.
	blossoms = {
		boxSize = Vector3.new(110, 1, 110),
		offset = Vector3.new(0, 30, 0),
		props = {
			Texture = SMOKE,
			Color = colours({
				Color3.fromRGB(255, 196, 222),
				Color3.fromRGB(255, 255, 255),
				Color3.fromRGB(226, 208, 255),
				Color3.fromRGB(255, 244, 176),
			}),
			Size = sequence({ { 0, 0.34 }, { 1, 0.28 } }),
			Transparency = sequence({ { 0, 0.05 }, { 0.85, 0.1 }, { 1, 1 } }),
			Speed = NumberRange.new(2, 3.2),
			SpreadAngle = Vector2.new(35, 35),
			Acceleration = Vector3.new(1.6, -0.2, 1),
			Lifetime = NumberRange.new(8, 10),
			Rate = 22,
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-120, 120),
			EmissionDirection = Enum.NormalId.Bottom,
		},
	},
	-- Popcorn popping all around: buttery puffs jump up from the ground and tumble back down.
	popcorn = {
		boxSize = Vector3.new(90, 1, 90),
		offset = Vector3.new(0, -7, 0),
		props = {
			Texture = SMOKE,
			Color = colours({ Color3.fromRGB(255, 248, 226), Color3.fromRGB(255, 226, 140) }),
			Size = sequence({ { 0, 0.5 }, { 1, 0.42 } }),
			Transparency = sequence({ { 0, 0 }, { 0.85, 0.05 }, { 1, 1 } }),
			Speed = NumberRange.new(14, 20),
			SpreadAngle = Vector2.new(25, 25),
			Acceleration = Vector3.new(0, -30, 0),
			Lifetime = NumberRange.new(1.2, 1.5),
			Rate = 18,
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-200, 200),
			EmissionDirection = Enum.NormalId.Top,
		},
	},
	-- Steam rising off a hot breakfast: soft white wisps drifting up and fading.
	steam = {
		boxSize = Vector3.new(100, 2, 100),
		offset = Vector3.new(0, -5, 0),
		props = {
			Texture = SMOKE,
			Color = colours({ Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 244, 228) }),
			Size = sequence({ { 0, 1.2 }, { 1, 4.5 } }),
			Transparency = sequence({ { 0, 1 }, { 0.25, 0.72 }, { 0.7, 0.8 }, { 1, 1 } }),
			Speed = NumberRange.new(1.5, 3),
			SpreadAngle = Vector2.new(15, 15),
			Acceleration = Vector3.new(0.4, 0.6, 0.2),
			Lifetime = NumberRange.new(3, 5),
			Rate = 16,
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-25, 25),
			EmissionDirection = Enum.NormalId.Top,
		},
	},
	-- Barbecue smoke at sundown: faint grey wisps rolling low and sideways across the ground.
	smoke = {
		boxSize = Vector3.new(110, 2, 110),
		offset = Vector3.new(0, -5, 0),
		props = {
			Texture = SMOKE,
			Color = colours({ Color3.fromRGB(206, 192, 182), Color3.fromRGB(156, 142, 134) }),
			Size = sequence({ { 0, 2 }, { 1, 6 } }),
			Transparency = sequence({ { 0, 1 }, { 0.3, 0.8 }, { 0.75, 0.86 }, { 1, 1 } }),
			Speed = NumberRange.new(0.8, 1.6),
			SpreadAngle = Vector2.new(30, 30),
			Acceleration = Vector3.new(1.6, 0.25, 0.6),
			Lifetime = NumberRange.new(5, 8),
			Rate = 10,
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-15, 15),
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

-- The modifier's weather while one with weather runs, else the seasonal theme's (if it has one), else the map's.
local function currentKind(): Types.WeatherKind
	local modifier = runningModifier()
	if modifier and modifier.weather then
		return modifier.weather
	end
	local seasonId = workspace:GetAttribute("SeasonTheme")
	local season = if type(seasonId) == "string" then Seasons.themes[seasonId] else nil
	if season and season.weather then
		return season.weather
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

-- The aurora: one invisible anchor following the camera, with a ribbon (a Beam between two attachments) on each side
-- of the sky. Returns the anchor and a function that sways and shimmers the ribbons at time `t`.
local function buildAurora(): (Part, (t: number) -> ())
	local anchor = Instance.new("Part")
	anchor.Name = "Aurora"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	local beams: { Beam } = {}
	for index, ribbon in AURORA_RIBBONS do
		local yaw = math.rad(ribbon.yaw)
		local middle = Vector3.new(math.sin(yaw) * ribbon.distance, ribbon.height, math.cos(yaw) * ribbon.distance)
		local along = Vector3.new(math.cos(yaw), 0, -math.sin(yaw)) * AURORA_LENGTH / 2
		local a0 = Instance.new("Attachment")
		a0.Name = `Start{index}`
		a0.Position = middle - along
		a0.Parent = anchor
		local a1 = Instance.new("Attachment")
		a1.Name = `End{index}`
		a1.Position = middle + along + Vector3.new(0, 25, 0)
		a1.Parent = anchor
		local list: { Color3 } = {}
		for _, hex in ribbon.colors do
			table.insert(list, Color3.fromHex(hex))
		end
		local beam = Instance.new("Beam")
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.Color = colours(list)
		beam.Width0 = AURORA_WIDTH
		beam.Width1 = AURORA_WIDTH * 1.3
		beam.FaceCamera = true
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Segments = 24
		beam.Parent = anchor
		table.insert(beams, beam)
	end
	local function animate(t: number)
		for index, beam in beams do
			local phase = index * 1.7
			beam.CurveSize0 = math.sin(t * 0.25 + phase) * AURORA_SWAY
			beam.CurveSize1 = math.cos(t * 0.21 + phase * 1.3) * AURORA_SWAY
			-- brighter bands drifting along the ribbon
			local shift = (t * 0.05 + index * 0.23) % 1
			beam.Transparency = sequence({
				{ 0, 1 },
				{ 0.12, 0.75 + 0.15 * math.sin(t * 0.9 + phase) },
				{ 0.35, 0.55 + 0.2 * math.sin(t * 0.7 + phase + shift * 6) },
				{ 0.6, 0.6 + 0.2 * math.cos(t * 0.8 + phase - shift * 6) },
				{ 0.85, 0.7 + 0.15 * math.sin(t * 1.1 + phase) },
				{ 1, 1 },
			})
		end
	end
	animate(0)
	return anchor, animate
end

-- Runs the aurora until the sky effect changes (token): built while effects are on, gone while they are reduced.
local function auroraLoop(token: number)
	local built: { anchor: Part, animate: (t: number) -> () }? = nil
	while token == skyToken do
		if ClientSettings.reduceEffects() then
			if built then
				built.anchor:Destroy()
				built = nil
			end
		else
			if built == nil or built.anchor.Parent == nil then
				local anchor, animate = buildAurora()
				anchor.Parent = folder()
				built = { anchor = anchor, animate = animate }
			end
			local current = built
			if current then
				current.anchor.CFrame = CFrame.new(workspace.CurrentCamera.Focus.Position)
				current.animate(os.clock())
			end
		end
		task.wait(AURORA_STEP)
	end
	if built then
		built.anchor:Destroy()
	end
end

-- One round frame of the eclipse billboard, `size` a share of it, centred unless moved.
local function disc(parent: Instance, size: number, color: string, transparency: number, z: number): Frame
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(size, size)
	frame.BackgroundColor3 = Color3.fromHex(color)
	frame.BackgroundTransparency = transparency
	frame.BorderSizePixel = 0
	frame.ZIndex = z
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = frame
	frame.Parent = parent
	return frame
end

type EclipseLayer = { frame: Frame, transparency: number }

-- The eclipsed sun on an invisible anchor. Returns the anchor and a function that draws it at `progress` (0: the dark
-- disc beside the bright sun, 1: eclipsed) with its streamers turned for time `t` (nil: as built).
local function buildEclipse(): (Part, (progress: number, t: number?) -> ())
	local anchor = Instance.new("Part")
	anchor.Name = "Eclipse"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	local gui = Instance.new("BillboardGui")
	gui.Name = "EclipseSun"
	gui.Size = UDim2.fromScale(ECLIPSE_DISTANCE * ECLIPSE_SPAN, ECLIPSE_DISTANCE * ECLIPSE_SPAN)
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false -- hills and buildings in front of it still hide it
	gui.Parent = anchor
	-- the corona: fades in as the disc covers the sun
	local corona: { EclipseLayer } = {}
	for index, ring in ECLIPSE_GLOW do
		table.insert(
			corona,
			{ frame = disc(gui, ring.size, ring.color, ring.transparency, index), transparency = ring.transparency }
		)
	end
	local streamers: { { frame: Frame, angle: number } } = {}
	for _, streamer in ECLIPSE_STREAMERS do
		local frame = Instance.new("Frame")
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.fromScale(0.5, 0.5)
		frame.Size = UDim2.fromScale(streamer.length, streamer.width)
		frame.Rotation = streamer.angle
		frame.BackgroundColor3 = Color3.fromHex(ECLIPSE_STREAMER_COLOR)
		frame.BorderSizePixel = 0
		frame.ZIndex = #ECLIPSE_GLOW + 1
		local fade = Instance.new("UIGradient")
		fade.Transparency = sequence(ECLIPSE_STREAMER_FADE)
		fade.Parent = frame
		frame.Parent = gui
		table.insert(corona, { frame = frame, transparency = 0 })
		table.insert(streamers, { frame = frame, angle = streamer.angle })
	end
	local z = #ECLIPSE_GLOW + 2
	local sun = disc(gui, ECLIPSE_MOON, ECLIPSE_SUN_COLOR, 0, z)
	for index, rim in ECLIPSE_RIM do
		table.insert(corona, { frame = disc(gui, rim.size, rim.color, 0, z + index), transparency = 0 })
	end
	local moon = disc(gui, ECLIPSE_MOON, ECLIPSE_MOON_COLOR, 0, z + #ECLIPSE_RIM + 1)
	local beadAngle = math.rad(ECLIPSE_BEAD.angle)
	local radius = ECLIPSE_RIM[1].size / 2
	local beadAt = UDim2.fromScale(0.5 + math.cos(beadAngle) * radius, 0.5 - math.sin(beadAngle) * radius)
	local beadGlow = disc(gui, ECLIPSE_BEAD.glow, ECLIPSE_GLOW[#ECLIPSE_GLOW].color, 0.55, z + #ECLIPSE_RIM + 2)
	beadGlow.Position = beadAt
	local bead = disc(gui, ECLIPSE_BEAD.size, ECLIPSE_SUN_COLOR, 0, z + #ECLIPSE_RIM + 3)
	bead.Position = beadAt
	table.insert(corona, { frame = beadGlow, transparency = 0.55 })
	table.insert(corona, { frame = bead, transparency = 0 })

	local function draw(progress: number, t: number?)
		-- the disc slides in from the lower right and slows as it covers the sun; the corona lights up at the end
		local slide = 1 - (1 - math.clamp(progress, 0, 1)) ^ 2
		moon.Position = UDim2.fromScale(0.5 + 0.2 * (1 - slide), 0.5 + 0.09 * (1 - slide))
		local lit = math.clamp((progress - 0.75) / 0.25, 0, 1)
		sun.BackgroundTransparency = lit
		for _, layer in corona do
			layer.frame.BackgroundTransparency = 1 - (1 - layer.transparency) * lit
		end
		if t then
			for _, streamer in streamers do
				streamer.frame.Rotation = streamer.angle + t * ECLIPSE_TURN
			end
		end
	end
	draw(1, nil)
	return anchor, draw
end

-- Runs the eclipsed sun until the sky effect changes (token), always where the sun is (Lighting:GetSunDirection).
-- `animate`: it starts now, so once the light has settled the disc slides over the sun (not with Reduce effects, nor
-- for a player who joins while it is already on).
local function eclipseLoop(token: number, animate: boolean)
	if animate then
		local last, still, waited = Lighting.ClockTime, 0, 0
		while token == skyToken and still < ECLIPSE_SETTLE and waited < ECLIPSE_SETTLE_MAX do
			task.wait(ECLIPSE_STEP)
			waited += ECLIPSE_STEP
			local clock = Lighting.ClockTime
			still = if clock == last then still + ECLIPSE_STEP else 0
			last = clock
		end
		if token ~= skyToken then
			return
		end
	end
	local anchor, draw = buildEclipse()
	local gui = anchor:FindFirstChildOfClass("BillboardGui")
	anchor.Parent = folder()
	local started = os.clock()
	while token == skyToken do
		local camera = workspace.CurrentCamera
		local direction = Lighting:GetSunDirection()
		anchor.CFrame = CFrame.new(camera.CFrame.Position + direction * ECLIPSE_DISTANCE)
		if gui then
			gui.Enabled = direction.Y > -0.03
		end
		local reduced = ClientSettings.reduceEffects()
		local progress = if animate and not reduced
			then math.clamp((os.clock() - started) / ECLIPSE_IN_SECONDS, 0, 1)
			else 1
		draw(progress, if reduced then nil else os.clock())
		task.wait(ECLIPSE_STEP)
	end
	anchor:Destroy()
end

-- Starts (or stops, with nil) the running sky effect's loop. `animate`: the effect starts now (not when this client
-- joins with it already running).
local function setSkyEffect(effect: Types.SkyEffect?, animate: boolean)
	if effect == skyEffect then
		return
	end
	skyEffect = effect
	skyToken += 1
	local token = skyToken
	if effect == nil then
		return
	end
	if effect == "aurora" then
		task.spawn(auroraLoop, token)
		return
	elseif effect == "eclipse" then
		task.spawn(eclipseLoop, token, animate)
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

local refreshedOnce = false -- the first refresh (this client joining) shows a running sky effect as it already is

local function refresh()
	clear()
	local modifier = runningModifier()
	setSkyEffect(if modifier then modifier.skyEffect else nil, refreshedOnce)
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
	workspace:GetAttributeChangedSignal("SeasonTheme"):Connect(refresh)
	workspace:GetAttributeChangedSignal("Modifier"):Connect(refresh)
	local reduced = ClientSettings.reduceEffects()
	ClientSettings.onChanged(function(settings)
		if settings.reduceEffects ~= reduced then
			reduced = settings.reduceEffects
			refresh()
		end
	end)
	refresh()
	refreshedOnce = true
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
