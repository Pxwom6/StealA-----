--!strict
--[[
	Game passes and developer products.

	Passes: ownership is checked on join (UserOwnsGamePassAsync, with retries) and when bought in-game
	(PromptGamePassPurchaseFinished, then UserOwnsGamePassAsync: the event alone is not trusted). Ownership lives in
	the session, not the save: Roblox is the source of truth.

	Products: MarketplaceService.ProcessReceipt → Logic/ReceiptLedger.process:
	  * the grant and the PurchaseId record happen together without yielding (no double grants on retry)
	  * PurchaseGranted is returned only once the PurchaseId is in the last SUCCESSFULLY SAVED data
	  * if the player is not in this server / the session ends first → NotProcessedYet (Roblox retries later)

	Paid random items (Server Luck, Lucky Spin packs: Logic/StoreRules.PAID_RANDOM_KINDS) are granted only when the
	buyer's Roblox policy allows them (PlayerPolicy, looked up before the grant step); otherwise the receipt is never
	granted. A Lucky Spin pack banks every spin it paid for, past any cap (SpinRules.bankPaid).

	Studio: products/passes with id 0 can be tested with the "(Studio) Grant" store buttons, which run the exact
	same receipt path with a fake receipt. The DevGrantProduct remote does not exist outside Studio. Products checked
	before prompting (StoreService) take the same fake receipt through MonetizationService.grantInStudio.
]]

local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Gadgets = require(ReplicatedStorage.Shared.Config.Gadgets)
local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local GameData = require(ReplicatedStorage.Shared.GameData)
local Types = require(ReplicatedStorage.Shared.Types)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local GadgetRules = require(ReplicatedStorage.Shared.Logic.GadgetRules)
local Guard = require(ReplicatedStorage.Shared.Logic.Guard)
local Inventory = require(ReplicatedStorage.Shared.Logic.Inventory)
local LiveOpsRules = require(ReplicatedStorage.Shared.Logic.LiveOpsRules)
local ReceiptLedger = require(ReplicatedStorage.Shared.Logic.ReceiptLedger)
local SpinRules = require(ReplicatedStorage.Shared.Logic.SpinRules)
local StarterPackRules = require(ReplicatedStorage.Shared.Logic.StarterPackRules)
local StoreRules = require(ReplicatedStorage.Shared.Logic.StoreRules)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local Analytics = require(script.Parent.Analytics)
local Announcer = require(script.Parent.Announcer)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local GameEvents = require(script.Parent.GameEvents)
local LiveOpsService = require(script.Parent.LiveOpsService)
local LockService = require(script.Parent.LockService)
local PlayerPolicy = require(script.Parent.PlayerPolicy)
local Remotes = require(script.Parent.Remotes)
local Replication = require(script.Parent.Replication)
local Sessions = require(script.Parent.Sessions)

type Session = Sessions.Session
local PASS_KEYS: { string } = { "DoubleCash", "VIP", "ExtraPodiums", "LongerLock", "AutoCollect" }
-- A receipt can arrive while the buyer's save is still loading (e.g. a retry on join): wait for it, longer than
-- DataService's 60 s load timeout, so the receipt is handled before the player can play (or rebirth).
local SESSION_WAIT_SECONDS = 75
local PASS_RECHECK_SECONDS = 60
local SAVE_TIMEOUT_SECONDS = 15
local MAX_SAVE_ATTEMPTS = 4

local MonetizationService = {}

local function hasPass(passes: Types.Passes, key: string): boolean
	if key == "DoubleCash" then
		return passes.DoubleCash
	elseif key == "VIP" then
		return passes.VIP
	elseif key == "ExtraPodiums" then
		return passes.ExtraPodiums
	elseif key == "LongerLock" then
		return passes.LongerLock
	elseif key == "AutoCollect" then
		return passes.AutoCollect
	end
	return false
end

local function setPass(passes: Types.Passes, key: string, value: boolean)
	if key == "DoubleCash" then
		passes.DoubleCash = value
	elseif key == "VIP" then
		passes.VIP = value
	elseif key == "ExtraPodiums" then
		passes.ExtraPodiums = value
	elseif key == "LongerLock" then
		passes.LongerLock = value
	elseif key == "AutoCollect" then
		passes.AutoCollect = value
	end
