--!strict
--[[
	Seasonal themes (Config/Seasons): while a LiveOps event mapped to a theme is active, the map gets code-built
	decorations (pumpkins, string lights, lamps, bats, ghosts) and a lighting mood; when it ends, they go away and the
	original lighting comes back. Which theme is on is decided by Logic/SeasonRules.activeTheme from the active
	event ids, and LiveOpsService tells this service whenever those change (events start and end by date while the
	server runs, remote config, `/event <id>` and `/event off`).

	Decorations live in workspace.SeasonDecor: every part is anchored, non-colliding, untouchable and invisible to
	raycasts and spatial queries (CanQuery false), so movement, steals, tagging and plot bounds never see them. The
	layout (Logic/SeasonRules.layout) keeps them out of plots, off the belt and off the lobby spawn; a prop that
	would still land inside a plot (e.g. after a map change) is skipped with a warning.

	Lighting: the original values of every property a theme changes are saved when a theme first turns on, tweened
	to the theme's values, and tweened back (then set exactly) when no theme is on. An Atmosphere that already
	exists is restyled and restored; one this service had to create is removed again, like its ColorCorrection.
	The current theme id is mirrored to workspace attribute SeasonTheme ("" = none) for clients.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Gameplay = require(ReplicatedStorage.Shared.Config.Gameplay)
local Seasons = require(ReplicatedStorage.Shared.Config.Seasons)
local SeasonRules = require(ReplicatedStorage.Shared.Logic.SeasonRules)
local Types = require(ReplicatedStorage.Shared.Types)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local LiveOpsService = require(script.Parent.LiveOpsService)
local MapBuilder = require(script.Parent.MapBuilder)

local SeasonService = {}

local CREATED_ATMOSPHERE = "SeasonAtmosphere"
local CREATED_CORRECTION = "SeasonColorCorrection"

type AtmosphereValues = {
	Density: number,
	Offset: number,
	Color: Color3,
	Decay: Color3,
	Glare: number,
	Haze: number,
}

type LightingSnapshot = {
	ClockTime: number,
	Brightness: number,
	Ambient: Color3,
	OutdoorAmbient: Color3,
	ColorShift_Top: Color3,
	atmosphere: AtmosphereValues?, -- values of an Atmosphere that existed before the theme
}

local world: MapBuilder.World
local currentTheme: string? = nil
local decor: Folder? = nil
local original: LightingSnapshot? = nil
local generation = 0 -- bumped on every lighting change, so a stale restore never finishes over a newer theme
local running: { Tween } = {}

-- No atmosphere: what a created Atmosphere fades in from and out to.
local CLEAR_ATMOSPHERE: AtmosphereValues = {
	Density = 0,
	Offset = 0,
	Color = Color3.fromRGB(199, 199, 199),
	Decay = Color3.fromRGB(106, 112, 125),
	Glare = 0,
	Haze = 0,
}

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
local builders: { [string]: (base: CFrame, prop: SeasonRules.Prop, palette: Types.SeasonPalette, parent: Instance) -> () } =
	{
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

-- Lighting -------------------------------------------------------------------------------------------------------

local function stopTweens()
	for _, tween in running do
		tween:Cancel()
	end
	running = {}
end

local function tween(instance: Instance, goals: { [string]: any })
	local info = TweenInfo.new(Seasons.transitionSeconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	local t = TweenService:Create(instance, info, goals)
	table.insert(running, t)
	t:Play()
end

local function atmosphereValues(atmosphere: Atmosphere): AtmosphereValues
	return {
		Density = atmosphere.Density,
		Offset = atmosphere.Offset,
		Color = atmosphere.Color,
		Decay = atmosphere.Decay,
		Glare = atmosphere.Glare,
		Haze = atmosphere.Haze,
	}
end

-- The Atmosphere we may restyle: one that was there before the theme (not ours), or nil.
local function foreignAtmosphere(): Atmosphere?
	for _, child in Lighting:GetChildren() do
		if child:IsA("Atmosphere") and child.Name ~= CREATED_ATMOSPHERE then
			return child
		end
	end
	return nil
end

local function snapshot(): LightingSnapshot
	local atmosphere = foreignAtmosphere()
	return {
		ClockTime = Lighting.ClockTime,
		Brightness = Lighting.Brightness,
		Ambient = Lighting.Ambient,
		OutdoorAmbient = Lighting.OutdoorAmbient,
		ColorShift_Top = Lighting.ColorShift_Top,
		atmosphere = if atmosphere then atmosphereValues(atmosphere) else nil,
	}
end

local function lightingGoals(values: LightingSnapshot): { [string]: any }
	return {
		ClockTime = values.ClockTime,
		Brightness = values.Brightness,
		Ambient = values.Ambient,
		OutdoorAmbient = values.OutdoorAmbient,
		ColorShift_Top = values.ColorShift_Top,
	}
end

local function applyLighting(lighting: Types.SeasonLighting)
	generation += 1
	stopTweens()
	if original == nil then
		original = snapshot()
	end
	tween(Lighting, {
		ClockTime = lighting.clockTime,
		Brightness = lighting.brightness,
		Ambient = UiTheme.color(lighting.ambient),
		OutdoorAmbient = UiTheme.color(lighting.outdoorAmbient),
		ColorShift_Top = UiTheme.color(lighting.colorShiftTop),
	})

	local atmosphere = foreignAtmosphere()
	if atmosphere == nil then
		local created = Lighting:FindFirstChild(CREATED_ATMOSPHERE) :: Atmosphere?
		if created == nil then
			local newAtmosphere = Instance.new("Atmosphere")
			newAtmosphere.Name = CREATED_ATMOSPHERE
			for key, value in CLEAR_ATMOSPHERE :: any do
				(newAtmosphere :: any)[key] = value
			end
			newAtmosphere.Parent = Lighting
			created = newAtmosphere
		end
		atmosphere = created
	end
	local a = lighting.atmosphere
	tween(atmosphere :: Atmosphere, {
		Density = a.density,
		Offset = a.offset,
		Color = UiTheme.color(a.color),
		Decay = UiTheme.color(a.decay),
		Glare = a.glare,
		Haze = a.haze,
	})

	local correction = Lighting:FindFirstChild(CREATED_CORRECTION) :: ColorCorrectionEffect?
	if correction == nil then
		local newCorrection = Instance.new("ColorCorrectionEffect")
		newCorrection.Name = CREATED_CORRECTION
		newCorrection.Parent = Lighting
		correction = newCorrection
	end
	local c = lighting.colorCorrection
	tween(correction :: ColorCorrectionEffect, {
		TintColor = UiTheme.color(c.tint),
		Brightness = c.brightness,
		Contrast = c.contrast,
		Saturation = c.saturation,
	})
end

local function restoreLighting()
	local saved = original
	if saved == nil then
		return
	end
	generation += 1
	local thisGeneration = generation
	stopTweens()
	tween(Lighting, lightingGoals(saved))
	local atmosphere = foreignAtmosphere()
	if atmosphere and saved.atmosphere then
		tween(atmosphere, saved.atmosphere :: any)
	end
	local created = Lighting:FindFirstChild(CREATED_ATMOSPHERE)
	if created then
		tween(created, CLEAR_ATMOSPHERE :: any)
	end
	local correction = Lighting:FindFirstChild(CREATED_CORRECTION)
	if correction then
		tween(correction, { TintColor = Color3.new(1, 1, 1), Brightness = 0, Contrast = 0, Saturation = 0 })
	end

	task.delay(Seasons.transitionSeconds + 0.1, function()
		if thisGeneration ~= generation then
			return -- a theme came back meanwhile: it owns the lighting now
		end
		running = {}
		for key, value in lightingGoals(saved) do
			(Lighting :: any)[key] = value
		end
		local current = foreignAtmosphere()
		if current and saved.atmosphere then
			for key, value in saved.atmosphere :: any do
				(current :: any)[key] = value
			end
		end
		for _, name in { CREATED_ATMOSPHERE, CREATED_CORRECTION } do
			local instance = Lighting:FindFirstChild(name)
			if instance then
				instance:Destroy()
			end
		end
		original = nil
	end)
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
		restoreLighting()
		workspace:SetAttribute("SeasonTheme", "")
		print("[Seasons] theme off")
		return
	end
	local theme = Seasons.themes[themeId]
	buildDecorations(themeId, theme)
	if theme.lighting then
		applyLighting(theme.lighting)
	else
		restoreLighting()
	end
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
