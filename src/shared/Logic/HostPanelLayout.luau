--!strict
--[[
	Where everything goes in the host panel (HostPanelController), in UI units inside the dialog's body (Modal: the
	body starts 16 in from the panel's sides and 58 from its top, and ends 14 above its bottom). Pure, so tests can
	prove the panel fits every checked screen below Roblox's top bar, keeps every button a full touch target (52 UI,
	44 px on the smallest phones) and every label at 12 UI or more (Logic/TextFit), as the HUD does (DECISIONS #47).

	  tab bar   the tabs (admins: Map, Modifiers, Belt, Boosts, Message; a private server's owner: Map, Modifiers),
	            then the admins' scope switch ("This server" / "All servers") or the owner's "Your private server"
	  content   from y 60: a scrolling list of choices on the left and the actions on the right (Map, Modifiers,
	            Belt), steppers in rows (Boosts), or a text box (Message)

	Each tab's boxes are named; `kind` says what the controller builds there: a button, a label, a value (a label in a
	panel, between a stepper's buttons), a list (a scrolling grid of `cell`-sized buttons) or an input (a text box).
]]

local HostPanelLayout = {}

export type Rect = { x: number, y: number, w: number, h: number }
export type Kind = "button" | "label" | "value" | "list" | "input"
export type Box = { rect: Rect, kind: Kind, cell: { w: number, h: number }?, columns: number? }
export type Role = "admin" | "owner"

HostPanelLayout.DIALOG = table.freeze({ w = 700, h = 336 }) -- the size Modal.open gets
HostPanelLayout.BODY = table.freeze({ w = 668, h = 264 })
HostPanelLayout.BUTTON = 52 -- every button's height and the smallest side of any button
HostPanelLayout.GAP = 6 -- between neighbours in a group
HostPanelLayout.GROUP_GAP = 8 -- between groups in a row
HostPanelLayout.SCROLLBAR = 6
-- A list's cells sit this far in from its edges, so their borders (UiKit.STROKE.normal) are never clipped.
HostPanelLayout.LIST_INSET = 3
HostPanelLayout.CONTENT_TOP = 60
HostPanelLayout.TAB = table.freeze({ w = 100, h = 52 })
HostPanelLayout.SCOPE = table.freeze({ w = 136, h = 52 })
-- Text inside a button or a value box sits this far in from its edges (UiKit.button pads 8 x 6).
HostPanelLayout.PAD = table.freeze({ x = 8, y = 6 })

HostPanelLayout.TABS = table.freeze({
	admin = table.freeze({ "map", "modifiers", "belt", "boosts", "broadcast" }),
	owner = table.freeze({ "map", "modifiers" }),
})

local function rect(x: number, y: number, w: number, h: number): Rect
	return { x = x, y = y, w = w, h = h }
end

local function box(kind: Kind, x: number, y: number, w: number, h: number): Box
	return { rect = rect(x, y, w, h), kind = kind }
end

-- A scrolling grid of `columns` cells `cellW` wide, sized to hold them (inset from its edges) beside its scroll bar.
local function list(x: number, y: number, h: number, cellW: number, columns: number): Box
	local w = 2 * HostPanelLayout.LIST_INSET
		+ columns * cellW
		+ (columns - 1) * HostPanelLayout.GAP
		+ HostPanelLayout.SCROLLBAR
	return {
		rect = rect(x, y, w, h),
		kind = "list",
		cell = { w = cellW, h = HostPanelLayout.BUTTON },
		columns = columns,
	}
end

-- The tabs `role` sees, in order.
function HostPanelLayout.tabs(role: Role): { string }
	return HostPanelLayout.TABS[role]
end

-- The `index`th tab button.
function HostPanelLayout.tabButton(index: number): Rect
	local T = HostPanelLayout.TAB
	return rect((index - 1) * (T.w + HostPanelLayout.GAP), 0, T.w, T.h)
end

-- The admins' scope switch, at the right end of the tab bar.
function HostPanelLayout.scopeButton(): Rect
	local S = HostPanelLayout.SCOPE
	return rect(HostPanelLayout.BODY.w - S.w, 0, S.w, S.h)
end

-- "Your private server": the rest of the owner's tab bar.
function HostPanelLayout.ownerNote(): Rect
	local x = HostPanelLayout.tabButton(#HostPanelLayout.TABS.owner + 1).x
	return rect(x, 0, HostPanelLayout.BODY.w - x, HostPanelLayout.TAB.h)
end

-- The boxes of tab `id` as `role` sees it, by name.
function HostPanelLayout.tab(id: string, role: Role): { [string]: Box }
	local B, G, GG = HostPanelLayout.BUTTON, HostPanelLayout.GAP, HostPanelLayout.GROUP_GAP
	local top = HostPanelLayout.CONTENT_TOP
	local height = HostPanelLayout.BODY.h - top
	local row1, row2, row3 = top + 34, top + 34 + B + G, top + 34 + 2 * (B + G)
	local boxes: { [string]: Box } = {}
	if id == "map" or id == "modifiers" then
		-- The choices on the left, two columns; the actions on the right.
		boxes.list = list(0, top, height, 181, 2)
		local x = boxes.list.rect.w + 12
		local w = HostPanelLayout.BODY.w - x
		boxes.now = box("label", x, top, w, 28)
		if id == "map" then
			boxes.switch = box("button", x, row1, w, B)
			if role == "admin" then
				boxes.vote = box("button", x, row2, w, B)
				boxes.rotation = box("button", x, row3, w, B)
			else
				boxes.rotation = box("button", x, row2, w, B)
			end
		else
			boxes.minutesMinus = box("button", x, row1, B, B)
			boxes.minutesValue = box("value", x + B + G, row1, w - 2 * (B + G), B)
			boxes.minutesPlus = box("button", x + w - B, row1, B, B)
			boxes.start = box("button", x, row2, w, B)
			boxes.stop = box("button", x, row3, w, B)
		end
	elseif id == "belt" then
		-- Snacklings (rarest first) and mutations, then what will drop and the button.
		boxes.creatures = list(0, top, height, 141, 2)
		local mx = boxes.creatures.rect.w + GG
		boxes.mutations = list(mx, top, height, 168, 1)
		local x = mx + boxes.mutations.rect.w + GG
		local w = HostPanelLayout.BODY.w - x
		boxes.summary = box("label", x, top, w, row3 - top - G)
		boxes.drop = box("button", x, row3, w, B)
	elseif id == "boosts" then
		-- Three rows: luck (multiplier, minutes, Start), an event (which, minutes, Start, End), a gift (minutes, Gift!).
		local function stepper(prefix: string, x: number, y: number, valueW: number): number
			boxes[prefix .. "Minus"] = box("button", x, y, B, B)
			boxes[prefix .. "Value"] = box("value", x + B + G, y, valueW, B)
			boxes[prefix .. "Plus"] = box("button", x + B + G + valueW + G, y, B, B)
			return x + 2 * (B + G) + valueW + GG
		end
		local y1, y2, y3 = top, top + B + G, top + 2 * (B + G)
		local x = stepper("luck", 0, y1, 104)
		x = stepper("luckMinutes", x, y1, 104)
		boxes.luckStart = box("button", x, y1, HostPanelLayout.BODY.w - x, B)
		local startX = x
		x = stepper("event", 0, y2, 150)
		x = stepper("eventMinutes", x, y2, 104)
		local half = (HostPanelLayout.BODY.w - x - G) / 2
		boxes.eventStart = box("button", x, y2, half, B)
		boxes.eventStop = box("button", x + half + G, y2, half, B)
		x = stepper("gift", 0, y3, 104)
		boxes.giftHint = box("label", x, y3, startX - GG - x, B)
		boxes.giftSend = box("button", startX, y3, HostPanelLayout.BODY.w - startX, B)
	elseif id == "broadcast" then
		boxes.input = box("input", 0, top, HostPanelLayout.BODY.w, 96)
		boxes.note = box("label", 0, top + 96 + G, HostPanelLayout.BODY.w, 24)
		boxes.count = box("label", 0, row3, 200, B)
		boxes.send = box("button", HostPanelLayout.BODY.w - 200, row3, 200, B)
	end
	return boxes
end

-- Problems with the panel on a screen `width` x `height` UI with Roblox's top bar ending at `topBar`: it must fit
-- across with `margin` to spare each side, and, with its drop shadow (6 lower), in the part below the top bar, where
-- Modal centres it (as tall as the Rewards panel allows, so no margin is asked for there).
function HostPanelLayout.fitProblems(width: number, height: number, topBar: number, margin: number): { string }
	local problems: { string } = {}
	local D = HostPanelLayout.DIALOG
	if D.w + 2 * margin > width then
		table.insert(problems, `the dialog is {D.w} wide, the screen {math.floor(width)}`)
	end
	if D.h + 6 > height - topBar then
		table.insert(problems, `the dialog is {D.h} tall, {math.floor(height - topBar)} below the top bar`)
	end
	return problems
end

return HostPanelLayout
