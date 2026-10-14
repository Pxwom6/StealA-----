--!strict
--[[
	Builds the 3D model for a Snackling.

	If ReplicatedStorage.CreatureModels contains a Model named exactly `def.modelName`, that model is cloned
	(drop your own art there; it should face -Z and stand on y = 0 with a PrimaryPart) and scaled by the rarity's
	modelScale. Otherwise the creature's polished model in Config/CreatureParts is built, or failing that its recipe
	in Config/CreatureLooks: Logic/CreatureRecipe turns either into a list of parts (already at the rarity's scale)
	and this module makes them: Ball / Block / Cylinder parts, WedgePart, and Block parts with a Sphere SpecialMesh
	for ellipsoids. No asset ids are needed.

	Every model returned has a PrimaryPart called "Root" at its feet, all other parts welded to it, and no
	collisions, so it can be anchored on a podium, moved along the belt, or welded above a thief's head.
	Rarity flair (glow, sparkles, aura ring) is added on top of either kind of model, then the mutation look (if
	any): material, tint, transparency, sparkles, rainbow, glow light, and a particle preset (honey drips, snow,
	embers, sparks, stars... MUTATION_PARTICLES below; the names are listed in Logic/Catalog.MUTATION_PARTICLES). Face parts (eyes, pupils, highlights, mouth,
	cheeks...) carry the attribute MutationSkip = true and keep their look, so a face always reads; so do the Root
	and the rarity Aura. In a custom model, give a part MutationSkip = true to keep its look too.
	Rainbow parts are tagged RAINBOW_TAG; the client cycles their hue (MutationFxController).

	Anchored models are tagged IDLE_TAG (unless options.idle == false) and the client's IdleController gives them a
	gentle bob / squash / sway; the parts the squash resizes carry the attribute SquashAxis (their local up axis).
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CreatureLooks = require("./Config/CreatureLooks")
local CreatureParts = require("./Config/CreatureParts")
local CreatureRecipe = require("./Logic/CreatureRecipe")
local Types = require("./Types")
local UiTheme = require("./UiTheme")

local CreatureVisuals = {}

local PARTICLE_RATE: { [number]: number } = { [4] = 5, [5] = 9, [6] = 16, [7] = 26 }
local SPARKLE_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local MUTATION_PARTICLE_RATE = 8
-- Parts a mutation never restyles by name (Root is invisible; Aura is the rarity ring). Face parts of recipe models
-- are skipped through their MutationSkip attribute.
local MUTATION_SKIP: { [string]: boolean } = { Root = true, Aura = true, Eye = true, Pupil = true, Mouth = true }
local RAINBOW_SPEED = 0.25 -- hue turns per second

CreatureVisuals.RAINBOW_TAG = "MutationRainbow"
CreatureVisuals.IDLE_TAG = "SnacklingIdle"

-- A plain round Snackling for a creature whose recipe is missing (a config mistake CI also catches).
local FALLBACK_LOOK: Types.CreatureLook = {
	size = 2.6,
	plan = "blob",
	feet = true,
	body = { skin = "round", color = "#F2C27A" },
	face = { eyes = "round", mouth = "smile", cheeks = "#FF8FA8" },
	features = {},
	toppings = {},
}

local function rainbowSequence(): ColorSequence
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 90)),
		ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 230, 90)),
		ColorSequenceKeypoint.new(0.66, Color3.fromRGB(90, 255, 200)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(170, 110, 255)),
	})
end

local function sequence(keys: { { number } }): NumberSequence
	local points: { NumberSequenceKeypoint } = {}
	for _, key in keys do
		table.insert(points, NumberSequenceKeypoint.new(key[1], key[2]))
	end
	return NumberSequence.new(points)
end

