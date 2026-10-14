--!strict
--[[
	Builds Snacklings offline (tools/worldsim/Sim) and writes them as JSON for a 3D preview (tools/preview):
	    lune run tools/worldsim/exportCreatures.luau <out.json> <creatureId[:mutationId]> ...
	    lune run tools/worldsim/exportCreatures.luau out.json pizza_pup pizza_pup:golden sushi_slug:molten
	    lune run tools/worldsim/exportCreatures.luau out.json rarity:Mythic     (every Snackling of a rarity)
	    lune run tools/worldsim/exportCreatures.luau out.json event:Winter2026  (every Snackling of an event)
	    lune run tools/worldsim/exportCreatures.luau out.json mutations:pizza_pup (one Snackling in every mutation)
	They stand in a row along +X on y = 0, facing the way they face on a podium, with a small gap between them, so
	the preview's `front` shot shows every face. Same JSON format as tools/worldsim/export.luau (parts, lights, no
	terrain) plus `labels`: each model's name and where it stands.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local Sim = require("./Sim")

local GameData = Sim.shared("GameData")
local CreatureVisuals = Sim.shared("CreatureVisuals")
local Mutations = Sim.shared("Config/Mutations")
local catalog = GameData.catalog

local out = process.args[1]
if out == nil or #process.args < 2 then
	error("usage: lune run tools/worldsim/exportCreatures.luau <out.json> <creatureId[:mutationId]> ...")
end

local mutationsById: { [string]: any } = {}
for _, mutation in Mutations do
	mutationsById[mutation.id] = mutation
end

-- Expand the arguments into { creature def, mutation def? } pairs.
local wanted: { { def: any, mutation: any? } } = {}
for i = 2, #process.args do
	local arg = process.args[i]
	local kind, value = string.match(arg, "^(%a+):(.+)$")
	if kind == "rarity" then
		for _, def in catalog.creatureList do
			if def.rarity == value then
				table.insert(wanted, { def = def })
			end
		end
	elseif kind == "event" then
		for _, def in catalog.creatureList do
			if def.eventId == value then
				table.insert(wanted, { def = def })
			end
		end
	elseif kind == "mutations" then
		local def = catalog.creatures[value]
		assert(def, `unknown creature {value}`)
		table.insert(wanted, { def = def })
		for _, mutation in Mutations do
			table.insert(wanted, { def = def, mutation = mutation })
		end
	else
		local id, mutationId = string.match(arg, "^([%w_]+):?([%w_]*)$")
		assert(id, `bad argument {arg}`)
		local def = catalog.creatures[id :: string]
		assert(def, `unknown creature {id}`)
		local mutation = nil
		if mutationId and mutationId ~= "" then
			mutation = mutationsById[mutationId]
			assert(mutation, `unknown mutation {mutationId}`)
		end
		table.insert(wanted, { def = def, mutation = mutation })
	end
end

local folder = Sim.Instance.new("Folder")
folder.Name = "Lineup"
folder.Parent = Sim.workspace()

local labels = {}
local x = 0
local GAP = 2
for _, entry in wanted do
	local rarity = catalog.rarities[entry.def.rarity]
	local model = CreatureVisuals.build(entry.def, rarity, { anchored = true, mutation = entry.mutation })
	model.Parent = folder
	local _, size = model:GetBoundingBox()
	local width = math.max(size.X, size.Z)
	local cx = x + width / 2
	-- The pivot sits at the feet, facing the way a podium faces it.
	model:PivotTo(roblox.CFrame.new(cx, 0, 0))
	local name = if entry.mutation then `{entry.def.id}:{entry.mutation.id}` else entry.def.id
	table.insert(labels, { name = name, x = cx, width = width, height = size.Y })
	x += width + GAP
end

-- A plain sunny afternoon (the map isn't built, so Lighting has no values of its own yet).
local Lighting = Sim.service("Lighting")
Lighting.ClockTime = 14
Lighting.GeographicLatitude = 30
Lighting.Brightness = 2.5
Lighting.Ambient = roblox.Color3.fromRGB(110, 110, 120)
Lighting.OutdoorAmbient = roblox.Color3.fromRGB(150, 150, 160)
Lighting.ColorShift_Top = roblox.Color3.new(0, 0, 0)
Lighting.ExposureCompensation = 0

local data = Sim.exportWorld(folder)
data.terrain = nil
data.labels = labels
fs.writeFile(out, serde.encode("json", data))
print(`wrote {out}: {#labels} Snacklings, {#data.parts} parts`)
