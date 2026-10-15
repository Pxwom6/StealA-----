--!strict
--[[
	The host panel (Config/Host; server: HostService; geometry: Logic/HostPanelLayout). It opens from its row in
	Settings, which only shows for players who may host: an admin, or this private server's owner (StateUpdate `host`).

	Admins get five tabs and a scope switch at the end of the tab bar ("📍 This server" / "🌍 All servers", kept while
	the game runs):
	  Map        switch to the chosen map now, start a vote, map rotation on or off (rotation is this server only)
	  Modifiers  start the chosen modifier for N minutes, or stop the one running
	  Belt       an admin drop: the chosen Snackling (rarest first) with the chosen mutation, on the belt now
	  Boosts     luck x N for M minutes; start or end a configured LiveOps event; gift everyone N minutes of income
	  Message    a message for everyone (the server has Roblox filter it first)
	A private server's owner gets Map (no vote) and Modifiers (only the hostable ones), with their cooldowns on the
	buttons ("Ready in 0:42").

	Every button sends one HostAction intent (kind, scope, args). The server checks everything again and answers with
	a toast, or with what happens (the new map, the modifier's banner and chip, the drop's banner). Choices are kept
	while the game runs. While open the panel refreshes once a second (the current map and modifier, countdowns), and
	it closes if the player may no longer host.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Host = require(ReplicatedStorage.Shared.Config.Host)
local LiveOps = require(ReplicatedStorage.Shared.Config.LiveOps)
local MapThemes = require(ReplicatedStorage.Shared.Config.MapThemes)
local Modifiers = require(ReplicatedStorage.Shared.Config.Modifiers)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local GameData = require(ReplicatedStorage.Shared.GameData)
local Net = require(ReplicatedStorage.Shared.Net)
local Types = require(ReplicatedStorage.Shared.Types)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local HostPanelLayout = require(ReplicatedStorage.Shared.Logic.HostPanelLayout)
local Modal = require(script.Parent.Parent.UI.Modal)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local NotificationController = require(script.Parent.NotificationController)
local StateStore = require(script.Parent.StateStore)

local HostPanelController = {}

type Rect = HostPanelLayout.Rect
type Box = HostPanelLayout.Box
type Role = HostPanelLayout.Role
type Refresh = (state: Types.ClientState) -> ()
type Choice = { id: string, text: string, stroke: Color3? }
type Scope = "server" | "all"

-- A double tap must not send twice (the server rate-limits as well).
local RESEND_SECONDS = 0.4
local PAD = HostPanelLayout.PAD
local PRESETS = Host.presets

local function presetIndex(list: { number }, wanted: number?): number
	if wanted == nil then
		return 1
	end
	return table.find(list, wanted) or 1
end

-- What was chosen, kept while the game runs.
local scope: Scope = "server"
local selectedTab = "map"
local chosenMap: string? = nil
local chosenModifier: string? = nil
local chosenCreature: string? = nil
local chosenMutation: string? = nil
local modifierMinutes = presetIndex(PRESETS.modifierMinutes, Host.limits.modifierMinutes.default)
local luckMultiplier = presetIndex(PRESETS.luckMultiplier, Host.limits.luckMultiplier.default)
local luckMinutes = presetIndex(PRESETS.luckMinutes, Host.limits.luckMinutes.default)
local chosenEvent = 1
local eventMinutes = 0 -- 0: the event's own length, else an index into presets.eventMinutes
local giftMinutes = presetIndex(PRESETS.giftMinutes, Host.limits.giftMinutes.default)
local message = ""
local lastSent = -math.huge

local openModal: Modal.ModalHandle? = nil
local currentRefresh: Refresh? = nil

-- Snacklings for the Belt tab: rarest first, in config order within a rarity.
local creatureOrder: { Types.CreatureDef } = {}
do
	local index: { [string]: number } = {}
	for i, def in GameData.catalog.creatureList do
		table.insert(creatureOrder, def)
		index[def.id] = i
	end
	local rarities = GameData.catalog.rarities
	table.sort(creatureOrder, function(a: Types.CreatureDef, b: Types.CreatureDef): boolean
		local ra, rb = rarities[a.rarity].order, rarities[b.rarity].order
		if ra ~= rb then
			return ra > rb
		end
		return index[a.id] < index[b.id]
	end)
end

local function now(): number
	return workspace:GetServerTimeNow()
end

local function roleOf(state: Types.ClientState?): Role?
	local role = if state then state.host.role else ""
	if role == "admin" then
		return "admin"
	elseif role == "owner" then
		return "owner"
	end
	return nil
end

-- Sends one HostAction. Owners always act on this server only.
local function send(kind: string, args: { [string]: any }?)
	local t = os.clock()
	if t - lastSent < RESEND_SECONDS then
		return
	end
	lastSent = t
	local sendScope = if roleOf(StateStore.get()) == "admin" then scope else "server"
	Net.get("HostAction"):FireServer(kind, sendScope, args or {})
end

local function refreshPanel()
	local state = StateStore.get()
	if state and currentRefresh then
		currentRefresh(state)
	end
end

local function secondsLeft(readyAt: number): number
	return math.max(0, readyAt - now())
end

local function readyText(seconds: number): string
	return Format.template(Theme.text.hostReadyIn, { time = Format.clock(seconds) })
end

-- Building blocks -----------------------------------------------------------------------------------------------------

local function button(
	parent: Instance,
	name: string,
	r: Rect,
	text: string,
	color: string,
	onActivated: () -> ()
): TextButton
	return UiKit.button({
		Name = name,
		Position = UDim2.fromOffset(r.x, r.y),
		Size = UDim2.fromOffset(r.w, r.h),
		BackgroundColor3 = UiTheme.palette(color),
		Text = text,
		Parent = parent,
	}, onActivated)
end

local function setButton(target: TextButton, text: string, color: string)
	UiKit.setButtonText(target, text)
	target.BackgroundColor3 = UiTheme.palette(color)
end

-- A button whose text may wrap onto two lines (long names in the lists).
local function wrapText(target: TextButton)
	local label = target:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		label.TextWrapped = true
	end
end

local function label(parent: Instance, name: string, r: Rect, text: string, props: UiKit.Props?): TextLabel
	local all: UiKit.Props = {
		Name = name,
		Text = text,
		Position = UDim2.fromOffset(r.x, r.y),
		Size = UDim2.fromOffset(r.w, r.h),
		Parent = parent,
	}
	local extra: UiKit.Props = props or {}
	for key, item in extra do
		all[key] = item
	end
	return UiKit.label(all)
end

-- A value between a stepper's buttons: a light panel with its text inside.
local function value(parent: Instance, name: string, r: Rect): TextLabel
	local frame = UiKit.panel({
		Name = name,
		Position = UDim2.fromOffset(r.x, r.y),
		Size = UDim2.fromOffset(r.w, r.h),
		BackgroundColor3 = UiTheme.palette("panelLight"),
		Parent = parent,
	})
	return UiKit.label({
		Name = "Text",
		Text = "",
		TextWrapped = true,
		Position = UDim2.fromOffset(PAD.x, PAD.y),
		Size = UDim2.new(1, -2 * PAD.x, 1, -2 * PAD.y),
		Parent = frame,
	})
end

-- A scrolling grid of choices. Returns a function that shows which one is chosen.
local function grid(
	parent: Instance,
	name: string,
	b: Box,
	choices: { Choice },
	isChosen: (id: string) -> boolean,
	onPick: (id: string) -> ()
): () -> ()
	local r = b.rect
	local inset = HostPanelLayout.LIST_INSET
	local scroller = UiKit.new("ScrollingFrame", {
		Name = name,
		Position = UDim2.fromOffset(r.x, r.y),
		Size = UDim2.fromOffset(r.w, r.h),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = HostPanelLayout.SCROLLBAR,
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = parent,
	}) :: ScrollingFrame
	UiKit.new("UIPadding", {
		PaddingTop = UDim.new(0, inset),
		PaddingBottom = UDim.new(0, inset),
		PaddingLeft = UDim.new(0, inset),
		PaddingRight = UDim.new(0, inset),
		Parent = scroller,
	})
	local cell = b.cell or { w = r.w, h = HostPanelLayout.BUTTON }
	UiKit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(cell.w, cell.h),
		CellPadding = UDim2.fromOffset(HostPanelLayout.GAP, HostPanelLayout.GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = scroller,
	})
	local buttons: { [string]: TextButton } = {}
	for order, choice in choices do
		local id = choice.id
		local item = UiKit.button({
			Name = id,
			LayoutOrder = order,
			BackgroundColor3 = UiTheme.palette("panelLight"),
			Text = choice.text,
			Parent = scroller,
		}, function()
			onPick(id)
			refreshPanel()
		end)
		wrapText(item)
		local stroke = item:FindFirstChildOfClass("UIStroke")
		if stroke and choice.stroke then
			stroke.Color = choice.stroke
		end
		buttons[id] = item
	end
	return function()
		for id, item in buttons do
			item.BackgroundColor3 = if isChosen(id) then UiTheme.palette("gold") else UiTheme.palette("panelLight")
		end
	end
end

-- A stepper's two buttons around its value: `step(-1)` / `step(1)` change the choice.
local function stepper(
	parent: Instance,
	boxes: { [string]: Box },
	prefix: string,
	step: (delta: number) -> ()
): TextLabel
	button(parent, prefix .. "Minus", boxes[prefix .. "Minus"].rect, "-", "panel", function()
		step(-1)
		refreshPanel()
	end)
	button(parent, prefix .. "Plus", boxes[prefix .. "Plus"].rect, "+", "panel", function()
		step(1)
		refreshPanel()
	end)
	return value(parent, prefix .. "Value", boxes[prefix .. "Value"].rect)
end

local function clampStep(index: number, delta: number, count: number, low: number?): number
	return math.clamp(index + delta, low or 1, count)
end

-- Tabs ----------------------------------------------------------------------------------------------------------------

local function currentMap(): string
	local id = workspace:GetAttribute("MapTheme")
	return if type(id) == "string" then id else ""
end

local function currentModifier(): string?
	local id = workspace:GetAttribute("Modifier")
	return if type(id) == "string" and id ~= "" then id else nil
end

local function buildMap(content: Frame, role: Role): Refresh
	local boxes = HostPanelLayout.tab("map", role)
	local choices: { Choice } = {}
	for _, id in MapThemes.order do
		local theme = MapThemes.themes[id]
		table.insert(choices, { id = id, text = `{theme.icon} {theme.displayName}` })
	end
	if chosenMap == nil or MapThemes.themes[chosenMap :: string] == nil or chosenMap == currentMap() then
		for _, id in MapThemes.order do
			if id ~= currentMap() then
				chosenMap = id
				break
			end
		end
	end
	local showChosen = grid(content, "Maps", boxes.list, choices, function(id: string): boolean
		return id == chosenMap
	end, function(id: string)
		chosenMap = id
	end)
	local nowLabel = label(content, "Now", boxes.now.rect, "", { TextXAlignment = Enum.TextXAlignment.Left })
	local switchWaits = 0
	local switch = button(content, "Switch", boxes.switch.rect, Theme.text.hostMapSwitch, "success", function()
		if switchWaits == 0 and chosenMap and chosenMap ~= currentMap() then
			send("mapSwitch", { id = chosenMap })
		end
	end)
	if boxes.vote then
		button(content, "Vote", boxes.vote.rect, Theme.text.hostMapVote, "primary", function()
			send("mapVote")
		end)
	end
	local rotation = button(content, "Rotation", boxes.rotation.rect, "", "success", function()
		send("mapRotation", { on = workspace:GetAttribute("MapRotation") == false })
	end)
	return function(state: Types.ClientState)
		showChosen()
		local theme = MapThemes.themes[currentMap()]
		nowLabel.Text = if theme
			then Format.template(Theme.text.hostMapNow, { icon = theme.icon, map = theme.displayName })
			else ""
		switchWaits = if role == "owner" then secondsLeft(state.host.mapReadyAt) else 0
		if switchWaits > 0 then
			setButton(switch, readyText(switchWaits), "panel")
		else
			setButton(switch, Theme.text.hostMapSwitch, if chosenMap == currentMap() then "panel" else "success")
		end
		local on = workspace:GetAttribute("MapRotation") ~= false
		setButton(
			rotation,
			if on then Theme.text.hostRotationOn else Theme.text.hostRotationOff,
			if on then "success" else "panelLight"
		)
	end
end

local function modifierIds(role: Role): { string }
	local ids: { string } = {}
	for _, id in Modifiers.order do
		if role == "admin" or Modifiers.modifiers[id].hostable == true then
			table.insert(ids, id)
		end
	end
	return ids
end

local function buildModifiers(content: Frame, role: Role): Refresh
	local boxes = HostPanelLayout.tab("modifiers", role)
	local ids = modifierIds(role)
	local choices: { Choice } = {}
	for _, id in ids do
		local def = Modifiers.modifiers[id]
		table.insert(choices, { id = id, text = `{def.icon} {def.displayName}`, stroke = UiTheme.color(def.color) })
	end
	if chosenModifier == nil or table.find(ids, chosenModifier :: string) == nil then
		chosenModifier = ids[1]
	end
	local showChosen = grid(content, "Modifiers", boxes.list, choices, function(id: string): boolean
		return id == chosenModifier
	end, function(id: string)
		chosenModifier = id
	end)
	local nowLabel = label(content, "Now", boxes.now.rect, "", { TextXAlignment = Enum.TextXAlignment.Left })
	local minutes = stepper(content, boxes, "minutes", function(delta: number)
		modifierMinutes = clampStep(modifierMinutes, delta, #PRESETS.modifierMinutes)
	end)
	local startWaits = 0
	local start = button(content, "Start", boxes.start.rect, Theme.text.hostModStart, "success", function()
		if startWaits == 0 and chosenModifier then
			send("modStart", { id = chosenModifier, minutes = PRESETS.modifierMinutes[modifierMinutes] })
		end
	end)
	local stop = button(content, "Stop", boxes.stop.rect, Theme.text.hostModStop, "danger", function()
		if currentModifier() then
			send("modStop")
		end
	end)
	return function(state: Types.ClientState)
		showChosen()
		local running = currentModifier()
		local def = if running then Modifiers.modifiers[running] else nil
		local endsAt = workspace:GetAttribute("ModifierEndsAt")
		nowLabel.Text = if def
			then Format.template(Theme.text.hostModNow, {
				icon = def.icon,
				name = def.displayName,
				time = Format.clock(if type(endsAt) == "number" then endsAt - now() else 0),
			})
			else Theme.text.hostModNone
		minutes.Text = Format.template(Theme.text.hostMinutes, { minutes = PRESETS.modifierMinutes[modifierMinutes] })
		startWaits = if role == "owner" then secondsLeft(state.host.modifierReadyAt) else 0
		if startWaits > 0 then
			setButton(start, readyText(startWaits), "panel")
		else
			setButton(start, Theme.text.hostModStart, "success")
		end
		-- Owners may only stop what they could have started.
		local stoppable = def ~= nil and (role == "admin" or def.hostable == true)
		stop.BackgroundColor3 = UiTheme.palette(if stoppable then "danger" else "panel")
	end
end

local function buildBelt(content: Frame): Refresh
	local boxes = HostPanelLayout.tab("belt", "admin")
	local rarities = GameData.catalog.rarities
	local creatures: { Choice } = {}
	for _, def in creatureOrder do
		table.insert(creatures, { id = def.id, text = def.displayName, stroke = UiTheme.rarityColor(def.rarity) })
	end
	chosenCreature = chosenCreature or creatureOrder[1].id
	local mutations: { Choice } = { { id = "", text = Theme.text.hostBeltPlain } }
	for _, mutation in GameData.catalog.mutationList do
		table.insert(
			mutations,
			{ id = mutation.id, text = mutation.displayName, stroke = UiTheme.color(mutation.color) }
		)
	end
	local showCreature = grid(content, "Snacklings", boxes.creatures, creatures, function(id: string): boolean
		return id == chosenCreature
	end, function(id: string)
		chosenCreature = id
	end)
	local showMutation = grid(content, "Mutations", boxes.mutations, mutations, function(id: string): boolean
		return id == (chosenMutation or "")
	end, function(id: string)
		chosenMutation = if id == "" then nil else id
	end)
	local summary = label(content, "Summary", boxes.summary.rect, "", { TextWrapped = true })
	button(content, "Drop", boxes.drop.rect, Theme.text.hostBeltDrop, "gold", function()
		if chosenCreature then
			send("beltDrop", { id = chosenCreature, mutation = chosenMutation })
		end
	end)
	return function(_state: Types.ClientState)
		showCreature()
		showMutation()
		local def = if chosenCreature then GameData.catalog.creatures[chosenCreature :: string] else nil
		if def then
			summary.Text = Format.template(Theme.text.hostBeltSummary, {
				rarity = string.upper(rarities[def.rarity].displayName),
				creature = GameData.displayName(def, chosenMutation),
			})
			summary.TextColor3 = UiTheme.rarityColor(def.rarity)
		end
	end
end

local function eventName(event: Types.EventDef): string
	return event.title or event.id
end

local function buildBoosts(content: Frame): Refresh
	local boxes = HostPanelLayout.tab("boosts", "admin")
	local events = LiveOps.events
	local luckValue = stepper(content, boxes, "luck", function(delta: number)
		luckMultiplier = clampStep(luckMultiplier, delta, #PRESETS.luckMultiplier)
	end)
	local luckMinutesValue = stepper(content, boxes, "luckMinutes", function(delta: number)
		luckMinutes = clampStep(luckMinutes, delta, #PRESETS.luckMinutes)
	end)
	button(content, "LuckStart", boxes.luckStart.rect, Theme.text.hostLuckStart, "success", function()
		send(
			"luck",
			{ multiplier = PRESETS.luckMultiplier[luckMultiplier], minutes = PRESETS.luckMinutes[luckMinutes] }
		)
	end)
	local eventValue = stepper(content, boxes, "event", function(delta: number)
		chosenEvent = clampStep(chosenEvent, delta, #events)
	end)
	local eventMinutesValue = stepper(content, boxes, "eventMinutes", function(delta: number)
		eventMinutes = clampStep(eventMinutes, delta, #PRESETS.eventMinutes, 0)
	end)
	button(content, "EventStart", boxes.eventStart.rect, Theme.text.hostEventStart, "success", function()
		local event = events[chosenEvent]
		if event then
			send("eventStart", {
				id = event.id,
				minutes = if eventMinutes > 0 then PRESETS.eventMinutes[eventMinutes] else nil,
			})
		end
	end)
	button(content, "EventStop", boxes.eventStop.rect, Theme.text.hostEventStop, "danger", function()
		local event = events[chosenEvent]
		if event then
			send("eventStop", { id = event.id })
		end
	end)
	local giftValue = stepper(content, boxes, "gift", function(delta: number)
		giftMinutes = clampStep(giftMinutes, delta, #PRESETS.giftMinutes)
	end)
	label(content, "GiftHint", boxes.giftHint.rect, Theme.text.hostGiftHint, {
		FontFace = UiTheme.bodyFont,
		TextColor3 = UiTheme.palette("textDim"),
		TextWrapped = true,
	})
	local giftWaits = 0
	local gift = button(content, "Gift", boxes.giftSend.rect, Theme.text.hostGiftSend, "gold", function()
		if giftWaits == 0 then
			send("gift", { minutes = PRESETS.giftMinutes[giftMinutes] })
		end
	end)
	return function(state: Types.ClientState)
		luckValue.Text =
			Format.template(Theme.text.hostLuckValue, { multiplier = PRESETS.luckMultiplier[luckMultiplier] })
		luckMinutesValue.Text = Format.template(Theme.text.hostMinutes, { minutes = PRESETS.luckMinutes[luckMinutes] })
		local event = events[chosenEvent]
		eventValue.Text = if event then Format.template(Theme.text.hostEventValue, { event = eventName(event) }) else ""
		eventMinutesValue.Text = if eventMinutes > 0
			then Format.template(Theme.text.hostMinutes, { minutes = PRESETS.eventMinutes[eventMinutes] })
			else Theme.text.hostEventDefault
		giftValue.Text = Format.template(Theme.text.hostGiftValue, { minutes = PRESETS.giftMinutes[giftMinutes] })
		giftWaits = secondsLeft(state.host.giftReadyAt)
		if giftWaits > 0 then
			setButton(gift, readyText(giftWaits), "panel")
		else
			setButton(gift, Theme.text.hostGiftSend, "gold")
		end
	end
end

-- The first `count` characters of `text`.
local function firstCharacters(text: string, count: number): string
	local length = utf8.len(text)
	if length == nil or length <= count then
		return text
	end
	local cut = utf8.offset(text, count + 1)
	return if cut then string.sub(text, 1, cut - 1) else text
end

local function buildBroadcast(content: Frame): Refresh
	local boxes = HostPanelLayout.tab("broadcast", "admin")
	local max = Host.limits.broadcastLength
	local r = boxes.input.rect
	local input = UiKit.new("TextBox", {
		Name = "Message",
		Position = UDim2.fromOffset(r.x, r.y),
		Size = UDim2.fromOffset(r.w, r.h),
		BackgroundColor3 = UiTheme.palette("panelLight"),
		TextColor3 = UiTheme.palette("text"),
		PlaceholderText = Theme.text.hostBroadcastPlaceholder,
		PlaceholderColor3 = UiTheme.palette("textDim"),
		FontFace = UiTheme.bodyFont,
		TextSize = 20,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ClearTextOnFocus = false,
		MultiLine = false,
		Text = message,
		Parent = content,
	}) :: TextBox
	UiKit.corner(UiKit.RADIUS.medium).Parent = input
	UiKit.stroke(UiKit.STROKE.normal).Parent = input
	UiKit.padding(10).Parent = input
	label(content, "Note", boxes.note.rect, Theme.text.hostBroadcastNote, {
		FontFace = UiTheme.bodyFont,
		TextColor3 = UiTheme.palette("textDim"),
	})
	local count = label(content, "Count", boxes.count.rect, "", {
		FontFace = UiTheme.bodyFont,
		TextColor3 = UiTheme.palette("textDim"),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local function show()
		count.Text = Format.template(Theme.text.hostBroadcastCount, { count = utf8.len(message) or 0, max = max })
	end
	input:GetPropertyChangedSignal("Text"):Connect(function()
		local text = firstCharacters(input.Text, max)
		if text ~= input.Text then
			input.Text = text -- runs this again, with the short text
			return
		end
		message = text
		show()
	end)
	button(content, "Send", boxes.send.rect, Theme.text.hostBroadcastSend, "primary", function()
		if string.match(message, "%S") then
			send("broadcast", { text = message })
		end
	end)
	show()
	return function(_state: Types.ClientState) end
end

-- The panel -----------------------------------------------------------------------------------------------------------

local TAB_TEXT: { [string]: string } = {
	map = Theme.text.hostTabMap,
	modifiers = Theme.text.hostTabModifiers,
	belt = Theme.text.hostTabBelt,
	boosts = Theme.text.hostTabBoosts,
	broadcast = Theme.text.hostTabBroadcast,
}

-- Whether the local player may host here (the Settings row shows only then).
function HostPanelController.mayHost(): boolean
	return roleOf(StateStore.get()) ~= nil
end

function HostPanelController.open()
	local state = StateStore.get()
	local found = roleOf(state)
	if state == nil or found == nil then
		return
	end
	local role: Role = found :: Role
	local tabs = HostPanelLayout.tabs(role)
	if table.find(tabs, selectedTab) == nil then
		selectedTab = tabs[1]
	end
	local D = HostPanelLayout.DIALOG
	local modal = Modal.open(Theme.text.hostTitle, Vector2.new(D.w, D.h), function()
		openModal = nil
		currentRefresh = nil
	end)
	openModal = modal

	local tabButtons: { [string]: TextButton } = {}
	local content = UiKit.new("Frame", {
		Name = "Content",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = modal.body,
	}) :: Frame

	local function showTab(id: string)
		selectedTab = id
		for tabId, tabButton in tabButtons do
			tabButton.BackgroundColor3 = UiTheme.palette(if tabId == id then "gold" else "panelLight")
		end
		content:ClearAllChildren()
		currentRefresh = if id == "map"
			then buildMap(content, role)
			elseif id == "modifiers" then buildModifiers(content, role)
			elseif id == "belt" then buildBelt(content)
			elseif id == "boosts" then buildBoosts(content)
			else buildBroadcast(content)
		refreshPanel()
	end

	for index, id in tabs do
		tabButtons[id] = button(modal.body, id, HostPanelLayout.tabButton(index), TAB_TEXT[id], "panelLight", function()
			if selectedTab ~= id then
				showTab(id)
			end
		end)
	end
	if role == "admin" then
		local scopeButton: TextButton
		local function showScope()
			setButton(
				scopeButton,
				if scope == "all" then Theme.text.hostScopeAll else Theme.text.hostScopeServer,
				if scope == "all" then "gold" else "panelLight"
			)
		end
		scopeButton = button(modal.body, "Scope", HostPanelLayout.scopeButton(), "", "panelLight", function()
			scope = (if scope == "all" then "server" else "all") :: Scope
			showScope()
			local latest = StateStore.get()
			if scope == "all" and latest and latest.host.studio then
				NotificationController.toast(Theme.text.hostStudioNote, "info")
			end
		end)
		showScope()
	else
		label(modal.body, "Owner", HostPanelLayout.ownerNote(), Theme.text.hostOwnerNote, {
			FontFace = UiTheme.bodyFont,
			TextColor3 = UiTheme.palette("textDim"),
			TextXAlignment = Enum.TextXAlignment.Right,
		})
	end
	showTab(selectedTab)

	-- Countdowns tick while the panel is open; it closes if the player may no longer host.
	task.spawn(function()
		while modal.isOpen() do
			task.wait(1)
			if openModal ~= modal then
				return
			end
			local latest = StateStore.get()
			if roleOf(latest) ~= role then
				modal.close()
				return
			end
			refreshPanel()
		end
	end)
end

return HostPanelController