local function colours(list: { string }): ColorSequence
	if #list == 1 then
		return ColorSequence.new(UiTheme.color(list[1]))
	end
	local points: { ColorSequenceKeypoint } = {}
	for index, hex in list do
		table.insert(points, ColorSequenceKeypoint.new((index - 1) / (#list - 1), UiTheme.color(hex)))
	end
	return ColorSequence.new(points)
end

-- ParticleEmitter properties of each mutation particle preset (MutationLook.particles), emitted from the body.
-- Logic/Catalog.MUTATION_PARTICLES lists the names; the world smoke test builds every mutation on a Snackling.
local MUTATION_PARTICLES: { [string]: { [string]: any } } = {
	drips = { -- honey sliding off and dripping down
		Texture = SPARKLE_TEXTURE,
		Color = colours({ "#F2A022", "#D9780A" }),
		LightEmission = 0.2,
		Size = sequence({ { 0, 0.24 }, { 1, 0.16 } }),
		Speed = NumberRange.new(0.2, 0.6),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, -9, 0),
		Lifetime = NumberRange.new(0.6, 1),
		Rate = 5,
	},
	sprinkles = { -- candy sprinkles popping off
		Texture = SPARKLE_TEXTURE,
		Color = colours({ "#FF5C8A", "#FFD23F", "#7CD9FF", "#B678FF" }),
		LightEmission = 0.3,
		Size = sequence({ { 0, 0.22 }, { 1, 0.18 } }),
		Speed = NumberRange.new(2, 4),
		SpreadAngle = Vector2.new(60, 60),
		EmissionDirection = Enum.NormalId.Top,
		Acceleration = Vector3.new(0, -10, 0),
		Lifetime = NumberRange.new(0.8, 1.2),
		Rate = 8,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-300, 300),
	},
	snow = { -- frost flakes drifting down
		Texture = SMOKE_TEXTURE,
		Color = colours({ "#FFFFFF" }),
		Size = sequence({ { 0, 0.18 }, { 1, 0.12 } }),
		Transparency = sequence({ { 0, 0.1 }, { 0.8, 0.2 }, { 1, 1 } }),
		Speed = NumberRange.new(0.5, 1.2),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, -1.5, 0),
		Lifetime = NumberRange.new(1.2, 2),
		Rate = 7,
	},
	dust = { -- sand puffs
		Texture = SMOKE_TEXTURE,
		Color = colours({ "#E8D3A6" }),
		Size = sequence({ { 0, 0.4 }, { 1, 1.1 } }),
		Transparency = sequence({ { 0, 0.55 }, { 1, 1 } }),
		Speed = NumberRange.new(0.3, 0.8),
		SpreadAngle = Vector2.new(180, 180),
		Lifetime = NumberRange.new(1, 1.6),
		Rate = 3,
	},
	embers = { -- glowing sparks rising
		Texture = SPARKLE_TEXTURE,
		Color = colours({ "#FFD27A", "#FF6A1F", "#C8301A" }),
		LightEmission = 1,
		Size = sequence({ { 0, 0.25 }, { 1, 0 } }),
		Speed = NumberRange.new(1, 2.5),
		SpreadAngle = Vector2.new(40, 40),
		EmissionDirection = Enum.NormalId.Top,
		Acceleration = Vector3.new(0, 2, 0),
		Lifetime = NumberRange.new(0.8, 1.4),
		Rate = 10,
	},
	motes = { -- pale moonlight motes hanging in the air
		Texture = SPARKLE_TEXTURE,
		Color = colours({ "#DCE4FF", "#9DB6FF" }),
		LightEmission = 1,
		Size = sequence({ { 0, 0 }, { 0.3, 0.3 }, { 1, 0 } }),
		Speed = NumberRange.new(0.3, 0.8),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 1,
		Lifetime = NumberRange.new(1.5, 2.5),
		Rate = 5,
	},
	bubbles = { -- pearly bubbles rising
		Texture = SMOKE_TEXTURE,
		Color = colours({ "#E8FFFF", "#BFF4FF" }),
		LightEmission = 0.3,
		Size = sequence({ { 0, 0.15 }, { 1, 0.3 } }),
		Transparency = sequence({ { 0, 0.3 }, { 0.8, 0.4 }, { 1, 1 } }),
		Speed = NumberRange.new(0.5, 1),
		SpreadAngle = Vector2.new(30, 30),
		EmissionDirection = Enum.NormalId.Top,
		Acceleration = Vector3.new(0, 1.2, 0),
		Lifetime = NumberRange.new(1.2, 2),
		Rate = 5,
	},
	leaves = { -- autumn leaves tumbling down
		Texture = SPARKLE_TEXTURE,
		Color = colours({ "#E8762E", "#F2B33A", "#C2452A" }),
		Size = sequence({ { 0, 0.3 }, { 1, 0.26 } }),
		Speed = NumberRange.new(0.5, 1.5),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0.6, -2.5, 0.3),
		Lifetime = NumberRange.new(1.2, 1.8),
		Rate = 4,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-150, 150),
	},
	sparks = { -- quick electric zaps
		Texture = SPARKLE_TEXTURE,
		Color = colours({ "#FFFFFF", "#7FDBFF" }),
		LightEmission = 1,
		Size = sequence({ { 0, 0.35 }, { 1, 0 } }),
		Speed = NumberRange.new(5, 9),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 4,
		Lifetime = NumberRange.new(0.15, 0.3),
		Rate = 18,
	},
	stars = { -- twinkling stars
		Texture = SPARKLE_TEXTURE,
		Color = colours({ "#FFFFFF", "#B9A6FF", "#7FDBFF", "#FF9AE0" }),
		LightEmission = 1,
		Size = sequence({ { 0, 0 }, { 0.5, 0.4 }, { 1, 0 } }),
		Speed = NumberRange.new(0.3, 1),
		SpreadAngle = Vector2.new(180, 180),
		Lifetime = NumberRange.new(1, 2),
		Rate = 8,
		RotSpeed = NumberRange.new(-60, 60),
	},
	ooze = { -- toxic green bubbles rising
		Texture = SMOKE_TEXTURE,
		Color = colours({ "#9BFF6B", "#4DFF7A" }),
		LightEmission = 0.6,
		Size = sequence({ { 0, 0.15 }, { 1, 0.3 } }),
		Transparency = sequence({ { 0, 0.2 }, { 0.8, 0.35 }, { 1, 1 } }),
		Speed = NumberRange.new(0.6, 1.2),
		SpreadAngle = Vector2.new(30, 30),
		EmissionDirection = Enum.NormalId.Top,
		Acceleration = Vector3.new(0, 1.5, 0),
		Lifetime = NumberRange.new(1, 1.6),
		Rate = 6,
	},
	petals = { -- cherry blossom petals fluttering down
		Texture = SPARKLE_TEXTURE,
		Color = colours({ "#FFB7D0", "#FFFFFF" }),
		Size = sequence({ { 0, 0.28 }, { 1, 0.22 } }),
		Speed = NumberRange.new(0.5, 1.4),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0.5, -1.8, 0.3),
		Lifetime = NumberRange.new(1.4, 2),
		Rate = 5,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-160, 160),
	},
	glitter = { -- silver moon dust glinting
		Texture = SPARKLE_TEXTURE,
		Color = colours({ "#FFFFFF", "#D8DCE8" }),
		LightEmission = 0.8,
		Size = sequence({ { 0, 0 }, { 0.4, 0.26 }, { 1, 0 } }),
		Speed = NumberRange.new(0.2, 0.6),
		SpreadAngle = Vector2.new(180, 180),
		Lifetime = NumberRange.new(0.8, 1.4),
		Rate = 9,
	},
	pollen = { -- golden-green pollen drifting up
		Texture = SPARKLE_TEXTURE,
		Color = colours({ "#E8F27A", "#B8E05A" }),
		LightEmission = 0.4,
		Size = sequence({ { 0, 0.18 }, { 1, 0.1 } }),
		Speed = NumberRange.new(0.3, 0.8),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0.3, 0.6, 0.2),
		Drag = 0.6,
		Lifetime = NumberRange.new(1.4, 2.2),
		Rate = 6,
	},
	glitch = { -- pink and cyan pixels flickering off
		Texture = SPARKLE_TEXTURE,
		Color = colours({ "#FF2EA8", "#2EF0FF" }),
		LightEmission = 1,
		Size = sequence({ { 0, 0.3 }, { 0.5, 0.3 }, { 0.51, 0 }, { 0.7, 0 }, { 0.71, 0.3 }, { 1, 0 } }),
		Speed = NumberRange.new(1.5, 3),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 3,
		Lifetime = NumberRange.new(0.3, 0.6),
		Rate = 12,
	},
	feathers = { -- white feathers floating down
		Texture = SPARKLE_TEXTURE,
		Color = colours({ "#FFFFFF", "#FFF4C8" }),
		LightEmission = 0.2,
		Size = sequence({ { 0, 0.32 }, { 1, 0.26 } }),
		Speed = NumberRange.new(0.4, 1),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0.3, -1.2, 0.2),
		Drag = 0.5,
		Lifetime = NumberRange.new(1.6, 2.4),
		Rate = 4,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-90, 90),
	},
	biolume = { -- deep-sea glowing dots
		Texture = SPARKLE_TEXTURE,
		Color = colours({ "#2EF0E0", "#7CB8FF" }),
		LightEmission = 1,
		Size = sequence({ { 0, 0 }, { 0.3, 0.24 }, { 0.7, 0.24 }, { 1, 0 } }),
		Speed = NumberRange.new(0.2, 0.6),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 1,
		Lifetime = NumberRange.new(1.4, 2.2),
		Rate = 7,
	},
	chocolate = { -- melted chocolate dripping off
		Texture = SPARKLE_TEXTURE,
		Color = colours({ "#7A4426", "#4A2614" }),
		LightEmission = 0.05,
		Size = sequence({ { 0, 0.26 }, { 1, 0.18 } }),
		Speed = NumberRange.new(0.2, 0.6),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, -9, 0),
		Lifetime = NumberRange.new(0.6, 1),
		Rate = 5,
	},
	confetti = { -- carnival confetti bursting up and fluttering down
		Texture = SPARKLE_TEXTURE,
		Color = colours({ "#FF5C8A", "#FFD23F", "#4DA8FF", "#3DDC84", "#B678FF" }),
		LightEmission = 0.3,
		Size = sequence({ { 0, 0.26 }, { 1, 0.22 } }),
		Speed = NumberRange.new(2.5, 4.5),
		SpreadAngle = Vector2.new(50, 50),
		EmissionDirection = Enum.NormalId.Top,
		Acceleration = Vector3.new(0, -7, 0),
		Drag = 1,
		Lifetime = NumberRange.new(1, 1.6),
		Rate = 7,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-320, 320),
	},
	cheese = { -- stretchy melted cheese dripping
		Texture = SPARKLE_TEXTURE,
		Color = colours({ "#FFE38A", "#FFC83D" }),
		LightEmission = 0.15,
		Size = sequence({ { 0, 0.2 }, { 0.5, 0.26 }, { 1, 0.16 } }),
		Speed = NumberRange.new(0.1, 0.4),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, -5, 0),
		Drag = 1.2,
		Lifetime = NumberRange.new(0.9, 1.4),
		Rate = 5,
	},
	festive = { -- red, green and gold fairy lights twinkling on and off
		Texture = SPARKLE_TEXTURE,
		Color = colours({ "#FF3B3B", "#FF3B3B", "#2EE66B", "#2EE66B", "#FFD23F", "#FFD23F" }),
		LightEmission = 1,
		Size = sequence({ { 0, 0 }, { 0.15, 0.3 }, { 0.4, 0.3 }, { 0.55, 0.05 }, { 0.7, 0.3 }, { 1, 0 } }),
		Speed = NumberRange.new(0.2, 0.7),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 1.5,
		Lifetime = NumberRange.new(1.2, 2),
		Rate = 9,
	},
}

