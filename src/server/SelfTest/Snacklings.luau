--!strict
--[[
	Self-test section Snacklings: builds every Snackling plain, then one (the first in the catalogue, as the world smoke
	test does) in every mutation, with CreatureVisuals.build as /gallery does, in batches high above the north edge of
	the map. A moment later (so a part that is not welded has fallen), each is measured in the real engine: it built
	without an error, stands on its feet (its lowest visible part, the halo, wings or ring of fire a mutation adds left
	out, within FLOAT studs of where its feet go), fits a
	podium (Logic/CreatureRecipe.PODIUM_FIT: as wide as the gap between podiums, as tall as the space under the
	billboard) and, plain, stays inside its rarity's part budget; a mutated one carries its look (the Variant attribute
	and its particle preset). Every model is destroyed straight after it is measured.

	Sizes are measured like Logic/CreatureRecipe.compileImported's own (each part by its real shape: an ellipsoid or a
	cylinder exactly, a wedge by its corners, a box by its box), leaving out the Root and the rarity's aura ring, so a
	number here can be compared with the CI check's.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Mutations = require(ReplicatedStorage.Shared.Config.Mutations)
local Scenery = require(ReplicatedStorage.Shared.Config.Scenery)
local CreatureVisuals = require(ReplicatedStorage.Shared.CreatureVisuals)
local GameData = require(ReplicatedStorage.Shared.GameData)
local Types = require(ReplicatedStorage.Shared.Types)
local CreatureRecipe = require(ReplicatedStorage.Shared.Logic.CreatureRecipe)
local Kit = require(script.Parent.Kit)

local FLOAT = 0.2 -- studs between the lowest visible part and the feet that still count as standing
local FIT_SLACK = 0.05 -- studs over the podium fit allowed for rounding
local HEIGHT = 300 -- studs above the ground where the test models are built
local SPACING = 12 -- studs between test models

type Job = { def: Types.CreatureDef, mutation: Types.MutationDef?, label: string }
type Measure = { lowest: number, height: number, width: number }

-- What a mutation's look adds round the model (CreatureVisuals): a halo above it, wings on its back, an eclipse's ring
-- of fire behind it (which reaches below the feet by design). Left out of where it stands, not of its size.
local LOOK_PARTS: { [string]: boolean } = { Halo = true, Wing = true, Corona = true }

-- A wedge's corners in its own space (half sizes): the bottom face and the top edge at the back (+Z).
local WEDGE_CORNERS = {
	Vector3.new(-1, -1, -1),
	Vector3.new(1, -1, -1),
	Vector3.new(-1, -1, 1),
	Vector3.new(1, -1, 1),
	Vector3.new(-1, 1, 1),
	Vector3.new(1, 1, 1),
}

local function isEllipsoid(part: BasePart): boolean
	local mesh = part:FindFirstChildOfClass("SpecialMesh")
	return mesh ~= nil and mesh.MeshType == Enum.MeshType.Sphere
end

-- How far `part` reaches from its centre along world X and Y (low and high), by its real shape, as
-- CreatureRecipe's import measures it.
local function reach(part: BasePart): (number, number, number, number)
	local size = part.Size
	local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2
	local _, _, _, r00, r01, r02, r10, r11, r12 = part.CFrame:GetComponents()
	if part:IsA("WedgePart") then
		local lowX, highX, lowY, highY = math.huge, -math.huge, math.huge, -math.huge
		for _, corner in WEDGE_CORNERS do
			local x = r00 * corner.X * hx + r01 * corner.Y * hy + r02 * corner.Z * hz
			local y = r10 * corner.X * hx + r11 * corner.Y * hy + r12 * corner.Z * hz
			lowX, highX = math.min(lowX, x), math.max(highX, x)
			lowY, highY = math.min(lowY, y), math.max(highY, y)
		end
		return lowX, highX, lowY, highY
	end
	local shape = if part:IsA("Part") then part.Shape else nil
	local ex, ey
	if shape == Enum.PartType.Ball then
		ex, ey = hx, hx
	elseif shape == Enum.PartType.Cylinder then
		-- along its X, round in Y and Z
		local radius = math.min(hy, hz)
		ex = math.abs(r00) * hx + radius * math.sqrt(math.max(0, 1 - r00 * r00))
		ey = math.abs(r10) * hx + radius * math.sqrt(math.max(0, 1 - r10 * r10))
	elseif isEllipsoid(part) then
		ex = math.sqrt((r00 * hx) ^ 2 + (r01 * hy) ^ 2 + (r02 * hz) ^ 2)
		ey = math.sqrt((r10 * hx) ^ 2 + (r11 * hy) ^ 2 + (r12 * hz) ^ 2)
	else
		ex = math.abs(r00) * hx + math.abs(r01) * hy + math.abs(r02) * hz
		ey = math.abs(r10) * hx + math.abs(r11) * hy + math.abs(r12) * hz
	end
	return -ex, ex, -ey, ey
end

