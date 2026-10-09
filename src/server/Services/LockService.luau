--!strict
--[[
	Base lock and new-player protection.

	* LockBase intent (owner, standing near their lock button) → Logic/LockRules decides; Instant Lock tokens are
	  spent automatically only when the free lock is recharging, and never inside the mandatory open window.
	* While a base is locked, any non-owner inside it is moved back outside the entrance (4×/s). Character
	  physics is client-owned, so the visible barrier alone would not stop an exploiter — this does.
	* A 1 Hz pass keeps each plot's force field (blue = locked, yellow = new-player shield) and attributes in sync.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Gameplay = require(ReplicatedStorage.Shared.Config.Gameplay)
local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local LockRules = require(ReplicatedStorage.Shared.Logic.LockRules)
local RebirthMath = require(ReplicatedStorage.Shared.Logic.RebirthMath)
local PlotService = require(script.Parent.PlotService)
local PositionTracker = require(script.Parent.PositionTracker)
local Remotes = require(script.Parent.Remotes)
local Replication = require(script.Parent.Replication)
local Sessions = require(script.Parent.Sessions)

type Session = Sessions.Session

local EJECT_INTERVAL = 0.25

local LockService = {}

local lockListener: ((owner: Session) -> ())? = nil

-- StealService registers here so a thief still inside a base when it locks drops the creature.
function LockService.setLockListener(listener: (owner: Session) -> ())
	lockListener = listener
end

local function now(): number
	return workspace:GetServerTimeNow()
end

function LockService.duration(session: Session): number
	return LockRules.duration(
		Gameplay.lock.durationSeconds,
		RebirthMath.lockBonusFor(session.data.rebirths, Economy.rebirth),
		if session.passes.LongerLock then Monetization.perks.longerLockSeconds else 0
	)
end

function LockService.refresh(session: Session)
	session.lockDuration = LockService.duration(session)
	Replication.markDirty(session)
end

function LockService.isLocked(session: Session): boolean
	return LockRules.isLocked(session.lock, now())
end

local function syncShield(session: Session)
	if session.plot == 0 then
		return
	end
	local t = now()
	PlotService.setShieldTimes(session.plot, session.lock.lockedUntil, session.graceUntil)
	if LockRules.isLocked(session.lock, t) then
		PlotService.applyShield(session.plot, "Locked")
	elseif t < session.graceUntil then
		PlotService.applyShield(session.plot, "Grace")
	else
		PlotService.applyShield(session.plot, "None")
	end
end

-- Moves every non-owner standing inside a locked plot back outside its entrance.
local function ejectVisitors(owner: Session)
	local refs = PlotService.refs(owner.plot)
	for _, visitor in Sessions.all() do
		if visitor == owner then
			continue
		end
		local root = Sessions.rootPart(visitor)
		if root and PlotService.isInside(owner.plot, root.Position) then
			local character = visitor.player.Character
			if character then
				-- Judge how they got in first (a teleport into a locked base is still a teleport), then move them.
				PositionTracker.record(visitor, root.Position)
				local target = refs.exitPosition + Vector3.new(math.random(-4, 4), 0, 0)
				character:PivotTo(CFrame.new(target))
				PositionTracker.reset(visitor, target) -- a server move, not a teleport exploit
				local carry = visitor.carry
				if carry then
					-- A server teleport is not a speed exploit.
					carry.lastPosition = target
					carry.lastCheckAt = os.clock()
				end
			end
		end
	end
end

-- Attempts to lock `session`'s base. Returns success and a failure reason.
function LockService.tryLock(session: Session): (boolean, string?)
	if session.plot == 0 then
		return false, "noplot"
	end
	local attempt =
		LockRules.tryLock(session.lock, now(), session.lockDuration, Gameplay.lock, session.data.lockTokens > 0)
	if not attempt.ok then
		local reason = attempt.reason or "cooldown"
		local text = if reason == "vulnerable"
			then Format.template(Theme.text.lockVulnerable, { time = Format.clock(attempt.waitSeconds) })
			elseif reason == "locked" then Format.template(
				Theme.text.lockButtonLocked,
				{ time = Format.clock(attempt.waitSeconds) }
			)
			else Format.template(Theme.text.lockCooldown, { time = Format.clock(attempt.waitSeconds) })
		Remotes.notify(session.player, text, "error")
		return false, reason
	end
	session.lock = attempt.state
	if attempt.usedToken then
		session.data.lockTokens -= 1
	end
	syncShield(session)
	if lockListener then
		lockListener(session)
	end
	ejectVisitors(session)
	Replication.markDirty(session)
	Remotes.notify(
		session.player,
		Format.template(Theme.text.baseLockedToast, { seconds = math.floor(session.lockDuration) }),
		"success"
	)
	Remotes.fire(session.player, "Effect", {
		kind = "lock",
		position = PlotService.refs(session.plot).lockButton.Position,
	})
	return true, nil
end

-- True when a lock could start right now (used to auto-apply a freshly bought Instant Lock).
function LockService.canLockNow(session: Session): boolean
	local attempt =
		LockRules.tryLock(session.lock, now(), session.lockDuration, Gameplay.lock, session.data.lockTokens > 0)
	return attempt.ok
end

-- Ends a session's new-player protection early (e.g. they started stealing).
function LockService.endGrace(session: Session)
	if session.graceUntil > 0 then
		session.graceUntil = 0
		syncShield(session)
		Replication.markDirty(session)
	end
end

local function onLockBase(player: Player)
	local session = Sessions.get(player)
	if session == nil or session.plot == 0 then
		return
	end
	local root = Sessions.rootPart(session)
	local button = PlotService.refs(session.plot).lockButton
	if root == nil or (root.Position - button.Position).Magnitude > Gameplay.lock.buttonRange then
		Remotes.notify(player, Theme.text.tooFar, "error")
		return
	end
	LockService.tryLock(session)
end

function LockService.start()
	Remotes.onIntent("LockBase", onLockBase)

	task.spawn(function()
		while true do
			task.wait(1)
			for _, session in Sessions.all() do
				syncShield(session)
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(EJECT_INTERVAL)
			local t = now()
			for _, session in Sessions.all() do
				if session.plot ~= 0 and LockRules.isLocked(session.lock, t) then
					ejectVisitors(session)
				end
			end
		end
	end)
end

return LockService
