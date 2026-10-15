--!strict
--[[
	Where every HUD element goes, and the check that keeps them out of each other's way (DECISIONS.md #23, #26, #47).
	Pure: no Roblox APIs. HudController builds a Device from the real screen (ScreenLayout.device) and places every HUD
	frame where ScreenLayout.hud says; tests/ScreenLayout.spec.luau and tools/layoutCheck.luau run the same functions on
	the phones, tablets and windows the game targets, in the busiest states, and fail on any problem.

	Units: UI units (reference px; UiKit scales them by ScreenLayout.scaleFor) in HUD coordinates, whose origin is the
	top-left corner of the device's safe area. Every game screen uses DeviceSafeInsets (UiKit.screen), so the HUD starts
	at the top of the screen, under Roblox's top bar (58 px), whose buttons sit at its left: the HUD uses the rest of
	that strip and keeps clear of them. Rects are { x, y, w, h }.

	The HUD on a landscape phone (667x375 px at UI scale 0.85 = 785x441 UI):

	  top centre    the cash pill (cash and cash/sec) in Roblox's top bar strip, then one band above the play zone: the
	                tutorial banner, or the "Need $X more?" strip, or the status pills (event, the running modifier,
	                server luck; side by side, more rows when the screen is narrow)
	  top right     the corner row in the top bar strip: lock button, 👥 Friends, ⚙ settings (under Roblox's top-left
	                buttons instead when the player list leaves no room at the right)
	  top left      the four feature buttons in a 2x2 grid under Roblox's top-left buttons, above the thumbstick
	  right         the TAG! button, above the jump button and below the player list
	  bottom        the map vote between the thumbstick and the jump button; toasts above it
	  middle        the play zone (the character and the prompts near it): nothing tappable
]]

local TextFit = require("./TextFit")

local ScreenLayout = {}

export type Rect = { x: number, y: number, w: number, h: number }

-- UiKit's scale: the HUD is authored for a 540-tall, 900-wide reference screen and scaled to the device, never below
-- 0.85 (so 52 UI is a full 44 px touch target on the smallest phones) nor above 1.35. The width limit keeps 4:3
-- tablets (1024x768 → 1.14) from getting a HUD too wide for their screen.
ScreenLayout.SCALE = table.freeze({ referenceHeight = 540, referenceWidth = 900, min = 0.85, max = 1.35 })

function ScreenLayout.scaleFor(widthPx: number, heightPx: number): number
	local s = math.min(heightPx / ScreenLayout.SCALE.referenceHeight, widthPx / ScreenLayout.SCALE.referenceWidth)
	if s ~= s then
		return 1 -- NaN (no viewport yet)
	end
	return math.clamp(s, ScreenLayout.SCALE.min, ScreenLayout.SCALE.max)
end

