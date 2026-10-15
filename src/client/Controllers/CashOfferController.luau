--!strict
--[[
	The offer strip right under the cash pill, in the HUD's band (Logic/ScreenLayout "cashOffer"; the status pills make
	way while it shows). Two offers use it, one at a time:

	  "Need $X more?"   (server/Services/CashOfferService) when a purchase fails for lack of cash, the server may
	                    suggest the cheapest cash pack that covers the gap: how much more is needed, what the pack gives,
	                    a Robux button that opens Roblox's own purchase prompt (the cash arrives through the normal
	                    receipt flow, quoted at purchase time like the store card) and ✕. It replaces a Starter Pack offer.
	  the Starter Pack  once per account, a gentle card after the first rebirth or 30 minutes of total play
	                    (StateUpdate `store.starterOffer`, StarterPackRules.offerDue): "See it" opens the Shop at the
	                    Starter Pack's card, where everything it gives is listed (no purchase from the strip itself).
	                    Never during the tutorial, over a dialog, while carrying or over a cash offer
	                    (StarterPackRules.canShowOffer, checked on every state update and every 2 s while due); once
	                    shown the server is told (store_viewed "offer") and it never shows again.

	It sits above the play zone, away from the Buy prompt the player just tapped, and its button ignores taps for a
	moment after the strip appears, so a repeated tap on a prompt can't open a purchase. The strip never blocks play: it
	closes itself after a few seconds, on ✕, or once its button is pressed.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local GameData = require(ReplicatedStorage.Shared.GameData)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local ScreenLayout = require(ReplicatedStorage.Shared.Logic.ScreenLayout)
local StarterPackRules = require(ReplicatedStorage.Shared.Logic.StarterPackRules)
local StoreRules = require(ReplicatedStorage.Shared.Logic.StoreRules)
local Net = require(ReplicatedStorage.Shared.Net)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local Modal = require(script.Parent.Parent.UI.Modal)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local HudController = require(script.Parent.HudController)
local SoundPlayer = require(script.Parent.SoundPlayer)
local StateStore = require(script.Parent.StateStore)
local StoreController = require(script.Parent.StoreController)

local CashOfferController = {}

local SHOW_SECONDS = 8
local TAP_GUARD_SECONDS = 0.7 -- the button ignores taps this long after the strip appears
local STARTER_CHECK_SECONDS = 2 -- while the Starter Pack's offer is due, how often the moment is checked
local SIZE = ScreenLayout.SIZE.cashOffer
local TEXT = ScreenLayout.TEXT.cashOffer
local GAP = ScreenLayout.GAP

local localPlayer = Players.LocalPlayer
local current: Frame? = nil
local priceCache: { [number]: number } = {}
local starterShown = false -- the Starter Pack's offer showed this session (the server's flag keeps it once ever)

local function close(strip: Frame)
	if current == strip then
		current = nil
	end
	UiKit.popOut(strip, function()
		strip:Destroy()
	end)
end

-- Shows the product's Robux price on the button once Roblox returns it (cached for later offers).
local function showPrice(button: TextButton, id: number)
	local cached = priceCache[id]
	if cached then
		UiKit.setButtonText(button, `R$ {cached}`)
		return
	end
	UiKit.setButtonText(button, "...")
	task.spawn(function()
		local ok, info = pcall(function(): { [string]: any }
			return MarketplaceService:GetProductInfoAsync(id, Enum.InfoType.Product)
		end)
		local price = if ok and type(info.PriceInRobux) == "number" then info.PriceInRobux else nil
		if price then
			priceCache[id] = price
		end
		if button.Parent then
			UiKit.setButtonText(button, if price then `R$ {price}` else "R$ ?")
		end
	end)
end

type StripSpec = {
	name: string,
	title: string,
	body: string,
	buttonColor: Color3,
	onButton: () -> (),
	seconds: number,
}

