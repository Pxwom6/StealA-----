--!strict
--[[
	The world's look around the gameplay geometry: lighting, the spawn plaza, trees, the boundary wall and the terrain
	outside it. Plain data only; colours live in Config/Theme.world.

	Nothing here changes how the game plays: plots, the belt, the walkway and their names/attributes are built from
	Config/Gameplay.map by MapBuilder. Logic/SceneryLayout turns this into positions, and CI checks that no prop lands
	on a plot, the belt, the walkway, the lobby spawn or a Halloween decoration, that the terrain stays outside the
	boundary wall, and that the extra parts stay under `partBudget`.

	Map reminder (studs): plots span x -127..127 and |z| 22..100, the belt runs along X through the middle
	(x -136..136), the walkway is x -157..157, |z| < 22. The Snack Factory sits on the belt's west end, the chute on
	its east end, and the spawn plaza past the chute (Gameplay.map.lobby is on it).
]]

local Types = require("../Types")

local Scenery: Types.SceneryConfig = {
	-- A bright, warm afternoon. SeasonService snapshots these values when a seasonal theme starts and restores them
	-- when it ends.
	lighting = {
		clockTime = 14.6,
		geographicLatitude = 35,
		brightness = 2.4,
		exposureCompensation = 0.1,
		ambient = "#70778C",
		outdoorAmbient = "#A3A8BA",
		colorShiftTop = "#FFF0D6", -- warm sunlight
		colorShiftBottom = "#000000",
		environmentDiffuseScale = 0.6,
		environmentSpecularScale = 0.5,
		shadowSoftness = 0.25,
		atmosphere = {
			density = 0.24, -- soft depth haze; the far end of the map stays readable
			offset = 0.15,
			color = "#C7DDF3",
			decay = "#7393B3",
			glare = 0.15,
			haze = 1,
		},
		colorCorrection = { tint = "#FFFCF5", brightness = 0.02, contrast = 0.06, saturation = 0.12 },
		bloom = { intensity = 0.5, size = 24, threshold = 2 }, -- only neon glows
		sunRays = { intensity = 0.04, spread = 0.6 },
		sky = { sunAngularSize = 16, moonAngularSize = 11, starCount = 3000 },
		clouds = { cover = 0.5, density = 0.6, color = "#FFFFFF" },
	},

	boundary = {
		minX = -236,
		maxX = 244,
		minZ = -136,
		maxZ = 136,
		wallHeight = 3,
		wallThickness = 2.4,
		barrierHeight = 20,
	},

	terrain = {
		extent = 640,
		depth = 12,
		-- Smallish spheres sunk into the ground (cheap to fill and to replicate): gentle hills on the horizon.
		hills = {
			{ x = -430, z = -250, radius = 85, height = 38 },
			{ x = -470, z = 30, radius = 90, height = 42 },
			{ x = -400, z = 290, radius = 80, height = 36 },
			{ x = -130, z = 370, radius = 85, height = 38 },
			{ x = 150, z = 410, radius = 90, height = 42 },
			{ x = 430, z = 330, radius = 85, height = 38 },
			{ x = 510, z = -30, radius = 90, height = 42 },
			{ x = 390, z = -330, radius = 85, height = 36 },
			{ x = 70, z = -400, radius = 90, height = 40 },
			{ x = -210, z = -410, radius = 85, height = 36 },
			{ x = 300, z = -480, radius = 85, height = 38 },
			{ x = -330, z = 470, radius = 80, height = 34 },
		},
		rocks = {
			{ x = -262, z = 70, radius = 5 },
			{ x = -290, z = -96, radius = 7 },
			{ x = 282, z = -64, radius = 6 },
			{ x = 268, z = 96, radius = 5 },
			{ x = -96, z = 168, radius = 6 },
			{ x = 84, z = -170, radius = 7 },
			{ x = 196, z = 176, radius = 5 },
			{ x = -186, z = -176, radius = 7 },
			{ x = -30, z = -190, radius = 5 },
			{ x = 40, z = 186, radius = 6 },
		},
		lake = { x = 330, z = 185, radius = 44, depth = 5 },
	},

	plaza = {
		x = 200,
		z = 0,
		radius = 26,
		fountainRadius = 8,
		archX = 165,
		archSpan = 26,
		pathWidth = 16,
		boardX = 158,
		boardZ = 36,
		benchRadius = 17,
		benchAngles = { 45, 90, 135, -45, -90, -135 },
		lampRadius = 24,
		lampAngles = { 67.5, 112.5, 157.5, -67.5, -112.5, -157.5 },
		flowerRadius = 21,
		flowerAngles = { 0, 22.5, -22.5 },
		extraFlowerBeds = {
			{ x = 165, z = 19, yaw = 90 }, -- at the foot of the archway
			{ x = 165, z = -19, yaw = 90 },
		},
		treeRadius = 33,
		treeAngles = { 0, 36, 72, 108, 144, -36, -72, -108, -144 },
	},

	-- Trees around the bases (behind the plots and at the map ends). Default kind "round", scale 1.
	trees = {
		-- behind the north row of plots
		{ x = -214, z = 116 },
		{ x = -176, z = 121, kind = "pine" },
		{ x = -138, z = 117, scale = 1.15 },
		{ x = -101, z = 120, kind = "pine" },
		{ x = -64, z = 116 },
		{ x = -27, z = 121, kind = "pine", scale = 1.1 },
		{ x = 11, z = 117 },
		{ x = 48, z = 120, kind = "pine" },
		{ x = 86, z = 116, scale = 1.2 },
		{ x = 123, z = 121, kind = "pine" },
		{ x = 161, z = 117 },
		{ x = 199, z = 121, kind = "pine", scale = 1.15 },
		{ x = 230, z = 112, scale = 0.9 },
		-- behind the south row
		{ x = -222, z = -118, kind = "pine" },
		{ x = -186, z = -114, scale = 1.1 },
		{ x = -150, z = -120, kind = "pine" },
		{ x = -112, z = -116 },
		{ x = -75, z = -121, kind = "pine", scale = 1.15 },
		{ x = -38, z = -115 },
		{ x = 0, z = -119, kind = "pine" },
		{ x = 37, z = -116, scale = 1.2 },
		{ x = 74, z = -121, kind = "pine" },
		{ x = 112, z = -115 },
		{ x = 150, z = -119, kind = "pine", scale = 1.1 },
		{ x = 188, z = -116 },
		{ x = 226, z = -120, kind = "pine" },
		-- behind the Snack Factory
		{ x = -205, z = -48 },
		{ x = -212, z = 52, kind = "pine", scale = 1.2 },
		{ x = -190, z = 84 },
		{ x = -196, z = -86, kind = "pine" },
		{ x = -184, z = 30, scale = 0.9 },
		-- beside the plaza
		{ x = 214, z = 64, kind = "pine" },
		{ x = 224, z = -66 },
		{ x = 186, z = 74, scale = 1.1 },
		{ x = 190, z = -76, kind = "pine", scale = 1.15 },
	},

	treeLine = { count = 30, minDistance = 14, maxDistance = 40, seed = 17 },

	chevronSpacing = 8,

	partBudget = 1500,
}

return Scenery
