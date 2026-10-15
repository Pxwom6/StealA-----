--!strict
--[[
	Where the store additions go inside their dialogs, in UI units. Modal gives a dialog's body 16 in from the panel's
	sides, 58 from its top and 14 above its bottom; the Rewards panel and the Shop put their tab bar there and a tab's
	content CONTENT_TOP below it. Pure, so tests/StoreLayout.spec.luau and tools/layoutCheck.luau hold these to the
	HUD's rules (DECISIONS.md #47) on all five checked screens: both dialogs fit below Roblox's top bar, every button is
	a full touch target (52 UI, 44 px on the smallest phones), every label reads at 12 UI or more (Logic/TextFit), and
	nothing overlaps.

	  Spin tab (Rewards)   the reel, and right of it the two Lucky Spin pack buttons (shown only to players whose
	                       Roblox policy allows paid random items, once the packs exist); SPIN!, Odds and the base-full
	                       warning under it, then the status line. Odds swaps the reel for the grid of every prize's
	                       exact chance, so with the packs shown the chances sit right beside their buy buttons.
	  Shop: a pack's card  its name and what it is beside the buy button, and the same odds grid across the card
	  Shop: Starter Pack   its name and what it is beside the buy button, then one line per thing it gives
]]

local ScreenLayout = require("./ScreenLayout")

local StoreLayout = {}

export type Rect = { x: number, y: number, w: number, h: number }
export type Kind = "button" | "label" | "panel"
export type Box = { rect: Rect, kind: Kind }

local function rect(x: number, y: number, w: number, h: number): Rect
	return { x = x, y = y, w = w, h = h }
end

local function box(kind: Kind, x: number, y: number, w: number, h: number): Box
	return { rect = rect(x, y, w, h), kind = kind }
end

StoreLayout.BUTTON = 52 -- every button's smallest side
StoreLayout.GAP = 6
-- Text inside a button sits this far in from its edges (UiKit.button pads 8 x 6).
StoreLayout.PAD = table.freeze({ x = 8, y = 6 })
-- Modal's margins around a dialog's body, and the tab bar both dialogs put at its top.
StoreLayout.MODAL = table.freeze({ side = 16, top = 58, bottom = 14 })
StoreLayout.CONTENT_TOP = 58

-- The two dialogs (the sizes their controllers give Modal.open), and the room they leave on every side of the part of
-- the screen below Roblox's top bar on every checked screen (the smallest phone, 640x360, leaves 7.6 UI above and
-- below: Modal's 340-tall limit).
StoreLayout.REWARDS = table.freeze({ w = 620, h = 340 })
StoreLayout.STORE = table.freeze({ w = 640, h = 340 })
StoreLayout.MARGIN = 4

-- A tab's content area in a dialog of `dialog`'s size.
function StoreLayout.content(dialog: { w: number, h: number }): { w: number, h: number }
	local M = StoreLayout.MODAL
	return { w = dialog.w - 2 * M.side, h = dialog.h - M.top - M.bottom - StoreLayout.CONTENT_TOP }
end

-- Problems fitting both dialogs on a screen `width` x `height` UI units whose top `topBar` is Roblox's (an empty list
-- means they fit). Modal centres a dialog below the top bar.
function StoreLayout.fitProblems(width: number, height: number, topBar: number, margin: number): { string }
	local problems: { string } = {}
	local dialogs: { { name: string, w: number, h: number } } = {
		{ name = "Rewards", w = StoreLayout.REWARDS.w, h = StoreLayout.REWARDS.h },
		{ name = "Shop", w = StoreLayout.STORE.w, h = StoreLayout.STORE.h },
	}
	for _, dialog in dialogs do
		local name = dialog.name
		if dialog.w + 2 * margin > width then
			table.insert(problems, `the {name} dialog is {dialog.w} wide, the screen {math.floor(width)}`)
		end
		if dialog.h + 2 * margin > height - topBar then
			table.insert(
				problems,
				`the {name} dialog is {dialog.h} tall, {math.floor(height - topBar)} below the top bar`
			)
		end
	end
	return problems
end

-- Where a tab's content area starts on a screen `width` x `height` UI units with Roblox's top bar `topBar` tall: Modal
-- centres the dialog below the top bar, its body is MODAL in, and the content CONTENT_TOP below the tab bar.
function StoreLayout.contentOrigin(
	width: number,
	height: number,
	topBar: number,
	dialog: { w: number, h: number }
): (number, number)
	local M = StoreLayout.MODAL
	local x = (width - dialog.w) / 2 + M.side
	local y = topBar + (height - topBar - dialog.h) / 2 + M.top + StoreLayout.CONTENT_TOP
	return x, y
