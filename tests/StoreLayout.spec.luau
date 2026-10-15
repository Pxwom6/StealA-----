--!strict
-- The store additions' layout (Logic/StoreLayout), held to the HUD's rules (DECISIONS #47) like the host panel: both
-- dialogs fit every checked screen below Roblox's top bar, every button is a full touch target, nothing overlaps, and
-- every label reads at 12 UI or more (Logic/TextFit).
local T = require("./TestKit")
local Catalog = require("../src/shared/Logic/Catalog")
local Format = require("../src/shared/Logic/Format")
local ScreenLayout = require("../src/shared/Logic/ScreenLayout")
local SpinOdds = require("../src/shared/Logic/SpinOdds")
local SpinRules = require("../src/shared/Logic/SpinRules")
local StoreLayout = require("../src/shared/Logic/StoreLayout")
local TextFit = require("../src/shared/Logic/TextFit")
local Creatures = require("../src/shared/Config/Creatures")
local Monetization = require("../src/shared/Config/Monetization")
local Mutations = require("../src/shared/Config/Mutations")
local Rarities = require("../src/shared/Config/Rarities")
local Spin = require("../src/shared/Config/Spin")
local Theme = require("../src/shared/Config/Theme")

local L = StoreLayout
local MIN = ScreenLayout.TEXT.minSize

local function fit(text: string, r: StoreLayout.Rect, wrapped: boolean): number
	return TextFit.fit(text, r.w, r.h, wrapped)
end

-- Every text the odds grid shows, worst cases included.
local function oddsTexts(): { { prize: string, chance: string } }
	local list = {}
	for index, chance in SpinRules.chances(Spin.segments) do
		local segment = Spin.segments[index]
		table.insert(list, { prize = `{segment.icon} {segment.label}`, chance = Format.percent(chance) })
	end
	return list
end

-- The smallest size any odds text comes out at in `area`, and which.
local function smallestOdds(area: StoreLayout.Rect): (number, string)
	local smallest, which = math.huge, ""
	local cells = L.oddsCells(area, #Spin.segments)
	local function measure(text: string, r: StoreLayout.Rect)
		local size = fit(text, r, false)
		if size < smallest then
			smallest, which = size, text
		end
	end
	for index, texts in oddsTexts() do
		local prize, chance = L.oddsText(cells[index])
		measure(texts.prize, prize)
		measure(texts.chance, chance)
	end
	return smallest, which
end

T.describe("StoreLayout dialogs", function()
	T.it("fit every checked screen below Roblox's top bar, at the smallest scale", function()
		local problems: { string } = {}
		for _, spec in ScreenLayout.DEVICES do
			local device = ScreenLayout.device(spec)
			for _, problem in L.fitProblems(device.width, device.height, device.topBar, L.MARGIN) do
				table.insert(problems, `{spec.name}: {problem}`)
			end
		end
		T.expect(table.concat(problems, "; ")).toBe("")
		-- Modal's rule for landscape phones, and the content areas the controllers fill
		T.expect(L.REWARDS.h).toBeAtMost(340)
		T.expect(L.STORE.h).toBeAtMost(340)
		T.expect(L.content(L.REWARDS)).toEqual({ w = 588, h = 210 })
		T.expect(L.content(L.STORE)).toEqual({ w = 608, h = 210 })
		-- 52 UI is 44 px at the smallest scale
		T.expect(L.BUTTON * ScreenLayout.SCALE.min).toBeAtLeast(ScreenLayout.MIN_TOUCH)
	end)
end)

T.describe("StoreLayout Spin tab", function()
	local content = L.content(L.REWARDS)

	for _, packs in { false, true } do
		local name = if packs then "with the Lucky Spin pack buttons" else "without them"
		T.it(`keeps everything inside the tab, apart and tappable, {name}`, function()
			local boxes = L.spinTab(packs)
			T.expect(table.concat(L.problems(boxes, content.w, content.h), "; ")).toBe("")
			T.expect(boxes.pack1 ~= nil).toBe(packs)
			T.expect(boxes.pack2 ~= nil).toBe(packs)
		end)

		T.it(`reads every prize and chance in the Odds view at 12 UI or more, {name}`, function()
			local smallest, which = smallestOdds(L.spinTab(packs).odds.rect)
			if smallest < MIN then
				print(`too small: {which} at {smallest}`)
			end
			T.expect(smallest).toBeAtLeast(MIN)
		end)
	end

	T.it("puts the Odds view beside the pack buttons, in the reel's place", function()
		local boxes = L.spinTab(true)
		T.expect(boxes.odds.rect).toEqual(boxes.reel.rect)
		local odds, pack = boxes.odds.rect, boxes.pack1.rect
		T.expect(pack.x).toBeGreaterThan(odds.x + odds.w - 1e-6) -- right of it, not under it
		T.expect(pack.y).toBe(odds.y)
		T.expect(boxes.pack2.rect.y + boxes.pack2.rect.h).toBe(odds.y + odds.h)
		-- and the reel only narrows: SPIN!, Odds, the warning and the status line stay where they were
		local plain = L.spinTab(false)
		for _, id in { "spin", "oddsButton", "warning", "status" } do
			T.expect(boxes[id].rect).toEqual(plain[id].rect)
		end
	end)

	T.it("fits each pack button's spins and price at 12 UI or more", function()
		local boxes = L.spinTab(true)
		local small: { string } = {}
		for _, slot in { "pack1", "pack2" } do
			local nameBox, priceBox = L.packText(boxes[slot].rect)
			for _, product in Monetization.products do
				if product.kind == "Spins" then
					local label = Format.template(Theme.text.spinPackName, { count = product.spins or 0 })
					if fit(label, nameBox, false) < MIN then
						table.insert(small, label)
					end
				end
			end
			-- the worst a price can read, and what the button says instead of one
			for _, text in { "R$ 9999", "R$ ?", Theme.text.spinPackFull, Theme.text.storeStudioGrant } do
				if fit(text, priceBox, false) < MIN then
					table.insert(small, text)
				end
			end
		end
		T.expect(table.concat(small, ", ")).toBe("")
	end)

	T.it("has room for every Lucky Spin pack for sale", function()
		local packs = 0
		for _, product in Monetization.products do
			if product.kind == "Spins" then
				packs += 1
			end
		end
		T.expect(packs).toBeAtLeast(1)
		T.expect(packs).toBeAtMost(2) -- pack1 and pack2
	end)
end)

T.describe("StoreLayout Shop cards", function()
	local C = L.CARD

	T.it("fits a Lucky Spin pack's card: buy button apart from the text, odds across the card", function()
		local boxes, height = L.packCard()
		T.expect(table.concat(L.problems(boxes, C.w, height), "; ")).toBe("")
		T.expect(boxes.buy.rect.y + boxes.buy.rect.h).toBeAtMost(boxes.odds.rect.y) -- the odds sit under the buy button
		local smallest, which = smallestOdds(boxes.odds.rect)
		if smallest < MIN then
			print(`too small: {which} at {smallest}`)
		end
		T.expect(smallest).toBeAtLeast(MIN)
		-- the card's title, as the other cards' titles are sized
		for key, product in Monetization.products do
			if product.kind == "Spins" then
				T.expect(fit(Theme.store[key].name, boxes.title.rect, false)).toBeAtLeast(MIN)
			end
		end
	end)

	T.it("fits the Starter Pack's card: its lines under the buy button, apart and inside", function()
		local boxes, height = L.starterCard(3)
		T.expect(table.concat(L.problems(boxes, C.w, height), "; ")).toBe("")
		T.expect(boxes.buy.rect.y + boxes.buy.rect.h).toBeAtMost(boxes.line1.rect.y)
		T.expect(boxes.line3 ~= nil and boxes.line4 == nil).toBe(true)
		T.expect(fit(Theme.store.StarterPack.name, boxes.title.rect, false)).toBeAtLeast(MIN)
	end)

	T.it("is as wide as the Shop's content less its scroll bar", function()
		T.expect(C.w).toBe(L.content(L.STORE).w - 8)
		T.expect(C.textX + C.textW).toBeAtMost(C.w - C.buy.right - C.buy.w)
	end)
end)

T.describe("StoreLayout: the Lucky Spin's Details list", function()
	local D = L.DETAILS
	local catalog = Catalog.build(Creatures, Rarities, Mutations)
	local odds = SpinOdds.table(Spin, catalog.rarityList, catalog.creatureList)
	local areas: { [string]: { w: number, h: number } } = { Rewards = L.content(L.REWARDS), Shop = L.content(L.STORE) }

	-- Every text a prize row can show (UI/OddsDetails.prizeText): a Snackling prize, or a cash prize with the largest
	-- amounts Format writes, or its rule.
	local function prizeTexts(): { string }
		local list: { string } = {}
		for _, segment in Spin.segments do
			local reward = segment.reward :: any
			if reward.kind == "creature" then
				local mutation = if reward.mutation then catalog.mutations[reward.mutation] else nil
				table.insert(
					list,
					if mutation
						then Format.template(
							Theme.text.spinDetailsSnacklingMutation,
							{ icon = segment.icon, label = segment.label, mutation = mutation.displayName }
						)
						else Format.template(
							Theme.text.spinDetailsSnackling,
							{ icon = segment.icon, label = segment.label }
						)
				)
			else
				local time = (string.gsub(Format.duration(reward.incomeSeconds), " 0s$", ""))
				for _, amount in
					{
						"$999Qa",
						"$9.99Sx",
						"$999.9K",
						Format.template(Theme.text.spinDetailsCashTime, { time = time }),
					}
				do
					table.insert(
						list,
						Format.template(
							Theme.text.spinDetailsCash,
							{ icon = segment.icon, label = segment.label, amount = amount }
						)
					)
				end
			end
		end
		return list
	end

	for name, area in areas do
		T.it(`fits the {name} dialog's content: a title, a full-size Back and the list`, function()
			local boxes = L.oddsDetails(area.w, area.h)
			T.expect(table.concat(L.problems(boxes, area.w, area.h), "; ")).toBe("")
			T.expect(TextFit.fit(Theme.text.spinDetailsTitle, boxes.title.rect.w, boxes.title.rect.h, false))
				.toBeAtLeast(MIN)
			T.expect(TextFit.fit(Theme.text.spinOddsBack, D.back.w - 16, D.back.h - 12, false)).toBeAtLeast(MIN)
			T.expect(boxes.list.rect.h).toBeAtLeast(4 * D.row) -- a few rows show at once
		end)

		T.it(`reads every row at {D.text} UI in the {name} dialog: prizes, every Snackling and every chance`, function()
			local w = L.oddsDetails(area.w, area.h).list.rect.w
			local columns = #odds.columns
			local small: { string } = {}
			local function check(text: string, r: StoreLayout.Rect)
				if not TextFit.fits(text, D.text, r.w, r.h, false) then
					table.insert(small, text)
				end
			end
			local prize, chance = L.detailsPrize(w)
			for _, text in prizeTexts() do
				check(text, prize)
			end
			for _, row in odds.segments do
				check(Format.percentPrecise(row.chance), chance)
			end
			local tierName, tierCells = L.detailsColumns(w, columns, false)
			local creatureName, creatureCells = L.detailsColumns(w, columns, true)
			for index, segment in odds.columns do
				check(`{segment.icon} {segment.label}`, tierCells[index])
			end
			for _, tier in odds.tiers do
				check(catalog.rarities[tier.rarity].displayName, tierName)
				for index, value in tier.chances do
					check(Format.percentPrecise(value), tierCells[index])
				end
				for _, creature in tier.creatures do
					check(catalog.creatures[creature.id].displayName, creatureName)
					for index, value in creature.chances do
						check(Format.percentPrecise(value), creatureCells[index])
					end
				end
			end
			-- the widest a chance can be written, and the headings and notes (two rows, wrapped)
			check("0.00012346%", creatureCells[1])
			for _, text in { Theme.text.spinDetailsReel, Theme.text.spinDetailsSnacklings } do
				check(text, L.detailsLine(w, 1))
			end
			for _, text in { Theme.text.spinDetailsFixed, Theme.text.spinDetailsRounded, Theme.text.spinDetailsSold } do
				local r = L.detailsLine(w, D.noteRows)
				if not TextFit.fits(text, D.text, r.w, r.h, true) then
					table.insert(small, text)
				end
			end
			T.expect(table.concat(small, " | ")).toBe("")
			T.expect(D.text).toBeAtLeast(MIN)
			T.expect(D.text * TextFit.LINE_HEIGHT).toBeAtMost(D.row)
		end)
	end

	T.it("keeps every column apart and inside the row", function()
		for _, area in areas do
			local w = L.oddsDetails(area.w, area.h).list.rect.w
			for _, indent in { false, true } do
				local name, cells = L.detailsColumns(w, #odds.columns, indent)
				local rightEdge = name.x + name.w
				for _, cell in cells do
					T.expect(cell.x).toBeAtLeast(rightEdge)
					rightEdge = cell.x + cell.w
				end
				T.expect(rightEdge).toBeAtMost(w - D.scrollBar)
			end
		end
	end)

	T.it("puts Details on the pack card beside the odds grid, and in SPIN!'s place in the Spin tab", function()
		local card = L.packCard()
		T.expect(card.details.kind).toBe("button")
		T.expect(card.details.rect.x).toBeAtLeast(card.odds.rect.x + card.odds.rect.w)
		T.expect(card.details.rect.y).toBeAtLeast(card.buy.rect.y + card.buy.rect.h)
		T.expect(TextFit.fit(Theme.text.spinDetails, card.details.rect.w - 16, card.details.rect.h - 12, false))
			.toBeAtLeast(MIN)
		for _, packs in { false, true } do
			local boxes = L.spinTab(packs)
			T.expect(boxes.details.rect).toEqual(boxes.spin.rect)
		end
	end)
end)

T.describe("StoreLayout: the Starter Pack's offer strip", function()
	T.it("fits its title, body and button in the narrowest offer strip, like a cash offer", function()
		local O, P = ScreenLayout.SIZE.cashOffer, ScreenLayout.TEXT.cashOffer
		local starter = Monetization.starterPack
		local body =
			Format.template(Theme.text.starterOfferBody, { creature = "Golden Cupcake Cub", count = #starter.gadgets })
		T.expect(starter.creatureId).toBe("cupcake_cub") -- the name above
		local small: { string } = {}
		for _, width in { O.w, O.minW } do
			local textW = width - O.text - O.inset - O.close - ScreenLayout.GAP - O.buy - ScreenLayout.GAP
			if TextFit.fit(Theme.text.starterOfferTitle, textW, P.title, false) < MIN then
				table.insert(small, `title at {width}`)
			end
			if TextFit.fit(body, textW, P.body, true) < MIN then
				table.insert(small, `body at {width}`)
			end
		end
		local button = ScreenLayout.TEXT.button
		local buttonSize = TextFit.fit(
			Theme.text.starterOfferButton,
			O.buy - 2 * button.padX,
			O.h - 2 * O.inset - 2 * button.padY,
			false
		)
		if buttonSize < MIN then
			table.insert(small, "button")
		end
		T.expect(table.concat(small, ", ")).toBe("")
	end)
end)

return nil
