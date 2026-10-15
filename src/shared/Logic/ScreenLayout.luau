--!strict
--[[
	Where every HUD element goes, and the check that keeps them out of each other's way (DECISIONS.md #23, #26, #44).
	Pure: no Roblox APIs. The client passes in the device facts and places its frames with these functions; tests and
	tools/layoutCheck.luau run the same functions for the phones, tablets and windows the game targets, in the busiest
	states, and fail on any overlap.

	Units: UI units (reference px; UiKit scales them by ScreenLayout.scaleFor) in HUD coordinates, whose origin is the
	top-left of the device's safe area (the HUD ScreenGui uses DeviceSafeInsets, so it starts at the top of the screen,
	under Roblox's 58 px top bar, not below it). Rects are { x, y, w, h }.

	The HUD, laid out for thumbs on a landscape phone (667x375 at UI scale 0.85 = 785x441 UI):

	  top centre    the top stack: cash, then the tutorial banner or the "Need $X more?" strip, cash/sec, and the
	                status row (event pill beside a column of luck / modifier chips, wrapping onto two rows when the
	                screen is narrow). Only Skip and the offer's buttons are tappable, and they end above the play zone.
	  top right     the corner row: lock button, 👥 Friends, ⚙ settings, in Roblox's top bar strip (its free part), or
	                under Roblox's own top-left buttons when the player list leaves no room right of the cash
	  top left      four feature buttons in a 2x2 grid under Roblox's top-left buttons, clear of the thumbstick
	  right         the TAG! button (action area), above the jump button and below the player list
	  bottom centre the map vote, between the thumbstick area and the jump button; toasts above it
	  middle        the play zone (the character and the prompts near it): nothing tappable
]]

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

-- Roblox's own UI, in screen pixels (the PlayerModule touch controls are copied from its TouchJump and
-- DynamicThumbstick code; the player list's size is an estimate, Roblox does not expose it).
ScreenLayout.ROBLOX = table.freeze({
	topBar = 58, -- the top bar (GuiService:GetGuiInset): the touch controls and the player list start below it
	topBarLeft = 210, -- its buttons on the left (menu, chat, more) end about here (GuiService.TopbarInset.Min.X)
	-- Touch controls (TouchGui, below the top bar): the dynamic thumbstick starts from the left 40% of the screen
	-- in its lower two thirds; the jump button is 70 px (120 when the short side is over 500) in the bottom right.
	thumbstickWidthShare = 0.4,
	thumbstickTopShare = 1 / 3,
	jumpSmall = 70,
	jumpBig = 120,
	jumpSmallBelow = 500,
})

-- Estimated width of Roblox's player list in pixels: the names column plus one column per leaderstat, and the gap to
-- the screen edge; its height is a header and one row per player (a full server of 8). It errs on the large side.
ScreenLayout.PLAYER_LIST = table.freeze({ base = 190, perStat = 80, max = 480, margin = 8, header = 40, row = 36 })

-- The player-facing play zone: the middle third of the screen, from 30% to 70% of its height. With Roblox's default
-- camera the character's head is at 50% and prompts near it are centred at 39-55% (147-207 of 375 px), each 72 px
-- tall, so their tops reach 30%; the feet are at 70-73%. Nothing tappable goes there.
ScreenLayout.PLAY_ZONE = table.freeze({ left = 1 / 3, right = 2 / 3, top = 0.3, bottom = 0.7 })

ScreenLayout.MIN_TOUCH = 44 -- px, on touch screens
ScreenLayout.EDGE = 8 -- UI units between an element and the screen edge or Roblox's UI

