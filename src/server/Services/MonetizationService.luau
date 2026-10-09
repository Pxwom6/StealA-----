--!strict
--[[
	Game passes and developer products.

	Passes: ownership is checked on join (UserOwnsGamePassAsync, with retries) and when bought in-game
	(PromptGamePassPurchaseFinished). Ownership lives in the session, not the save: Roblox is the source of truth.

	Products: MarketplaceService.ProcessReceipt → Logic/ReceiptLedger.process:
	  * the grant and the PurchaseId record happen together without yielding (no double grants on retry)
	  * PurchaseGranted is returned only once the PurchaseId is in the last SUCCESSFULLY SAVED data
	  * if the player is not in this server / the session ends first → NotProcessedYet (Roblox retries later)

	Studio: products/passes with id 0 can be tested with the "(Studio) Grant" store buttons, which run the exact
	same receipt path with a fake receipt. The DevGrantProduct remote does not exist outside Studio.
]]

local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local Types = require(ReplicatedStorage.Shared.Types)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local Guard = require(ReplicatedStorage.Shared.Logic.Guard)
local LiveOpsRules = require(ReplicatedStorage.Shared.Logic.LiveOpsRules)
local ReceiptLedger = require(ReplicatedStorage.Shared.Logic.ReceiptLedger)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local Analytics = require(script.Parent.Analytics)
local Announcer = require(script.Parent.Announcer)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local LiveOpsService = require(script.Parent.LiveOpsService)
local LockService = require(script.Parent.LockService)
local Remotes = require(script.Parent.Remotes)
local Replication = require(script.Parent.Replication)
local Sessions = require(script.Parent.Sessions)

type Session = Sessions.Session
local PASS_KEYS: { string } = { "DoubleCash", "VIP", "ExtraPodiums", "LongerLock" }
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
	local passes: Types.Passes = { DoubleCash = false, VIP = false, ExtraPodiums = false, LongerLock = false }
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
	Analytics.storeStep(session, "ProductPurchased", { kind = "pass", key = key })
	Analytics.custom(session, "pass_purchased", nil, { key = key })
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

-- Works out everything a product grants WITHOUT changing anything (it may throw: nothing is lost, Roblox retries).
-- Returns `apply`, which only writes the precomputed results (plain table writes: no yields, nothing that can fail;
-- see ReceiptLedger), and a follow-up that runs once the purchase is confirmed saved (announcements, auto-lock...).
local function prepareProduct(
	session: Session,
	key: string,
	receipt: { [string]: any },
	quotedCash: number
): (() -> (), AfterGrant?)
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
	local cash, tokens = 0, 0
	local newBoosts: { LiveOpsRules.Boost }? = nil
	local after: AfterGrant

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
		newBoosts = LiveOpsService.boostsWith(perks.serverLuckSeconds, perks.serverLuckMultiplier, "purchase", true)
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
	else
		error(`unknown product kind for {key}`)
	end

	local function apply()
		ReceiptLedger.appendHistory(data.purchaseHistory, historyEntry, historySize)
		data.stats.robuxSpent += robux
		data.cash += cash
		data.stats.totalEarned += cash
		data.lockTokens += tokens
		if newBoosts then
			LiveOpsService.setBoosts(newBoosts) -- the only write outside the save
		end
		Replication.markDirty(session) -- a flag: shows the new cash/tokens now, not after the save lands
	end
	return apply, after
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
	-- A cash pack's amount is fixed the first time its receipt reaches the player's session (and saved with the data),
	-- so if that grant fails and Roblox retries after the player's income changed (e.g. they rebirthed), the retry
	-- pays what the purchase was worth then. A receipt that finds no session yet waits for the load (see above).
	local quotedCash = 0
	if Monetization.products[key].kind == "Cash" and profile:IsActive() then
		quotedCash = ReceiptLedger.quote(session.data.cashPackQuotes, purchaseId, function(): number
			return EconomyService.cashPackAmount(session, key)
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
			local apply, followUp = prepareProduct(session, key, receipt, quotedCash)
			after = followUp
			return apply
		end,
		saveAndWait = function()
			DataService.saveAndWait(profile, SAVE_TIMEOUT_SECONDS)
		end,
		maxSaveAttempts = MAX_SAVE_ATTEMPTS,
	})
	Replication.markDirty(session)
	if decision == "PurchaseGranted" then
		local followUp = after
		if followUp then
			task.spawn(followUp)
		end
		Analytics.storeStep(session, "ProductPurchased", { kind = "product", key = key })
		Analytics.custom(
			session,
			"product_purchased",
			if type(receipt.CurrencySpent) == "number" then receipt.CurrencySpent else 0,
			{
				key = key,
			}
		)
		return Enum.ProductPurchaseDecision.PurchaseGranted
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
	local decision = processFor(player, key, {
		PlayerId = player.UserId,
		ProductId = Monetization.products[key].id,
		PurchaseId = "studio-" .. HttpService:GenerateGUID(false),
		CurrencySpent = 0,
	})
	print(`[Monetization] Studio grant {key}: {decision.Name}`)
end

local function onClientEvent(player: Player, nameArg: unknown, keyArg: unknown)
	local name = Guard.oneOf(nameArg, { "store_opened", "store_product_clicked" })
	local session = Sessions.get(player)
	if name == nil or session == nil then
		return
	end
	if name == "store_opened" then
		Analytics.storeStep(session, "StoreOpened")
	else
		local key = Guard.shortString(keyArg, 40)
		Analytics.storeStep(session, "ProductPrompted", { key = key or "" })
	end
end

function MonetizationService.start()
	MarketplaceService.ProcessReceipt = processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player: Player, passId: number, purchased: boolean)
			if not purchased then
				return
			end
			local key = passKeyForId(passId)
			local session = Sessions.get(player)
			if key and session then
				grantPass(session, key)
			end
		end
	)
	Remotes.onIntent("ClientEvent", onClientEvent)
	if RunService:IsStudio() then
		Remotes.onIntent("DevGrantProduct", onDevGrant)
	end
end

return MonetizationService
