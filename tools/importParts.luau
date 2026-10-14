--!strict
--[[
	Imports the polished Snackling models designed in Claude Design: `lune run tools/importParts.luau`

	Reads art/snackling-parts/batch-*.json (format "snackling-parts-1", made from the prompts next to them), checks
	every model (Logic/CreatureRecipe.validateImported and its rarity's part budget), sizes it, and writes
	src/shared/Config/CreatureParts.luau. Re-run after replacing or editing a batch file (DECISIONS.md #28).

	  * Names: the rarity glow and sparkles attach to the one part called Body (CreatureVisuals), so the biggest body
	    part is named Body and any other "Body" is renumbered.
	  * Size: every Snackling of a rarity gets about the same presence, the typical height of that rarity's recipe
	    models (so tiers keep growing as before). A tall model is that tall; a long, low one (a dachshund, a gecko)
	    is that long divided by LONG_FACTOR, so it doesn't shrink to nothing. Then it is shrunk if needed to fit a
	    podium at its rarity's scale (CreatureRecipe.PODIUM_FIT).
]]

local fs = require("@lune/fs")
local serde = require("@lune/serde")

local CreatureLooks = require("../src/shared/Config/CreatureLooks")
local Creatures = require("../src/shared/Config/Creatures")
local Rarities = require("../src/shared/Config/Rarities")
local CreatureRecipe = require("../src/shared/Logic/CreatureRecipe")
local Types = require("../src/shared/Types")

local SOURCE_DIR = "art/snackling-parts"
local OUTPUT = "src/shared/Config/CreatureParts.luau"
local FIT_MARGIN = 0.98
local LONG_FACTOR = 0.75 -- a long model's length counts this much towards its presence
local SHAPE_VOLUME: { [string]: number } = { sphere = math.pi / 6, box = 1, cylinder = math.pi / 4, wedge = 0.5 }

local rarityById: { [string]: Types.RarityDef } = {}
for _, rarity in Rarities do
	rarityById[rarity.id] = rarity
end
local defById: { [string]: Types.CreatureDef } = {}
for _, def in Creatures do
	defById[def.id] = def
end

local function volume(raw: { any }): number
	local size: { number } = raw[3]
	return size[1] * size[2] * size[3] * (SHAPE_VOLUME[raw[2]] or 1)
end

-- Exactly one part called Body: the biggest body part.
local function nameBody(parts: { { any } })
	local biggest, best = nil :: { any }?, -1
	for _, raw in parts do
		if raw[8] == "body" and volume(raw) > best then
			biggest, best = raw, volume(raw)
		end
	end
	local extra = 1
	for _, raw in parts do
		if raw == biggest then
			raw[1] = "Body"
		elseif raw[1] == "Body" then
			extra += 1
			raw[1] = `Body{extra}`
		end
	end
end

-- How big a model reads on a podium: its height, or most of its length if it is long and low.
local function presence(compiled: CreatureRecipe.Compiled): number
	return math.max(compiled.maxY - compiled.minY, compiled.footprint * LONG_FACTOR)
end

-- The typical height of each rarity's tall recipe models at scale 1 (the upper quartile: a tier's few long, low
-- Snacklings mustn't pull it down).
local tierHeight: { [string]: number } = {}
do
	local heights: { [string]: { number } } = {}
	for _, def in Creatures do
		local list = heights[def.rarity] or {}
		heights[def.rarity] = list
		local compiled = CreatureRecipe.compile(CreatureLooks[def.id], 1)
		table.insert(list, compiled.maxY - compiled.minY)
	end
	for rarity, list in heights do
		table.sort(list)
		tierHeight[rarity] = list[math.ceil(#list * 0.75)]
	end
end

local function number(n: number): string
	if n == math.floor(n) then
		return string.format("%d", n)
	end
	local text = string.format("%.3f", n):gsub("0+$", ""):gsub("%.$", "")
	return if text == "-0" then "0" else text
end

local function vector(values: { number }): string
	return `\{ {number(values[1])}, {number(values[2])}, {number(values[3])} \}`
end

local function word(value: string): string
	assert(string.match(value, "^[#%w_]+$"), `unexpected text {value}`)
	return `"{value}"`
end

-- Read every batch.
local models: { [string]: Types.ImportedModel } = {}
local sources: { [string]: string } = {}
for _, entry in fs.readDir(SOURCE_DIR) do
	local path = `{SOURCE_DIR}/{entry}`
	if string.match(entry, "^batch%-%d+%.json$") then
		local data = serde.decode("json", fs.readFile(path))
		assert(data.format == "snackling-parts-1", `{path}: unknown format {data.format}`)
		for _, creature in data.creatures do
			assert(defById[creature.id], `{path}: {creature.id} is not a Snackling`)
			assert(models[creature.id] == nil, `{creature.id} appears twice ({sources[creature.id]} and {path})`)
			models[creature.id] = { scale = 1, parts = creature.parts }
			sources[creature.id] = entry
		end
	end
end

-- Check, name and size every model, in catalogue order.
local problems: { string } = {}
local lines: { string } = {}
local imported = 0
print(
	string.format(
		"%-24s %-9s %5s %6s %6s %6s %6s %6s  %s",
		"id",
		"rarity",
		"parts",
		"oldH",
		"newH",
		"oldW",
		"newW",
		"scale",
		"note"
	)
)
for _, def in Creatures do
	local model = models[def.id]
	if model == nil then
		continue
	end
	local rarity = rarityById[def.rarity]
	nameBody(model.parts)
	local allowance = CreatureRecipe.budgetFor(rarity.order) - 1 - (if rarity.order >= 6 then 1 else 0)
	local found = CreatureRecipe.validateImported(model, allowance)
	for _, message in found do
		table.insert(problems, `{def.id}: {message}`)
	end
	if #found > 0 then
		continue
	end

	local old = CreatureRecipe.compile(CreatureLooks[def.id], 1)
	local unit = CreatureRecipe.compileImported(model, 1)
	local scale = tierHeight[def.rarity] / presence(unit)
	local fit = CreatureRecipe.PODIUM_FIT
	local limit = math.min(
		fit.width * FIT_MARGIN / (unit.width * rarity.modelScale),
		fit.height * FIT_MARGIN / (unit.maxY * rarity.modelScale)
	)
	local note = ""
	if limit < scale then
		scale, note = limit, "shrunk to fit a podium"
	end
	scale = math.floor(scale * 1000) / 1000
	model.scale = scale
	imported += 1
	print(
		string.format(
			"%-24s %-9s %5d %6.2f %6.2f %6.2f %6.2f %6.3f  %s",
			def.id,
			def.rarity,
			#model.parts,
			old.maxY - old.minY,
			unit.maxY * scale,
			old.width,
			unit.footprint * scale,
			scale,
			note
		)
	)

	table.insert(lines, `\t{def.id} = \{`)
	table.insert(lines, `\t\tscale = {number(scale)}, -- from {sources[def.id]}`)
	table.insert(lines, "\t\tparts = {")
	for _, raw in model.parts do
		local fields = {
			word(raw[1]),
			word(raw[2]),
			vector(raw[3]),
			vector(raw[4]),
			vector(raw[5]),
			word(raw[6]),
			word(raw[7]),
			word(raw[8]),
		}
		if raw[9] ~= nil then
			table.insert(fields, number(raw[9]))
		end
		table.insert(lines, `\t\t\t\{ {table.concat(fields, ", ")} \},`)
	end
	table.insert(lines, "\t\t},")
	table.insert(lines, "\t},")
end

if #problems > 0 then
	print(`\n{#problems} problem(s), nothing written:`)
	for _, message in problems do
		print(`  {message}`)
	end
	error("import failed")
end

local header = [[
--!strict
--[=[
	GENERATED by `lune run tools/importParts.luau` from art/snackling-parts/batch-*.json. Don't edit by hand: change
	the batch file and re-run the tool.

	The polished Snackling models designed in Claude Design (DECISIONS.md #28), keyed by creature id. Each replaces
	that creature's recipe in Config/CreatureLooks (the recipe stays as the fallback); Logic/CreatureRecipe
	.compileImported turns one into parts and documents the format. `scale` is studs per design unit at rarity scale
	1, chosen so the model is as big overall as the recipe it replaces and fits a podium.
]=]

local Types = require("../Types")

local CreatureParts: { [string]: Types.ImportedModel } = {
]]
local footer = "}\n\nreturn CreatureParts\n"
fs.writeFile(OUTPUT, header .. table.concat(lines, "\n") .. "\n" .. footer)
print(`\nWrote {OUTPUT}: {imported} models`)