end

-- The Spin tab ------------------------------------------------------------------------------------------------------

StoreLayout.SPIN = table.freeze({
	inset = 4, -- the reel's distance from the content's sides
	top = 2,
	reel = 112, -- the reel's height (its tiles are 100 tall)
	pack = { w = 136, h = 53 }, -- each Lucky Spin pack button, stacked right of the reel
	row = 122, -- the SPIN! row's top
	spin = { w = 240, h = 56 },
	odds = { w = 100, h = 52, top = 124 },
	-- "Base full: Snackling prizes will be sold", left of SPIN! (its text is checked with the HUD's, ScreenLayout.spec)
	warning = ScreenLayout.TEXT.prizesBaseFull.spin,
	status = { top = 184, h = 22 },
	-- Inside a pack button (UiKit.button's padding taken off): its name over its price.
	packName = 22,
	packPrice = 19,
})

-- The Spin tab's boxes in its content area (StoreLayout.content(REWARDS)); `packs`: the pack buttons show.
function StoreLayout.spinTab(packs: boolean): { [string]: Box }
	local S = StoreLayout.SPIN
	local W = StoreLayout.content(StoreLayout.REWARDS).w
	local reelW = W - 2 * S.inset - (if packs then S.pack.w + StoreLayout.GAP else 0)
	local boxes: { [string]: Box } = {
		reel = box("panel", S.inset, S.top, reelW, S.reel),
		odds = box("panel", S.inset, S.top, reelW, S.reel), -- the Odds view, in the reel's place
		warning = box("label", S.inset, S.row, S.warning.w, S.warning.h),
		spin = box("button", (W - S.spin.w) / 2, S.row, S.spin.w, S.spin.h),
		oddsButton = box("button", W - S.inset - S.odds.w, S.odds.top, S.odds.w, S.odds.h),
		status = box("label", 0, S.status.top, W, S.status.h),
	}
	if packs then
		local x = S.inset + reelW + StoreLayout.GAP
		boxes.pack1 = box("button", x, S.top, S.pack.w, S.pack.h)
		boxes.pack2 = box("button", x, S.top + S.reel - S.pack.h, S.pack.w, S.pack.h)
	end
	return boxes
end

-- The name and price lines inside a pack button `r` (padding taken off).
function StoreLayout.packText(r: Rect): (Rect, Rect)
	local S, P = StoreLayout.SPIN, StoreLayout.PAD
	local w = r.w - 2 * P.x
	return rect(r.x + P.x, r.y + P.y, w, S.packName), rect(r.x + P.x, r.y + P.y + S.packName, w, S.packPrice)
end

-- The odds grid ----------------------------------------------------------------------------------------------------

StoreLayout.ODDS = table.freeze({ columns = 4, gap = 6, padX = 4, prize = 0.52, chance = 0.42 })

-- `count` cells in rows of ODDS.columns filling `area`, `gap` apart and from its edges.
function StoreLayout.oddsCells(area: Rect, count: number): { Rect }
	local O = StoreLayout.ODDS
	local columns = O.columns
	local rows = math.max(1, math.ceil(count / columns))
	local w = (area.w - O.gap * (columns + 1)) / columns
	local h = (area.h - O.gap * (rows + 1)) / rows
	local cells: { Rect } = {}
	for index = 1, count do
		local column = (index - 1) % columns
		local row = (index - 1) // columns
		table.insert(cells, rect(area.x + O.gap + column * (w + O.gap), area.y + O.gap + row * (h + O.gap), w, h))
	end
	return cells
end

-- A cell's prize line ("🎰 JACKPOT") over its chance ("1.5%").
function StoreLayout.oddsText(cell: Rect): (Rect, Rect)
	local O = StoreLayout.ODDS
	local w = cell.w - 2 * O.padX
	return rect(cell.x + O.padX, cell.y + 2, w, cell.h * O.prize),
		rect(cell.x + O.padX, cell.y + cell.h * (1 - O.chance) - 2, w, cell.h * O.chance)
end

-- Shop cards -------------------------------------------------------------------------------------------------------

-- A Shop card is the Shop's content width less its scroll bar; the name and description leave room for the buy
-- button at the right (StoreController's other cards use the same text column).
StoreLayout.CARD = table.freeze({
	w = 600,
	textX = 20,
	textW = 400,
	title = { y = 8, h = 34 },
	description = { y = 44, h = 36 },
	buy = { w = 160, h = 58, right = 12, top = 14 },
	bottom = 10,
	-- A Lucky Spin pack: the odds grid across the card, under the buy button.
	odds = { y = 86, h = 98 },
	-- The Starter Pack: one line per thing it gives.
	line = { y = 84, h = 24, gap = 2 },
})

-- A Lucky Spin pack's card: its boxes and height.
function StoreLayout.packCard(): ({ [string]: Box }, number)
	local C = StoreLayout.CARD
	local boxes: { [string]: Box } = {
		title = box("label", C.textX, C.title.y, C.textW, C.title.h),
		description = box("label", C.textX, C.description.y, C.textW, C.description.h),
		buy = box("button", C.w - C.buy.right - C.buy.w, C.buy.top, C.buy.w, C.buy.h),
		odds = box("panel", C.textX, C.odds.y, C.w - 2 * C.textX, C.odds.h),
	}
	return boxes, C.odds.y + C.odds.h + C.bottom
end

-- The Starter Pack's card with `lines` content lines: its boxes ("line1"...) and height.
function StoreLayout.starterCard(lines: number): ({ [string]: Box }, number)
	local C = StoreLayout.CARD
	local boxes: { [string]: Box } = {
		title = box("label", C.textX, C.title.y, C.textW, C.title.h),
		description = box("label", C.textX, C.description.y, C.textW, C.description.h),
		buy = box("button", C.w - C.buy.right - C.buy.w, C.buy.top, C.buy.w, C.buy.h),
	}
	local y = C.line.y
	for index = 1, lines do
		boxes[`line{index}`] = box("label", C.textX, y, C.w - 2 * C.textX, C.line.h)
		y += C.line.h + C.line.gap
	end
	return boxes, y - C.line.gap + C.bottom
end

-- Every problem with the Spin tab (with and without the pack buttons) on one screen, `scale` px per UI unit: a box off
-- the screen or under Roblox's top bar, or a button under `minTouch` px. Returns the problems and the boxes on screen
-- (UI units from the screen's top left) for printing.
function StoreLayout.screenProblems(
	width: number,
	height: number,
	topBar: number,
	scale: number,
	minTouch: number
): ({ string }, { [string]: Rect })
	local problems: { string } = {}
	local placed: { [string]: Rect } = {}
	local ox, oy = StoreLayout.contentOrigin(width, height, topBar, StoreLayout.REWARDS)
	for _, packs in { false, true } do
		local suffix = if packs then "+packs" else ""
		for name, b in StoreLayout.spinTab(packs) do
			local r = rect(ox + b.rect.x, oy + b.rect.y, b.rect.w, b.rect.h)
			placed[name .. suffix] = r
			if r.x < 0 or r.x + r.w > width or r.y < topBar or r.y + r.h > height then
				table.insert(problems, `Spin tab{suffix}: {name} is off the screen or under the top bar`)
			end
			if b.kind == "button" and math.min(r.w, r.h) * scale < minTouch then
				table.insert(problems, `Spin tab{suffix}: {name} is under {minTouch} px`)
			end
		end
	end
	return problems, placed
end

-- Pairs of boxes drawn over each other on purpose: the Odds view takes the reel's place.
StoreLayout.STACKED = table.freeze({ "odds|reel" })

-- Every problem with `boxes` laid out in a `w` x `h` area: outside it, overlapping (but for StoreLayout.STACKED
-- pairs), or a button too small to tap.
function StoreLayout.problems(boxes: { [string]: Box }, w: number, h: number): { string }
	local problems: { string } = {}
	local names: { string } = {}
	for name in boxes do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in names do
		local r = boxes[name].rect
		if r.x < -1e-6 or r.y < -1e-6 or r.x + r.w > w + 1e-6 or r.y + r.h > h + 1e-6 then
			table.insert(problems, `{name} sticks out of its {w}x{h} area`)
		end
		if boxes[name].kind == "button" and (r.w < StoreLayout.BUTTON or r.h < StoreLayout.BUTTON) then
			table.insert(problems, `{name} is {r.w}x{r.h}, under a {StoreLayout.BUTTON} touch target`)
		end
	end
	for i, a in names do
		for j = i + 1, #names do
			local b = names[j]
			local ra, rb = boxes[a].rect, boxes[b].rect
			local apart = ra.x + ra.w <= rb.x or rb.x + rb.w <= ra.x or ra.y + ra.h <= rb.y or rb.y + rb.h <= ra.y
			if not apart and table.find(StoreLayout.STACKED, `{a}|{b}`) == nil then
				table.insert(problems, `{a} overlaps {b}`)
			end
		end
	end
	return problems
end

return StoreLayout
