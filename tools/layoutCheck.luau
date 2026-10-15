--!strict
--[[
	The HUD layout check (DECISIONS.md #47): where every HUD element lands on the five screens the game is checked on
	(Logic/ScreenLayout.DEVICES: 640x360, 667x375, 844x390 phones, a 1024x768 tablet, a 1280x720 window), in the busiest
	states (ScreenLayout.SCENARIOS), and what is wrong with it. HudController places the real frames with the same
	functions, so this is what players see. CI runs it; it exits with an error when anything overlaps, leaves the
	screen, sits in the play zone or is too small to tap. The unit tests (tests/ScreenLayout.spec.luau) check the same.
	Then the store additions' dialogs on the same screens (Logic/StoreLayout: the Spin tab with and without the Lucky
	Spin pack buttons, a pack's Shop card; tests/StoreLayout.spec.luau proves their text sizes).

	Usage: lune run tools/layoutCheck.luau [--all]   (--all lists every element in every scenario, in screen pixels)
]]

local process = require("@lune/process")

local ScreenLayout = require("../src/shared/Logic/ScreenLayout")
local StoreLayout = require("../src/shared/Logic/StoreLayout")

local verbose = table.find(process.args, "--all") ~= nil

local function span(a: number, b: number): string
	return string.format("%4.0f-%-4.0f", a, b)
end

local function px(device: ScreenLayout.Device, r: ScreenLayout.Rect): string
	local p = ScreenLayout.toPx(device, r)
	return `x {span(p.x, p.x + p.w)} y {span(p.y, p.y + p.h)}`
end

local IMPORTANT = {
	"cash",
	"lock",
	"gear",
	"shop",
	"snackdex",
	"tutorial",
	"skip",
	"cashOfferBuy",
	"modifier",
	"tag",
	"gadget1",
	"gadget2",
	"gadget3",
	"gadget4",
}

local total = 0
for _, spec in ScreenLayout.DEVICES do
	local base = ScreenLayout.device(spec)
	local zone = ScreenLayout.playZone(base)
	print(
		string.format(
			"%s: UI scale %.3f, HUD %.0f x %.0f UI, play zone px %s",
			spec.name,
			base.scale,
			base.width,
			base.height,
			px(base, zone)
		)
	)
	for _, scenario in ScreenLayout.SCENARIOS do
		local device = ScreenLayout.scenarioDevice(spec, scenario)
		local layout = ScreenLayout.layout(device, scenario.state)
		local problems = ScreenLayout.problems(device, layout.elements)
		total += #problems
		local stackPx = (device.top + layout.stackBottom * device.scale)
		local hidden = if device.playerList ~= base.playerList then ", player list hidden" else ""
		print(
			string.format(
				"  %-28s %s, stack ends at %3.0f px (%2.0f%%)%s",
				scenario.name,
				if #problems == 0 then "ok" else `{#problems} PROBLEMS`,
				stackPx,
				100 * stackPx / spec.heightPx,
				hidden
			)
		)
		for _, element in layout.elements do
			local important = table.find(IMPORTANT, element.id) ~= nil or string.match(element.id, "^vote%d") ~= nil
			if verbose or (important and scenario == ScreenLayout.SCENARIOS[1]) then
				print(string.format("      %-14s %-7s px %s", element.id, element.kind, px(device, element.rect)))
			end
		end
		for _, problem in problems do
			print("      !! " .. problem)
		end
	end
end

-- The store additions' dialogs (Logic/StoreLayout): the Rewards panel and the Shop fit below Roblox's top bar, and the
-- Spin tab's buttons (SPIN!, Odds, the Lucky Spin pack buttons) land on screen as full touch targets, with and without
-- the packs.
print("\nStore dialogs:")
for _, spec in ScreenLayout.DEVICES do
	local device = ScreenLayout.device(spec)
	local problems = StoreLayout.fitProblems(device.width, device.height, device.topBar, StoreLayout.MARGIN)
	local onScreen, placed =
		StoreLayout.screenProblems(device.width, device.height, device.topBar, device.scale, ScreenLayout.MIN_TOUCH)
	for _, problem in onScreen do
		table.insert(problems, problem)
	end
	local content = StoreLayout.content(StoreLayout.REWARDS)
	for _, packs in { false, true } do
		for _, problem in StoreLayout.problems(StoreLayout.spinTab(packs), content.w, content.h) do
			table.insert(problems, `Spin tab: {problem}`)
		end
	end
	local card, height = StoreLayout.packCard()
	for _, problem in StoreLayout.problems(card, StoreLayout.CARD.w, height) do
		table.insert(problems, `Lucky Spin pack card: {problem}`)
	end
	total += #problems
	print(string.format("  %-16s %s", spec.name, if #problems == 0 then "ok" else `{#problems} PROBLEMS`))
	for _, id in { "spin", "oddsButton", "pack1+packs", "pack2+packs" } do
		local r = placed[id]
		if r and (verbose or spec == ScreenLayout.DEVICES[2]) then
			local x, y = device.left + r.x * device.scale, device.top + r.y * device.scale
			print(
				string.format(
					"      %-14s px x %s y %s",
					id,
					span(x, x + r.w * device.scale),
					span(y, y + r.h * device.scale)
				)
			)
		end
	end
	for _, problem in problems do
		print("      !! " .. problem)
	end
end

if total > 0 then
	print(`\n{total} layout problems`)
	process.exit(1)
end
print("\nHUD and store dialogs: no problems on any screen")