end

local function passKeyForId(passId: number): string?
	if passId == 0 then
		return nil
	end
	for _, key in PASS_KEYS do
		if Monetization.passes[key].id == passId then
			return key
		end
	end
	return nil
end

local function productKeyForId(productId: number): string?
	if productId == 0 then
		return nil
	end
	for key, product in Monetization.products do
		if product.id == productId then
			return key
		end
	end
	return nil
end

-- Whether the user owns the pass, or nil when Roblox could not be asked (after a few retries).
local function ownsPass(userId: number, passId: number): boolean?
	if passId == 0 then
		return false
	end
	for attempt = 1, 3 do
		local ok, owns = pcall(function(): boolean
			return MarketplaceService:UserOwnsGamePassAsync(userId, passId)
		end)
		if ok then
			return owns
		end
		if attempt < 3 then
			task.wait(attempt)
		end
	end
	warn(`[Monetization] could not check pass {passId} for {userId}`)
	return nil
end

-- Looks up every pass in `keys` at the same time and yields until all are answered. A key is missing from the
-- result when its lookup failed.
local function lookupPasses(userId: number, keys: { string }): { [string]: boolean }
	local results: { [string]: boolean } = {}
	local remaining = #keys
	local waiting: thread? = nil
	for _, key in keys do
		task.spawn(function()
			local owns = ownsPass(userId, Monetization.passes[key].id)
			if owns ~= nil then
				results[key] = owns
			end
			remaining -= 1
			if remaining == 0 and waiting then
				task.spawn(waiting)
			end
		end)
	end
	if remaining > 0 then
		waiting = coroutine.running()
		coroutine.yield()
	end
	return results
end

-- Re-applies everything a pass affects (income, podiums, lock length, VIP tag/trim).
local function applyPasses(session: Session)
	session.player:SetAttribute("VIP", session.passes.VIP)
	EconomyService.refresh(session)
	LockService.refresh(session)
end

-- Passes whose ownership could not be checked at join are re-checked every PASS_RECHECK_SECONDS until Roblox
-- answers (or the player leaves); an owned one is then applied.
local function recheckPasses(player: Player, keys: { string })
	local pending = keys
	while #pending > 0 do
		task.wait(PASS_RECHECK_SECONDS)
		if player.Parent ~= Players then
			return
		end
		local results = lookupPasses(player.UserId, pending)
		local session = Sessions.get(player)
		local still: { string } = {}
		for _, key in pending do
			local owns = results[key]
			if owns == nil or (owns and session == nil) then
				table.insert(still, key) -- unknown, or owned but the session is not ready yet
			elseif owns and session and not hasPass(session.passes, key) then
				setPass(session.passes, key, true)
				applyPasses(session)
			end
		end
		pending = still
	end
end

-- PlayerLifecycle hook: runs before the session exists. Lookups run in parallel; any that fail are treated as
-- not owned for now and re-checked in the background.
function MonetizationService.checkPasses(player: Player): Types.Passes
	local passes: Types.Passes =
		{ DoubleCash = false, VIP = false, ExtraPodiums = false, LongerLock = false, AutoCollect = false }
	local results = lookupPasses(player.UserId, PASS_KEYS)
	local failed: { string } = {}
	for _, key in PASS_KEYS do
		local owns = results[key]
		if owns == nil then
			table.insert(failed, key)
		end
		setPass(passes, key, owns == true)
	end
	player:SetAttribute("VIP", passes.VIP)
	if #failed > 0 then
		task.spawn(recheckPasses, player, failed)
	end
	return passes
end

local function grantPass(session: Session, key: string)
	if hasPass(session.passes, key) then
		return
	end
	setPass(session.passes, key, true)
	applyPasses(session)
	local copy = Theme.store[key]
	Remotes.notify(
		session.player,
		Format.template(Theme.text.passGranted, { pass = if copy then copy.name else key }),
		"success"
	)
	Analytics.storeStep(session, "ProductPurchased", { "pass", key })
	Analytics.custom(session, "pass_purchased", nil, { key })
