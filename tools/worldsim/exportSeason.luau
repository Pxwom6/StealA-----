--!strict
--[[
	Builds the map offline with a seasonal event's theme on, and writes it as JSON for a 3D preview (tools/preview):
	    lune run tools/worldsim/exportSeason.luau <mapThemeId> <eventId> [out.json]
	    lune run tools/worldsim/exportSeason.luau meadow Harvest2026 build/harvest-meadow.json
	The real MapBuilder and SeasonService build everything (decorations and the lighting overlay); LiveOps is a stand-in
	that reports only that event as running. Same JSON format as tools/worldsim/export.luau.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local Sim = require("./Sim")

local themeId = process.args[1]
local eventId = process.args[2]
if themeId == nil or eventId == nil then
	error("usage: lune run tools/worldsim/exportSeason.luau <mapThemeId> <eventId> [out.json]")
end
local out = process.args[3] or `world-{themeId}-{eventId}.json`

-- Only this event is running, and it never changes while the script runs.
Sim.mock("src/server/Services/LiveOpsService.luau", {
	activeEventIds = function(): { [string]: boolean }
		return { [eventId] = true }
	end,
	onActiveEventsChanged = function(_listener: (ids: { [string]: boolean }) -> ()) end,
})

local Seasons = Sim.shared("Config/Seasons")
if Seasons.eventThemes[eventId] == nil then
	error(`{eventId} has no seasonal theme in Config/Seasons`)
end
local MapBuilder = Sim.server("Services/MapBuilder")
local SeasonService = Sim.server("Services/SeasonService")
SeasonService.start(MapBuilder.build(themeId))

for _, message in Sim.warnings do
	print(`warning: {message}`)
end
local data = Sim.exportWorld()
fs.writeFile(out, serde.encode("json", data))
print(`wrote {out}: {SeasonService.currentTheme()} on {themeId}, {#data.parts} parts, {#data.lights} lights`)