-- The halo: a ring of glowing segments floating above the head (MutationLook.halo).
local HALO_SEGMENTS = 8
local HALO_COLOR = "#FFE066"

-- Whether `name` is a particle preset this module can build (MutationLook.particles).
function CreatureVisuals.hasParticles(name: string): boolean
	return MUTATION_PARTICLES[name] ~= nil
end

-- Colour of a rainbow part at clock time `t`; `offset` (0..1) staggers the parts of one model.
function CreatureVisuals.rainbowColor(offset: number, t: number): Color3
	return Color3.fromHSV((offset + t * RAINBOW_SPEED) % 1, 0.7, 1)
end

local function newPart(className: "Part" | "WedgePart", props: { [string]: any }): BasePart
	local part = Instance.new(className) :: BasePart
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		(part :: any)[key] = value
	end
	return part
end

local function disc(diameter: number, thickness: number, color: Color3, cframe: CFrame): BasePart
	-- Cylinders run along X; rotate so the flat face points up.
	return newPart("Part", {
		Size = Vector3.new(thickness, diameter, diameter),
		Color = color,
		CFrame = cframe * CFrame.Angles(0, 0, math.rad(90)),
		Shape = Enum.PartType.Cylinder,
	})
end

local function materialNamed(name: string): Enum.Material?
	local ok, item = pcall(function(): Enum.Material
		return (Enum.Material :: any)[name]
	end)
	return if ok then item else nil
