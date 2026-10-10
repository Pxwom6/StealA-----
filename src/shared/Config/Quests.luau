--!strict
--[[
	Daily quests. Plain data only; rules in Logic/QuestRules, server in QuestService.

	Every UTC day each player gets one quest per entry in `slots` (2 easy + 1 hard), picked from `pool` by a seed of
	their UserId and the day, so the same player gets the same quests on every server that day (rejoining never
	re-rolls them). Two quests of the same kind are never picked together while another kind is left. Progress only
	counts what the server saw happen; it resets at UTC midnight, and anything finished but not claimed by then is paid
	automatically.

	  kind          counts                                                   target
	  beltPurchase  Snacklings bought from the belt (minRarity: that rarity    `target` purchases
	                id or rarer only)
	  collect       cash collected from your pads (not selling)             `incomeSeconds` of steady income when
	                                                                        the day's quests are rolled, >= `minimum`
	  sell          Snacklings sold                                          `target`
	  lock          base locks (Instant Lock included)                       `target`
	  steal         delivered steals                                         `target`
	  discover      new Snackdex entries: a new Snackling or a new           `target`
	                mutation of one

	Rewards are sized like cash packs from steady income (no LiveOps cash event, no friend & group bonus), never below
	the minimum. Finishing all three pays `allDoneBonus` once a day, with the last claim.
	Quest ids are saved in the day's list: never reuse an id for a different quest (a removed id simply stops counting
	until the next day). Text: the `quest*` keys in Config/Theme.
]]

local Types = require("../Types")

local Quests: Types.QuestsConfig = {
	slots = { "easy", "easy", "hard" },

	pool = {
		-- Easy: a few minutes of normal play.
		{ id = "buy_belt", kind = "beltPurchase", difficulty = "easy", textKey = "questBuy", target = 5 },
		{
			id = "collect_small",
			kind = "collect",
			difficulty = "easy",
			textKey = "questCollect",
			incomeSeconds = 5 * 60,
			minimum = 250,
		},
		{ id = "sell", kind = "sell", difficulty = "easy", textKey = "questSell", target = 2 },
		{ id = "lock", kind = "lock", difficulty = "easy", textKey = "questLock", target = 2 },

		-- Hard: needs a bit of luck, daring or a longer session.
		{ id = "steal", kind = "steal", difficulty = "hard", textKey = "questSteal", target = 1 },
		{
			id = "buy_rare",
			kind = "beltPurchase",
			difficulty = "hard",
			textKey = "questBuyRare",
			target = 1,
			minRarity = "Rare",
		},
		{ id = "discover", kind = "discover", difficulty = "hard", textKey = "questDiscover", target = 1 },
		{
			id = "collect_big",
			kind = "collect",
			difficulty = "hard",
			textKey = "questCollect",
			incomeSeconds = 20 * 60,
			minimum = 2500,
		},
	},

	rewards = {
		easy = { incomeSeconds = 3 * 60, minimum = 250 },
		hard = { incomeSeconds = 10 * 60, minimum = 1000 },
	},
	allDoneBonus = { incomeSeconds = 5 * 60, minimum = 500 },
}

return Quests
