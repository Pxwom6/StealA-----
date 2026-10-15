--!strict
--[[
	Base skins: a look for the player's own base, picked in Settings ▸ Style ▸ Base. Earned from achievements, rebirths
	and Snackdex tiers (Logic/StyleRules), never Robux. Plain data only.

	A skin only recolours a base's cosmetic surfaces (server/Services/MapBuilder.paintPlot): the floor's checker tiles,
	the rug down the aisle, the wall tops and the corner caps. The walls keep the plot's own colour, and the sign,
	podiums, collect pads, lock button and upgrade pad never change, so a base reads the same on every map. CI keeps
	every floor colour as far from the collect pads' green as the Classic floors are (StyleRules.MIN_PAD_CONTRAST).
	Map changes never repaint a base: a skin stays on until its owner picks another or leaves. VIP's golden trim is
	the Classic look for VIP players; with another skin they keep the gold corner caps.

	id       the equipped one is saved as the flag skin_<id> (none = `default`): never rename one that has shipped
	look     nil = the plot's own colours. tiles: two or more colours, alternated over the floor; materials are
	         Enum.Material names (StyleRules.FLOOR_MATERIALS / TRIM_MATERIALS); rainbow = the trims cycle through the
	         rainbow on clients (off with Reduce effects)
	unlock   like a title's (Config/Titles)
]]

local Types = require("../Types")

local Skins: Types.SkinsConfig = {
	list = {
		{ id = "classic", name = "Classic", icon = "🏠", look = nil, unlock = { kind = "free" } },
		{
			id = "sprinklePink",
			name = "Sprinkle Pink",
			icon = "🍩",
			look = {
				tiles = { "#FFB3D4", "#FF85BA" },
				tileMaterial = "CeramicTiles",
				rug = "#FFF0E0",
				rugMaterial = "Fabric",
				trim = "#FF4F9A",
				trimMaterial = "SmoothPlastic",
			},
			unlock = { kind = "achievement", id = "epicTaste" },
		},
		{
			id = "mintChip",
			name = "Mint Chip",
			icon = "🍨",
			look = {
				tiles = { "#BDF0DA", "#93DFC0" },
				tileMaterial = "CeramicTiles",
				rug = "#5A3A26",
				rugMaterial = "Fabric",
				trim = "#3E2618",
				trimMaterial = "SmoothPlastic",
			},
			unlock = { kind = "tiers", count = 1 },
		},
		{
			id = "blueberry",
			name = "Blueberry",
			icon = "🫐",
			look = {
				tiles = { "#A9B4FF", "#7F8CEB" },
				tileMaterial = "CeramicTiles",
				rug = "#3E4AA8",
				rugMaterial = "Fabric",
				trim = "#E6EAFF",
				trimMaterial = "SmoothPlastic",
			},
			unlock = { kind = "achievement", id = "legend" },
		},
		{
			id = "goldenCrust",
			name = "Golden Crust",
			icon = "🥐",
			look = {
				tiles = { "#F0BE5A", "#D99A3A" },
				tileMaterial = "CeramicTiles",
				rug = "#FFE7A0",
				rugMaterial = "Fabric",
				trim = "#9C5A22", -- a toasted crust (VIP's gold stays VIP's)
				trimMaterial = "SmoothPlastic",
			},
			unlock = { kind = "achievement", id = "snackBreak" },
		},
		{
			id = "licoriceNight",
			name = "Licorice Night",
			icon = "🖤",
			look = {
				tiles = { "#3A3346", "#26212F" },
				tileMaterial = "Slate",
				rug = "#C8243A",
				rugMaterial = "Fabric",
				trim = "#FF5CA8",
				trimMaterial = "Neon",
			},
			unlock = { kind = "rebirths", count = 2 },
		},
		{
			id = "rainbowSwirl",
			name = "Rainbow Swirl",
			icon = "🌈",
			look = {
				tiles = { "#FF7A93", "#FFB347", "#FFDD3C", "#B6EE5C", "#5CB8FF", "#A98BFF" },
				tileMaterial = "CeramicTiles",
				rug = "#FFFFFF",
				rugMaterial = "Fabric",
				trim = "#FF7AC8",
				trimMaterial = "SmoothPlastic",
				rainbow = true,
			},
			unlock = { kind = "achievement", id = "mutationMaster" },
		},
		{
			id = "diamond",
			name = "Diamond",
			icon = "💎",
			look = {
				tiles = { "#BFEFFF", "#7FD1F5" },
				tileMaterial = "Marble",
				rug = "#FFFFFF",
				rugMaterial = "Marble",
				trim = "#BFF4FF",
				trimMaterial = "Neon",
			},
			unlock = { kind = "rebirths", count = 4 },
		},
	},
	default = "classic",
}

return Skins
