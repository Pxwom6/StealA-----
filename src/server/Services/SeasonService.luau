--!strict
--[[
	Seasonal themes (Config/Seasons): while a LiveOps event mapped to a theme is active, the map gets code-built
	decorations (Halloween: pumpkins, string lights, lamps, bats, ghosts; Winter: presents, decorated trees, string
	lights, snowmen, snowflakes, snowdrifts; Valentine's: potted roses, heart balloons, giant hearts pierced by Cupid's
	arrow, string lights, lamps; Easter: giant painted eggs, chocolate bunnies, blossom trees, butterflies, string
	lights, lamps) and a lighting mood; when it ends, they go away and the map's own lighting comes back. Which theme is on is decided by Logic/SeasonRules.activeTheme from the active event ids, and
	LiveOpsService tells this service whenever those change (events start and end by date while the server runs,
	remote config, `/event <id>` and `/event off`).

	Decorations live in workspace.SeasonDecor: every part is anchored, non-colliding, untouchable and invisible to
	raycasts and spatial queries (CanQuery false), so movement, steals, tagging and plot bounds never see them. The
	layout (Logic/SeasonRules.layout) keeps them out of plots, off the belt and off the lobby spawn; a prop that
	would still land inside a plot (e.g. after a map change) is skipped with a warning.

	Lighting: a theme's mood is an overlay in WorldLighting, above the map theme's own lighting: it fades in when the
	theme turns on and back out to the map's lighting when it ends (whatever map is on by then).
	The current theme id is mirrored to workspace attribute SeasonTheme ("" = none) for clients: the music
	(MusicController) and the theme's weather (WeatherController) follow it.
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

-- Colours a builder falls back on when the theme's palette leaves one out (CI makes sure it never does for a prop
-- the theme places: SeasonRules.PALETTE_KEYS).
local FALLBACK_COLORS: { [string]: string } = {
	pumpkin = "#F07A12",
	pumpkinFace = "#FFD23F",
	stem = "#3B7A2A",
	lampPost = "#2B2238",
	lampLight = "#FF9F1C",
	bat = "#1E1A2E",
	ghost = "#EDEBFF",
	tree = "#2E7D4F",
	wood = "#6B4A2E",
	treeStar = "#FFD23F",
	snow = "#F4F8FF",
	carrot = "#FF8A2A",
	coal = "#2A2A30",
	scarf = "#D7263D",
	hat = "#2A2A30",
	snowflake = "#E8F4FF",
	present = "#D7263D",
	ribbon = "#FFD23F",
	ornament = "#FF3B3B",
	pot = "#E8B0A0",
	leaves = "#3F8F4A",
	rose = "#E8204F",
	balloon = "#FF4F8B",
	balloonString = "#FFFFFF",
	heart = "#E8204F",
	pedestal = "#FFF4F8",
	arrow = "#F2C14E",
	egg = "#FFC4E1",
	eggStripe = "#5AB8F5",
	chocolate = "#5C3018",
	bunnyBow = "#FF8FC7",
	blossom = "#FFC0DA",
	butterfly = "#FFD24A",
	butterflyBody = "#3A2A40",
}

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

-- A palette colour (or its fallback).
local function paletteColor(palette: Types.SeasonPalette, key: string): Color3
	local value = (palette :: any)[key]
	return UiTheme.color(if type(value) == "string" then value else FALLBACK_COLORS[key])
end

-- The `index`th colour of a palette list (cycling), or the fallback.
local function listColor(list: { string }?, index: number, fallback: string): Color3
	if list == nil or #list == 0 then
		return UiTheme.color(FALLBACK_COLORS[fallback])
	end
	return UiTheme.color(list[(index - 1) % #list + 1])
end

-- Roblox cylinders run along X: this turns one upright.
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90))

-- A frame whose X axis runs from `a` to `b` (for cylinders between two points).
local function along(a: Vector3, b: Vector3): CFrame
	return CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0)
end

-- A sphere-meshed part: an ellipsoid of any proportions (a Ball part is always round).
local function ellipsoid(props: { [string]: any }): Part
	local p = part(props)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

-- The tree's tiers (studs: width, height, centre height, quarter turn) and which corners of the bottom three get a
-- bauble (local x / z signs).
local TREE_TIERS = {
	{ w = 6.6, h = 3.4, y = 3.9, turn = 45 },
	{ w = 5.2, h = 3.2, y = 6.6, turn = 0 },
	{ w = 3.8, h = 3, y = 9.1, turn = 45 },
	{ w = 2.4, h = 2.6, y = 11.3, turn = 0 },
}
local BAUBLE_CORNERS = { { { 1, 1 }, { -1, -1 } }, { { 1, -1 }, { -1, 1 } }, { { -1, 1 }, { 1, -1 } } }

