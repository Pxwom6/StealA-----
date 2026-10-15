--!strict
--[[
	What the store UI says to the server: analytics, and asking to buy the products that can't always be bought.

	RequestPurchase(key, surface)   a Lucky Spin pack or the Starter Pack (Logic/StoreRules.CHECKED_KINDS). The server
	    checks it before Roblox's prompt opens (StoreRules.purchaseRefusal, on the server's own state): the product
	    exists on the Creator Hub (or this is Studio), a Lucky Spin pack needs the player's Roblox policy to allow paid
	    random items (PlayerPolicy, looked up first: it may yield, the checks after it don't) and fewer than
	    Config/Spin.paidBankFull spins banked, the Starter Pack must not be owned and needs a free podium. A refusal
	    says why (a toast); otherwise the client is told to open the prompt (PurchaseApproved), or in Studio, for a
	    product with no id yet, the fake receipt runs at once (MonetizationService.grantInStudio). The receipt path
	    checks again: a client can always open a prompt by itself.

	ClientEvent(name, arg)   analytics only, every field a known key:
	    store_opened             the store funnel's StoreOpened, and product_viewed (01 key, 02 "store") for each
	                             tracked item (Monetization.viewTracked) the Shop shows this player
	    store_product_clicked    ProductPrompted (01 key) for the items the client prompts by itself
	    cash_offer_clicked       cash_offer_clicked (01 cash pack key)
	    store_viewed             product_viewed (01 key, 02 the surface: "spin" for the Spin tab's pack buttons,
	                             "offer" for the Starter Pack's offer card, which then never shows again: the save flag
	                             StarterPackRules.OFFER_FLAG, set only while the offer is due)
	A view is logged at most once per item and surface per session.

	The Starter Pack's offer card is due after the first rebirth or the configured play time (StarterPackRules.offerDue,
	sent in StateUpdate `store`); play time grows without a state update, so every few seconds the state is marked
	dirty for whoever's due-ness changed.

	Analytics (beyond MonetizationService's purchases): ProductPrompted (01 key, 02 surface) when a checked purchase is
	approved, product_refused (01 key, 02 reason: StoreRules.REASONS) when it isn't.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Gadgets = require(ReplicatedStorage.Shared.Config.Gadgets)
local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)
local Spin = require(ReplicatedStorage.Shared.Config.Spin)
local GameData = require(ReplicatedStorage.Shared.GameData)
local DataSchema = require(ReplicatedStorage.Shared.Logic.DataSchema)
local Guard = require(ReplicatedStorage.Shared.Logic.Guard)
local Inventory = require(ReplicatedStorage.Shared.Logic.Inventory)
local PaidRandomItems = require(ReplicatedStorage.Shared.Logic.PaidRandomItems)
local SpinRules = require(ReplicatedStorage.Shared.Logic.SpinRules)
local StarterPackRules = require(ReplicatedStorage.Shared.Logic.StarterPackRules)
local StoreRules = require(ReplicatedStorage.Shared.Logic.StoreRules)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local Analytics = require(script.Parent.Analytics)
local MonetizationService = require(script.Parent.MonetizationService)
local PlayerPolicy = require(script.Parent.PlayerPolicy)
local Remotes = require(script.Parent.Remotes)
local Replication = require(script.Parent.Replication)
local Sessions = require(script.Parent.Sessions)

type Session = Sessions.Session

local StoreService = {}

local OFFER_CHECK_SECONDS = 5

-- "key|surface" views already logged, per session.
local viewed: { [Session]: { [string]: boolean } } = setmetatable({}, { __mode = "k" }) :: any
-- Whether the Starter Pack's offer was due at the last check, per session.
local lastDue: { [Session]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function logView(session: Session, key: string, surface: string)
	local seen = viewed[session]
	if seen == nil then
		seen = {}
		viewed[session] = seen
	end
	local id = `{key}|{surface}`
	if seen[id] then
		return
	end
	seen[id] = true
	Analytics.custom(session, "product_viewed", nil, { key, surface })
end

-- The purchase check's view of `session` (StoreRules.PurchaseContext) for product `key`.
local function context(session: Session, key: string, paidRandomAllowed: boolean): StoreRules.PurchaseContext
	local data = session.data
	return {
		visible = StoreRules.visible(Monetization.products[key].id, RunService:IsStudio()),
		paidRandomAllowed = paidRandomAllowed,
		spins = data.spin.spins,
		spinBankFull = Spin.paidBankFull,
		starterOwned = StarterPackRules.owns(data.flags),
		-- the Starter Pack's Snackling needs a podium a prize could take (a carrying thief keeps the last one)
		podiumFree = Inventory.prizeMayTakePodium(data.creatures, session.capacity, session.carry ~= nil),
	}
end

-- Whether the Starter Pack's one-time offer card is due for `session` (the same rule as its StateUpdate).
local function offerDue(session: Session): boolean
	local forSale = StoreRules.visible(Monetization.products.StarterPack.id, RunService:IsStudio())
	return StarterPackRules.offerDue(
		StarterPackRules.offerContext(session.data, session.tutorial ~= nil, forSale),
		Monetization.starterPack
	)
end

-- Whether tracked item `key` shows (and can be bought) on `surface` for this player right now.
local function shownTo(session: Session, key: string): boolean
	local isStudio = RunService:IsStudio()
	local pass = Monetization.passes[key]
	if pass then
		return StoreRules.visible(pass.id, isStudio) and not (session.passes :: any)[key]
	end
	local product = Monetization.products[key]
	if product == nil or not StoreRules.visible(product.id, isStudio) then
		return false
	end
	if StoreRules.PAID_RANDOM_KINDS[product.kind] then
		return PaidRandomItems.allowedByAttribute(session.player:GetAttribute(PaidRandomItems.ATTRIBUTE))
	elseif product.kind == "StarterPack" then
		return not StarterPackRules.owns(session.data.flags)
	end
	return true
end

local function onRequestPurchase(player: Player, keyArg: unknown, surfaceArg: unknown)
	local key = Guard.keyOf(keyArg, Monetization.products)
	local surface = Guard.oneOf(surfaceArg, StoreRules.SURFACES) or "store"
	if key == nil or not StoreRules.CHECKED_KINDS[Monetization.products[key].kind] then
		return -- only made-up keys and products the client prompts by itself get here: silence
	end
	local product = Monetization.products[key]
	-- The policy lookup may yield, so it comes first; nothing yields from the checks to the answer.
	local paidRandomAllowed = if StoreRules.PAID_RANDOM_KINDS[product.kind]
		then PlayerPolicy.paidRandomItemsAllowed(player)
		else true
	local session = Sessions.get(player)
	if session == nil then
		return
	end
	local reason = StoreRules.purchaseRefusal(product.kind, context(session, key, paidRandomAllowed))
	if reason then
		local messageKey = StoreRules.messageKey(reason)
		if messageKey then
			Remotes.notify(player, UiTheme.text(messageKey, { count = session.data.spin.spins }), "error")
		end
		Analytics.custom(session, "product_refused", nil, { key, reason })
		return
	end
	Analytics.storeStep(session, "ProductPrompted", { key, surface })
	if product.id == 0 then
		MonetizationService.grantInStudio(player, key) -- only Studio gets here (StoreRules.visible)
	else
		Remotes.fire(player, "PurchaseApproved", { key = key })
	end
end

local function onClientEvent(player: Player, nameArg: unknown, arg: unknown)
	local name = Guard.oneOf(nameArg, { "store_opened", "store_product_clicked", "cash_offer_clicked", "store_viewed" })
	local session = Sessions.get(player)
	if name == nil or session == nil then
		return
	end
	if name == "store_opened" then
		Analytics.storeStep(session, "StoreOpened")
		for _, key in Monetization.viewTracked do
			if shownTo(session, key) then
				logView(session, key, "store")
			end
		end
	elseif name == "cash_offer_clicked" then
		local key = Guard.keyOf(arg, Monetization.products)
		if key and Monetization.products[key].kind == "Cash" then
			Analytics.custom(session, "cash_offer_clicked", nil, { key })
		end
	elseif name == "store_viewed" then
		local surface = Guard.oneOf(arg, { "spin", "offer" })
		if surface == "spin" then
			for _, key in Monetization.viewTracked do
				local product = Monetization.products[key]
				if product and product.kind == "Spins" and shownTo(session, key) then
					logView(session, key, surface)
				end
			end
		elseif surface == "offer" and offerDue(session) then
			-- The offer card showed: once per account.
			session.data.flags[StarterPackRules.OFFER_FLAG] = true
			Replication.markDirty(session)
			logView(session, "StarterPack", surface)
		end
	else
		-- Only known keys reach a breakdown field: any other string from a client would add a value to the analytics
		-- breakdowns, so it is dropped instead.
		local key = Guard.keyOf(arg, Monetization.products) or Guard.keyOf(arg, Monetization.passes)
		if key then
			Analytics.storeStep(session, "ProductPrompted", { key })
		end
	end
end

function StoreService.start()
	local packs: { number } = {}
	for _, product in Monetization.products do
		if product.kind == "Spins" then
			table.insert(packs, product.spins or 0)
		end
	end
	for _, problem in SpinRules.validatePacks(packs, Spin, DataSchema.MAX_BANKED_SPINS) do
		warn(`[Store] config problem: {problem}`)
	end
	for _, problem in
		StarterPackRules.validate(
			Monetization.starterPack,
			GameData.catalog.creatures,
			GameData.catalog.mutations,
			Gadgets.order
		)
	do
		warn(`[Store] Starter Pack config problem: {problem}`)
	end
	Remotes.onIntent("ClientEvent", onClientEvent)
	Remotes.onIntent("RequestPurchase", onRequestPurchase)
	-- Play time crosses the offer's mark without a state update: mark the state dirty when the due-ness changes.
	task.spawn(function()
		while true do
			task.wait(OFFER_CHECK_SECONDS)
			local ok, err = pcall(function()
				for _, session in Sessions.all() do
					local due = offerDue(session)
					if lastDue[session] ~= due then
						lastDue[session] = due
						Replication.markDirty(session)
					end
				end
			end)
			if not ok then
				warn(`[Store] {err}`)
			end
		end
	end)
end

return StoreService
