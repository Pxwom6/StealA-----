--!strict
--[[
	Friend & group rewards (Config/Social, rules in Logic/SocialRules).

	* Friends: when a session starts, the server asks Roblox (Player:IsFriendsWithAsync) about each pair it forms with
	  the players already here. Answers are cached per pair while both players stay, failed calls are retried a few
	  times, and Studio's local test players (UserIds <= 0) are never asked about. Friend counts are recounted when an
	  answer arrives and when someone leaves, and both friends get a toast.
	* Group (only when Config/Social.group.groupId is set): Player:IsInGroupAsync on join (retried on failure), and
	  again on the client's CheckGroup intent after the in-game join prompt (at most once per
	  recheckCooldownSeconds). Members earn the group bonus and, once per account, a welcome reward (save flag).

	Every Roblox call is pcall'd and runs in its own thread, so a slow or failing web call never blocks the join
	flow, and an answer that arrives after either player left is dropped. Any change calls EconomyService.refresh,
	which updates income, podium signs and the HUD.
]]

local GroupService = game:GetService("GroupService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Social = require(ReplicatedStorage.Shared.Config.Social)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local SocialRules = require(ReplicatedStorage.Shared.Logic.SocialRules)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local Analytics = require(script.Parent.Analytics)
local EconomyService = require(script.Parent.EconomyService)
local Remotes = require(script.Parent.Remotes)
local Sessions = require(script.Parent.Sessions)

type Session = Sessions.Session

-- One pair of players in the server. `friends` stays nil until Roblox answers (or if it never does): not friends.
type Friendship = { a: Session, b: Session, friends: boolean? }

type GroupCheck = { checking: boolean, lastCheckAt: number }

local SocialService = {}

local friendships: { [string]: Friendship } = {}
local groupChecks: { [Session]: GroupCheck } = {}
local studioFriendCounts: { [Session]: number? } = {} -- /friends dev command (Studio test players can't be friends)

local function isCurrent(session: Session): boolean
	return Sessions.getByUserId(session.userId) == session
end

local function countFriends(session: Session): number
	local override = studioFriendCounts[session]
	if override then
		return override
	end
	local others: { number } = {}
	for _, other in Sessions.all() do
		if other ~= session then
			table.insert(others, other.userId)
		end
	end
	local answers: { [string]: boolean } = {}
	for key, friendship in friendships do
		answers[key] = friendship.friends == true
	end
	return SocialRules.countFriends(session.userId, others, answers)
end

-- Recounts a session's friends and refreshes its income when the count changed. Returns the counts before / after.
local function recount(session: Session): (number, number)
	local before = session.social.friends
	local after = countFriends(session)
	if after ~= before then
		session.social.friends = after
		EconomyService.refresh(session)
	end
	return before, after
end

local function friendPercent(count: number): number
	return SocialRules.percent(SocialRules.friendBonus(count, Social.friends))
end

-- A friend of `session` arrived: recount and tell them. `isNewcomer`: `session` is the one who just joined.
local function welcomeFriend(session: Session, friend: Session, isNewcomer: boolean)
	local _, after = recount(session)
	local template = if isNewcomer then Theme.text.socialFriendHere else Theme.text.socialFriendJoined
	Remotes.notify(
		session.player,
		Format.template(template, { name = friend.player.DisplayName, percent = friendPercent(after) }),
		"success"
	)
end

local function checkFriendship(friendship: Friendship, key: string, attempt: number)
	if friendships[key] ~= friendship then
		return -- one of them left (and perhaps came back) since this check was queued
	end
	local a, b = friendship.a, friendship.b
	local ok, result = pcall(function(): boolean
		return a.player:IsFriendsWithAsync(b.userId)
	end)
	if friendships[key] ~= friendship then
		return -- one of them left while Roblox was answering
	end
	if not ok then
		if attempt < Social.friends.checkAttempts then
			task.delay(Social.friends.retrySeconds, checkFriendship, friendship, key, attempt + 1)
		end
		return -- after the last attempt they simply don't count as friends this session
	end
	friendship.friends = result == true
	if friendship.friends then
		local aIsNewer = a.joinedAt >= b.joinedAt
		local newcomer = if aIsNewer then a else b
		local other = if aIsNewer then b else a
		welcomeFriend(other, newcomer, false)
		welcomeFriend(newcomer, other, true)
	end
end

-- Group membership ----------------------------------------------------------------------------------------------

-- Fresh membership from the group list (a different lookup than IsInGroupAsync, in case that one is cached on the
-- server). nil when the call failed.
local function listedInGroup(userId: number): boolean?
	local ok, groups = pcall(function(): { any }
		return GroupService:GetGroupsAsync(userId)
	end)
	if not ok or type(groups) ~= "table" then
		return nil
	end
	for _, group in groups do
		if type(group) == "table" and group.Id == Social.group.groupId then
			return true
		end
	end
	return false
end

local function grantGroupWelcome(session: Session)
	if not SocialRules.canClaimGroupWelcome(session.data.flags, session.social.groupMember, Social.group) then
		return
	end
	-- Sized from the steady income (no events, no social bonus), like a cash pack. Flag first, then pay: no yield in
	-- between, so it can only ever be paid once per account.
	local amount = SocialRules.groupWelcomeAmount(session.packIncome, Social.group)
	session.data.flags[SocialRules.GROUP_WELCOME_FLAG] = true
	EconomyService.addCash(session, amount, "Onboarding", "GroupWelcome")
	Remotes.notify(
		session.player,
		Format.template(Theme.text.socialGroupWelcome, { amount = UiTheme.cash(amount) }),
		"success"
	)
	Analytics.custom(session, "group_reward_claimed", amount)
end

local function setGroupMember(session: Session, isMember: boolean)
	if session.social.groupMember ~= isMember then
		session.social.groupMember = isMember
		EconomyService.refresh(session)
	end
	grantGroupWelcome(session)
end

-- `manual`: the player asked (CheckGroup), so they get an answer either way and the group list is consulted too.
local function checkGroup(session: Session, manual: boolean, attempt: number)
	local check = groupChecks[session]
	if check == nil or not isCurrent(session) then
		return
	end
	check.checking = true
	local groupId = Social.group.groupId
	local ok, result = pcall(function(): boolean
		return session.player:IsInGroupAsync(groupId)
	end)
	local isMember = ok and result == true
	if manual and not isMember then
		local listed = listedInGroup(session.userId)
		if listed ~= nil then
			ok = true
			isMember = listed
		end
	end
	check.checking = false
	if groupChecks[session] ~= check or not isCurrent(session) then
		return -- left while Roblox was answering
	end
	if not ok then
		if manual then
			Remotes.notify(session.player, Theme.text.socialGroupCheckFailed, "error")
		elseif attempt < Social.group.checkAttempts then
			task.delay(Social.group.retrySeconds, checkGroup, session, false, attempt + 1)
		end
		return
	end
	local wasMember = session.social.groupMember
	setGroupMember(session, isMember)
	if manual and isMember and not wasMember then
		Remotes.notify(
			session.player,
			Format.template(Theme.text.socialGroupJoined, {
				percent = SocialRules.percent(SocialRules.groupBonus(true, Social.group)),
			}),
			"success"
		)
	elseif manual and not isMember then
		Remotes.notify(session.player, Theme.text.socialGroupNotYet, "info")
	end
end

local function onCheckGroup(player: Player)
	local session = Sessions.get(player)
	if session == nil or not SocialRules.groupEnabled(Social.group) then
		return
	end
	local check = groupChecks[session]
	if check == nil or check.checking then
		return
	end
	if session.social.groupMember then
		grantGroupWelcome(session) -- nothing to look up; just make sure the welcome reward was paid
		return
	end
	local now = os.clock()
	if not SocialRules.canRecheckGroup(check.lastCheckAt, now, Social.group.recheckCooldownSeconds) then
		Remotes.notify(player, Theme.text.socialGroupCheckWait, "info")
		return
	end
	check.lastCheckAt = now
	checkGroup(session, true, 1)
end

local function onInvitePrompted(player: Player)
	local session = Sessions.get(player)
	if session then
		Analytics.custom(session, "invite_prompt_opened", session.social.friends)
	end
end

-- Lifecycle hooks -----------------------------------------------------------------------------------------------

-- PlayerLifecycle onJoined hook. Never yields: every Roblox call runs in its own thread.
function SocialService.onJoined(session: Session)
	groupChecks[session] = { checking = false, lastCheckAt = -math.huge }
	for _, other in Sessions.all() do
		if other == session or not SocialRules.canBeFriends(session.userId, other.userId) then
			continue
		end
		local key = SocialRules.pairKey(session.userId, other.userId)
		local existing = friendships[key]
		if existing and (existing.a == other or existing.b == other) then
			continue -- the other player's join already asked about this pair (both joined at once)
		end
		local friendship: Friendship = { a = session, b = other, friends = nil }
		friendships[key] = friendship
		task.spawn(checkFriendship, friendship, key, 1)
	end
	if SocialRules.groupEnabled(Social.group) then
		task.spawn(checkGroup, session, false, 1)
	end
end

-- PlayerLifecycle onLeaving hook: forget the player's pairs and tell their friends.
function SocialService.onLeaving(session: Session)
	groupChecks[session] = nil
	studioFriendCounts[session] = nil
	local friendsLeftBehind: { Session } = {}
	for key, friendship in friendships do
		if friendship.a == session or friendship.b == session then
			friendships[key] = nil
			if friendship.friends == true then
				table.insert(friendsLeftBehind, if friendship.a == session then friendship.b else friendship.a)
			end
		end
	end
	for _, friend in friendsLeftBehind do
		if isCurrent(friend) then
			local _, after = recount(friend)
			local percent = friendPercent(after)
			local template = if percent > 0 then Theme.text.socialFriendLeft else Theme.text.socialFriendLeftNoBonus
			Remotes.notify(
				friend.player,
				Format.template(template, { name = session.player.DisplayName, percent = percent }),
				"info"
			)
		end
	end
end

-- Studio only (DevCommands /friends): pretend `count` friends are here, or nil to go back to real friends.
function SocialService.devSetFriends(session: Session, count: number?)
	if not RunService:IsStudio() then
		return
	end
	studioFriendCounts[session] = count
	recount(session)
end

function SocialService.start()
	Remotes.onIntent("CheckGroup", onCheckGroup)
	Remotes.onIntent("InvitePrompted", onInvitePrompted)
end

return SocialService
