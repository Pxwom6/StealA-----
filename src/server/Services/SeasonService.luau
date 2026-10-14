--!strict
--[[
	Seasonal themes (Config/Seasons): while a LiveOps event mapped to a theme is active, the map gets code-built
	decorations (pumpkins, string lights, lamps, bats, ghosts) and a lighting mood; when it ends, they go away and the
	map's own lighting comes back. Which theme is on is decided by Logic/SeasonRules.activeTheme from the active
	event ids, and LiveOpsService tells this service whenever those change (events start and end by date while the
	server runs, remote config, `/event <id>` and `/event off`).

	Decorations live in workspace.SeasonDecor: every part is anchored, non-colliding, untouchable and invisible to
	raycasts and spatial queries (CanQuery false), so movement, steals, tagging and plot bounds never see them. The
	layout (Logic/SeasonRules.layout) keeps them out of plots, off the belt and off the lobby spawn; a prop that
	would still land inside a plot (e.g. after a map change) is skipped with a warning.

	Lighting: a theme's mood is an overlay in WorldLighting, above the map theme's own lighting: it fades in when the
	theme turns on and back out to the map's lighting when it ends (whatever map is on by then).
	The current theme id is mirrored to workspace attribute SeasonTheme ("" = none) for clients.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Gameplay = require(ReplicatedStorage.Shared.Config.Gameplay)
local Seasons = require(ReplicatedStorage.Shared.Config.Seasons)
local SeasonRules = require(ReplicatedStorage.Shared.Logic.SeasonRules)
local Types = require(ReplicatedStorage.Shared.Types)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local LiveOpsService = require(script.Parent.LiveOpsService)
local MapBuilder = require(script.Parent.MapBuilder)
local WorldLighting = require(script.Parent.WorldLighting)

local SeasonService = {}

-- The seasonal mood sits above the map's lighting (WorldLighting overlays: highest priority wins).
local LIGHTING_LAYER = "season"
local LIGHTING_PRIORITY = 10

local world: MapBuilder.World
local currentTheme: string? = nil
local decor: Folder? = nil

-- Decorations ----------------------------------------------------------------------------------------------------

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		(p :: any)[key] = value
	end
	return p
end

local function light(parent: BasePart, color: Color3, range: number, brightness: number)
	local pointLight = Instance.new("PointLight")
	pointLight.Color = color
	pointLight.Range = range
	pointLight.Brightness = brightness
	pointLight.Shadows = false
	pointLight.Parent = parent
end

-- Each builder makes exactly SeasonRules.PARTS_PER[kind] parts. `base` stands on the prop's position, front (-Z)
-- towards its face direction.
type Builder = (base: CFrame, prop: SeasonRules.Prop, palette: Types.SeasonPalette, parent: Instance) -> ()

local builders: { [string]: Builder } = {
	pumpkin = function(base, prop, palette, parent)
		local s = 2.8 * prop.scale
		local face = UiTheme.color(palette.pumpkinFace)
		local body = part({
			Name = "Pumpkin",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * s,
			CFrame = base * CFrame.new(0, s / 2, 0),
			Color = UiTheme.color(palette.pumpkin),
			Parent = parent,
		})
		part({
			Name = "Stem",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.35 * s, 0.14 * s, 0.14 * s),
			CFrame = base * CFrame.new(0, s * 1.05, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color = UiTheme.color(palette.stem),
			Parent = parent,
		})
		for _, side in { -1, 1 } do
			part({
				Name = "Eye",
				Size = Vector3.new(0.22 * s, 0.22 * s, 0.2),
				CFrame = base * CFrame.new(side * 0.2 * s, 0.62 * s, -0.45 * s) * CFrame.Angles(0, 0, math.rad(45)),
				Color = face,
				Material = Enum.Material.Neon,
				Parent = parent,
			})
		end
		part({
			Name = "Mouth",
			Size = Vector3.new(0.42 * s, 0.1 * s, 0.2),
			CFrame = base * CFrame.new(0, 0.36 * s, -0.47 * s),
			Color = face,
			Material = Enum.Material.Neon,
			Parent = parent,
		})
		if prop.scale >= 1 then
			light(body, face, 10, 1.5) -- only the big ones by the plots: lights are not free
		end
	end,

	bulb = function(base, prop, _palette, parent)
		part({
			Name = "Bulb",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 0.7 * prop.scale,
			CFrame = base,
			Color = UiTheme.color(prop.color or "#FFFFFF"),
			Material = Enum.Material.Neon,
			Parent = parent,
		})
	end,

	lamp = function(base, _prop, palette, parent)
		local postColor = UiTheme.color(palette.lampPost)
		part({
			Name = "LampPost",
			Size = Vector3.new(0.5, 6, 0.5),
			CFrame = base * CFrame.new(0, 3, 0),
			Color = postColor,
			Parent = parent,
		})
		local lantern = part({
			Name = "Lantern",
			Size = Vector3.new(1.2, 1.4, 1.2),
			CFrame = base * CFrame.new(0, 6.7, 0),
			Color = UiTheme.color(palette.lampLight),
			Material = Enum.Material.Neon,
			Parent = parent,
		})
		part({
			Name = "LampCap",
			Size = Vector3.new(1.6, 0.3, 1.6),
			CFrame = base * CFrame.new(0, 7.55, 0),
			Color = postColor,
			Parent = parent,
		})
		light(lantern, UiTheme.color(palette.lampLight), 14, 1.2)
	end,

	bat = function(base, prop, palette, parent)
		local color = UiTheme.color(palette.bat)
		local s = prop.scale
		part({
			Name = "Bat",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 1.1 * s,
			CFrame = base,
			Color = color,
			Parent = parent,
		})
		for _, side in { -1, 1 } do
			part({
				Name = "Wing",
				Size = Vector3.new(1.8 * s, 0.12, 0.9 * s),
				CFrame = base * CFrame.new(side * 1.15 * s, 0.15 * s, 0) * CFrame.Angles(0, 0, math.rad(side * 20)),
				Color = color,
				Parent = parent,
			})
		end
	end,

	ghost = function(base, prop, palette, parent)
		local s = prop.scale
		local color = UiTheme.color(palette.ghost)
		part({
			Name = "GhostSkirt",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(2.2 * s, 2.4 * s, 2.4 * s),
			CFrame = base * CFrame.new(0, 1.1 * s, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color = color,
			Transparency = 0.3,
			Parent = parent,
		})
		part({
			Name = "GhostHead",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 2.4 * s,
			CFrame = base * CFrame.new(0, 2.4 * s, 0),
			Color = color,
			Transparency = 0.2,
			Parent = parent,
		})
		for _, side in { -1, 1 } do
			part({
				Name = "GhostEye",
				Size = Vector3.new(0.3 * s, 0.45 * s, 0.15),
				CFrame = base * CFrame.new(side * 0.4 * s, 2.6 * s, -1.12 * s),
				Color = Color3.fromRGB(25, 20, 35),
				Parent = parent,
			})
		end
	end,
}

-- The map as SeasonRules sees it, from the plots MapBuilder actually built.
local function mapShape(): SeasonRules.MapShape
	local entrances: { SeasonRules.Entrance } = {}
	local wallTopY = 0
	for _, plot in world.plots do
		local entrance = (plot.origin * CFrame.new(0, 0, -Gameplay.map.plotDepth / 2)).Position
		local out = plot.origin.LookVector
		table.insert(entrances, { x = entrance.X, z = entrance.Z, outX = out.X, outZ = out.Z })
		wallTopY = plot.floorY + Gameplay.map.wallHeight
	end
	return {
		entrances = entrances,
		entranceWidth = Gameplay.map.entranceWidth,
		plotWidth = Gameplay.map.plotWidth,
		groundY = world.walkwayY,
		wallTopY = wallTopY,
		beltLength = Gameplay.belt.length,
		beltWidth = Gameplay.belt.width,
		walkwayWidth = Gameplay.map.walkwayWidth,
	}
end

local function insidePlot(x: number, z: number): boolean
	for _, plot in world.plots do
		local rect = plot.rect
		if x > rect.minX and x < rect.maxX and z > rect.minZ and z < rect.maxZ then
			return true
		end
	end
	return false
end

local function clearDecorations()
	if decor then
		decor:Destroy()
		decor = nil
	end
end

local function buildDecorations(themeId: string, theme: Types.SeasonTheme)
	clearDecorations()
	local folder = Instance.new("Folder")
	folder.Name = "SeasonDecor"
	folder:SetAttribute("Theme", themeId)
	local skipped = 0
	for _, prop in SeasonRules.layout(theme.decorations, theme.palette, mapShape()) do
		if insidePlot(prop.x, prop.z) then
			skipped += 1
			continue
		end
		local position = Vector3.new(prop.x, prop.y, prop.z)
		local base = CFrame.lookAt(position, position + Vector3.new(prop.faceX, 0, prop.faceZ))
		builders[prop.kind](base, prop, theme.palette, folder)
	end
	if skipped > 0 then
		warn(`[Seasons] {themeId}: skipped {skipped} decorations that would sit inside a plot`)
	end
	local parts = 0
	for _, descendant in folder:GetDescendants() do
		if descendant:IsA("BasePart") then
			parts += 1
		end
	end
	if parts > Seasons.maxParts then
		warn(`[Seasons] {themeId}: {parts} decoration parts, over the budget of {Seasons.maxParts}`)
	end
	folder.Parent = workspace
	decor = folder
end

-- Theme switching -------------------------------------------------------------------------------------------------

local function refresh(activeEventIds: { [string]: boolean })
	local themeId = SeasonRules.activeTheme(Seasons, activeEventIds)
	if themeId == currentTheme then
		return
	end
	currentTheme = themeId
	if themeId == nil then
		clearDecorations()
		WorldLighting.setOverlay(LIGHTING_LAYER, nil, LIGHTING_PRIORITY, Seasons.transitionSeconds)
		workspace:SetAttribute("SeasonTheme", "")
		print("[Seasons] theme off")
		return
	end
	local theme = Seasons.themes[themeId]
	buildDecorations(themeId, theme)
	WorldLighting.setOverlay(LIGHTING_LAYER, theme.lighting, LIGHTING_PRIORITY, Seasons.transitionSeconds)
	workspace:SetAttribute("SeasonTheme", themeId)
	print(`[Seasons] theme on: {themeId}`)
end

function SeasonService.currentTheme(): string?
	return currentTheme
end

function SeasonService.start(worldDef: MapBuilder.World)
	world = worldDef
	workspace:SetAttribute("SeasonTheme", "")
	for _, problem in SeasonRules.validate(Seasons, mapShape()) do
		warn(`[Seasons] config problem: {problem}`)
	end
	LiveOpsService.onActiveEventsChanged(refresh)
	refresh(LiveOpsService.activeEventIds())
end

return SeasonService
