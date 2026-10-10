--!strict
--[[
	The Snackdex (collection book) UI. The server owns the data (SnackdexService → SnackdexSync); this only shows it.

	* Side button "Snackdex" (4th in the left column) with a red dot while there are discoveries not looked at yet.
	* Panel: a tab per rarity tier (its regular Snacklings, "3/4", a tick when complete) and an "Event" tab for
	  limited-time Snacklings (they never block a tier); a line with the tier's reward (or "Complete!") and the
	  collection bonus; then a page of cards. Discovered: a live 3D preview (the CreatureVisuals model in a ViewportFrame,
	  gently swaying), name, income and a pip per mutation (filled once owned with it). Undiscovered: the same model as a
	  black silhouette and "???". Everything comes from the creature list, so new Snacklings need no change here.
	* Cheap: models are built only for the visible page (5 cards), destroyed on every page / tab change and when the
	  panel closes, and the sway runs only while it is open.
	* Feedback: a "NEW! ..." toast per discovery (and a NEW tag on its card until the panel is next closed); a completed
	  tier gets the big announcement banner, sparkles and its rarity sound. Rewards are claimed by the server on its own.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Snackdex = require(ReplicatedStorage.Shared.Config.Snackdex)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local CreatureVisuals = require(ReplicatedStorage.Shared.CreatureVisuals)
local GameData = require(ReplicatedStorage.Shared.GameData)
local Net = require(ReplicatedStorage.Shared.Net)
local Types = require(ReplicatedStorage.Shared.Types)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local SnackdexRules = require(ReplicatedStorage.Shared.Logic.SnackdexRules)
local Modal = require(script.Parent.Parent.UI.Modal)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local HudController = require(script.Parent.HudController)
local NotificationController = require(script.Parent.NotificationController)
local SoundPlayer = require(script.Parent.SoundPlayer)
local StateStore = require(script.Parent.StateStore)

type Section = {
	id: string, -- rarity id, or SnackdexRules.EVENT_SECTION
	label: string,
	color: Color3,
	creatures: { Types.CreatureDef }, -- in config order
	isEvent: boolean,
}

type Card = { frame: Frame, camera: Camera?, target: Vector3, distance: number, phase: number }

type TabView = { button: TextButton, name: TextLabel, count: TextLabel, badge: Frame }

type Panel = {
	modal: Modal.ModalHandle,
	section: Section,
	page: number,
	tabs: { [string]: TabView },
	cardRow: Frame,
	cards: { Card },
	infoLabel: TextLabel,
	bonusLabel: TextLabel,
	pageLabel: TextLabel,
	prev: TextButton,
	next: TextButton,
}

local SnackdexController = {}

-- Reference px (Modal keeps heights <= 340 so it fits a landscape phone; 720 wide fits 640x360 too).
local PANEL_SIZE = Vector2.new(720, 340)
local TAB_HEIGHT = 44
local TAB_GAP = 6
local MIN_TAB_WIDTH = 78
local INFO_TOP = 50
local CARDS_TOP = 76
local ARROW_WIDTH = 40
local CARD_GAP = 8
local CARDS_PER_PAGE = 5
local PIP_SIZE = 12

-- Preview camera: a narrow lens, a little above the face (models face -Z), swaying left and right.
local FIELD_OF_VIEW = 32
local SWAY_ANGLE = 0.55 -- radians each way
local SWAY_SPEED = 0.9
local CAMERA_RISE = 0.28 -- of the distance

local catalog = GameData.catalog
local sections: { Section } = {}

local sideButton: HudController.SideButton
local panel: Panel? = nil
local swayConnection: RBXScriptConnection? = nil

-- What the server last sent.
local owned: { [string]: boolean } = {}
local ownedVariants: { [string]: { [string]: boolean } } = {}
local completedTiers: { [string]: boolean } = {}
local incomeBonus = 0
-- Discoveries not looked at yet (the button's dot clears when the panel opens; the NEW tags when it closes).
local newIds: { [string]: boolean } = {}
local lastDiscovery: string? = nil

local function percent(fraction: number): number
	return math.floor(fraction * 100 + 0.5)
end

local function setStroke(frame: GuiObject, color: Color3, thickness: number?)
	local stroke = frame:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = color
		if thickness then
			stroke.Thickness = thickness
		end
	end
end

local function buildSections()
	for _, rarity in catalog.rarityList do
		table.insert(sections, {
			id = rarity.id,
			label = rarity.displayName,
			color = UiTheme.color(rarity.color),
			creatures = SnackdexRules.section(catalog.creatureList, rarity.id),
			isEvent = false,
		})
	end
	local eventCreatures = SnackdexRules.section(catalog.creatureList, SnackdexRules.EVENT_SECTION)
	if #eventCreatures > 0 then
		table.insert(sections, {
			id = SnackdexRules.EVENT_SECTION,
			label = Theme.text.snackdexEventTab,
			color = UiTheme.palette("event"),
			creatures = eventCreatures,
			isEvent = true,
		})
	end
end

local function sectionOf(creatureId: string): (Section?, number)
	for _, section in sections do
		for index, def in section.creatures do
			if def.id == creatureId then
				return section, index
			end
		end
	end
	return nil, 0
end

local function foundIn(section: Section): number
	local found = 0
	for _, def in section.creatures do
		if owned[def.id] then
			found += 1
		end
	end
	return found
end

local function hasNew(section: Section): boolean
	for _, def in section.creatures do
		if newIds[def.id] then
			return true
		end
	end
	return false
end

local function pageCount(section: Section): number
	return math.max(1, math.ceil(#section.creatures / CARDS_PER_PAGE))
end

-- Cards ---------------------------------------------------------------------------------------------------------------

local function newPip(color: Color3, filled: boolean, order: number, parent: Instance)
	local pip = UiKit.new("Frame", {
		LayoutOrder = order,
		Size = UDim2.fromOffset(PIP_SIZE, PIP_SIZE),
		BackgroundColor3 = if filled then color else UiTheme.palette("panel"),
		BackgroundTransparency = if filled then 0 else 0.2,
		Parent = parent,
	})
	UiKit.corner(PIP_SIZE // 2).Parent = pip
	UiKit.stroke(2, if filled then UiTheme.palette("stroke") else color).Parent = pip
end

-- One card: discovered → live preview, name, income and mutation pips; undiscovered → black silhouette and "???".
local function buildCard(def: Types.CreatureDef, order: number, width: number, height: number, parent: Instance): Card
	local discovered = owned[def.id] == true
	local rarity = catalog.rarities[def.rarity]
	local rarityColor = UiTheme.rarityColor(def.rarity)
	local frame = UiKit.panel({
		Name = def.id,
		LayoutOrder = order,
		Size = UDim2.fromOffset(width, height),
		BackgroundColor3 = UiTheme.palette("panelLight"),
		Parent = parent,
	})
	setStroke(frame, if discovered then rarityColor else UiTheme.palette("stroke"), 3)

	local previewHeight = height - 84
	local disc = UiKit.new("Frame", {
		Name = "Backdrop",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 4 + previewHeight / 2),
		Size = UDim2.fromOffset(previewHeight - 8, previewHeight - 8),
		BackgroundColor3 = if discovered then rarityColor else UiTheme.palette("panel"),
		BackgroundTransparency = if discovered then 0.72 else 0.25,
		Parent = frame,
	})
	UiKit.corner((previewHeight - 8) // 2).Parent = disc
	local viewport = UiKit.new("ViewportFrame", {
		Name = "Preview",
		Position = UDim2.fromOffset(4, 4),
		Size = UDim2.new(1, -8, 0, previewHeight),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(165, 165, 185),
		LightColor = Color3.fromRGB(255, 250, 240),
		LightDirection = Vector3.new(-0.4, -1, 0.7),
		-- Undiscovered: the same model, multiplied to black: a silhouette that hints at the shape and nothing else.
		ImageColor3 = if discovered then Color3.new(1, 1, 1) else Color3.new(0, 0, 0),
		ImageTransparency = if discovered then 0 else 0.1,
		Parent = frame,
	}) :: ViewportFrame

	local card: Card = { frame = frame, camera = nil, target = Vector3.zero, distance = 10, phase = order * 1.3 }
	if rarity then
		local ok, model = pcall(CreatureVisuals.build, def, rarity, { anchored = true })
		if ok then
			-- A ViewportFrame never draws particles, lights, beams or trails: drop the rarity / mutation effects (and any
			-- sound) the model would carry there for nothing.
			for _, descendant in model:GetDescendants() do
				if
					descendant:IsA("ParticleEmitter")
					or descendant:IsA("Light")
					or descendant:IsA("Beam")
					or descendant:IsA("Trail")
					or descendant:IsA("Sound")
				then
					descendant:Destroy()
				end
			end
			-- Feet at the origin; a ViewportFrame has no physics, so every part is placed by PivotTo itself.
			model:PivotTo(CFrame.new())
			local modelHeight = CreatureVisuals.height(model)
			local _, size = model:GetBoundingBox()
			local extent = math.max(size.X, modelHeight, size.Z, 0.5)
			card.target = Vector3.new(0, modelHeight * 0.5, 0)
			card.distance = extent * 0.62 / math.tan(math.rad(FIELD_OF_VIEW / 2))
			local camera = Instance.new("Camera")
			camera.FieldOfView = FIELD_OF_VIEW
			camera.Parent = viewport
			viewport.CurrentCamera = camera
			model.Parent = viewport
			card.camera = camera
		else
			warn(`[Snackdex] preview of {def.id} failed: {model}`)
		end
	end

	UiKit.label({
		Name = "Name",
		Text = if discovered then def.displayName else Theme.text.snackdexUnknown,
		Position = UDim2.fromOffset(6, previewHeight + 6),
		Size = UDim2.new(1, -12, 0, 34),
		TextWrapped = true,
		TextColor3 = if discovered then UiTheme.palette("text") else UiTheme.palette("textDim"),
		Parent = frame,
	})
	if discovered then
		UiKit.label({
			Name = "Income",
			Text = UiTheme.perSecond(def.income),
			Position = UDim2.fromOffset(6, previewHeight + 42),
			Size = UDim2.new(1, -12, 0, 18),
			TextColor3 = UiTheme.palette("cash"),
			Parent = frame,
		})
		local pips = UiKit.new("Frame", {
			Name = "Mutations",
			Position = UDim2.fromOffset(6, previewHeight + 64),
			Size = UDim2.new(1, -12, 0, PIP_SIZE),
			BackgroundTransparency = 1,
			Parent = frame,
		})
		UiKit.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 5),
			Parent = pips,
		})
		local variants = ownedVariants[def.id] or {}
		for _, mutation in catalog.mutationList do
			local has = variants[mutation.id] == true
			-- Event-only mutations (e.g. Haunted) show once owned; the permanent ones always, as goals.
			if has or mutation.eventId == nil then
				newPip(UiTheme.color(mutation.color), has, mutation.order, pips)
			end
		end
	end
	if newIds[def.id] then
		local tag = UiKit.new("Frame", {
			Name = "New",
			Position = UDim2.fromOffset(4, 4),
			Size = UDim2.fromOffset(44, 20),
			BackgroundColor3 = UiTheme.palette("danger"),
			ZIndex = 3,
			Parent = frame,
		})
		UiKit.corner(10).Parent = tag
		UiKit.stroke(2).Parent = tag
		UiKit.label({
			Text = Theme.text.snackdexNewTag,
			Size = UDim2.new(1, -6, 1, -4),
			Position = UDim2.fromOffset(3, 2),
			ZIndex = 4,
			Parent = tag,
		})
	end
	return card
end

local function sway()
	local current = panel
	if current == nil then
		return
	end
	local t = os.clock()
	for _, card in current.cards do
		local camera = card.camera
		if camera then
			local angle = math.sin(t * SWAY_SPEED + card.phase) * SWAY_ANGLE
			local offset = CFrame.Angles(0, angle, 0):VectorToWorldSpace(Vector3.new(0, 0, -card.distance))
			local position = card.target + offset + Vector3.new(0, card.distance * CAMERA_RISE, 0)
			camera.CFrame = CFrame.lookAt(position, card.target)
		end
	end
end

-- Panel -------------------------------------------------------------------------------------------------------------

local function tabCountText(section: Section): string
	local found = foundIn(section)
	local text = Format.template(Theme.text.snackdexTabCount, { found = found, total = #section.creatures })
	return if not section.isEvent and completedTiers[section.id] then "✓ " .. text else text
end

local function refreshTabs()
	local current = panel
	if current == nil then
		return
	end
	for _, section in sections do
		local tab = current.tabs[section.id]
		if tab then
			local selected = section == current.section
			tab.button.BackgroundColor3 = if selected then section.color else UiTheme.palette("panelLight")
			tab.name.TextColor3 = if selected then UiTheme.palette("text") else section.color
			setStroke(tab.button, if selected then UiTheme.palette("text") else UiTheme.palette("stroke"))
			tab.count.Text = tabCountText(section)
			tab.badge.Visible = hasNew(section)
		end
	end
end

local function refreshInfo()
	local current = panel
	if current == nil then
		return
	end
	local section = current.section
	local text: string
	if section.isEvent then
		text = Theme.text.snackdexEventNote
	elseif completedTiers[section.id] then
		text = Format.template(
			if foundIn(section) >= #section.creatures
				then Theme.text.snackdexTierDone
				else Theme.text.snackdexTierDoneMore,
			{ percent = percent(Snackdex.incomeBonusPerTier) }
		)
	else
		local state = StateStore.get()
		local amount = SnackdexRules.tierReward(section.id, if state then state.packIncome else 0, Snackdex)
		text = Format.template(Theme.text.snackdexTierReward, {
			total = #section.creatures,
			amount = UiTheme.cash(amount),
			percent = percent(Snackdex.incomeBonusPerTier),
		})
	end
	current.infoLabel.Text = text
	current.infoLabel.TextColor3 = if section.isEvent then UiTheme.palette("textDim") else section.color
	current.bonusLabel.Text = Format.template(Theme.text.snackdexBonus, { percent = percent(incomeBonus) })
	local pages = pageCount(section)
	current.pageLabel.Visible = pages > 1
	current.pageLabel.Text = Format.template(Theme.text.snackdexPage, { page = current.page, pages = pages })
	current.prev.Visible = pages > 1
	current.next.Visible = pages > 1
	current.prev.BackgroundColor3 = if current.page > 1 then UiTheme.palette("primary") else UiTheme.palette("panel")
	current.next.BackgroundColor3 = if current.page < pages
		then UiTheme.palette("primary")
		else UiTheme.palette("panel")
end

-- Rebuilds the visible page's cards (and destroys the previous ones with their models).
local function renderPage()
	local current = panel
	if current == nil then
		return
	end
	for _, card in current.cards do
		card.frame:Destroy()
	end
	table.clear(current.cards)
	local row = current.cardRow
	-- Sizes in reference px: the row is the modal body (panel - 32) minus both arrows.
	local rowWidth = PANEL_SIZE.X - 32 - 2 * (ARROW_WIDTH + 6)
	local width = math.floor((rowWidth - (CARDS_PER_PAGE - 1) * CARD_GAP) / CARDS_PER_PAGE)
	local height = PANEL_SIZE.Y - 72 - CARDS_TOP
	local first = (current.page - 1) * CARDS_PER_PAGE + 1
	for index = first, math.min(first + CARDS_PER_PAGE - 1, #current.section.creatures) do
		table.insert(current.cards, buildCard(current.section.creatures[index], index, width, height, row))
	end
	sway()
	refreshInfo()
end

local function selectSection(section: Section, page: number?)
	local current = panel
	if current == nil then
		return
	end
	current.section = section
	current.page = math.clamp(page or 1, 1, pageCount(section))
	refreshTabs()
	renderPage()
end

local function turnPage(delta: number)
	local current = panel
	if current == nil then
		return
	end
	local page = math.clamp(current.page + delta, 1, pageCount(current.section))
	if page ~= current.page then
		SoundPlayer.ui("click")
		current.page = page
		renderPage()
	end
end

local function updateButtonBadge()
	sideButton.badge.Visible = panel == nil and next(newIds) ~= nil
end

local function onClosed()
	panel = nil
	if swayConnection then
		swayConnection:Disconnect()
		swayConnection = nil
	end
	table.clear(newIds) -- seen
	updateButtonBadge()
end

-- The section (and page) the panel opens on: the newest discovery's, else the first tier still incomplete.
local function startingPoint(): (Section, number)
	local latest = lastDiscovery
	if latest and newIds[latest] then
		local section, index = sectionOf(latest)
		if section then
			return section, math.ceil(index / CARDS_PER_PAGE)
		end
	end
	for _, section in sections do
		if not section.isEvent and foundIn(section) < #section.creatures then
			return section, 1
		end
	end
	return sections[1], 1
end

function SnackdexController.open()
	if #sections == 0 then
		return
	end
	local modal = Modal.open(Theme.text.snackdexTitle, PANEL_SIZE, onClosed)
	local body = modal.body

	-- Tabs: one per tier, then Event. As wide as fits; they scroll sideways if a config ever has too many.
	local strip = UiKit.new("ScrollingFrame", {
		Name = "Tabs",
		Size = UDim2.new(1, 0, 0, TAB_HEIGHT + 4),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.fromOffset(0, 0),
		ScrollBarThickness = 3,
		ElasticBehavior = Enum.ElasticBehavior.Never,
		Parent = body,
	}) :: ScrollingFrame
	UiKit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, TAB_GAP),
		Parent = strip,
	})
	UiKit.new("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingLeft = UDim.new(0, 2), Parent = strip })
	local bodyWidth = PANEL_SIZE.X - 32
	local tabWidth = math.max(MIN_TAB_WIDTH, math.floor((bodyWidth - 4 - (#sections - 1) * TAB_GAP) / #sections))
	local tabs: { [string]: TabView } = {}
	for order, section in sections do
		local button = UiKit.button({
			Name = section.id,
			LayoutOrder = order,
			Size = UDim2.fromOffset(tabWidth, TAB_HEIGHT),
			BackgroundColor3 = UiTheme.palette("panelLight"),
			Text = "",
			Parent = strip,
		}, function()
			local current = panel
			if current and current.section ~= section then
				SoundPlayer.ui("click")
				selectSection(section)
			end
		end)
		local padding = button:FindFirstChildOfClass("UIPadding")
		if padding then
			padding.PaddingLeft = UDim.new(0, 3)
			padding.PaddingRight = UDim.new(0, 3)
			padding.PaddingTop = UDim.new(0, 3)
			padding.PaddingBottom = UDim.new(0, 3)
		end
		local name = UiKit.label({
			Name = "Rarity",
			Text = section.label,
			Size = UDim2.fromScale(1, 0.55),
			TextColor3 = section.color,
			Parent = button,
		})
		local count = UiKit.label({
			Name = "Count",
			Text = "",
			Size = UDim2.fromScale(1, 0.45),
			Position = UDim2.fromScale(0, 0.55),
			FontFace = UiTheme.bodyFont,
			Parent = button,
		})
		-- Inside the strip (a ScrollingFrame clips what sticks out): the top-right corner of the tab.
		local badge = UiKit.new("Frame", {
			Name = "Badge",
			Size = UDim2.fromOffset(14, 14),
			Position = UDim2.new(1, -8, 0, -2),
			BackgroundColor3 = UiTheme.palette("danger"),
			Visible = false,
			ZIndex = 3,
			Parent = button,
		}) :: Frame
		UiKit.corner(7).Parent = badge
		UiKit.stroke(2).Parent = badge
		tabs[section.id] = { button = button, name = name, count = count, badge = badge }
	end

	local infoLabel = UiKit.label({
		Name = "Info",
		Text = "",
		Position = UDim2.fromOffset(2, INFO_TOP),
		Size = UDim2.new(0.66, -2, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = body,
	})
	local pageLabel = UiKit.label({
		Name = "Page",
		Text = "",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -2, 0, INFO_TOP),
		Size = UDim2.fromOffset(48, 22),
		TextXAlignment = Enum.TextXAlignment.Right,
		FontFace = UiTheme.bodyFont,
		Parent = body,
	})
	local bonusLabel = UiKit.label({
		Name = "Bonus",
		Text = "",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -56, 0, INFO_TOP),
		Size = UDim2.new(0.34, -60, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = UiTheme.palette("cash"),
		Parent = body,
	})

	local areaHeight = PANEL_SIZE.Y - 72 - CARDS_TOP
	local function arrow(text: string, anchorX: number, delta: number): TextButton
		return UiKit.button({
			Name = if delta < 0 then "Previous" else "Next",
			AnchorPoint = Vector2.new(anchorX, 0.5),
			Position = UDim2.new(anchorX, 0, 0, CARDS_TOP + areaHeight / 2),
			Size = UDim2.fromOffset(ARROW_WIDTH, 72),
			BackgroundColor3 = UiTheme.palette("primary"),
			Text = text,
			Parent = body,
		}, function()
			turnPage(delta)
		end)
	end
	local prev = arrow("<", 0, -1)
	local nextButton = arrow(">", 1, 1)
	local cardRow = UiKit.new("Frame", {
		Name = "Cards",
		Position = UDim2.fromOffset(ARROW_WIDTH + 6, CARDS_TOP),
		Size = UDim2.new(1, -2 * (ARROW_WIDTH + 6), 0, areaHeight),
		BackgroundTransparency = 1,
		Parent = body,
	}) :: Frame
	UiKit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, CARD_GAP),
		Parent = cardRow,
	})

	local section, page = startingPoint()
	panel = {
		modal = modal,
		section = section,
		page = page,
		tabs = tabs,
		cardRow = cardRow,
		cards = {},
		infoLabel = infoLabel,
		bonusLabel = bonusLabel,
		pageLabel = pageLabel,
		prev = prev,
		next = nextButton,
	}
	updateButtonBadge() -- looked at: the dot goes (the NEW tags stay until the panel closes)
	selectSection(section, page)
	if swayConnection == nil then
		swayConnection = RunService.RenderStepped:Connect(sway)
	end
end

-- Server sync ---------------------------------------------------------------------------------------------------------

local function celebrate(paid: Types.SnackdexTierPaid)
	local rarity = catalog.rarities[paid.rarity]
	local name = if rarity then rarity.displayName else paid.rarity
	NotificationController.announce(
		Format.template(Theme.text.snackdexTierComplete, {
			rarity = name,
			amount = UiTheme.cash(paid.amount),
			percent = percent(paid.bonus),
		}),
		paid.rarity
	)
	SoundPlayer.rarity(paid.rarity)
	SoundPlayer.ui("claim")
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		NotificationController.sparkle(root.Position + Vector3.new(0, 2, 0), UiTheme.rarityColor(paid.rarity))
	end
end

local function onSync(payload: Types.SnackdexSync)
	local dex = payload.dex
	table.clear(owned)
	for _, id in dex.creatures do
		owned[id] = true
	end
	table.clear(ownedVariants)
	for creatureId, list in dex.variants do
		local set: { [string]: boolean } = {}
		for _, mutationId in list do
			set[mutationId] = true
		end
		ownedVariants[creatureId] = set
	end
	table.clear(completedTiers)
	for _, rarityId in dex.tiers do
		completedTiers[rarityId] = true
	end
	incomeBonus = dex.incomeBonus

	local discovered = payload.discovered
	if discovered then
		local def = catalog.creatures[discovered.creatureId]
		if def then
			newIds[def.id] = true
			lastDiscovery = def.id
			NotificationController.toast(
				Format.template(Theme.text.snackdexNew, { creature = GameData.displayName(def, discovered.variant) }),
				"success"
			)
			SoundPlayer.ui("claim")
		end
	end
	local completed = payload.completed
	if completed then
		for _, paid in completed do
			celebrate(paid)
		end
	end

	if panel then
		refreshTabs()
		renderPage()
	end
	updateButtonBadge()
end

function SnackdexController.start()
	buildSections()
	sideButton = HudController.addSideButton(
		4,
		"📖",
		Theme.text.snackdexButton,
		UiTheme.palette("snackdex"),
		function()
			SoundPlayer.ui("click")
			SnackdexController.open()
		end
	)
	Net.get("SnackdexSync").OnClientEvent:Connect(onSync)
	-- Tier rewards are sized from steady income: keep the open panel's amount current.
	StateStore.onChange(function()
		if panel then
			refreshInfo()
		end
	end)
end

return SnackdexController
