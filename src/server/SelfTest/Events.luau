--!strict
--[[
	Self-test section Events: switches each seasonal event (Config/Seasons.eventThemes) on for a moment with
	LiveOpsService.startEventNow, what `/event <id>` and the host panel run (without the banner), and off again with
	LiveOpsService.endEvents (`/event off <id>`).

	While it runs: SeasonService switched its theme on (workspace attribute SeasonTheme), built the decorations in
	workspace.SeasonDecor within Config/Seasons.maxParts, every one anchored and out of everyone's way (no collisions,
	touches or raycasts), the lighting layers want the theme's mood, and the event's mutation can roll on the belt.
	Once ended: the decorations are gone and the theme is back to what it was. An event that is already running (by its
	dates, or started before the test) is left alone; each of the others takes over from it while it is checked (one
	seasonal event at a time, DECISIONS.md #58), and it comes back after. One that still doesn't come on is noted.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modifiers = require(ReplicatedStorage.Shared.Config.Modifiers)
local Mutations = require(ReplicatedStorage.Shared.Config.Mutations)
local Seasons = require(ReplicatedStorage.Shared.Config.Seasons)
local SeasonRules = require(ReplicatedStorage.Shared.Logic.SeasonRules)
local Services = script.Parent.Parent.Services
local BeltService = require(Services.BeltService)
local LiveOpsService = require(Services.LiveOpsService)
local ModifierService = require(Services.ModifierService)
local SeasonService = require(Services.SeasonService)
local WorldLighting = require(Services.WorldLighting)
local Kit = require(script.Parent.Kit)

-- Long enough never to end by itself while it is checked: the section ends it.
local RUN_SECONDS = 600

-- What is wrong with the decorations of theme `themeId`, and how many parts they have.
local function decorationIssues(themeId: string): ({ string }, number)
	local issues: { string } = {}
	local decor = workspace:FindFirstChild("SeasonDecor")
	if decor == nil then
		return { "workspace.SeasonDecor was not built" }, 0
	end
	if decor:GetAttribute("Theme") ~= themeId then
		table.insert(issues, `SeasonDecor was built for {decor:GetAttribute("Theme")}`)
	end
	local parts, inTheWay = 0, 0
	for _, descendant in decor:GetDescendants() do
		if descendant:IsA("BasePart") then
			parts += 1
			if descendant.CanCollide or descendant.CanTouch or descendant.CanQuery or not descendant.Anchored then
				inTheWay += 1
			end
		end
	end
	if parts == 0 then
		table.insert(issues, "no decorations were built")
	elseif parts > Seasons.maxParts then
		table.insert(issues, `{parts} decoration parts, over the budget of {Seasons.maxParts}`)
	end
	if inTheWay > 0 then
		table.insert(issues, `{inTheWay} decoration parts could get in the way (collide, touch, raycast or fall)`)
	end
	return issues, parts
end

local Section: Kit.Section = {
	name = "Events",
	run = function(ctx: Kit.Context): string
		-- A weather modifier's sky would sit over the theme's mood.
		local running = ModifierService.current()
		if running and Modifiers.modifiers[running].lighting then
			Kit.endModifier()
		end
		local baseline = SeasonService.currentTheme()
		local eventIds: { string } = {}
		for eventId in Seasons.eventThemes do
			table.insert(eventIds, eventId)
		end
		table.sort(eventIds)

		-- Starting a seasonal event ends any other one an admin started (one at a time): each check puts them back.
		local startedBefore = LiveOpsService.startedEvents()
		local started: { string } = {}
		ctx.onCleanup(function()
			for _, eventId in started do
				LiveOpsService.endEvents(eventId)
			end
			LiveOpsService.restoreStartedEvents(startedBefore)
		end)
		local checked, fewest, most = 0, math.huge, 0
		for _, eventId in eventIds do
			local themeId = Seasons.eventThemes[eventId]
			if LiveOpsService.activeEventIds()[eventId] then
				ctx.note(`{eventId} is running already: left as it is`)
				continue
			end
			local event = LiveOpsService.findConfiguredEvent(eventId)
			if event == nil then
				ctx.problem(`{eventId} has a theme in Config/Seasons but no event in Config/LiveOps`)
				continue
			end
			local issues: { string } = {}
			local mark = ctx.mark()
			local ok, err = pcall(LiveOpsService.startEventNow :: (any, number) -> ...any, event, RUN_SECONDS)
			if not ok then
				table.insert(issues, `startEventNow failed: {Kit.short(tostring(err))}`)
			end
			table.insert(started, eventId)
			task.wait(ctx.options.settleSeconds)
			local wanted = SeasonRules.activeTheme(Seasons, LiveOpsService.activeEventIds())
			if wanted ~= themeId then
				ctx.note(`{eventId}: {wanted} is on instead of its theme ({themeId}): not checked`)
			else
				checked += 1
				if SeasonService.currentTheme() ~= themeId or workspace:GetAttribute("SeasonTheme") ~= themeId then
					table.insert(issues, `the theme on is {workspace:GetAttribute("SeasonTheme")}, not {themeId}`)
				end
				local decorIssues, parts = decorationIssues(themeId)
				for _, issue in decorIssues do
					table.insert(issues, issue)
				end
				if parts > 0 then
					fewest, most = math.min(fewest, parts), math.max(most, parts)
				end
				local clock = WorldLighting.clockTime()
				local mood = Kit.expectedClockTime()
				if clock == nil or not Kit.near(clock, mood) then
					table.insert(issues, `the lighting wants clock {clock}, the theme's mood is {mood}`)
				end
				local conditions = BeltService.mutationConditions()
				for _, mutation in Mutations do
					if mutation.eventId == eventId and conditions[eventId] ~= true then
						table.insert(issues, `{mutation.id} Snacklings can't roll on the belt`)
					end
				end
			end

			local endedOk, endErr = pcall(LiveOpsService.endEvents, eventId)
			if not endedOk then
				table.insert(issues, `endEvents failed: {Kit.short(tostring(endErr))}`)
			end
			LiveOpsService.restoreStartedEvents(startedBefore)
			local index = table.find(started, eventId)
			if index then
				table.remove(started, index)
			end
			task.wait(ctx.options.settleSeconds)
			if SeasonService.currentTheme() ~= baseline then
				table.insert(issues, `after it ended the theme is {SeasonService.currentTheme()}, not {baseline}`)
			end
			if baseline == nil and workspace:FindFirstChild("SeasonDecor") ~= nil then
				table.insert(issues, "its decorations stay after it ended")
			end
			for _, message in ctx.take(mark) do
				table.insert(issues, `{message.kind}: {message.text}`)
			end
			for _, issue in issues do
				ctx.problem(`{eventId}: {issue}`)
			end
		end
		if fewest > most then
			return `{checked} events checked`
		end
		return `{checked} events, decorations {fewest}-{most} parts of {Seasons.maxParts}`
	end,
}

return Section
