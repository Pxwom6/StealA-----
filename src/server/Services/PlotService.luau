--!strict
--[[
	Owns the 8 base plots: who owns which, and making the world match each owner's saved data.

	The save (`session.data.creatures`) is the single source of truth; `syncPodiums` makes podium models and
	replicated attributes match it. Clients read those attributes (CreatureId, Stored, Income, BeingStolen,
	OwnerUserId, LockedUntil, ...) to draw billboards and build their own interaction prompts.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Gameplay = require(ReplicatedStorage.Shared.Config.Gameplay)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local GameData = require(ReplicatedStorage.Shared.GameData)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local CreatureVisuals = require(ReplicatedStorage.Shared.CreatureVisuals)
local PlotAssignment = require(ReplicatedStorage.Shared.Logic.PlotAssignment)
local StealRules = require(ReplicatedStorage.Shared.Logic.StealRules)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local MapBuilder = require(script.Parent.MapBuilder)
local Sessions = require(script.Parent.Sessions)

type Session = Sessions.Session

type PlacedCreature = { uid: string, creatureId: string, model: Model }

export type ShieldMode = "None" | "Locked" | "Grace"

local PlotService = {}

local world: MapBuilder.World
local owners: PlotAssignment.Owners = {}
local placed: { [number]: { [number]: PlacedCreature } } = {}
local busy: { [number]: { [number]: boolean } } = {}

function PlotService.start(builtWorld: MapBuilder.World)
	world = builtWorld
	for index = 1, #world.plots do
		placed[index] = {}
		busy[index] = {}
		PlotService.applyShield(index, "None")
	end
end

function PlotService.world(): MapBuilder.World
	return world
end

function PlotService.refs(plot: number): MapBuilder.PlotRefs
	return world.plots[plot]
end

function PlotService.ownerOf(plot: number): number
	return owners[plot] or 0
end

function PlotService.rect(plot: number): StealRules.Rect
	return world.plots[plot].rect
end

function PlotService.isInside(plot: number, position: Vector3): boolean
	return StealRules.isInsideRect(position.X, position.Z, world.plots[plot].rect)
end

-- Plot index containing `position`, or nil when outside every plot.
function PlotService.plotAt(position: Vector3): number?
	for index, refs in world.plots do
		if StealRules.isInsideRect(position.X, position.Z, refs.rect) then
			return index
		end
	end
	return nil
end

function PlotService.podium(plot: number, podium: number): MapBuilder.PodiumRefs?
	local refs = world.plots[plot]
	return if refs then refs.podiums[podium] else nil
end

function PlotService.assign(session: Session): number?
	local plot = PlotAssignment.claim(owners, #world.plots, session.userId)
	if plot == nil then
		return nil
	end
	session.plot = plot
	local refs = world.plots[plot]
	refs.model:SetAttribute("OwnerUserId", session.userId)
	refs.model:SetAttribute("OwnerName", session.player.DisplayName)
	refs.signLabel.Text = Format.template(Theme.text.ownerSign, { name = session.player.DisplayName })
	return plot
end

function PlotService.release(session: Session)
	local plot = session.plot
	if plot == 0 then
		return
	end
	PlotAssignment.release(owners, session.userId)
	local refs = world.plots[plot]
	for podiumIndex, entry in placed[plot] do
		entry.model:Destroy()
		placed[plot][podiumIndex] = nil
	end
	table.clear(busy[plot])
	for _, podium in refs.podiums do
		podium.model:SetAttribute("Active", false)
		podium.model:SetAttribute("CreatureId", "")
		podium.model:SetAttribute("Uid", "")
		podium.model:SetAttribute("Stored", 0)
		podium.model:SetAttribute("Income", 0)
		podium.model:SetAttribute("BeingStolen", false)
		podium.base.Color = UiTheme.world("lockedPodium")
		podium.base.Transparency = 0.6
		podium.pad.Transparency = 1
	end
	refs.model:SetAttribute("OwnerUserId", 0)
	refs.model:SetAttribute("OwnerName", "")
	refs.model:SetAttribute("LockedUntil", 0)
	refs.model:SetAttribute("GraceUntil", 0)
	refs.model:SetAttribute("Capacity", 0)
	refs.model:SetAttribute("NextPodiumCost", -1)
	refs.signLabel.Text = Theme.text.freePlotSign
	refs.signIncome.Text = ""
	PlotService.setVipTrim(plot, false)
	PlotService.applyShield(plot, "None")
	session.plot = 0
end

-- Makes podium visuals + attributes match the session's saved creatures, capacity and income multiplier.
function PlotService.syncPodiums(session: Session)
	local plot = session.plot
	if plot == 0 then
		return
	end
	local refs = world.plots[plot]
	local byPodium: { [number]: typeof(session.data.creatures[1]) } = {}
	for _, record in session.data.creatures do
		byPodium[record.podium] = record
	end

	for _, podium in refs.podiums do
		local i = podium.index
		local active = i <= session.capacity
		podium.model:SetAttribute("Active", active)
		podium.base.Color = if active then UiTheme.world("podium") else UiTheme.world("lockedPodium")
		podium.base.Transparency = if active then 0 else 0.6
		podium.pad.Transparency = if active then 0.15 else 1

		local record = byPodium[i]
		local current = placed[plot][i]
		local isBusy = busy[plot][i] == true
		if record == nil or isBusy then
			if current then
				current.model:Destroy()
				placed[plot][i] = nil
			end
		elseif current == nil or current.uid ~= record.uid then
			if current then
				current.model:Destroy()
			end
			local def = GameData.catalog.creatures[record.id]
			local rarity = GameData.catalog.rarities[def.rarity]
			local model = CreatureVisuals.build(def, rarity, { anchored = true })
			model:PivotTo(podium.standCFrame)
			model.Parent = podium.model
			placed[plot][i] = { uid = record.uid, creatureId = record.id, model = model }
		end

		if record then
			local def = GameData.catalog.creatures[record.id]
			podium.model:SetAttribute("CreatureId", record.id)
			podium.model:SetAttribute("Uid", record.uid)
			podium.model:SetAttribute("Income", def.income * session.multiplier)
			podium.model:SetAttribute("Stored", math.floor(record.stored))
		else
			podium.model:SetAttribute("CreatureId", "")
			podium.model:SetAttribute("Uid", "")
			podium.model:SetAttribute("Income", 0)
			podium.model:SetAttribute("Stored", 0)
		end
		podium.model:SetAttribute("BeingStolen", isBusy)
	end

	refs.model:SetAttribute("Capacity", session.capacity)
	refs.signIncome.Text = UiTheme.perSecond(session.incomePerSecond)
	PlotService.setVipTrim(plot, session.passes.VIP)
end

function PlotService.setStored(plot: number, podium: number, stored: number)
	local refs = world.plots[plot]
	local podiumRefs = refs and refs.podiums[podium]
	if podiumRefs then
		local value = math.floor(stored)
		if podiumRefs.model:GetAttribute("Stored") ~= value then
			podiumRefs.model:SetAttribute("Stored", value)
		end
	end
end

-- Marks a podium's creature as being carried away (hides it, shows "being stolen" on clients).
function PlotService.setBusy(plot: number, podium: number, isBusy: boolean)
	busy[plot][podium] = isBusy
end

function PlotService.isBusy(plot: number, podium: number): boolean
	return busy[plot][podium] == true
end

function PlotService.setNextPodiumCost(plot: number, cost: number?)
	world.plots[plot].model:SetAttribute("NextPodiumCost", cost or -1)
end

function PlotService.setVipTrim(plot: number, isVip: boolean)
	for _, trim in world.plots[plot].trims do
		trim.Color = if isVip then UiTheme.world("vipTrim") else UiTheme.world("wall")
		trim.Material = if isVip then Enum.Material.Neon else Enum.Material.SmoothPlastic
	end
end

-- Shows the force field for a lock (blue) or new-player protection (yellow), or hides it.
function PlotService.applyShield(plot: number, mode: ShieldMode)
	local refs = world.plots[plot]
	if mode == "None" then
		refs.dome.Transparency = 1
		refs.barrier.Transparency = 1
		refs.barrier.CanCollide = false
		return
	end
	local color = if mode == "Locked" then UiTheme.world("lockField") else UiTheme.world("graceField")
	refs.dome.Color = color
	refs.dome.Transparency = 0.55
	refs.barrier.Color = color
	refs.barrier.Transparency = 0.25
	refs.barrier.CanCollide = true
end

function PlotService.setShieldTimes(plot: number, lockedUntil: number, graceUntil: number)
	local model = world.plots[plot].model
	model:SetAttribute("LockedUntil", lockedUntil)
	model:SetAttribute("GraceUntil", graceUntil)
end

function PlotService.maxPodiums(): number
	return Gameplay.map.maxPodiums
end

return PlotService
