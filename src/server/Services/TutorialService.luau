--!strict
--[[
	First-time player tutorial (Config/Tutorial, rules in Logic/TutorialRules). Server-authoritative:

	* Progress is saved in `data.flags` (one flag per finished step, `tutorial_done` at the end; no schema change).
	  The step the player is on lives in `session.tutorial` and reaches their client in StateUpdate (`tutorial`).
	* Steps finish from real gameplay the server saw: the services call `record` after a belt purchase, a collect
	  from a pad, a lock and a delivered steal. No client message can finish a step; the only tutorial intent is
	  SkipTutorial, which ends it without the reward.
	* A 1 Hz pass ends steps that can't wait forever (the lock recharging for 20 s, the steal step after 90 s).
	* Finishing pays `Tutorial.reward` once per account: TutorialRules.finish sets the done flag and returns the
	  amount, and it is paid right away (no yield in between).
	* Existing players (progress in their save but no tutorial flags) are marked done on join, without the reward.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Gameplay = require(ReplicatedStorage.Shared.Config.Gameplay)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local Tutorial = require(ReplicatedStorage.Shared.Config.Tutorial)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local LockRules = require(ReplicatedStorage.Shared.Logic.LockRules)
local TutorialRules = require(ReplicatedStorage.Shared.Logic.TutorialRules)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local Analytics = require(script.Parent.Analytics)
local Remotes = require(script.Parent.Remotes)
local Replication = require(script.Parent.Replication)
local Sessions = require(script.Parent.Sessions)

type Session = Sessions.Session

-- Pays cash with analytics (EconomyService.addCash, passed in by the bootstrap: EconomyService itself reports collects
-- here, so requiring it would be circular).
export type PayCash = (session: Session, amount: number, transactionType: string?, sku: string?) -> ()

local TICK_SECONDS = 1

local TutorialService = {}

local payCash: PayCash? = nil

local function now(): number
	return workspace:GetServerTimeNow()
end

-- Whether the step's action can be done right now (only the lock can be unavailable: recharging or already locked).
local function actionAvailable(session: Session, stepId: string, t: number): boolean
	if stepId == "lock" then
		local attempt =
			LockRules.tryLock(session.lock, t, session.lockDuration, Gameplay.lock, session.data.lockTokens > 0)
		return session.plot ~= 0 and attempt.ok
	end
	return true
end

local function finish(session: Session, reason: TutorialRules.FinishReason)
	local run = session.tutorial
	session.tutorial = nil
	-- Flag first, then pay: no yield in between, so the reward can only ever be paid once per account.
	local reward = TutorialRules.finish(session.data.flags, reason, Tutorial)
	if reward > 0 and payCash then
		payCash(session, reward, "Onboarding", "TutorialReward")
	end
	Replication.markDirty(session)
	if reason == "completed" then
		Remotes.notify(
			session.player,
			if reward > 0
				then Format.template(Theme.text.tutorialComplete, { amount = UiTheme.cash(reward) })
				else Theme.text.tutorialCompleteNoReward,
			"success"
		)
		local root = Sessions.rootPart(session)
		Remotes.fire(session.player, "Effect", {
			kind = "tutorialComplete",
			position = if root then root.Position else nil,
		})
		Analytics.milestone(session, "TutorialComplete")
	elseif reason == "skipped" and run then
		Analytics.tutorialSkipped(session, run.stepId, TutorialRules.stepIndex(run.stepId, Tutorial))
	end
	Analytics.flushMilestones(session) -- the tutorial is over: funnel steps waiting on it can go
end

-- Moves the session onto the current step (from the saved flags), or finishes the tutorial when every step is done.
local function sync(session: Session)
	local step, index = TutorialRules.currentStep(session.data.flags, Tutorial)
	-- Funnel step 4 once the tutorial has moved past its lock step (never when the lock was merely done early).
	local lockIndex = TutorialRules.stepIndex("lock", Tutorial)
	if lockIndex > 0 and (step == nil or index > lockIndex) then
		Analytics.milestone(session, "TutorialLock")
	end
	if step == nil then
		finish(session, "completed")
		return
	end
	local run = session.tutorial
	if run == nil or run.stepId ~= step.id then
		session.tutorial = { stepId = step.id, startedAt = now(), unavailableSince = nil }
		Replication.markDirty(session)
	end
end

local function endStep(session: Session, stepId: string, outcome: TutorialRules.StepOutcome)
	local run = session.tutorial
	if run == nil or not TutorialRules.markStep(session.data.flags, stepId, Tutorial) then
		return
	end
	local seconds = if run.stepId == stepId then now() - run.startedAt else 0
	Analytics.tutorialStep(session, stepId, outcome, seconds)
	sync(session)
end

-- The player did a tutorial action (a step id: "buy", "collect", "lock", "steal"). Called by the gameplay services
-- right after the server applied it. Finishes that step: now if it is the current one, or when it comes up.
function TutorialService.record(session: Session, action: string)
	local run = session.tutorial
	if run == nil then
		return -- no tutorial running (done, existing player, disabled, or the join isn't finished yet)
	end
	local outcome: TutorialRules.StepOutcome = if run.stepId == action then "done" else "early"
	endStep(session, action, outcome)
end

-- Join hook (after the plot is assigned): starts, resumes or retires the tutorial.
function TutorialService.onJoined(session: Session)
	local status = TutorialRules.joinStatus(session.data, Tutorial)
	if status == "returning" then
		TutorialRules.finish(session.data.flags, "returning", Tutorial) -- pays nothing
	elseif status == "new" or status == "resume" then
		sync(session)
	end
	Analytics.flushMilestones(session) -- e.g. an existing player's steps that waited on the tutorial steps
end

function TutorialService.onLeaving(session: Session)
	session.tutorial = nil
end

-- Studio /tutorial: clears the tutorial flags and starts it again.
function TutorialService.restart(session: Session)
	TutorialRules.reset(session.data.flags, Tutorial)
	session.tutorial = nil
	sync(session)
	Replication.markDirty(session)
end

local function onSkip(player: Player)
	local session = Sessions.get(player)
	if session == nil or session.tutorial == nil then
		return
	end
	finish(session, "skipped")
end

local function tick()
	local t = now()
	for _, session in Sessions.all() do
		local run = session.tutorial
		if run == nil then
			continue
		end
		local step = TutorialRules.currentStep(session.data.flags, Tutorial)
		if step == nil or step.id ~= run.stepId then
			sync(session) -- e.g. the config changed under a running session; never expected
			continue
		end
		run.unavailableSince =
			TutorialRules.trackUnavailable(run.unavailableSince, actionAvailable(session, step.id, t), t)
		local outcome: TutorialRules.StepOutcome? =
			TutorialRules.autoOutcome(step, run.startedAt, run.unavailableSince, t)
		if outcome then
			endStep(session, step.id, outcome)
		end
	end
end

function TutorialService.start(pay: PayCash)
	payCash = pay
	Remotes.onIntent("SkipTutorial", onSkip)
	task.spawn(function()
		while true do
			task.wait(TICK_SECONDS)
			local ok, err = pcall(tick :: () -> ...any)
			if not ok then
				warn(`[TutorialService] tick failed: {err}`)
			end
		end
	end)
end

return TutorialService