end

local function waitForSession(player: Player): Session?
	local deadline = os.clock() + SESSION_WAIT_SECONDS
	local session = Sessions.get(player)
	while session == nil and player.Parent == Players and os.clock() < deadline do
		task.wait(0.25)
		session = Sessions.get(player)
	end
	return session
end

type AfterGrant = () -> ()

-- Purchases granted on this server whose save had not landed when their call returned (Roblox retries those): their
-- follow-up and analytics wait for the retry that finds them saved.
local unconfirmed: { [string]: AfterGrant } = {}

-- A Starter Pack's grant, worked out (StarterPackRules): what to write, and what to tell the buyer.
type StarterGrant = {
	cash: number,
	unlock: { string }, -- gadget ids whose flags it sets
	creature: { id: string, variant: string?, podium: number }?, -- the Snackling and its free podium
	duplicate: boolean, -- the pack was owned already: the whole pack's value in cash instead
	text: string, -- the toast
}

local function gadgetPrice(id: string): number
	local def = Gadgets.gadgets[id]
	return if def then def.price else 0
end

-- What a Starter Pack receipt grants `session` now, `quotedCash` being its income-sized cash fixed when the receipt
-- was first seen. Changes nothing.
local function prepareStarter(session: Session, quotedCash: number): StarterGrant
	local config = Monetization.starterPack
	local data = session.data
	local def = GameData.catalog.creatures[config.creatureId]
	if def == nil then
		error(`the Starter Pack's Snackling {config.creatureId} is missing; check Config/Monetization`)
	end
	local creatureName = GameData.displayName(def, config.variant)
	local creaturePrice = GameData.price(def, config.variant)
	local contents = StarterPackRules.contents(config, quotedCash, function(id: string): boolean
		return GadgetRules.owns(data.flags, id)
	end, gadgetPrice)
	if StarterPackRules.owns(data.flags) then
		-- Bought already (the server refuses that before the prompt): the whole pack's worth in cash, so nothing paid
		-- for is lost.
		local value = StarterPackRules.cashValue(contents, creaturePrice, gadgetPrice)
		return {
			cash = value,
			unlock = {},
			creature = nil,
			duplicate = true,
			text = Format.template(Theme.text.starterDuplicate, { amount = UiTheme.cash(value) }),
		}
	end
	-- Its Snackling takes a free podium (a carrying thief's last one stays for the delivery); with none, its full belt
	-- price is paid instead (buying is refused with a full base, so only a base filled since the prompt gets here).
	local podium = if Inventory.prizeMayTakePodium(data.creatures, session.capacity, session.carry ~= nil)
		then EconomyService.freePodium(session)
		else nil
	local cash = contents.cash + contents.gadgetCash + (if podium then 0 else creaturePrice)
	return {
		cash = cash,
		unlock = contents.gadgets,
		creature = if podium then { id = def.id, variant = config.variant, podium = podium } else nil,
		duplicate = false,
		text = Format.template(
			if podium then Theme.text.starterBought else Theme.text.starterBoughtFull,
			{ creature = creatureName, amount = UiTheme.cash(cash) }
		),
	}
end

-- Works out everything a product grants WITHOUT changing anything (it may throw: nothing is lost, Roblox retries).
-- Returns `apply`, which only writes the precomputed results (plain table writes: no yields, nothing that can fail;
-- see ReceiptLedger), a follow-up that runs once the purchase is confirmed saved (announcements, auto-lock...), and
-- `landed`, which runs right after a grant this call made (podiums, gameplay events), saved yet or not.
-- `paidRandomAllowed`: the buyer's policy allows paid random items (PlayerPolicy, looked up before this step).
local function prepareProduct(
	session: Session,
	key: string,
	receipt: { [string]: any },
	quotedCash: number,
	paidRandomAllowed: boolean
): (() -> (), AfterGrant?, (() -> ())?)
	local product = Monetization.products[key]
	local perks = Monetization.perks
	local data = session.data
	local robux = if type(receipt.CurrencySpent) == "number" then receipt.CurrencySpent else 0
	local historyEntry: Types.PurchaseRecord = {
		purchaseId = tostring(receipt.PurchaseId),
		productId = if type(receipt.ProductId) == "number" then receipt.ProductId else 0,
		key = key,
		robux = robux,
		at = os.time(),
	}
	local historySize = Monetization.purchaseHistorySize
	local cash, tokens, spins = 0, 0, 0
	local newBoosts: { LiveOpsRules.Boost }? = nil
	local starter: StarterGrant? = nil
	local after: AfterGrant
	local landed: (() -> ())? = nil

	if product.kind == "Cash" then
		cash = quotedCash
		after = function()
			Analytics.economySource(session, cash, "IAP", key)
			Remotes.notify(session.player, `+{UiTheme.cash(cash)}! {Theme.text.purchaseThanks}`, "success")
		end
	elseif product.kind == "LockToken" then
		tokens = 1
		after = function()
			local attempt = LockService.preview(session)
			if session.data.lockTokens <= 0 then
				-- Already used (e.g. they tapped lock while the purchase was saving).
				Remotes.notify(session.player, Theme.text.purchaseThanks, "success")
			elseif attempt.ok then
				LockService.tryLock(session)
			elseif attempt.reason == "locked" or attempt.reason == "vulnerable" then
				-- The token is kept, but can't be used before the current lock and the open window after it end.
				local wait = session.lock.vulnerableUntil - workspace:GetServerTimeNow()
				Remotes.notify(
					session.player,
					Format.template(Theme.text.lockTokenLater, { time = Format.clock(wait) }),
					"info"
				)
			else
				Remotes.notify(session.player, Theme.text.lockTokenReady, "success")
			end
		end
	elseif product.kind == "ServerLuck" then
		if not paidRandomAllowed then
			-- Only a client that went around the store's blocked card gets here: never grant it (PlayerPolicy).
			error("paid random items are not allowed for this player (PolicyService)")
		end
		newBoosts = LiveOpsService.boostsWith(
			perks.serverLuckSeconds,
			perks.serverLuckMultiplier,
			LiveOpsService.PURCHASE_SOURCE,
			true
		)
		after = function()
			LiveOpsService.publishAttributes()
			Announcer.broadcast({
				text = Format.template(Theme.text.luckActivated, {
					player = session.player.DisplayName,
					multiplier = perks.serverLuckMultiplier,
					minutes = math.floor(perks.serverLuckSeconds / 60),
				}),
				rarity = "Legendary",
				kind = "luck",
			})
		end
	elseif product.kind == "Spins" then
		if not paidRandomAllowed then
			-- A paid random item too: only a client that went around the blocked buttons gets here (PlayerPolicy).
			error("paid random items are not allowed for this player (PolicyService)")
		end
		spins = math.max(0, math.floor(product.spins or 0))
		if spins < 1 then
			error(`{key} gives no spins; check Config/Monetization`)
		end
		after = function()
			Remotes.notify(
				session.player,
				Format.template(Theme.text.spinPackBought, { count = spins, total = session.data.spin.spins }),
				"success"
			)
		end
	elseif product.kind == "StarterPack" then
		local grant = prepareStarter(session, quotedCash)
		starter = grant
		cash = grant.cash
		after = function()
			Analytics.economySource(session, grant.cash, "IAP", key)
			Remotes.notify(session.player, grant.text, "success")
			if grant.duplicate then
				-- Logged so Leo can see how often a second prompt still gets bought.
				Analytics.custom(session, "starter_pack_duplicate", grant.cash, { key })
				warn(
					`[Monetization] {session.player.Name} bought the Starter Pack again: paid {grant.cash} cash instead`
				)
			end
		end
		landed = function()
			EconomyService.refresh(session) -- the Snackling's podium, the gadget buttons
			local creature = grant.creature
			if creature then
				local event = { kind = "acquired" :: "acquired", creatureId = creature.id, variant = creature.variant }
				GameEvents.emit(session, event) -- the Snackdex, quests
				GameEvents.emit(session, {
					kind = "found",
					creatureId = creature.id,
					variant = creature.variant,
					source = "StarterPack",
				})
			end
		end
	else
		error(`unknown product kind for {key}`)
	end

	local function apply()
		ReceiptLedger.appendHistory(data.purchaseHistory, historyEntry, historySize)
		data.stats.robuxSpent += robux
		data.cash += cash
		data.stats.totalEarned += cash
		data.lockTokens += tokens
		-- Every spin paid for, past the bank's caps: a purchase is never clipped (buying is refused at
		-- Config/Spin.paidBankFull, before the prompt; see StoreService).
		SpinRules.bankPaid(data.spin, spins)
		if starter then
			data.flags[StarterPackRules.OWNED_FLAG] = true -- once per account, saved with the purchase
			for _, id in starter.unlock do
				data.flags[GadgetRules.flag(id)] = true
			end
			local creature = starter.creature
			if creature then
				Inventory.add(data, creature.id, creature.podium, os.time(), creature.variant)
			end
		end
		if newBoosts then
			LiveOpsService.setBoosts(newBoosts) -- the only write outside the save
		end
		Replication.markDirty(session) -- a flag: shows the new cash/tokens now, not after the save lands
	end
	return apply, after, landed