-- Sizes and gaps in UI units, shared by the controllers that build these elements and by the check below.
ScreenLayout.SIZE = table.freeze({
	stackTop = 6,
	stackGap = 4,
	cash = { w = 250, h = 58 },
	income = { w = 250, h = 26 },
	stackHalfWidth = 125, -- the widest thing in the top strip (the cash pill) is 250
	tutorial = { w = 420, h = 64, tip = 24, minW = 300, gap = 6 }, -- gap: from the TAG area / player list
	skip = { w = 60, h = 52, inset = 8 }, -- the tutorial's Skip, in the banner's top 64 (inset from its right edge)
	-- buttons 52 tall, inset from the strip's edges; narrowed down to minW where Roblox's player list leaves less room
	cashOffer = { w = 400, minW = 330, h = 60, inset = 4, buy = 116, close = 52 },
	eventPill = { w = 220, h = 64 },
	chip = { w = 165, h = 30, gap = 4 },
	statusGap = 6, -- between the event pill and the chips, and between the two rows when they wrap
	corner = { button = 52, lock = 104, gap = 8, top = 4 },
	side = { w = 76, h = 52, gap = 6, columns = 2, left = 10 },
	tag = { size = 120, pad = 15, right = 24, bottom = 185, gap = 6 }, -- right / bottom: from the HUD's edges
	vote = { header = 20, gap = 4, choice = 68, choiceGap = 6, maxW = 420, thumbGap = 8, jumpGap = 16 },
	toast = { w = 340, h = 40, tall = 56, gap = 6, max = 3, bottom = 110 },
	banner = { w = 560, h = 64 }, -- announcement banner (narrowed by overlayWidth)
	titleCard = { w = 400, h = 120 }, -- the new map's title card
	stealAlert = { w = 420, h = 52, y = 230 },
	carry = { w = 320, h = 46, bottom = 60 },
	overlayGap = 6, -- banners and title cards drop in this far under the top stack
})

export type DeviceSpec = {
	name: string,
	widthPx: number,
	heightPx: number,
	touch: boolean, -- Roblox's touch controls show (thumbstick + jump)
	insetLeftPx: number?, -- device safe-area insets (notch, home indicator)
	insetRightPx: number?,
	insetBottomPx: number?,
	playerListPx: number?, -- width the player list takes from the right edge (ScreenLayout.playerListWidth), 0 = none
	players: number?, -- rows in the player list (default 8)
	topBarPx: number?, -- Roblox's top bar height (default ROBLOX.topBar)
	topBarLeftPx: number?, -- where its left buttons end (default ROBLOX.topBarLeft)
}

export type Device = {
	name: string,
	widthPx: number,
	heightPx: number,
	touch: boolean,
	scale: number,
	left: number, -- px from the screen's left edge to the HUD's
	insetRightPx: number,
	insetBottomPx: number,
	width: number, -- the HUD area (the safe area), UI units
	height: number,
	topBar: number, -- UI y where Roblox's top bar ends
	topBarLeft: number, -- UI x where its left buttons end
	playerList: number, -- UI width the player list takes from the right (0 = none)
	playerListBottom: number, -- UI y of its bottom (0 = none)
}

