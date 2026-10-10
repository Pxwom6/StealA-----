--!strict
--[[
	Friend & group rewards (Config/Social): the income bonus from Roblox friends playing in the same server and from
	membership of the owner's Roblox group, and the one-time group welcome reward. Pure: no Roblox APIs.

	The social bonus is temporary (it depends on who happens to be in the server), so it only raises live income.
	EconomyMath leaves it out of everything sized from income and paid or saved for later: cash packs
	(permanentMultiplier / packIncome) and daily rewards, offline earnings and the best cash/sec stat
	(rewardMultiplier).
]]

local Types = require("../Types")
local EconomyMath = require("./EconomyMath")

export type SocialConfig = Types.SocialConfig
export type FriendsConfig = Types.FriendsConfig
export type GroupConfig = Types.GroupConfig

local SocialRules = {}

-- Save flag (data.flags) set when the one-time group welcome reward is paid.
SocialRules.GROUP_WELCOME_FLAG = "social_groupWelcome"

local function finite(value: number, fallback: number): number
	if value ~= value or value == math.huge or value == -math.huge then
		return fallback
	end
	return value
end

-- Friends that count towards the bonus: whole, never negative, at most maxFriends.
function SocialRules.countedFriends(friendCount: number, cfg: FriendsConfig): number
	local cap = math.max(0, math.floor(finite(cfg.maxFriends, 0)))
	return math.clamp(math.floor(finite(friendCount, 0)), 0, cap)
end

-- Income bonus (0.2 = +20%) from `friendCount` friends in the server.
function SocialRules.friendBonus(friendCount: number, cfg: FriendsConfig): number
	return SocialRules.countedFriends(friendCount, cfg) * math.max(0, finite(cfg.incomeBonusPerFriend, 0))
end

-- The group feature is on only once the owner has set a real group id.
function SocialRules.groupEnabled(cfg: GroupConfig): boolean
	local id = cfg.groupId
	return id == id and id > 0 and id ~= math.huge and id == math.floor(id)
end

function SocialRules.groupBonus(isMember: boolean, cfg: GroupConfig): number
	if not isMember or not SocialRules.groupEnabled(cfg) then
		return 0
	end
	return math.max(0, finite(cfg.incomeBonus, 0))
end

-- The whole social bonus: friends and group add up (EconomyMath.MultiplierInputs.socialBonus).
function SocialRules.totalBonus(friendCount: number, isMember: boolean, cfg: SocialConfig): number
	return SocialRules.friendBonus(friendCount, cfg.friends) + SocialRules.groupBonus(isMember, cfg.group)
end

-- The largest bonus the config allows (all friends counted, group member if the group is on).
function SocialRules.maxBonus(cfg: SocialConfig): number
	return SocialRules.totalBonus(cfg.friends.maxFriends, true, cfg)
end

-- A bonus as a whole percentage for display (0.3 -> 30).
function SocialRules.percent(bonus: number): number
	return math.floor(finite(bonus, 0) * 100 + 0.5)
end

-- Whether to ask Roblox if two players are friends at all: only real, distinct accounts (Studio's local test players
-- have UserIds <= 0 and can't be anyone's friend).
function SocialRules.canBeFriends(userIdA: number, userIdB: number): boolean
	return userIdA > 0 and userIdB > 0 and userIdA ~= userIdB
end

-- One cache key per pair of players, whichever order they come in.
function SocialRules.pairKey(userIdA: number, userIdB: number): string
	return `{math.min(userIdA, userIdB)}:{math.max(userIdA, userIdB)}`
end

-- How many of `others` (UserIds in the server) are known friends of `userId`. `friendships` maps pairKey to the
-- answer Roblox gave; pairs not checked yet (or whose check failed) are not friends for now.
function SocialRules.countFriends(userId: number, others: { number }, friendships: { [string]: boolean }): number
	local count = 0
	for _, other in others do
		if other ~= userId and friendships[SocialRules.pairKey(userId, other)] == true then
			count += 1
		end
	end
	return count
end

-- How a friend joining or leaving changed the friend bonus, so the toast can say the right thing.
export type FriendChange = "gained" | "lost" | "unchanged"

function SocialRules.friendChange(countBefore: number, countAfter: number, cfg: FriendsConfig): FriendChange
	local before = SocialRules.friendBonus(countBefore, cfg)
	local after = SocialRules.friendBonus(countAfter, cfg)
	if after > before then
		return "gained"
	elseif after < before then
		return "lost"
	end
	return "unchanged"
end

-- The one-time group welcome reward is due: the group is on, the reward is configured, the player is a member and
-- this account was never paid it.
function SocialRules.canClaimGroupWelcome(flags: { [string]: boolean }, isMember: boolean, cfg: GroupConfig): boolean
	return SocialRules.groupEnabled(cfg)
		and cfg.welcomeReward ~= nil
		and isMember
		and flags[SocialRules.GROUP_WELCOME_FLAG] ~= true
end

-- The welcome reward for a player whose steady income (EconomyMath.packIncome: no events, no social bonus) is
-- `steadyIncome` per second. 0 when the reward is turned off.
function SocialRules.groupWelcomeAmount(steadyIncome: number, cfg: GroupConfig): number
	local reward = cfg.welcomeReward
	if reward == nil then
		return 0
	end
	return EconomyMath.cashPackAmount(steadyIncome, reward)
end

-- A "check my group membership again" request is allowed `cooldown` seconds after the previous one.
function SocialRules.canRecheckGroup(lastCheckAt: number, now: number, cooldown: number): boolean
	return now - lastCheckAt >= cooldown or now < lastCheckAt -- a clock that went backwards never locks it forever
end

-- Problems with a social config (empty when valid). Checked by CI so a typo can't ship.
function SocialRules.validate(cfg: SocialConfig): { string }
	local problems: { string } = {}
	local friends, group = cfg.friends, cfg.group
	local function check(ok: boolean, message: string)
		if not ok then
			table.insert(problems, message)
		end
	end
	check(friends.incomeBonusPerFriend >= 0 and friends.incomeBonusPerFriend <= 1, "friends.incomeBonusPerFriend")
	check(friends.maxFriends >= 0 and friends.maxFriends == math.floor(friends.maxFriends), "friends.maxFriends")
	check(friends.checkAttempts >= 1 and friends.retrySeconds > 0, "friends retry settings")
	check(group.groupId >= 0 and group.groupId == math.floor(group.groupId), "group.groupId")
	check(group.incomeBonus >= 0 and group.incomeBonus <= 1, "group.incomeBonus")
	check(group.recheckCooldownSeconds >= 1, "group.recheckCooldownSeconds")
	check(group.checkAttempts >= 1 and group.retrySeconds > 0, "group retry settings")
	local reward = group.welcomeReward
	if reward then
		check(reward.incomeSeconds >= 0 and reward.minimum >= 0, "group.welcomeReward")
	end
	return problems
end

return SocialRules
