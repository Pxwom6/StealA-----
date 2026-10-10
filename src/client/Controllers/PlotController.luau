--!strict
--[[
	Client-side visuals for the 8 plots, driven entirely by replicated attributes:
	  * podium billboards: name (rarity colour; a mutation such as "Golden" in its own colour), cash/sec,
	    uncollected cash, "being stolen!" warning, and an "EVENT" tag over limited-time Snacklings
	  * shield countdown over each entrance (lock or new-player protection)
	  * a big "YOUR BASE" marker over your own plot so a new player always knows where home is
	  * your own entrance barrier is made non-collidable locally, so the lock never blocks the owner
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local GameData = require(ReplicatedStorage.Shared.GameData)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local UiKit = require(script.Parent.Parent.UI.UiKit)

local PlotController = {}

local localPlayer = Players.LocalPlayer

type PlotView = {
	model: Model,
	barrier: BasePart,
	shieldLabel: TextLabel,
	shieldGui: BillboardGui,
	homeMarker: BillboardGui,
	upgradeGui: BillboardGui,
	upgradeLabel: TextLabel,
}

local views: { PlotView } = {}

local function isMine(plot: Model): boolean
	return plot:GetAttribute("OwnerUserId") == localPlayer.UserId
end

-- Podium billboard rows in pixels; the "EVENT" tag row only shows (and the billboard only grows) for event Snacklings.
local PODIUM_GUI_WIDTH = 170
local PODIUM_GUI_HEIGHT = 78
local EVENT_TAG_HEIGHT = 16

local function setupPodium(podium: Model)
	local base = podium:WaitForChild("Base") :: BasePart
	local gui = UiKit.new("BillboardGui", {
		Name = "PodiumInfo",
		Size = UDim2.fromOffset(PODIUM_GUI_WIDTH, PODIUM_GUI_HEIGHT),
		StudsOffsetWorldSpace = Vector3.new(0, 8.5, 0),
		MaxDistance = 55,
		LightInfluence = 0,
		Enabled = false,
		Parent = base,
	}) :: BillboardGui
	UiKit.new("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Parent = gui,
	})
	local eventLabel = UiKit.label({
		LayoutOrder = 0,
		Size = UDim2.new(1, 0, 0, EVENT_TAG_HEIGHT),
		Text = Theme.text.eventTag,
		Visible = false,
		Parent = gui,
	})
	local nameLabel = UiKit.label({ LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 25), RichText = true, Parent = gui })
	local incomeLabel = UiKit.label({
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 20),
		TextColor3 = UiTheme.palette("cash"),
		Parent = gui,
	})
	local storedLabel = UiKit.label({
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, 28),
		TextColor3 = UiTheme.palette("gold"),
		Parent = gui,
	})
	local function showEventTag(eventId: string?)
		eventLabel.Visible = eventId ~= nil
		if eventId then
			eventLabel.TextColor3 = UiTheme.eventColor(eventId)
		end
		gui.Size = UDim2.fromOffset(PODIUM_GUI_WIDTH, PODIUM_GUI_HEIGHT + (if eventId then EVENT_TAG_HEIGHT else 0))
	end

	local function update()
		local creatureId = podium:GetAttribute("CreatureId")
		local def = if type(creatureId) == "string" then GameData.catalog.creatures[creatureId] else nil
		local beingStolen = podium:GetAttribute("BeingStolen") == true
		if def == nil and not beingStolen then
			gui.Enabled = false
			return
		end
		gui.Enabled = true
		if beingStolen then
			showEventTag(nil)
			nameLabel.Text = UiTheme.escapeRich(Theme.text.carryMarker)
			nameLabel.TextColor3 = UiTheme.palette("danger")
			incomeLabel.Text = ""
			storedLabel.Text = ""
			return
		end
		if def == nil then
			gui.Enabled = false
			return
		end
		showEventTag(def.eventId)
		local variant = podium:GetAttribute("Variant")
		nameLabel.Text = UiTheme.creatureNameRich(def, if type(variant) == "string" then variant else nil)
		nameLabel.TextColor3 = UiTheme.palette("text") -- the rich text colours each word
		local income = podium:GetAttribute("Income")
		incomeLabel.Text = UiTheme.perSecond(if type(income) == "number" then income else 0)
		local stored = podium:GetAttribute("Stored")
		storedLabel.Text = UiTheme.cash(if type(stored) == "number" then stored else 0)
	end
	for _, attribute in { "CreatureId", "Variant", "Stored", "Income", "BeingStolen" } do
		podium:GetAttributeChangedSignal(attribute):Connect(update)
	end
	update()
end

