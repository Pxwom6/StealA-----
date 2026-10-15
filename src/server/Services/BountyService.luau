--!strict
--[[
	Bounty Hunt (Config/Modifiers `bounty`, Config/Bounty, rules in Logic/BountyRules): while it runs, the server's top
	earner wears a bounty.

	  * When it starts, the target is the player with the most steady income (BountyRules.pickTarget: a base, not in
	    the first-time tutorial; ties to whoever joined first). Everyone hears who it is; the target is told to guard
	    their base. If they leave, it moves to the next top earner (announced); with nobody earning yet, the server
	    looks again every few seconds.
	  * The target wears it as the Player attribute Bounty ("on", or "resting" for restSeconds after a claim): Nametags
	    puts a 🎯 BOUNTY marker in their title's place and a gold outline round them, and StealService's THIEF! marker
	    says BOUNTY while they carry.
	  * Claims come only from what StealService decided (its GameEvents): a tag on the target, who must be carrying a
	    Snackling for a tag to land at all ("tag"), or a Snackling stolen from the target's base delivered home
	    ("steal"). BountyRules.canClaim refuses the target themself, their Roblox friends (SocialService's cached
	    answers: no trading tags for payouts), a hunter who already claimed claimsPerHunter times this hunt, and any
	    claim while it rests. A claim pays cash sized from the claimer's own steady income (BountyRules.payout), is
	    announced, and rests the bounty. Nothing yields between the check and the payout.
	  * When it ends, the marker goes; a target nobody claimed is announced as having got through it.

	Analytics: bounty_claimed (value = cash, 01 = "tag" | "steal").
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Bounty = require(ReplicatedStorage.Shared.Config.Bounty)
local Modifiers = require(ReplicatedStorage.Shared.Config.Modifiers)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local BountyRules = require(ReplicatedStorage.Shared.Logic.BountyRules)
local CrossServerRules = require(ReplicatedStorage.Shared.Logic.CrossServerRules)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local Analytics = require(script.Parent.Analytics)
local Announcer = require(script.Parent.Announcer)
local EconomyService = require(script.Parent.EconomyService)
local GameEvents = require(script.Parent.GameEvents)
local ModifierService = require(script.Parent.ModifierService)
local Nametags = require(script.Parent.Nametags)
local Remotes = require(script.Parent.Remotes)
local Sessions = require(script.Parent.Sessions)
local SocialService = require(script.Parent.SocialService)
local StealService = require(script.Parent.StealService)

type Session = Sessions.Session

local BountyService = {}

local hunt: BountyRules.Hunt? = nil
local huntColor = "#FF3D6E"

local function now(): number
	return workspace:GetServerTimeNow()
end

-- A player's name for a banner: shortened like a shout-out's, so two long names still fit on a phone.
local function bannerName(session: Session): string
	return CrossServerRules.shortName(session.player.DisplayName, CrossServerRules.SHOUT_NAME_LENGTH)
end

local function runningBounty(): (boolean, string?)
	local id = ModifierService.current()
	local def = if id then Modifiers.modifiers[id] else nil
	if def and def.bounty == true then
		return true, def.color
	end
	return false, nil
end

-- Shows `session` wearing the bounty as `state` ("on" | "resting" | nil: not at all).
local function wear(session: Session, state: string?)
	if session.player:GetAttribute(Nametags.BOUNTY_ATTRIBUTE) == state then
		return
	end
	session.player:SetAttribute(Nametags.BOUNTY_ATTRIBUTE, state)
	Nametags.refresh(session)
	StealService.refreshMarker(session)
end

local function target(): Session?
	local current = hunt
	local userId = if current then current.targetUserId else nil
	return if userId then Sessions.getByUserId(userId) else nil
end

-- The top earner now, leaving out `leaving` (a player on their way out).
local function topEarner(leaving: Session?): number?
	local candidates: { BountyRules.Candidate } = {}
	for _, session in Sessions.all() do
		if session ~= leaving then
			table.insert(candidates, {
				userId = session.userId,
				income = session.packIncome,
				joinedAt = session.joinedAt,
				eligible = session.plot ~= 0 and session.tutorial == nil,
			})
		end
	end
	return BountyRules.pickTarget(candidates)
end

-- Puts the bounty on `userId` (nil: nobody), announcing it (`moved`: it was on someone else before).
local function setTarget(userId: number?, moved: boolean)
	local current = hunt
	if current == nil or current.targetUserId == userId then
		return
	end
	local old = target()
	current.targetUserId = userId
	if old then
		wear(old, nil)
	end
	local new = target()
	if new == nil then
		return
	end
	wear(new, if BountyRules.isResting(current, now()) then "resting" else "on")
	Announcer.broadcast({
		text = Format.template(
			if moved then Theme.text.bountyMoved else Theme.text.bountyOn,
			{ player = bannerName(new) }
		),
		color = huntColor,
		kind = "modifier",
	})
	Remotes.notify(new.player, Theme.text.bountyYou, "warning")
end

local function startHunt(color: string?)
	hunt = BountyRules.newHunt()
	huntColor = color or huntColor
	setTarget(topEarner(nil), false)
end

local function endHunt()
	local current = hunt
	if current == nil then
		return
	end
	local old = target()
	hunt = nil
	if old then
		wear(old, nil)
		if current.claimed == 0 then
			Announcer.broadcast({
				text = Format.template(Theme.text.bountyEscaped, { player = bannerName(old) }),
				color = huntColor,
				kind = "modifier",
			})
		end
	end
end

local function onModifierChanged()
	local running, color = runningBounty()
	if running and hunt == nil then
		startHunt(color)
	elseif not running and hunt ~= nil then
		endHunt()
	end
end

-- Every few seconds while a hunt runs: a target if there is none yet (nobody earned anything when it started), and
-- the marker back from resting once the rest is over.
local function step()
	local current = hunt
	if current == nil then
		return
	end
	local wearer = target()
	if wearer == nil then
		setTarget(topEarner(nil), current.targetUserId ~= nil)
		return
	end
	wear(wearer, if BountyRules.isResting(current, now()) then "resting" else "on")
end

-- `claimer` tagged, or robbed, `victimUserId` (StealService's events): pays the bounty when that claims it.
local function tryClaim(claimer: Session, victimUserId: number?, kind: BountyRules.ClaimKind)
	local current = hunt
	local wearer = target()
	if current == nil or wearer == nil or victimUserId == nil then
		return
	end
	local t = now()
	local ok, reason = BountyRules.canClaim(Bounty, current, {
		claimerUserId = claimer.userId,
		victimUserId = victimUserId,
		friends = SocialService.areFriends(claimer, wearer),
		now = t,
	})
	if not ok then
		local key = if reason then BountyRules.messageKey(reason) else nil
		if key then
			Remotes.notify(
				claimer.player,
				UiTheme.text(key, { time = Format.clock(current.restUntil - t) }),
				if reason == "friend" then "info" else "error"
			)
		end
		return
	end
	BountyRules.claim(Bounty, current, claimer.userId, t)
	local amount = BountyRules.payout(Bounty, kind, claimer.packIncome)
	EconomyService.addCash(claimer, amount, "Gameplay", "Bounty")
	wear(wearer, "resting")
	Remotes.notify(claimer.player, Format.template(Theme.text.bountyReward, { cash = UiTheme.cash(amount) }), "success")
	Remotes.notify(
		wearer.player,
		Format.template(
			Theme.text.bountyClaimedOnYou,
			{ player = claimer.player.DisplayName, seconds = Bounty.restSeconds }
		),
		"warning"
	)
	Announcer.broadcast({
		text = Format.template(
			if kind == "tag" then Theme.text.bountyClaimedTag else Theme.text.bountyClaimedSteal,
			{ player = bannerName(claimer), target = bannerName(wearer) }
		),
		color = huntColor,
		kind = "modifier",
	})
	local fields: { string } = { kind }
	Analytics.custom(claimer, "bounty_claimed", amount, fields)
end

-- PlayerLifecycle onLeaving hook: the target leaving hands the bounty to the next top earner.
function BountyService.onLeaving(session: Session)
	local current = hunt
	if current and current.targetUserId == session.userId then
		session.player:SetAttribute(Nametags.BOUNTY_ATTRIBUTE, nil)
		current.targetUserId = nil
		setTarget(topEarner(session), true)
	end
end

-- The hunt running now (tests), or nil.
function BountyService.hunt(): BountyRules.Hunt?
	return hunt
end

function BountyService.start()
	for _, problem in BountyRules.validate(Bounty) do
		warn(`[Bounty] config problem: {problem}`)
	end
	ModifierService.onChanged(onModifierChanged)
	GameEvents.on("BountyService", function(session: Session, event: GameEvents.Event)
		if event.kind == "tag" then
			tryClaim(session, event.otherUserId, "tag")
		elseif event.kind == "steal" then
			tryClaim(session, event.otherUserId, "steal")
		end
	end)
	onModifierChanged()
	task.spawn(function()
		while true do
			task.wait(Bounty.checkSeconds)
			local ok, err = pcall(step :: () -> ...any)
			if not ok then
				warn(`[Bounty] {err}`)
			end
		end
	end)
end

return BountyService
