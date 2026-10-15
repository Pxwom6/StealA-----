--!strict
-- The Style dialog and the Settings row (Logic/StyleLayout), held to the HUD's rules (DECISIONS #47): the dialog fits
-- every checked screen below Roblox's top bar, every button is a full touch target and every text reads at 12 UI or
-- more. Also every title on its nametag, and the unlock toasts.
local T = require("./TestKit")
local Achievements = require("../src/shared/Config/Achievements")
local AchievementRules = require("../src/shared/Logic/AchievementRules")
local Catalog = require("../src/shared/Logic/Catalog")
local Creatures = require("../src/shared/Config/Creatures")
local DataSchema = require("../src/shared/Logic/DataSchema")
local Format = require("../src/shared/Logic/Format")
local Mutations = require("../src/shared/Config/Mutations")
local Rarities = require("../src/shared/Config/Rarities")
local ScreenLayout = require("../src/shared/Logic/ScreenLayout")
local Skins = require("../src/shared/Config/Skins")
local StyleLayout = require("../src/shared/Logic/StyleLayout")
local StyleRules = require("../src/shared/Logic/StyleRules")
local TextFit = require("../src/shared/Logic/TextFit")
local Theme = require("../src/shared/Config/Theme")
local Titles = require("../src/shared/Config/Titles")
local Types = require("../src/shared/Types")

type Rect = StyleLayout.Rect

local L = StyleLayout
local MIN = ScreenLayout.TEXT.minSize
local PAD = ScreenLayout.TEXT.button -- UiKit.button pads 8 x 6
local text = Theme.text :: any
local achievements = StyleRules.achievementsById(Achievements)
local catalog = Catalog.build(Creatures, Rarities, Mutations)
local tierCount = #Rarities
-- A brand-new save: every card's progress starts here.
local fresh: StyleRules.Unlocks = {
	ctx = AchievementRules.context(DataSchema.template(100), catalog.creatures, catalog.rarities),
	flags = {},
	achievements = achievements,
	rarities = catalog.rarities,
}

local function inside(inner: Rect, outer: { w: number, h: number }): boolean
	return inner.x >= 0 and inner.y >= 0 and inner.x + inner.w <= outer.w + 1e-6 and inner.y + inner.h <= outer.h + 1e-6
end

local function overlaps(a: Rect, b: Rect): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

local small: { string } = {}
local function check(what: string, size: number)
	if size < MIN then
		table.insert(small, `{what} ({size})`)
	end
end
local function fits(what: string, line: string, r: Rect, wrapped: boolean)
	check(what, TextFit.fit(line, r.w, r.h, wrapped))
end

