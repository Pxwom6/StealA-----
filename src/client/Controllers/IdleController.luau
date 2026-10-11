--!strict
--[[
	Makes Snacklings on podiums (and in the Studio /gallery) feel alive: a gentle bob, squash & stretch and sway
	(Logic/IdleMotion). Client-only and purely visual: it moves the anchored Root of models tagged
	CreatureVisuals.IDLE_TAG locally (welded parts follow); the server never sees it.

	Cheap on purpose:
	  * only models within ACTIVE_RANGE studs of the camera move (at most MAX_ACTIVE, nearest first), re-picked twice
	    a second
	  * poses update at ~30 Hz: one CFrame write per model plus a size write on its one or two body parts
	  * a model that leaves the range goes back exactly where the server put it
	Belt models aren't tagged: BeltController moves them every frame and folds the hop into that.
	Rainbow mutations keep working (MutationFxController only changes colours).
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CreatureVisuals = require(ReplicatedStorage.Shared.CreatureVisuals)
local ClientSettings = require(script.Parent.ClientSettings)
local IdleMotion = require(ReplicatedStorage.Shared.Logic.IdleMotion)

local IdleController = {}

local ACTIVE_RANGE = 120
local MAX_ACTIVE = 32 -- phones: ~35 parts each at 30 Hz
local STEP_SECONDS = 1 / 30
local PICK_SECONDS = 0.5

type Entry = {
	model: Model,
	root: BasePart,
	base: CFrame, -- where the server put the Root
	written: CFrame?, -- the last CFrame written here (anything else means the server moved it)
	height: number,
	phase: number,
	squash: { CreatureVisuals.SquashPart },
	active: boolean,
}

local entries: { [Model]: Entry } = {}
local activeList: { Entry } = {}
local random = Random.new()

local function rest(entry: Entry)
	if entry.written then
		entry.root.CFrame = entry.base
		entry.written = nil
	end
	CreatureVisuals.applySquash(entry.squash, 0)
end

local function track(model: Model)
	local root = model.PrimaryPart
	if entries[model] or root == nil or not root.Anchored or not model:IsDescendantOf(workspace) then
		return
	end
	entries[model] = {
		model = model,
		root = root,
		base = root.CFrame,
		written = nil,
		height = CreatureVisuals.height(model),
		phase = random:NextNumber(),
		squash = CreatureVisuals.squashParts(model),
		active = false,
	}
end

local function forget(instance: Instance)
	local entry = entries[instance :: Model]
	if entry then
		entries[instance :: Model] = nil
		entry.active = false
	end
end

-- True when the Root is no longer where this client last put it: the server moved or turned the model.
local function movedElsewhere(current: CFrame, written: CFrame): boolean
	return (current.Position - written.Position).Magnitude > 0.01 or current.LookVector:Dot(written.LookVector) < 0.9999
end

-- The server moved the model (or it was just placed): take its new position as the resting one.
local function syncBase(entry: Entry)
	local current = entry.root.CFrame
	local written = entry.written
	if written == nil or movedElsewhere(current, written) then
		entry.base = current
		entry.written = nil
	end
end

local function pick()
	-- Models whose parts arrived after their tag, or that moved into the workspace later.
	for _, instance in CollectionService:GetTagged(CreatureVisuals.IDLE_TAG) do
		if instance:IsA("Model") and entries[instance] == nil then
			track(instance)
		end
	end
	local camera = workspace.CurrentCamera
	if camera == nil then
		return
	end
	local eye = camera.CFrame.Position
	type Candidate = { entry: Entry, distance: number }
	local candidates: { Candidate } = {}
	for model, entry in entries do
		if model.Parent == nil or not entry.root:IsDescendantOf(workspace) then
			entries[model] = nil
			continue
		end
		syncBase(entry)
		local distance = (entry.base.Position - eye).Magnitude
		if distance <= ACTIVE_RANGE then
			table.insert(candidates, { entry = entry, distance = distance })
		end
	end
	table.sort(candidates, function(a: Candidate, b: Candidate): boolean
		return a.distance < b.distance
	end)
	local nextList: { Entry } = {}
	local chosen: { [Entry]: boolean } = {}
	for i = 1, math.min(#candidates, MAX_ACTIVE) do
		local entry = candidates[i].entry
		chosen[entry] = true
		table.insert(nextList, entry)
	end
	for _, entry in activeList do
		if not chosen[entry] and entries[entry.model] == entry then
			rest(entry)
		end
		entry.active = false
	end
	for _, entry in nextList do
		entry.active = true
	end
	activeList = nextList
end

local function animate()
	local t = os.clock()
	for _, entry in activeList do
		if not entry.active or entry.model.Parent == nil then
			continue
		end
		-- Checked every step (not only when re-picking): otherwise the next write would put a model the server just
		-- moved straight back where it was, on this client only.
		syncBase(entry)
		local pose = IdleMotion.podium(t, entry.phase, entry.height)
		local cframe = entry.base * CFrame.new(0, pose.lift, 0) * CFrame.Angles(0, pose.yaw, pose.roll)
		entry.root.CFrame = cframe
		entry.written = cframe
		CreatureVisuals.applySquash(entry.squash, pose.squash)
	end
end

function IdleController.start()
	for _, instance in CollectionService:GetTagged(CreatureVisuals.IDLE_TAG) do
		if instance:IsA("Model") then
			track(instance)
		end
	end
	CollectionService:GetInstanceAddedSignal(CreatureVisuals.IDLE_TAG):Connect(function(instance: Instance)
		if instance:IsA("Model") then
			-- wait a frame so the whole model (parts, PrimaryPart) has arrived
			task.defer(track, instance)
		end
	end)
	CollectionService:GetInstanceRemovedSignal(CreatureVisuals.IDLE_TAG):Connect(forget)

	local sinceStep, sincePick = 0, PICK_SECONDS
	RunService.Heartbeat:Connect(function(dt: number)
		-- Settings > Reduce effects: put every model back at rest and stop animating until it's switched off.
		if ClientSettings.reduceEffects() then
			if #activeList > 0 then
				for _, entry in activeList do
					rest(entry)
					entry.active = false
				end
				activeList = {}
			end
			sincePick = PICK_SECONDS
			return
		end
		sincePick += dt
		if sincePick >= PICK_SECONDS then
			sincePick = 0
			pick()
		end
		sinceStep += dt
		if sinceStep >= STEP_SECONDS then
			sinceStep %= STEP_SECONDS
			animate()
		end
	end)
end

return IdleController