function ScreenLayout.device(spec: DeviceSpec): Device
	local scale = ScreenLayout.scaleFor(spec.widthPx, spec.heightPx)
	local left = spec.insetLeftPx or 0
	local right = spec.insetRightPx or 0
	local bottom = spec.insetBottomPx or 0
	local topBarPx = spec.topBarPx or ScreenLayout.ROBLOX.topBar
	local listPx = spec.playerListPx or 0
	local rows = spec.players or 8
	local listBottomPx = if listPx > 0
		then topBarPx + ScreenLayout.PLAYER_LIST.header + rows * ScreenLayout.PLAYER_LIST.row
		else 0
	return {
		name = spec.name,
		widthPx = spec.widthPx,
		heightPx = spec.heightPx,
		touch = spec.touch,
		scale = scale,
		left = left,
		insetRightPx = right,
		insetBottomPx = bottom,
		width = (spec.widthPx - left - right) / scale,
		height = (spec.heightPx - bottom) / scale,
		topBar = topBarPx / scale,
		topBarLeft = (spec.topBarLeftPx or ScreenLayout.ROBLOX.topBarLeft) / scale,
		playerList = listPx / scale,
		playerListBottom = listBottomPx / scale,
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
	return (xPx - device.left) / device.scale, yPx / device.scale
end

function ScreenLayout.toPx(device: Device, r: Rect): Rect
	return rect(device.left + r.x * device.scale, r.y * device.scale, r.w * device.scale, r.h * device.scale)
end

-- Roblox's UI --------------------------------------------------------------------------------------------------------

-- Roblox's buttons at the top left of the top bar.
function ScreenLayout.topBarButtons(device: Device): Rect
	return rect(-device.left / device.scale, 0, device.topBarLeft + device.left / device.scale, device.topBar)
end

function ScreenLayout.playerListRect(device: Device): Rect?
	if device.playerList <= 0 then
		return nil
	end
	return rect(device.width - device.playerList, device.topBar, device.playerList, device.playerListBottom - device.topBar)
end

-- The touch controls' screen (TouchGui): the safe area below the top bar, in px.
local function touchArea(device: Device): (number, number, number, number)
	local topPx = device.topBar * device.scale
	return device.left, topPx, device.widthPx - device.left - device.insetRightPx, device.heightPx - device.insetBottomPx - topPx
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
	local small = math.min(aw, ah) <= R.jumpSmallBelow
	local size = if small then R.jumpSmall else R.jumpBig
	local xPx = ax + aw - (size * 1.5 - 10)
	local yPx = if small then ay + ah - size - 20 else ay + ah - size * 1.75
	local x, y = fromPx(device, xPx, yPx)
	return rect(x, y, size / device.scale, size / device.scale)
end

-- The play zone in HUD units.
function ScreenLayout.playZone(device: Device): Rect
	local Z = ScreenLayout.PLAY_ZONE
	local x0, y0 = fromPx(device, device.widthPx * Z.left, device.heightPx * Z.top)
	local x1, y1 = fromPx(device, device.widthPx * Z.right, device.heightPx * Z.bottom)
	return rect(x0, y0, x1 - x0, y1 - y0)
end

-- Placement ---------------------------------------------------------------------------------------------------------

-- The corner row's buttons (widths left to right; the lock, Friends and the gear), as rects in the same order, and
-- whether they had to leave the top-right corner: right-aligned in the top bar strip, left of the player list and
-- clear of the cash pill; when that leaves no room, in a row under Roblox's top-left buttons instead.
function ScreenLayout.cornerRow(device: Device, widths: { number }): ({ Rect }, boolean)
	local C = ScreenLayout.SIZE.corner
	local total = 0
	for index, w in widths do
		total += w + (if index > 1 then C.gap else 0)
	end
	local rightLimit = device.width - ScreenLayout.EDGE - device.playerList
	local leftLimit = device.width / 2 + ScreenLayout.SIZE.stackHalfWidth + ScreenLayout.EDGE
	local overflow = rightLimit - total < leftLimit
	local rects: { Rect } = {}
	local x = if overflow then ScreenLayout.SIZE.side.left else rightLimit - total
	local y = if overflow then device.topBar + C.top else C.top
	for _, w in widths do
		table.insert(rects, rect(x, y, w, C.button))
		x += w + C.gap
	end
	return rects, overflow and #widths > 0
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

function ScreenLayout.sideCell(grid: Rect, index: number): Rect
	local S = ScreenLayout.SIZE.side
	local column = (index - 1) % S.columns
	local row = (index - 1) // S.columns
	return rect(grid.x + column * (S.w + S.gap), grid.y + row * (S.h + S.gap), S.w, S.h)
end

-- The TAG! button: where it always was on phones (above the jump button, right side), lower when Roblox's player list
-- would cover it, and never on the jump button. Returns the button's rect; the action area frame is `pad` bigger.
function ScreenLayout.tagButton(device: Device): Rect
	local T = ScreenLayout.SIZE.tag
	local x = device.width - T.right - T.pad - T.size
	local bottom = device.height - T.bottom
	local lowest = device.height - T.right - T.pad -- non-touch: down to the bottom-right corner
	local jump = ScreenLayout.jumpButton(device)
	if jump then
		lowest = jump.y - T.gap
		bottom = math.min(bottom, lowest)
	end
	local list = ScreenLayout.playerListRect(device)
	if list and x + T.size > list.x and bottom - T.size < list.y + list.h + T.gap then
		bottom = math.min(lowest, list.y + list.h + T.gap + T.size)
	end
	return rect(x, bottom - T.size, T.size, T.size)
end

function ScreenLayout.actionArea(device: Device): Rect
	local tag = ScreenLayout.tagButton(device)
	local pad = ScreenLayout.SIZE.tag.pad
	return rect(tag.x - pad, tag.y - pad, tag.w + 2 * pad, tag.h + 2 * pad)
end

-- The "Need $X more?" strip under the cash: centred, or shifted and narrowed (never below `cashOffer.minW`) to stay
-- clear of the corner row and feature buttons on the left and of the TAG area and the player list on the right.
-- Returns its x and width.
function ScreenLayout.cashOfferPlacement(device: Device, cornerMoved: boolean, cornerRight: number): (number, number)
	local O = ScreenLayout.SIZE.cashOffer
	local grid = ScreenLayout.sideGrid(device, 4, cornerMoved)
	local gap = ScreenLayout.SIZE.overlayGap
	local leftLimit = grid.x + grid.w + gap
	if cornerMoved then
		leftLimit = math.max(leftLimit, cornerRight + gap)
	end
	local rightLimit = math.min(ScreenLayout.actionArea(device).x, device.width - device.playerList) - gap
	local w = math.max(O.minW, math.min(O.w, rightLimit - leftLimit))
	local x = math.clamp(device.width / 2 - w / 2, leftLimit, math.max(leftLimit, rightLimit - w))
	return x, w
end

-- How wide something centred on `centerX` may be to stay clear of the feature buttons on the left, and of the TAG
-- area and the player list on the right: `preferred`, or less.
function ScreenLayout.centredWidth(device: Device, centerX: number, preferred: number, cornerMoved: boolean): number
	local grid = ScreenLayout.sideGrid(device, 4, cornerMoved)
	local leftLimit = grid.x + grid.w + ScreenLayout.SIZE.overlayGap
	local rightLimit = math.min(ScreenLayout.actionArea(device).x, device.width - device.playerList)
		- ScreenLayout.SIZE.overlayGap
	local half = math.min(centerX - leftLimit, rightLimit - centerX)
	return math.max(0, math.min(preferred, 2 * half))
end

-- Whether the status row's event pill and chips fit side by side, else they wrap onto two rows (UIListLayout.Wraps).
function ScreenLayout.statusRowWidth(device: Device, cornerMoved: boolean): number
	return ScreenLayout.centredWidth(device, device.width / 2, math.huge, cornerMoved)
end

-- The map vote strip at the bottom: between the thumbstick's area and the jump button on touch screens, centred
-- otherwise; header line, then one button per map.
function ScreenLayout.voteStrip(device: Device): Rect
	local V = ScreenLayout.SIZE.vote
	local h = V.header + V.gap + V.choice
	local y = device.height - ScreenLayout.EDGE - h
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
	return rect(centre - w / 2, y, w, h)
end

-- One of `count` vote buttons in the strip.
function ScreenLayout.voteChoice(strip: Rect, index: number, count: number): Rect
	local V = ScreenLayout.SIZE.vote
	local w = (strip.w - V.choiceGap * (count - 1)) / math.max(1, count)
	return rect(strip.x + (index - 1) * (w + V.choiceGap), strip.y + V.header + V.gap, w, V.choice)
end

-- The toast list: centred, its bottom `toast.bottom` above the screen's (over the vote strip); newest at the bottom.
function ScreenLayout.toastList(device: Device): Rect
	local T = ScreenLayout.SIZE.toast
	local h = T.max * T.tall + (T.max - 1) * T.gap
	return rect(device.width / 2 - T.w / 2, device.height - T.bottom - h, T.w, h)
end

-- The HUD in one state ------------------------------------------------------------------------------------------------

export type HudState = {
	tutorial: string?, -- "full" (with its tip), "compact", or nil
	cashOffer: boolean?,
	event: boolean?,
	luck: boolean?,
	modifier: boolean?,
	vote: boolean?,
	carrying: boolean?,
	toasts: number?,
	announcement: boolean?,
	titleCard: boolean?,
	stealAlert: boolean?,
	tag: boolean?,
	friends: boolean?,
}

-- kind: "button" (tappable), "info" (a HUD pill), "overlay" (drawn above the HUD for a few seconds), "core" (Roblox's
-- own UI), "zone" (the play zone). `parent`: the element this one sits inside (its own pill).
export type Element = { id: string, kind: string, rect: Rect, parent: string? }

-- Everything on screen in `state` on `device` (UI units, HUD coordinates). The tutorial banner switches the player
-- list off when it can't clear it (TutorialController), so `device` should already reflect that
-- (ScreenLayout.tutorialDevice).
function ScreenLayout.hud(device: Device, state: HudState): { Element }
	local S = ScreenLayout.SIZE
	local list: { Element } = {}
	local function add(id: string, kind: string, r: Rect, parent: string?)
		table.insert(list, { id = id, kind = kind, rect = r, parent = parent })
	end

	-- Roblox's UI and the play zone.
	add("robloxTopBar", "core", ScreenLayout.topBarButtons(device))
	local playerList = ScreenLayout.playerListRect(device)
	if playerList then
		add("playerList", "core", playerList)
	end
	local thumb = ScreenLayout.thumbstickArea(device)
	if thumb then
		add("thumbstick", "core", thumb)
	end
	local jump = ScreenLayout.jumpButton(device)
	if jump then
		add("jump", "core", jump)
	end
	add("playZone", "zone", ScreenLayout.playZone(device))

	-- Corner row and feature buttons.
	local widths = { S.corner.lock }
	local ids = { "lock" }
	if state.friends then
		table.insert(widths, S.corner.button)
		table.insert(ids, "friends")
	end
	table.insert(widths, S.corner.button)
	table.insert(ids, "gear")
	local corner, moved = ScreenLayout.cornerRow(device, widths)
	local cornerRight = 0
	for index, r in corner do
		add(ids[index], "button", r)
		cornerRight = math.max(cornerRight, r.x + r.w)
	end
	local grid = ScreenLayout.sideGrid(device, 4, moved)
	for index, id in { "shop", "rebirth", "rewards", "snackdex" } do
		add(id, "button", ScreenLayout.sideCell(grid, index))
	end

	-- Top stack (a centred UIListLayout).
	local cx = device.width / 2
	local y = S.stackTop
	local function pill(id: string, w: number, h: number): Rect
		local r = rect(cx - w / 2, y, w, h)
		add(id, "info", r)
		y += h + S.stackGap
		return r
	end
	pill("cash", S.cash.w, S.cash.h)
	local tagRect = ScreenLayout.tagButton(device)
	if state.tutorial then
		local rightLimit = math.min(ScreenLayout.actionArea(device).x, device.width - device.playerList)
		local fits = 2 * (rightLimit - S.tutorial.gap - cx)
		local w = math.max(S.tutorial.minW, math.min(S.tutorial.w, fits))
		local banner = pill("tutorial", w, S.tutorial.h + (if state.tutorial == "full" then S.tutorial.tip else 0))
		add(
			"skip",
			"button",
			rect(
				banner.x + banner.w - S.skip.inset - S.skip.w,
				banner.y + (S.tutorial.h - S.skip.h) / 2,
				S.skip.w,
				S.skip.h
			),
			"tutorial"
		)
	elseif state.cashOffer then
		local O = S.cashOffer
		local x, w = ScreenLayout.cashOfferPlacement(device, moved, cornerRight)
		local strip = rect(x, y, w, O.h)
		add("cashOffer", "info", strip)
		y += O.h + S.stackGap
		local closeX = strip.x + strip.w - O.inset - O.close
		add("cashOfferClose", "button", rect(closeX, strip.y + O.inset, O.close, O.h - 2 * O.inset), "cashOffer")
		add(
			"cashOfferBuy",
			"button",
			rect(closeX - 6 - O.buy, strip.y + O.inset, O.buy, O.h - 2 * O.inset),
			"cashOffer"
		)
	end
	pill("income", S.income.w, S.income.h)
	local chips = (if state.luck then 1 else 0) + (if state.modifier then 1 else 0)
	if state.event or chips > 0 then
		local columnH = chips * S.chip.h + math.max(0, chips - 1) * S.chip.gap
		local available = ScreenLayout.statusRowWidth(device, moved)
		local both = state.event and chips > 0
		local function chipColumn(top: number, x: number)
			local chipY = top
			for _, id in { "luck", "modifier" } do
				if (id == "luck" and state.luck) or (id == "modifier" and state.modifier) then
					add(id, "info", rect(x, chipY, S.chip.w, S.chip.h))
					chipY += S.chip.h + S.chip.gap
				end
			end
		end
		if both and S.eventPill.w + S.statusGap + S.chip.w <= available then
			local w = S.eventPill.w + S.statusGap + S.chip.w
			local h = math.max(S.eventPill.h, columnH)
			local x = cx - w / 2
			add("event", "info", rect(x, y + (h - S.eventPill.h) / 2, S.eventPill.w, S.eventPill.h))
			chipColumn(y + (h - columnH) / 2, x + S.eventPill.w + S.statusGap)
			y += h + S.stackGap
		else
			if state.event then
				add("event", "info", rect(cx - S.eventPill.w / 2, y, S.eventPill.w, S.eventPill.h))
				y += S.eventPill.h + (if chips > 0 then S.statusGap else S.stackGap)
			end
			if chips > 0 then
				chipColumn(y, cx - S.chip.w / 2)
				y += columnH + S.stackGap
			end
		end
	end
	local stackBottom = y - S.stackGap

	-- The TAG button, the vote strip and what floats above the HUD.
	if state.tag then
		add("tag", "button", tagRect)
	end
	if state.vote then
		local strip = ScreenLayout.voteStrip(device)
		add("voteHeader", "info", rect(strip.x, strip.y, strip.w, S.vote.header))
		for index = 1, 3 do
			add("vote" .. index, "button", ScreenLayout.voteChoice(strip, index, 3))
		end
	end
	if state.carrying then
		add("carry", "overlay", rect(cx - S.carry.w / 2, device.height - S.carry.bottom - S.carry.h, S.carry.w, S.carry.h))
	end
	local overlayY = stackBottom + S.overlayGap
	if state.announcement then
		local w = ScreenLayout.centredWidth(device, cx, S.banner.w, moved)
		add("announcement", "overlay", rect(cx - w / 2, overlayY, w, S.banner.h))
	end
	if state.titleCard then
		local w = ScreenLayout.centredWidth(device, cx, S.titleCard.w, moved)
		add("titleCard", "overlay", rect(cx - w / 2, overlayY, w, S.titleCard.h))
	end
	if state.stealAlert then
		local w = ScreenLayout.centredWidth(device, cx, S.stealAlert.w, moved)
		add("stealAlert", "overlay", rect(cx - w / 2, S.stealAlert.y, w, S.stealAlert.h))
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
	return list
end

-- The device as the tutorial leaves it: the player list switched off while its banner can't clear it.
function ScreenLayout.tutorialDevice(device: Device): Device
	if device.playerList <= 0 then
		return device
	end
	local S = ScreenLayout.SIZE.tutorial
	local cx = device.width / 2
	local rightLimit = math.min(ScreenLayout.actionArea(device).x, device.width - device.playerList)
	local w = math.max(S.minW, math.min(S.w, 2 * (rightLimit - S.gap - cx)))
	if ScreenLayout.bannerNeedsPlayerListHidden(cx, w, device.width, device.playerList, S.gap) then
		return ScreenLayout.withoutPlayerList(device)
	end
	return device
end

-- The check -----------------------------------------------------------------------------------------------------------

local function describe(e: Element): string
	local r = e.rect
	return string.format("%s (x %.0f-%.0f, y %.0f-%.0f)", e.id, r.x, r.x + r.w, r.y, r.y + r.h)
end

-- What is wrong with a layout (empty when it is fine):
--   * everything of the HUD inside the screen's safe area
--   * no two buttons overlap, and no HUD pill overlaps another pill or a button (except its own pill)
--   * nothing that floats above the HUD (toasts, banners, alerts, cards) covers a button
--   * no button in the play zone, on Roblox's top-bar buttons, the player list, the jump button or where the
--     thumbstick starts; no HUD pill under Roblox's buttons or the player list
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
		if r.x < -tolerance or r.y < -tolerance or r.x + r.w > device.width + tolerance or r.y + r.h > device.height + tolerance then
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
			if (not overlay) or button then
				report(`{describe(a)} overlaps {describe(b)}`)
			end
		end
	end
	return problems
end

-- The devices and the busiest states the HUD is checked in (tests/ScreenLayout.spec.luau, tools/layoutCheck.luau).
ScreenLayout.DEVICES = table.freeze({
	{ name = "640x360 phone", widthPx = 640, heightPx = 360, touch = true },
	{ name = "667x375 phone", widthPx = 667, heightPx = 375, touch = true },
	-- iPhone 12-15 in landscape: the notch and the home indicator take 47 px each side and 21 at the bottom
	{ name = "844x390 phone", widthPx = 844, heightPx = 390, touch = true, insetLeftPx = 47, insetRightPx = 47, insetBottomPx = 21 },
	-- a tablet keeps Roblox's player list on screen (leaderstats: Cash, Steals)
	{ name = "1024x768 tablet", widthPx = 1024, heightPx = 768, touch = true, playerListPx = 358 },
	{ name = "1280x720 window", widthPx = 1280, heightPx = 720, touch = false, playerListPx = 358 },
} :: { DeviceSpec })

export type Scenario = { name: string, state: HudState }

ScreenLayout.SCENARIOS = table.freeze({
	{
		name = "everything at once (no tutorial)",
		state = {
			cashOffer = true,
			event = true,
			luck = true,
			modifier = true,
			vote = true,
			toasts = 3,
			announcement = true,
			stealAlert = true,
			tag = true,
			friends = true,
		},
	},
	{
		-- the vote hides while carrying, and nothing offers cash then (buying is refused while carrying)
		name = "carrying a Snackling home",
		state = {
			event = true,
			luck = true,
			modifier = true,
			carrying = true,
			toasts = 3,
			announcement = true,
			stealAlert = true,
			tag = true,
			friends = true,
		},
	},
	{
		-- the vote and cash offers wait for the tutorial; the Friends button hides during it
		name = "tutorial with its tip",
		state = {
			tutorial = "full",
			event = true,
			luck = true,
			modifier = true,
			toasts = 3,
			announcement = true,
			stealAlert = true,
			tag = true,
		},
	},
	{
		name = "tutorial while carrying",
		state = {
			tutorial = "compact",
			event = true,
			luck = true,
			modifier = true,
			carrying = true,
			toasts = 3,
			announcement = true,
			tag = true,
		},
	},
	{
		-- right after a vote: the new map's title card (the vote strip is gone)
		name = "a new map",
		state = {
			event = true,
			modifier = true,
			titleCard = true,
			toasts = 3,
			announcement = true,
			tag = true,
			friends = true,
		},
	},
	{ name = "a quiet moment", state = { friends = true } },
} :: { Scenario })

-- The device a scenario runs on (the tutorial may switch the player list off).
function ScreenLayout.scenarioDevice(spec: DeviceSpec, scenario: Scenario): Device
	local device = ScreenLayout.device(spec)
	return if scenario.state.tutorial then ScreenLayout.tutorialDevice(device) else device
end

-- Every problem on every device in every scenario.
function ScreenLayout.checkAll(): { string }
	local all: { string } = {}
	for _, spec in ScreenLayout.DEVICES do
		for _, scenario in ScreenLayout.SCENARIOS do
			local device = ScreenLayout.scenarioDevice(spec, scenario)
			for _, problem in ScreenLayout.problems(device, ScreenLayout.hud(device, scenario.state)) do
				table.insert(all, `{problem} [{scenario.name}]`)
			end
		end
	end
	return all
end

-- Tutorial banner helpers (TutorialController) -------------------------------------------------------------------------

-- The x the tutorial banner's right edge must stay left of: the TAG button area, or the player list's left edge.
function ScreenLayout.bannerRightLimit(actionAreaX: number, screenWidth: number, playerList: number): number
	return math.min(actionAreaX, screenWidth - playerList)
end

-- True when even the narrowest banner (centred on centerX) would run under the player list: the tutorial then hides
-- the player list while its banner shows, so Skip is always reachable.
function ScreenLayout.bannerNeedsPlayerListHidden(
	centerX: number,
	minWidth: number,
	screenWidth: number,
	playerList: number,
	gap: number
): boolean
	if playerList <= 0 then
		return false
	end
	return centerX + minWidth / 2 > screenWidth - playerList - gap
end

return ScreenLayout
