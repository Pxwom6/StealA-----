--!strict
--[[
	Server-observed positions. Character physics is client-owned, so a client can report any position it likes;
	this samples every player's root part a few times per second (Gameplay.tracking.sampleInterval) against a walking
	movement budget (Logic/StealRules.stepWalkTrack: jumps and short lag stalls are fine). A step the budget can't pay
	for records `session.flaggedAt` (the position is untrusted for a couple of seconds); a gross one (a teleport)
	also records `session.teleportedAt`.

	isTrusted(session, position, carryStartedAt) is what tagging uses: a tag only counts when the tagger hasn't been
	flagged in the last couple of seconds, wasn't caught teleporting since just before that carry started, and their
	current position is walkable from the latest sample (Logic/StealRules.isPositionTrusted).

	isTrustedForSteal(session, position) gates starting and finishing a steal hold: the thief must not have been
	flagged at all since just before they were first seen in the plot they are in, so teleporting onto a podium
	(even then waiting) doesn't work; walking out and back in on foot clears it.

	Whenever the SERVER moves a character (spawning at the base, ejecting from a locked base) call reset(), so the
	jump is not mistaken for a teleport exploit. A reset never clears the flags: record() the position before a
	server move, so a teleport into a locked base is still caught.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Gameplay = require(ReplicatedStorage.Shared.Config.Gameplay)
local StealRules = require(ReplicatedStorage.Shared.Logic.StealRules)
local PlotService = require(script.Parent.PlotService)
local Sessions = require(script.Parent.Sessions)

type Session = Sessions.Session

local CFG = Gameplay.tracking

local PositionTracker = {}

local WALK_LIMITS: StealRules.WalkLimits = {
	maxSpeed = Gameplay.walkSpeed,
	tolerance = CFG.walkTolerance,
	budgetSeconds = CFG.walkBudgetSeconds,
	leeway = CFG.walkLeeway,
}

local function now(): number
	return workspace:GetServerTimeNow()
end

function PositionTracker.record(session: Session, position: Vector3)
	local t = now()
	local plot = PlotService.plotAt(position) or 0
	if plot ~= session.samplePlot then
		session.samplePlot = plot
		session.enteredPlotAt = t
	end
	local track = session.walk
	if track == nil then
		session.walk = StealRules.newWalkTrack(position.X, position.Y, position.Z, t, WALK_LIMITS)
	elseif not StealRules.stepWalkTrack(track, position.X, position.Y, position.Z, t, WALK_LIMITS) then
		session.flaggedAt = t
		if StealRules.walkStepVerdict(track, CFG.teleportDeficit) == "teleport" then
			session.teleportedAt = t
		end
		track.budget = 0 -- start over from here, so they are not flagged again for the same move
	end
end

-- Restarts tracking after a server-side move (or death). `position`, when given, becomes the first sample.
function PositionTracker.reset(session: Session, position: Vector3?)
	session.walk = if position
		then StealRules.newWalkTrack(position.X, position.Y, position.Z, now(), WALK_LIMITS)
		else nil
end

-- True when `position` (the player's current root position) is consistent with what the server observed: not
-- flagged in the last couple of seconds, and (when `carryStartedAt` is given) not caught teleporting since just
-- before that carry started, which also covers the thief's hold.
function PositionTracker.isTrusted(session: Session, position: Vector3, carryStartedAt: number?): boolean
	local t = now()
	return StealRules.isPositionTrusted({
		track = session.walk,
		flaggedAt = session.flaggedAt,
		teleportedAt = session.teleportedAt,
		flagSince = t - CFG.teleportPenaltySeconds,
		teleportSince = (carryStartedAt or t) - CFG.teleportPenaltySeconds,
		x = position.X,
		z = position.Z,
		t = t,
		stepSlack = CFG.stepSlack,
	}, WALK_LIMITS)
end

-- True when a thief's `position` can be trusted for starting or finishing a steal: as isTrusted, and not flagged at
-- all since just before they were first seen in the plot they are in now.
function PositionTracker.isTrustedForSteal(session: Session, position: Vector3): boolean
	local t = now()
	local since = math.min(t, session.enteredPlotAt) - CFG.teleportPenaltySeconds
	return StealRules.isPositionTrusted({
		track = session.walk,
		flaggedAt = session.flaggedAt,
		teleportedAt = session.teleportedAt,
		flagSince = since,
		teleportSince = since,
		x = position.X,
		z = position.Z,
		t = t,
		stepSlack = CFG.stepSlack,
	}, WALK_LIMITS)
end

function PositionTracker.start()
	task.spawn(function()
		while true do
			task.wait(CFG.sampleInterval)
			for _, session in Sessions.all() do
				local root = Sessions.rootPart(session)
				if root then
					PositionTracker.record(session, root.Position)
				elseif session.walk then
					PositionTracker.reset(session, nil) -- dead or respawning: the old history no longer applies
				end
			end
		end
	end)
end

return PositionTracker
