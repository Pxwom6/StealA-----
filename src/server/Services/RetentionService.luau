--!strict
--[[
	Reasons to come back:
	  * Offline earnings: on join, a capped, reduced-rate payout for time away, shown as a "Welcome back" popup.
	  * Daily streak: one claim per UTC day; consecutive days grow the reward, missing a day resets it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local DailyStreak = require(ReplicatedStorage.Shared.Logic.DailyStreak)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local OfflineEarnings = require(ReplicatedStorage.Shared.Logic.OfflineEarnings)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local Analytics = require(script.Parent.Analytics)
local EconomyService = require(script.Parent.EconomyService)
local PlotService = require(script.Parent.PlotService)
local Remotes = require(script.Parent.Remotes)
local Sessions = require(script.Parent.Sessions)

type Session = Sessions.Session

local RetentionService = {}

-- PlayerLifecycle onJoined hook (income is already computed at this point).
function RetentionService.payOfflineEarnings(session: Session)
	local bonus = if session.passes.VIP then Monetization.perks.vipOfflineCapBonusSeconds else 0
	local result =
		OfflineEarnings.compute(session.lastSeenAtJoin, os.time(), session.incomePerSecond, Economy.offline, bonus)
	if result.amount > 0 then
		EconomyService.addCash(session, result.amount, "TimedReward", "Offline")
		session.pendingWelcome = { amount = result.amount, seconds = result.secondsAway }
	end
end

-- PlayerLifecycle onReady hook.
function RetentionService.sendWelcome(session: Session)
	local welcome = session.pendingWelcome
	if welcome then
		session.pendingWelcome = nil
		Remotes.fire(session.player, "WelcomeBack", welcome)
	end
end

local function onClaimDaily(player: Player)
	local session = Sessions.get(player)
	if session == nil then
		return
	end
	local claimed = DailyStreak.claim(session.data.daily, os.time())
	if claimed == nil then
		return
	end
	local slot = Economy.daily[DailyStreak.slot(claimed.streak, #Economy.daily)]
	local amount = DailyStreak.rewardAmount(slot, session.incomePerSecond)
	session.data.daily = claimed
	EconomyService.addCash(session, amount, "TimedReward", "Daily")
	Remotes.notify(
		player,
		Format.template(Theme.text.dailyClaimed, { day = claimed.streak, amount = UiTheme.cash(amount) }),
		"success"
	)
	if session.plot ~= 0 then
		Remotes.fire(player, "Effect", {
			kind = "daily",
			position = PlotService.refs(session.plot).spawnCFrame.Position,
		})
	end
	Analytics.custom(session, "daily_claim", claimed.streak)
end

function RetentionService.start()
	Remotes.onIntent("ClaimDaily", onClaimDaily)
end

return RetentionService
