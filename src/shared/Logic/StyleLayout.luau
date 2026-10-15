--!strict
--[[
	Where everything goes in the Style dialog (StyleController) and the Settings dialog's last row (SettingsController),
	in UI units inside a dialog's body (Modal: the body starts 16 in from the panel's sides and 58 from its top, and
	ends 14 above its bottom). Pure, so tests can hold them to the HUD's rules (DECISIONS #47): the dialog fits every
	checked screen below Roblox's top bar, every button is a full touch target (52 UI, 44 px on the smallest phones) and
	every text reads at 12 UI or more (Logic/TextFit).

	Style dialog
	  tab bar   Titles and Base, then a line about what is worn and a hint under it
	  content   from y 60: a scrolling grid of cards (three columns of titles, two of skins with a colour swatch);
	            a card is one button: tap it to wear that title or skin. Inside: the name, how to earn it (two lines),
	            and its state ("Tap to wear", "✓ Wearing", "🔒 12 / 25")
	Settings  the last row: Style and Codes side by side, and the host panel for players who may host
]]

local StyleLayout = {}

export type Rect = { x: number, y: number, w: number, h: number }
export type Size = { w: number, h: number }
export type Tab = "titles" | "base"

StyleLayout.DIALOG = table.freeze({ w = 700, h = 336 }) -- the size Modal.open gets
StyleLayout.BODY = table.freeze({ w = 668, h = 264 })
StyleLayout.BUTTON = 52 -- the smallest side of any button
StyleLayout.GAP = 6
StyleLayout.TAB = table.freeze({ w = 150, h = 52 })
local TABS: { Tab } = { "titles", "base" }
StyleLayout.TABS = TABS
StyleLayout.CONTENT_TOP = 60
StyleLayout.SCROLLBAR = 6
-- A grid's cards sit this far in from its edges, so their borders (UiKit.STROKE.normal) are never clipped.
StyleLayout.LIST_INSET = 3
StyleLayout.COLUMNS = table.freeze({ titles = 3, base = 2 } :: { [string]: number })
StyleLayout.CARD_W = table.freeze({ titles = 214, base = 324 } :: { [string]: number })
StyleLayout.CARD_H = 96
StyleLayout.CARD_PAD = 8
StyleLayout.SWATCH = 76 -- the Base cards' colour swatch (a square)

-- Settings (SettingsController): its body and the last row's height; the row's buttons hold a label 16 in from each
-- side, 40 tall.
StyleLayout.SETTINGS_BODY_W = 460 - 32
StyleLayout.SETTINGS_ROW_H = 54
StyleLayout.SETTINGS_ROW_GAP = 8
StyleLayout.SETTINGS_LABEL_INSET = 16
StyleLayout.SETTINGS_LABEL_H = 40

local function rect(x: number, y: number, w: number, h: number): Rect
	return { x = x, y = y, w = w, h = h }
end

function StyleLayout.tabButton(index: number): Rect
	local T = StyleLayout.TAB
	return rect((index - 1) * (T.w + StyleLayout.GAP), 0, T.w, T.h)
end

-- Right of the tabs: what is worn (the top line) and a hint under it.
function StyleLayout.nowLines(): (Rect, Rect)
	local last = StyleLayout.tabButton(#StyleLayout.TABS)
	local x = last.x + last.w + 12
	local w = StyleLayout.BODY.w - x
	return rect(x, 0, w, 30), rect(x, 32, w, 20)
end

function StyleLayout.cardSize(tab: Tab): Size
	return { w = StyleLayout.CARD_W[tab], h = StyleLayout.CARD_H }
end

-- The scrolling grid of `tab`, sized to hold its columns (inset from its edges) beside its scroll bar.
function StyleLayout.list(tab: Tab): Rect
	local columns, w = StyleLayout.COLUMNS[tab], StyleLayout.CARD_W[tab]
	local width = 2 * StyleLayout.LIST_INSET + columns * w + (columns - 1) * StyleLayout.GAP + StyleLayout.SCROLLBAR
	local top = StyleLayout.CONTENT_TOP
	return rect(0, top, width, StyleLayout.BODY.h - top)
end

-- Card `index` (1-based) of `tab` inside its grid's canvas.
function StyleLayout.cardAt(tab: Tab, index: number): Rect
	local columns, size = StyleLayout.COLUMNS[tab], StyleLayout.cardSize(tab)
	local column, row = (index - 1) % columns, (index - 1) // columns
	local inset, gap = StyleLayout.LIST_INSET, StyleLayout.GAP
	return rect(inset + column * (size.w + gap), inset + row * (size.h + gap), size.w, size.h)
end

-- How tall the grid's canvas is for `count` cards.
function StyleLayout.canvasHeight(tab: Tab, count: number): number
	local rows = math.ceil(math.max(count, 1) / StyleLayout.COLUMNS[tab])
	return 2 * StyleLayout.LIST_INSET + rows * StyleLayout.CARD_H + (rows - 1) * StyleLayout.GAP
end

-- What is inside a card of `tab`: the name, the hint (how to earn it, two lines), the state, and on Base the swatch.
function StyleLayout.cardBoxes(tab: Tab): { [string]: Rect }
	local size = StyleLayout.cardSize(tab)
	local pad = StyleLayout.CARD_PAD
	local x = pad
	local boxes: { [string]: Rect } = {}
	if tab == "base" then
		local s = StyleLayout.SWATCH
		boxes.swatch = rect(pad, (size.h - s) / 2, s, s)
		x = pad + s + pad
	end
	local w = size.w - x - pad
	boxes.name = rect(x, 6, w, 28)
	boxes.hint = rect(x, 36, w, 34) -- two lines at 14 UI
	boxes.status = rect(x, 72, w, 20)
	return boxes
end

-- The Settings dialog's last row: Style and Codes, and for players who may host the host panel too (left to right).
function StyleLayout.settingsRow(mayHost: boolean): { Rect }
	local count = if mayHost then 3 else 2
	local gap = StyleLayout.SETTINGS_ROW_GAP
	local w = (StyleLayout.SETTINGS_BODY_W - (count - 1) * gap) / count
	local row: { Rect } = {}
	for i = 1, count do
		table.insert(row, rect((i - 1) * (w + gap), 0, w, StyleLayout.SETTINGS_ROW_H))
	end
	return row
end

-- The label box inside one of those buttons.
function StyleLayout.settingsLabel(button: Rect): Rect
	local inset = StyleLayout.SETTINGS_LABEL_INSET
	return rect(inset, 7, button.w - 2 * inset, StyleLayout.SETTINGS_LABEL_H)
end

-- Problems with the dialog on a screen `width` x `height` UI with Roblox's top bar ending at `topBar`: it must fit
-- across with `margin` to spare each side, and, with its drop shadow (6 lower), in the part below the top bar, where
-- Modal centres it.
function StyleLayout.fitProblems(width: number, height: number, topBar: number, margin: number): { string }
	local problems: { string } = {}
	local size = StyleLayout.DIALOG
	if size.w + 2 * margin > width then
		table.insert(problems, `the dialog is {size.w} wide, the screen {math.floor(width)}`)
	end
	if size.h + 6 > height - topBar then
		table.insert(problems, `the dialog is {size.h} tall, {math.floor(height - topBar)} below the top bar`)
	end
	return problems
end

return StyleLayout
