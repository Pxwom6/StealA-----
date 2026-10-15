--!strict
--[[
	"Need $X more?" offers (server/Services/CashOfferService). When a purchase fails for lack of cash, the server may
	suggest the cheapest cash pack that covers the gap; this shows it as a strip right under the cash pill, in the
	HUD's band (Logic/ScreenLayout; the status pills make way while it shows): how much more is needed, what the pack
	gives, a Robux button that opens Roblox's own purchase prompt (the cash arrives through the normal receipt flow,
	quoted at purchase time like the store card) and ✕.

	It sits above the play zone, away from the Buy prompt the player just tapped, and the Robux button ignores taps for
	a moment after the strip appears, so a repeated tap on the prompt can't open a purchase. The strip never blocks
	play: it closes itself after a few seconds, on ✕, or once the button is pressed, and a new offer replaces the old
	one. The server decides when an offer is allowed (not during the tutorial, a cooldown).
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local ScreenLayout = require(ReplicatedStorage.Shared.Logic.ScreenLayout)
local StoreRules = require(ReplicatedStorage.Shared.Logic.StoreRules)
local Net = require(ReplicatedStorage.Shared.Net)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local HudController = require(script.Parent.HudController)
local SoundPlayer = require(script.Parent.SoundPlayer)

local CashOfferController = {}

local SHOW_SECONDS = 8
local TAP_GUARD_SECONDS = 0.7 -- the Robux button ignores taps this long after the strip appears
local SIZE = ScreenLayout.SIZE.cashOffer
local TEXT = ScreenLayout.TEXT.cashOffer
local GAP = ScreenLayout.GAP

local localPlayer = Players.LocalPlayer
local current: Frame? = nil
local priceCache: { [number]: number } = {}

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
	local previous = current
	if previous then
		current = nil
		previous:Destroy()
	end
	SoundPlayer.ui("error") -- the purchase itself still failed

	-- HudController sizes and places the strip (narrower where Roblox's player list leaves less room).
	local strip = UiKit.panel({
		Name = "CashOffer",
		Size = UDim2.fromOffset(SIZE.w, SIZE.h),
	})
	local stroke = strip:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = UiTheme.palette("gold")
	end
	current = strip
	local shownAt = os.clock()
	-- Text on the left, then the Robux button and ✕ (Logic/ScreenLayout measures the same boxes).
	local buttonsWidth = SIZE.inset + SIZE.close + GAP + SIZE.buy + GAP
	UiKit.label({
		Name = "Title",
		Text = Format.template(Theme.text.cashOfferTitle, { amount = UiTheme.cash(payload.shortfall) }),
		TextColor3 = UiTheme.palette("gold"),
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(SIZE.text, TEXT.top),
		Size = UDim2.new(1, -SIZE.text - buttonsWidth, 0, TEXT.title),
		Parent = strip,
	})
	UiKit.label({
		Name = "Body",
		Text = Format.template(Theme.text.cashOfferBody, { pack = copy.name, amount = UiTheme.cash(payload.amount) }),
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(SIZE.text, TEXT.top + TEXT.title),
		Size = UDim2.new(1, -SIZE.text - buttonsWidth, 0, TEXT.body),
		Parent = strip,
	})
	UiKit.button({
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -SIZE.inset, 0.5, 0),
		Size = UDim2.fromOffset(SIZE.close, SIZE.h - 2 * SIZE.inset),
		BackgroundColor3 = UiTheme.palette("danger"),
		Text = "X",
		Parent = strip,
	}, function()
		close(strip)
	end)
	local buy = UiKit.button({
		Name = "Buy",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -SIZE.inset - SIZE.close - GAP, 0.5, 0),
		Size = UDim2.fromOffset(SIZE.buy, SIZE.h - 2 * SIZE.inset),
		BackgroundColor3 = UiTheme.palette("robux"),
		Parent = strip,
	}, function()
		-- A second tap meant for the Buy prompt that just failed lands here: not a purchase.
		if os.clock() - shownAt < TAP_GUARD_SECONDS then
			return
		end
		Net.get("ClientEvent"):FireServer("cash_offer_clicked", key)
		if product.id ~= 0 then
			MarketplaceService:PromptProductPurchase(localPlayer, product.id)
		elseif isStudio then
			Net.get("DevGrantProduct"):FireServer(key)
		end
		close(strip)
	end)
	if product.id ~= 0 then
		showPrice(buy, product.id)
	else
		UiKit.setButtonText(buy, Theme.text.storeStudioGrant)
	end
	HudController.place("cashOffer", strip)
	UiKit.popIn(strip)
	task.delay(SHOW_SECONDS, function()
		if current == strip then
			close(strip)
		end
	end)
end

function CashOfferController.start()
	Net.get("CashOffer").OnClientEvent:Connect(show)
end

return CashOfferController
