--!strict
--[[
	Builds the 3D model for a Snackling.

	If ReplicatedStorage.CreatureModels contains a Model named exactly `def.modelName`, that model is cloned
	(drop your own art there; it should face -Z and stand on y = 0 with a PrimaryPart). Otherwise a chunky,
	toy-like placeholder is built from the `look` recipe in Config/Creatures.

	Every model returned has a PrimaryPart called "Root" at its feet, all other parts welded to it, and no
	collisions, so it can be anchored on a podium, moved along the belt, or welded above a thief's head.
	Rarity flair (glow, sparkles, aura ring) is added on top of either kind of model, then the mutation look (if
	any): material, tint, transparency, sparkles, rainbow, glow light. The face (Eye/Pupil/Mouth), the Root and the rarity Aura
	keep their look; in a custom model, give a part the attribute MutationSkip = true to keep its look too.
	Rainbow parts are tagged RAINBOW_TAG; the client cycles their hue (MutationFxController).
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require("./Types")
local UiTheme = require("./UiTheme")

local CreatureVisuals = {}

local PARTICLE_RATE: { [number]: number } = { [4] = 5, [5] = 9, [6] = 16, [7] = 26 }
local SPARKLE_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local MUTATION_PARTICLE_RATE = 8
-- Parts a mutation never restyles (the face stays readable; Root is invisible; Aura is the rarity ring).
local MUTATION_SKIP: { [string]: boolean } = { Root = true, Aura = true, Eye = true, Pupil = true, Mouth = true }
local RAINBOW_SPEED = 0.25 -- hue turns per second

CreatureVisuals.RAINBOW_TAG = "MutationRainbow"

local function rainbowSequence(): ColorSequence
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 90)),
		ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 230, 90)),
		ColorSequenceKeypoint.new(0.66, Color3.fromRGB(90, 255, 200)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(170, 110, 255)),
	})
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

local function ball(size: Vector3, color: Color3, cframe: CFrame): BasePart
	return newPart("Part", { Size = size, Color = color, CFrame = cframe, Shape = Enum.PartType.Ball })
end

local function block(size: Vector3, color: Color3, cframe: CFrame): BasePart
	return newPart("Part", { Size = size, Color = color, CFrame = cframe })
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