-- Builds an offer strip (replacing the one showing) and returns its button. Text on the left, then the button and ✕
-- (Logic/ScreenLayout measures the same boxes).
local function strip(spec: StripSpec): TextButton
	local previous = current
	if previous then
		current = nil
		previous:Destroy()
	end
	-- HudController sizes and places the strip (narrower where Roblox's player list leaves less room).
	local frame = UiKit.panel({
		Name = spec.name,
		Size = UDim2.fromOffset(SIZE.w, SIZE.h),
	})
	local stroke = frame:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = UiTheme.palette("gold")
	end
	current = frame
	local shownAt = os.clock()
	local buttonsWidth = SIZE.inset + SIZE.close + GAP + SIZE.buy + GAP
	UiKit.label({
		Name = "Title",
		Text = spec.title,
		TextColor3 = UiTheme.palette("gold"),
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(SIZE.text, TEXT.top),
		Size = UDim2.new(1, -SIZE.text - buttonsWidth, 0, TEXT.title),
		Parent = frame,
	})
	UiKit.label({
		Name = "Body",
		Text = spec.body,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(SIZE.text, TEXT.top + TEXT.title),
		Size = UDim2.new(1, -SIZE.text - buttonsWidth, 0, TEXT.body),
		Parent = frame,
	})
	UiKit.button({
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -SIZE.inset, 0.5, 0),
		Size = UDim2.fromOffset(SIZE.close, SIZE.h - 2 * SIZE.inset),
		BackgroundColor3 = UiTheme.palette("danger"),
		Text = "X",
		Parent = frame,
	}, function()
		close(frame)
	end)
	local button = UiKit.button({
		Name = "Buy",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -SIZE.inset - SIZE.close - GAP, 0.5, 0),
		Size = UDim2.fromOffset(SIZE.buy, SIZE.h - 2 * SIZE.inset),
		BackgroundColor3 = spec.buttonColor,
		Parent = frame,
	}, function()
		-- A second tap meant for the prompt that just failed lands here: not a purchase.
		if os.clock() - shownAt < TAP_GUARD_SECONDS then
			return
		end
		spec.onButton()
		close(frame)
	end)
	HudController.place("cashOffer", frame)
	UiKit.popIn(frame)
	task.delay(spec.seconds, function()
		if current == frame then
			close(frame)
		end
	end)
	return button
end

local function show(payload: any)
	if
		type(payload) ~= "table"
		or type(payload.key) ~= "string"
		or type(payload.amount) ~= "number"
		or type(payload.shortfall) ~= "number"
	then
		return
	end
	local key = payload.key :: string
	local product = Monetization.products[key]
	local copy = (Theme.store :: any)[key]
	if product == nil or product.kind ~= "Cash" or copy == nil then
		return
	end
	local isStudio = RunService:IsStudio()
	if not StoreRules.visible(product.id, isStudio) then
		return -- not created on the Creator Hub yet: hidden outside Studio, like in the store
	end
	SoundPlayer.ui("error") -- the purchase itself still failed
	local buy = strip({
		name = "CashOffer",
		title = Format.template(Theme.text.cashOfferTitle, { amount = UiTheme.cash(payload.shortfall) }),
		body = Format.template(Theme.text.cashOfferBody, { pack = copy.name, amount = UiTheme.cash(payload.amount) }),
		buttonColor = UiTheme.palette("robux"),
		seconds = SHOW_SECONDS,
		onButton = function()
			Net.get("ClientEvent"):FireServer("cash_offer_clicked", key)
			if product.id ~= 0 then
				MarketplaceService:PromptProductPurchase(localPlayer, product.id)
			elseif isStudio then
				Net.get("DevGrantProduct"):FireServer(key)
			end
		end,
	})
	if product.id ~= 0 then
		showPrice(buy, product.id)
	else
		UiKit.setButtonText(buy, Theme.text.storeStudioGrant)
	end
end

-- The Starter Pack's one-time offer, when it is due and the moment is right (StarterPackRules.canShowOffer).
local function maybeOfferStarter()
	local state = StateStore.get()
	if state == nil then
		return
	end
	local ok = StarterPackRules.canShowOffer({
		due = state.store.starterOffer,
		inTutorial = state.tutorial.step ~= "",
		dialogOpen = Modal.isAnyOpen(),
		carrying = state.carrying ~= "",
		otherOffer = current ~= nil,
		shownThisSession = starterShown,
	})
	if not ok then
		return
	end
	starterShown = true
	Net.get("ClientEvent"):FireServer("store_viewed", "offer") -- analytics, and never again for this account
	local config = Monetization.starterPack
	local def = GameData.catalog.creatures[config.creatureId]
	local button = strip({
		name = "StarterOffer",
		title = Theme.text.starterOfferTitle,
		body = Format.template(Theme.text.starterOfferBody, {
			creature = if def then GameData.displayName(def, config.variant) else "",
			count = #config.gadgets,
		}),
		buttonColor = UiTheme.palette("gold"),
		seconds = config.offer.showSeconds,
		onButton = function()
			StoreController.open("StarterPack")
		end,
	})
	UiKit.setButtonText(button, Theme.text.starterOfferButton)
	SoundPlayer.ui("open")
end

function CashOfferController.start()
	Net.get("CashOffer").OnClientEvent:Connect(show)
	StateStore.onChange(function(state)
		if state.store.starterOffer and not starterShown then
			maybeOfferStarter()
		end
	end)
	-- A dialog closing or a carry ending doesn't always bring a state update: look again now and then while it's due.
	task.spawn(function()
		while not starterShown do
			task.wait(STARTER_CHECK_SECONDS)
			local state = StateStore.get()
			if state and state.store.starterOffer then
				maybeOfferStarter()
			end
		end
	end)
end

return CashOfferController