-- The model's extents from its feet: lowest and highest point, and width side to side.
local function measure(model: Model): Measure?
	local root = model.PrimaryPart
	if root == nil then
		return nil
	end
	local feetY = root.Position.Y - root.Size.Y / 2
	local centreX = root.Position.X
	local lowest, highest, wide = math.huge, -math.huge, 0
	for _, part in model:GetDescendants() do
		if not part:IsA("BasePart") or part == root or part.Name == "Aura" or part.Transparency >= 1 then
			continue
		end
		local position = part.Position
		local lowX, highX, lowY, highY = reach(part)
		if not LOOK_PARTS[part.Name] then
			lowest = math.min(lowest, position.Y + lowY)
		end
		highest = math.max(highest, position.Y + highY)
		wide = math.max(wide, math.abs(position.X - centreX + lowX), math.abs(position.X - centreX + highX))
	end
	if lowest > highest then
		return nil
	end
	return { lowest = lowest - feetY, height = highest - feetY, width = wide * 2 }
end

local function isCustom(def: Types.CreatureDef): boolean
	local folder = ReplicatedStorage:FindFirstChild("CreatureModels")
	return folder ~= nil and folder:FindFirstChild(def.modelName) ~= nil
end

-- What is wrong with `model`, built for `job`.
local function issuesOf(job: Job, model: Model): { string }
	local issues: { string } = {}
	local size = measure(model)
	if size == nil then
		return { "no visible parts, or no PrimaryPart" }
	end
	if size.lowest > FLOAT then
		table.insert(issues, string.format("floats %.2f studs above its feet", size.lowest))
	elseif size.lowest < -FLOAT then
		table.insert(issues, string.format("sinks %.2f studs below its feet", -size.lowest))
	end
	local fit = CreatureRecipe.PODIUM_FIT
	if size.width > fit.width + FIT_SLACK then
		table.insert(issues, string.format("%.2f studs wide (a podium fits %.1f)", size.width, fit.width))
	end
	if size.height > fit.height + FIT_SLACK then
		table.insert(issues, string.format("%.2f studs tall (a podium fits %.1f)", size.height, fit.height))
	end
	local mutation = job.mutation
	if mutation then
		if model:GetAttribute("Variant") ~= mutation.id then
			table.insert(issues, "the model is not marked with its mutation (Variant)")
		end
		local particles = mutation.look.particles
		if particles and model:FindFirstChild("MutationParticles", true) == nil then
			table.insert(issues, `its {particles} particles are missing`)
		end
	else
		local rarity = GameData.catalog.rarities[job.def.rarity]
		local budget = CreatureRecipe.budgetFor(rarity.order)
		local parts = Kit.countParts(model)
		if parts > budget and not isCustom(job.def) then
			table.insert(issues, `{parts} parts, over the {rarity.displayName} budget of {budget}`)
		end
	end
	return issues
end

local Section: Kit.Section = {
	name = "Snacklings",
	run = function(ctx: Kit.Context): string
		local jobs: { Job } = {}
		for _, def in GameData.catalog.creatureList do
			table.insert(jobs, { def = def, label = def.id })
		end
		local sample = GameData.catalog.creatureList[1]
		local mutated = 0
		if sample then
			for _, mutation in Mutations do
				table.insert(jobs, { def = sample, mutation = mutation, label = `{sample.id} {mutation.id}` })
				mutated += 1
			end
		end

		local folder = Instance.new("Folder")
		folder.Name = "SelfTestSnacklings"
		folder.Parent = workspace
		ctx.onCleanup(function()
			folder:Destroy()
		end)
		local z = Scenery.boundary.maxZ + 80
		local broken = 0
		local batchSize = math.max(1, math.floor(ctx.options.batch))
		for first = 1, #jobs, batchSize do
			local batch: { { job: Job, model: Model } } = {}
			for index = first, math.min(first + batchSize - 1, #jobs) do
				local job = jobs[index]
				local rarity = GameData.catalog.rarities[job.def.rarity]
				local ok, result = pcall(
					CreatureVisuals.build,
					job.def,
					rarity,
					{ anchored = true, mutation = job.mutation, idle = false }
				)
				if ok then
					local model = result :: Model
					local x = (index - first - batchSize / 2) * SPACING
					model:PivotTo(CFrame.new(x, HEIGHT + 0.1, z))
					model.Parent = folder
					table.insert(batch, { job = job, model = model })
				else
					broken += 1
					ctx.problem(`{job.label} failed to build: {Kit.short(tostring(result))}`)
				end
			end
			task.wait(0.25) -- a part left unwelded falls meanwhile
			for _, entry in batch do
				local issues = issuesOf(entry.job, entry.model)
				if #issues > 0 then
					broken += 1
				end
				for _, issue in issues do
					ctx.problem(`{entry.job.label}: {issue}`)
				end
				entry.model:Destroy()
			end
		end
		folder:Destroy()
		local plain = #jobs - mutated
		if broken > 0 then
			return `{broken} of {#jobs} models have problems`
		end
		return `{plain} Snacklings and {mutated} mutations built, on their feet and podium-sized`
	end,
}

return Section
