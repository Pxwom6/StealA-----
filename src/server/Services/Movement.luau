--!strict
--[[
	How fast each player may move: the walking speed their Humanoid gets, and the speed the server's movement checks
	allow for them. One place for both, so they can never disagree.

	  speed     Gameplay.walkSpeed x (a speed modifier x a speed gadget, capped at Config/Gadgets.maxSpeedMultiplier),
	            x the carry slowdown while carrying a Snackling; 0 while frozen (slipped on a banana peel)
	  allowance what PositionTracker's walking budget and StealService's carry budget allow, as a multiplier on walking
	            speed: the modifier's allowance (ModifierService.walkSpeedAllowance, which keeps a faster old speed for a
	            few seconds after a change) x the speed gadget's (Logic/GadgetRules.speedAllowance, the same grace),
	            under the same cap. Never less than the speed itself, so nobody is flagged for a speed the server gave
	            them, and never above 1.5x walking speed (CI checks the cap).

	Whatever changes one of those calls apply(session): a carry starting or ending (StealService), a modifier changing
	(StealService listens), a gadget starting or ending and a slip (GadgetService), a new character (PlayerLifecycle).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Gadgets = require(ReplicatedStorage.Shared.Config.Gadgets)
local Gameplay = require(ReplicatedStorage.Shared.Config.Gameplay)
local GadgetRules = require(ReplicatedStorage.Shared.Logic.GadgetRules)
local ModifierService = require(script.Parent.ModifierService)
local Sessions = require(script.Parent.Sessions)

type Session = Sessions.Session

local Movement = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

-- The walking multiplier `session` has right now: a running speed modifier times their speed gadget, capped.
function Movement.multiplier(session: Session): number
	return GadgetRules.combinedSpeed(
		ModifierService.effects().walkSpeed,
		GadgetRules.speedMultiplier(session.gadgets, now()),
		Gadgets.maxSpeedMultiplier
	)
end

-- The multiplier on walking speed the movement checks allow `session` right now (see the header).
function Movement.allowance(session: Session): number
	return GadgetRules.combinedSpeed(
		ModifierService.walkSpeedAllowance(),
		GadgetRules.speedAllowance(session.gadgets, now(), Gadgets.speedGraceSeconds),
		Gadgets.maxSpeedMultiplier
	)
end

-- The Humanoid.WalkSpeed `session` should have right now.
function Movement.walkSpeed(session: Session): number
	if GadgetRules.isFrozen(session.gadgets, now()) then
		return 0
	end
	local speed = Gameplay.walkSpeed * Movement.multiplier(session)
	if session.carry then
		speed *= Gameplay.steal.carrySpeedMultiplier
	end
	return speed
end

-- Gives the player's character the walking speed it should have now (nothing when there is no character).
function Movement.apply(session: Session)
	local humanoid = Sessions.humanoid(session)
	if humanoid then
		humanoid.WalkSpeed = Movement.walkSpeed(session)
	end
end

return Movement
