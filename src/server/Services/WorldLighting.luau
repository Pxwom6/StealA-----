--!strict
--[[
	The world's lighting, in layers: the current map's preset at the bottom (Config/MapThemes, set by MapBuilder when it
	builds or restyles the map), and overlays on top (a seasonal theme's mood, set by SeasonService; a weather
	modifier's sky, set by ModifierService, above it). The highest-priority overlay decides every value it has (time of
	day, brightness, ambient colours, haze, colour grading, the clouds if it has them, and whether the sun shows); the
	rest always comes from the map. Every change tweens over a few seconds.

	This module owns the lighting instances: Lighting's own properties, its Atmosphere, Sky, Bloom, ColorCorrection and
	SunRays children (created once, named World*), and the terrain's Clouds. Nothing else should change them, except
	the Studio-only /sky preview (DevCommands), which the next change undoes.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Types = require(ReplicatedStorage.Shared.Types)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)

local WorldLighting = {}

type Overlay = { lighting: Types.SeasonLighting, priority: number }

local base: Types.SceneryLighting? = nil
local overlays: { [string]: Overlay } = {}
local running: { Tween } = {}

-- The child of Lighting called `name`, created as `className` the first time. A Lighting child of the same class
-- that came with the place (the Baseplate template has an Atmosphere and a Sky) is adopted and renamed, so there is
-- never a second one fighting over the look.
local function owned(className: string, name: string, parent: Instance?): Instance
	local container = parent or Lighting
	local existing = container:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end
	for _, child in container:GetChildren() do
		if child.ClassName == className and not string.match(child.Name, "^World") then
			child.Name = name
			return child
		end
	end
	local created = Instance.new(className)
	created.Name = name
	created.Parent = container
	return created
end

-- The overlay with the highest priority (ties: the alphabetically first id), or nil.
local function topOverlay(): Types.SeasonLighting?
	local bestId: string? = nil
	local best: Overlay? = nil
	for id, overlay in overlays do
		if
			best == nil
			or overlay.priority > best.priority
			or (overlay.priority == best.priority and bestId ~= nil and id < bestId)
		then
			bestId, best = id, overlay
		end
	end
	return if best then best.lighting else nil
end

local function stop()
	for _, tween in running do
		tween:Cancel()
	end
	running = {}
end

local function set(instance: Instance, goals: { [string]: any }, seconds: number)
	if seconds <= 0 then
		for key, value in goals do
			(instance :: any)[key] = value
		end
		return
	end
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	local tween = TweenService:Create(instance, info, goals)
	table.insert(running, tween)
	tween:Play()
end

-- Moves every lighting value to what the layers say now, over `seconds` (0 = at once).
function WorldLighting.apply(seconds: number)
	local preset = base
	if preset == nil then
		return
	end
	stop()
	local top = topOverlay()
	local mood: Types.SeasonLighting = top
		or {
			clockTime = preset.clockTime,
			brightness = preset.brightness,
			ambient = preset.ambient,
			outdoorAmbient = preset.outdoorAmbient,
			colorShiftTop = preset.colorShiftTop,
			atmosphere = preset.atmosphere,
			colorCorrection = preset.colorCorrection,
		}

	Lighting.GlobalShadows = true
	set(Lighting, {
		ClockTime = mood.clockTime,
		Brightness = mood.brightness,
		Ambient = UiTheme.color(mood.ambient),
		OutdoorAmbient = UiTheme.color(mood.outdoorAmbient),
		ColorShift_Top = UiTheme.color(mood.colorShiftTop),
		ColorShift_Bottom = UiTheme.color(preset.colorShiftBottom),
		GeographicLatitude = preset.geographicLatitude,
		ExposureCompensation = preset.exposureCompensation,
		EnvironmentDiffuseScale = preset.environmentDiffuseScale,
		EnvironmentSpecularScale = preset.environmentSpecularScale,
		ShadowSoftness = preset.shadowSoftness,
	}, seconds)

	local a = mood.atmosphere
	set(owned("Atmosphere", "WorldAtmosphere"), {
		Density = a.density,
		Offset = a.offset,
		Color = UiTheme.color(a.color),
		Decay = UiTheme.color(a.decay),
		Glare = a.glare,
		Haze = a.haze,
	}, seconds)

	local c = mood.colorCorrection
	local correction = owned("ColorCorrectionEffect", "WorldColorCorrection") :: ColorCorrectionEffect
	correction.Enabled = true
	set(correction, {
		TintColor = UiTheme.color(c.tint),
		Brightness = c.brightness,
		Contrast = c.contrast,
		Saturation = c.saturation,
	}, seconds)

	set(owned("BloomEffect", "WorldBloom"), {
		Intensity = preset.bloom.intensity,
		Size = preset.bloom.size,
		Threshold = preset.bloom.threshold,
	}, seconds)
	set(owned("SunRaysEffect", "WorldSunRays"), {
		Intensity = preset.sunRays.intensity,
		Spread = preset.sunRays.spread,
	}, seconds)

	-- Roblox's own skybox textures (a new Sky starts with them); only the sun, moon and stars change. Sizes and star
	-- counts are whole-number properties: set, not tweened. An overlay with `hideSun` (Eclipse) takes the sun (and the
	-- moon) away: each client draws the eclipsed sun where it was (WeatherController).
	local sky = owned("Sky", "WorldSky") :: Sky
	sky.CelestialBodiesShown = mood.hideSun ~= true
	sky.SunAngularSize = preset.sky.sunAngularSize
	sky.MoonAngularSize = preset.sky.moonAngularSize
	sky.StarCount = preset.sky.starCount

	local cloudLook = mood.clouds or preset.clouds
	local clouds = owned("Clouds", "WorldClouds", workspace.Terrain) :: Clouds
	clouds.Enabled = true
	set(clouds, {
		Cover = cloudLook.cover,
		Density = cloudLook.density,
		Color = UiTheme.color(cloudLook.color),
	}, seconds)
end

-- The map's lighting (the bottom layer).
function WorldLighting.setBase(preset: Types.SceneryLighting, seconds: number)
	base = preset
	WorldLighting.apply(seconds)
end

-- Adds, replaces or (lighting = nil) removes an overlay. The highest `priority` wins.
function WorldLighting.setOverlay(id: string, lighting: Types.SeasonLighting?, priority: number, seconds: number)
	if lighting then
		overlays[id] = { lighting = lighting, priority = priority }
	else
		overlays[id] = nil
	end
	WorldLighting.apply(seconds)
end

-- The time of day the layers want right now (tests and previews).
function WorldLighting.clockTime(): number?
	local top = topOverlay()
	if top then
		return top.clockTime
	end
	return if base then base.clockTime else nil
end

return WorldLighting
