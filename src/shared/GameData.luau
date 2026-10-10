--!strict
--[[
	The creature/rarity/mutation catalogue, built once from config and shared by server and client.
	Validation problems are reported loudly at startup (CI also runs the same validation in tests).

	The price / income / name helpers take a creature plus its mutation id (`variant`, nil for a plain one) and are
	what every belt item and owned creature uses, so a mutation applies everywhere (Logic/MutationRules).
]]

local Catalog = require("./Logic/Catalog")
local MutationRules = require("./Logic/MutationRules")
local Creatures = require("./Config/Creatures")
local Mutations = require("./Config/Mutations")
local Rarities = require("./Config/Rarities")
local Theme = require("./Config/Theme")
local Types = require("./Types")

local problems = Catalog.validate(Creatures, Rarities)
for _, problem in Catalog.validateMutations(Mutations) do
	table.insert(problems, problem)
end
for _, problem in problems do
	warn(`[GameData] config problem: {problem}`)
end

local catalog = Catalog.build(Creatures, Rarities, Mutations)

local GameData = {
	catalog = catalog,
}

-- The mutation a variant refers to, or nil (plain creature, or an id no longer in the config: treated as plain).
function GameData.mutation(variant: string?): Types.MutationDef?
	return MutationRules.find(catalog.mutations, variant)
end

-- Belt price (whole number) of this creature with this variant.
function GameData.price(def: Types.CreatureDef, variant: string?): number
	return MutationRules.price(catalog.mutations, def, variant)
end

-- Base income per second (before rebirth / pass / event multipliers) of this creature with this variant.
function GameData.income(def: Types.CreatureDef, variant: string?): number
	return MutationRules.income(catalog.mutations, def, variant)
end

-- "Golden Pizza Pup" (Theme.text.mutatedName), or the plain name.
function GameData.displayName(def: Types.CreatureDef, variant: string?): string
	return MutationRules.displayName(catalog.mutations, def, variant, Theme.text.mutatedName)
end

return GameData
