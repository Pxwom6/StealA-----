--!strict
--[[
	The Rewards panel's Spin tab (the Lucky Spin; server: SpinService, config: Config/Spin): a reel of prize tiles
	under a gold marker, a SPIN! button and when the next free spin comes. The server picks the prize; when its answer
	(SpinResult) arrives the reel spins and slows down onto that tile, then the prize shows as a toast (above the
	dialog: NotificationController). If the panel was closed meanwhile, the toast shows at once.

	"Odds" swaps the reel for a grid of every prize with its exact chance (UI/OddsGrid, readable at a glance), and
	"Back" returns. While the grid shows, SPIN! makes way for "Details", which opens the list of every outcome of a
	spin, every Snackling included, with its exact chance (UI/OddsDetails, Logic/SpinOdds: the odds never change).
	While the base is full a warning says Snackling prizes will be sold.

	Lucky Spin packs (Robux, Config/Monetization kind "Spins"): two buttons right of the reel, each with its spins and
	price. They are paid random items, so they show only to a player whose Roblox policy allows those (the player
	attribute in Logic/PaidRandomItems, so not while it is being looked up) and only once the packs exist on the Creator
	Hub (Studio: always); the Odds view sits right beside them. A tap goes through PurchaseController (checked here, then
	on the server, before Roblox's prompt opens); while the spin bank holds Config/Spin.paidBankFull spins they say
	"Bank full". Where everything goes: Logic/StoreLayout.spinTab (checked on every checked screen by tools/layoutCheck.luau).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)
local Spin = require(ReplicatedStorage.Shared.Config.Spin)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local Net = require(ReplicatedStorage.Shared.Net)
local Types = require(ReplicatedStorage.Shared.Types)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local PaidRandomItems = require(ReplicatedStorage.Shared.Logic.PaidRandomItems)
local SpinRules = require(ReplicatedStorage.Shared.Logic.SpinRules)
local StoreLayout = require(ReplicatedStorage.Shared.Logic.StoreLayout)
local OddsDetails = require(script.Parent.Parent.UI.OddsDetails)
local OddsGrid = require(script.Parent.Parent.UI.OddsGrid)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local NotificationController = require(script.Parent.NotificationController)
local PurchaseController = require(script.Parent.PurchaseController)
local SoundPlayer = require(script.Parent.SoundPlayer)
local StateStore = require(script.Parent.StateStore)

local SpinTab = {}

local S = StoreLayout.SPIN
local REEL_HEIGHT = S.reel
local TILE = 100
local TILE_GAP = 8
local PITCH = TILE + TILE_GAP
local STRIP_TILES = 34 -- the winner sits near the end, so the reel runs a good way first
local SPIN_SECONDS = 3.6 -- under SpinService.REEL_SECONDS

-- The Lucky Spin packs in store order; the layout has room for two (pack1, pack2).
local PACKS: { string } = {}
for _, key in Monetization.storeProducts do
	local product = Monetization.products[key]
	if product and product.kind == "Spins" and #PACKS < 2 then
		table.insert(PACKS, key)
	end
end

type PackButton = { key: string, button: TextButton, price: TextLabel }

type Built = {
	content: Frame,
	reel: Frame,
	strip: Frame,
	odds: Frame,
	oddsCells: Frame?,
	oddsButton: TextButton,
	details: TextButton, -- in SPIN!'s place while the Odds view shows
	detailsView: GuiObject?, -- the Details list, built the first time it opens
	button: TextButton,
	status: TextLabel,
	warning: TextLabel,
	packs: { PackButton },
	packsShown: boolean?, -- the layout last applied (nil: none yet)
	policyWatch: RBXScriptConnection,
	spinning: boolean,
}

local built: Built? = nil
local random = Random.new()
local packsViewSent = false -- the pack buttons' view was reported this session (analytics)

local function setRect(object: GuiObject, r: StoreLayout.Rect)
	object.AnchorPoint = Vector2.zero
	object.Position = UDim2.fromOffset(r.x, r.y)
	object.Size = UDim2.fromOffset(r.w, r.h)
end

-- Whether pack `key`'s button shows: paid random items allowed by this player's policy, and the pack exists on the
-- Creator Hub (or this is Studio). A full spin bank still shows it, saying so.
local function packShown(key: string, state: Types.ClientState): boolean
	local refusal = PurchaseController.refusal(key, state)
	return refusal == nil or refusal == "bankFull"
end

-- Whether the layout makes room for the pack buttons (any of them shows).
local function anyPackShown(state: Types.ClientState?): boolean
	if state == nil then
		return false
	end
	for _, key in PACKS do
		if packShown(key, state) then
			return true
		end
	end
	return false
end

local function tile(segment: Types.SpinSegment, cash: number, order: number, parent: Instance): Frame
	local frame = UiKit.panel({
		Name = segment.id,
		LayoutOrder = order,
		Size = UDim2.fromOffset(TILE, TILE),
		BackgroundColor3 = UiTheme.color(segment.color),
		Parent = parent,
	})
	UiKit.label({
		Name = "Icon",
		Text = segment.icon,
		Size = UDim2.new(1, 0, 0, 44),
		Position = UDim2.fromOffset(0, 6),
		Parent = frame,
	})
	UiKit.label({
		Name = "Label",
		Text = if cash > 0 then UiTheme.cash(cash) else segment.label,
		Size = UDim2.new(1, -8, 0, 30),
		Position = UDim2.fromOffset(4, 56),
		Parent = frame,
	})
	return frame
end

-- Fills the strip with tiles: `winner` (an index into Spin.segments) at `at`, random ones elsewhere.
local function fill(strip: Frame, rewards: { number }, winner: number?, at: number)
	for _, child in strip:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local chances = SpinRules.chances(Spin.segments)
	for order = 1, STRIP_TILES do
		local index: number
		if order == at and winner then
			index = winner
		else
			-- Weighted like the real odds, so rare prizes look rare on the reel too.
			local roll, running = random:NextNumber(), 0
			index = #Spin.segments
			for candidate, chance in chances do
				running += chance
				if roll < running then
					index = candidate
					break
				end
			end
		end
		tile(Spin.segments[index], rewards[index] or 0, order, strip)
	end
end

-- The strip's X that puts tile `at`'s centre (plus `jitter` px) under the marker.
local function stripX(reelWidth: number, at: number, jitter: number): number
	return reelWidth / 2 - ((at - 1) * PITCH + TILE / 2) - jitter
end

local function showOdds(current: Built, shown: boolean)
	current.odds.Visible = shown
	current.button.Visible = not shown
	current.details.Visible = shown
	local view = current.detailsView
	if view and not shown then
		view.Visible = false
	end
	UiKit.setButtonText(current.oddsButton, if shown then Theme.text.spinOddsBack else Theme.text.spinOdds)
end

-- The Details list over the whole tab (built the first time), with what each cash prize pays this player now.
local function showDetails(current: Built)
	local view = current.detailsView
	if view == nil then
		local state = StateStore.get()
		local area = StoreLayout.content(StoreLayout.REWARDS)
		local overlay: GuiObject
		overlay = OddsDetails.build(
			current.content,
			{ x = 0, y = 0, w = area.w, h = area.h },
			20,
			if state then state.spin.rewards else {},
			function()
				overlay.Visible = false
			end
		)
		current.detailsView = overlay
		view = overlay
	end
	if view then
		view.Visible = true
	end
end

-- Puts everything where StoreLayout.spinTab says, with or without the pack buttons.
local function applyLayout(current: Built, withPacks: boolean)
	if current.packsShown == withPacks then
		return
	end
	current.packsShown = withPacks
	local boxes = StoreLayout.spinTab(withPacks)
	setRect(current.reel, boxes.reel.rect)
	setRect(current.odds, boxes.odds.rect)
	setRect(current.warning, boxes.warning.rect)
	setRect(current.button, boxes.spin.rect)
	setRect(current.details, boxes.details.rect)
	setRect(current.oddsButton, boxes.oddsButton.rect)
	setRect(current.status, boxes.status.rect)
	-- The odds grid fills the reel's place, so it is rebuilt at the new width.
	local old = current.oddsCells
	if old then
		old:Destroy()
	end
	local r = boxes.odds.rect
	current.oddsCells = OddsGrid.build(current.odds, { x = 0, y = 0, w = r.w, h = r.h }, 5)
	for index, pack in current.packs do
		local slot = boxes[`pack{index}`]
		if slot then
			setRect(pack.button, slot.rect)
		else
			pack.button.Visible = false
		end
	end
	if withPacks and not packsViewSent then
		packsViewSent = true
		Net.get("ClientEvent"):FireServer("store_viewed", "spin") -- analytics: product_viewed for each pack
	end
end

local function buildPack(content: Frame, key: string): PackButton
	local product = Monetization.products[key]
	local button = UiKit.button({
		Name = key,
		BackgroundColor3 = UiTheme.palette("robux"),
		Text = Format.template(Theme.text.spinPackName, { count = product.spins or 0 }),
		Visible = false,
		Parent = content,
	}, function()
		SoundPlayer.ui("click")
		PurchaseController.request(key, "spin")
	end)
	-- Its spins over its price, as Logic/StoreLayout.packText measures them.
	local name = button:FindFirstChild("Label") :: TextLabel
	name.Size = UDim2.new(1, 0, 0, S.packName)
	local price = UiKit.label({
		Name = "Price",
		Text = "",
		Position = UDim2.fromOffset(0, S.packName),
		Size = UDim2.new(1, 0, 0, S.packPrice),
		Parent = button,
	})
	PurchaseController.priceText(key, function(text: string)
		if price.Parent then
			price:SetAttribute("Price", text)
			price.Text = text
		end
	end)
	return { key = key, button = button, price = price }
end

-- Builds the tab into `content`; returns its refresh.
function SpinTab.build(content: Frame): (state: Types.ClientState) -> ()
	local reel = UiKit.panel({
		Name = "Reel",
		BackgroundColor3 = UiTheme.palette("stroke"),
		ClipsDescendants = true,
		Parent = content,
	})
	local strip = UiKit.new("Frame", {
		Name = "Strip",
		Position = UDim2.fromOffset(0, (REEL_HEIGHT - TILE) / 2),
		Size = UDim2.fromOffset(STRIP_TILES * PITCH, TILE),
		BackgroundTransparency = 1,
		Parent = reel,
	}) :: Frame
	UiKit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, TILE_GAP),
		Parent = strip,
	})
	UiKit.new("Frame", {
		Name = "Marker",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(0, 4, 1, 0),
		BackgroundColor3 = UiTheme.palette("gold"),
		ZIndex = 3,
		Parent = reel,
	})
	local odds = UiKit.panel({
		Name = "Odds",
		BackgroundColor3 = UiTheme.palette("stroke"),
		Visible = false,
		ZIndex = 4,
		Parent = content,
	})
	local status = UiKit.label({
		Name = "Status",
		Text = "",
		FontFace = UiTheme.bodyFont,
		TextColor3 = UiTheme.palette("textDim"),
		Parent = content,
	})
	local warning = UiKit.label({
		Name = "BaseFull",
		Text = Theme.text.prizesBaseFull,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = UiTheme.palette("danger"),
		Visible = false,
		Parent = content,
	})
	local button = UiKit.button({
		Name = "Spin",
		BackgroundColor3 = UiTheme.palette("panel"),
		Text = Theme.text.spinButton,
		Parent = content,
	}, function()
		local current = built
		local latest = StateStore.get()
		if current == nil or current.spinning or latest == nil then
			return
		end
		if not latest.spin.ready then
			NotificationController.toast(Theme.text.spinNotReady, "info")
			return
		end
		current.spinning = true
		showOdds(current, false)
		SoundPlayer.ui("open")
		Net.get("Spin"):FireServer()
		-- Unlocks itself if the server never answers (a refused spin).
		task.delay(SPIN_SECONDS + 2, function()
			if built == current then
				current.spinning = false
			end
		end)
	end)
	local oddsButton = UiKit.button({
		Name = "OddsButton",
		BackgroundColor3 = UiTheme.palette("panelLight"),
		Text = Theme.text.spinOdds,
		Parent = content,
	}, function()
		local current = built
		if current then
			showOdds(current, not current.odds.Visible)
		end
	end)
	local details = UiKit.button({
		Name = "Details",
		BackgroundColor3 = UiTheme.palette("luck"),
		Text = Theme.text.spinDetails,
		Visible = false,
		Parent = content,
	}, function()
		local current = built
		if current then
			SoundPlayer.ui("click")
			showDetails(current)
		end
	end)
	local packs: { PackButton } = {}
	for _, key in PACKS do
		table.insert(packs, buildPack(content, key))
	end

	local state = StateStore.get()
	fill(strip, if state then state.spin.rewards else {}, nil, 1)
	local refresh: (state: Types.ClientState) -> ()
	local current: Built = {
		content = content,
		reel = reel,
		strip = strip,
		odds = odds,
		oddsCells = nil,
		oddsButton = oddsButton,
		details = details,
		detailsView = nil,
		button = button,
		status = status,
		warning = warning,
		packs = packs,
		packsShown = nil,
		-- The policy lookup can finish while the tab is open: the pack buttons may appear.
		policyWatch = Players.LocalPlayer:GetAttributeChangedSignal(PaidRandomItems.ATTRIBUTE):Connect(function()
			local latest = StateStore.get()
			if latest and built then
				refresh(latest)
			end
		end),
		spinning = false,
	}
	built = current
	applyLayout(current, anyPackShown(state))

	refresh = function(latest: Types.ClientState)
		local view = latest.spin
		local now = workspace:GetServerTimeNow()
		local freeReady = now >= view.nextFreeAt
		local withPacks = anyPackShown(latest)
		applyLayout(current, withPacks)
		current.button.BackgroundColor3 = if view.ready and not current.spinning
			then UiTheme.palette("success")
			else UiTheme.palette("panel")
		UiKit.setButtonText(
			current.button,
			if not freeReady and view.spins > 0
				then Format.template(Theme.text.spinButtonBanked, { count = view.spins })
				else Theme.text.spinButton
		)
		local free = if freeReady
			then ""
			else Format.template(Theme.text.spinFreeIn, { time = Format.clock(view.nextFreeAt - now) })
		local banked = if view.spins > 0 then Format.template(Theme.text.spinBanked, { count = view.spins }) else ""
		current.status.Text = if free ~= "" and banked ~= "" then `{free} · {banked}` else free .. banked
		current.warning.Visible = latest.baseFull
		-- A full spin bank: the packs say so (a tap explains), instead of a price.
		for _, pack in current.packs do
			pack.button.Visible = withPacks and packShown(pack.key, latest)
			local full = PurchaseController.refusal(pack.key, latest) == "bankFull"
			pack.button.BackgroundColor3 = if full then UiTheme.palette("panel") else UiTheme.palette("robux")
			local priceText = pack.price:GetAttribute("Price")
			pack.price.Text = if full
				then Theme.text.spinPackFull
				elseif type(priceText) == "string" then priceText
				else pack.price.Text
		end
	end
	return refresh
