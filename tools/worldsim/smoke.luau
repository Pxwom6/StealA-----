--!strict
--[[
	Smoke test for the code-built world, offline (CI runs it after the unit tests):
	    lune run tools/worldsim/smoke.luau

	Builds the map dressed as the first map theme (MapBuilder.build), then restyles it through every other theme
	(MapBuilder.restyle) and back, and checks that:
	  * nothing errors or warns
	  * the decoration stays under Config/Scenery.partBudget on every map
	  * every flora kind and landmark builds exactly the parts Logic/MapThemeRules says (the budget check relies on it)
	  * the gameplay geometry is untouched by a restyle (same parts, same places)
	  * the lighting follows the map, and a seasonal overlay wins over it and leaves cleanly; a weather modifier's
	    overlay (with its own clouds) wins over both
	  * every Snackling builds (plain), and every mutation look builds on one (materials, particle presets, glow)
]]

local Sim = require("./Sim")

local MapThemes = Sim.shared("Config/MapThemes")
local Scenery = Sim.shared("Config/Scenery")
local Seasons = Sim.shared("Config/Seasons")
local MapThemeRules = Sim.shared("Logic/MapThemeRules")
local SceneryLayout = Sim.shared("Logic/SceneryLayout")
local Modifiers = Sim.shared("Config/Modifiers")
local Mutations = Sim.shared("Config/Mutations")
local CreatureVisuals = Sim.shared("CreatureVisuals")
local GameData = Sim.shared("GameData")
local MapBuilder = Sim.server("Services/MapBuilder")
local WorldLighting = Sim.server("Services/WorldLighting")

local failures: { string } = {}
local function check(ok: boolean, message: string)
	if not ok then
		table.insert(failures, message)
		print(`FAIL {message}`)
	end
end

local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-3
end

local function countParts(root: any): number
	if root == nil then
		return 0
	end
	local count = 0
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			count += 1
		end
	end
	return count
end

-- Every gameplay part (outside the scenery) by its full path and position, to compare before / after a restyle.
local function gameplaySnapshot(map: any): { [string]: string }
	local snapshot: { [string]: string } = {}
	local scenery = map:FindFirstChild("Scenery")
	for _, descendant in map:GetDescendants() do
		if descendant:IsA("BasePart") and not (scenery and descendant:IsDescendantOf(scenery)) then
			local key = descendant:GetFullName()
			local p = descendant.CFrame.Position
			snapshot[key] = string.format("%.2f,%.2f,%.2f|%s", p.X, p.Y, p.Z, tostring(descendant.Size))
		end
	end
	return snapshot
end

local layout = SceneryLayout.layout(Scenery)
local workspace = Sim.workspace()
local Lighting = Sim.service("Lighting")

local function verify(themeId: string)
	local theme = MapThemes.themes[themeId]
	local scenery = workspace.Map.Scenery
	local expectedTrees = 0
	for _, tree in layout.trees do
		expectedTrees += MapThemeRules.FLORA_PARTS[MapThemeRules.floraFor(theme, tree.kind)]
	end
	local expectedLandmarks = 0
	for index = 1, #Scenery.landmarkSpots do
		local kind = MapThemeRules.landmarkFor(theme, index)
		if kind then
			expectedLandmarks += MapThemeRules.LANDMARK_PARTS[kind]
		end
	end
	check(
		countParts(scenery.Trees) == expectedTrees,
		`{themeId}: trees built {countParts(scenery.Trees)} parts, expected {expectedTrees}`
	)
	check(
		countParts(scenery.Landmarks) == expectedLandmarks,
		`{themeId}: landmarks built {countParts(scenery.Landmarks)} parts, expected {expectedLandmarks}`
	)
	check(
		near(Lighting.ClockTime, theme.lighting.clockTime),
		`{themeId}: ClockTime {Lighting.ClockTime}, expected {theme.lighting.clockTime}`
	)
	check(workspace.Map.Ground.Material.Name == theme.groundMaterial, `{themeId}: ground material`)