-- Roblox's own UI, in screen pixels: the top bar's height and where its left buttons end (the client reads both from
-- GuiService), and the touch controls (copied from the PlayerModule's TouchJump and DynamicThumbstick code).
ScreenLayout.ROBLOX = table.freeze({
	topBar = 58,
	topBarLeft = 210, -- an estimate on the large side; the client uses GuiService.TopbarInset.Min.X
	-- TouchGui sits below the top bar: the dynamic thumbstick starts from the left 40% of it in its lower two thirds;
	-- the jump button is 70 px (120 when the short side is over 500) in the bottom right.
	thumbstickWidthShare = 0.4,
	thumbstickTopShare = 1 / 3,
	jumpSmall = 70,
	jumpBig = 120,
	jumpSmallBelow = 500,
})

-- Estimated size of Roblox's player list in pixels (Roblox does not expose it): the names column plus one column per
-- leaderstat, the gap to the screen edge, a header and a row per player (a full server of 8). It errs on the large side.
ScreenLayout.PLAYER_LIST = table.freeze({ base = 190, perStat = 80, max = 480, margin = 8, header = 40, row = 36 })

-- The play zone: the middle third of the screen, from 30% to 70% of its height. With Roblox's default camera the
-- character's head is at 50% and the Buy / Steal / Open prompts near it are centred at 39-55% (147-207 of 375 px),
-- so their tops reach 30%; the feet are at 70-73%. Nothing tappable goes there.
ScreenLayout.PLAY_ZONE = table.freeze({ left = 1 / 3, right = 2 / 3, top = 0.3, bottom = 0.7 })

ScreenLayout.MIN_TOUCH = 44 -- px, every button on a touch screen
ScreenLayout.EDGE = 8 -- UI units from the screen edge
ScreenLayout.GAP = 6 -- UI units between neighbours that are not in one list

-- Sizes in UI units, shared by the controllers that build these elements and by the check.
ScreenLayout.SIZE = table.freeze({
	stackTop = 6,
	stackGap = 4,
	cash = { w = 250, h = 58, amount = 36, income = 18 }, -- the amount over cash/sec, inside one pill
	tutorial = { w = 420, h = 64, tip = 24, minW = 300 },
	skip = { w = 64, h = 52, inset = 8 }, -- the tutorial's Skip: in the banner's top 64, inset from its right edge
	-- "Need $X more?": text, the Robux button and ✕ (52 tall), inset from the strip's edges
	cashOffer = { w = 400, minW = 330, h = 60, inset = 4, buy = 116, close = 52, text = 12 },
	event = { w = 220, h = 58 }, -- event pill: the banner (two lines) over its countdown
	modifier = { w = 165, h = 52 }, -- the running modifier: a button (tap for its description)
	luck = { w = 165, h = 30 }, -- server luck
	corner = { button = 52, lock = 104, gap = 8, top = 4 },
	side = { w = 76, h = 52, gap = 6, columns = 2, left = 10 },
	tag = { size = 120, pad = 15, right = 24, bottom = 185 }, -- right / bottom: from the HUD's edges
	vote = { header = 20, gap = 4, choice = 68, choiceGap = 6, maxW = 420, thumbGap = 8, jumpGap = 16 },
	toast = { w = 340, h = 40, tall = 56, gap = 6, max = 3, bottom = 110 },
	banner = { w = 560, h = 64 }, -- announcement banners
	titleCard = { w = 400, h = 120 }, -- the new map's title card
	stealAlert = { w = 420, h = 52, y = 230 },
	carry = { w = 320, h = 46, bottom = 60 },
})

-- The text boxes inside those elements (UI units), so tests can prove the text stays readable (Logic/TextFit): no HUD
-- text below TEXT.minSize, 12 UI = 10 px on the smallest phones. `pad`: from the element's edges (UiKit.button pads
-- 8 x 6).
ScreenLayout.TEXT = table.freeze({
	minSize = 12,
	button = { padX = 8, padY = 6 }, -- every UiKit.button (lock, modifier, ...)
	vote = { padX = 4, padY = 2, icon = 16, name = 32, mutation = 16 }, -- top to bottom inside a vote button
	event = { padX = 8, top = 4, banner = 32, countdown = 18 }, -- the banner wraps onto two lines
	luck = { padX = 6, padY = 3 },
	toast = { padX = 8, padY = 4, oneLine = 16 }, -- a toast whose one line would be smaller wraps (the tall toast)
	cashOffer = { top = 4, title = 24, body = 30 }, -- left of the Robux button, from `cashOffer.text`
	banner = { padX = 12, padY = 6 }, -- announcement banners wrap onto two lines
})

