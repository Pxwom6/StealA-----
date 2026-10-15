--!strict
--[[
	The Lucky Spin (Rewards panel, Spin tab): a reel of prizes. Everyone gets a free spin every `freeEverySeconds`
	(a new player's first one is ready at once), and playtime gifts (Config/Gifts) bank extra spins. The server picks
	the prize by weight (chance = weight / total of all weights) and pays at once; the reel animation only shows it.

	Prizes (Types.PrizeReward): cash sized from steady income like a cash pack, or a Snackling rolled at extra luck,
	optionally always with a mutation (sold for its refund when the base is full). Balance notes: BALANCE.md
	"Playtime gifts and the Lucky Spin". CI checks this file (Logic/SpinRules.validate).
]]

local Types = require("../Types")

local Spin: Types.SpinConfig = {
	freeEverySeconds = 12 * 3600,
	maxBanked = 20,
	bankedOverflow = { incomeSeconds = 60, minimum = 400 },
	-- Lucky Spin packs (Config/Monetization) can't be bought with this many spins banked ("spin some first!"); a
	-- receipt that arrives anyway banks every spin it paid for, past any cap.
	paidBankFull = 40,

	segments = {
		{
			id = "pocketMoney",
			label = "Cash",
			icon = "💵",
			color = "#3DDC84",
			weight = 30,
			reward = { kind = "cash", incomeSeconds = 30, minimum = 200 },
		},
		{
			id = "cashStack",
			label = "Big Cash",
			icon = "💰",
			color = "#2EC4B6",
			weight = 25,
			reward = { kind = "cash", incomeSeconds = 90, minimum = 600 },
		},
		{
			id = "snackling",
			label = "Snackling",
			icon = "🎁",
			color = "#FF8C1A",
			weight = 18,
			reward = { kind = "creature", luck = 2 },
		},
		{
			id = "cashVault",
			label = "Huge Cash",
			icon = "🏦",
			color = "#4DA8FF",
			weight = 14,
			reward = { kind = "cash", incomeSeconds = 300, minimum = 2000 },
		},
		{
			id = "golden",
			label = "Golden!",
			icon = "✨",
			color = "#FFC83D",
			weight = 8,
			reward = { kind = "creature", luck = 2, mutation = "golden" },
		},
		{
			id = "diamond",
			label = "Diamond!",
			icon = "💎",
			color = "#8FF3FF",
			weight = 3.5,
			reward = { kind = "creature", luck = 2, mutation = "diamond" },
		},
		{
			id = "jackpot",
			label = "JACKPOT",
			icon = "🎰",
			color = "#FF5FD2",
			weight = 1.5,
			reward = { kind = "cash", incomeSeconds = 1200, minimum = 10000 },
		},
	},
}

return Spin
