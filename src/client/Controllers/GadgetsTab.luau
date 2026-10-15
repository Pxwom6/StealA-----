--!strict
--[[
	The Shop's Gadgets tab (StoreController): every gadget in Config/Gadgets with its icon, name, what it does, how long
	it recharges, and a button with its price in cash (green when affordable) that sends the BuyGadget intent, or
	"Owned". Gadgets are bought once with in-game cash and kept forever; nothing here costs Robux. The server checks
	the price, the cash and ownership again (GadgetService).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Gadgets = require(ReplicatedStorage.Shared.Config.Gadgets)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local Net = require(ReplicatedStorage.Shared.Net)
local Types = require(ReplicatedStorage.Shared.Types)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local GadgetRules = require(ReplicatedStorage.Shared.Logic.GadgetRules)
local UiKit = require(script.Parent.Parent.UI.UiKit)

local GadgetsTab = {}

local CARD_HEIGHT = 104
local ICON_SIZE = 72
local BUY_WIDTH = 150
local HEADER_HEIGHT = 26

type Card = { id: string, buy: TextButton }

-- Builds the tab in `content`; returns the function that refreshes it from the player's state.
function GadgetsTab.build(content: Frame): (state: Types.ClientState) -> ()
	UiKit.label({
		Name = "Header",
		Text = Theme.text.gadgetsHeader,
		Size = UDim2.new(1, 0, 0, HEADER_HEIGHT),
		TextColor3 = UiTheme.palette("gold"),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = content,
	})
	local scroller = UiKit.new("ScrollingFrame", {
		Name = "Gadgets",
		Position = UDim2.fromOffset(0, HEADER_HEIGHT + 4),
		Size = UDim2.new(1, 0, 1, -(HEADER_HEIGHT + 4)),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = content,
	}) :: ScrollingFrame
	UiKit.new("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
		Parent = scroller,
	})

	local cards: { Card } = {}
	local ownedNow: { [string]: boolean } = {}
	for order, id in Gadgets.order do
		local def = Gadgets.gadgets[id]
		local accent = UiTheme.color(def.color)
		local frame = UiKit.panel({
			Name = id,
			LayoutOrder = order,
			Size = UDim2.new(1, -12, 0, CARD_HEIGHT),
			BackgroundColor3 = UiTheme.palette("panelLight"),
			Parent = scroller,
		})
		local swatch = UiKit.new("Frame", {
			Name = "Icon",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 14, 0.5, 0),
			Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE),
			BackgroundColor3 = accent,
			Parent = frame,
		}) :: Frame
		UiKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = swatch })
		UiKit.stroke(UiKit.STROKE.normal).Parent = swatch
		UiKit.label({
			Text = def.icon,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.7, 0.7),
			Parent = swatch,
		})
		local textLeft = 14 + ICON_SIZE + 12
		local textWidth = -(textLeft + BUY_WIDTH + 24)
		UiKit.label({
			Name = "Name",
			Text = UiTheme.text(def.nameKey),
			Size = UDim2.new(1, textWidth, 0, 30),
			Position = UDim2.fromOffset(textLeft, 8),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = accent,
			Parent = frame,
		})
		UiKit.label({
			Name = "Description",
			Text = UiTheme.text(def.descriptionKey, GadgetRules.describe(def)),
			FontFace = UiTheme.bodyFont,
			TextScaled = false,
			TextSize = 15,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Size = UDim2.new(1, textWidth, 0, 40),
			Position = UDim2.fromOffset(textLeft, 40),
			Parent = frame,
		})
		UiKit.label({
			Name = "Recharge",
			Text = Format.template(Theme.text.gadgetRechargeLine, { cooldown = def.cooldownSeconds }),
			FontFace = UiTheme.bodyFont,
			TextScaled = false,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = UiTheme.palette("textDim"),
			Size = UDim2.new(1, textWidth, 0, 18),
			Position = UDim2.fromOffset(textLeft, 80),
			Parent = frame,
		})
		local buy = UiKit.button({
			Name = "Buy",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.fromOffset(BUY_WIDTH, 58),
			BackgroundColor3 = UiTheme.palette("panel"),
			Text = UiTheme.cash(def.price),
			Parent = frame,
		}, function()
			if not ownedNow[id] then
				Net.get("BuyGadget"):FireServer(id)
			end
		end)
		table.insert(cards, { id = id, buy = buy })
	end
	UiKit.label({
		Name = "Hint",
		LayoutOrder = #Gadgets.order + 1,
		Text = Theme.text.gadgetsHint,
		FontFace = UiTheme.bodyFont,
		TextScaled = false,
		TextSize = 14,
		TextWrapped = true,
		TextColor3 = UiTheme.palette("textDim"),
		Size = UDim2.new(1, -12, 0, 36),
		Parent = scroller,
	})

	return function(state: Types.ClientState)
		table.clear(ownedNow)
		for _, id in state.gadgets.owned do
			ownedNow[id] = true
		end
		for _, card in cards do
			local def = Gadgets.gadgets[card.id]
			if ownedNow[card.id] then
				UiKit.setButtonText(card.buy, Theme.text.storeOwned)
				card.buy.BackgroundColor3 = UiTheme.palette("panel")
			else
				UiKit.setButtonText(card.buy, UiTheme.cash(def.price))
				-- green when there is enough cash; tapping it anyway gets the server's "Not enough cash!"
				card.buy.BackgroundColor3 = if state.cash >= def.price
					then UiTheme.palette("success")
					else UiTheme.palette("panel")
			end
		end
	end
end

return GadgetsTab
