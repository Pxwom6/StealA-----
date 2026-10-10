--!strict
--[[
	Seasonal themes: map decorations and a lighting mood that switch on while a LiveOps event runs. Plain data only.

	A theme is keyed by LiveOps event id (`eventThemes`), so it turns on and off with the event's dates
	(Config/LiveOps `events`, the remote-config DataStore, or `/event <id>`), with no code change. The server
	(SeasonService) checks the active events every second, builds the decorations, fades the lighting in, and on the
	event's end removes every decoration and puts the original lighting back.

	Reusing a theme next year: add the new event to Config/LiveOps and one line here, e.g.
	    eventThemes = { Halloween2026 = "halloween", Halloween2027 = "halloween" }
	A new season (e.g. winter): add a theme below; new prop kinds go in server/Services/SeasonService.luau.

	Every decoration is anchored, non-colliding and invisible to raycasts (CanQuery false), so it never changes
	movement, steals, tagging or plot bounds. Keep each theme within `maxParts` (CI checks the estimate).
]]

local Types = require("../Types")

export type SeasonsConfig = Types.SeasonsConfig

local Seasons: SeasonsConfig = {
	eventThemes = {
		Halloween2026 = "halloween",
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
	},

	maxParts = 240,
	transitionSeconds = 4,
}

return Seasons