end

-- Forgets the built tab (the panel closed or switched tabs).
function SpinTab.clear()
	local current = built
	if current then
		current.policyWatch:Disconnect()
	end
	built = nil
end

local function onResult(payload: { index: number, text: string })
	local current = built
	local index = payload.index
	if current == nil or current.reel.Parent == nil or Spin.segments[index] == nil then
		if built and built.reel.Parent == nil then
			SpinTab.clear()
		end
		NotificationController.toast(payload.text, "success")
		SoundPlayer.ui("claim")
		return
	end
	current.spinning = true
	showOdds(current, false) -- the reel shows the prize
	local state = StateStore.get()
	local at = STRIP_TILES - 3
	fill(current.strip, if state then state.spin.rewards else {}, index, at)
	local width = current.reel.AbsoluteSize.X / math.max(0.01, UiKit.scaleFor(workspace.CurrentCamera.ViewportSize))
	current.strip.Position = UDim2.fromOffset(stripX(width, 3, 0), (REEL_HEIGHT - TILE) / 2)
	local target = stripX(width, at, random:NextNumber(-TILE * 0.3, TILE * 0.3))
	local tween = TweenService:Create(
		current.strip,
		TweenInfo.new(SPIN_SECONDS, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Position = UDim2.fromOffset(target, (REEL_HEIGHT - TILE) / 2) }
	)
	tween.Completed:Once(function()
		NotificationController.toast(payload.text, "success")
		SoundPlayer.ui("claim")
		if built == current then
			current.spinning = false
		end
	end)
	tween:Play()
end

function SpinTab.start()
	Net.get("SpinResult").OnClientEvent:Connect(onResult)
end

return SpinTab
