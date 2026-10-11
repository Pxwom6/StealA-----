--!strict
--[[
	"Need $X more?" card (server/Services/CashOfferService). When a purchase fails for lack of cash, the server may
	suggest the cheapest cash pack that covers the gap; this shows it as a small card above the bottom of the screen:
	how much more is needed, what the pack gives, and a Robux button that opens Roblox's own purchase prompt (the cash
	arrives through the normal receipt flow, quoted at purchase time like the store card).

	The card never blocks play: it closes itself after a few seconds, on ✕, or once the button is pressed, and a new
	offer replaces the old one. The server decides when an offer is allowed (not during the tutorial, cooldown).
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local Net = require(ReplicatedStorage.Shared.Net)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local SoundPlayer = require(script.Parent.SoundPlayer)

local CashOfferController = {}

local SHOW_SECONDS = 8
local CARD_SIZE = Vector2.new(420, 150)

local localPlayer = Players.LocalPlayer
local screen: ScreenGui
local current: Frame? = nil
local priceCache: { [number]: number } = {}

local function close(card: Frame)
	if current == card then
		current = nil
	end
	UiKit.popOut(card, function()
		card:Destroy()
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
	if product.id == 0 and not isStudio then
		return
	end
	local previous = current
	if previous then
		current = nil
		previous:Destroy()
	end
	SoundPlayer.ui("error") -- the purchase itself still failed

	local card = UiKit.panel({
		Name = "CashOffer",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -120),
		Size = UDim2.fromOffset(CARD_SIZE.X, CARD_SIZE.Y),
		Parent = screen,
	})
	current = card
	UiKit.label({
		Text = Format.template(Theme.text.cashOfferTitle, { amount = UiTheme.cash(payload.shortfall) }),
		TextColor3 = UiTheme.palette("gold"),
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(18, 14),
		Size = UDim2.new(1, -80, 0, 40),
		Parent = card,
	})
	UiKit.label({
		Text = Format.template(Theme.text.cashOfferBody, { pack = copy.name, amount = UiTheme.cash(payload.amount) }),
		FontFace = UiTheme.bodyFont,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(18, 62),
		Size = UDim2.new(1, -210, 0, 70),
		Parent = card,
	})
	UiKit.button({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.fromOffset(42, 42),
		BackgroundColor3 = UiTheme.palette("danger"),
		Text = "X",
		Parent = card,
	}, function()
		close(card)
	end)
	local buy = UiKit.button({
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -14, 1, -14),
		Size = UDim2.fromOffset(170, 60),
		BackgroundColor3 = UiTheme.palette("robux"),
		Parent = card,
	}, function()
		Net.get("ClientEvent"):FireServer("cash_offer_clicked", key)
		if product.id ~= 0 then
			MarketplaceService:PromptProductPurchase(localPlayer, product.id)
		elseif isStudio then
			Net.get("DevGrantProduct"):FireServer(key)
		end
		close(card)
	end)
	if product.id ~= 0 then
		showPrice(buy, product.id)
	else
		UiKit.setButtonText(buy, Theme.text.storeStudioGrant)
	end
	UiKit.popIn(card)
	task.delay(SHOW_SECONDS, function()
		if current == card then
			close(card)
		end
	end)
end

function CashOfferController.start()
	screen = UiKit.screen("CashOffer", 6) -- above the HUD and toasts, below modals (10)
	Net.get("CashOffer").OnClientEvent:Connect(show)
end

return CashOfferController
