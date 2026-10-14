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
	eventThemes = {
		Halloween2026 = "halloween",
		Winter2026 = "winter",
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
	},

	maxParts = 400, -- Halloween builds 220, Winter 380 (DECISIONS.md #37)
	transitionSeconds = 4,
}

return Seasons
