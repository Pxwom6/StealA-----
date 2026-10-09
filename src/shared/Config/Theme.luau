--!strict
--[[
	Every theme-specific name, string and colour. Re-theming the game ("Steal a ___") should only need edits here,
	in Creatures.luau, Rarities.luau and Sounds.luau. Plain data only.

	Templates use {placeholders}; Format.template fills them in.
	Fonts are Enum.Font item names. Colours are hex strings.
]]

local Theme = {
	gameTitle = "Steal a Snackling",
	creatureNoun = "Snackling",
	creatureNounPlural = "Snacklings",
	currencySymbol = "$",

	fonts = {
		display = "FredokaOne",
		body = "GothamBold",
	},

	palette = {
		primary = "#FF7A1A",
		secondary = "#2EC4B6",
		danger = "#FF3B5C",
		success = "#3DDC84",
		gold = "#FFD23F",
		robux = "#3DDC84",
		panel = "#2B2D42",
		panelLight = "#3D4062",
		text = "#FFFFFF",
		textDim = "#C8CAD8",
		stroke = "#15162A",
		cash = "#8CFF6B",
		lock = "#4DA8FF",
		vip = "#FFD700",
		luck = "#7CFF4D",
	},

	world = {
		ground = "#7BD389",
		walkway = "#F2E8CF",
		belt = "#3D3D4E",
		beltTrim = "#FFD23F",
		wall = "#FFFFFF",
		podium = "#EDEDF4",
		emptyPodium = "#B9BCCB",
		lockedPodium = "#6E7187",
		collectPad = "#3DDC84",
		lockButton = "#4DA8FF",
		lockField = "#4DA8FF",
		graceField = "#FFD23F",
		vipTrim = "#FFD700",
		upgradePad = "#FF7A1A",
		lobby = "#FFE8A3",
	},

	-- One colour per plot (index = plot number).
	plotColors = { "#FF6B6B", "#4ECDC4", "#FFD166", "#A78BFA", "#F78C6B", "#06D6A0", "#118AB2", "#EF476F" },

	text = {
		-- World prompts
		buyAction = "Buy",
		stealAction = "Steal",
		sellAction = "Sell",
		lockAction = "Lock Base",
		upgradeAction = "Add Podium",
		ownerSign = "{name}'s Snack Shack",
		freePlotSign = "Free Base",
		lockedBanner = "LOCKED {time}",
		protectedBanner = "NEW PLAYER SHIELD {time}",
		lockButtonReady = "LOCK",
		lockButtonCooldown = "READY IN {time}",
		lockButtonLocked = "LOCKED {time}",
		podiumUpgradeSign = "+1 Podium\n{price}",
		podiumMaxSign = "Max podiums",
		carryMarker = "THIEF!",
		collectHint = "Step here to collect",

		-- HUD
		perSecond = "+{amount}/s",
		storeButton = "Shop",
		rebirthButton = "Rebirth",
		dailyButton = "Daily",
		tagButton = "TAG!",
		lockPillReady = "Lock ready",
		lockPillLocked = "Locked {time}",
		lockPillCooldown = "Lock in {time}",
		lockPillToken = "Instant lock x{count}",
		luckBanner = "{multiplier}x LUCK {time}",

		-- Toasts
		notEnoughCash = "Not enough cash!",
		baseFull = "Your base is full! Sell or add a podium.",
		tooFar = "Get closer!",
		boughtCreature = "You got {creature}!",
		soldCreature = "Sold {creature} for {amount}",
		collected = "+{amount}",
		podiumAdded = "New podium unlocked!",
		baseLockedToast = "Base locked for {seconds}s!",
		lockCooldown = "Lock recharging: {time}",
		lockVulnerable = "Can't lock again so soon ({time})",
		cantStealLocked = "That base is locked!",
		cantStealProtected = "New players are protected for a few minutes.",
		cantStealOwn = "That's yours!",
		stealFromInside = "Get inside their base first!",
		stealOnFloor = "Stand on the floor to steal!",
		stealHoldNear = "Hold Steal right next to the Snackling!",
		stealConnectionHiccup = "Connection hiccup — try again in a moment",
		stealCooldown = "Catch your breath... {time}",
		alreadyCarrying = "You're already carrying one!",
		stealStarted = "Run home! Don't get tagged!",
		stealSuccess = "You stole {creature}!",
		stealFailedTimeout = "Too slow! {creature} ran home.",
		gotTagged = "Tagged! {creature} ran home.",
		taggedThief = "You tagged {thief}! {creature} is safe.",
		stolenFromYou = "{thief} stole your {creature}!",
		beingStolen = "{thief} is stealing your {creature}! TAG them!",
		creatureReturned = "{creature} made it home safely.",
		ownerLeftDuringSteal = "The owner left - {creature} ran home.",
		dailyClaimed = "Day {day} reward: {amount}!",
		purchaseThanks = "Thanks for your support!",
		luckActivated = "{player} activated {multiplier}x Server Luck for {minutes} min!",
		passGranted = "{pass} unlocked!",
		lockTokenReady = "Instant Lock ready! Tap the lock button.",
		lockTokenLater = "Instant Lock saved! You can use it in {time}.",

		-- Announcements (server-wide banners)
		announceSpawn = "A {rarity} {creature} appeared on the belt!",
		announceBuy = "{player} bought a {rarity} {creature}!",
		announceSteal = "{thief} stole {owner}'s {rarity} {creature}!",
		announceRebirth = "{player} reached Rebirth {rebirths}!",

		-- Welcome back / daily / rebirth dialogs
		welcomeBackTitle = "Welcome back!",
		welcomeBackBody = "Your Snacklings earned {amount} while you were away ({duration}).",
		dailyTitle = "Daily Snacks",
		dailyBody = "Day {day} streak - come back tomorrow for more!",
		claim = "Claim",
		ok = "Awesome!",
		close = "Close",
		rebirthTitle = "Rebirth",
		rebirthLose = "You lose",
		rebirthGain = "You keep forever",
		rebirthLoseCash = "All cash ({amount})",
		rebirthLoseCreatures = "{count} Snacklings ({income}/s)",
		rebirthGainMultiplier = "Earnings x{from} -> x{to}",
		rebirthGainLock = "Base lock {from}s -> {to}s",
		rebirthKeep = "Podiums, game passes and stats stay",
		rebirthNeed = "Need {amount} to rebirth",
		rebirthConfirm = "Rebirth!",
		rebirthMax = "Max rebirths reached",

		-- Store
		storeTitle = "Snack Shop",
		storePassesHeader = "Forever perks",
		storeProductsHeader = "Boosts & cash",
		storeOwned = "Owned",
		storeUnavailable = "Coming soon",
		storeStudioGrant = "(Studio) Grant",
		storeLuckMaxed = "Luck maxed",
		oddsHeader = "Belt odds now -> with Server Luck",
		oddsExtendHeader = "Server Luck is on: buying adds +{minutes} min (odds stay the same)",
		oddsMaxedHeader = "Server Luck is on: maximum time reached",
	},

	-- Store copy per item key (see Config/Monetization). Available placeholders: {vipBonus} {extraPodiums}
	-- {lockSeconds} {minVulnerable} {luckMultiplier} {luckMinutes}, filled from the perk values.
	store = {
		DoubleCash = { name = "2x Cash", description = "Double all Snackling income, forever." },
		VIP = {
			name = "VIP",
			description = "Gold VIP chat tag, golden base trim, +{vipBonus}% income and longer offline earnings.",
		},
		ExtraPodiums = {
			name = "+{extraPodiums} Podiums",
			description = "{extraPodiums} extra podiums in your base, forever.",
		},
		LongerLock = { name = "Longer Lock", description = "Your base lock lasts {lockSeconds} seconds longer." },
		CashSmall = { name = "Snack Pack", description = "About 15 minutes of your income." },
		CashMedium = { name = "Snack Crate", description = "About 1 hour of your income." },
		CashLarge = { name = "Snack Truck", description = "About 6 hours of your income." },
		InstantLock = {
			name = "Instant Lock",
			description = "Lock your base right now, even while the lock recharges. Can't be chained: every base stays open between locks for at least {minVulnerable}s, or half its lock time if longer.",
		},
		ServerLuck = {
			name = "Server Luck",
			description = "{luckMultiplier}x rare odds on the belt for EVERYONE in this server for {luckMinutes} minutes. Buying again adds time.",
		},
	} :: { [string]: { name: string, description: string } },

	vipChatTag = "[VIP]",
}

return Theme
