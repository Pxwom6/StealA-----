--!strict
--[[
	Seasonal themes: map decorations and a lighting mood that switch on while a LiveOps event runs. Plain data only.

	A theme is keyed by LiveOps event id (`eventThemes`), so it turns on and off with the event's dates
	(Config/LiveOps `events`, the remote-config DataStore, or `/event <id>`), with no code change. The server
	(SeasonService) checks the active events every second, builds the decorations, fades the lighting in, and on the
	event's end removes every decoration and puts the original lighting back.

	Reusing a theme next year: add the new event to Config/LiveOps and one line here, e.g.
	    eventThemes = { Halloween2026 = "halloween", Halloween2027 = "halloween" }
	A new season: add a theme below, mixing any of the props (Types.SeasonDecorations lists them and where they go);
	a new prop kind goes in Logic/SeasonRules (where) and server/Services/SeasonService.luau (how it is built).
	A theme only needs the palette colours of the props it places (Logic/SeasonRules.PALETTE_KEYS; CI checks them).
	`weather` (optional) replaces the map's particles while the theme is on, e.g. "snow"; a weather modifier's still
	wins while one runs. Its music is Config/Sounds `music.<theme id>`.

	Every decoration is anchored, non-colliding and invisible to raycasts (CanQuery false), so it never changes
	movement, steals, tagging or plot bounds. Keep each theme within `maxParts` (CI checks the estimate).
]]

local Types = require("../Types")

export type SeasonsConfig = Types.SeasonsConfig

