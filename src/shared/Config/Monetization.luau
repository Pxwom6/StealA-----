--!strict
--[[
	Game passes and developer products.

	IDs come from the Creator Hub (create.roblox.com → Creations → Steal a Snackling → Monetization →
	  Passes / Developer Products). Prices are set there, not here; the comment on each line records the
	  price it launched at. An id of 0 means "not configured yet": the store shows the item as unavailable
	  in live servers, and in Studio the "(Studio) Grant" button simulates the purchase through the exact
	  same receipt code path.

	Display names and descriptions live in Config/Theme.luau (store section) so a re-theme never touches this file.

	Fairness rules this config must keep (enforced in code, see DECISIONS.md):
	  * nothing paid makes a base un-stealable (lock tokens never skip the open window, Logic/LockRules.windows)
	  * paid items speed progress up; they never gate content
	  * the only paid item with a random effect (Server Luck) shows exact before/after odds before purchase
]]

export type PassKey = "DoubleCash" | "VIP" | "ExtraPodiums" | "LongerLock"
export type ProductKey = "CashSmall" | "CashMedium" | "CashLarge" | "InstantLock" | "ServerLuck"
export type ProductKind = "Cash" | "LockToken" | "ServerLuck"

export type PassDef = { id: number }
export type ProductDef = { id: number, kind: ProductKind }

local Monetization = {
	passes = {
		DoubleCash = { id = 2025248736 }, -- 2x Cash, 199 R$
		VIP = { id = 2025212749 }, -- VIP, 149 R$
		ExtraPodiums = { id = 2026712754 }, -- +4 Podiums, 99 R$
		LongerLock = { id = 2026892736 }, -- Longer Lock, 49 R$
	} :: { [string]: PassDef },

	products = {
		CashSmall = { id = 3717840270, kind = "Cash" }, -- Snack Pack, 25 R$
		CashMedium = { id = 3717844121, kind = "Cash" }, -- Snack Crate, 75 R$
		CashLarge = { id = 3717844684, kind = "Cash" }, -- Snack Truck, 199 R$
		InstantLock = { id = 3717845411, kind = "LockToken" }, -- Instant Lock, 15 R$
		ServerLuck = { id = 3717845483, kind = "ServerLuck" }, -- Server Luck, 39 R$
	} :: { [string]: ProductDef },

	-- Perk values (balance knobs).
	perks = {
		doubleCashMultiplier = 2,
		vipIncomeBonus = 0.1, -- +10% income
		vipOfflineCapBonusSeconds = 3600,
		extraPodiums = 4,
		longerLockSeconds = 30,
		serverLuckMultiplier = 2,
		serverLuckSeconds = 15 * 60,
	},

	-- Order of items in the store UI.
	storePasses = { "DoubleCash", "VIP", "ExtraPodiums", "LongerLock" } :: { string },
	storeProducts = { "ServerLuck", "CashSmall", "CashMedium", "CashLarge", "InstantLock" } :: { string },

	-- Receipt idempotency: how many recent PurchaseIds each player's save remembers, and purchase history length.
	purchaseIdCacheSize = 100,
	purchaseHistorySize = 100,
}

return Monetization