end

-- One part from a compiled recipe spec.
local function makePart(spec: CreatureRecipe.PartSpec): BasePart
	local size = Vector3.new(spec.size[1], spec.size[2], spec.size[3])
	local c = spec.cf
	local cframe = CFrame.new(c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12])
	local part: BasePart
	if spec.shape == "Wedge" then
		part = newPart("WedgePart", { Size = size, CFrame = cframe })
	elseif spec.shape == "Ball" then
		part = newPart("Part", { Shape = Enum.PartType.Ball, Size = size, CFrame = cframe })
	elseif spec.shape == "Cylinder" then
		part = newPart("Part", { Shape = Enum.PartType.Cylinder, Size = size, CFrame = cframe })
	else
		part = newPart("Part", { Size = size, CFrame = cframe })
		if spec.shape == "Ellipsoid" then
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = part
		end
	end
	part.Name = spec.name
	part.Color = UiTheme.color(spec.color)
	if spec.material then
		part.Material = materialNamed(spec.material) or Enum.Material.SmoothPlastic
	end
	if spec.transparency then
		part.Transparency = spec.transparency
	end
	part.CastShadow = spec.shadow == true
	if spec.role == "face" then
		part:SetAttribute("MutationSkip", true)
	end
	if spec.squashAxis then
		part:SetAttribute("SquashAxis", spec.squashAxis)
	end
	return part
