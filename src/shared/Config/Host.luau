--!strict
--[[
	The host panel, cross-server LiveOps and global rare-pull shout-outs. Plain data only; the rules are in
	Logic/HostRules (who may do what, arguments, cooldowns) and Logic/CrossServerRules (messages between servers).

	Who may host (always checked on the server):
	  admins   Config/LiveOps.adminUserIds: everything, in any server, for "This server" or "All servers". In Studio
	           anyone is an admin, and "All servers" only ever reaches that Studio session.
	  owner    a private server's owner (game.PrivateServerId ~= "" and game.PrivateServerOwnerId == their UserId),
	           in their own server only: switch the map (cooldown `owner.mapCooldownSeconds`, the rotation's turn),
	           map rotation on/off, and start a modifier marked `hostable = true` in Config/Modifiers when none runs
	           (cooldown `owner.modifierCooldownSeconds`), and stop or replace one they started. No belt drops, boosts,
	           gifts, broadcasts or "All servers".
	  everyone else: nothing (the Settings row stays hidden and the HostAction intent is refused).

	limits are the ones the chat commands have always used (/mod 0.25-60 minutes, /luck up to the LiveOps luck cap for
	1-1440 minutes, /event 1 minute to 7 days); the panel and the commands clamp to the same numbers. A luck boost's
	remaining time is still capped at LiveOps.limits.maxBoostSeconds.

	"Gift everyone" pays each player in scope N minutes of their own steady income, sized like a cash pack
	(EconomyMath.cashPackAmount: at least N x gift.minimumPerMinute), N capped by limits.giftMinutes.

	messaging: "All servers" actions go out on `hostTopic`, shout-outs on `shoutTopic` (separate, so a busy evening of
	shout-outs can never crowd out an admin's message). Each message is one small versioned JSON table; receivers
	drop anything older than maxAgeSeconds (or dated more than maxFutureSeconds ahead), any id they have seen, and
	more than receiveBurst / receivePerMinute per topic. A server sends at most sendBurst / sendPerMinute admin
	actions. Roblox's own limit is 1 KB per message (maxBytes stays under it).

	shoutouts: a Secret Snackling (`rarity` or rarer), or a Mythic-or-rarer (`mutatedRarity`) with one of `mutations`,
	found any way but a steal (the belt, a Lucky Spin, a crate, a runaway, a Snack Attack, a gift, an achievement or a
	code; an admin drop doesn't count) tells every other server: "🌍 Bob found a SECRET Gelato Griffin in another
	server!". A server publishes at most one every publishEverySeconds and shows at most one every showEverySeconds,
	never to a player in the first-time tutorial.
]]

local Types = require("../Types")

local Host: Types.HostConfig = {
	owner = {
		-- as long as the rotation keeps a map (Config/MapThemes rotation.mapSeconds, CI): picking maps is never a
		-- faster way through them (the map achievements) or their signature mutations than the rotation
		mapCooldownSeconds = 20 * 60,
		modifierCooldownSeconds = 10 * 60,
	},
	admin = {
		giftCooldownSeconds = 30, -- a double tap must never pay everyone twice
	},

	limits = {
		modifierMinutes = { min = 0.25, max = 60, default = 5 },
		luckMultiplier = { min = 1, max = 6, default = 2 }, -- never above LiveOps.limits.maxLuckMultiplier (CI)
		luckMinutes = { min = 1, max = 24 * 60, default = 15 },
		eventMinutes = { min = 1, max = 7 * 24 * 60 },
		giftMinutes = { min = 1, max = 30, default = 5 },
		broadcastLength = 120, -- characters, as /announce
	},

	presets = {
		modifierMinutes = { 1, 2, 5, 10, 15, 30, 60 },
		luckMultiplier = { 2, 3, 4, 5, 6 },
		luckMinutes = { 5, 10, 15, 30, 60 },
		eventMinutes = { 15, 30, 60, 120, 240 },
		giftMinutes = { 1, 2, 5, 10, 15, 30 },
	},

	gift = {
		minimumPerMinute = 150, -- a 5-minute gift is at least $750 (cash packs: about $170-250 a minute)
	},

	messaging = {
		hostTopic = "SnacklingHost1",
		shoutTopic = "SnacklingShoutouts1",
		version = 1,
		maxAgeSeconds = 60,
		maxFutureSeconds = 15, -- server clocks agree to well under a second; anything further ahead is not ours
		rememberIds = 256,
		maxBytes = 900,
		sendBurst = 5,
		sendPerMinute = 6,
		receiveBurst = 20,
		receivePerMinute = 30,
	},

	shoutouts = {
		enabled = true,
		rarity = "Secret",
		mutatedRarity = "Mythic",
		mutations = { "diamond", "rainbow" },
		publishEverySeconds = 30,
		showEverySeconds = 20,
	},
}

return Host
