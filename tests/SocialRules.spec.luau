--!strict
local T = require("./TestKit")
local SocialRules = require("../src/shared/Logic/SocialRules")
local EconomyMath = require("../src/shared/Logic/EconomyMath")
local DailyStreak = require("../src/shared/Logic/DailyStreak")
local OfflineEarnings = require("../src/shared/Logic/OfflineEarnings")
local Social = require("../src/shared/Config/Social")
local Types = require("../src/shared/Types")

local friends: Types.FriendsConfig =
	{ incomeBonusPerFriend = 0.1, maxFriends = 3, checkAttempts = 3, retrySeconds = 15 }

local function group(groupId: number, reward: Types.GroupWelcomeReward?): Types.GroupConfig
	return {
		groupId = groupId,
		incomeBonus = 0.1,
		welcomeReward = reward,
		recheckCooldownSeconds = 10,
		checkAttempts = 3,
		retrySeconds = 15,
	}
end

local function config(groupId: number): Types.SocialConfig
	return { friends = friends, group = group(groupId, { incomeSeconds = 600, minimum = 1000 }) }
end

T.describe("SocialRules friend bonus", function()
	T.it("gives +10% per friend in the server", function()
		T.expect(SocialRules.friendBonus(0, friends)).toBe(0)
		T.expect(SocialRules.friendBonus(1, friends)).toBeNear(0.1)
		T.expect(SocialRules.friendBonus(2, friends)).toBeNear(0.2)
		T.expect(SocialRules.friendBonus(3, friends)).toBeNear(0.3)
	end)
	T.it("stops counting at maxFriends", function()
		T.expect(SocialRules.friendBonus(4, friends)).toBeNear(0.3)
		T.expect(SocialRules.friendBonus(7, friends)).toBeNear(0.3)
		T.expect(SocialRules.countedFriends(7, friends)).toBe(3)
	end)
	T.it("never goes negative or NaN on garbage counts", function()
		T.expect(SocialRules.friendBonus(-2, friends)).toBe(0)
		T.expect(SocialRules.friendBonus(0 / 0, friends)).toBe(0)
		T.expect(SocialRules.friendBonus(math.huge, friends)).toBe(0)
		T.expect(SocialRules.friendBonus(1.7, friends)).toBeNear(0.1)
	end)
end)

T.describe("SocialRules group bonus", function()
	T.it("is off while the group id is 0 (owner hasn't set one)", function()
		T.expect(SocialRules.groupEnabled(group(0))).toBe(false)
		T.expect(SocialRules.groupBonus(true, group(0))).toBe(0)
		T.expect(SocialRules.groupEnabled(group(-5))).toBe(false)
		T.expect(SocialRules.groupEnabled(group(1.5))).toBe(false)
		T.expect(SocialRules.groupEnabled(group(0 / 0))).toBe(false)
	end)
	T.it("gives members +10% once a group id is set", function()
		T.expect(SocialRules.groupEnabled(group(12345))).toBe(true)
		T.expect(SocialRules.groupBonus(true, group(12345))).toBeNear(0.1)
		T.expect(SocialRules.groupBonus(false, group(12345))).toBe(0)
	end)
end)

T.describe("SocialRules total bonus", function()
	T.it("adds friends and group", function()
		T.expect(SocialRules.totalBonus(2, true, config(12345))).toBeNear(0.3)
		T.expect(SocialRules.totalBonus(5, true, config(12345))).toBeNear(0.4)
		T.expect(SocialRules.totalBonus(5, true, config(0))).toBeNear(0.3) -- no group configured: friends only
		T.expect(SocialRules.totalBonus(0, false, config(12345))).toBe(0)
	end)
	T.it("is capped at +40% with the group on, +30% without", function()
		T.expect(SocialRules.maxBonus(config(12345))).toBeNear(0.4)
		T.expect(SocialRules.maxBonus(config(0))).toBeNear(0.3)
	end)
	T.it("formats as whole percentages", function()
		T.expect(SocialRules.percent(0.3)).toBe(30)
		T.expect(SocialRules.percent(0.1 + 0.2)).toBe(30)
		T.expect(SocialRules.percent(0)).toBe(0)
		T.expect(SocialRules.percent(0 / 0)).toBe(0)
	end)
end)

