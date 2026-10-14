--!strict
--[[
	Achievements (Rewards panel, Trophies tab): goals counted from what the save already records, each paid once
	per account the moment it is reached (AchievementService), with a toast. Plain data only.

	id       saved as the flag ach_<id>: never rename or remove one that has shipped (CI keeps a released list)
	goal     what it counts (Types.AchievementGoal), with `target` (and `rarity` for "rarity")
	reward   a prize (Types.PrizeReward): cash sized from steady income, Lucky Spins or a lucky Snackling
	badgeId  optional: a Roblox badge awarded too. Create one in the Creator Hub (Associated Items > Badges) and paste
	         its id here; nil awards none.
]]

local Types = require("../Types")

local function cash(seconds: number, minimum: number): Types.PrizeReward
	return { kind = "cash", incomeSeconds = seconds, minimum = minimum }
end

local Achievements: Types.AchievementsConfig = {
	list = {
		-- Buying from the belt
		{
			id = "firstBite",
			title = "First Bite",
			description = "Buy your first Snackling",
			icon = "🍕",
			goal = "beltPurchases",
			target = 1,
			reward = cash(30, 100),
		},
		{
			id = "snackShopper",
			title = "Snack Shopper",
			description = "Buy 25 Snacklings from the belt",
			icon = "🛒",
			goal = "beltPurchases",
			target = 25,
			reward = cash(120, 1000),
		},
		{
			id = "beltBoss",
			title = "Belt Boss",
			description = "Buy 250 Snacklings from the belt",
			icon = "🏭",
			goal = "beltPurchases",
			target = 250,
			reward = { kind = "spin", count = 3 },
		},
		-- Stealing
		{
			id = "stickyFingers",
			title = "Sticky Fingers",
			description = "Steal a Snackling",
			icon = "🫳",
			goal = "steals",
			target = 1,
			reward = cash(60, 300),
		},
		{
			id = "masterThief",
			title = "Master Thief",
			description = "Steal 25 Snacklings",
			icon = "🦹",
			goal = "steals",
			target = 25,
			reward = cash(300, 5000),
		},
		{
			id = "legendaryBandit",
			title = "Legendary Bandit",
			description = "Steal 150 Snacklings",
			icon = "👑",
			goal = "steals",
			target = 150,
			reward = { kind = "creature", luck = 4 },
		},
		-- The Snackdex
		{
			id = "collector",
			title = "Collector",
			description = "Discover 10 Snacklings",
			icon = "📖",
			goal = "discovered",
			target = 10,
			reward = cash(120, 800),
		},
		{
			id = "curator",
			title = "Curator",
			description = "Discover 30 Snacklings",
			icon = "🏛️",
			goal = "discovered",
			target = 30,
			reward = { kind = "spin", count = 2 },
		},
		{
			id = "completionist",
			title = "Completionist",
			description = "Discover every regular Snackling",
			icon = "💯",
			goal = "allRegular",
			target = 1,
			reward = { kind = "creature", luck = 4, mutation = "rainbow" },
		},
		-- Rarities
		{
			id = "rareFind",
			title = "Rare Find",
			description = "Own a Rare Snackling",
			icon = "💙",
			goal = "rarity",
			rarity = "Rare",
			target = 1,
			reward = cash(60, 500),
		},
		{
			id = "epicTaste",
			title = "Epic Taste",
			description = "Own an Epic Snackling",
			icon = "💜",
			goal = "rarity",
			rarity = "Epic",
			target = 1,
			reward = cash(120, 2000),
		},
		{
			id = "legend",
			title = "Legend",
			description = "Own a Legendary Snackling",
			icon = "🧡",
			goal = "rarity",
			rarity = "Legendary",
			target = 1,
			reward = cash(300, 20000),
		},
		{
			id = "mythical",
			title = "Mythical",
			description = "Own a Mythic Snackling",
			icon = "💖",
			goal = "rarity",
			rarity = "Mythic",
			target = 1,
			reward = { kind = "spin", count = 3 },
		},
		{
			id = "secretKeeper",
			title = "Secret Keeper",
			description = "Own a Secret Snackling",
			icon = "🤫",
			goal = "rarity",
			rarity = "Secret",
			target = 1,
			reward = { kind = "spin", count = 5 },
		},
		-- Mutations
		{
			id = "shiny",
			title = "Shiny!",
			description = "Own a mutated Snackling",
			icon = "✨",
			goal = "mutations",
			target = 1,
			reward = cash(60, 500),
		},
		{
			id = "mutationHunter",
			title = "Mutation Hunter",
			description = "Own 8 different mutations",
			icon = "🧪",
			goal = "mutations",
			target = 8,
			reward = { kind = "spin", count = 2 },
		},
		{
			id = "mutationMaster",
			title = "Mutation Master",
			description = "Own 16 different mutations",
			icon = "🌈",
			goal = "mutations",
			target = 16,
			reward = { kind = "creature", luck = 4, mutation = "diamond" },
		},
		-- Earnings
		{
			id = "pocketMoney",
			title = "Pocket Money",
			description = "Earn $10K in total",
			icon = "💵",
			goal = "earned",
			target = 10000,
			reward = cash(60, 500),
		},
		{
			id = "millionaire",
			title = "Millionaire",
			description = "Earn $1M in total",
			icon = "💰",
			goal = "earned",
			target = 1e6,
			reward = cash(180, 50000),
		},
		{
			id = "billionaire",
			title = "Billionaire",
			description = "Earn $1B in total",
			icon = "🏦",
			goal = "earned",
			target = 1e9,
			reward = { kind = "spin", count = 5 },
		},
		-- Rebirths
		{
			id = "bornAgain",
			title = "Born Again",
			description = "Rebirth once",
			icon = "♻️",
			goal = "rebirths",
			target = 1,
			reward = { kind = "spin", count = 2 },
		},
		{
			id = "fiveLives",
			title = "Five Lives",
			description = "Rebirth 5 times",
			icon = "🔁",
			goal = "rebirths",
			target = 5,
			reward = { kind = "spin", count = 5 },
		},
		-- Maps and the Lucky Spin
		{
			id = "tourist",
			title = "Tourist",
			description = "Play on 5 different maps",
			icon = "🗺️",
			goal = "maps",
			target = 5,
			reward = cash(120, 1000),
		},
		{
			id = "globetrotter",
			title = "Globetrotter",
			description = "Play on every map",
			icon = "🌍",
			goal = "maps",
			target = 14,
			reward = { kind = "spin", count = 3 },
		},
		{
			id = "luckySpinner",
			title = "Lucky Spinner",
			description = "Spin the Lucky Spin 10 times",
			icon = "🎰",
			goal = "spins",
			target = 10,
			reward = cash(180, 2000),
		},
	},
}

return Achievements