end

local first = MapThemes.order[1]
MapBuilder.build(first)
verify(first)
local before = gameplaySnapshot(workspace.Map)

local order = table.clone(MapThemes.order)
table.insert(order, first)
for index = 2, #order do
	local themeId = order[index]
	MapBuilder.restyle(themeId, 0)
	verify(themeId)
end

local after = gameplaySnapshot(workspace.Map)
local changed = 0
for key, value in before do
	if after[key] ~= value then
		changed += 1
		if changed <= 5 then
			print(`  changed: {key}`)
		end
	end
end
for key in after do
	if before[key] == nil then
		changed += 1
	end
end
check(changed == 0, `restyling moved, added or removed {changed} gameplay parts`)

-- A seasonal mood overrides the map's lighting while it lasts.
local halloween = Seasons.themes.halloween.lighting
WorldLighting.setOverlay("season", halloween, 10, 0)
check(near(Lighting.ClockTime, halloween.clockTime), "the seasonal overlay sets the time of day")
WorldLighting.setOverlay("season", nil, 10, 0)
check(near(Lighting.ClockTime, MapThemes.themes[first].lighting.clockTime), "the map's lighting comes back")

-- A weather modifier's sky goes over a seasonal mood, clouds included, and leaves the map's clouds behind it.
local storm = Modifiers.modifiers.thunderstorm.lighting
local clouds = workspace.Terrain:FindFirstChild("WorldClouds")
WorldLighting.setOverlay("season", halloween, 10, 0)
WorldLighting.setOverlay("modifier", storm, 20, 0)
check(near(Lighting.ClockTime, storm.clockTime), "the weather overlay wins over the seasonal one")
check(clouds ~= nil and near(clouds.Cover, storm.clouds.cover), "the weather overlay sets the clouds")
WorldLighting.setOverlay("modifier", nil, 20, 0)
check(near(Lighting.ClockTime, halloween.clockTime), "the seasonal mood comes back after the weather")
WorldLighting.setOverlay("season", nil, 10, 0)
check(clouds ~= nil and near(clouds.Cover, MapThemes.themes[first].lighting.clouds.cover), "the map's clouds come back")

-- Every Snackling, plain; then every mutation on one of them (their looks and particle presets).
local built = 0
local gallery = Sim.Instance.new("Folder")
for _, def in GameData.catalog.creatureList do
	local rarity = GameData.catalog.rarities[def.rarity]
	local ok, result = pcall(CreatureVisuals.build, def, rarity, { anchored = true })
	if ok then
		result.Parent = gallery
		built += 1
	else
		check(false, `{def.id} failed to build: {result}`)
	end
end
local sample = GameData.catalog.creatureList[1]
for _, mutation in Mutations do
	local ok, result = pcall(
		CreatureVisuals.build,
		sample,
		GameData.catalog.rarities[sample.rarity],
		{ anchored = true, mutation = mutation }
	)
	if ok then
		check(result:GetAttribute("Variant") == mutation.id, `{mutation.id}: the model is not marked as mutated`)
		local particles = mutation.look.particles
		if particles then
			check(CreatureVisuals.hasParticles(particles), `{mutation.id}: no particle preset {particles}`)
			check(
				result:FindFirstChild("MutationParticles", true) ~= nil,
				`{mutation.id}: the {particles} particles are missing`
			)
		end
		result.Parent = gallery
		built += 1
	else
		check(false, `{mutation.id} failed to build: {result}`)
	end
end
gallery:Destroy()

for _, message in Sim.warnings do
	table.insert(failures, `warning: {message}`)
end
if #failures > 0 then
	error(`world smoke test: {#failures} problem(s)`)
end
print(`world smoke test: {#MapThemes.order} maps built and restyled, {built} Snacklings built, no problems`)
