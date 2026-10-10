--!strict
-- Snackling models (Config/CreatureLooks built by Logic/CreatureRecipe) and the roster's tier bands.
local T = require("./TestKit")
local Catalog = require("../src/shared/Logic/Catalog")
local CreatureRecipe = require("../src/shared/Logic/CreatureRecipe")
local CreatureLooks = require("../src/shared/Config/CreatureLooks")
local Creatures = require("../src/shared/Config/Creatures")
local Rarities = require("../src/shared/Config/Rarities")
local Types = require("../src/shared/Types")

-- Models must fit the bases (Config/Gameplay.map): neighbouring podiums stand podiumRowSpacing = 6.6 studs apart
-- side to side, and the podium billboard floats 8.5 studs above the podium (a model starts 0.7 above that point).
local MAX_WIDTH = 6.6
local MAX_HEIGHT = 7.4

local FACE_NAMES = {
	Eye = true,
	Pupil = true,
	Highlight = true,
	Mouth = true,
	Tongue = true,
	Teeth = true,
	Cheek = true,
	Brow = true,
	Nose = true,
	Patch = true,
}

local rarityById: { [string]: Types.RarityDef } = {}
for _, rarity in Rarities do
	rarityById[rarity.id] = rarity
end

local function isHex(value: string): boolean
	return string.match(value, "^#%x%x%x%x%x%x$") ~= nil
end

local function finite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

