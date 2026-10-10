--!strict
--[[
	Batched player-state replication. Services call `markDirty(session)` whenever something the HUD shows
	changes; at most `Gameplay.replicationHz` times per second each dirty player receives ONE StateUpdate with
	their full (small) state. No per-frame traffic, no per-field remotes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Gameplay = require(ReplicatedStorage.Shared.Config.Gameplay)
local Social = require(ReplicatedStorage.Shared.Config.Social)
local DailyStreak = require(ReplicatedStorage.Shared.Logic.DailyStreak)
local EconomyMath = require(ReplicatedStorage.Shared.Logic.EconomyMath)
local RebirthMath = require(ReplicatedStorage.Shared.Logic.RebirthMath)
local SocialRules = require(ReplicatedStorage.Shared.Logic.SocialRules)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local Types = require(ReplicatedStorage.Shared.Types)
local Remotes = require(script.Parent.Remotes)
local Sessions = require(script.Parent.Sessions)

type Session = Sessions.Session

local Replication = {}

function Replication.markDirty(session: Session)
	session.dirty = true
end

function Replication.snapshot(session: Session): Types.ClientState
	local data = session.data
	local daily = DailyStreak.status(data.daily, os.time())
	local slot = Economy.daily[DailyStreak.slot(daily.nextStreak, #Economy.daily)]
	local carry = session.carry
	local social = session.social
	local friendBonus = SocialRules.friendBonus(social.friends, Social.friends)
	local groupBonus = SocialRules.groupBonus(social.groupMember, Social.group)
	return {
		cash = data.cash,
		income = session.incomePerSecond,
		multiplier = session.multiplier,
		rebirths = data.rebirths,
		rebirthMultiplier = data.rebirthMultiplier,
		rebirthCost = RebirthMath.cost(data.rebirths, Economy.rebirth) or -1,
		creatureCount = #data.creatures,
		capacity = session.capacity,
		packIncome = session.packIncome,
		podiumUpgrades = data.podiumUpgrades,
		nextPodiumCost = EconomyMath.podiumUpgradeCost(data.podiumUpgrades, Economy.podiumUpgrade) or -1,
		lockTokens = data.lockTokens,
		lockedUntil = session.lock.lockedUntil,
		lockCooldownUntil = session.lock.cooldownUntil,
		lockVulnerableUntil = session.lock.vulnerableUntil,
		lockDuration = session.lockDuration,
		graceUntil = session.graceUntil,
		plot = session.plot,
		passes = session.passes,
		carrying = if carry then carry.creatureId else "",
		stealCooldownUntil = session.stealCooldownUntil,
		steals = data.stats.steals,
		daily = {
			canClaim = daily.canClaim,
			streak = data.daily.streak,
			nextStreak = daily.nextStreak,
			secondsUntilNext = daily.secondsUntilNext,
			reward = DailyStreak.rewardAmount(slot, session.rewardIncome), -- as RetentionService pays it
		},
		social = {
			friends = social.friends,
			friendBonus = friendBonus,
			groupMember = social.groupMember,
			groupBonus = groupBonus,
			bonus = friendBonus + groupBonus,
			groupRewardClaimed = data.flags[SocialRules.GROUP_WELCOME_FLAG] == true,
		},
	}
end

local function updateLeaderstats(session: Session)
	local stats = session.player:FindFirstChild("leaderstats")
	if stats == nil then
		return
	end
	local cash = stats:FindFirstChild("Cash")
	if cash and cash:IsA("StringValue") then
		cash.Value = Format.cash(session.data.cash, Theme.currencySymbol)
	end
	local steals = stats:FindFirstChild("Steals")
	if steals and steals:IsA("IntValue") then
		steals.Value = session.data.stats.steals
	end
end

function Replication.flush(session: Session)
	session.dirty = false
	updateLeaderstats(session)
	if session.ready then
		Remotes.fire(session.player, "StateUpdate", Replication.snapshot(session))
	end
end

function Replication.start()
	task.spawn(function()
		local interval = 1 / Gameplay.replicationHz
		while true do
			task.wait(interval)
			for _, session in Sessions.all() do
				if session.dirty then
					Replication.flush(session)
				end
			end
		end
	end)
end

return Replication
