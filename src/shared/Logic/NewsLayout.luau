--!strict
--[[
	Where everything goes on the What's New card (WhatsNewController) and on the What's New board by the spawn plaza
	(NewsService), for Config/Updates' newest update. Pure, so tests can prove the card fits every checked screen and
	reads at 12 UI or more like the HUD (DECISIONS #47), and that the board's lines stay big enough to read from a few
	benches away.

	  card   UI units inside the card's body (Modal: 16 in from the panel's sides, 58 from its top, 14 from its
	         bottom): the update's title, its number and date, a line per highlight, a big "Let's go!" button
	  board  pixels on the board's SurfaceGui (BOARD.pixelsPerStud): a header, the title, a line per highlight and the
	         number and date at the bottom
]]

local NewsLayout = {}

export type Rect = { x: number, y: number, w: number, h: number }

NewsLayout.CARD = table.freeze({ w = 560, h = 336 }) -- the size Modal.open gets
NewsLayout.BODY = table.freeze({ w = 528, h = 264 })
NewsLayout.BUTTON = table.freeze({ w = 240, h = 56 })
NewsLayout.LINE = 28
NewsLayout.LINE_GAP = 2

-- The board's face in studs, and its SurfaceGui's resolution. MapBuilder builds the panel this size, its bottom
-- `lift` studs above the ground on two legs.
NewsLayout.BOARD = table.freeze({ w = 14, h = 9, pixelsPerStud = 50, lift = 3 })
NewsLayout.BOARD_PAD = 24 -- px from the panel's edges
NewsLayout.BOARD_LINE = 44 -- px per highlight
-- The smallest text the board may show, in px at its resolution: 18 px at 50 px a stud is a letter about 0.36 studs
-- tall, readable on a phone from about 12-16 studs, so once a player walks up to it (not from the spawn: the card is
-- how most players read an update).
NewsLayout.BOARD_MIN_TEXT = 18

local function rect(x: number, y: number, w: number, h: number): Rect
	return { x = x, y = y, w = w, h = h }
end

-- The card's boxes for `lines` highlights: title, meta (number and date), line1..lineN and button.
function NewsLayout.cardBoxes(lines: number): { [string]: Rect }
	local B = NewsLayout.BODY
	local boxes: { [string]: Rect } = {
		title = rect(0, 0, B.w, 32),
		meta = rect(0, 32, B.w, 18),
	}
	local y = 54
	for i = 1, lines do
		boxes[`line{i}`] = rect(0, y, B.w, NewsLayout.LINE)
		y += NewsLayout.LINE + NewsLayout.LINE_GAP
	end
	local button = NewsLayout.BUTTON
	boxes.button = rect((B.w - button.w) / 2, B.h - button.h, button.w, button.h)
	return boxes
end

-- The board's boxes for `lines` highlights, in px on its SurfaceGui: header, title, line1..lineN and meta.
function NewsLayout.boardBoxes(lines: number): { [string]: Rect }
	local B = NewsLayout.BOARD
	local w, h = B.w * B.pixelsPerStud, B.h * B.pixelsPerStud
	local pad = NewsLayout.BOARD_PAD
	local boxes: { [string]: Rect } = {
		header = rect(0, 0, w, 72),
		title = rect(pad, 78, w - 2 * pad, 44),
		meta = rect(pad, h - pad - 32, w - 2 * pad, 32),
	}
	local y = 130
	for i = 1, lines do
		boxes[`line{i}`] = rect(pad, y, w - 2 * pad, NewsLayout.BOARD_LINE)
		y += NewsLayout.BOARD_LINE
	end
	return boxes
end

-- Problems with the card on a screen `width` x `height` UI with Roblox's top bar ending at `topBar` (like
-- StyleLayout.fitProblems): `margin` to spare each side, and with its drop shadow (6 lower) below the top bar.
function NewsLayout.fitProblems(width: number, height: number, topBar: number, margin: number): { string }
	local problems: { string } = {}
	local size = NewsLayout.CARD
	if size.w + 2 * margin > width then
		table.insert(problems, `the card is {size.w} wide, the screen {math.floor(width)}`)
	end
	if size.h + 6 > height - topBar then
		table.insert(problems, `the card is {size.h} tall, {math.floor(height - topBar)} below the top bar`)
	end
	return problems
end

return NewsLayout
