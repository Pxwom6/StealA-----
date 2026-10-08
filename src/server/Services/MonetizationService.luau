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

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local Types = require(ReplicatedStorage.Shared.Types)
local EconomyMath = require(ReplicatedStorage.Shared.Logic.EconomyMath)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local Guard = require(ReplicatedStorage.Shared.Logic.Guard)
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
local SESSION_WAIT_SECONDS = 20
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

local function ownsPass(userId: number, passId: number): boolean
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
		task.wait(attempt)
	end
	warn(`[Monetization] could not check pass {passId} for {userId}`)
	return false
end

-- PlayerLifecycle hook: runs before the session exists.
function MonetizationService.checkPasses(player: Player): Types.Passes
	local passes: Types.Passes = { DoubleCash = false, VIP = false, ExtraPodiums = false, LongerLock = false }
	for _, key in PASS_KEYS do
		setPass(passes, key, ownsPass(player.UserId, Monetization.passes[key].id))
	end
	player:SetAttribute("VIP", passes.VIP)
	return passes
end

-- Re-applies everything a pass affects (income, podiums, lock length, VIP tag/trim).
local function applyPasses(session: Session)
	session.player:SetAttribute("VIP", session.passes.VIP)
	EconomyService.refresh(session)
	LockService.refresh(session)
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

-- Applies a product to the save. MUST NOT YIELD (see ReceiptLedger). Returns an optional follow-up that runs
-- after the purchase is confirmed saved (announcements, auto-lock...).
local function applyProduct(session: Session, key: string, receipt: { [string]: any }): AfterGrant?
	local product = Monetization.products[key]
	local data = session.data
	local robux = if type(receipt.CurrencySpent) == "number" then receipt.CurrencySpent else 0
	ReceiptLedger.appendHistory(data.purchaseHistory, {
		purchaseId = tostring(receipt.PurchaseId),
		productId = if type(receipt.ProductId) == "number" then receipt.ProductId else 0,
		key = key,
		robux = robux,
		at = os.time(),
	}, Monetization.purchaseHistorySize)
	data.stats.robuxSpent += robux

	if product.kind == "Cash" then
		local pack = (Economy.cashPacks :: any)[key] :: EconomyMath.CashPack
		local amount = EconomyMath.cashPackAmount(session.incomePerSecond, pack)
		data.cash += amount
		data.stats.totalEarned += amount
		Replication.markDirty(session)
		return function()
			Analytics.economySource(session, amount, "IAP", key)
			Remotes.notify(session.player, `+{UiTheme.cash(amount)}! {Theme.text.purchaseThanks}`, "success")
		end
	elseif product.kind == "LockToken" then
		data.lockTokens += 1
		Replication.markDirty(session)
		return function()
			if LockService.canLockNow(session) then
				LockService.tryLock(session)
			else
				Remotes.notify(session.player, Theme.text.lockTokenReady, "success")
			end
		end
	elseif product.kind == "ServerLuck" then
		local perks = Monetization.perks
		LiveOpsService.addLuckBoost(perks.serverLuckSeconds, perks.serverLuckMultiplier, "purchase")
		return function()
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
	end
	error(`unknown product kind for {key}`)
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
		grant = function()
			after = applyProduct(session, key, receipt)
		end,
		saveAndWait = function()
			DataService.saveAndWait(profile, SAVE_TIMEOUT_SECONDS)
		end,
		maxSaveAttempts = MAX_SAVE_ATTEMPTS,
	})
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
