--!strict
--[[
	The HUD layout check (DECISIONS.md #47): where every HUD element lands on the five screens the game is checked on
	(Logic/ScreenLayout.DEVICES: 640x360, 667x375, 844x390 phones, a 1024x768 tablet, a 1280x720 window), in the busiest
	states (ScreenLayout.SCENARIOS), and what is wrong with it. HudController places the real frames with the same
	functions, so this is what players see. CI runs it; it exits with an error when anything overlaps, leaves the
	screen, sits in the play zone or is too small to tap. The unit tests (tests/ScreenLayout.spec.luau) check the same.

	Then the dialogs laid out by pure modules (the Style dialog, the What's New card, the host panel): each must fit
	every screen below Roblox's top bar. What is inside them (touch targets, text sizes) is checked by their unit tests
	(tests/StyleLayout.spec.luau, tests/NewsLayout.spec.luau, tests/HostPanelLayout.spec.luau).

	Usage: lune run tools/layoutCheck.luau [--all]   (--all lists every element in every scenario, in screen pixels)
]]

local process = require("@lune/process")

local HostPanelLayout = require("../src/shared/Logic/HostPanelLayout")
local NewsLayout = require("../src/shared/Logic/NewsLayout")
local ScreenLayout = require("../src/shared/Logic/ScreenLayout")
local StyleLayout = require("../src/shared/Logic/StyleLayout")

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

type FitCheck = (width: number, height: number, topBar: number, margin: number) -> { string }
local DIALOGS: { { name: string, fit: FitCheck } } = {
	{ name = "Style dialog", fit = StyleLayout.fitProblems },
	{ name = "What's New card", fit = NewsLayout.fitProblems },
	{ name = "host panel", fit = HostPanelLayout.fitProblems },
}
print("Dialogs (below Roblox's top bar, 8 UI from the sides):")
for _, spec in ScreenLayout.DEVICES do
	local device = ScreenLayout.device(spec)
	for _, dialog in DIALOGS do
		local problems = dialog.fit(device.width, device.height, device.topBar, ScreenLayout.EDGE)
		total += #problems
		local verdict = if #problems == 0 then "ok" else table.concat(problems, "; ")
		print(string.format("  %-16s %-16s %s", spec.name, dialog.name, verdict))
	end
end

if total > 0 then
	print(`\n{total} layout problems`)
	process.exit(1)
end
print("\nHUD and dialog layout: no problems on any screen")
