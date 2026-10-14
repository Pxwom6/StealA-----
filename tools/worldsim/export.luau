--!strict
--[[
	Builds the map offline (tools/worldsim/Sim) and writes it as JSON for a 3D preview:
	    lune run tools/worldsim/export.luau [mapThemeId] [out.json]
	The JSON lists every visible part (shape, size, CFrame components, colour, material), the lights, the lighting and
	the terrain calls in order. Without a map theme id it builds the first one in Config/MapThemes.order.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local Sim = require("./Sim")

local MapThemes = Sim.shared("Config/MapThemes")
local themeId = process.args[1] or MapThemes.order[1]
local out = process.args[2] or `world-{themeId}.json`

local MapBuilder = Sim.server("Services/MapBuilder")
MapBuilder.build(themeId)

local data = Sim.exportWorld()
fs.writeFile(out, serde.encode("json", data))
print(`wrote {out}: {#data.parts} parts, {#data.lights} lights, {#data.terrain.ops} terrain calls`)
