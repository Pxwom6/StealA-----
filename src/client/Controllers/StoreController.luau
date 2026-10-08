--!strict
--[[
	The Snack Shop.
	  * Forever perks (game passes) show "Owned" once bought.
	  * Cash packs show the exact amount you'd get right now (scaled to your current income).
	  * Server Luck shows the exact belt odds now vs. with the boost before you buy (random effect → disclose odds).
	  * Items whose id is still 0 show "Coming soon" — or, in Studio, a "(Studio) Grant" button that runs the real
	    server receipt path, so purchases are testable before the IDs exist.
	Opening the store and tapping an item are reported for the analytics store funnel.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Gameplay = require(ReplicatedStorage.Shared.Config.Gameplay)
local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local GameData = require(ReplicatedStorage.Shared.GameData)
local Net = require(ReplicatedStorage.Shared.Net)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local EconomyMath = require(ReplicatedStorage.Shared.Logic.EconomyMath)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local RarityRoll = require(ReplicatedStorage.Shared.Logic.RarityRoll)
local LiveOps = require(ReplicatedStorage.Shared.Config.LiveOps)
local Modal = require(script.Parent.Parent.UI.Modal)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local HudController = require(script.Parent.HudController)
local LockController = require(script.Parent.LockController)
local SoundPlayer = require(script.Parent.SoundPlayer)
local StateStore = require(script.Parent.StateStore)

local StoreController = {}

local localPlayer = Players.LocalPlayer
local priceCache: { [string]: number } = {}

local CARD_HEIGHT = 112

local function copyVars(): { [string]: any }
	local perks = Monetization.perks
	return {
		vipBonus = math.floor(perks.vipIncomeBonus * 100),
		extraPodiums = perks.extraPodiums,
		lockSeconds = perks.longerLockSeconds,
		minVulnerable = Gameplay.lock.minVulnerableSeconds,
		luckMultiplier = perks.serverLuckMultiplier,
		luckMinutes = math.floor(perks.serverLuckSeconds / 60),
	}
end

local function fetchPrice(kind: "pass" | "product", id: number, label: TextLabel)
	local cacheKey = `{kind}:{id}`
	local cached = priceCache[cacheKey]
	if cached then
		label.Text = `R$ {cached}`
		return
	end
	label.Text = "..."
	task.spawn(function()
		local ok, info = pcall(function(): { [string]: any }
			return MarketplaceService:GetProductInfoAsync(
				id,
				if kind == "pass" then Enum.InfoType.GamePass else Enum.InfoType.Product
			)
		end)
		local price = if ok and type(info.PriceInRobux) == "number" then info.PriceInRobux else nil
		if price then
			priceCache[cacheKey] = price
			label.Text = `R$ {price}`
		else
			label.Text = "R$ ?"
		end
	end)
end

local function oddsText(): string
	local catalog = GameData.catalog
	local luckAttr = workspace:GetAttribute("LuckMultiplier")
	local currentLuck = if type(luckAttr) == "number" then luckAttr else 1
	local boosted =
		math.clamp(currentLuck * Monetization.perks.serverLuckMultiplier, 1, LiveOps.limits.maxLuckMultiplier)
	local events: { [string]: boolean } = {}
	local idsAttr = workspace:GetAttribute("ActiveEventIds")
	if type(idsAttr) == "string" then
		for id in string.gmatch(idsAttr, "[^,]+") do
			events[id] = true
		end
	end
	local before = RarityRoll.odds(catalog.rarityList, catalog.creatureList, currentLuck, events)
	local after = RarityRoll.odds(catalog.rarityList, catalog.creatureList, boosted, events)
	local lines: { string } = {}
	for index, entry in before do
		local rarity = catalog.rarities[entry.id]
		table.insert(
			lines,
			`<font color="{rarity.color}">{rarity.displayName}</font> {Format.percent(entry.chance)} -> {Format.percent(
				after[index].chance
			)}`
		)
	end
	return table.concat(lines, "   ")
end

type CardSpec = {
	key: string,
	kind: "pass" | "product",
	id: number,
	order: number,
	accent: Color3,
	detail: string?,
	richDetail: boolean?,
}

local function card(parent: Instance, spec: CardSpec, owned: boolean): Frame
	local copy = Theme.store[spec.key]
	local vars = copyVars()
	local frame = UiKit.panel({
		LayoutOrder = spec.order,
		Size = UDim2.new(1, -8, 0, if spec.richDetail then CARD_HEIGHT + 46 else CARD_HEIGHT),
		BackgroundColor3 = UiTheme.palette("panelLight"),
		Parent = parent,
	})
	local stripe = UiKit.new("Frame", {
		Size = UDim2.new(0, 10, 1, 0),
		BackgroundColor3 = spec.accent,
		Parent = frame,
	}) :: Frame
	UiKit.corner(6).Parent = stripe
	UiKit.label({
		Text = Format.template(copy.name, vars),
		Size = UDim2.new(1, -200, 0, 34),
		Position = UDim2.fromOffset(20, 8),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = spec.accent,
		Parent = frame,
	})
	local description = UiKit.label({
		Text = Format.template(copy.description, vars),
		FontFace = UiTheme.bodyFont,
		TextScaled = false,
		TextSize = 15,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, -200, 0, 40),
		Position = UDim2.fromOffset(20, 44),
		Parent = frame,
	})
	if spec.detail then
		local detail = UiKit.label({
			Text = spec.detail,
			RichText = spec.richDetail == true,
			FontFace = UiTheme.bodyFont,
			TextScaled = false,
			TextSize = 14,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = UiTheme.palette("gold"),
			Size = UDim2.new(1, -200, 0, if spec.richDetail then 70 else 24),
			Position = UDim2.fromOffset(20, 84),
			Parent = frame,
		})
		if spec.richDetail then
			description.Size = UDim2.new(1, -200, 0, 36)
			detail.Position = UDim2.fromOffset(20, 80)
		end
	end

	local buyButton: TextButton
	local isStudio = RunService:IsStudio()
	local configured = spec.id ~= 0
	buyButton = UiKit.button({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(160, 58),
		BackgroundColor3 = if owned
			then UiTheme.palette("panel")
			elseif configured or isStudio then UiTheme.palette("robux")
			else UiTheme.palette("panel"),
		Text = "",
		Parent = frame,
	}, function()
		if owned then
			return
		end
		SoundPlayer.ui("click")
		Net.get("ClientEvent"):FireServer("store_product_clicked", spec.key)
		if not configured then
			if isStudio then
				local devKey = if spec.kind == "pass" then "pass:" .. spec.key else spec.key
				Net.get("DevGrantProduct"):FireServer(devKey)
			end
			return
		end
		if spec.kind == "pass" then
			MarketplaceService:PromptGamePassPurchase(localPlayer, spec.id)
		else
			MarketplaceService:PromptProductPurchase(localPlayer, spec.id)
		end
	end)
	local priceLabel = UiKit.label({ Size = UDim2.fromScale(1, 1), Parent = buyButton })
	if owned then
		priceLabel.Text = Theme.text.storeOwned
	elseif configured then
		fetchPrice(spec.kind, spec.id, priceLabel)
	elseif isStudio then
		priceLabel.Text = Theme.text.storeStudioGrant
	else
		priceLabel.Text = Theme.text.storeUnavailable
	end
	return frame
end

local function header(parent: Instance, order: number, text: string)
	UiKit.label({
		LayoutOrder = order,
		Text = text,
		Size = UDim2.new(1, -8, 0, 34),
		TextColor3 = UiTheme.palette("gold"),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = parent,
	})
end

function StoreController.open(focusKey: string?)
	local state = StateStore.get()
	if state == nil then
		return
	end
	Net.get("ClientEvent"):FireServer("store_opened")
	SoundPlayer.ui("click")
	local modal = Modal.open(Theme.text.storeTitle, Vector2.new(640, 440))
	local scroller = UiKit.new("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = modal.body,
	}) :: ScrollingFrame
	UiKit.new("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
		Parent = scroller,
	})

	local cards: { [string]: Frame } = {}
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	-- Boosts first: they are the impulse buys and the server-hero moment.
	header(scroller, nextOrder(), Theme.text.storeProductsHeader)
	for _, key in Monetization.storeProducts do
		local product = Monetization.products[key]
		local detail: string? = nil
		local rich = false
		local accent = UiTheme.palette("cash")
		if product.kind == "Cash" then
			local pack = (Economy.cashPacks :: any)[key] :: EconomyMath.CashPack
			detail = "+" .. UiTheme.cash(EconomyMath.cashPackAmount(state.income, pack))
		elseif product.kind == "ServerLuck" then
			detail = Theme.text.oddsHeader .. "\n" .. oddsText()
			rich = true
			accent = UiTheme.palette("luck")
		elseif product.kind == "LockToken" then
			accent = UiTheme.palette("lock")
			if state.lockTokens > 0 then
				detail = Format.template(Theme.text.lockPillToken, { count = state.lockTokens })
			end
		end
		cards[key] = card(scroller, {
			key = key,
			kind = "product",
			id = product.id,
			order = nextOrder(),
			accent = accent,
			detail = detail,
			richDetail = rich,
		}, false)
	end

	header(scroller, nextOrder(), Theme.text.storePassesHeader)
	for _, key in Monetization.storePasses do
		local pass = Monetization.passes[key]
		local owned = (state.passes :: any)[key] == true
		cards[key] = card(scroller, {
			key = key,
			kind = "pass",
			id = pass.id,
			order = nextOrder(),
			accent = if key == "VIP" then UiTheme.palette("vip") else UiTheme.palette("primary"),
		}, owned)
	end

	local focus = if focusKey then cards[focusKey] else nil
	if focus then
		task.defer(function()
			scroller.CanvasPosition = Vector2.new(0, focus.AbsolutePosition.Y - scroller.AbsolutePosition.Y)
		end)
	end
end

function StoreController.start()
	local side = HudController.addSideButton(1, "🛒", Theme.text.storeButton, UiTheme.palette("robux"), function()
		StoreController.open()
	end)
	side.button.LayoutOrder = 1
	LockController.onPillTappedWhileRecharging = function()
		StoreController.open("InstantLock")
	end
end

return StoreController
