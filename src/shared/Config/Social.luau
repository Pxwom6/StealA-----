--!strict
--[[
	Friend & group rewards. Plain data only. Rules: Logic/SocialRules; server: SocialService; UI: SocialController.

	* Friends: every Roblox friend playing in the same server adds `incomeBonusPerFriend` to your income, up to
	  `maxFriends` friends. Nothing is ever given for sending invites (the Invite button only opens Roblox's prompt).
	* Group: members of the owner's Roblox group earn `incomeBonus` more while they play, and get a one-time welcome
	  reward (once per account, remembered in the save).

	The social bonus only raises live income: cash packs, daily rewards, offline earnings and the best cash/sec stat
	are sized without it (see DECISIONS.md #19).
]]

local Types = require("../Types")

local Social: Types.SocialConfig = {
	friends = {
		incomeBonusPerFriend = 0.10, -- +10% income per friend in the server...
		maxFriends = 3, -- ...counting at most this many (so at most +30%)
		-- Roblox's friend check is a web call that can fail: retry a pair this many times in total, this far apart.
		checkAttempts = 3,
		retrySeconds = 15,
	},

	group = {
		-- TODO(owner): paste your Roblox group's ID here (the number in its URL:
		-- roblox.com/communities/<groupId>/...). While it is 0 the whole group feature is off and its UI is hidden.
		groupId = 0,
		incomeBonus = 0.10, -- +10% income while the player is a member
		-- One-time welcome reward for members, paid once per account: N seconds of the player's steady income (the
		-- same basis as cash packs), never below the minimum. Set to nil to turn it off.
		welcomeReward = { incomeSeconds = 10 * 60, minimum = 1000 },
		-- After joining in-game the client asks the server to check again; at most once per this many seconds.
		recheckCooldownSeconds = 10,
		checkAttempts = 3,
		retrySeconds = 15,
	},
}

return Social