T.describe("Snackling model recipes", function()
	T.it("every Snackling has a recipe and every recipe belongs to a Snackling", function()
		local ids: { [string]: boolean } = {}
		for _, creature in Creatures do
			ids[creature.id] = true
			if CreatureLooks[creature.id] == nil then
				error(`{creature.id} has no recipe in Config/CreatureLooks`)
			end
		end
		for id in CreatureLooks do
			if not ids[id] then
				error(`recipe {id} has no Snackling in Config/Creatures`)
			end
		end
	end)

	T.it("every recipe validates (known plan, skins, features, toppings, colours, materials)", function()
		for id, look in CreatureLooks do
			local problems = CreatureRecipe.validate(look, Catalog.MUTATION_MATERIALS)
			if #problems > 0 then
				error(`{id}: {table.concat(problems, "; ")}`)
			end
		end
	end)

	T.it("stays inside its rarity's part budget (30 / 40 / 50, Root and aura included)", function()
		T.expect(CreatureRecipe.budgetFor(1)).toBe(30)
		T.expect(CreatureRecipe.budgetFor(2)).toBe(30)
		T.expect(CreatureRecipe.budgetFor(3)).toBe(40)
		T.expect(CreatureRecipe.budgetFor(4)).toBe(40)
		for order = 5, 7 do
			T.expect(CreatureRecipe.budgetFor(order)).toBe(50)
		end
		for _, creature in Creatures do
			local order = rarityById[creature.rarity].order
			local count = CreatureRecipe.partCount(CreatureLooks[creature.id], order)
			local budget = CreatureRecipe.budgetFor(order)
			if count > budget then
				error(`{creature.id} has {count} parts, over its {creature.rarity} budget of {budget}`)
			end
		end
	end)

	T.it("builds only well-formed parts", function()
		for id, look in CreatureLooks do
			local compiled = CreatureRecipe.compile(look, 1)
			T.expect(#compiled.parts).toBeGreaterThan(5)
			local bodies = 0
			for _, part in compiled.parts do
				if part.name == "Body" then
					bodies += 1
				end
				for _, v in part.size do
					if not (finite(v) and v > 0 and v < 20) then
						error(`{id}: part {part.name} has a bad size`)
					end
				end
				for _, v in part.cf do
					if not finite(v) then
						error(`{id}: part {part.name} has a bad CFrame`)
					end
				end
				-- the rotation is a proper rotation (orthonormal, determinant 1)
				local r = part.cf
				local det = r[4] * (r[8] * r[12] - r[9] * r[11])
					- r[5] * (r[7] * r[12] - r[9] * r[10])
					+ r[6] * (r[7] * r[11] - r[8] * r[10])
				T.expect(det).toBeNear(1, 1e-6)
				T.expect(r[4] * r[4] + r[7] * r[7] + r[10] * r[10]).toBeNear(1, 1e-6)
				T.expect(isHex(part.color)).toBe(true)
				if part.squashAxis then
					T.expect(part.shape == "Ellipsoid" or part.shape == "Block").toBe(true)
				end
			end
			-- the rarity flair (glow, particles) attaches to the one part called Body
			if bodies ~= 1 then
				error(`{id} has {bodies} parts called Body (needs exactly 1)`)
			end
		end
	end)

	T.it("stands on its feet: nothing below y = 0 and something touching the ground", function()
		for id, look in CreatureLooks do
			local compiled = CreatureRecipe.compile(look, 1)
			if compiled.minY < -1e-6 or compiled.minY > 0.05 then
				error(`{id}: lowest point is at y = {compiled.minY}`)
			end
		end
	end)

	T.it("has a face on its front that mutations never restyle", function()
		for id, look in CreatureLooks do
			local compiled = CreatureRecipe.compile(look, 1)
			local eyes, faceZ, faceCount, allZ = 0, 0, 0, 0
			for _, part in compiled.parts do
				allZ += part.cf[3]
				if FACE_NAMES[part.name] and part.role ~= "face" then
					error(`{id}: {part.name} must have the face role (mutations skip it)`)
				end
				if part.name == "Eye" or part.name == "Pupil" then
					eyes += 1
					faceZ += part.cf[3]
					faceCount += 1
				end
			end
			if eyes < 2 then
				error(`{id} needs two eyes`)
			end
			-- faces look at -Z: the eyes sit in front of the middle of the model
			T.expect(faceZ / faceCount).toBeLessThan(allZ / #compiled.parts)
		end
	end)

	T.it("fits a podium at its rarity's scale (width between neighbours, height under the billboard)", function()
		for _, creature in Creatures do
			local compiled = CreatureRecipe.compile(CreatureLooks[creature.id], rarityById[creature.rarity].modelScale)
			if compiled.width > MAX_WIDTH then
				error(`{creature.id} is {compiled.width} studs wide (max {MAX_WIDTH})`)
			end
			if compiled.maxY > MAX_HEIGHT then
				error(`{creature.id} is {compiled.maxY} studs tall (max {MAX_HEIGHT})`)
			end
		end
	end)

	T.it("scales with the rarity's modelScale and builds the same every time", function()
		local look = CreatureLooks.donut_dragon
		local one = CreatureRecipe.compile(look, 1)
		local two = CreatureRecipe.compile(look, 2)
		T.expect(#two.parts).toBe(#one.parts)
		for i, part in one.parts do
			-- (parts at the minimum part size don't shrink further, so they can't scale exactly)
			if math.min(part.size[1], part.size[2], part.size[3]) > 0.06 then
				for k = 1, 3 do
					T.expect(two.parts[i].size[k]).toBeNear(part.size[k] * 2, 1e-6)
					T.expect(two.parts[i].cf[k]).toBeNear(part.cf[k] * 2, 1e-6)
				end
			end
		end
		T.expect(two.maxY).toBeNear(one.maxY * 2, 1e-6)
		T.expect(CreatureRecipe.compile(look, 1)).toEqual(one)
	end)

	T.it("reports broken recipes instead of building them silently", function()
		local broken: Types.CreatureLook = {
			size = 2,
			plan = "biped",
			body = { skin = "round", color = "red" },
			head = { skin = "round", color = "#FFFFFF" },
			face = { eyes = "round", mouth = "smile", cheeks = "#12345" },
			features = { { kind = "ears", color = "#ZZZZZZ" } },
			toppings = { { kind = "sprinkles", colors = {}, material = "Unobtanium" } },
		}
		local problems = CreatureRecipe.validate(broken, Catalog.MUTATION_MATERIALS)
		T.expect(#problems).toBeAtLeast(5)
		local blob: Types.CreatureLook = {
			size = 2,
			plan = "blob",
			body = { skin = "round", color = "#FFFFFF" },
			head = { skin = "round", color = "#FFFFFF" },
			face = {},
			features = {},
			toppings = {},
		}
		T.expect(#CreatureRecipe.validate(blob, Catalog.MUTATION_MATERIALS)).toBe(1) -- a blob has no separate head
	end)

	T.it("knows every kind the shared types list", function()
		local kinds = CreatureRecipe.kinds()
		T.expect(kinds.plans).toEqual({ "biped", "blob", "quadruped", "swimmer", "tentacled" })
		T.expect(#kinds.skins).toBe(15)
		T.expect(#kinds.features).toBe(30)
		T.expect(#kinds.toppings).toBe(20)
	end)
end)

return nil