local function setupPlot(plot: Model)
	local barrier = plot:WaitForChild("Barrier") :: BasePart
	local sign = plot:WaitForChild("Sign") :: BasePart
	local upgradePad = plot:WaitForChild("UpgradePad") :: BasePart

	local shieldGui = UiKit.new("BillboardGui", {
		Name = "Shield",
		Size = UDim2.fromOffset(240, 44),
		StudsOffsetWorldSpace = Vector3.new(0, 2, 0),
		MaxDistance = 140,
		LightInfluence = 0,
		Enabled = false,
		Parent = barrier,
	}) :: BillboardGui
	local shieldLabel = UiKit.label({ Size = UDim2.fromScale(1, 1), Parent = shieldGui })

	local homeMarker = UiKit.new("BillboardGui", {
		Name = "HomeMarker",
		Size = UDim2.fromOffset(160, 50),
		StudsOffsetWorldSpace = Vector3.new(0, 7, 0),
		AlwaysOnTop = true,
		MaxDistance = 1000,
		LightInfluence = 0,
		Enabled = false,
		Parent = sign,
	}) :: BillboardGui
	UiKit.label({
		Text = "YOUR BASE",
		Size = UDim2.fromScale(1, 1),
		TextColor3 = UiTheme.palette("gold"),
		Parent = homeMarker,
	})

	local upgradeGui = UiKit.new("BillboardGui", {
		Name = "Upgrade",
		Size = UDim2.fromOffset(170, 56),
		StudsOffsetWorldSpace = Vector3.new(0, 4.5, 0),
		MaxDistance = 60,
		LightInfluence = 0,
		Enabled = false,
		Parent = upgradePad,
	}) :: BillboardGui
	local upgradeLabel = UiKit.label({ Size = UDim2.fromScale(1, 1), Parent = upgradeGui })

	local view: PlotView = {
		model = plot,
		barrier = barrier,
		shieldLabel = shieldLabel,
		shieldGui = shieldGui,
		homeMarker = homeMarker,
		upgradeGui = upgradeGui,
		upgradeLabel = upgradeLabel,
	}
	table.insert(views, view)

	local function applyOwnership()
		local mine = isMine(plot)
		homeMarker.Enabled = mine
		upgradeGui.Enabled = mine
		if mine then
			barrier.CanCollide = false
		end
	end
	local function applyUpgradeCost()
		local cost = plot:GetAttribute("NextPodiumCost")
		if type(cost) == "number" and cost >= 0 then
			upgradeLabel.Text = Format.template(Theme.text.podiumUpgradeSign, { price = UiTheme.cash(cost) })
		else
			upgradeLabel.Text = Theme.text.podiumMaxSign
		end
	end
	plot:GetAttributeChangedSignal("OwnerUserId"):Connect(applyOwnership)
	plot:GetAttributeChangedSignal("NextPodiumCost"):Connect(applyUpgradeCost)
	-- The server turns collision on while locked; the owner's client always walks through.
	barrier:GetPropertyChangedSignal("CanCollide"):Connect(function()
		if isMine(plot) and barrier.CanCollide then
			barrier.CanCollide = false
		end
	end)
	applyOwnership()
	applyUpgradeCost()

	local podiums = plot:WaitForChild("Podiums")
	for _, podium in podiums:GetChildren() do
		if podium:IsA("Model") then
			task.spawn(setupPodium, podium)
		end
	end
end

local function updateShields()
	local now = workspace:GetServerTimeNow()
	for _, view in views do
		local lockedUntil = view.model:GetAttribute("LockedUntil")
		local graceUntil = view.model:GetAttribute("GraceUntil")
		local locked = if type(lockedUntil) == "number" then lockedUntil - now else 0
		local grace = if type(graceUntil) == "number" then graceUntil - now else 0
		if locked > 0 then
			view.shieldGui.Enabled = true
			view.shieldLabel.Text = Format.template(Theme.text.lockedBanner, { time = Format.clock(locked) })
			view.shieldLabel.TextColor3 = UiTheme.palette("lock")
		elseif grace > 0 then
			view.shieldGui.Enabled = true
			view.shieldLabel.Text = Format.template(Theme.text.protectedBanner, { time = Format.clock(grace) })
			view.shieldLabel.TextColor3 = UiTheme.palette("gold")
		else
			view.shieldGui.Enabled = false
		end
	end
end

-- The Model for the local player's plot, if assigned.
function PlotController.myPlot(): Model?
	for _, view in views do
		if isMine(view.model) then
			return view.model
		end
	end
	return nil
end

function PlotController.plots(): { Model }
	local list: { Model } = {}
	for _, view in views do
		table.insert(list, view.model)
	end
	return list
end

function PlotController.start()
	local plotsFolder = workspace:WaitForChild("Map"):WaitForChild("Plots")
	for _, plot in plotsFolder:GetChildren() do
		if plot:IsA("Model") then
			setupPlot(plot)
		end
	end
	task.spawn(function()
		while true do
			updateShields()
			task.wait(0.25)
		end
	end)
end

return PlotController
