--!strict
--[[
	Self-test section Modifiers: starts every server modifier with ModifierService.startModifier (the start path the
	schedule, `/mod` and the host panel share; no banner), lets it run `holdSeconds` (a drop modifier: until its first
	crate, coins, runaway or giant is out), checks it, ends it with ModifierService.stopModifier and checks again.

	While it runs: the server publishes it (workspace attributes), its effects are the ones Logic/ModifierRules gives
	(what the belt, economy, locks, steals and movement read), luck reaches the server luck, a weather modifier's sky is
	the top lighting layer and its mutation can roll on the belt, and every player's walking speed and lock length
	follow it. Once ended: nothing is published, no effect is left, the luck and the sky are back as they were, and
	whatever a drop left is taken away (DropService.clear, BossService.dismiss) so nobody finds a stray crate. An error
	or a warning logged meanwhile counts against that modifier.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modifiers = require(ReplicatedStorage.Shared.Config.Modifiers)
local Mutations = require(ReplicatedStorage.Shared.Config.Mutations)
local ModifierRules = require(ReplicatedStorage.Shared.Logic.ModifierRules)
local MutationRules = require(ReplicatedStorage.Shared.Logic.MutationRules)
local Services = script.Parent.Parent.Services
local BeltService = require(Services.BeltService)
local BossService = require(Services.BossService)
local BountyService = require(Services.BountyService)
local DropService = require(Services.DropService)
local LockService = require(Services.LockService)
local ModifierService = require(Services.ModifierService)
local Movement = require(Services.Movement)
local Nametags = require(Services.Nametags)
local Sessions = require(Services.Sessions)
local WorldLighting = require(Services.WorldLighting)
local Kit = require(script.Parent.Kit)

-- Long enough never to end by itself while it is checked: the section ends it.
local RUN_SECONDS = 120

local function luck(): number
	local value = workspace:GetAttribute("LuckMultiplier")
	return if type(value) == "number" then value else 1
end

-- Whether a drop modifier's first thing is out.
local function dropped(kind: string): boolean
	if kind == "boss" then
		return BossService.current() ~= nil
	elseif kind == "treasure" then
		return DropService.treasureModel() ~= nil
	end
	local crates, coins, runaways = DropService.counts()
	if kind == "crate" then
		return crates > 0
	elseif kind == "coins" then
		return coins > 0
	elseif kind == "runaway" then
		return runaways > 0
	end
	return false
end

-- Whether anything a drop modifier puts out is still out.
local function anythingOut(): boolean
	local crates, coins, runaways = DropService.counts()
	return crates + coins + runaways > 0 or DropService.treasureModel() ~= nil or BossService.current() ~= nil
end

-- Who still wears a bounty (the Player attribute BountyService sets), by name.
local function bountyWearers(): { string }
	local names: { string } = {}
	for _, session in Sessions.all() do
		if session.player:GetAttribute(Nametags.BOUNTY_ATTRIBUTE) ~= nil then
			table.insert(names, session.player.Name)
		end
	end
	return names
end

-- What is wrong with modifier `id` while it runs.
local function runningIssues(id: string, lockBefore: { [Sessions.Session]: number }): { string }
	local def = Modifiers.modifiers[id]
	local expected = ModifierRules.effects(Modifiers, id)
	local effects = ModifierService.effects()
	local issues: { string } = {}
	if ModifierService.current() ~= id or workspace:GetAttribute("Modifier") ~= id then
		table.insert(issues, `the server publishes {workspace:GetAttribute("Modifier")} as running`)
	end
	for _, key in ModifierRules.EFFECT_KEYS do
		local have, want = (effects :: any)[key] :: number, (expected :: any)[key] :: number
		if not Kit.near(have, want) then
			table.insert(issues, `{key} is x{have}, ModifierRules says x{want}`)
		end
	end
	if expected.luck > 1 and luck() < expected.luck - 1e-6 then
		table.insert(issues, `server luck is x{luck()}, not at least x{expected.luck}`)
	end
	local lighting = def.lighting
	if lighting then
		local clock = WorldLighting.clockTime()
		if clock == nil or not Kit.near(clock, lighting.clockTime) then
			table.insert(issues, `its sky (clock {lighting.clockTime}) is not the top lighting layer ({clock})`)
		end
	end
	local conditions = BeltService.mutationConditions()
	for _, mutation in Mutations do
		if mutation.modifierId == id and conditions[MutationRules.modifierKey(id)] ~= true then
			table.insert(issues, `{mutation.id} Snacklings can't roll on the belt`)
		end
	end
	if def.bounty == true and BountyService.hunt() == nil then
		table.insert(issues, "no bounty hunt started")
	end
	for _, session in Sessions.all() do
		local name = session.player.Name
		local humanoid = Sessions.humanoid(session)
		local speed = Movement.walkSpeed(session)
		if humanoid and humanoid.Health > 0 and math.abs(humanoid.WalkSpeed - speed) > 0.01 then
			table.insert(issues, `{name} walks at {humanoid.WalkSpeed}, Movement says {speed}`)
		end
		local before = lockBefore[session]
		local length = LockService.duration(session)
		if before and not Kit.near(length, before * expected.lockDuration) then
			table.insert(issues, `{name}'s lock lasts {length} s, expected {before * expected.lockDuration}`)
		end
	end
	return issues
end

local Section: Kit.Section = {
	name = "Modifiers",
	run = function(ctx: Kit.Context): string
		ctx.onCleanup(Kit.endModifier)
		Kit.endModifier()
		local count, drops = 0, 0
		for _, id in Modifiers.order do
			local def = Modifiers.modifiers[id]
			if def == nil then
				ctx.problem(`{id} is in Modifiers.order but not in Modifiers.modifiers`)
				continue
			end
			count += 1
			local issues: { string } = {}
			local luckBefore = luck()
			local clockBefore = WorldLighting.clockTime()
			local lockBefore: { [Sessions.Session]: number } = {}
			for _, session in Sessions.all() do
				lockBefore[session] = LockService.duration(session)
			end

			local mark = ctx.mark()
			local started, err =
				pcall(ModifierService.startModifier :: (string, number, boolean) -> ...any, id, RUN_SECONDS, false)
			if not started then
				table.insert(issues, `startModifier failed: {Kit.short(tostring(err))}`)
			end
			local dropDef = def.drops
			if dropDef then
				local waited = dropDef.firstSeconds + ctx.options.dropMarginSeconds
				local kind = dropDef.kind
				if Kit.waitUntil(function(): boolean
					return dropped(kind)
				end, ctx.now() + waited) then
					drops += 1
				else
					table.insert(issues, `no {kind} came within {waited} s`)
				end
			else
				task.wait(ctx.options.holdSeconds)
			end
			for _, issue in runningIssues(id, lockBefore) do
				table.insert(issues, issue)
			end

			local stopped, stopErr = pcall(ModifierService.stopModifier :: () -> ...any)
			if not stopped then
				table.insert(issues, `stopModifier failed: {Kit.short(tostring(stopErr))}`)
			end
			if ModifierService.current() ~= nil or workspace:GetAttribute("Modifier") ~= "" then
				table.insert(issues, "it is still published as running after it ended")
			end
			local left = ModifierService.effects()
			for _, key in ModifierRules.EFFECT_KEYS do
				local value = (left :: any)[key] :: number
				if not Kit.near(value, 1) then
					table.insert(issues, `{key} stays x{value} after it ended`)
				end
			end
			if not Kit.near(luck(), luckBefore) then
				table.insert(issues, `server luck is x{luck()} after it ended, x{luckBefore} before`)
			end
			local clockAfter = WorldLighting.clockTime()
			if clockBefore and clockAfter and not Kit.near(clockAfter, clockBefore) then
				table.insert(issues, `the sky stays at clock {clockAfter} (it was {clockBefore})`)
			end
			if def.bounty == true then
				if BountyService.hunt() ~= nil then
					table.insert(issues, "its bounty hunt goes on after it ended")
				end
				local wearers = bountyWearers()
				if #wearers > 0 then
					table.insert(issues, `{table.concat(wearers, ", ")} still wear the bounty after it ended`)
				end
			end
			if dropDef then
				DropService.clear()
				BossService.dismiss()
				if anythingOut() then
					table.insert(issues, "its drops are still out after the clean-up")
				end
			end
			for _, message in ctx.take(mark) do
				table.insert(issues, `{message.kind}: {message.text}`)
			end
			for _, issue in issues do
				ctx.problem(`{id}: {issue}`)
			end
		end
		return `{count} modifiers started and ended ({drops} drops came)`
	end,
}

return Section
