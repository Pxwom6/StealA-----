--!strict
--[[
	Self-test section Maps: switches through every map theme with MapThemeService.switchTo (what the rotation, the vote,
	`/map` and the host panel call), then back to the map it started on. Each switch is checked by the rules of
	tools/worldsim/smoke.luau, in the real engine: nothing logged an error or a warning meanwhile, every flora kind and
	landmark built the parts Logic/MapThemeRules counts, the decoration stays under Config/Scenery.partBudget, no
	gameplay part moved, appeared or went away, the ground has the map's material and the lighting layers want the
	right time of day. The switches are not announced (no banners).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapThemes = require(ReplicatedStorage.Shared.Config.MapThemes)
local Scenery = require(ReplicatedStorage.Shared.Config.Scenery)
local MapThemeRules = require(ReplicatedStorage.Shared.Logic.MapThemeRules)
local SceneryLayout = require(ReplicatedStorage.Shared.Logic.SceneryLayout)
local MapThemeService = require(script.Parent.Parent.Services.MapThemeService)
local WorldLighting = require(script.Parent.Parent.Services.WorldLighting)
local Kit = require(script.Parent.Kit)

-- The Snacklings on podiums are left out: a purchase or a steal during the test may add or move one.
local function creatureParts(map: Instance): { [Instance]: boolean }
	local skip: { [Instance]: boolean } = {}
	for _, descendant in map:GetDescendants() do
		if descendant:IsA("Model") and descendant:GetAttribute("CreatureId") ~= nil then
			for _, part in descendant:GetDescendants() do
				skip[part] = true
			end
		end
	end
	return skip
end

-- Every gameplay part (outside the scenery) by full name: where it is and how big.
local function gameplaySnapshot(map: Instance): { [string]: string }
	local snapshot: { [string]: string } = {}
	local scenery = map:FindFirstChild("Scenery")
	local skip = creatureParts(map)
	for _, descendant in map:GetDescendants() do
		if
			descendant:IsA("BasePart")
			and not skip[descendant]
			and not (scenery ~= nil and descendant:IsDescendantOf(scenery))
		then
			local p, s = descendant.Position, descendant.Size
			snapshot[descendant:GetFullName()] =
				string.format("%.2f,%.2f,%.2f|%.2f,%.2f,%.2f", p.X, p.Y, p.Z, s.X, s.Y, s.Z)
		end
	end
	return snapshot
end

-- Gameplay parts that differ from `before`: moved or resized, gone, or new.
local function differences(before: { [string]: string }, now: { [string]: string }): { string }
	local list: { string } = {}
	for key, value in before do
		if now[key] == nil then
			table.insert(list, `{key} went away`)
		elseif now[key] ~= value then
			table.insert(list, `{key} moved`)
		end
	end
	for key in now do
		if before[key] == nil then
			table.insert(list, `{key} appeared`)
		end
	end
	table.sort(list)
	return list
end

-- The decoration MapBuilder adds outside the scenery (plot trims, pad rings, belt chevrons, board frames), which its
-- budget counts with the scenery: the parts that never collide, are never touched and are invisible to raycasts,
-- hidden ones too, but for each plot's Dome (the lock's force field, a gameplay part built the same way). It never
-- changes when the map does.
local function decorationOutsideScenery(map: Instance): number
	local scenery = map:FindFirstChild("Scenery")
	local skip = creatureParts(map)
	local count = 0
	for _, descendant in map:GetDescendants() do
		if
			descendant:IsA("BasePart")
			and not skip[descendant]
			and not (scenery ~= nil and descendant:IsDescendantOf(scenery))
			and not descendant.CanCollide
			and not descendant.CanTouch
			and not descendant.CanQuery
			and descendant.Name ~= "Dome"
		then
			count += 1
		end
	end
	return count
end

local Maps: Kit.Section = {
	name = "Maps",
	run = function(ctx: Kit.Context): string
		local map = workspace:FindFirstChild("Map")
		if map == nil then
			ctx.problem("there is no workspace.Map: the server didn't build the world")
			return "no map"
		end
		local start = MapThemeService.current()
		ctx.onCleanup(function()
			if MapThemeService.current() ~= start then
				MapThemeService.switchTo(start, false)
			end
		end)
		local before = gameplaySnapshot(map)
		local decoration = decorationOutsideScenery(map)
		local layout = SceneryLayout.layout(Scenery)

		local order: { string } = {}
		for _, id in MapThemes.order do
			if id ~= start then
				table.insert(order, id)
			end
		end
		table.insert(order, start)

		local fewest, most = math.huge, 0
		for _, themeId in order do
			local theme = MapThemes.themes[themeId]
			local issues: { string } = {}
			local mark = ctx.mark()
			local ok, err = pcall(MapThemeService.switchTo :: (string, boolean) -> ...any, themeId, false)
			if not ok then
				table.insert(issues, `switchTo failed: {Kit.short(tostring(err))}`)
			end
			task.wait(ctx.options.settleSeconds)
			for _, message in ctx.take(mark) do
				table.insert(issues, `{message.kind}: {message.text}`)
			end
			if MapThemeService.current() ~= themeId or workspace:GetAttribute("MapTheme") ~= themeId then
				table.insert(issues, `the server says the map is {workspace:GetAttribute("MapTheme")}`)
			end

			local scenery = map:FindFirstChild("Scenery")
			if scenery == nil then
				table.insert(issues, "Map.Scenery is missing")
			else
				if scenery:GetAttribute("MapTheme") ~= theme.displayName then
					table.insert(issues, `the scenery was built as {scenery:GetAttribute("MapTheme")}`)
				end
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
				local trees = Kit.countParts(scenery:FindFirstChild("Trees"))
				local landmarks = Kit.countParts(scenery:FindFirstChild("Landmarks"))
				if trees ~= expectedTrees then
					table.insert(issues, `trees built {trees} parts, MapThemeRules counts {expectedTrees}`)
				end
				if landmarks ~= expectedLandmarks then
					table.insert(issues, `landmarks built {landmarks} parts, MapThemeRules counts {expectedLandmarks}`)
				end
				local parts = Kit.countParts(scenery)
				fewest, most = math.min(fewest, parts), math.max(most, parts)
				if parts + decoration > Scenery.partBudget then
					table.insert(
						issues,
						`{parts + decoration} decoration parts ({parts} scenery), over the budget of {Scenery.partBudget}`
					)
				end
			end

			local moved = differences(before, gameplaySnapshot(map))
			if #moved > 0 then
				table.insert(issues, `{#moved} gameplay parts changed: {Kit.list(moved, 2)}`)
			end
			local ground = map:FindFirstChild("Ground")
			if ground and ground:IsA("BasePart") and ground.Material.Name ~= theme.groundMaterial then
				table.insert(issues, `the ground is {ground.Material.Name}, not {theme.groundMaterial}`)
			end
			local clock = WorldLighting.clockTime()
			local wanted = Kit.expectedClockTime()
			if clock == nil or not Kit.near(clock, wanted) then
				table.insert(issues, `the lighting wants clock {clock}, expected {wanted}`)
			end
			for _, issue in issues do
				ctx.problem(`{themeId}: {issue}`)
			end
		end

		if MapThemeService.current() ~= start then
			ctx.problem(`not back on the first map ({start})`)
		end
		if fewest > most then
			return `{#order} maps`
		end
		return `{#order} maps, decoration {fewest + decoration}-{most + decoration} parts of {Scenery.partBudget}`
	end,
}

return Maps