end

-- Shared receipt path for real purchases and Studio test grants.
local function processFor(player: Player, key: string, receipt: { [string]: any }): Enum.ProductPurchaseDecision
	local session = waitForSession(player)
	if session == nil then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local purchaseId = tostring(receipt.PurchaseId)
	local after: AfterGrant? = nil
	local profile = session.profile
	-- Server Luck and Lucky Spin packs are paid random items: only for players whose policy allows them (the store
	-- blocks or hides them otherwise). Looked up here, before the grant step, because it may yield.
	local paidRandomAllowed = true
	if StoreRules.PAID_RANDOM_KINDS[Monetization.products[key].kind] then
		paidRandomAllowed = PlayerPolicy.paidRandomItemsAllowed(player)
		if not paidRandomAllowed then
			warn(`[Monetization] {player.Name} may not buy paid random items: {key} is not granted`)
		end
	end
	-- A cash pack's amount is fixed the first time its receipt reaches the player's session (and saved with the data),
	-- so if that grant fails and Roblox retries after the player's income changed (e.g. they rebirthed), the retry
	-- pays what the purchase was worth then. A receipt that finds no session yet waits for the load (see above).
	-- The Starter Pack's income-sized cash is quoted the same way.
	local quotedCash = 0
	local kind = Monetization.products[key].kind
	if (kind == "Cash" or kind == "StarterPack") and profile:IsActive() then
		quotedCash = ReceiptLedger.quote(session.data.cashPackQuotes, purchaseId, function(): number
			return if kind == "Cash"
				then EconomyService.cashPackAmount(session, key)
				else StarterPackRules.cash(Monetization.starterPack, session.packIncome)
		end, Monetization.purchaseIdCacheSize)
	end
	local decision = ReceiptLedger.process(purchaseId, Monetization.purchaseIdCacheSize, {
		isActive = function(): boolean
			return profile:IsActive()
		end,
		liveIds = function(): { string }
			return profile.Data.processedReceipts
		end,
		savedIds = function(): { string }?
			local saved = profile.LastSavedData
			return if saved then saved.processedReceipts else nil
		end,
		data = function(): { [string]: any }
			return (profile.Data :: any) :: { [string]: any }
		end,
		prepare = function(): () -> ()
			local apply, followUp, landed = prepareProduct(session, key, receipt, quotedCash, paidRandomAllowed)
			return function()
				apply()
				after = followUp -- set only once this call's grant went through
				if landed then
					-- The grant stands from here: show it while the save is on its way (the save waits yield).
					task.defer(function()
						local ok, err = pcall(landed :: () -> ...any)
						if not ok then
							warn(`[Monetization] after granting {key}: {err}`)
						end
					end)
				end
			end
		end,
		saveAndWait = function()
			DataService.saveAndWait(profile, SAVE_TIMEOUT_SECONDS)
		end,
		maxSaveAttempts = MAX_SAVE_ATTEMPTS,
	})
	Replication.markDirty(session)
	if decision == "PurchaseGranted" then
		-- The call that granted it (or the first retry to find it saved, when that call's save hadn't landed) shows the
		-- follow-up and logs the purchase; Roblox retrying a receipt already granted logs nothing more.
		local followUp = after or unconfirmed[purchaseId]
		unconfirmed[purchaseId] = nil
		if followUp then
			task.spawn(followUp)
			Analytics.storeStep(session, "ProductPurchased", { "product", key })
			Analytics.custom(
				session,
				"product_purchased",
				if type(receipt.CurrencySpent) == "number" then receipt.CurrencySpent else 0,
				{ key }
			)
		end
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	if after then
		unconfirmed[purchaseId] = after -- granted here, the save not confirmed yet: Roblox will retry
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

