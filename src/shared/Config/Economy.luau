--!strict
--[[
	Economy tuning. Plain data only. See BALANCE.md for how these numbers shape the progression curve, and run
	`lune run tools/simulate.luau` after changing them.
]]

export type CashPack = { incomeSeconds: number, minimum: number }
export type DailySlot = { minimum: number, incomeMinutes: number }

local Economy = {
	startingCash = 100,

	-- Podiums: every base starts with `startingPodiums`; more can be bought with cash, one at a time.
	startingPodiums = 8,
	podiumUpgrade = {
		basePrice = 2500,
		growth = 3,
		maxPurchased = 8, -- 8 + 8 = 16 podiums from cash; the Extra Podiums pass adds more on top
	},

	-- Selling a Snackling from your own podium refunds this share of its belt price.
	sellRefund = 0.5,

	-- Offline earnings (paid on rejoin as a "Welcome back" popup).
	offline = {
		rate = 0.5, -- share of normal income earned while away
		capSeconds = 2 * 3600,
		minSecondsAway = 120,
	},

	-- Rebirth: reset cash + Snacklings for a permanent multiplier and a longer base lock.
	rebirth = {
		baseCost = 1500000,
		costGrowth = 6,
		multiplierPerRebirth = 0.5, -- x1 → x1.5 → x2 → ...
		lockBonusPerRebirth = 5, -- extra lock seconds per rebirth
		maxLockBonus = 60,
		maxRebirths = 30,
		cashAfterRebirth = 100,
		keepPodiumUpgrades = true,
	},

	-- Developer-product cash packs scale with the buyer's current income so they stay meaningful.
	cashPacks = {
		CashSmall = { incomeSeconds = 15 * 60, minimum = 2500 } :: CashPack,
		CashMedium = { incomeSeconds = 60 * 60, minimum = 15000 } :: CashPack,
		CashLarge = { incomeSeconds = 6 * 60 * 60, minimum = 120000 } :: CashPack,
	},

	-- Daily login streak (cycles after the last entry). Reward = max(minimum, income * incomeMinutes).
	daily = {
		{ minimum = 250, incomeMinutes = 3 },
		{ minimum = 600, incomeMinutes = 5 },
		{ minimum = 1500, incomeMinutes = 8 },
		{ minimum = 4000, incomeMinutes = 12 },
		{ minimum = 10000, incomeMinutes = 18 },
		{ minimum = 25000, incomeMinutes = 25 },
		{ minimum = 75000, incomeMinutes = 45 },
	} :: { DailySlot },
}

return Economy