end

-- A compiled model (an imported model's or a recipe's parts), standing on y = 0 and facing -Z.
local function buildCompiled(compiled: CreatureRecipe.Compiled): Model
	local model = Instance.new("Model")
	local base = math.max(compiled.base, 0.5)
	local root = newPart("Part", {
		Name = "Root",
		Size = Vector3.new(base, 0.2, base),
		CFrame = CFrame.new(0, 0.1, 0),
		Transparency = 1,
	})
	root.Parent = model
	model.PrimaryPart = root
	for _, spec in compiled.parts do
		makePart(spec).Parent = model
	end
	return model
end

local function findCustomModel(modelName: string): Model?
	local folder = ReplicatedStorage:FindFirstChild("CreatureModels")
	if folder == nil then
		return nil
	end
	local found = folder:FindFirstChild(modelName)
	if found ~= nil and found:IsA("Model") then
		return found
	end
	return nil
end

-- Normalises a cloned custom model: makes sure there is a "Root" PrimaryPart at its feet.
local function prepareCustom(source: Model): Model
	local model = source:Clone()
	if model.PrimaryPart == nil or model.PrimaryPart.Name ~= "Root" then
		local cf, size = model:GetBoundingBox()
		local root = newPart("Part", {
			Name = "Root",
			Size = Vector3.new(size.X, 0.2, size.Z),
			CFrame = CFrame.new(cf.Position.X, cf.Position.Y - size.Y / 2 + 0.1, cf.Position.Z),
			Transparency = 1,
		})
		root.Parent = model
		model.PrimaryPart = root
	end
	return model
end

