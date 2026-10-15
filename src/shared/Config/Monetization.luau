--!strict
--[[
	Game passes and developer products.

	IDs come from the Creator Hub (create.roblox.com → Creations → Steal a Snackling → Monetization →
	  Passes / Developer Products). Prices are set there, not here; the comment on each line records the
	  price it launched at (or the suggested price, for an item not created yet). An id of 0 means "not
	  configured yet": live servers hide the item everywhere it would be sold (Logic/StoreRules.visible), and in
	  Studio the "(Studio) Grant" button simulates the purchase through the exact same receipt code path.

	Display names and descriptions live in Config/Theme.luau (store section) so a re-theme never touches this file.

	Fairness rules this config must keep (enforced in code, see DECISIONS.md):
	  * nothing paid makes a base un-stealable (lock tokens never skip the open window, Logic/LockRules.windows)
	  * paid items speed progress up; they never gate content
	  * the paid items with a random effect (Server Luck, the Lucky Spin packs) show their exact odds before purchase
	    and are sold only to players whose Roblox policy allows paid random items (PlayerPolicy)
]]

local Types = require("../Types")

export type PassKey = "DoubleCash" | "VIP" | "ExtraPodiums" | "LongerLock" | "AutoCollect"
export type ProductKey =
	"CashBite"
	| "CashBag"
	| "CashSmall"
	| "CashBasket"
	| "CashMedium"
	| "CashLarge"
	| "InstantLock"
	| "ServerLuck"
	| "LuckySpins3"
	| "LuckySpins10"
	| "StarterPack"
-- Spins: Lucky Spins banked for the Rewards panel's reel (a paid random item: odds shown, PolicyService respected).
-- StarterPack: fixed contents once per account (`starterPack` below).
export type ProductKind = "Cash" | "LockToken" | "ServerLuck" | "Spins" | "StarterPack"

export type PassDef = { id: number }
export type ProductDef = { id: number, kind: ProductKind, spins: number? } -- spins: a Spins pack's count

local Monetization = {
	passes = {
		DoubleCash = { id = 2025248736 }, -- 2x Cash, 199 R$
		VIP = { id = 2025212749 }, -- VIP, 149 R$
		ExtraPodiums = { id = 2026712754 }, -- +4 Podiums, 99 R$
		LongerLock = { id = 2026892736 }, -- Longer Lock, 49 R$
		-- Not created yet (README "Before publishing"): paste the Creator Hub ids here.
		AutoCollect = { id = 0 }, -- Auto Collect, suggested 149 R$
	} :: { [string]: PassDef },

	products = {
		CashBite = { id = 3717868366, kind = "Cash" }, -- Snack Bite, 5 R$
		CashBag = { id = 3717868501, kind = "Cash" }, -- Snack Bag, 15 R$
		CashSmall = { id = 3717840270, kind = "Cash" }, -- Snack Pack, 25 R$
		CashBasket = { id = 3717868578, kind = "Cash" }, -- Snack Basket, 49 R$
		CashMedium = { id = 3717844121, kind = "Cash" }, -- Snack Crate, 75 R$
		CashLarge = { id = 3717844684, kind = "Cash" }, -- Snack Truck, 199 R$
		InstantLock = { id = 3717845411, kind = "LockToken" }, -- Instant Lock, 15 R$
		ServerLuck = { id = 3717845483, kind = "ServerLuck" }, -- Server Luck, 39 R$
		-- Not created yet (README "Before publishing"): paste the Creator Hub ids here.
		LuckySpins3 = { id = 0, kind = "Spins", spins = 3 }, -- 3 Lucky Spins, suggested 25 R$
		LuckySpins10 = { id = 0, kind = "Spins", spins = 10 }, -- 10 Lucky Spins, suggested 69 R$
		StarterPack = { id = 0, kind = "StarterPack" }, -- Starter Pack, suggested 49 R$ (once per account)
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
		-- Auto Collect: every active pad's cash, this often, wherever the owner is (Logic/AutoCollectRules keeps it
		-- between 2 and 30 s).
		autoCollectSeconds = 5,
	},

	-- Order of items in the store UI.
	storePasses = { "DoubleCash", "AutoCollect", "VIP", "ExtraPodiums", "LongerLock" } :: { string },
	storeProducts = {
		"StarterPack", -- first: the one-time best value (hidden once bought)
		"ServerLuck",
		"LuckySpins3",
		"LuckySpins10",
		"CashBite",
		"CashBag",
		"CashSmall",
		"CashBasket",
		"CashMedium",
		"CashLarge",
		"InstantLock",
	} :: { string },

	-- Items whose views are logged (product_viewed: 01 key, 02 where it was seen), once per session each.
	viewTracked = { "StarterPack", "AutoCollect", "LuckySpins3", "LuckySpins10" } :: { string },

	-- The Starter Pack (Logic/StarterPackRules): fixed contents, once per account. Cash sized from steady income like a
	-- cash pack (40 minutes, more than the same-price Snack Basket's 35), a Golden Cupcake Cub (the top Rare, earning
	-- like an Epic) and the first two gadgets, or their cash prices for gadgets already owned. Its offer card shows once,
	-- after the first rebirth or 30 minutes of total play, whichever comes first. BALANCE.md "Store additions".
	starterPack = {
		cash = { incomeSeconds = 40 * 60, minimum = 60000 },
		creatureId = "cupcake_cub",
		variant = "golden",
		gadgets = { "soda", "peel" },
		offer = { afterRebirths = 1, afterPlaySeconds = 30 * 60, showSeconds = 10 },
	} :: Types.StarterPackConfig,

	-- "Need $X more?": when a belt or podium purchase fails for lack of cash, offer the cheapest of the small cash packs
	-- that covers the gap (Logic/CashOfferRules; CI keeps these within its LIMITS). Gentle for a young audience: never
	-- during the first-time tutorial or a player's first 10 minutes of play, never for a gap their income covers in
	-- 45 s or less (the toast says how many seconds instead), and at most one offer every 3 minutes. DECISIONS.md #25.
	cashOffer = {
		cooldownSeconds = 180,
		minPlaySeconds = 10 * 60,
		smallGapSeconds = 45,
		packs = { "CashBite", "CashBag", "CashSmall" } :: { string }, -- 5, 15 and 25 R$: cheapest first (store order)
	},

	-- Receipt idempotency: how many recent PurchaseIds each player's save remembers, and purchase history length.
	purchaseIdCacheSize = 100,
	purchaseHistorySize = 100,
}

return Monetization