local function buildPlaceholder(look: Types.Look): Model
	local s = look.size
	local model = Instance.new("Model")
	local root = newPart("Part", {
		Name = "Root",
		Size = Vector3.new(s, 0.2, s),
		CFrame = CFrame.new(0, 0.1, 0),
		Transparency = 1,
	})
	root.Parent = model
	model.PrimaryPart = root

	local bodyColor = UiTheme.color(look.bodyColor)
	local accentColor = UiTheme.color(look.accentColor)
	local centerY = s * 0.5 + 0.2
	local topY = centerY + s * 0.45
	local center = CFrame.new(0, centerY, 0)

	local body: BasePart
	if look.body == "Ball" then
		body = ball(Vector3.new(s, s, s), bodyColor, center)
	elseif look.body == "Block" then
		body = block(Vector3.new(s, s * 0.85, s * 0.9), bodyColor, center)
		topY = centerY + s * 0.425
	elseif look.body == "Wedge" then
		body = newPart("WedgePart", {
			Size = Vector3.new(s, s * 0.9, s * 1.1),
			Color = bodyColor,
			-- slope faces the back so the face is on the tall, flat front
			CFrame = center * CFrame.Angles(0, math.rad(180), 0),
		})
	else
		body = newPart("Part", {
			Size = Vector3.new(s * 0.95, s, s),
			Color = bodyColor,
			CFrame = center * CFrame.Angles(0, 0, math.rad(90)),
			Shape = Enum.PartType.Cylinder,
		})
		topY = centerY + s * 0.475
	end
	body.Name = "Body"
	body.Parent = model

	-- Face (front is -Z)
	local faceZ = -s * 0.47
	local eyeY = centerY + s * 0.12
	for _, side in { -1, 1 } do
		local eye = ball(Vector3.one * s * 0.3, Color3.new(1, 1, 1), CFrame.new(side * s * 0.2, eyeY, faceZ))
		eye.Name = "Eye"
		eye.Parent = model
		local pupil =
			ball(Vector3.one * s * 0.15, Color3.fromRGB(25, 25, 35), CFrame.new(side * s * 0.2, eyeY, faceZ - s * 0.12))
		pupil.Name = "Pupil"
		pupil.Parent = model
	end
	local mouth = block(
		Vector3.new(s * 0.22, s * 0.06, s * 0.06),
		Color3.fromRGB(60, 25, 25),
		CFrame.new(0, centerY - s * 0.12, faceZ - 0.02)
	)
	mouth.Name = "Mouth"
	mouth.Parent = model

	local accentParts: { BasePart } = {}
	local accent = look.accent
	if accent == "Ears" then
		for _, side in { -1, 1 } do
			table.insert(
				accentParts,
				block(
					Vector3.new(s * 0.25, s * 0.35, s * 0.15),
					accentColor,
					CFrame.new(side * s * 0.28, topY + s * 0.1, 0) * CFrame.Angles(0, 0, math.rad(-side * 18))
				)
			)
		end
	elseif accent == "Spots" then
		for _, offset in { Vector3.new(-0.18, 0, -0.12), Vector3.new(0.2, 0, 0.05), Vector3.new(-0.02, 0, 0.22) } do
			table.insert(
				accentParts,
				disc(s * 0.24, 0.08, accentColor, CFrame.new(offset.X * s, topY - s * 0.02, offset.Z * s))
			)
		end
	elseif accent == "Shell" then
		table.insert(
			accentParts,
			ball(Vector3.new(s * 0.95, s * 0.55, s * 0.95), accentColor, CFrame.new(0, topY - s * 0.05, s * 0.12))
		)
	elseif accent == "Wings" then
		for _, side in { -1, 1 } do
			local wing = newPart("WedgePart", {
				Size = Vector3.new(0.15, s * 0.55, s * 0.65),
				Color = accentColor,
				CFrame = CFrame.new(side * s * 0.58, centerY + s * 0.15, s * 0.1)
					* CFrame.Angles(0, 0, math.rad(side * 25)),
			})
			table.insert(accentParts, wing)
		end
	elseif accent == "Horns" then
		for _, side in { -1, 1 } do
			local horn = newPart("WedgePart", {
				Size = Vector3.new(s * 0.12, s * 0.32, s * 0.18),
				Color = accentColor,
				CFrame = CFrame.new(side * s * 0.2, topY + s * 0.13, -s * 0.05),
			})
			table.insert(accentParts, horn)
		end
	elseif accent == "Crown" then
		table.insert(accentParts, disc(s * 0.55, 0.12, accentColor, CFrame.new(0, topY + 0.02, 0)))
		for i = 1, 5 do
			local angle = (i / 5) * math.pi * 2
			local spike = block(
				Vector3.new(s * 0.1, s * 0.2, s * 0.1),
				accentColor,
				CFrame.new(math.cos(angle) * s * 0.22, topY + s * 0.12, math.sin(angle) * s * 0.22)
			)
			spike.Material = Enum.Material.Neon
			table.insert(accentParts, spike)
		end
	else -- Sprinkles
		local sprinkleColors =
			{ accentColor, Color3.fromRGB(255, 120, 190), Color3.fromRGB(110, 200, 255), Color3.fromRGB(255, 225, 90) }
		for i = 1, 8 do
			local angle = i * 2.4
			local radius = s * (0.12 + (i % 3) * 0.08)
			table.insert(
				accentParts,
				block(
					Vector3.new(s * 0.07, s * 0.07, s * 0.2),
					sprinkleColors[(i % #sprinkleColors) + 1],
					CFrame.new(math.cos(angle) * radius, topY, math.sin(angle) * radius) * CFrame.Angles(0, angle, 0)
				)
			)
		end
	end
	for _, part in accentParts do
		part.Name = "Accent"
		part.Parent = model
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

local function materialNamed(name: string): Enum.Material?
	local ok, item = pcall(function(): Enum.Material
		return (Enum.Material :: any)[name]
	end)
	return if ok then item else nil
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
export type BuildOptions = { anchored: boolean, mutation: Types.MutationDef? }

-- Builds a ready-to-place model for a creature. Pivot it with model:PivotTo(cframeAtFeet).
function CreatureVisuals.build(def: Types.CreatureDef, rarity: Types.RarityDef, options: BuildOptions): Model
	local custom = findCustomModel(def.modelName)
	local model = if custom then prepareCustom(custom) else buildPlaceholder(def.look)
	model.Name = def.id
	model:SetAttribute("CreatureId", def.id)
	if rarity.modelScale ~= 1 then
		model:ScaleTo(rarity.modelScale)
	end
	addRarityFlair(model, rarity)
	if options.mutation then
		addMutationLook(model, options.mutation)
	end
	weldAndConfigure(model, options.anchored)
	return model
end

-- Height of a model above its pivot (for placing billboards).
function CreatureVisuals.height(model: Model): number
	local _, size = model:GetBoundingBox()
	return size.Y
end

return CreatureVisuals
