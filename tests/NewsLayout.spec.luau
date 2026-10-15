--!strict
-- The What's New card and board (Logic/NewsLayout): the card fits every checked screen below Roblox's top bar, its
-- button is big and its text reads at 12 UI or more; the board's lines stay readable once you walk up to it.
local T = require("./TestKit")
local Format = require("../src/shared/Logic/Format")
local NewsLayout = require("../src/shared/Logic/NewsLayout")
local ScreenLayout = require("../src/shared/Logic/ScreenLayout")
local TextFit = require("../src/shared/Logic/TextFit")
local Theme = require("../src/shared/Config/Theme")
local UpdateRules = require("../src/shared/Logic/UpdateRules")
local Updates = require("../src/shared/Config/Updates")

type Rect = NewsLayout.Rect

local L = NewsLayout
local MIN = ScreenLayout.TEXT.minSize
local PAD = ScreenLayout.TEXT.button

local function inside(inner: Rect, w: number, h: number): boolean
	return inner.x >= 0 and inner.y >= 0 and inner.x + inner.w <= w + 1e-6 and inner.y + inner.h <= h + 1e-6
end

local function overlaps(a: Rect, b: Rect): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

local function apart(boxes: { [string]: Rect }): string
	local problems: { string } = {}
	for name, r in boxes do
		for other, s in boxes do
			if name < other and overlaps(r, s) then
				table.insert(problems, `{name} overlaps {other}`)
			end
		end
	end
	table.sort(problems)
	return table.concat(problems, "; ")
end

T.describe("NewsLayout card", function()
	T.it("fits every checked screen below Roblox's top bar, at the smallest scale", function()
		local problems: { string } = {}
		for _, spec in ScreenLayout.DEVICES do
			local device = ScreenLayout.device(spec)
			for _, problem in L.fitProblems(device.width, device.height, device.topBar, ScreenLayout.EDGE) do
				table.insert(problems, `{spec.name}: {problem}`)
			end
		end
		T.expect(table.concat(problems, "; ")).toBe("")
		T.expect(L.BODY.w).toBe(L.CARD.w - 32)
		T.expect(L.BODY.h).toBe(L.CARD.h - 72)
		T.expect(L.CARD.h).toBeAtMost(340)
	end)

	T.it("keeps every line and the big button inside the card, apart", function()
		for lines = UpdateRules.MIN_HIGHLIGHTS, UpdateRules.MAX_HIGHLIGHTS do
			local boxes = L.cardBoxes(lines)
			for name, r in boxes do
				if not inside(r, L.BODY.w, L.BODY.h) then
					error(`{lines} lines: {name} sticks out`)
				end
			end
			T.expect(apart(boxes)).toBe("")
		end
		local button = L.cardBoxes(5).button
		T.expect(button.h).toBeAtLeast(56) -- "a big Let's go! button"
		T.expect(button.w).toBeAtLeast(200)
	end)

	T.it("reads at 12 UI or more for every update", function()
		local small: { string } = {}
		local function check(what: string, size: number)
			if size < MIN then
				table.insert(small, `{what} ({size})`)
			end
		end
		for _, def in Updates.list do
			local boxes = L.cardBoxes(#def.highlights)
			check(`#{def.number} title`, TextFit.fit(def.title, boxes.title.w, boxes.title.h, false))
			local meta = Format.template(Theme.text.whatsNewMeta, { number = def.number, date = def.date })
			check(`#{def.number} meta`, TextFit.fit(meta, boxes.meta.w, boxes.meta.h, false))
			for i, line in def.highlights do
				local r = boxes[`line{i}`]
				check(`#{def.number} line {i}`, TextFit.fit(line, r.w, r.h, false))
			end
			local b = boxes.button
			check(
				"whatsNewButton",
				TextFit.fit(Theme.text.whatsNewButton, b.w - 2 * PAD.padX, b.h - 2 * PAD.padY, false)
			)
		end
		T.expect(table.concat(small, ", ")).toBe("")
	end)
end)

T.describe("NewsLayout board", function()
	T.it("keeps everything on the board's face, apart", function()
		local B = L.BOARD
		for lines = UpdateRules.MIN_HIGHLIGHTS, UpdateRules.MAX_HIGHLIGHTS do
			local boxes = L.boardBoxes(lines)
			for name, r in boxes do
				if not inside(r, B.w * B.pixelsPerStud, B.h * B.pixelsPerStud) then
					error(`{lines} lines: {name} sticks out`)
				end
			end
			T.expect(apart(boxes)).toBe("")
		end
	end)

	T.it("shows every update's lines big enough to read up close", function()
		local small: { string } = {}
		for _, def in Updates.list do
			local boxes = L.boardBoxes(#def.highlights)
			local function check(what: string, line: string, r: Rect)
				local size = TextFit.fit(line, r.w, r.h, false)
				if size < L.BOARD_MIN_TEXT then
					table.insert(small, `{what} ({size})`)
				end
			end
			check("header", Theme.text.newsBoardHeader, boxes.header)
			check("title", def.title, boxes.title)
			for i, line in def.highlights do
				check(`line {i}`, line, boxes[`line{i}`])
			end
			check(
				"meta",
				Format.template(Theme.text.whatsNewMeta, { number = def.number, date = def.date }),
				boxes.meta
			)
		end
		T.expect(table.concat(small, ", ")).toBe("")
	end)
end)

return nil
