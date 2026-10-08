--!strict
--[[
	The creature/rarity catalogue, built once from config and shared by server and client.
	Validation problems are reported loudly at startup (CI also runs the same validation in tests).
]]

local Catalog = require("./Logic/Catalog")
local Creatures = require("./Config/Creatures")
local Rarities = require("./Config/Rarities")

local problems = Catalog.validate(Creatures, Rarities)
for _, problem in problems do
	warn(`[GameData] config problem: {problem}`)
end

local GameData = {
	catalog = Catalog.build(Creatures, Rarities),
}

return GameData
