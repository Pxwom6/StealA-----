--!strict
local T = require("./TestKit")
local Gadgets = require("../src/shared/Config/Gadgets")
local LiveOps = require("../src/shared/Config/LiveOps")
local MapThemes = require("../src/shared/Config/MapThemes")
local Modifiers = require("../src/shared/Config/Modifiers")
local Monetization = require("../src/shared/Config/Monetization")
local Mutations = require("../src/shared/Config/Mutations")
local Theme = require("../src/shared/Config/Theme")
local Format = require("../src/shared/Logic/Format")
local MutationRules = require("../src/shared/Logic/MutationRules")
local ScreenLayout = require("../src/shared/Logic/ScreenLayout")
local TextFit = require("../src/shared/Logic/TextFit")

local S = ScreenLayout.SIZE
local TEXT = ScreenLayout.TEXT

local function spec(name: string): ScreenLayout.DeviceSpec
	for _, device in ScreenLayout.DEVICES do
		if device.name == name then
			return device
		end
	end
	error(`no device {name}`)
end

local function layoutOn(name: string, state: ScreenLayout.HudState): (ScreenLayout.Device, ScreenLayout.Layout)
	local device = ScreenLayout.device(spec(name))
	if state.tutorial then
		device = ScreenLayout.tutorialDevice(device)
	end
	return device, ScreenLayout.layout(device, state)
end

local PHONES = { "640x360 phone", "667x375 phone", "844x390 phone" }