local Seasons: SeasonsConfig = {
	-- Only one of these events runs at a time (DECISIONS.md #58): starting one ends the others.
	eventThemes = {
		Halloween2026 = "halloween",
		Harvest2026 = "harvest",
		Winter2026 = "winter",
		Valentine2027 = "valentine",
		StPatrick2027 = "clover",
		Easter2027 = "spring",
		Summer2027 = "summer",
	},

	themes = {
		halloween = {
			displayName = "Halloween",
			accentColor = "#FF8C1A",
			priority = 1,
			lighting = {
				clockTime = 17.8, -- dusk
				brightness = 1.6,
				ambient = "#3C3050",
				outdoorAmbient = "#6E5A8C",
				colorShiftTop = "#FF9A4D",
				atmosphere = {
					density = 0.3, -- light fog: the whole map stays readable
					offset = 0.1,
					color = "#9C7FC9",
					decay = "#4A2F6B",
					glare = 0.2,
					haze = 1.6,
				},
				colorCorrection = { tint = "#FFE6D0", brightness = 0, contrast = 0.08, saturation = 0.08 },
			},
			decorations = {
				pumpkinsPerPlot = 2,
				beltPumpkinsPerSide = 4,
				bulbsPerPlot = 6,
				lampsBetweenPlots = true,
				bats = 6,
				ghosts = 4,
			},
			palette = {
				pumpkin = "#F07A12",
				pumpkinFace = "#FFD23F",
				stem = "#3B7A2A",
				bulbs = { "#FF8C1A", "#9B5CFF" },
				lampPost = "#2B2238",
				lampLight = "#FF9F1C",
				bat = "#1E1A2E",
				ghost = "#EDEBFF",
			},
		},

		harvest = {
			displayName = "Harvest Feast",
			accentColor = "#E8A23A",
			priority = 1,
			weather = "leaves", -- autumn leaves drifting down (Apple Pie Orchard's)
			lighting = {
				clockTime = 17.3, -- golden hour: a low warm sun, long shadows, the lanterns just lit
				brightness = 2.3,
				ambient = "#7A5E44",
				outdoorAmbient = "#C9A27A",
				colorShiftTop = "#FFB766",
				atmosphere = {
					density = 0.3, -- a warm golden haze: the whole map stays readable
					offset = 0.12,
					color = "#FFD9A8",
					decay = "#C98A52",
					glare = 0.5,
					haze = 1.7,
				},
				colorCorrection = { tint = "#FFF1DE", brightness = 0.02, contrast = 0.07, saturation = 0.12 },
				clouds = { cover = 0.5, density = 0.45, color = "#FFE6C8" },
			},
			decorations = {
				pumpkinsPerPlot = 2, -- plain harvest pumpkins (no pumpkinFace: they aren't carved)
				hayBalesPerPlot = 2,
				bulbsPerPlot = 6,
				lampsBetweenPlots = true,
				scarecrowsBetweenPlots = true,
				beltCornucopiasPerSide = 3,
				cornStalks = 4,
			},
			palette = {
				pumpkin = "#F07A12",
				stem = "#5E8A2E",
				bulbs = { "#FFB347", "#FF7A2E", "#FFD24A", "#E8452E" },
				lampPost = "#4A3222",
				lampLight = "#FFB347",
				straw = "#E8C766",
				twine = "#8A6236",
				wood = "#7A5236",
				shirt = "#C8452E",
				overalls = "#3E5A8C",
				burlap = "#D9B47A",
				hat = "#6A4A2A",
				wicker = "#C98A3E",
				produce = { "#F28A1E", "#D7262E", "#7A3A9A", "#FFD23F" },
				stalks = "#7E9E3C",
				corn = "#FFC93C",
			},
		},

		winter = {
			displayName = "Winter",
			accentColor = "#4FC3FF",
			priority = 1,
			weather = "snow",
			lighting = {
				clockTime = 17.2, -- late afternoon: low warm sun, long blue shadows, the lights already glowing
				brightness = 1.9,
				ambient = "#4C5878",
				outdoorAmbient = "#97A8CC",
				colorShiftTop = "#FFC98F",
				atmosphere = {
					density = 0.28, -- a light winter haze: the whole map stays readable
					offset = 0.12,
					color = "#E4ECFF",
					decay = "#93A8D6",
					glare = 0.35,
					haze = 1.3,
				},
				colorCorrection = { tint = "#F2F6FF", brightness = 0.02, contrast = 0.06, saturation = 0.04 },
				clouds = { cover = 0.62, density = 0.5, color = "#F4F7FF" },
			},
			decorations = {
				presentsPerPlot = 3,
				beltPresentsPerSide = 3,
				bulbsPerPlot = 8,
				treesBetweenPlots = true,
				snowmen = 4,
				snowflakes = 8,
				snowPilesPerPlot = 2,
			},
			palette = {
				bulbs = { "#FF3B3B", "#2EE66B", "#FFD23F", "#3BA4FF" },
				presents = { "#D7263D", "#2E8B57", "#2F6FD6", "#F2C230", "#8E44D9" },
				ribbons = { "#FFD23F", "#FFFFFF", "#D7263D" },
				tree = "#2E8050",
				wood = "#6B4A2E",
				treeStar = "#FFD54A",
				ornaments = { "#FF3B3B", "#FFD23F", "#3BA4FF", "#FF7BD5" },
				snow = "#F4F8FF",
				carrot = "#FF8A2A",
				coal = "#2A2A30",
				scarf = "#D7263D",
				hat = "#2A2A30",
				snowflake = "#DDF0FF",
			},
		},

		valentine = {
			displayName = "Valentine's",
			accentColor = "#FF4F8B",
			priority = 1,
			weather = "petals",
			lighting = {
				clockTime = 16.8, -- a rosy late afternoon
				brightness = 2.1,
				ambient = "#7A5A6A",
				outdoorAmbient = "#C89AAA",
				colorShiftTop = "#FFB8C8",
				atmosphere = {
					density = 0.28, -- a soft pink haze: the whole map stays readable
					offset = 0.12,
					color = "#FFD6E2",
					decay = "#C88AA8",
					glare = 0.3,
					haze = 1.5,
				},
				colorCorrection = { tint = "#FFF0F4", brightness = 0.02, contrast = 0.06, saturation = 0.1 },
				clouds = { cover = 0.45, density = 0.45, color = "#FFE0EA" },
			},
			decorations = {
				rosesPerPlot = 2,
				beltRosesPerSide = 3,
				bulbsPerPlot = 8,
				lampsBetweenPlots = true,
				heartBalloons = 14,
				giantHearts = 4,
			},
			palette = {
				bulbs = { "#FF4F8B", "#FFFFFF", "#E8204F", "#FFB0CC" },
				lampPost = "#6A2A44",
				lampLight = "#FF9AC0",
				pot = "#F2B8C6",
				leaves = "#3F8F4A",
				roses = { "#E8204F", "#FF5C8A", "#FFFFFF", "#FF9AB8" },
				balloons = { "#FF4F8B", "#E8204F", "#FF9AC0", "#FFFFFF" },
				balloonString = "#FFFFFF",
				heart = "#E8204F",
				pedestal = "#FFF4F8",
				arrow = "#F2C14E",
			},
		},

		spring = {
			displayName = "Easter",
			accentColor = "#B48CFF",
			priority = 1,
			weather = "blossoms",
			lighting = {
				clockTime = 10.2, -- a bright spring morning
				brightness = 2.6,
				ambient = "#8A8A9E",
				outdoorAmbient = "#BFC6DA",
				colorShiftTop = "#FFF2D6",
				atmosphere = {
					density = 0.24, -- a light spring haze
					offset = 0.1,
					color = "#E8F0FF",
					decay = "#BCCBEA",
					glare = 0.2,
					haze = 1.1,
				},
				colorCorrection = { tint = "#FFFCF4", brightness = 0.03, contrast = 0.05, saturation = 0.14 },
				clouds = { cover = 0.5, density = 0.4, color = "#FFFFFF" },
			},
			decorations = {
				eggsPerPlot = 2,
				beltEggsPerSide = 3,
				bulbsPerPlot = 8,
				lampsBetweenPlots = true,
				blossomTreesBetweenPlots = true,
				butterflies = 16,
				chocolateBunnies = 4,
			},
			palette = {
				bulbs = { "#FFB3D9", "#B8F2D6", "#D6C2FF", "#FFF2A6", "#BFE4FF" },
				lampPost = "#8C7AA8",
				lampLight = "#FFF0B8",
				-- each shell is painted in a contrasting colour: pink with sky blue, mint with pink...
				eggs = { "#FFC4E1", "#B8F2D6", "#D6C2FF", "#FFF2A6", "#BFE4FF", "#FFD2B0" },
				eggStripes = { "#5AB8F5", "#FF6FAE", "#FFC93C", "#9A6BFF", "#3FC48A", "#FFFFFF" },
				wood = "#7A5236",
				blossoms = { "#FFC0DA", "#FFFFFF", "#FFA6C9", "#F7D6FF" },
				butterflies = { "#FFD24A", "#7CC8FF", "#FF8FC7", "#B48CFF", "#FF9A4A" },
				butterflyBody = "#3A2A40",
				chocolate = "#5C3018",
				bunnyBow = "#FF8FC7",
			},
		},

		-- St Patrick's ("Lucky Clover"): a rainbow over every gap between two bases with its pot of gold at the foot,
		-- clover patches by the entrances, little pots of chocolate coins along the belt, giant shamrocks at the belt
		-- ends, green and gold string lights, a fresh spring afternoon and clover leaves drifting down. (398 parts: the
		-- rainbows are 31 each, so the string lights are half the usual and the belt has two pots a side.)
		clover = {
			displayName = "Lucky Clover",
			accentColor = "#2FBF5A",
			priority = 1,
			weather = "clovers",
			lighting = {
				clockTime = 14.6, -- a fresh spring afternoon
				brightness = 2.6,
				ambient = "#7E8C82",
				outdoorAmbient = "#B6C8B8",
				colorShiftTop = "#FFF2D8",
				atmosphere = {
					density = 0.22, -- clear spring air
					offset = 0.1,
					color = "#E4F2E6",
					decay = "#A9C8B2",
					glare = 0.25,
					haze = 1.0,
				},
				colorCorrection = { tint = "#F7FFF4", brightness = 0.03, contrast = 0.06, saturation = 0.16 },
				clouds = { cover = 0.42, density = 0.4, color = "#FFFFFF" },
			},
			decorations = {
				cloverPatchesPerPlot = 2,
				beltPotsOfGoldPerSide = 2,
				bulbsPerPlot = 4,
				rainbowsBetweenPlots = true,
				shamrocks = 4,
			},
			palette = {
				bulbs = { "#2EE66B", "#FFD23F", "#9CFF7A", "#1FBF55" },
				rainbow = { "#F23A3A", "#FF8A1A", "#FFD21A", "#2FC452", "#2E8FF0", "#8A4FFF" },
				cloud = "#FFFFFF",
				cauldron = "#2A2A30",
				gold = "#FFC93C",
				clover = "#3BB54A",
			},
		},

		-- Summer Splash: beach umbrellas between the bases, a swim ring and a beach ball by every entrance, beach balls
		-- along the belt, sandcastles at the belt ends, bunting along the front walls, a bright midsummer noon and
		-- sparkling spray in the air.
		summer = {
			displayName = "Summer Splash",
			accentColor = "#18B8E8",
			priority = 1,
			weather = "spray",
			lighting = {
				clockTime = 12.4, -- a bright midsummer noon
				brightness = 2.8,
				ambient = "#8C96A4",
				outdoorAmbient = "#C6D4E0",
				colorShiftTop = "#FFF6E2",
				atmosphere = {
					density = 0.18, -- a clear sky, unlike the Heatwave's haze
					offset = 0.06,
					color = "#DDF1FF",
					decay = "#9AC6E8",
					glare = 0.45,
					haze = 0.7,
				},
				colorCorrection = { tint = "#FFFDF2", brightness = 0.02, contrast = 0.1, saturation = 0.22 },
				clouds = { cover = 0.3, density = 0.35, color = "#FFFFFF" },
			},
			decorations = {
				swimRingsPerPlot = 1,
				beachBallsPerPlot = 1,
				beltBeachBallsPerSide = 3,
				pennantsPerPlot = 12,
				umbrellasBetweenPlots = true,
				sandcastles = 4,
			},
			palette = {
				bulbs = {},
				umbrellas = { "#FF5A5A", "#2FA8FF", "#FFC23A", "#2FD07A", "#FF7AC8", "#7A6BFF" },
				stripe = "#FFFFFF",
				rings = { "#FF5A5A", "#FF9A2E", "#2FA8FF", "#FF5AA8" },
				ballPanels = { "#FF3B3B", "#FFD23F", "#2F8BFF", "#2FD07A" },
				pennants = { "#F23A3A", "#FFB21A", "#1E8BFF", "#1FBF5A", "#FF4FA8" },
				sand = "#E8C27E",
				flag = "#F23A3A",
				bucket = "#2F8BFF",
			},
		},
	},

	maxParts = 400, -- Halloween builds 220, Winter 380 (DECISIONS.md #37), Valentine's 280 (#41), Easter 330 (#44),
	-- Harvest Feast 386 (#50), Lucky Clover 398 and Summer Splash 330 (#59)
	transitionSeconds = 4,
}

return Seasons
