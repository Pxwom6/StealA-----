--!strict
-- Snackling models (the polished models in Config/CreatureParts and the recipes in Config/CreatureLooks, both built
-- by Logic/CreatureRecipe) and the roster's tier bands.
local T = require("./TestKit")
local Catalog = require("../src/shared/Logic/Catalog")
local CreatureRecipe = require("../src/shared/Logic/CreatureRecipe")
local CreatureLooks = require("../src/shared/Config/CreatureLooks")
local CreatureParts = require("../src/shared/Config/CreatureParts")
local Creatures = require("../src/shared/Config/Creatures")
local Rarities = require("../src/shared/Config/Rarities")
local Types = require("../src/shared/Types")

type Band = { price: { number }, income: { number }, payback: { number } }

-- Each tier's price, income and payback (seconds) band, as in BALANCE.md "Rarity tiers". Every Snackling, event ones
-- included, sits inside its tier's band, so a bigger roster never changes the shape of the chase.
local TIER_BANDS: { [string]: Band } = {
	Common = { price = { 25, 200 }, income = { 1, 6 }, payback = { 25, 34 } },
	Uncommon = { price = { 500, 1500 }, income = { 12, 30 }, payback = { 41, 50 } },
	Rare = { price = { 4500, 12500 }, income = { 65, 160 }, payback = { 69, 79 } },
	Epic = { price = { 60000, 150000 }, income = { 400, 950 }, payback = { 150, 158 } },
	Legendary = { price = { 1400000, 3400000 }, income = { 2800, 6500 }, payback = { 500, 524 } },
	Mythic = { price = { 50000000, 85000000 }, income = { 35000, 56000 }, payback = { 1428, 1518 } },
	Secret = { price = { 1800000000, 3200000000 }, income = { 360000, 620000 }, payback = { 5000, 5162 } },
}

-- Models must fit the bases: side to side between neighbouring podiums, and under the podium billboard.
local MAX_WIDTH = CreatureRecipe.PODIUM_FIT.width
local MAX_HEIGHT = CreatureRecipe.PODIUM_FIT.height

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

-- Every model the game can build at `scale(rarity)`: each polished model and each recipe (the recipes are the
-- fallback, so they must stay buildable too).
type Build = { label: string, creature: Types.CreatureDef, compiled: CreatureRecipe.Compiled }
local function allBuilds(scale: (Types.RarityDef) -> number): { Build }
	local list: { Build } = {}
	for _, creature in Creatures do
		local rarity = rarityById[creature.rarity]
		local imported = CreatureParts[creature.id]
		if imported then
			local compiled = CreatureRecipe.compileImported(imported, scale(rarity))
			table.insert(list, { label = creature.id, creature = creature, compiled = compiled })
		end
		local look = CreatureLooks[creature.id]
		if look then
			local compiled = CreatureRecipe.compile(look, scale(rarity))
			table.insert(list, { label = `{creature.id} (recipe)`, creature = creature, compiled = compiled })
		end
	end
	return list
end
local function unitScale(_: Types.RarityDef): number
	return 1
