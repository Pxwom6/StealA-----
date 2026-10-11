--!strict
--[[
	Base lock and new-player protection.

	* LockBase intent (owner, standing near their lock button) → Logic/LockRules decides; Instant Lock tokens are
	  spent automatically only when the free lock is recharging, and never inside the mandatory open window.
	* While a base is locked, any non-owner inside it is moved back outside the entrance (4×/s; a carrying thief
	  just outside the nearest side). Character physics is client-owned, so the visible barrier alone would not
	  stop an exploiter — this does.
	* A 1 Hz pass keeps each plot's force field (blue = locked, yellow = new-player shield) and attributes in sync.
	* The cooldown and open window are saved (`data.lockTimers`, wall-clock seconds) when a lock starts and on every
	  save (on the final save a lock still running counts as ending then), and restored on join, so leaving and
	  rejoining any server never resets them.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Gameplay = require(ReplicatedStorage.Shared.Config.Gameplay)
local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local LockRules = require(ReplicatedStorage.Shared.Logic.LockRules)
local RebirthMath = require(ReplicatedStorage.Shared.Logic.RebirthMath)
local StealRules = require(ReplicatedStorage.Shared.Logic.StealRules)
local GameEvents = require(script.Parent.GameEvents)
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

local beforeEject: ((visitor: Session) -> ())? = nil

-- StealService registers here to check a carrying visitor's movement before the server moves them out of a base,
-- so the server's move can't launder a teleport into that base.
function LockService.setBeforeEject(listener: (visitor: Session) -> ())
	beforeEject = listener
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

-- Sessions whose saved timers were restored on join. Only those may write timers back: a join that never got that
-- far (e.g. kicked because the server was full) must not overwrite the saved cooldown with a blank state.
local restored: { [Session]: boolean } = setmetatable({}, { __mode = "k" }) :: any

-- Writes the lock timers into the save as wall-clock times (LockRules.toSaved). On the final save (leave, shutdown,
-- another server taking the session) a lock still running counts as ending now, which it does; on any other save it
-- keeps its natural end, so if the server then crashes mid-lock the next join is not let off early.
local function persist(session: Session, isFinalSave: boolean)
	if restored[session] then
		local t = now()
		local state = if isFinalSave then LockRules.unlock(session.lock, t) else session.lock
		session.data.lockTimers = LockRules.toSaved(state, t, os.time())
	end
end

-- On join (after `refresh`): restores the cooldown and open window saved on the player's last visit, and keeps the
-- save up to date from then on (every save, including the final one at leave or shutdown).
function LockService.restore(session: Session)
	local _, cooldownSeconds = LockRules.windows(session.lockDuration, Gameplay.lock)
	local maxSeconds = session.lockDuration + cooldownSeconds
	session.lock = LockRules.fromSaved(session.data.lockTimers, now(), os.time(), maxSeconds)
	restored[session] = true
	session.profile.OnSave:Connect(function()
		persist(session, false)
	end)
	session.profile.OnLastSave:Connect(function()
		persist(session, true)
	end)
	Replication.markDirty(session)
end

-- On leave: a running lock ends now (the base goes with its owner) and its cooldown is saved for the next join.
function LockService.onLeaving(session: Session)
	session.lock = LockRules.unlock(session.lock, now())
	persist(session, false)
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
-- `lockStarting` is true for the pass that runs as the lock turns on (see the carry push below).
local function ejectVisitors(owner: Session, lockStarting: boolean)
	local refs = PlotService.refs(owner.plot)
	for _, visitor in Sessions.all() do
		if visitor == owner then
			continue
		end
		local root = Sessions.rootPart(visitor)
		-- Right after an ejection the client may still report a position inside for a moment: the server already
		-- moved them, so that stale position is not ejected again (it is once the settle window has passed).
		if
			root
			and PlotService.isInside(owner.plot, root.Position)
			and not PositionTracker.isSettling(visitor, root.Position)
		then
			local character = visitor.player.Character
			if character then
				-- Judge how they got in first (a teleport into a locked base is still a teleport), then move them.
				PositionTracker.record(visitor, root.Position)
				if visitor.carry and beforeEject then
					beforeEject(visitor) -- steps the carry to here; may cancel it
				end
				local target = refs.exitPosition + Vector3.new(math.random(-4, 4), 0, 0)
				local carry = visitor.carry
				if carry then
					-- A carrying thief goes just outside the nearest side instead (the entrance could be a shortcut
					-- home). If they were inside when the lock started, the push costs them nothing: no budget, no
					-- progress toward the straight-line cap. Anyone found inside later got past the locked barrier
					-- and walls (no-clip, teleport), so their budget pays for the push at the next carry check.
					local x, z =
						StealRules.nearestOutside(root.Position.X, root.Position.Z, PlotService.rect(owner.plot), 3)
					target = Vector3.new(x, refs.exitPosition.Y, z)
					if lockStarting then
						StealRules.shiftCarryTrack(carry.track, target.X, target.Y, target.Z)
					end
				end
				character:PivotTo(CFrame.new(target))
				PositionTracker.reset(visitor, target) -- a server move, not a teleport exploit
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
	persist(session, false)
	syncShield(session)
	if lockListener then
		lockListener(session)
	end
	ejectVisitors(session, true)
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
	GameEvents.emit(session, { kind = "lock" }) -- tutorial, quests
	return true, nil
end

-- What a lock attempt right now would do, without doing it (used after buying Instant Lock).
function LockService.preview(session: Session): LockRules.LockAttempt
	return LockRules.tryLock(session.lock, now(), session.lockDuration, Gameplay.lock, session.data.lockTokens > 0)
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
					-- One failing base must not stop the loop (every locked base would stop ejecting).
					local ok, err = pcall(ejectVisitors :: (Session, boolean) -> ...any, session, false)
					if not ok then
						warn(`[LockService] ejecting from {session.player.Name}'s base failed: {err}`)
					end
				end
			end
		end
	end)
end

return LockService
