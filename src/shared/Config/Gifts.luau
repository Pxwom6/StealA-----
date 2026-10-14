--!strict
--[[
	Playtime gifts: a ladder that unlocks with the time a player spends in game each UTC day (Rewards panel, Gifts
	tab). Each gift is claimed once per day, in any order once unlocked; at UTC midnight unclaimed unlocked gifts are
	paid automatically and the ladder starts again. Time counts while the player is in game (Logic/GiftRules).

	Rewards (Types.PrizeReward): cash sized from steady income like a cash pack ({ kind = "cash", incomeSeconds,
	minimum }), Lucky Spins ({ kind = "spin", count }), or a Snackling rolled at extra luck ({ kind = "creature",
	luck }; sold for its refund when the base is full). Balance notes: BALANCE.md "Playtime gifts and the Lucky Spin".
]]

local Types = require("../Types")

local Gifts: Types.GiftsConfig = {
	ladder = {
		{ minutes = 5, icon = "💵", reward = { kind = "cash", incomeSeconds = 30, minimum = 150 } },
		{ minutes = 10, icon = "🎰", reward = { kind = "spin", count = 1 } },
		{ minutes = 15, icon = "💰", reward = { kind = "cash", incomeSeconds = 60, minimum = 400 } },
		{ minutes = 25, icon = "🎁", reward = { kind = "creature", luck = 2 } },
		{ minutes = 40, icon = "🎰", reward = { kind = "spin", count = 2 } },
		{ minutes = 60, icon = "🎁", reward = { kind = "creature", luck = 4 } },
	},
}

return Gifts