end
local function rarityScale(rarity: Types.RarityDef): number
	return rarity.modelScale
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

	T.it("stays inside its rarity's part budget (40 / 50 / 60, Root and aura included)", function()
		T.expect(CreatureRecipe.budgetFor(1)).toBe(40)
		T.expect(CreatureRecipe.budgetFor(2)).toBe(40)
		T.expect(CreatureRecipe.budgetFor(3)).toBe(50)
		T.expect(CreatureRecipe.budgetFor(4)).toBe(50)
		for order = 5, 7 do
			T.expect(CreatureRecipe.budgetFor(order)).toBe(60)
		end
		for _, creature in Creatures do
			local order = rarityById[creature.rarity].order
			local budget = CreatureRecipe.budgetFor(order)
			local counts: { [string]: number } =
				{ recipe = CreatureRecipe.partCount(CreatureLooks[creature.id], order) }
			local imported = CreatureParts[creature.id]
			if imported then
				counts.model = CreatureRecipe.importedPartCount(imported, order)
			end
			for kind, count in counts do
				if count > budget then
					error(`{creature.id}'s {kind} has {count} parts, over its {creature.rarity} budget of {budget}`)
				end
			end
		end
	end)

	T.it("builds only well-formed parts", function()
		for _, build in allBuilds(unitScale) do
			local id, compiled = build.label, build.compiled
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
		for _, build in allBuilds(unitScale) do
			local id, compiled = build.label, build.compiled
			if compiled.minY < -1e-6 or compiled.minY > 0.05 then
				error(`{id}: lowest point is at y = {compiled.minY}`)
			end
		end
	end)

	T.it("has a face on its front that mutations never restyle", function()
		for _, build in allBuilds(unitScale) do
			local id, compiled = build.label, build.compiled
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
		for _, build in allBuilds(rarityScale) do
			local compiled = build.compiled
			if compiled.width > MAX_WIDTH then
				error(`{build.label} is {compiled.width} studs wide (max {MAX_WIDTH})`)
			end
			if compiled.maxY > MAX_HEIGHT then
				error(`{build.label} is {compiled.maxY} studs tall (max {MAX_HEIGHT})`)
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

T.describe("Polished Snackling models (Config/CreatureParts)", function()
	local function model(parts: { { any } }): Types.ImportedModel
		return { scale = 2, parts = parts }
	end
	local EYES: { { any } } = {
		{ "Eye", "sphere", { 0.2, 0.2, 0.1 }, { -0.2, 1, -0.5 }, { 0, 0, 0 }, "#FFFFFF", "SmoothPlastic", "face" },
		{ "Eye", "sphere", { 0.2, 0.2, 0.1 }, { 0.2, 1, -0.5 }, { 0, 0, 0 }, "#FFFFFF", "SmoothPlastic", "face" },
	}
	local function withEyes(parts: { { any } }): { { any } }
		local list = table.clone(parts)
		for _, eye in EYES do
			table.insert(list, eye)
		end
		return list
	end

	T.it("belongs to a Snackling and passes the import rules within its rarity's budget", function()
		for id, imported in CreatureParts do
			local creature: Types.CreatureDef? = nil
			for _, def in Creatures do
				if def.id == id then
					creature = def
				end
			end
			if creature == nil then
				error(`polished model {id} has no Snackling in Config/Creatures`)
			end
			local order = rarityById[(creature :: Types.CreatureDef).rarity].order
			local allowance = CreatureRecipe.budgetFor(order) - 1 - (if order >= 6 then 1 else 0)
			local problems = CreatureRecipe.validateImported(imported, allowance)
			if #problems > 0 then
				error(`{id}: {table.concat(problems, "; ")}`)
			end
		end
	end)

	T.it("turns design shapes into Roblox parts: cylinders run along X, everything else keeps its frame", function()
		local compiled = CreatureRecipe.compileImported(
			model(withEyes({
				{ "Body", "cylinder", { 0.4, 1, 0.4 }, { 0, 0.5, 0 }, { 0, 0, 0 }, "#FF0000", "SmoothPlastic", "body" },
				{ "Hat", "wedge", { 0.5, 0.3, 0.6 }, { 0, 1.15, 0 }, { 0, 90, 0 }, "#00FF00", "Neon", "detail", 0.2 },
				{ "Paw", "box", { 0.2, 0.1, 0.3 }, { 0.3, 0.05, 0 }, { 0, 0, 0 }, "#0000FF", "Wood", "body" },
			})),
			1
		)
		local body, hat, paw = compiled.parts[1], compiled.parts[2], compiled.parts[3]
		-- a 1-unit-tall cylinder at scale 2: 2 studs long along its local X, which points up
		T.expect(body.shape).toBe("Cylinder")
		T.expect(body.size).toEqual({ 2, 0.8, 0.8 })
		T.expect(body.cf[4]).toBeNear(0, 1e-9) -- R00: local X has no world-x part...
		T.expect(body.cf[7]).toBeNear(1, 1e-9) -- R10: ...and points straight up
		T.expect(body.cf[2]).toBeNear(1, 1e-9) -- centre 0.5 u up = 1 stud
		T.expect(body.material).toBeNil() -- SmoothPlastic is the default
		-- a wedge keeps its own frame; ry(90) turns its local Z (the back face) to world -X
		T.expect(hat.shape).toBe("Wedge")
		T.expect(hat.size).toEqual({ 1, 0.6, 1.2 })
		T.expect(hat.cf[6]).toBeNear(1, 1e-9) -- R02 = sin(90)
		T.expect(hat.cf[12]).toBeNear(0, 1e-9) -- R22 = cos(90)
		T.expect(hat.material).toBe("Neon")
		T.expect(hat.transparency).toBe(0.2)
		T.expect(paw.shape).toBe("Block")
		T.expect(paw.material).toBe("Wood")
		T.expect(compiled.parts[4].shape).toBe("Ellipsoid")
	end)

	T.it("applies rotations in three.js XYZ order (rx * ry * rz, like CFrame.Angles)", function()
		local compiled = CreatureRecipe.compileImported(
			model(withEyes({
				{ "Body", "box", { 1, 0.2, 0.4 }, { 0, 0.6, 0 }, { 90, 90, 0 }, "#FFFFFF", "SmoothPlastic", "body" },
			})),
			1
		)
		local cf = compiled.parts[1].cf
		-- rx(90) * ry(90) = { 0, 0, 1; 1, 0, 0; 0, 1, 0 }
		local expected = { 0, 0, 1, 1, 0, 0, 0, 1, 0 }
		for i = 1, 9 do
			T.expect(cf[3 + i]).toBeNear(expected[i], 1e-9)
		end
	end)

	T.it("scales by the model's scale times the rarity's, and stands exactly on y = 0", function()
		local raised = model(withEyes({
			{ "Body", "sphere", { 1, 1, 1 }, { 0, 0.52, 0 }, { 0, 0, 0 }, "#FFFFFF", "SmoothPlastic", "body" },
		}))
		local compiled = CreatureRecipe.compileImported(raised, 1.5)
		T.expect(compiled.parts[1].size).toEqual({ 3, 3, 3 }) -- 1 u x 2 x 1.5
		T.expect(compiled.minY).toBe(0)
		T.expect(compiled.parts[1].cf[2]).toBeNear(1.5, 1e-9) -- lowered by the 0.02 u it floated
		T.expect(compiled.maxY).toBeNear((1.1 - 0.02) * 3, 1e-9) -- the eyes' tops (1.1 u) are the highest point
		-- the big body casts a shadow and breathes with the idle squash, on its upright axis
		T.expect(compiled.parts[1].shadow).toBe(true)
		T.expect(compiled.parts[1].squashAxis).toBe(2)
	end)

	T.it("squashes one body part and lets at most the three biggest cast shadows", function()
		for id, imported in CreatureParts do
			local compiled = CreatureRecipe.compileImported(imported, 1)
			local squashed, shadows = 0, 0
			for _, part in compiled.parts do
				if part.squashAxis then
					squashed += 1
				end
				if part.shadow then
					shadows += 1
				end
			end
			if squashed > 1 or shadows > CreatureRecipe.IMPORT.shadowCasters then
				error(`{id}: {squashed} squashed parts, {shadows} shadow casters`)
			end
		end
	end)

	T.it("reports broken models instead of building them", function()
		local broken = model({
			{ "Body", "cone", { 1, 1, 1 }, { 0, 0.5, 0 }, { 0, 0, 0 }, "#FFFFFF", "SmoothPlastic", "body" },
			{ "Leg", "cylinder", { 0.4, 1, 0.2 }, { 0, 0.5, 0 }, { 0, 0, 0 }, "#FFFFFF", "Plastic", "body" },
			{ "Eye", "sphere", { 0.2, 0.2, 0.2 }, { 0, 1, -0.5 }, { 0, 0, 0 }, "red", "SmoothPlastic", "detail" },
			{ "Fin", "box", { 0.5, 0.5, 0.5 }, { 1.2, 0.25, 0 }, { 0, 0, 0 }, "#FFFFFF", "SmoothPlastic", "fin" },
			{ "Toe", "box", { 0.01, 0.5, 0.5 }, { 0, -0.2, 0 }, { 0, 0, 0 }, "#FFFFFF", "SmoothPlastic", "body", 0.9 },
		})
		local problems = CreatureRecipe.validateImported(broken, 4)
		local text = table.concat(problems, "\n")
		for _, expected in
			{
				"5 parts",
				"unknown shape cone",
				"cylinder must be circular",
				"unknown material Plastic",
				"colour must be",
				"face role",
				"unknown role fin",
				"smaller than",
				"transparency",
				"two eyes",
			}
		do
			if string.find(text, expected, 1, true) == nil then
				error(`expected a problem mentioning "{expected}", got:\n{text}`)
			end
		end
		local floating = model(withEyes({
			{ "Body", "sphere", { 1, 1, 1 }, { 0, 0.8, 0 }, { 0, 0, 0 }, "#FFFFFF", "SmoothPlastic", "body" },
		}))
		local floatingText = table.concat(CreatureRecipe.validateImported(floating, 10), " ")
		T.expect(string.find(floatingText, "stand on y = 0", 1, true) ~= nil).toBe(true)
		local noBody = model(withEyes({
			{ "Torso", "sphere", { 1, 1, 1 }, { 0, 0.5, 0 }, { 0, 0, 0 }, "#FFFFFF", "SmoothPlastic", "body" },
		}))
		local noBodyText = table.concat(CreatureRecipe.validateImported(noBody, 10), " ")
		T.expect(string.find(noBodyText, "exactly one part called Body", 1, true) ~= nil).toBe(true)
	end)
end)

T.describe("Snackling roster", function()
	local catalog = Catalog.build(Creatures, Rarities)

	T.it("has about 60 permanent Snacklings spread over every tier", function()
		local total = 0
		for _, rarity in catalog.rarityList do
			local regular = 0
			for _, creature in catalog.byRarity[rarity.id] do
				if creature.eventId == nil then
					regular += 1
				end
			end
			T.expect(regular).toBeAtLeast(6)
			total += regular
		end
		T.expect(total).toBeAtLeast(60)
	end)

	T.it("never repeats an id, a name or a model name", function()
		local ids, names, models = {}, {}, {}
		for _, creature in Creatures do
			T.expect(ids[creature.id]).toBeNil()
			T.expect(names[creature.displayName]).toBeNil()
			T.expect(models[creature.modelName]).toBeNil()
			ids[creature.id], names[creature.displayName], models[creature.modelName] = true, true, true
			T.expect(#creature.flavor).toBeGreaterThan(0)
		end
	end)

	T.it("prices, incomes and paybacks stay inside their tier's band", function()
		for _, creature in Creatures do
			local band = TIER_BANDS[creature.rarity]
			local payback = creature.price / creature.income
			local function inside(label: string, value: number, range: { number })
				if value < range[1] or value > range[2] then
					error(`{creature.id}: {label} {value} is outside {creature.rarity}'s {range[1]}..{range[2]}`)
				end
			end
			inside("price", creature.price, band.price)
			inside("income", creature.income, band.income)
			inside("payback", payback, band.payback)
		end
	end)

	T.it("pricier Snacklings pay back a little slower within a tier", function()
		for _, rarity in catalog.rarityList do
			local regular: { Types.CreatureDef } = {}
			for _, creature in catalog.byRarity[rarity.id] do
				if creature.eventId == nil then
					table.insert(regular, creature)
				end
			end
			table.sort(regular, function(a: Types.CreatureDef, b: Types.CreatureDef): boolean
				return a.price < b.price
			end)
			local cheapest, dearest = regular[1], regular[#regular]
			T.expect(dearest.price / dearest.income).toBeGreaterThan(cheapest.price / cheapest.income)
		end
	end)

	T.it("each tier's regular belt weights add up to 100, so an event Snackling's share is easy to read", function()
		for _, rarity in catalog.rarityList do
			local sum = 0
			for _, creature in catalog.byRarity[rarity.id] do
				if creature.eventId == nil then
					sum += creature.beltWeight
				end
			end
			T.expect(sum).toBe(100)
		end
	end)
end)

return nil