T.describe("StyleLayout", function()
	T.it("fits every checked screen below Roblox's top bar, at the smallest scale", function()
		local problems: { string } = {}
		for _, spec in ScreenLayout.DEVICES do
			local device = ScreenLayout.device(spec)
			for _, problem in L.fitProblems(device.width, device.height, device.topBar, ScreenLayout.EDGE) do
				table.insert(problems, `{spec.name}: {problem}`)
			end
		end
		T.expect(table.concat(problems, "; ")).toBe("")
		T.expect(L.BODY.w).toBe(L.DIALOG.w - 32) -- Modal's margins
		T.expect(L.BODY.h).toBe(L.DIALOG.h - 72)
		T.expect(L.DIALOG.h).toBeAtMost(340) -- Modal's rule for landscape phones
	end)

	T.it("keeps the tab bar, the line about what is worn and the grids inside the body, apart", function()
		local boxes: { [string]: Rect } = {}
		for index, tab in L.TABS do
			boxes[`tab {tab}`] = L.tabButton(index)
		end
		local now, hint = L.nowLines()
		boxes.now, boxes.hint = now, hint
		for name, r in boxes do
			T.expect(inside(r, L.BODY)).toBe(true)
			for other, s in boxes do
				if name < other and overlaps(r, s) then
					error(`{name} overlaps {other}`)
				end
			end
		end
		for _, tab: StyleLayout.Tab in L.TABS do
			local list = L.list(tab)
			T.expect(inside(list, L.BODY)).toBe(true)
			for _, r in boxes do
				T.expect(overlaps(list, r)).toBe(false)
			end
		end
	end)

	T.it("makes every tab and card a full touch target", function()
		for index in L.TABS do
			local r = L.tabButton(index)
			T.expect(math.min(r.w, r.h)).toBeAtLeast(L.BUTTON)
		end
		for _, tab: StyleLayout.Tab in L.TABS do
			local size = L.cardSize(tab)
			T.expect(math.min(size.w, size.h)).toBeAtLeast(L.BUTTON)
		end
		T.expect(L.BUTTON * ScreenLayout.SCALE.min).toBeAtLeast(ScreenLayout.MIN_TOUCH) -- 52 UI is 44 px
	end)

	T.it("lays the cards out as a grid inside its scrolling list, beside the scroll bar", function()
		for _, tab: StyleLayout.Tab in L.TABS do
			local list = L.list(tab)
			local columns = L.COLUMNS[tab]
			local count = if tab == "titles" then #Titles.list + 1 else #Skins.list
			local canvas = { w = list.w - L.SCROLLBAR, h = L.canvasHeight(tab, count) }
			for i = 1, count do
				local card = L.cardAt(tab, i)
				T.expect(inside(card, canvas)).toBe(true)
				if i > 1 then
					T.expect(overlaps(card, L.cardAt(tab, i - 1))).toBe(false)
				end
			end
			-- the last column ends right before the inset and the scroll bar
			local last = L.cardAt(tab, columns)
			T.expect(last.x + last.w + L.LIST_INSET + L.SCROLLBAR).toBe(list.w)
			-- what is inside a card stays inside it, apart
			local size = L.cardSize(tab)
			local inner = L.cardBoxes(tab)
			for name, r in inner do
				T.expect(inside(r, size)).toBe(true)
				for other, s in inner do
					if name < other and overlaps(r, s) then
						error(`{tab}: {name} overlaps {other}`)
					end
				end
			end
		end
	end)

	T.it("puts Style beside Codes in Settings' last row (and the host panel for hosts), full touch targets", function()
		for _, mayHost in { false, true } do
			local row = L.settingsRow(mayHost)
			T.expect(#row).toBe(if mayHost then 3 else 2)
			for i, r in row do
				T.expect(math.min(r.w, r.h)).toBeAtLeast(L.BUTTON)
				T.expect(r.x + r.w).toBeAtMost(L.SETTINGS_BODY_W + 1e-6)
				if i > 1 then
					T.expect(overlaps(r, row[i - 1])).toBe(false)
				end
			end
		end
	end)
end)

T.describe("StyleLayout text", function()
	T.it("fits the tabs, and every line about what is worn", function()
		table.clear(small)
		local tab = L.tabButton(1)
		local button = { x = 0, y = 0, w = tab.w - 2 * PAD.padX, h = tab.h - 2 * PAD.padY }
		fits("styleTabTitles", Theme.text.styleTabTitles, button, false)
		fits("styleTabBase", Theme.text.styleTabBase, button, false)
		local now, hint = L.nowLines()
		for _, def in Titles.list do
			fits(def.id, Format.template(Theme.text.styleWearing, { title = `{def.icon} {def.text}` }), now, false)
		end
		fits("styleWearingNone", Theme.text.styleWearingNone, now, false)
		for _, def in Skins.list do
			fits(def.id, Format.template(Theme.text.styleBaseNow, { skin = `{def.icon} {def.name}` }), now, false)
		end
		fits("styleTitlesHint", Theme.text.styleTitlesHint, hint, false)
		fits("styleBaseHint", Theme.text.styleBaseHint, hint, false)
		T.expect(table.concat(small, ", ")).toBe("")
	end)

	T.it("fits every card: its name, how to earn it and its state", function()
		table.clear(small)
		local function card(tab: StyleLayout.Tab, name: string, unlock: Types.StyleUnlock)
			local boxes = L.cardBoxes(tab)
			fits(`{tab} name {name}`, name, boxes.name, false)
			local hint = StyleRules.hint(unlock, achievements, tierCount, text)
			fits(`{tab} hint {name}`, hint, boxes.hint, true)
			local states: { string } = if tab == "titles"
				then { Theme.text.styleTapToWear, Theme.text.styleWorn }
				else { Theme.text.styleTapToUse, Theme.text.styleUsed }
			-- the longest progress it can show: one short of the target
			local _, target = StyleRules.progress(unlock, fresh)
			local worst = if target > 1 then target * 0.999 else 0
			table.insert(
				states,
				StyleRules.progressText(unlock, worst, target, achievements, text, Theme.currencySymbol)
			)
			for _, state in states do
				fits(`{tab} state {name}`, state, boxes.status, false)
			end
		end
		for _, def in Titles.list do
			card("titles", `{def.icon} {def.text}`, def.unlock)
		end
		local boxes = L.cardBoxes("titles")
		fits("styleNoTitle", `🚫 {Theme.text.styleNoTitle}`, boxes.name, false)
		fits("styleNoTitleHint", Theme.text.styleNoTitleHint, boxes.hint, true)
		for _, def in Skins.list do
			card("base", `{def.icon} {def.name}`, def.unlock)
		end
		fits("styleLoading", Theme.text.styleLoading, L.list("titles"), false)
		T.expect(table.concat(small, ", ")).toBe("")
	end)

	T.it("fits the Settings row's labels in halves and in thirds", function()
		table.clear(small)
		for _, mayHost in { false, true } do
			local row = L.settingsRow(mayHost)
			local label = L.settingsLabel(row[1])
			fits("settingsStyle", Theme.text.settingsStyle, label, false)
			fits("settingsCodes", Theme.text.settingsCodes, label, false)
			if mayHost then
				fits("settingsHost", Theme.text.settingsHost, label, false)
			end
		end
		T.expect(table.concat(small, ", ")).toBe("")
	end)

	T.it("fits every title on its nametag, at a size a phone reads", function()
		local tag = Titles.nametag
		local tooSmall: { string } = {}
		for _, def in Titles.list do
			-- the label is inset 6 px a side and 2 top and bottom inside the BillboardGui (server/Services/Nametags)
			local size = TextFit.fit(`{def.icon} {def.text}`, tag.width - 12, tag.height - 4, false, tag.maxTextSize)
			if size < 14 then
				table.insert(tooSmall, `{def.id} ({size})`)
			end
		end
		T.expect(table.concat(tooSmall, ", ")).toBe("")
	end)

	T.it("fits every unlock toast, with the real names, like any other toast", function()
		table.clear(small)
		local S, P = ScreenLayout.SIZE.toast, ScreenLayout.TEXT.toast
		local function toast(what: string, line: string)
			local h = ScreenLayout.toastHeight(line)
			check(what, TextFit.fit(line, S.w - 2 * P.padX, h - 2 * P.padY, h == S.tall))
		end
		for _, def in Titles.list do
			toast(def.id, Format.template(Theme.text.titleUnlocked, { icon = def.icon, title = def.text }))
		end
		for _, def in Skins.list do
			toast(def.id, Format.template(Theme.text.skinUnlocked, { icon = def.icon, skin = def.name }))
			local hint = StyleRules.hint(def.unlock, achievements, tierCount, text)
			toast(`locked {def.id}`, Format.template(Theme.text.styleLockedHint, { hint = hint }))
		end
		for _, def in Titles.list do
			local hint = StyleRules.hint(def.unlock, achievements, tierCount, text)
			toast(`locked {def.id}`, Format.template(Theme.text.styleLockedHint, { hint = hint }))
		end
		T.expect(table.concat(small, ", ")).toBe("")
	end)
end)

return nil
