--!strict
--[[
	Game passes and developer products.

	TODO(owner): create each pass / product on the Creator Hub
	  (create.roblox.com → Creations → this experience → Monetization → Passes / Developer Products),
	  then paste the numeric IDs below. An id of 0 means "not configured yet": the store shows the item as
	  unavailable in live servers, and in Studio the "(Studio) Grant" button simulates the purchase through the
	  exact same receipt code path so you can test before the IDs exist.

	Display names and descriptions live in Config/Theme.luau (store section) so a re-theme never touches this file.

	Fairness rules this config must keep (enforced in code, see DECISIONS.md):
	  * nothing paid makes a base un-stealable (lock tokens still respect Gameplay.lock.minVulnerableSeconds)
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
		DoubleCash = { id = 0 }, -- TODO(owner): game pass id
		VIP = { id = 0 }, -- TODO(owner): game pass id
		ExtraPodiums = { id = 0 }, -- TODO(owner): game pass id
		LongerLock = { id = 0 }, -- TODO(owner): game pass id
	} :: { [string]: PassDef },

	products = {
		CashSmall = { id = 0, kind = "Cash" }, -- TODO(owner): developer product id
		CashMedium = { id = 0, kind = "Cash" }, -- TODO(owner): developer product id
		CashLarge = { id = 0, kind = "Cash" }, -- TODO(owner): developer product id
		InstantLock = { id = 0, kind = "LockToken" }, -- TODO(owner): developer product id
		ServerLuck = { id = 0, kind = "ServerLuck" }, -- TODO(owner): developer product id
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
