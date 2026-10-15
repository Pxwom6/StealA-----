--!strict
--[[
	The Style dialog (Settings ▸ 🎨 Style; Config/Titles, Config/Skins): two tabs, 🏷️ Titles and 🏠 Base, each a
	scrolling grid of cards placed by Logic/StyleLayout (held to the HUD's rules by tests: it fits every checked screen,
	cards are full touch targets, text reads at 12 UI or more). A card is one button: tap an unlocked one to wear it
	(EquipStyle; the server checks it again), tap a locked one to hear how to earn it. Titles start with "No title";
	their names show in their own colour, as over a head. Base cards show a swatch of the floor and trim (Classic: your
	base's own colours).

	Opening the dialog asks the server what is unlocked (GetStyle → StyleSync); every equip answers with a new StyleSync
	and the cards follow. Nothing here decides anything: the client only sends what was tapped.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Achievements = require(ReplicatedStorage.Shared.Config.Achievements)
local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)
local Skins = require(ReplicatedStorage.Shared.Config.Skins)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local Titles = require(ReplicatedStorage.Shared.Config.Titles)
local Net = require(ReplicatedStorage.Shared.Net)
local Types = require(ReplicatedStorage.Shared.Types)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local StyleLayout = require(ReplicatedStorage.Shared.Logic.StyleLayout)
local StyleRules = require(ReplicatedStorage.Shared.Logic.StyleRules)
local Modal = require(script.Parent.Parent.UI.Modal)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local NotificationController = require(script.Parent.NotificationController)
local SoundPlayer = require(script.Parent.SoundPlayer)
local StateStore = require(script.Parent.StateStore)

type Tab = StyleLayout.Tab
type Rect = StyleLayout.Rect

-- One card: what it wears (kind + id, "" = no title) and the labels that change.
type Card = {
	kind: StyleRules.Kind,
	id: string,
	unlock: Types.StyleUnlock,
	button: TextButton,
	stroke: UIStroke,
	name: TextLabel,
	status: TextLabel,
	color: Color3, -- the name's colour when unlocked
}

type Dialog = {
	modal: Modal.ModalHandle,
	tab: Tab,
	tabs: { [string]: TextButton },
	content: Frame,
	now: TextLabel,
	nowHint: TextLabel,
	cards: { Card },
}

local StyleController = {}

local L = StyleLayout
local TAB_TEXT: { [string]: string } = { titles = Theme.text.styleTabTitles, base = Theme.text.styleTabBase }
local NO_TITLE_ICON = "🚫"
local achievements = StyleRules.achievementsById(Achievements)
local tierCount = #Rarities
local text = (Theme.text :: any) :: { [string]: string }

local dialog: Dialog? = nil
local latest: Types.StyleView? = nil
local listening = false

local function place(object: GuiObject, r: Rect)
	object.Position = UDim2.fromOffset(r.x, r.y)
	object.Size = UDim2.fromOffset(r.w, r.h)
end

local function itemOf(view: Types.StyleView, kind: StyleRules.Kind, id: string): Types.StyleItemView?
	local items: { Types.StyleItemView } = if kind == "title" then view.titles else view.skins
	for _, item in items do
		if item.id == id then
			return item
		end
	end
	return nil
end

-- What a card shows for `view`: worn, unlocked or locked (with its progress).
local function refreshCard(card: Card, view: Types.StyleView)
	local worn = if card.kind == "title" then view.title == card.id else view.skin == card.id
	local item = if card.id == "" then nil else itemOf(view, card.kind, card.id)
	local unlocked = card.id == "" or (item ~= nil and item.unlocked)
	card.button.BackgroundColor3 = if unlocked then UiTheme.palette("panelLight") else UiTheme.palette("panel")
	card.name.TextColor3 = if unlocked then card.color else UiTheme.palette("textDim")
	card.stroke.Color = if worn then UiTheme.palette("gold") else UiTheme.palette("stroke")
	card.stroke.Thickness = if worn then UiKit.STROKE.thick else UiKit.STROKE.normal
	if worn then
		card.status.Text = if card.kind == "title" then Theme.text.styleWorn else Theme.text.styleUsed
		card.status.TextColor3 = UiTheme.palette("gold")
	elseif unlocked then
		card.status.Text = if card.kind == "title" then Theme.text.styleTapToWear else Theme.text.styleTapToUse
		card.status.TextColor3 = UiTheme.palette("success")
	else
		local progress = if item then item.progress else 0
		local target = if item then item.target else 1
		card.status.Text =
			StyleRules.progressText(card.unlock, progress, target, achievements, text, Theme.currencySymbol)
		card.status.TextColor3 = UiTheme.palette("textDim")
	end
end

-- The line about what is worn, over its hint.
local function refreshNow(current: Dialog, view: Types.StyleView)
	if current.tab == "titles" then
		local def = StyleRules.titleById(Titles, view.title)
		current.now.Text = if def
			then Format.template(Theme.text.styleWearing, { title = `{def.icon} {def.text}` })
			else Theme.text.styleWearingNone
		current.now.TextColor3 = if def then UiTheme.color(def.color) else UiTheme.palette("text")
		current.nowHint.Text = Theme.text.styleTitlesHint
	else
		local def = StyleRules.skinById(Skins, view.skin)
		current.now.Text =
			Format.template(Theme.text.styleBaseNow, { skin = if def then `{def.icon} {def.name}` else view.skin })
		current.now.TextColor3 = UiTheme.palette("text")
		current.nowHint.Text = Theme.text.styleBaseHint
	end
end

local function show(view: Types.StyleView)
	latest = view
	local current = dialog
	if current == nil then
		return
	end
	refreshNow(current, view)
	for _, card in current.cards do
		refreshCard(card, view)
	end
end

local function tapped(card: Card)
	local view = latest
	if view == nil then
		return
	end
	local item = if card.id == "" then nil else itemOf(view, card.kind, card.id)
	if card.id ~= "" and not (item and item.unlocked) then
		SoundPlayer.ui("error")
		local hint = StyleRules.hint(card.unlock, achievements, tierCount, text)
		NotificationController.toast(Format.template(Theme.text.styleLockedHint, { hint = hint }), "error")
		return
	end
	local worn = if card.kind == "title" then view.title == card.id else view.skin == card.id
	if worn then
		return
	end
	SoundPlayer.ui("toggle")
	Net.get("EquipStyle"):FireServer(card.kind, card.id)
end

-- A swatch of a skin: its floor tiles in a little checker, the rug down the middle, framed in its trim.
local function buildSwatch(def: Types.SkinDef, r: Rect, parent: Instance)
	local state = StateStore.get()
	local accent = UiTheme.plotColor(if state and state.plot > 0 then state.plot else 1)
	local look = def.look
	local tiles: { Color3 } = {}
	if look then
		for _, hex in look.tiles do
			table.insert(tiles, UiTheme.color(hex))
		end
	else
		tiles = {
			UiTheme.world("plotTileLight"):Lerp(accent, 0.18),
			UiTheme.world("plotTileDark"):Lerp(accent, 0.32),
		}
	end
	local frame = UiKit.new("Frame", {
		Name = "Swatch",
		BackgroundColor3 = tiles[1],
		ClipsDescendants = true,
		Parent = parent,
	}) :: Frame
	place(frame, r)
	UiKit.corner(UiKit.RADIUS.small).Parent = frame
	local stroke = UiKit.stroke(5, if look then UiTheme.color(look.trim) else UiTheme.world("wall"))
	stroke.Parent = frame
	if look and look.rainbow then
		UiKit.new("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromHSV(0, 0.7, 1)),
				ColorSequenceKeypoint.new(0.33, Color3.fromHSV(0.33, 0.7, 1)),
				ColorSequenceKeypoint.new(0.66, Color3.fromHSV(0.66, 0.7, 1)),
				ColorSequenceKeypoint.new(1, Color3.fromHSV(0.9, 0.7, 1)),
			}),
			Parent = stroke,
		})
	end
	-- 3 x 3 cells, coloured like the base's floor (StyleRules.tileIndex), with the rug down the middle column.
	local cell = r.w / 3
	for row = 0, 2 do
		for column = 0, 2 do
			local rug = column == 1
			local color = if rug
				then (if look then UiTheme.color(look.rug) else accent:Lerp(Color3.new(1, 1, 1), 0.15))
				else tiles[StyleRules.tileIndex(row, if column == 0 then 1 else 2, #tiles)]
			UiKit.new("Frame", {
				Name = "Cell",
				BorderSizePixel = 0,
				BackgroundColor3 = color,
				Position = UDim2.fromOffset(column * cell, row * cell),
				Size = UDim2.fromOffset(math.ceil(cell), math.ceil(cell)),
				Parent = frame,
			})
		end
	end
end

local function buildCard(
	tab: Tab,
	index: number,
	kind: StyleRules.Kind,
	id: string,
	name: string,
	color: Color3,
	unlock: Types.StyleUnlock,
	hint: string,
	skin: Types.SkinDef?,
	parent: Instance
): Card
	local boxes = L.cardBoxes(tab)
	local button = UiKit.new("TextButton", {
		Name = if id == "" then "None" else id,
		AutoButtonColor = false,
		Text = "",
		BackgroundColor3 = UiTheme.palette("panelLight"),
		Parent = parent,
	}) :: TextButton
	place(button, L.cardAt(tab, index))
	UiKit.corner(UiKit.RADIUS.medium).Parent = button
	local stroke = UiKit.stroke(UiKit.STROKE.normal)
	stroke.Parent = button
	UiKit.addPressFeedback(button)
	if skin and boxes.swatch then
		buildSwatch(skin, boxes.swatch, button)
	end
	local nameLabel = UiKit.label({
		Name = "Name",
		Text = name,
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = button,
	})
	place(nameLabel, boxes.name)
	local hintLabel = UiKit.label({
		Name = "Hint",
		Text = hint,
		FontFace = UiTheme.bodyFont,
		TextColor3 = UiTheme.palette("textDim"),
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = button,
	})
	place(hintLabel, boxes.hint)
	local status = UiKit.label({
		Name = "Status",
		Text = "",
		FontFace = UiTheme.bodyFont,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = button,
	})
	place(status, boxes.status)
	local card: Card = {
		kind = kind,
		id = id,
		unlock = unlock,
		button = button,
		stroke = stroke,
		name = nameLabel,
		status = status,
		color = color,
	}
	button.Activated:Connect(function()
		SoundPlayer.ui("click")
		tapped(card)
	end)
	return card
end

local function buildTab(current: Dialog)
	current.content:ClearAllChildren()
	table.clear(current.cards)
	local tab: Tab = current.tab
	for id, button in current.tabs do
		button.BackgroundColor3 = if id == tab then UiTheme.palette("gold") else UiTheme.palette("panelLight")
	end
	local list = L.list(tab)
	local count = if tab == "titles" then #Titles.list + 1 else #Skins.list
	local scroll = UiKit.new("ScrollingFrame", {
		Name = "Grid",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = L.SCROLLBAR,
		ScrollBarImageColor3 = UiTheme.palette("textDim"),
		CanvasSize = UDim2.fromOffset(0, L.canvasHeight(tab, count)),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = current.content,
	}) :: ScrollingFrame
	place(scroll, list)
	local none = Theme.text.styleNoTitle
	if tab == "titles" then
		local free: Types.StyleUnlock = { kind = "free" }
		table.insert(
			current.cards,
			buildCard(
				tab,
				1,
				"title",
				"",
				`{NO_TITLE_ICON} {none}`,
				UiTheme.palette("text"),
				free,
				Theme.text.styleNoTitleHint,
				nil,
				scroll
			)
		)
		for index, def in Titles.list do
			local hint = StyleRules.hint(def.unlock, achievements, tierCount, text)
			table.insert(
				current.cards,
				buildCard(
					tab,
					index + 1,
					"title",
					def.id,
					`{def.icon} {def.text}`,
					UiTheme.color(def.color),
					def.unlock,
					hint,
					nil,
					scroll
				)
			)
		end
	else
		for index, def in Skins.list do
			local hint = StyleRules.hint(def.unlock, achievements, tierCount, text)
			table.insert(
				current.cards,
				buildCard(
					tab,
					index,
					"skin",
					def.id,
					`{def.icon} {def.name}`,
					UiTheme.palette("text"),
					def.unlock,
					hint,
					def,
					scroll
				)
			)
		end
	end
	local view = latest
	if view then
		show(view)
	else
		current.now.Text = Theme.text.styleLoading
		current.nowHint.Text = ""
	end
end

-- Opens the Style dialog on `tab` (Titles by default).
function StyleController.open(tab: Tab?)
	if not listening then
		listening = true
		Net.get("StyleSync").OnClientEvent:Connect(show)
	end
	local modal = Modal.open(Theme.text.styleTitle, Vector2.new(L.DIALOG.w, L.DIALOG.h), function()
		dialog = nil
	end)
	local tabs: { [string]: TextButton } = {}
	local now, nowHint = L.nowLines()
	local nowLabel =
		UiKit.label({ Name = "Now", Text = "", TextXAlignment = Enum.TextXAlignment.Left, Parent = modal.body })
	place(nowLabel, now)
	local hintLabel = UiKit.label({
		Name = "NowHint",
		Text = "",
		FontFace = UiTheme.bodyFont,
		TextColor3 = UiTheme.palette("textDim"),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = modal.body,
	})
	place(hintLabel, nowHint)
	local content = UiKit.new("Frame", {
		Name = "Content",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = modal.body,
	}) :: Frame
	local first: Tab = if tab ~= nil then tab else "titles"
	local current: Dialog = {
		modal = modal,
		tab = first,
		tabs = tabs,
		content = content,
		now = nowLabel,
		nowHint = hintLabel,
		cards = {},
	}
	for index, id: Tab in L.TABS do
		local button = UiKit.button({
			Name = id,
			Text = TAB_TEXT[id],
			BackgroundColor3 = UiTheme.palette("panelLight"),
			Parent = modal.body,
		}, function()
			if current.tab ~= id and dialog == current then
				current.tab = id
				buildTab(current)
			end
		end)
		place(button, L.tabButton(index))
		tabs[id] = button
	end
	dialog = current
	buildTab(current)
	Net.get("GetStyle"):FireServer()
end

return StyleController