local function processReceipt(receipt: { [string]: any }): Enum.ProductPurchaseDecision
	local playerId = receipt.PlayerId
	local productId = receipt.ProductId
	if type(playerId) ~= "number" or type(productId) ~= "number" then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local player = Players:GetPlayerByUserId(playerId)
	local key = productKeyForId(productId)
	if player == nil then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if key == nil then
		warn(`[Monetization] receipt for unknown product {productId}; check Config/Monetization`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return processFor(player, key, receipt)
end

-- Studio only: the real receipt path with a fake receipt, so a product can be tested before its id exists. Returns
-- the decision's name.
function MonetizationService.grantInStudio(player: Player, key: string): string
	assert(RunService:IsStudio(), "grantInStudio is Studio-only")
	local product = Monetization.products[key]
	assert(product ~= nil, `unknown product {key}`)
	local decision = processFor(player, key, {
		PlayerId = player.UserId,
		ProductId = product.id,
		PurchaseId = "studio-" .. HttpService:GenerateGUID(false),
		CurrencySpent = 0,
	})
	print(`[Monetization] Studio grant {key}: {decision.Name}`)
	return decision.Name
end

-- Studio-only: simulate a purchase so the full flow can be tested before real IDs exist.
local function onDevGrant(player: Player, keyArg: unknown)
	if not RunService:IsStudio() then
		return
	end
	local raw = Guard.shortString(keyArg, 40)
	if raw == nil then
		return
	end
	local passKey = string.match(raw, "^pass:(%w+)$")
	if passKey then
		local session = Sessions.get(player)
		for _, key in PASS_KEYS do
			if key == passKey and session then
				grantPass(session, key)
			end
		end
		return
	end
	local key = Guard.keyOf(raw, Monetization.products)
	if key == nil then
		return
	end
	MonetizationService.grantInStudio(player, key)
end

-- A game pass bought in-game. The event's `purchased` flag is not proof of a purchase, so Roblox is asked first
-- (UserOwnsGamePassAsync, retried): granted only when it says owned; when it can't answer, the pass joins the
-- background re-check (recheckPasses) like a failed lookup at join.
local function onPassPurchaseFinished(player: Player, passId: number, purchased: boolean)
	if not purchased then
		return
	end
	local key = passKeyForId(passId)
	if key == nil then
		return
	end
	local owns = ownsPass(player.UserId, passId)
	local session = Sessions.get(player)
	if owns == true and session then
		grantPass(session, key)
	elseif owns == nil or (owns == true and session == nil) then
		task.spawn(recheckPasses, player, { key }) -- unknown, or owned but the session is not ready yet
	end
end

function MonetizationService.start()
	MarketplaceService.ProcessReceipt = processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player: Player, passId: number, purchased: boolean)
			task.spawn(onPassPurchaseFinished, player, passId, purchased)
		end
	)
	-- The store's own intents (ClientEvent analytics, RequestPurchase) are StoreService's.
	if RunService:IsStudio() then
		Remotes.onIntent("DevGrantProduct", onDevGrant)
	end
end

return MonetizationService
