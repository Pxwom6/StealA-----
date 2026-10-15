--!strict
--[[
	Builds a map offline with a base skin on each plot (Config/Skins, in order: plot 1 wears the first) and writes it as
	JSON for the 3D preview, to check how the skins look on that map:
	    lune run tools/worldsim/exportSkins.luau [mapThemeId] [out.json] [--vip]
	    node tools/preview/render.mjs out.json build/skins --cam 0,150,-40:0,0,77:55
	Each plot gets eight active podiums (their collect pads glow) and a few Snacklings, like a base in play; --vip
	gives every owner VIP's golden trim (the corner caps stay gold under a skin). The rainbow skin's trims show their
	server colour (clients animate them).
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local Sim = require("./Sim")

local MapThemes = Sim.shared("Config/MapThemes")
local Skins = Sim.shared("Config/Skins")
local GameData = Sim.shared("GameData")
local CreatureVisuals = Sim.shared("CreatureVisuals")
local MapBuilder = Sim.server("Services/MapBuilder")

local args: { string } = {}
local vip = false
for _, arg in process.args do
	if arg == "--vip" then
		vip = true
	else
		table.insert(args, arg)
	end
end
local themeId = args[1] or MapThemes.order[1]
local out = args[2] or `skins-{themeId}.json`

local world = MapBuilder.build(themeId)
local sample = { "pizza_pup", "sushi_slug", "cookie_crab", "fry_fox" }
for index, plot in world.plots do
	local def = Skins.list[(index - 1) % #Skins.list + 1]
	MapBuilder.paintPlot(plot, def.look, vip)
	for i = 1, 8 do
		local podium = plot.podiums[i]
		MapBuilder.setPodiumActive(podium, true, plot.accent)
		local creatureId = sample[(i - 1) % #sample + 1]
		local creature = GameData.catalog.creatures[creatureId]
		if i <= 4 and creature then
			local model =
				CreatureVisuals.build(creature, GameData.catalog.rarities[creature.rarity], { anchored = true })
			model:PivotTo(podium.standCFrame)
			model.Parent = podium.model
		end
	end
	print(`plot {index}: {def.name}`)
end

local data = Sim.exportWorld()
fs.writeFile(out, serde.encode("json", data))
print(`wrote {out}: {#data.parts} parts`)
