--!strict
--[[
	Server modifiers (Config/Modifiers): every few minutes a random twist runs for a while — a faster belt, a sale,
	more mutations, more luck, more income, faster running, quicker steals, longer locks, longer tags.

	This service only keeps the schedule and says what is running. The systems read the effects
	(ModifierService.effects(), resolved by Logic/ModifierRules) where they decide: BeltService (spawn interval, belt
	capacity, prices, mutation chances), EconomyService (income, with LiveOps cash events), LockService (lock length),
	StealService (hold time, tag reach, walking and carrying speed), PlayerLifecycle (a new character's speed) and
	PositionTracker (its walking budget). Services that cache a value re-read it when `onChanged` fires. Luck is added
	as a LiveOps boost (source "modifier"), so the HUD's luck pill shows it and the usual cap applies.

	Movement checks never trust a speed the client might not have yet: walkSpeedAllowance() is the larger of the
	current and the previous multiplier for a few seconds after every change.

	Weather modifiers (Thunderstorm, Meteor Shower, Toxic Fog) unlock a mutation while they run (BeltService passes
	the running id into the mutation roll) and put their lighting over the map's through WorldLighting (above a
	seasonal theme's). Their particles and sky effects are client-side (WeatherController).

	Clients read workspace attributes Modifier (id, "" = none), ModifierEndsAt and ModifierNextAt, and work out the same
	effects from the id.

	Commands, this server only: /mod <id> [minutes], /mod off, /mod list. Anyone in Studio; in live servers the admins
	in Config/LiveOps.adminUserIds. The host panel (HostService) calls the same functions, with the same limits
	(Config/Host.limits.modifierMinutes); a private server's owner may start the `hostable` ones from it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local Host = require(ReplicatedStorage.Shared.Config.Host)
local LiveOps = require(ReplicatedStorage.Shared.Config.LiveOps)
local Modifiers = require(ReplicatedStorage.Shared.Config.Modifiers)
local Mutations = require(ReplicatedStorage.Shared.Config.Mutations)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local ModifierRules = require(ReplicatedStorage.Shared.Logic.ModifierRules)
local MutationRules = require(ReplicatedStorage.Shared.Logic.MutationRules)
local Announcer = require(script.Parent.Announcer)
local LiveOpsService = require(script.Parent.LiveOpsService)
local Remotes = require(script.Parent.Remotes)
local WorldLighting = require(script.Parent.WorldLighting)

local ModifierService = {}

-- How long the movement checks keep allowing the previous walking speed after a change (a client catches up within
-- a round trip; this is generous).
local SPEED_GRACE_SECONDS = 4
local LUCK_SOURCE = "modifier"
-- The weather's lighting layer: above a seasonal theme's (SeasonService uses 10), so a storm darkens Halloween too.
local LIGHTING_LAYER = "modifier"
local LIGHTING_PRIORITY = 20
local LIGHTING_SECONDS = 4

local random = Random.new()
local current: string? = nil
local last: string? = nil
local endsAt = 0
local nextAt = 0
local effects = ModifierRules.none()
local previousWalk = 1
local previousWalkUntil = 0
local listeners: { () -> () } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function nextRandom(): number
	return random:NextNumber()
end

-- What the running modifier changes (every field 1 when none runs).
function ModifierService.effects(): ModifierRules.Effects
	return effects
end

function ModifierService.current(): string?
	return current
end

-- When the running modifier ends (server time; 0 when none runs).
function ModifierService.endsAt(): number
	return if current then endsAt else 0
end

-- The walking-speed multiplier movement checks should allow right now: the current one, or the previous one for a
-- few seconds after a change if that was faster.
function ModifierService.walkSpeedAllowance(): number
	if now() < previousWalkUntil then
		return math.max(effects.walkSpeed, previousWalk)
	end
	return effects.walkSpeed
end

-- Calls `listener` whenever a modifier starts or ends.
function ModifierService.onChanged(listener: () -> ())
	table.insert(listeners, listener)
end

local function publish()
	workspace:SetAttribute("Modifier", current or "")
	workspace:SetAttribute("ModifierEndsAt", if current then endsAt else 0)
	workspace:SetAttribute("ModifierNextAt", if current then 0 else nextAt)
end

local function setEffects(id: string?)
	local before = effects
	effects = ModifierRules.effects(Modifiers, id)
	if effects.walkSpeed ~= before.walkSpeed then
		previousWalk = before.walkSpeed
		previousWalkUntil = now() + SPEED_GRACE_SECONDS
	end
	for _, listener in listeners do
		task.spawn(listener)
	end
end

-- Starts modifier `id` now for `seconds` (ending whatever runs). `announce` shows the banner to everyone.
function ModifierService.startModifier(id: string, seconds: number, announce: boolean)
	local def = Modifiers.modifiers[id]
	if def == nil then
		return
	end
	LiveOpsService.endBoosts(LUCK_SOURCE)
	current = id
	last = id
	endsAt = now() + seconds
	setEffects(id)
	if effects.luck > 1 then
		LiveOpsService.addLuckBoost(seconds, effects.luck, LUCK_SOURCE, true)
	end
	WorldLighting.setOverlay(LIGHTING_LAYER, def.lighting, LIGHTING_PRIORITY, LIGHTING_SECONDS)
	publish()
	if announce then
		Announcer.broadcast({
			text = Format.template(
				Theme.text.modifierStarted,
				{ icon = def.icon, name = string.upper(def.displayName), description = def.description }
			),
			color = def.color,
			kind = "modifier",
		})
	end
	print(`[Modifiers] {id} for {math.floor(seconds)} s`)
end

-- Ends the running modifier now; the next one comes after a random gap.
function ModifierService.stopModifier()
	if current == nil then
		return
	end
	LiveOpsService.endBoosts(LUCK_SOURCE)
	current = nil
	nextAt = now() + ModifierRules.gap(Modifiers.schedule, nextRandom)
	setEffects(nil)
	WorldLighting.setOverlay(LIGHTING_LAYER, nil, LIGHTING_PRIORITY, LIGHTING_SECONDS)
	publish()
end

local function step()
	local t = now()
	if current then
		if t >= endsAt then
			ModifierService.stopModifier()
		end
	elseif Modifiers.schedule.enabled and t >= nextAt then
		local id = ModifierRules.pick(Modifiers, last, nextRandom)
		if id then
			ModifierService.startModifier(id, Modifiers.schedule.durationSeconds, true)
		else
			nextAt = t + Modifiers.schedule.gapMaxSeconds
			publish()
		end
	end
end

-- Chat commands ------------------------------------------------------------------------------------------------------

local function isAdmin(userId: number): boolean
	return RunService:IsStudio() or table.find(LiveOps.adminUserIds, userId) ~= nil
end

local function onCommand(player: Player, args: { string })
	local first = args[1] or ""
	if first == "" or string.lower(first) == "list" then
		local names: { string } = {}
		for _, id in Modifiers.order do
			table.insert(names, if id == current then `[{id}]` else id)
		end
		Remotes.notify(player, `Modifiers: {table.concat(names, ", ")}`, "info")
		return
	end
	if string.lower(first) == "off" then
		ModifierService.stopModifier()
		Remotes.notify(player, "Modifier stopped", "info")
		return
	end
	-- Ids are camelCase; accept any case ("/mod rushhour").
	local id: string? = nil
	for candidate in Modifiers.modifiers do
		if string.lower(candidate) == string.lower(first) then
			id = candidate
		end
	end
	if id == nil then
		Remotes.notify(player, "Usage: /mod <id> [minutes] | /mod off | /mod list", "error")
		return
	end
	local minutes = tonumber(args[2])
	local limits = Host.limits.modifierMinutes
	local seconds = if minutes and minutes == minutes
		then math.clamp(minutes, limits.min, limits.max) * 60
		else Modifiers.schedule.durationSeconds
	ModifierService.startModifier(id, seconds, true)
end

local function addCommand()
	local command = Instance.new("TextChatCommand")
	command.Name = "Modifiers"
	command.PrimaryAlias = "/mod"
	command.AutocompleteVisible = false
	command.Parent = TextChatService
	command.Triggered:Connect(function(source: TextSource, text: string)
		if not isAdmin(source.UserId) then
			return
		end
		local player = Players:GetPlayerByUserId(source.UserId)
		if player == nil then
			return
		end
		local args: { string } = {}
		for word in string.gmatch(text, "%S+") do
			table.insert(args, word)
		end
		table.remove(args, 1)
		onCommand(player, args)
	end)
end

function ModifierService.start()
	local unlocks: { [string]: boolean } = {}
	for _, mutation in Mutations do
		if mutation.modifierId then
			unlocks[mutation.modifierId] = true
		end
	end
	for _, problem in ModifierRules.validate(Modifiers, MutationRules.worstCaseTotal(Mutations), unlocks) do
		warn(`[Modifiers] config problem: {problem}`)
	end
	nextAt = now() + Modifiers.schedule.firstDelaySeconds
	publish()
	addCommand()
	task.spawn(function()
		while true do
			task.wait(1)
			local ok, err = pcall(step :: () -> ...any)
			if not ok then
				warn(`[Modifiers] {err}`)
			end
		end
	end)
end

return ModifierService