export type DeviceSpec = {
	name: string,
	widthPx: number,
	heightPx: number,
	touch: boolean, -- Roblox's touch controls show (thumbstick + jump)
	insetLeftPx: number?, -- the device's safe-area insets (notch, home indicator)
	insetRightPx: number?,
	insetTopPx: number?,
	insetBottomPx: number?,
	playerListPx: number?, -- width the player list takes from the right edge (ScreenLayout.playerListWidth), 0 = none
	players: number?, -- rows in the player list (default 8)
	topBarPx: number?, -- Roblox's top bar height (default ROBLOX.topBar)
	topBarLeftPx: number?, -- where its left buttons end, from the screen's left edge (default ROBLOX.topBarLeft)
	topBarRightPx: number?, -- where its free part ends on the right (default: the screen's right edge)
}

export type Device = {
	name: string,
	widthPx: number,
	heightPx: number,
	touch: boolean,
	scale: number,
	left: number, -- px from the screen's left edge to the HUD's
	top: number, -- px from the screen's top edge to the HUD's
	insetRightPx: number,
	insetBottomPx: number,
	width: number, -- the HUD area (the safe area), UI units
	height: number,
	topBar: number, -- UI y where Roblox's top bar ends
	topBarLeft: number, -- UI x where its left buttons end
	topBarRight: number, -- UI x where its free part ends
	playerList: number, -- UI width the player list takes from the right (0 = none)
	playerListBottom: number, -- UI y of its bottom
}

function ScreenLayout.device(spec: DeviceSpec): Device
	local scale = ScreenLayout.scaleFor(spec.widthPx, spec.heightPx)
	local left = spec.insetLeftPx or 0
	local right = spec.insetRightPx or 0
	local top = spec.insetTopPx or 0
	local bottom = spec.insetBottomPx or 0
	local topBarPx = spec.topBarPx or ScreenLayout.ROBLOX.topBar
	local listPx = spec.playerListPx or 0
	local listBottomPx = topBarPx + ScreenLayout.PLAYER_LIST.header + (spec.players or 8) * ScreenLayout.PLAYER_LIST.row
	return {
		name = spec.name,
		widthPx = spec.widthPx,
		heightPx = spec.heightPx,
		touch = spec.touch,
		scale = scale,
		left = left,
		top = top,
		insetRightPx = right,
		insetBottomPx = bottom,
		width = (spec.widthPx - left - right) / scale,
		height = (spec.heightPx - top - bottom) / scale,
		topBar = (topBarPx - top) / scale,
		topBarLeft = ((spec.topBarLeftPx or ScreenLayout.ROBLOX.topBarLeft) - left) / scale,
		topBarRight = ((spec.topBarRightPx or spec.widthPx) - left) / scale,
		playerList = listPx / scale,
		playerListBottom = if listPx > 0 then (listBottomPx - top) / scale else 0,
	}
end

-- The same device with the player list switched off (the tutorial does that when its banner can't clear it).
function ScreenLayout.withoutPlayerList(device: Device): Device
	local copy = table.clone(device)
	copy.playerList = 0
	copy.playerListBottom = 0
	return copy
end

-- Pixels the player list takes from the right edge of the screen: 0 when it is switched off or on a phone (a
-- touch-only device whose short side is under 500 px, where it starts hidden in Roblox's menu).
function ScreenLayout.playerListWidth(
	enabled: boolean,
	touchOnly: boolean,
	viewportX: number,
	viewportY: number,
	statCount: number
): number
	if not enabled then
		return 0
	end
	if touchOnly and math.min(viewportX, viewportY) < 500 then
		return 0
	end
	local list = ScreenLayout.PLAYER_LIST
	return math.min(list.max, list.base + list.perStat * math.max(0, statCount)) + list.margin
end

local function rect(x: number, y: number, w: number, h: number): Rect
	return { x = x, y = y, w = w, h = h }
end

-- True when two rects overlap by more than `tolerance` (default 0.01) both ways: touching edges don't count.
function ScreenLayout.overlaps(a: Rect, b: Rect, tolerance: number?): boolean
	local eps = tolerance or 0.01
	return a.x < b.x + b.w - eps and b.x < a.x + a.w - eps and a.y < b.y + b.h - eps and b.y < a.y + a.h - eps
end

-- Screen pixels → HUD UI units, and back.
local function fromPx(device: Device, xPx: number, yPx: number): (number, number)
	return (xPx - device.left) / device.scale, (yPx - device.top) / device.scale
end

function ScreenLayout.toPx(device: Device, r: Rect): Rect
	return rect(
		device.left + r.x * device.scale,
		device.top + r.y * device.scale,
		r.w * device.scale,
		r.h * device.scale
	)
end

-- Roblox's UI ----------------------------------------------------------------------------------------------------------

-- Roblox's buttons at the left of its top bar.
function ScreenLayout.topBarButtons(device: Device): Rect
	local x0 = -device.left / device.scale
	return rect(x0, -device.top / device.scale, device.topBarLeft - x0, device.topBar + device.top / device.scale)
end

function ScreenLayout.playerListRect(device: Device): Rect?
	if device.playerList <= 0 then
		return nil
	end
	return rect(
		device.width - device.playerList,
		device.topBar,
		device.playerList,
		device.playerListBottom - device.topBar
	)
end

-- The touch controls' screen (TouchGui): the safe area below the top bar, in px.
local function touchArea(device: Device): (number, number, number, number)
	local topPx = math.max(device.top, device.top + device.topBar * device.scale)
	return device.left,
		topPx,
		device.widthPx - device.left - device.insetRightPx,
		device.heightPx - device.insetBottomPx - topPx
end

-- Where a touch starts the dynamic thumbstick (touch screens only).
function ScreenLayout.thumbstickArea(device: Device): Rect?
	if not device.touch then
		return nil
	end
	local ax, ay, aw, ah = touchArea(device)
	local x0, y0 = fromPx(device, ax, ay + ah * ScreenLayout.ROBLOX.thumbstickTopShare)
	local x1, y1 = fromPx(device, ax + aw * ScreenLayout.ROBLOX.thumbstickWidthShare, ay + ah)
	return rect(x0, y0, x1 - x0, y1 - y0)
end

function ScreenLayout.jumpButton(device: Device): Rect?
	if not device.touch then
		return nil
	end
	local R = ScreenLayout.ROBLOX
	local ax, ay, aw, ah = touchArea(device)
	local size = if math.min(aw, ah) <= R.jumpSmallBelow then R.jumpSmall else R.jumpBig
	local xPx = ax + aw - (size * 1.5 - 10)
	local yPx = if size == R.jumpSmall then ay + ah - size - 20 else ay + ah - size * 1.75
	local x, y = fromPx(device, xPx, yPx)
	return rect(x, y, size / device.scale, size / device.scale)
end

function ScreenLayout.playZone(device: Device): Rect
	local Z = ScreenLayout.PLAY_ZONE
	local x0, y0 = fromPx(device, device.widthPx * Z.left, device.heightPx * Z.top)
	local x1, y1 = fromPx(device, device.widthPx * Z.right, device.heightPx * Z.bottom)
	return rect(x0, y0, x1 - x0, y1 - y0)
end

-- Placement helpers ------------------------------------------------------------------------------------------------------

-- The span [left, right] across the HUD between heights y0 and y1 that stays GAP clear of `obstacles`: an obstacle
-- whose centre is left of `cx` bounds it on the left, one right of `cx` on the right.
function ScreenLayout.lane(device: Device, obstacles: { Rect }, y0: number, y1: number, cx: number): (number, number)
	local left, right = ScreenLayout.EDGE, device.width - ScreenLayout.EDGE
	for _, r in obstacles do
		if r.y < y1 and r.y + r.h > y0 then
			if r.x + r.w / 2 < cx then
				left = math.max(left, r.x + r.w + ScreenLayout.GAP)
			else
				right = math.min(right, r.x - ScreenLayout.GAP)
			end
		end
	end
	return left, right
end

-- x and width of something `w` wide (at least `minW`) centred on `cx` in [left, right]: narrowed evenly while it
-- stays at least `minW`, else shifted to fit (or, `centred`, kept centred at `minW`: the caller makes room).
function ScreenLayout.fitSpan(
	cx: number,
	w: number,
	minW: number,
	left: number,
	right: number,
	centred: boolean?
): (number, number)
	local even = 2 * math.min(cx - left, right - cx)
	if even >= math.min(w, minW) or centred then
		local width = math.max(math.min(w, minW), math.min(w, even))
		return cx - width / 2, width
	end
	local width = math.max(math.min(minW, w), math.min(w, right - left))
	return math.clamp(cx - width / 2, left, math.max(left, right - width)), width
end

-- The corner row (widths left to right: lock, Friends, gear) and whether it had to leave the top-right corner. It sits
-- right-aligned in the top bar strip, clear of the player list and of the cash pill; when there is no room there, in a
-- row under Roblox's top-left buttons instead.
function ScreenLayout.cornerRow(device: Device, widths: { number }): ({ Rect }, boolean)
	local C = ScreenLayout.SIZE.corner
	local total = 0
	for index, w in widths do
		total += w + (if index > 1 then C.gap else 0)
	end
	local right = math.min(device.width - device.playerList, device.topBarRight) - ScreenLayout.EDGE
	local cashRight = device.width / 2 + ScreenLayout.SIZE.cash.w / 2 + ScreenLayout.EDGE
	local moved = right - total < math.max(cashRight, device.topBarLeft + ScreenLayout.EDGE)
	local rects: { Rect } = {}
	local x = if moved then ScreenLayout.SIZE.side.left else right - total
	local y = if moved then device.topBar + C.top else C.top
	for _, w in widths do
		table.insert(rects, rect(x, y, w, C.button))
		x += w + C.gap
	end
	return rects, moved and #widths > 0
end

-- The 2x2 grid of feature buttons (Shop, Rebirth, Rewards, Snackdex): under Roblox's top-left buttons (and under the
-- corner row when it moved there), so the bottom-left stays the thumbstick's.
function ScreenLayout.sideGrid(device: Device, count: number, cornerMoved: boolean): Rect
	local S = ScreenLayout.SIZE.side
	local top = device.topBar + ScreenLayout.SIZE.corner.top
	if cornerMoved then
		top += ScreenLayout.SIZE.corner.button + S.gap
	end
	local rows = math.max(1, math.ceil(count / S.columns))
	local columns = math.min(S.columns, math.max(1, count))
	return rect(S.left, top, columns * S.w + (columns - 1) * S.gap, rows * S.h + (rows - 1) * S.gap)
end

-- Button `index` (1 Shop, 2 Rebirth, 3 Rewards, 4 Snackdex) in the grid.
function ScreenLayout.sideCell(grid: Rect, index: number): Rect
	local S = ScreenLayout.SIZE.side
	local column = (index - 1) % S.columns
	local row = (index - 1) // S.columns
	return rect(grid.x + column * (S.w + S.gap), grid.y + row * (S.h + S.gap), S.w, S.h)
end

-- The TAG! button: where it always was (right side, above the jump button), lower when Roblox's player list would
-- cover it, and never on the jump button.
function ScreenLayout.tagButton(device: Device): Rect
	local T = ScreenLayout.SIZE.tag
	local x = device.width - T.right - T.pad - T.size
	local lowest = device.height - T.right - T.pad
	local jump = ScreenLayout.jumpButton(device)
	if jump then
		lowest = jump.y - ScreenLayout.GAP
	end
	local bottom = math.min(device.height - T.bottom, lowest)
	local list = ScreenLayout.playerListRect(device)
	if list and x + T.size > list.x and bottom - T.size < list.y + list.h + ScreenLayout.GAP then
		bottom = math.min(lowest, list.y + list.h + ScreenLayout.GAP + T.size)
	end
	return rect(x, bottom - T.size, T.size, T.size)
end

-- The frame around the TAG button (the action area other controllers may add to).
function ScreenLayout.actionArea(device: Device): Rect
	local tag = ScreenLayout.tagButton(device)
	local pad = ScreenLayout.SIZE.tag.pad
	return rect(tag.x - pad, tag.y - pad, tag.w + 2 * pad, tag.h + 2 * pad)
end

-- The map vote strip at the bottom: between the thumbstick's area and the jump button on touch screens, centred
-- otherwise: a header line over one button per map.
function ScreenLayout.voteStrip(device: Device): Rect
	local V = ScreenLayout.SIZE.vote
	local h = V.header + V.gap + V.choice
	local thumb = ScreenLayout.thumbstickArea(device)
	local jump = ScreenLayout.jumpButton(device)
	local x0, x1 = ScreenLayout.EDGE, device.width - ScreenLayout.EDGE
	if thumb then
		x0 = math.max(x0, thumb.x + thumb.w + V.thumbGap)
	end
	if jump then
		x1 = math.min(x1, jump.x - V.jumpGap)
	end
	local centre = if thumb or jump then (x0 + x1) / 2 else device.width / 2
	local w = math.min(V.maxW, x1 - x0)
	return rect(centre - w / 2, device.height - ScreenLayout.EDGE - h, w, h)
end

-- One of `count` vote buttons in the strip (the client splits the strip the same way, with scale sizes).
function ScreenLayout.voteChoice(strip: Rect, index: number, count: number): Rect
	local V = ScreenLayout.SIZE.vote
	local w = (strip.w - V.choiceGap * (count - 1)) / math.max(1, count)
	return rect(strip.x + (index - 1) * (w + V.choiceGap), strip.y + V.header + V.gap, w, V.choice)
end

-- The toast list: centred, its bottom `toast.bottom` above the screen's (over the vote strip); the newest on top.
function ScreenLayout.toastList(device: Device): Rect
	local T = ScreenLayout.SIZE.toast
	local h = T.max * T.tall + (T.max - 1) * T.gap
	return rect(device.width / 2 - T.w / 2, device.height - T.bottom - h, T.w, h)
end

-- How tall a toast showing `text` is: one line when that line is big enough to read (TEXT.toast.oneLine), else two
-- wrapped lines (the tall toast).
function ScreenLayout.toastHeight(text: string): number
	local T, P = ScreenLayout.SIZE.toast, ScreenLayout.TEXT.toast
	local oneLine = TextFit.fit(text, T.w - 2 * P.padX, T.h - 2 * P.padY, false)
	return if oneLine >= P.oneLine then T.h else T.tall
end

-- The HUD in one state ------------------------------------------------------------------------------------------------

export type HudState = {
	tutorial: string?, -- "full" (with its tip) or "compact" while the banner shows
	cashOffer: boolean?,
	event: boolean?,
	modifier: boolean?,
	luck: boolean?,
	vote: boolean?,
	carrying: boolean?,
	friends: boolean?,
	tag: boolean?,
	toasts: number?,
	announcement: boolean?,
	titleCard: boolean?,
	stealAlert: boolean?,
}

-- kind: "button" (tappable), "info" (a HUD pill), "overlay" (above the HUD for a few seconds, never tappable), "core"
-- (Roblox's own UI), "zone" (the play zone). `parent`: the element this one sits inside.
export type Element = { id: string, kind: string, rect: Rect, parent: string? }

export type Layout = {
	elements: { Element },
	byId: { [string]: Rect },
	stackBottom: number, -- UI y where the top stack ends
	cornerMoved: boolean,
	statusShown: boolean, -- the status pills show (the band isn't the tutorial's or a cash offer's)
	obstacles: { Rect }, -- what centred overlays stay clear of (buttons and Roblox's UI)
	centerX: number,
}

-- The stack's centre: the screen's, moved right if the cash pill would reach Roblox's top-left buttons, and never into
-- the corner row.
function ScreenLayout.stackCenter(device: Device, cornerLeft: number?): number
	local half = ScreenLayout.SIZE.cash.w / 2 + ScreenLayout.EDGE
	local cx = math.max(device.width / 2, device.topBarLeft + half)
	if cornerLeft then
		cx = math.min(cx, cornerLeft - half)
	end
	return cx
end

-- Where the band under the cash pill starts: below the pill, and below Roblox's top bar (its buttons are in the strip).
function ScreenLayout.bandTop(device: Device): number
	local S = ScreenLayout.SIZE
	return math.max(S.stackTop + S.cash.h + S.stackGap, device.topBar)
end

-- Status pills in rows: each row as wide as fits the lane, centred, items vertically centred in their row.
local function flow(
	device: Device,
	items: { { id: string, kind: string, w: number, h: number } },
	top: number,
	cx: number,
	obstacles: { Rect },
	add: (id: string, kind: string, r: Rect) -> ()
): number
	local y = top
	local index = 1
	while index <= #items do
		-- The lane for a row as tall as the tallest item.
		local rowH = 0
		for i = index, #items do
			rowH = math.max(rowH, items[i].h)
		end
		local left, right = ScreenLayout.lane(device, obstacles, y, y + rowH, cx)
		local width = items[index].w
		local last = index
		while last < #items and width + ScreenLayout.GAP + items[last + 1].w <= right - left do
			last += 1
			width += ScreenLayout.GAP + items[last].w
		end
		local height = 0
		for i = index, last do
			height = math.max(height, items[i].h)
		end
		local x = ScreenLayout.fitSpan(cx, width, width, left, right)
		for i = index, last do
			local item = items[i]
			add(item.id, item.kind, rect(x, y + (height - item.h) / 2, item.w, item.h))
			x += item.w + ScreenLayout.GAP
		end
		y += height + ScreenLayout.SIZE.stackGap
		index = last + 1
	end
	return y
end

-- Everything on screen in `state` on `device` (UI units, HUD coordinates). Run it on ScreenLayout.tutorialDevice(device)
-- while the tutorial runs: its banner switches the player list off when it can't clear it.
function ScreenLayout.layout(device: Device, state: HudState): Layout
	local S = ScreenLayout.SIZE
	local elements: { Element } = {}
	local byId: { [string]: Rect } = {}
	local function add(id: string, kind: string, r: Rect, parent: string?)
		table.insert(elements, { id = id, kind = kind, rect = r, parent = parent })
		byId[id] = r
	end

	-- Roblox's UI and the play zone.
	local obstacles: { Rect } = {}
	local robloxButtons = ScreenLayout.topBarButtons(device)
	add("robloxTopBar", "core", robloxButtons)
	table.insert(obstacles, robloxButtons)
	local playerList = ScreenLayout.playerListRect(device)
	if playerList then
		add("playerList", "core", playerList)
		table.insert(obstacles, playerList)
	end
	local thumb = ScreenLayout.thumbstickArea(device)
	if thumb then
		add("thumbstick", "core", thumb)
	end
	local jump = ScreenLayout.jumpButton(device)
	if jump then
		add("jump", "core", jump)
		table.insert(obstacles, jump)
	end
	add("playZone", "zone", ScreenLayout.playZone(device))

	-- The corner row and the feature buttons.
	local widths = { S.corner.lock }
	local ids = { "lock" }
	if state.friends then
		table.insert(widths, S.corner.button)
		table.insert(ids, "friends")
	end
	table.insert(widths, S.corner.button)
	table.insert(ids, "gear")
	local corner, moved = ScreenLayout.cornerRow(device, widths)
	for index, r in corner do
		add(ids[index], "button", r)
		table.insert(obstacles, r)
	end
	local grid = ScreenLayout.sideGrid(device, 4, moved)
	table.insert(obstacles, grid)
	for index, id in { "shop", "rebirth", "rewards", "snackdex" } do
		add(id, "button", ScreenLayout.sideCell(grid, index))
	end
	local action = ScreenLayout.actionArea(device)
	table.insert(obstacles, action)
	if state.tag then
		add("tag", "button", ScreenLayout.tagButton(device))
	end

	-- The top stack: the cash pill, then the band.
	local cx = ScreenLayout.stackCenter(device, if moved then nil else corner[1].x)
	add("cash", "info", rect(cx - S.cash.w / 2, S.stackTop, S.cash.w, S.cash.h))
	local y = ScreenLayout.bandTop(device)
	local statusShown = false
	if state.tutorial then
		local h = S.tutorial.h + (if state.tutorial == "full" then S.tutorial.tip else 0)
		-- Centred under the cash; ScreenLayout.tutorialDevice switches the player list off when it needs the room.
		local left, right = ScreenLayout.lane(device, obstacles, y, y + h, cx)
		local x, w = ScreenLayout.fitSpan(cx, S.tutorial.w, S.tutorial.minW, left, right, true)
		add("tutorial", "info", rect(x, y, w, h))
		add(
			"skip",
			"button",
			rect(x + w - S.skip.inset - S.skip.w, y + (S.tutorial.h - S.skip.h) / 2, S.skip.w, S.skip.h),
			"tutorial"
		)
		y += h + S.stackGap
	elseif state.cashOffer then
		local O = S.cashOffer
		local left, right = ScreenLayout.lane(device, obstacles, y, y + O.h, cx)
		local x, w = ScreenLayout.fitSpan(cx, O.w, O.minW, left, right)
		add("cashOffer", "info", rect(x, y, w, O.h))
		local closeX = x + w - O.inset - O.close
		local buttonH = O.h - 2 * O.inset
		add("cashOfferClose", "button", rect(closeX, y + O.inset, O.close, buttonH), "cashOffer")
		add("cashOfferBuy", "button", rect(closeX - ScreenLayout.GAP - O.buy, y + O.inset, O.buy, buttonH), "cashOffer")
		y += O.h + S.stackGap
	else
		-- The status pills, most lasting first: the event, the modifier (a button), luck.
		local items = {}
		if state.event then
			table.insert(items, { id = "event", kind = "info", w = S.event.w, h = S.event.h })
		end
		if state.modifier then
			table.insert(items, { id = "modifier", kind = "button", w = S.modifier.w, h = S.modifier.h })
		end
		if state.luck then
			table.insert(items, { id = "luck", kind = "info", w = S.luck.w, h = S.luck.h })
		end
		statusShown = true
		y = flow(device, items, y, cx, obstacles, add)
	end
	local stackBottom = y - S.stackGap

	-- The bottom of the screen.
	if state.vote then
		local strip = ScreenLayout.voteStrip(device)
		add("voteHeader", "info", rect(strip.x, strip.y, strip.w, S.vote.header))
		for index = 1, 3 do
			add("vote" .. index, "button", ScreenLayout.voteChoice(strip, index, 3))
		end
	end
	if state.carrying then
		local carryX = device.width / 2 - S.carry.w / 2 -- centred on the screen (StealController anchors it there)
		add("carry", "overlay", rect(carryX, device.height - S.carry.bottom - S.carry.h, S.carry.w, S.carry.h))
	end

	-- What drops in over the HUD for a few seconds: below the stack, clear of the buttons beside it.
	local function overlay(id: string, w: number, h: number, top: number)
		local left, right = ScreenLayout.lane(device, obstacles, top, top + h, cx)
		local x, width = ScreenLayout.fitSpan(cx, w, 0, left, right)
		add(id, "overlay", rect(x, top, width, h))
	end
	local overlayTop = stackBottom + ScreenLayout.GAP
	if state.announcement then
		overlay("announcement", S.banner.w, S.banner.h, overlayTop)
	end
	if state.titleCard then
		overlay("titleCard", S.titleCard.w, S.titleCard.h, overlayTop)
	end
	if state.stealAlert then
		overlay("stealAlert", S.stealAlert.w, S.stealAlert.h, ScreenLayout.stealAlertTop(stackBottom))
	end
	local toasts = state.toasts or 0
	if toasts > 0 then
		local area = ScreenLayout.toastList(device)
		local bottom = area.y + area.h
		for index = 1, math.min(toasts, S.toast.max) do
			add("toast" .. index, "overlay", rect(area.x, bottom - S.toast.tall, S.toast.w, S.toast.tall))
			bottom -= S.toast.tall + S.toast.gap
		end
	end
	return {
		elements = elements,
		byId = byId,
		stackBottom = stackBottom,
		cornerMoved = moved,
		statusShown = statusShown,
		obstacles = obstacles,
		centerX = cx,
	}
end

-- The steal alert's top: its usual height, or under an announcement banner below a tall stack.
function ScreenLayout.stealAlertTop(stackBottom: number): number
	return math.max(ScreenLayout.SIZE.stealAlert.y, stackBottom + 2 * ScreenLayout.GAP + ScreenLayout.SIZE.banner.h)
end

-- Where a centred overlay `w` x `h` goes at `top` (announcement banners, the map title card...): x and width.
function ScreenLayout.overlaySpan(device: Device, layout: Layout, w: number, h: number, top: number): (number, number)
	local left, right = ScreenLayout.lane(device, layout.obstacles, top, top + h, layout.centerX)
	return ScreenLayout.fitSpan(layout.centerX, w, 0, left, right)
end

-- The device as the tutorial leaves it: the player list switched off while the banner, centred under the cash and
-- at least `tutorial.minW` wide, would run under it (TutorialController does the same).
function ScreenLayout.tutorialDevice(device: Device): Device
	if device.playerList <= 0 then
		return device
	end
	local probe = ScreenLayout.layout(device, { tutorial = "full" })
	local banner = probe.byId.tutorial
	local list = ScreenLayout.playerListRect(device)
	if banner and list and ScreenLayout.overlaps(banner, list) then
		return ScreenLayout.withoutPlayerList(device)
	end
	return device
end

-- The check -------------------------------------------------------------------------------------------------------------

local function describe(e: Element): string
	local r = e.rect
	return string.format("%s (x %.0f-%.0f, y %.0f-%.0f)", e.id, r.x, r.x + r.w, r.y, r.y + r.h)
end

-- What is wrong with a layout (empty when nothing):
--   * every HUD element inside the safe area
--   * no two HUD elements overlap (a button may sit inside its own pill); overlays may cover pills but no button
--   * no button in the play zone, on Roblox's top-bar buttons, the player list, the jump button or where the thumbstick
--     starts; no HUD pill under Roblox's top-bar buttons or the player list
--   * on touch screens every button is at least MIN_TOUCH px both ways
function ScreenLayout.problems(device: Device, elements: { Element }): { string }
	local problems: { string } = {}
	local function report(text: string)
		table.insert(problems, `{device.name}: {text}`)
	end
	local hud: { Element } = {}
	local core: { Element } = {}
	local zone: Element? = nil
	for _, e in elements do
		if e.kind == "core" then
			table.insert(core, e)
		elseif e.kind == "zone" then
			zone = e
		else
			table.insert(hud, e)
		end
	end
	local tolerance = 0.5
	for _, e in hud do
		local r = e.rect
		if
			r.x < -tolerance
			or r.y < -tolerance
			or r.x + r.w > device.width + tolerance
			or r.y + r.h > device.height + tolerance
		then
			report(`{describe(e)} is off screen ({string.format("%.0f x %.0f", device.width, device.height)})`)
		end
		if e.kind == "button" then
			if device.touch then
				local px = math.min(r.w, r.h) * device.scale
				if px < ScreenLayout.MIN_TOUCH - 0.01 then
					report(`{describe(e)} is a {string.format("%.1f", px)} px touch target`)
				end
			end
			if zone and ScreenLayout.overlaps(r, zone.rect) then
				report(`{describe(e)} is in the play zone {describe(zone)}`)
			end
		end
		if e.kind ~= "overlay" then
			for _, c in core do
				if (e.kind == "button" or c.id ~= "thumbstick") and ScreenLayout.overlaps(r, c.rect, tolerance) then
					report(`{describe(e)} is under Roblox's {describe(c)}`)
				end
			end
		end
	end
	for i = 1, #hud do
		for j = i + 1, #hud do
			local a, b = hud[i], hud[j]
			if a.parent == b.id or b.parent == a.id or not ScreenLayout.overlaps(a.rect, b.rect) then
				continue
			end
			local overlay = a.kind == "overlay" or b.kind == "overlay"
			local button = a.kind == "button" or b.kind == "button"
			if not overlay or button then
				report(`{describe(a)} overlaps {describe(b)}`)
			end
		end
	end
	return problems
end

-- The screens and the busiest states the HUD is checked in (tests/ScreenLayout.spec.luau, tools/layoutCheck.luau).
ScreenLayout.DEVICES = table.freeze({
	{ name = "640x360 phone", widthPx = 640, heightPx = 360, touch = true },
	{ name = "667x375 phone", widthPx = 667, heightPx = 375, touch = true },
	-- iPhone 12-15 in landscape: the notch and the home indicator take 47 px each side and 21 at the bottom
	{
		name = "844x390 phone",
		widthPx = 844,
		heightPx = 390,
		touch = true,
		insetLeftPx = 47,
		insetRightPx = 47,
		insetBottomPx = 21,
	},
	-- a tablet keeps Roblox's player list on screen (two leaderstats)
	{ name = "1024x768 tablet", widthPx = 1024, heightPx = 768, touch = true, playerListPx = 358 },
	{ name = "1280x720 window", widthPx = 1280, heightPx = 720, touch = false, playerListPx = 358 },
} :: { DeviceSpec })

export type Scenario = { name: string, state: HudState }

-- Toasts, banners and alerts are transient, so the worst cases put them all on screen together. Never at once (by the
-- game's own rules): the vote and a cash offer during the tutorial, the vote while carrying (it hides), a cash offer
-- while carrying (buying is refused), the Friends button during the tutorial.
ScreenLayout.SCENARIOS = table.freeze({
	{
		name = "everything at once",
		state = {
			event = true,
			modifier = true,
			luck = true,
			vote = true,
			friends = true,
			tag = true,
			toasts = 3,
			announcement = true,
			stealAlert = true,
		},
	},
	{
		name = "a cash offer during a vote",
		state = {
			cashOffer = true,
			event = true,
			modifier = true,
			luck = true,
			vote = true,
			friends = true,
			tag = true,
			toasts = 3,
			announcement = true,
			stealAlert = true,
		},
	},
	{
		name = "carrying a Snackling home",
		state = {
			event = true,
			modifier = true,
			luck = true,
			carrying = true,
			friends = true,
			tag = true,
			toasts = 3,
			announcement = true,
			stealAlert = true,
		},
	},
	{
		name = "the tutorial with its tip",
		state = {
			tutorial = "full",
			event = true,
			modifier = true,
			luck = true,
			tag = true,
			toasts = 3,
			announcement = true,
			stealAlert = true,
		},
	},
	{
		name = "the tutorial while carrying",
		state = {
			tutorial = "compact",
			event = true,
			modifier = true,
			luck = true,
			carrying = true,
			tag = true,
			toasts = 3,
			announcement = true,
		},
	},
	{
		name = "a new map",
		state = { event = true, modifier = true, friends = true, tag = true, toasts = 3, titleCard = true },
	},
	{ name = "a quiet moment", state = { friends = true } },
} :: { Scenario })

-- The device a scenario runs on (the tutorial may switch the player list off).
function ScreenLayout.scenarioDevice(spec: DeviceSpec, scenario: Scenario): Device
	local device = ScreenLayout.device(spec)
	return if scenario.state.tutorial then ScreenLayout.tutorialDevice(device) else device
end

-- Every problem on every screen in every scenario.
function ScreenLayout.checkAll(): { string }
	local all: { string } = {}
	for _, spec in ScreenLayout.DEVICES do
		for _, scenario in ScreenLayout.SCENARIOS do
			local device = ScreenLayout.scenarioDevice(spec, scenario)
			for _, problem in ScreenLayout.problems(device, ScreenLayout.layout(device, scenario.state).elements) do
				table.insert(all, `{problem} [{scenario.name}]`)
			end
		end
	end
	return all
end

return ScreenLayout