T.describe("SocialRules friend checks", function()
	T.it("only asks Roblox about real, distinct accounts", function()
		T.expect(SocialRules.canBeFriends(10, 20)).toBe(true)
		T.expect(SocialRules.canBeFriends(10, 10)).toBe(false)
		T.expect(SocialRules.canBeFriends(-1, 20)).toBe(false) -- Studio local test players
		T.expect(SocialRules.canBeFriends(-1, -2)).toBe(false)
		T.expect(SocialRules.canBeFriends(0, 20)).toBe(false)
	end)
	T.it("uses one key per pair, in either order", function()
		T.expect(SocialRules.pairKey(20, 10)).toBe(SocialRules.pairKey(10, 20))
		T.expect(SocialRules.pairKey(10, 20)).toBe("10:20")
	end)
	T.it("counts only confirmed friends among the others in the server", function()
		local friendships = {
			[SocialRules.pairKey(1, 2)] = true,
			[SocialRules.pairKey(1, 3)] = false,
			[SocialRules.pairKey(4, 1)] = true,
			[SocialRules.pairKey(2, 3)] = true,
		}
		T.expect(SocialRules.countFriends(1, { 2, 3, 4, 5 }, friendships)).toBe(2) -- 5 unchecked: not yet
		T.expect(SocialRules.countFriends(1, { 1, 2 }, friendships)).toBe(1) -- never counts yourself
		T.expect(SocialRules.countFriends(3, { 1, 2, 4 }, friendships)).toBe(1)
		T.expect(SocialRules.countFriends(1, {}, friendships)).toBe(0)
		-- a friend who left is simply no longer among the others
		T.expect(SocialRules.countFriends(1, { 2, 3 }, friendships)).toBe(1)
	end)
	T.it("describes how a friend joining or leaving changed the bonus", function()
		T.expect(SocialRules.friendChange(0, 1, friends)).toBe("gained")
		T.expect(SocialRules.friendChange(3, 4, friends)).toBe("unchanged") -- already at the cap
		T.expect(SocialRules.friendChange(4, 3, friends)).toBe("unchanged") -- still at the cap
		T.expect(SocialRules.friendChange(3, 2, friends)).toBe("lost")
	end)
end)

T.describe("SocialRules group welcome reward", function()
	local reward = { incomeSeconds = 600, minimum = 1000 }
	T.it("is paid once per account, to members, only when the group is on", function()
		local enabled = group(12345, reward)
		T.expect(SocialRules.canClaimGroupWelcome({}, true, enabled)).toBe(true)
		T.expect(SocialRules.canClaimGroupWelcome({}, false, enabled)).toBe(false)
		T.expect(SocialRules.canClaimGroupWelcome({ [SocialRules.GROUP_WELCOME_FLAG] = true }, true, enabled))
			.toBe(false)
		T.expect(SocialRules.canClaimGroupWelcome({}, true, group(0, reward))).toBe(false)
		T.expect(SocialRules.canClaimGroupWelcome({}, true, group(12345, nil))).toBe(false) -- reward turned off
	end)
	T.it("is 10 minutes of steady income, at least the minimum, rounded like cash packs", function()
		local enabled = group(12345, reward)
		T.expect(SocialRules.groupWelcomeAmount(0, enabled)).toBe(1000)
		T.expect(SocialRules.groupWelcomeAmount(1, enabled)).toBe(1000)
		T.expect(SocialRules.groupWelcomeAmount(100, enabled)).toBe(60000)
		T.expect(SocialRules.groupWelcomeAmount(123, enabled)).toBe(73000) -- 73,800 rounded down
		T.expect(SocialRules.groupWelcomeAmount(0 / 0, enabled)).toBe(1000)
		T.expect(SocialRules.groupWelcomeAmount(100, group(12345, nil))).toBe(0)
	end)
	T.it("limits 'check again' to once per cooldown", function()
		T.expect(SocialRules.canRecheckGroup(-math.huge, 5, 10)).toBe(true)
		T.expect(SocialRules.canRecheckGroup(100, 105, 10)).toBe(false)
		T.expect(SocialRules.canRecheckGroup(100, 110, 10)).toBe(true)
		T.expect(SocialRules.canRecheckGroup(100, 50, 10)).toBe(true) -- clock went backwards
	end)
end)

