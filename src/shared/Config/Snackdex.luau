--!strict
--[[
	The Snackdex (collection book) rewards. Plain data only; rules in Logic/SnackdexRules.

	Owning every regular Snackling of a rarity tier at least once (event Snacklings never count, they have their own
	"Event" section) completes the tier, once per account:
	  * a one-time cash reward, sized like a cash pack: `incomeSeconds` of the player's steady income (rebirths, passes
	    and this bonus; no LiveOps cash event, no friend & group bonus), never below `minimum`
	  * a permanent income bonus of `incomeBonusPerTier` per completed tier, at most `maxIncomeBonus` in total

	Rewards are keyed by rarity id (Config/Rarities); a rarity without an entry uses `defaultTierReward`. Each minimum is
	about a quarter of the price of the tier's cheapest Snackling: enough to feel like a reward for a player who
	completes a tier early, but well below what passing Snacklings between two accounts by stealing would have to
	"pay", so lending Snacklings to an alt can't mint cash (a delivered steal counts as owning it).
	Balance notes: BALANCE.md "Snackdex".
]]

local Types = require("../Types")

local Snackdex: Types.SnackdexConfig = {
	incomeBonusPerTier = 0.03,
	-- Every one of the seven tiers: +21%. The cap keeps it there if tiers are ever added.
	maxIncomeBonus = 0.21,

	tierRewards = {
		Common = { incomeSeconds = 3 * 60, minimum = 10 },
		Uncommon = { incomeSeconds = 5 * 60, minimum = 250 },
		Rare = { incomeSeconds = 8 * 60, minimum = 1000 },
		Epic = { incomeSeconds = 10 * 60, minimum = 15000 },
		Legendary = { incomeSeconds = 15 * 60, minimum = 350000 },
		Mythic = { incomeSeconds = 20 * 60, minimum = 12500000 },
		Secret = { incomeSeconds = 30 * 60, minimum = 450000000 },
	},
	defaultTierReward = { incomeSeconds = 10 * 60, minimum = 1000 },
}

return Snackdex