local function addRarityFlair(model: Model, rarity: Types.RarityDef)
	local body = model:FindFirstChild("Body") or model.PrimaryPart
	if body == nil or not body:IsA("BasePart") then
		return
	end
	local color = UiTheme.color(rarity.color)
	if rarity.glow then
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = 6 + rarity.order * 1.5
		light.Brightness = 1.2 + rarity.order * 0.15
		light.Shadows = false
		light.Parent = body
	end
	if rarity.particles then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Texture = SPARKLE_TEXTURE
		emitter.Rate = PARTICLE_RATE[rarity.order] or 6
		emitter.Lifetime = NumberRange.new(0.8, 1.6)
		emitter.Speed = NumberRange.new(1, 3)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.LightEmission = 1
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(1, 0),
		})
		if rarity.order >= 7 then
			emitter.Color = rainbowSequence()
		else
			emitter.Color = ColorSequence.new(color)
		end
		emitter.Parent = body
	end
	if rarity.order >= 6 then
		local root = model.PrimaryPart
		if root then
			local aura = disc(
				math.max(root.Size.X, root.Size.Z) * 1.5,
				0.1,
				color,
				CFrame.new(root.Position.X, root.Position.Y - 0.05, root.Position.Z)
			)
			aura.Name = "Aura"
			aura.Material = Enum.Material.Neon
			aura.Transparency = 0.35
			aura.Parent = model
		end
	end
end

-- The mutation look, on top of the rarity flair (see the header for which parts keep their own look).
local function addMutationLook(model: Model, mutation: Types.MutationDef)
	local look = mutation.look
	local material = materialNamed(look.material)
	local tint = if look.tint then UiTheme.color(look.tint) else nil
	local strength = math.clamp(look.tintStrength or 1, 0, 1)
	local count = 0
	for _, descendant in model:GetDescendants() do
		if
			not descendant:IsA("BasePart")
			or MUTATION_SKIP[descendant.Name]
			or descendant.Transparency >= 1
			or descendant:GetAttribute("MutationSkip") == true
		then
			continue
		end
		count += 1
		if material then
			descendant.Material = material
		end
		if tint then
			descendant.Color = descendant.Color:Lerp(tint, strength)
		end
		if look.transparency then
			descendant.Transparency = math.max(descendant.Transparency, look.transparency)
		end
		if look.reflectance then
			descendant.Reflectance = look.reflectance
		end
		if look.rainbow then
			local offset = (count * 0.13) % 1
			descendant:SetAttribute("HueOffset", offset)
			descendant.Color = CreatureVisuals.rainbowColor(offset, 0)
			CollectionService:AddTag(descendant, CreatureVisuals.RAINBOW_TAG)
		end
	end

	local body = model:FindFirstChild("Body") or model.PrimaryPart
	if (look.sparkles or look.rainbow) and body ~= nil and body:IsA("BasePart") then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "MutationSparkles"
		emitter.Texture = SPARKLE_TEXTURE
		emitter.Rate = MUTATION_PARTICLE_RATE
		emitter.Lifetime = NumberRange.new(0.6, 1.4)
		emitter.Speed = NumberRange.new(0.5, 2)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.LightEmission = 1
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.45),
			NumberSequenceKeypoint.new(1, 0),
		})
		emitter.Color = if look.rainbow then rainbowSequence() else ColorSequence.new(UiTheme.color(mutation.color))
		emitter.Parent = body
	end
	local preset = if look.particles then MUTATION_PARTICLES[look.particles] else nil
	if preset and body ~= nil and body:IsA("BasePart") then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "MutationParticles"
		for key, value in preset do
			(emitter :: any)[key] = value
		end
		emitter.Parent = body
	end
	local root = model.PrimaryPart
	if look.halo and root ~= nil then
		-- Above the model's top, sized to its width: a ring of short neon segments.
		local cf, size = model:GetBoundingBox()
		local radius = math.clamp(math.min(size.X, size.Z) * 0.28, 0.45, 1.6)
		local centre = Vector3.new(root.Position.X, cf.Position.Y + size.Y / 2 + radius * 0.6, root.Position.Z)
		local length = 2 * math.pi * radius / HALO_SEGMENTS * 1.08
		for index = 1, HALO_SEGMENTS do
			local angle = (index - 1) / HALO_SEGMENTS * math.pi * 2
			local segment = newPart("Part", {
				Name = "Halo",
				Size = Vector3.new(length, radius * 0.16 + 0.05, radius * 0.16 + 0.05),
				CFrame = CFrame.new(centre) * CFrame.Angles(0, -angle, 0) * CFrame.new(0, 0, -radius),
				Color = UiTheme.color(HALO_COLOR),
				Material = Enum.Material.Neon,
			})
			segment:SetAttribute("MutationSkip", true)
			segment.Parent = model
		end
	end
	if look.glow and body ~= nil and body:IsA("BasePart") then
		local light = Instance.new("PointLight")
		light.Name = "MutationGlow"
		light.Color = UiTheme.color(look.glow)
		light.Range = 10
		light.Brightness = 1.6
		light.Shadows = false
		light.Parent = body
	end
	model:SetAttribute("Variant", mutation.id)
