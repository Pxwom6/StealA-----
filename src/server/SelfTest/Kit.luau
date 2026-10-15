--!strict
--[[
	What every section of the Studio self-test gets (SelfTest/init.luau runs them; README "Studio self-test"), and
	small helpers they share.

	A section is { name, run(ctx) }: `run` checks one part of the game in the real engine, reports each thing that is
	wrong with ctx.problem (something broken), ctx.warning (worth a look) or ctx.note (for the full report only), and
	returns a short detail for its one-line verdict ("23 maps, scenery 553-748 parts of 1500"). Whatever the game logs
	meanwhile is captured: ctx.mark() / ctx.take(mark) hand a section the errors and warnings logged since a point (to
	say which map or modifier they came with); any it doesn't take count against it when it ends. Anything it changes
	gets undone by a step it registers with ctx.onCleanup, which runs at the end even when a section fails.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapThemes = require(ReplicatedStorage.Shared.Config.MapThemes)
local Modifiers = require(ReplicatedStorage.Shared.Config.Modifiers)
local Seasons = require(ReplicatedStorage.Shared.Config.Seasons)
local BossService = require(script.Parent.Parent.Services.BossService)
local DropService = require(script.Parent.Parent.Services.DropService)
local MapThemeService = require(script.Parent.Parent.Services.MapThemeService)
local ModifierService = require(script.Parent.Parent.Services.ModifierService)
local SeasonService = require(script.Parent.Parent.Services.SeasonService)

local Kit = {}

-- Timings; studio/SelfTest.luau's runner can override each with an attribute of the same name (the offline harness
-- makes them short).
export type Options = {
	holdSeconds: number, -- how long each modifier runs before it is checked and ended
	settleSeconds: number, -- after a map switch or an event starting / ending, for errors to surface
	assetTimeoutSeconds: number, -- how long the asset requests may take in all
	dropMarginSeconds: number, -- how long past a drop modifier's first drop to wait for it
	batch: number, -- Snacklings built at once
	sections: { [string]: boolean }?, -- only these sections (all when nil)
}

export type MessageKind = "error" | "warning" | "output"

-- Something the game logged while a section ran: an Error, a Warning, or other output with "error" in it.
export type Message = { text: string, kind: MessageKind, section: string, handled: boolean }

export type Context = {
	options: Options,
	section: string,
	problem: (text: string) -> (),
	warning: (text: string) -> (),
	note: (text: string) -> (),
	mark: () -> number,
	-- The errors and warnings logged since `mark`, from now on the caller's to report.
	take: (mark: number) -> { Message },
	onCleanup: (step: () -> ()) -> (),
	now: () -> number, -- server time
}

export type Section = { name: string, run: (ctx: Context) -> string }

-- What Studio logs, with Studio API access off, that says nothing about the game: DataStore requests refused, Roblox's
-- own CorePackages, and PlayerLifecycle's Max Players warning (a Studio test server has its own Max Players; the live
-- place's is 8). Lower case, found anywhere in a message. The report lists them apart and nothing counts them.
Kit.STUDIO_NOISE = table.freeze({
	"studioaccesstoapisnotallowed",
	"studio access to api",
	"corepackages",
	"[playerlifecycle] max players is",
})

function Kit.isStudioNoise(text: string): boolean
	local lower = string.lower(text)
	for _, pattern in Kit.STUDIO_NOISE do
		if string.find(lower, pattern, 1, true) then
			return true
		end
	end
	return false
end

-- One line of at most `max` characters (default 160).
function Kit.short(text: string, max: number?): string
	local line = string.gsub(string.gsub(text, "%s+", " "), "^ ", "")
	local limit = max or 160
	if #line > limit then
		return string.sub(line, 1, limit - 3) .. "..."
	end
	return line
end

function Kit.near(a: number, b: number, epsilon: number?): boolean
	return math.abs(a - b) <= (epsilon or 1e-3)
end

function Kit.countParts(root: Instance?): number
	if root == nil then
		return 0
	end
	local count = 0
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			count += 1
		end
	end
	return count
end

-- Waits (polling every `step` seconds, default 0.1) until `done()` or until server time `deadline`. Returns done().
function Kit.waitUntil(done: () -> boolean, deadline: number, step: number?): boolean
	while not done() and workspace:GetServerTimeNow() < deadline do
		task.wait(step or 0.1)
	end
	return done()
end

-- The time of day the lighting layers want now, by WorldLighting's rule: a weather modifier's sky over a seasonal
-- theme's mood over the map's own.
function Kit.expectedClockTime(): number
	local modifierId = ModifierService.current()
	local modifier = if modifierId then Modifiers.modifiers[modifierId] else nil
	if modifier and modifier.lighting then
		return modifier.lighting.clockTime
	end
	local seasonId = SeasonService.currentTheme()
	local season = if seasonId then Seasons.themes[seasonId] else nil
	local mood = if season then season.lighting else nil
	if mood then
		return mood.clockTime
	end
	return MapThemes.themes[MapThemeService.current()].lighting.clockTime
end

-- "a, b, c" of at most `max` entries (default 3), then "(+N more)".
function Kit.list(items: { string }, max: number?): string
	local limit = max or 3
	local shown: { string } = {}
	for index = 1, math.min(#items, limit) do
		table.insert(shown, items[index])
	end
	local text = table.concat(shown, ", ")
	if #items > limit then
		text ..= ` (+{#items - limit} more)`
	end
	return text
end

-- Ends the running modifier (if any) and takes away whatever its drops left (crates, coins, runaways, a giant).
function Kit.endModifier()
	if ModifierService.current() ~= nil then
		ModifierService.stopModifier()
	end
	DropService.clear()
	BossService.dismiss()
end

return Kit