T.describe("Social bonus in the economy", function()
	-- A player with a rebirth, 2x Cash and VIP, mid LiveOps 2x cash event.
	local function inputs(socialBonus: number): EconomyMath.MultiplierInputs
		return {
			rebirthMultiplier = 1.5,
			hasDoubleCash = true,
			doubleCashMultiplier = 2,
			isVip = true,
			vipIncomeBonus = 0.1,
			eventCashMultiplier = 2,
			socialBonus = socialBonus,
		}
	end
	local withFriends = inputs(SocialRules.totalBonus(3, true, config(12345))) -- the +40% maximum
	local alone = inputs(0)

	T.it("multiplies live income by (1 + bonus) on top of every other multiplier", function()
		T.expect(EconomyMath.incomeMultiplier(withFriends)).toBeNear(1.5 * 2 * 1.1 * 2 * 1.4)
		T.expect(EconomyMath.incomeMultiplier(inputs(0.2)) / EconomyMath.incomeMultiplier(alone)).toBeNear(1.2)
		T.expect(EconomyMath.incomeMultiplier(alone)).toBeNear(1.5 * 2 * 1.1 * 2)
	end)
	T.it("ignores a garbage bonus instead of producing NaN or a penalty", function()
		T.expect(EconomyMath.incomeMultiplier(inputs(0 / 0))).toBeNear(EconomyMath.incomeMultiplier(alone))
		T.expect(EconomyMath.incomeMultiplier(inputs(-0.5))).toBeNear(EconomyMath.incomeMultiplier(alone))
		T.expect(EconomyMath.incomeMultiplier(inputs(math.huge))).toBeNear(EconomyMath.incomeMultiplier(alone))
	end)
	T.it("is left out of the steady multiplier, so cash packs can't be inflated by friends", function()
		T.expect(EconomyMath.permanentMultiplier(withFriends)).toBeNear(1.5 * 2 * 1.1) -- no event, no social
		T.expect(EconomyMath.permanentMultiplier(withFriends)).toBe(EconomyMath.permanentMultiplier(alone))
		local sources: { EconomyMath.PackSource } = {
			{ baseIncome = 100, podium = 1, inTransit = false },
			{ baseIncome = 50, podium = 2, inTransit = false },
		}
		local pack = { incomeSeconds = 3600, minimum = 15000 }
		local packWithFriends = EconomyMath.cashPackAmount(
			EconomyMath.packIncome(sources, 8, EconomyMath.permanentMultiplier(withFriends)),
			pack
		)
		local packAlone =
			EconomyMath.cashPackAmount(EconomyMath.packIncome(sources, 8, EconomyMath.permanentMultiplier(alone)), pack)
		T.expect(packWithFriends).toBe(packAlone)
		T.expect(withFriends.socialBonus).toBeNear(0.4) -- the caller's inputs are not modified
	end)
	T.it("is left out of daily rewards, offline earnings and saved stats (rewardMultiplier)", function()
		T.expect(EconomyMath.rewardMultiplier(withFriends)).toBe(EconomyMath.rewardMultiplier(alone))
		T.expect(EconomyMath.rewardMultiplier(withFriends)).toBe(EconomyMath.incomeMultiplier(alone)) -- event stays
		local incomes = { 100, 50, 7 }
		local rewardIncomeWithFriends = EconomyMath.totalIncome(incomes, EconomyMath.rewardMultiplier(withFriends))
		local rewardIncomeAlone = EconomyMath.totalIncome(incomes, EconomyMath.rewardMultiplier(alone))
		T.expect(rewardIncomeWithFriends).toBe(rewardIncomeAlone)
		T.expect(EconomyMath.totalIncome(incomes, EconomyMath.incomeMultiplier(withFriends)))
			.toBeGreaterThan(rewardIncomeWithFriends) -- live income does get the bonus
		local slot = { minimum = 250, incomeMinutes = 3 }
		T.expect(DailyStreak.rewardAmount(slot, rewardIncomeWithFriends))
			.toBe(DailyStreak.rewardAmount(slot, rewardIncomeAlone))
		local offline = { rate = 0.5, capSeconds = 7200, minSecondsAway = 120 }
		T.expect(OfflineEarnings.compute(1000, 5000, rewardIncomeWithFriends, offline).amount)
			.toBe(OfflineEarnings.compute(1000, 5000, rewardIncomeAlone, offline).amount)
	end)
	T.it("sizes the group welcome reward from the steady income too", function()
		local sources: { EconomyMath.PackSource } = { { baseIncome = 100, podium = 1, inTransit = false } }
		local steady = EconomyMath.packIncome(sources, 8, EconomyMath.permanentMultiplier(withFriends))
		T.expect(SocialRules.groupWelcomeAmount(steady, config(12345).group)).toBe(190000) -- 100 * 3.3 * 600
	end)
end)

T.describe("Config/Social", function()
	T.it("passes validation", function()
		T.expect(#SocialRules.validate(Social)).toBe(0)
	end)
	T.it("validation catches bad values", function()
		local bad: Types.SocialConfig = {
			friends = { incomeBonusPerFriend = 5, maxFriends = 1.5, checkAttempts = 0, retrySeconds = 1 },
			group = group(-1, { incomeSeconds = -1, minimum = 0 }),
		}
		T.expect(#SocialRules.validate(bad)).toBe(5)
	end)
	T.it("keeps the shipped bonus modest (not pay-to-win, not a must-have)", function()
		T.expect(SocialRules.maxBonus(Social)).toBeAtMost(0.5)
	end)
end)

return nil