end

local function weldAndConfigure(model: Model, anchored: boolean)
	local root = model.PrimaryPart :: BasePart
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
			descendant.Anchored = false
			if descendant ~= root then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = root
				weld.Part1 = descendant
				weld.Parent = descendant
			end
		end
	end
	root.Anchored = anchored
end

-- `mutation`: the creature's mutation (GameData.mutation(record.variant)); nil builds the plain look.
-- `idle`: anchored models get the client idle animation unless this is false (the belt animates its own models).
export type BuildOptions = { anchored: boolean, mutation: Types.MutationDef?, idle: boolean? }

-- Builds a ready-to-place model for a creature. Pivot it with model:PivotTo(cframeAtFeet).
function CreatureVisuals.build(def: Types.CreatureDef, rarity: Types.RarityDef, options: BuildOptions): Model
	local custom = findCustomModel(def.modelName)
	local model: Model
	if custom then
		model = prepareCustom(custom)
		if rarity.modelScale ~= 1 then
			model:ScaleTo(rarity.modelScale)
		end
	elseif CreatureParts[def.id] then
		model = buildCompiled(CreatureRecipe.compileImported(CreatureParts[def.id], rarity.modelScale))
	else
		model = buildCompiled(CreatureRecipe.compile(CreatureLooks[def.id] or FALLBACK_LOOK, rarity.modelScale))
	end
	model.Name = def.id
	model:SetAttribute("CreatureId", def.id)
	addRarityFlair(model, rarity)
	if options.mutation then
		addMutationLook(model, options.mutation)
	end
	weldAndConfigure(model, options.anchored)
	if options.anchored and options.idle ~= false then
		CollectionService:AddTag(model, CreatureVisuals.IDLE_TAG)
	end
	return model
end

-- Height of a model above its pivot (for placing billboards).
function CreatureVisuals.height(model: Model): number
	local _, size = model:GetBoundingBox()
	return size.Y
end

-- The parts of a model the idle animation squashes, with their resting size and local up axis (1..3).
export type SquashPart = { part: BasePart, size: Vector3, axis: number }

function CreatureVisuals.squashParts(model: Model): { SquashPart }
	local list: { SquashPart } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			local axis = descendant:GetAttribute("SquashAxis")
			if type(axis) == "number" and axis >= 1 and axis <= 3 then
				table.insert(list, { part = descendant, size = descendant.Size, axis = axis })
			end
		end
	end
	return list
end

-- Squash (amount < 0) or stretch (amount > 0) those parts around their own centres, keeping their volume roughly.
function CreatureVisuals.applySquash(parts: { SquashPart }, amount: number)
	local up = 1 + amount
	local side = 1 - amount * 0.5
	for _, entry in parts do
		local s = entry.size
		entry.part.Size = Vector3.new(
			s.X * (if entry.axis == 1 then up else side),
			s.Y * (if entry.axis == 2 then up else side),
			s.Z * (if entry.axis == 3 then up else side)
		)
	end
end

return CreatureVisuals