-- A heart in the XY plane of `frame` (its face looks along the frame's front), `width` studs wide and `depth` thick:
-- two lobes on the upper edges of a square turned 45 degrees. Balls make a puffy balloon; cylinders a flat sculpture.
-- Three parts, all in `parent`; returns the middle one.
local function heart(frame: CFrame, width: number, depth: number, puffy: boolean, props: { [string]: any }): Part
	local side = width / (math.sqrt(0.5) + 1) -- the square's side
	local shift = side * (0.5 + math.sqrt(0.5) / 2 - math.sqrt(0.5)) / 2 -- centres the heart on the frame
	local lobeX = side * math.sqrt(0.5) / 2
	for _, x in { -lobeX, lobeX } do
		local at = frame * CFrame.new(x, lobeX - shift, 0)
		local lobe = part(props)
		if puffy then
			lobe.Shape = Enum.PartType.Ball
			lobe.Size = Vector3.one * side
			lobe.CFrame = at
		else
			lobe.Shape = Enum.PartType.Cylinder
			lobe.Size = Vector3.new(depth, side, side)
			lobe.CFrame = at * CFrame.Angles(0, math.rad(90), 0) -- a Roblox cylinder runs along X: turn it along Z
		end
	end
	local point = part(props)
	point.Size = Vector3.new(side, side, if puffy then side * 0.8 else depth)
	point.CFrame = frame * CFrame.new(0, -shift, 0) * CFrame.Angles(0, 0, math.rad(45))
	return point
end

-- Each builder makes exactly SeasonRules.PARTS_PER[kind] parts. `base` stands on the prop's position, front (-Z)
-- towards its face direction.
type Builder = (base: CFrame, prop: SeasonRules.Prop, palette: Types.SeasonPalette, parent: Instance) -> ()

local builders: { [string]: Builder } = {
	pumpkin = function(base, prop, palette, parent)
		local s = 2.8 * prop.scale
		local face = paletteColor(palette, "pumpkinFace")
		local body = part({
			Name = "Pumpkin",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * s,
			CFrame = base * CFrame.new(0, s / 2, 0),
			Color = paletteColor(palette, "pumpkin"),
			Parent = parent,
		})
		part({
			Name = "Stem",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.35 * s, 0.14 * s, 0.14 * s),
			CFrame = base * CFrame.new(0, s * 1.05, 0) * UPRIGHT,
			Color = paletteColor(palette, "stem"),
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
		local postColor = paletteColor(palette, "lampPost")
		local glow = paletteColor(palette, "lampLight")
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
			Color = glow,
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
		light(lantern, glow, 14, 1.2)
	end,

	bat = function(base, prop, palette, parent)
		local color = paletteColor(palette, "bat")
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
		local color = paletteColor(palette, "ghost")
		part({
			Name = "GhostSkirt",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(2.2 * s, 2.4 * s, 2.4 * s),
			CFrame = base * CFrame.new(0, 1.1 * s, 0) * UPRIGHT,
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

	-- A wrapped box with a lid, a ribbon both ways round and a rosette bow on top.
	present = function(base, prop, _palette, parent)
		local s = 2.3 * prop.scale -- box width
		local h = 0.85 * s -- box height
		local lid = 0.2 * h
		local wrap = UiTheme.color(prop.color or FALLBACK_COLORS.present)
		local ribbon = UiTheme.color(prop.color2 or FALLBACK_COLORS.ribbon)
		part({
			Name = "Present",
			Size = Vector3.new(s, h, s),
			CFrame = base * CFrame.new(0, h / 2, 0),
			Color = wrap,
			Parent = parent,
		})
		part({
			Name = "Lid",
			Size = Vector3.new(s * 1.08, lid, s * 1.08),
			CFrame = base * CFrame.new(0, h - lid * 0.1, 0),
			Color = wrap:Lerp(Color3.new(1, 1, 1), 0.12),
			Parent = parent,
		})
		local top = h + lid * 0.4 + 0.04
		for _, size in { Vector3.new(s * 1.1, top, 0.2 * s), Vector3.new(0.2 * s, top, s * 1.1) } do
			part({
				Name = "Ribbon",
				Size = size,
				CFrame = base * CFrame.new(0, top / 2, 0),
				Color = ribbon,
				Parent = parent,
			})
		end
		part({
			Name = "Bow",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 0.42 * s,
			CFrame = base * CFrame.new(0, top + 0.1 * s, 0),
			Color = ribbon,
			Parent = parent,
		})
	end,

	-- A fir of four tiers on a trunk, baubles on the tiers' corners and a glowing star on top.
	tree = function(base, _prop, palette, parent)
		local green = paletteColor(palette, "tree")
		part({
			Name = "Trunk",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(2.6, 1.2, 1.2),
			CFrame = base * CFrame.new(0, 1.3, 0) * UPRIGHT,
			Color = paletteColor(palette, "wood"),
			Material = Enum.Material.Wood,
			Parent = parent,
		})
		local bauble = 0
		for index, tier in TREE_TIERS do
			local frame = base * CFrame.new(0, tier.y, 0) * CFrame.Angles(0, math.rad(tier.turn), 0)
			part({
				Name = "Tier",
				Size = Vector3.new(tier.w, tier.h, tier.w),
				CFrame = frame,
				-- alternate two shades so the tiers read apart
				Color = if index % 2 == 0 then green:Lerp(Color3.new(0, 0, 0), 0.15) else green,
				Parent = parent,
			})
			local corners = BAUBLE_CORNERS[index]
			if corners then
				for _, corner in corners do
					bauble += 1
					local half = tier.w / 2
					part({
						Name = "Bauble",
						Shape = Enum.PartType.Ball,
						Size = Vector3.one * 1.05,
						CFrame = frame * CFrame.new(corner[1] * half * 0.9, -tier.h / 2 + 0.5, corner[2] * half * 0.9),
						Color = listColor(palette.ornaments, bauble, "ornament"),
						Material = Enum.Material.Neon,
						Parent = parent,
					})
				end
			end
		end
		local top = TREE_TIERS[#TREE_TIERS]
		local starAt = base * CFrame.new(0, top.y + top.h / 2 + 1, 0)
		local gold = paletteColor(palette, "treeStar")
		local star = part({
			Name = "Star",
			Size = Vector3.new(1.7, 1.7, 0.4),
			CFrame = starAt * CFrame.Angles(0, 0, math.rad(45)),
			Color = gold,
			Material = Enum.Material.Neon,
			Parent = parent,
		})
		part({
			Name = "Star",
			Size = Vector3.new(1.7, 1.7, 0.4),
			CFrame = starAt,
			Color = gold,
			Material = Enum.Material.Neon,
			Parent = parent,
		})
		light(star, gold, 12, 1.4)
	end,

	-- Three snowballs with coal eyes, a carrot nose, a top hat, a scarf and stick arms.
	snowman = function(base, prop, palette, parent)
		local s = prop.scale
		local snow = paletteColor(palette, "snow")
		local coal = paletteColor(palette, "coal")
		local scarf = paletteColor(palette, "scarf")
		for _, ball in { { d = 3.4, y = 1.5 }, { d = 2.6, y = 3.75 }, { d = 1.9, y = 5.35 } } do
			part({
				Name = "Snowball",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * ball.d * s,
				CFrame = base * CFrame.new(0, ball.y * s, 0),
				Color = snow,
				Material = Enum.Material.Snow,
				Parent = parent,
			})
		end
		for _, side in { -1, 1 } do
			part({
				Name = "Eye",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * 0.3 * s,
				CFrame = base * CFrame.new(side * 0.32 * s, 5.55 * s, -0.8 * s),
				Color = coal,
				Parent = parent,
			})
		end
		part({
			Name = "Nose",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.9 * s, 0.26 * s, 0.26 * s),
			CFrame = base * CFrame.new(0, 5.3 * s, -1.2 * s) * CFrame.Angles(0, math.rad(90), 0),
			Color = paletteColor(palette, "carrot"),
			Parent = parent,
		})
		local hat = paletteColor(palette, "hat")
		part({
			Name = "HatBrim",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.18 * s, 1.9 * s, 1.9 * s),
			CFrame = base * CFrame.new(0, 6.12 * s, 0) * UPRIGHT,
			Color = hat,
			Parent = parent,
		})
		part({
			Name = "HatTop",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1.1 * s, 1.25 * s, 1.25 * s),
			CFrame = base * CFrame.new(0, 6.7 * s, 0) * UPRIGHT,
			Color = hat,
			Parent = parent,
		})
		part({
			Name = "Scarf",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.45 * s, 1.95 * s, 1.95 * s),
			CFrame = base * CFrame.new(0, 4.72 * s, 0) * UPRIGHT,
			Color = scarf,
			Material = Enum.Material.Fabric,
			Parent = parent,
		})
		part({
			Name = "ScarfTail",
			Size = Vector3.new(0.45 * s, 1.2 * s, 0.18 * s),
			CFrame = base * CFrame.new(0.5 * s, 4.15 * s, -1.12 * s) * CFrame.Angles(math.rad(-18), 0, math.rad(-8)),
			Color = scarf,
			Material = Enum.Material.Fabric,
			Parent = parent,
		})
		for _, side in { -1, 1 } do
			local from = (base * CFrame.new(side * 1.05 * s, 4.0 * s, 0)).Position
			local to = (base * CFrame.new(side * 2.25 * s, 4.9 * s, 0.1 * s)).Position
			part({
				Name = "Arm",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new((to - from).Magnitude, 0.18 * s, 0.18 * s),
				CFrame = along(from, to),
				Color = paletteColor(palette, "wood"),
				Material = Enum.Material.Wood,
				Parent = parent,
			})
		end
	end,

	-- Three glowing bars crossed at 60 degrees, hanging in the air (the flake's face looks along its front).
	snowflake = function(base, prop, palette, parent)
		local s = prop.scale
		local color = paletteColor(palette, "snowflake")
		for i = 0, 2 do
			part({
				Name = "Snowflake",
				Size = Vector3.new(0.4 * s, 4.6 * s, 0.22),
				CFrame = base * CFrame.Angles(0, 0, math.rad(i * 60)),
				Color = color,
				Material = Enum.Material.Neon,
				Transparency = 0.1,
				Parent = parent,
			})
		end
	end,

	-- A rose bush in a pot, three blooms on the side facing the walkway.
	rosePot = function(base, prop, palette, parent)
		local s = prop.scale
		local pot = part({
			Name = "RosePot",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1.3 * s, 1.7 * s, 1.7 * s),
			CFrame = base * CFrame.new(0, 0.65 * s, 0) * UPRIGHT,
			Color = paletteColor(palette, "pot"),
			Parent = parent,
		})
		pot.Material = Enum.Material.Sandstone
		ellipsoid({
			Name = "RoseBush",
			Size = Vector3.new(2.3 * s, 2.1 * s, 2.3 * s),
			CFrame = base * CFrame.new(0, 2.2 * s, 0),
			Color = paletteColor(palette, "leaves"),
			Material = Enum.Material.Grass,
			Parent = parent,
		})
		local bloom = UiTheme.color(prop.color or FALLBACK_COLORS.rose)
		local middle = UiTheme.color(prop.color2 or prop.color or FALLBACK_COLORS.rose)
		for i, spot in { Vector3.new(-0.6, 2.5, -0.85), Vector3.new(0.05, 3.15, -0.55), Vector3.new(0.65, 2.3, -0.8) } do
			part({
				Name = "Rose",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * (if i == 2 then 0.85 else 0.72) * s,
				CFrame = base * CFrame.new(spot * s),
				Color = if i == 2 then middle else bloom,
				Material = Enum.Material.Fabric,
				Parent = parent,
			})
		end
	end,

	-- A glossy heart balloon on a string.
	heartBalloon = function(base, prop, palette, parent)
		local s = prop.scale
		local width = 3.2 * s
		heart(base, width, 0, true, {
			Name = "HeartBalloon",
			Color = UiTheme.color(prop.color or FALLBACK_COLORS.balloon),
			Reflectance = 0.15,
			Parent = parent,
		})
		local bottom = width * 0.45 -- the heart's point, below its middle
		part({
			Name = "BalloonString",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(5 * s, 0.12, 0.12),
			CFrame = base * CFrame.new(0, -bottom - 2.5 * s, 0) * UPRIGHT,
			Color = paletteColor(palette, "balloonString"),
			Parent = parent,
		})
	end,

	-- A big candy-red heart on a pedestal, pierced by a golden arrow, glowing softly.
	giantHeart = function(base, prop, palette, parent)
		local s = prop.scale
		local red = paletteColor(palette, "heart")
		part({
			Name = "Pedestal",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1.2 * s, 4.4 * s, 4.4 * s),
			CFrame = base * CFrame.new(0, 0.6 * s, 0) * UPRIGHT,
			Color = paletteColor(palette, "pedestal"),
			Material = Enum.Material.Marble,
			Parent = parent,
		})
		local width = 6.5 * s
		-- standing on its point, just planted in the pedestal
		local centre = base * CFrame.new(0, 1.2 * s + width * 0.45, 0)
		local middle = heart(centre, width, 1.6 * s, false, {
			Name = "GiantHeart",
			Color = red,
			Reflectance = 0.12,
			Parent = parent,
		})
		light(middle, red:Lerp(Color3.new(1, 1, 1), 0.4), 16, 1.2)
		-- the arrow: through the heart, rising to the right, its tip out one side and its feathers out the other
		local gold = paletteColor(palette, "arrow")
		local tilt = CFrame.Angles(0, 0, math.rad(25))
		local shaftLength = 8 * s
		part({
			Name = "ArrowShaft",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(shaftLength, 0.32 * s, 0.32 * s),
			CFrame = centre * tilt,
			Color = gold,
			Material = Enum.Material.Metal,
			Parent = parent,
		})
		part({
			Name = "ArrowTip",
			Size = Vector3.new(0.9 * s, 0.9 * s, 0.25 * s),
			CFrame = centre * tilt * CFrame.new(shaftLength / 2 + 0.2 * s, 0, 0) * CFrame.Angles(0, 0, math.rad(45)),
			Color = gold,
			Material = Enum.Material.Metal,
			Parent = parent,
		})
		for _, side in { -1, 1 } do
			part({
				Name = "ArrowFeather",
				Size = Vector3.new(1.1 * s, 0.45 * s, 0.12 * s),
				CFrame = centre
					* tilt
					* CFrame.new(-shaftLength / 2 + 0.6 * s, side * 0.3 * s, 0)
					* CFrame.Angles(0, 0, math.rad(side * 30)),
				Color = Color3.new(1, 1, 1),
				Parent = parent,
			})
		end
	end,

	-- A giant painted egg standing on its end: a pastel shell, two painted bands round it and two dots between them.
	easterEgg = function(base, prop, _palette, parent)
		local s = prop.scale
		local a, b = 1.5 * s, 2 * s -- the shell's half width and half height
		local paint = UiTheme.color(prop.color2 or FALLBACK_COLORS.eggStripe)
		local centre = base * CFrame.new(0, b, 0)
		ellipsoid({
			Name = "EasterEgg",
			Size = Vector3.new(2 * a, 2 * b, 2 * a),
			CFrame = centre,
			Color = UiTheme.color(prop.color or FALLBACK_COLORS.egg),
			Parent = parent,
		})
		-- each band is a thin disc a little wider than the shell where it crosses it
		for _, y in { 0.42 * b, -0.3 * b } do
			local radius = a * math.sqrt(1 - (y / b) ^ 2) + 0.06 * s
			part({
				Name = "EggBand",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.28 * s, 2 * radius, 2 * radius),
				CFrame = centre * CFrame.new(0, y, 0) * UPRIGHT,
				Color = paint,
				Parent = parent,
			})
		end
		local dotY = 0.06 * b
		for _, side in { -1, 1 } do
			local x = side * 0.42 * a
			local z = -a * math.sqrt(1 - (x / a) ^ 2 - (dotY / b) ^ 2)
			part({
				Name = "EggDot",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * 0.42 * s,
				CFrame = centre * CFrame.new(x, dotY, z + 0.1 * s),
				Color = paint:Lerp(Color3.new(1, 1, 1), 0.35),
				Parent = parent,
			})
		end
	end,

	-- A big glossy chocolate bunny sitting up: tall ears with milk-chocolate linings, white icing eyes with dark
	-- pupils, a pink nose, big feet and a ribbon bow at its neck.
	chocolateBunny = function(base, prop, palette, parent)
		local s = prop.scale
		local chocolate = paletteColor(palette, "chocolate")
		local milk = chocolate:Lerp(Color3.fromRGB(205, 150, 104), 0.55)
		local function piece(name: string, size: Vector3, at: Vector3, color: Color3, turn: CFrame?)
			ellipsoid({
				Name = name,
				Size = size * s,
				CFrame = base * CFrame.new(at * s) * (turn or CFrame.identity),
				Color = color,
				Reflectance = 0.1,
				Parent = parent,
			})
		end
		piece("BunnyBody", Vector3.new(3.4, 3.8, 3.2), Vector3.new(0, 1.9, 0.3), chocolate)
		piece("BunnyHead", Vector3.new(2.6, 2.4, 2.4), Vector3.new(0, 4.6, -0.2), chocolate)
		local bow = paletteColor(palette, "bunnyBow")
		for _, side in { -1, 1 } do
			local tilt = CFrame.Angles(0, 0, math.rad(-side * 10))
			piece("BunnyEar", Vector3.new(0.9, 3, 0.5), Vector3.new(side * 0.6, 6.9, 0), chocolate, tilt)
			piece("EarLining", Vector3.new(0.5, 2.2, 0.2), Vector3.new(side * 0.62, 6.8, -0.24), milk, tilt)
			piece("BunnyFoot", Vector3.new(1.1, 0.7, 1.9), Vector3.new(side * 0.95, 0.35, -0.9), chocolate)
			piece(
				"BunnyBow",
				Vector3.new(1, 0.7, 0.4),
				Vector3.new(side * 0.5, 3.25, -0.9),
				bow,
				CFrame.Angles(0, 0, math.rad(side * 15))
			)
			part({
				Name = "BunnyEye",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * 0.7 * s,
				CFrame = base * CFrame.new(side * 0.55 * s, 4.9 * s, -1.1 * s),
				Color = Color3.fromRGB(255, 252, 245),
				Parent = parent,
			})
			part({
				Name = "BunnyPupil",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * 0.36 * s,
				CFrame = base * CFrame.new(side * 0.55 * s, 4.85 * s, -1.37 * s),
				Color = Color3.fromRGB(40, 22, 14),
				Parent = parent,
			})
		end
		part({
			Name = "BunnyNose",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 0.4 * s,
			CFrame = base * CFrame.new(0, 4.35 * s, -1.35 * s),
			Color = Color3.fromRGB(255, 143, 168),
			Parent = parent,
		})
	end,

	-- A blossom tree: a trunk under four soft clouds of blossom in two colours.
	blossomTree = function(base, prop, palette, parent)
		local s = prop.scale
		part({
			Name = "BlossomTrunk",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(5 * s, 1 * s, 1 * s),
			CFrame = base * CFrame.new(0, 2.5 * s, 0) * UPRIGHT,
			Color = paletteColor(palette, "wood"),
			Material = Enum.Material.Wood,
			Parent = parent,
		})
		local first = UiTheme.color(prop.color or FALLBACK_COLORS.blossom)
		local second = UiTheme.color(prop.color2 or prop.color or FALLBACK_COLORS.blossom)
		for i, cloud in
			{
				{ size = Vector3.new(6.2, 4.4, 6.2), at = Vector3.new(0, 6.6, 0) },
				{ size = Vector3.new(3.8, 3, 3.8), at = Vector3.new(2.4, 5.6, 0.8) },
				{ size = Vector3.new(3.6, 3, 3.6), at = Vector3.new(-2.2, 5.8, -0.9) },
				{ size = Vector3.new(3.4, 2.8, 3.4), at = Vector3.new(0.3, 8.4, -0.4) },
			}
		do
			ellipsoid({
				Name = "Blossom",
				Size = cloud.size * s,
				CFrame = base * CFrame.new(cloud.at * s),
				Color = if i % 2 == 1 then first else second,
				Material = Enum.Material.Grass,
				Parent = parent,
			})
		end
	end,

	-- A butterfly hovering: a slim body and two wings tilted up.
	butterfly = function(base, prop, palette, parent)
		local s = prop.scale
		ellipsoid({
			Name = "ButterflyBody",
			Size = Vector3.new(0.45, 0.45, 1.8) * s,
			CFrame = base,
			Color = paletteColor(palette, "butterflyBody"),
			Parent = parent,
		})
		local wings = UiTheme.color(prop.color or FALLBACK_COLORS.butterfly)
		for _, side in { -1, 1 } do
			ellipsoid({
				Name = "ButterflyWing",
				Size = Vector3.new(2.6, 0.12, 2.2) * s,
				CFrame = base
					* CFrame.new(side * 1.3 * s, 0.2 * s, -0.15 * s)
					* CFrame.Angles(0, 0, math.rad(side * 25)),
				Color = wings,
				Parent = parent,
			})
		end
	end,

	-- A low drift of snow against the front wall.
	snowPile = function(base, prop, palette, parent)
		local s = prop.scale
		ellipsoid({
			Name = "Snowdrift",
			Size = Vector3.new(6 * s, 1.8 * s, 3 * s),
			CFrame = base * CFrame.new(0, 0.25 * s, 0),
			Color = paletteColor(palette, "snow"),
			Material = Enum.Material.Snow,
			Parent = parent,
		})
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
