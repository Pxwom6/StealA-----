--!strict
--[[
	The Lucky Spin's Details list: every outcome of one spin with its exact chance (Logic/SpinOdds), the itemized
	disclosure Roblox's Paid Random Items policy asks for behind a "Details" button before purchase. First the reel's
	prizes with their chances (what the Odds grid shows; a cash prize with what it pays this player now), then every
	Snackling a spin can give, by rarity, with its chance per spin under each Snackling prize (🎁 plain, ✨ Golden,
	💎 Diamond), then the notes: these odds never change, the policy's rounding note, and a full base sells the prize.

	Opened by Details in the Spin tab's Odds view and on each Lucky Spin pack's Shop card, over that dialog's content,
	with a Back button. Where everything goes: Logic/StoreLayout.oddsDetails and its row helpers (checked by
	tests/StoreLayout.spec.luau: inside the dialogs, a full touch target, every text at 12 UI or more).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Spin = require(ReplicatedStorage.Shared.Config.Spin)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local GameData = require(ReplicatedStorage.Shared.GameData)
local Types = require(ReplicatedStorage.Shared.Types)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local SpinOdds = require(ReplicatedStorage.Shared.Logic.SpinOdds)
local StoreLayout = require(ReplicatedStorage.Shared.Logic.StoreLayout)
local UiKit = require(script.Parent.UiKit)

local OddsDetails = {}

local D = StoreLayout.DETAILS

-- What a reel segment's row says it gives: a cash prize what it pays this player now (ClientState.spin.rewards),
-- else its rule; a Snackling prize points at the list (naming its mutation, if it always has one).
function OddsDetails.prizeText(segment: Types.SpinSegment, amount: number?): string
	local reward = segment.reward :: any
	if reward.kind == "creature" then
		local mutation = if reward.mutation then GameData.catalog.mutations[reward.mutation] else nil
		if mutation then
			return Format.template(
				Theme.text.spinDetailsSnacklingMutation,
				{ icon = segment.icon, label = segment.label, mutation = mutation.displayName }
			)
		end
		return Format.template(Theme.text.spinDetailsSnackling, { icon = segment.icon, label = segment.label })
	end
	local paid = if type(amount) == "number" and amount > 0
		then UiTheme.cash(amount)
		else Format.template(Theme.text.spinDetailsCashTime, {
			time = (string.gsub(Format.duration(reward.incomeSeconds or 0), " 0s$", "")),
		})
	return Format.template(Theme.text.spinDetailsCash, { icon = segment.icon, label = segment.label, amount = paid })
end

local function text(parent: Instance, r: StoreLayout.Rect, value: string, props: { [string]: any }?): TextLabel
	local defaults: { [string]: any } = {
		Text = value,
		TextScaled = false,
		TextSize = D.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(r.x, r.y),
		Size = UDim2.fromOffset(r.w, r.h),
		ZIndex = (parent :: GuiObject).ZIndex + 1,
		Parent = parent,
	}
	if props then
		for key, item in props do
			defaults[key] = item
		end
	end
	return UiKit.label(defaults)
end

-- Builds the list over `area` of `parent` (UI units in `parent`'s coordinates) at `zIndex` and up, hidden.
-- `rewards`: the cash each reel segment pays this player now (by segment index; may be empty). `onBack` runs when
-- Back is tapped (the caller hides it). Returns the overlay.
function OddsDetails.build(
	parent: GuiObject,
	area: StoreLayout.Rect,
	zIndex: number,
	rewards: { number },
	onBack: () -> ()
): GuiObject
	-- A (text-less) button, so taps on the list never reach the dialog's buttons under it.
	local overlay = UiKit.new("TextButton", {
		Name = "OddsDetails",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = UiTheme.palette("panel"),
		Position = UDim2.fromOffset(area.x, area.y),
		Size = UDim2.fromOffset(area.w, area.h),
		ZIndex = zIndex,
		Visible = false,
		Parent = parent,
	}) :: TextButton
	local boxes = StoreLayout.oddsDetails(area.w, area.h)
	local title = boxes.title.rect
	text(overlay, title, Theme.text.spinDetailsTitle, {
		TextScaled = true,
		TextColor3 = UiTheme.palette("gold"),
	})
	local back = UiKit.button({
		Name = "Back",
		BackgroundColor3 = UiTheme.palette("panelLight"),
		Text = Theme.text.spinOddsBack,
		Position = UDim2.fromOffset(boxes.back.rect.x, boxes.back.rect.y),
		Size = UDim2.fromOffset(boxes.back.rect.w, boxes.back.rect.h),
		ZIndex = zIndex + 2,
		Parent = overlay,
	}, onBack)
	for _, child in back:GetDescendants() do
		if child:IsA("GuiObject") then
			child.ZIndex = zIndex + 3
		end
	end
	local listRect = boxes.list.rect
	local list = UiKit.new("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromOffset(listRect.x, listRect.y),
		Size = UDim2.fromOffset(listRect.w, listRect.h),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = D.scrollBar,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = zIndex + 1,
		Parent = overlay,
	}) :: ScrollingFrame
	UiKit.new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
	local w = listRect.w
	local order = 0
	local function row(rows: number?): Frame
		order += 1
		return UiKit.new("Frame", {
			Name = `Row{order}`,
			LayoutOrder = order,
			Size = UDim2.fromOffset(w, D.row * (rows or 1)),
			BackgroundTransparency = 1,
			ZIndex = zIndex + 1,
			Parent = list,
		}) :: Frame
	end
	local function line(value: string, color: Color3?, rows: number?)
		local r = StoreLayout.detailsLine(w, rows or 1)
		text(row(rows), r, value, {
			TextWrapped = (rows or 1) > 1,
			TextColor3 = color or UiTheme.palette("text"),
		})
	end

	local catalog = GameData.catalog
	local odds = SpinOdds.table(Spin, catalog.rarityList, catalog.creatureList)
	-- the reel's prizes: what each pays (a Snackling prize: from the list below), and its chance
	line(Theme.text.spinDetailsReel, UiTheme.palette("gold"))
	for index, entry in odds.segments do
		local prize, chance = StoreLayout.detailsPrize(w)
		local frame = row()
		text(frame, prize, OddsDetails.prizeText(entry.segment, rewards[index]))
		text(frame, chance, Format.percentPrecise(entry.chance), { TextXAlignment = Enum.TextXAlignment.Right })
	end
	-- every Snackling, by rarity: its chance per spin under each Snackling prize
	line(Theme.text.spinDetailsSnacklings, UiTheme.palette("gold"))
	local columns = #odds.columns
	do
		local frame = row()
		local _, heads = StoreLayout.detailsColumns(w, columns, false)
		for index, segment in odds.columns do
			text(frame, heads[index], `{segment.icon} {segment.label}`, {
				TextXAlignment = Enum.TextXAlignment.Right,
				TextColor3 = UiTheme.color(segment.color),
			})
		end
	end
	for _, tier in odds.tiers do
		local rarity = catalog.rarities[tier.rarity]
		local color = UiTheme.rarityColor(tier.rarity)
		local frame = row()
		local name, cells = StoreLayout.detailsColumns(w, columns, false)
		text(frame, name, rarity.displayName, { TextColor3 = color })
		for index, chance in tier.chances do
			text(frame, cells[index], Format.percentPrecise(chance), {
				TextXAlignment = Enum.TextXAlignment.Right,
				TextColor3 = color,
			})
		end
		for _, creature in tier.creatures do
			local def = catalog.creatures[creature.id]
			local creatureRow = row()
			local creatureName, creatureCells = StoreLayout.detailsColumns(w, columns, true)
			text(creatureRow, creatureName, if def then GameData.displayName(def, nil) else creature.id)
			for index, chance in creature.chances do
				text(creatureRow, creatureCells[index], Format.percentPrecise(chance), {
					TextXAlignment = Enum.TextXAlignment.Right,
				})
			end
		end
	end
	-- the notes
	line(Theme.text.spinDetailsFixed, UiTheme.palette("textDim"), D.noteRows)
	line(Theme.text.spinDetailsRounded, UiTheme.palette("textDim"), D.noteRows)
	line(Theme.text.spinDetailsSold, UiTheme.palette("textDim"), D.noteRows)
	return overlay
end

return OddsDetails