T.describe("ScreenLayout", function()
	T.it("scales like UiKit: 0.85 on phones, by the height on computers, by the width on 4:3 tablets", function()
		T.expect(ScreenLayout.scaleFor(667, 375)).toBe(0.85)
		T.expect(ScreenLayout.scaleFor(1280, 720)).toBeNear(1.3333, 0.001)
		T.expect(ScreenLayout.scaleFor(1024, 768)).toBeNear(1024 / 900, 1e-9)
		T.expect(ScreenLayout.scaleFor(1920, 1080)).toBe(1.35)
		T.expect(ScreenLayout.scaleFor(0 / 0, 0 / 0)).toBe(1)
	end)

	T.it("finds nothing wrong on any of the five screens in any of the busiest states", function()
		T.expect(#ScreenLayout.DEVICES).toBe(5)
		T.expect(table.concat(ScreenLayout.checkAll(), "\n")).toBe("")
	end)

	T.it("keeps the lock, the modifier and the vote out of the play zone on the reference phone", function()
		-- the reviewer's worst case: an event, server luck, a modifier and a vote
		local device, layout =
			layoutOn("667x375 phone", { event = true, luck = true, modifier = true, vote = true, friends = true })
		local zone = ScreenLayout.playZone(device)
		for _, id in { "lock", "modifier", "vote1", "vote2", "vote3", "gear", "friends" } do
			T.expect(ScreenLayout.overlaps(layout.byId[id], zone)).toBe(false)
		end
		-- the lock is a 44 px button in the top-right row, in Roblox's top bar strip
		local lock = ScreenLayout.toPx(device, layout.byId.lock)
		T.expect(lock.y + lock.h).toBeAtMost(58)
		T.expect(lock.h).toBeAtLeast(44)
		T.expect(lock.x).toBeGreaterThan(667 / 2)
	end)

	T.it(
		"ends the top stack above the play zone with an event and a modifier, the usual state, on every phone",
		function()
			for _, name in PHONES do
				local device, layout = layoutOn(name, { event = true, modifier = true, friends = true })
				T.expect(layout.stackBottom).toBeAtMost(ScreenLayout.playZone(device).y)
			end
		end
	)

	T.it("reports overlaps, small buttons, the play zone, Roblox's UI and the screen edge", function()
		local device = ScreenLayout.device(spec("667x375 phone"))
		-- Roblox's UI and the play zone, plus the elements under test
		local roblox: { ScreenLayout.Element } = {}
		for _, e in ScreenLayout.layout(device, {}).elements do
			if e.kind == "core" or e.kind == "zone" then
				table.insert(roblox, e)
			end
		end
		local function problems(elements: { ScreenLayout.Element }): number
			local all = table.clone(roblox)
			for _, e in elements do
				table.insert(all, e)
			end
			return #ScreenLayout.problems(device, all)
		end
		local function button(id: string, x: number, y: number, w: number, h: number): ScreenLayout.Element
			return { id = id, kind = "button", rect = { x = x, y = y, w = w, h = h } }
		end
		T.expect(problems({ button("a", 300, 80, 60, 52) })).toBe(0)
		T.expect(problems({ button("a", 300, 70, 60, 52), button("b", 330, 74, 60, 52) })).toBe(1) -- overlap
		T.expect(problems({ button("a", 300, 80, 60, 30) })).toBe(1) -- 25.5 px tall
		T.expect(problems({ button("a", 380, 200, 60, 52) })).toBe(1) -- in the play zone
		T.expect(problems({ button("a", 760, 80, 60, 52) })).toBe(1) -- off the right edge
		T.expect(problems({ button("a", 100, 10, 60, 52) })).toBe(1) -- under Roblox's top-left buttons
		T.expect(problems({ button("a", 20, 300, 60, 52) })).toBe(1) -- where the thumbstick starts
		local pill = { id = "pill", kind = "info", rect = { x = 300, y = 80, w = 100, h = 30 } }
		local toast = { id = "toast", kind = "overlay", rect = { x = 300, y = 80, w = 100, h = 30 } }
		T.expect(problems({ pill, toast })).toBe(0) -- an overlay may cover a pill
		T.expect(problems({ button("a", 300, 80, 60, 52), toast })).toBe(1) -- but not a button
		T.expect(problems({ { id = "pill", kind = "info", rect = { x = 100, y = 10, w = 60, h = 30 } } })).toBe(1)
		local inside = button("skip", 310, 72, 60, 52) -- a button inside its own pill (the tutorial's Skip)
		inside.parent = "pill"
		T.expect(problems({ { id = "pill", kind = "info", rect = { x = 300, y = 70, w = 200, h = 60 } }, inside }))
			.toBe(0)
	end)

	T.it(
		"keeps the corner row in the top bar on phones, under Roblox's buttons when the player list fills the corner",
		function()
			for _, name in PHONES do
				local _, layout = layoutOn(name, { friends = true })
				T.expect(layout.cornerMoved).toBe(false)
				T.expect(layout.byId.gear.y).toBe(S.corner.top)
			end
			local window, layout = layoutOn("1280x720 window", { friends = true })
			T.expect(layout.cornerMoved).toBe(true)
			T.expect(layout.byId.lock.y).toBeAtLeast(window.topBar)
			T.expect(layout.byId.lock.x).toBe(S.side.left)
			-- the feature grid moves under it
			T.expect(layout.byId.shop.y).toBeAtLeast(layout.byId.lock.y + S.corner.button)
			-- with the player list switched off the corner is free again
			local free = ScreenLayout.layout(ScreenLayout.withoutPlayerList(window), { friends = true })
			T.expect(free.cornerMoved).toBe(false)
			T.expect(free.byId.gear.x + free.byId.gear.w).toBeNear(window.width - ScreenLayout.EDGE, 1e-9)
		end
	)

	T.it("never puts the cash pill under Roblox's top-left buttons", function()
		local wide = ScreenLayout.device({
			name = "wide top bar",
			widthPx = 667,
			heightPx = 375,
			touch = true,
			topBarLeftPx = 250,
		})
		local layout = ScreenLayout.layout(wide, {})
		T.expect(layout.byId.cash.x).toBeAtLeast(wide.topBarLeft + ScreenLayout.EDGE - 1e-9)
		T.expect(#ScreenLayout.problems(wide, layout.elements)).toBe(0)
	end)

	T.it("puts the feature buttons below Roblox's top bar and above the thumbstick on phones", function()
		for _, name in PHONES do
			local device, layout = layoutOn(name, {})
			local thumb = ScreenLayout.thumbstickArea(device) :: ScreenLayout.Rect
			for _, id in { "shop", "rebirth", "rewards", "snackdex" } do
				local r = layout.byId[id]
				T.expect(r.y).toBeAtLeast(device.topBar)
				T.expect(r.y + r.h).toBeAtMost(thumb.y)
				T.expect(r.h * device.scale).toBeAtLeast(ScreenLayout.MIN_TOUCH)
			end
		end
	end)

	T.it("keeps TAG above the jump button, and below the player list on a tablet", function()
		for _, name in { "640x360 phone", "667x375 phone", "844x390 phone", "1024x768 tablet" } do
			local device = ScreenLayout.device(spec(name))
			local tag = ScreenLayout.tagButton(device)
			local jump = ScreenLayout.jumpButton(device) :: ScreenLayout.Rect
			T.expect(tag.y + tag.h).toBeAtMost(jump.y)
			local list = ScreenLayout.playerListRect(device)
			if list then
				T.expect(tag.y).toBeAtLeast(list.y + list.h)
			end
		end
		-- the reference phone keeps it where it was (x 626-746, y 136-256)
		local tag = ScreenLayout.tagButton(ScreenLayout.device(spec("667x375 phone")))
		T.expect(tag.x).toBeNear(625.7, 0.01)
		T.expect(tag.y).toBeNear(136.18, 0.01)
	end)

	T.it("has a gadget button for every gadget on every screen, beside TAG", function()
		T.expect(S.gadget.slots).toBeAtLeast(#Gadgets.order)
		for _, entry in ScreenLayout.DEVICES do
			local device = ScreenLayout.device(entry)
			local slots = ScreenLayout.gadgetSlots(device, #Gadgets.order)
			T.expect(#slots).toBe(#Gadgets.order)
			local tag = ScreenLayout.tagButton(device)
			for _, r in slots do
				T.expect(r.w * device.scale).toBeAtLeast(ScreenLayout.MIN_TOUCH)
				-- near TAG: within a button and a gap of its square on every side, or two on the side away from the jump
				local reach = 2 * (S.gadget.size + S.gadget.gap) + 1e-6
				T.expect(r.x + r.w).toBeAtLeast(tag.x - reach)
				T.expect(r.x).toBeAtMost(tag.x + tag.w + reach)
				T.expect(r.y + r.h).toBeAtLeast(tag.y - reach)
				T.expect(r.y).toBeAtMost(tag.y + tag.h + reach)
			end
		end
	end)

	T.it("keeps the gadget buttons where they are whatever else shows or is bought", function()
		for _, entry in ScreenLayout.DEVICES do
			local device = ScreenLayout.device(entry)
			local all = ScreenLayout.gadgetSlots(device, S.gadget.slots)
			for count = 1, S.gadget.slots do
				local some = ScreenLayout.gadgetSlots(device, count)
				T.expect(#some).toBe(count)
				for index, r in some do
					T.expect(r).toEqual(all[index]) -- buying another gadget never moves the others
				end
			end
			for _, scenario in ScreenLayout.SCENARIOS do
				if scenario.state.tutorial == nil then
					local state = table.clone(scenario.state)
					state.gadgets = S.gadget.slots
					local layout = ScreenLayout.layout(device, state)
					for index, r in all do
						T.expect(layout.byId["gadget" .. index]).toEqual(r) -- nor a pill, a toast or the vote
					end
				end
			end
		end
	end)

	T.it("keeps the gadget buttons away from the jump button and its thumb", function()
		for _, entry in ScreenLayout.DEVICES do
			local device = ScreenLayout.device(entry)
			local jump = ScreenLayout.jumpButton(device)
			if jump then
				local jx, jy = jump.x + jump.w / 2, jump.y + jump.h / 2
				for _, r in ScreenLayout.gadgetSlots(device, S.gadget.slots) do
					local dx = math.max(r.x - jx, 0, jx - (r.x + r.w))
					local dy = math.max(r.y - jy, 0, jy - (r.y + r.h))
					T.expect(math.sqrt(dx * dx + dy * dy)).toBeAtLeast(jump.w / 2 + S.vote.jumpGap - 1e-6)
				end
			end
		end
		-- the reference phone: under TAG, right-aligned with it, the fourth beside it (x 568-620, y 204-256)
		local device = ScreenLayout.device(spec("667x375 phone"))
		local tag = ScreenLayout.tagButton(device)
		local slots = ScreenLayout.gadgetSlots(device, 4)
		T.expect(slots[1].x + slots[1].w).toBeNear(tag.x + tag.w, 1e-6)
		T.expect(slots[1].y).toBeNear(tag.y + tag.h + S.gadget.gap, 1e-6)
		T.expect(slots[4].x + slots[4].w).toBeNear(tag.x - S.gadget.gap, 1e-6)
	end)

	T.it("lets announcements and the steal alert move aside for the gadget buttons", function()
		for _, entry in ScreenLayout.DEVICES do
			local device = ScreenLayout.device(entry)
			local state = table.clone(ScreenLayout.SCENARIOS[1].state)
			state.gadgets = S.gadget.slots
			state.titleCard = true
			local layout = ScreenLayout.layout(device, state)
			for _, id in { "announcement", "titleCard", "stealAlert" } do
				for index = 1, S.gadget.slots do
					T.expect(ScreenLayout.overlaps(layout.byId[id], layout.byId["gadget" .. index])).toBe(false)
				end
			end
			T.expect(table.concat(ScreenLayout.problems(device, layout.elements), "\n")).toBe("")
		end
	end)

	T.it("switches the player list off for the tutorial only when its banner can't clear it", function()
		-- the 1280x720 window has room left of the list for the centred banner
		local window = ScreenLayout.device(spec("1280x720 window"))
		T.expect(ScreenLayout.tutorialDevice(window).playerList).toBe(window.playerList)
		local layout = ScreenLayout.layout(window, { tutorial = "full" })
		T.expect(layout.byId.tutorial.w).toBeAtLeast(S.tutorial.minW)
		T.expect(ScreenLayout.overlaps(layout.byId.tutorial, ScreenLayout.playerListRect(window) :: ScreenLayout.Rect))
			.toBe(false)
		-- the tablet and a small window don't: the list goes while the banner shows, and the banner is full width
		local small = ScreenLayout.device({
			name = "800x600 window",
			widthPx = 800,
			heightPx = 600,
			touch = false,
			playerListPx = 358,
		})
		for _, device in { ScreenLayout.device(spec("1024x768 tablet")), small } do
			local hidden = ScreenLayout.tutorialDevice(device)
			T.expect(hidden.playerList).toBe(0)
			local tutorial = ScreenLayout.layout(hidden, { tutorial = "full", tag = true })
			T.expect(tutorial.byId.tutorial.w).toBe(S.tutorial.w)
			T.expect(table.concat(ScreenLayout.problems(hidden, tutorial.elements), "\n")).toBe("")
		end
	end)

	T.it("hides the status pills while the band shows the tutorial or a cash offer", function()
		local _, tutorial = layoutOn("667x375 phone", { tutorial = "full", event = true, modifier = true })
		T.expect(tutorial.statusShown).toBe(false)
		T.expect(tutorial.byId.modifier).toBeNil()
		local _, offer = layoutOn("667x375 phone", { cashOffer = true, event = true, modifier = true })
		T.expect(offer.byId.event).toBeNil()
		T.expect(offer.byId.cashOfferBuy ~= nil).toBe(true)
	end)

	T.it("reserves the player list's width on computers and tablets, not on phones", function()
		T.expect(ScreenLayout.playerListWidth(true, true, 667, 375, 2)).toBe(0)
		T.expect(ScreenLayout.playerListWidth(false, false, 1920, 1080, 2)).toBe(0)
		local two = ScreenLayout.playerListWidth(true, false, 1920, 1080, 2)
		T.expect(two).toBe(358)
		T.expect(ScreenLayout.playerListWidth(true, false, 1920, 1080, 4)).toBeGreaterThan(two)
		T.expect(ScreenLayout.playerListWidth(true, false, 1920, 1080, 50)).toBeAtMost(500)
		T.expect(ScreenLayout.playerListWidth(true, true, 1024, 768, 2)).toBe(two)
	end)
end)

-- Text stays readable: nothing in the HUD below TEXT.minSize (12 UI, 10 px on the smallest phones), measured with
-- FredokaOne's metrics in the boxes the controllers give it.
T.describe("ScreenLayout text", function()
	local MIN = TEXT.minSize

	local function fit(text: string, w: number, h: number, wrapped: boolean): number
		return TextFit.fit(text, w, h, wrapped)
	end

	T.it("fits every map's name on two lines and its mutation on one in the narrowest vote button", function()
		local narrowest = math.huge
		for _, name in PHONES do
			local strip = ScreenLayout.voteStrip(ScreenLayout.device(spec(name)))
			narrowest = math.min(narrowest, ScreenLayout.voteChoice(strip, 1, 3).w)
		end
		local w = narrowest - 2 * TEXT.vote.padX
		local small: { string } = {}
		for _, id in MapThemes.order do
			local theme = MapThemes.themes[id]
			if fit(theme.displayName, w, TEXT.vote.name, true) < MIN then
				table.insert(small, theme.displayName)
			end
			local signature = MutationRules.forMap(Mutations, id)
			if signature then
				local line = Format.template(Theme.text.mapVoteMutation, { mutation = signature.displayName })
				if fit(line, w, TEXT.vote.mutation, false) < MIN then
					table.insert(small, line)
				end
			end
		end
		T.expect(table.concat(small, ", ")).toBe("")
	end)

	T.it("fits every event banner on two lines in the event pill", function()
		local small: { string } = {}
		for _, event in LiveOps.events do
			local banner = event.bannerText
			if banner and fit(banner, S.event.w - 2 * TEXT.event.padX, TEXT.event.banner, true) < MIN then
				table.insert(small, banner)
			end
		end
		T.expect(table.concat(small, ", ")).toBe("")
	end)

	T.it("fits every modifier, lock and luck line in its button or chip", function()
		local small: { string } = {}
		local function check(text: string, w: number, h: number, wrapped: boolean)
			if fit(text, w, h, wrapped) < MIN then
				table.insert(small, text)
			end
		end
		local button = TEXT.button
		for _, def in Modifiers.modifiers do
			local text =
				Format.template(Theme.text.modifierChip, { icon = def.icon, name = def.displayName, time = "4:59" })
			check(text, S.modifier.w - 2 * button.padX, S.modifier.h - 2 * button.padY, true)
		end
		for _, line in
			{
				Theme.text.lockPillReady,
				Format.template(Theme.text.lockPillLocked, { time = "1:30" }),
				Format.template(Theme.text.lockPillCooldown, { time = "1:30" }),
				Format.template(Theme.text.lockPillToken, { count = 99 }),
			}
		do
			check("🔒 " .. line, S.corner.lock - 2 * button.padX, S.corner.button - 2 * button.padY, true)
		end
		for _, vars in { { multiplier = "1.5", time = "59:59" }, { multiplier = "10", time = "2d 23h" } } do
			check(
				Format.template(Theme.text.luckBanner, vars),
				S.luck.w - 2 * TEXT.luck.padX,
				S.luck.h - 2 * TEXT.luck.padY,
				false
			)
		end
		T.expect(table.concat(small, ", ")).toBe("")
	end)

	T.it("fits every game text in a toast: one line when it reads well, else two", function()
		local small: { string } = {}
		local P = TEXT.toast
		for key, template in (Theme.text :: any) :: { [string]: string } do
			local text = string.gsub(template, "{[%w_]+}", "Abcdefgh")
			local h = ScreenLayout.toastHeight(text)
			local size = fit(text, S.toast.w - 2 * P.padX, h - 2 * P.padY, h == S.toast.tall)
			if size < MIN then
				table.insert(small, key)
			end
		end
		T.expect(table.concat(small, ", ")).toBe("")
		-- the reviewer's examples wrap onto the tall toast
		T.expect(ScreenLayout.toastHeight(Theme.text.spinNotReady)).toBe(S.toast.tall)
		T.expect(ScreenLayout.toastHeight(Theme.text.codeBaseFull)).toBe(S.toast.tall)
		T.expect(ScreenLayout.toastHeight("Bought it!")).toBe(S.toast.h)
	end)

	T.it("fits every cash pack's offer in the narrowest offer strip", function()
		local O, P = S.cashOffer, TEXT.cashOffer
		local small: { string } = {}
		for key, product in Monetization.products do
			if product.kind ~= "Cash" then
				continue
			end
			local copy = (Theme.store :: any)[key]
			for _, width in { O.w, O.minW } do
				local textW = width - O.text - O.inset - O.close - ScreenLayout.GAP - O.buy - ScreenLayout.GAP
				local title = Format.template(Theme.text.cashOfferTitle, { amount = "$999.9K" })
				local body = Format.template(Theme.text.cashOfferBody, { pack = copy.name, amount = "$999.9K" })
				if fit(title, textW, P.title, false) < MIN or fit(body, textW, P.body, true) < MIN then
					table.insert(small, `{copy.name} at {width}`)
				end
			end
		end
		T.expect(table.concat(small, ", ")).toBe("")
	end)

	T.it("fits the base-full warning in the Spin and Gifts tabs", function()
		local box = TEXT.prizesBaseFull
		T.expect(fit(Theme.text.prizesBaseFull, box.spin.w, box.spin.h, true)).toBeAtLeast(MIN)
		T.expect(fit(Theme.text.prizesBaseFull, box.gifts.w, box.gifts.h, false)).toBeAtLeast(MIN)
	end)

	T.it("fits every modifier's announcement in the narrowest banner", function()
		local narrowest = math.huge
		for _, device in ScreenLayout.DEVICES do
			local d = ScreenLayout.device(device)
			local layout = ScreenLayout.layout(d, ScreenLayout.SCENARIOS[1].state)
			narrowest = math.min(narrowest, layout.byId.announcement.w)
		end
		local small: { string } = {}
		for _, def in Modifiers.modifiers do
			local text = Format.template(
				Theme.text.modifierStarted,
				{ icon = def.icon, name = def.displayName, description = def.description }
			)
			local size = fit(text, narrowest - 2 * TEXT.banner.padX, S.banner.h - 2 * TEXT.banner.padY, true)
			if size < MIN then
				table.insert(small, def.displayName)
			end
		end
		T.expect(table.concat(small, ", ")).toBe("")
	end)
end)

return nil
