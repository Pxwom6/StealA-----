--!strict
--[[
	Buying the products that are checked before Roblox's prompt opens (Logic/StoreRules.CHECKED_KINDS: the Lucky Spin
	packs and the Starter Pack). Every buy button for them calls PurchaseController.request(key, surface):
	  1. the client checks the server's rule on its own state (StoreRules.purchaseRefusal) and, when it says no, shows
	     why at once (a toast) without asking: a full spin bank, paid random items not allowed, the pack owned...;
	  2. otherwise it asks the server (RequestPurchase), which checks again on its own state;
	  3. the server answers PurchaseApproved, and only then does Roblox's prompt open (only for a request made here in
	     the last few seconds), or a toast saying why not. In Studio a product with no id yet is granted through the
	     test receipt at once instead.
	What was bought arrives through the normal receipt flow (MonetizationService), which checks everything a third time.

	Also the Robux prices of those products (Roblox's own, cached), for the Spin tab's pack buttons.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)
local Spin = require(ReplicatedStorage.Shared.Config.Spin)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local Net = require(ReplicatedStorage.Shared.Net)
local Types = require(ReplicatedStorage.Shared.Types)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local PaidRandomItems = require(ReplicatedStorage.Shared.Logic.PaidRandomItems)
local StoreRules = require(ReplicatedStorage.Shared.Logic.StoreRules)
local NotificationController = require(script.Parent.NotificationController)
local StateStore = require(script.Parent.StateStore)

local PurchaseController = {}

local APPROVAL_SECONDS = 15 -- an approval arriving later than this after the tap opens nothing
local REQUEST_DEBOUNCE = 0.8 -- one tap is one request

local localPlayer = Players.LocalPlayer
local askedAt: { [string]: number } = {} -- product key -> os.clock() of the last request
local prices: { [number]: number } = {} -- product id -> Robux

-- Whether this player's Roblox policy allows paid random items (false while it is being looked up).
function PurchaseController.paidRandomAllowed(): boolean
	return PaidRandomItems.allowedByAttribute(localPlayer:GetAttribute(PaidRandomItems.ATTRIBUTE))
end

-- The purchase check's view of this player for product `key` (the server builds the same from its own state).
function PurchaseController.context(key: string, state: Types.ClientState): StoreRules.PurchaseContext
	local product = Monetization.products[key]
	return {
		visible = product ~= nil and StoreRules.visible(product.id, RunService:IsStudio()),
		paidRandomAllowed = PurchaseController.paidRandomAllowed(),
		spins = state.spin.spins,
		spinBankFull = Spin.paidBankFull,
		starterOwned = state.store.starterOwned,
		-- the server also keeps a carrying thief's last podium for the delivery (Inventory.prizeMayTakePodium)
		podiumFree = not state.baseFull,
	}
end

-- Why `key` can't be bought right now by this client's view (nil: it can; the server has the last word).
function PurchaseController.refusal(key: string, state: Types.ClientState): string?
	local product = Monetization.products[key]
	if product == nil then
		return "unknown"
	end
	return StoreRules.purchaseRefusal(product.kind, PurchaseController.context(key, state))
end

-- A buy button for checked product `key` was tapped on `surface` (StoreRules.SURFACES).
function PurchaseController.request(key: string, surface: string)
	local state = StateStore.get()
	if state == nil then
		return
	end
	local reason = PurchaseController.refusal(key, state)
	if reason then
		local messageKey = StoreRules.messageKey(reason)
		if messageKey then
			NotificationController.toast(UiTheme.text(messageKey, { count = state.spin.spins }), "error")
		end
		return
	end
	local now = os.clock()
	local last = askedAt[key]
	if last and now - last < REQUEST_DEBOUNCE then
		return
	end
	askedAt[key] = now
	Net.get("RequestPurchase"):FireServer(key, surface)
end

-- Calls `show` with product `key`'s price text ("R$ 25"), at once when known ("..." meanwhile), or the Studio grant
-- label for a product with no id yet.
function PurchaseController.priceText(key: string, show: (text: string) -> ())
	local product = Monetization.products[key]
	if product == nil then
		return
	end
	if product.id == 0 then
		show(Theme.text.storeStudioGrant)
		return
	end
	local cached = prices[product.id]
	if cached then
		show(`R$ {cached}`)
		return
	end
	show("...")
	task.spawn(function()
		local ok, info = pcall(function(): { [string]: any }
			return MarketplaceService:GetProductInfoAsync(product.id, Enum.InfoType.Product)
		end)
		local price = if ok and type(info.PriceInRobux) == "number" then info.PriceInRobux else nil
		if price then
			prices[product.id] = price
		end
		show(if price then `R$ {price}` else "R$ ?")
	end)
end

function PurchaseController.start()
	Net.get("PurchaseApproved").OnClientEvent:Connect(function(payload: any)
		if type(payload) ~= "table" or type(payload.key) ~= "string" then
			return
		end
		local key = payload.key :: string
		local product = Monetization.products[key]
		local at = askedAt[key]
		-- Only the answer to a tap made here, a moment ago, opens a prompt.
		if product == nil or product.id == 0 or at == nil or os.clock() - at > APPROVAL_SECONDS then
			return
		end
		askedAt[key] = nil
		MarketplaceService:PromptProductPurchase(localPlayer, product.id)
	end)
end

return PurchaseController
