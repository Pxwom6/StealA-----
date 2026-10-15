--!strict
--[[
	What's New (Config/Updates): the newest update, who gets its card when they join, remembering it was seen, and
	validation. Pure: no Roblox APIs.

	A returning player sees the newest update's card once: the flag news_<number> remembers it (only the newest is
	kept, so a save never collects old ones). A brand-new player gets the tutorial instead, and the update they started
	in counts as seen: the card is for what changed since a player last played. The same goes for a player still in
	the tutorial when they join.
]]

local Types = require("../Types")

type UpdateDef = Types.UpdateDef

local UpdateRules = {}

UpdateRules.FLAG_PREFIX = "news_"
UpdateRules.MIN_HIGHLIGHTS = 3
UpdateRules.MAX_HIGHLIGHTS = 5
UpdateRules.TITLE_LENGTH = 40 -- characters
UpdateRules.HIGHLIGHT_LENGTH = 64

-- What happens when a player joins: show the newest update's card, count it as seen without showing it, or nothing.
export type JoinDecision = "show" | "markSeen" | "none"

function UpdateRules.flagKey(number: number): string
	return UpdateRules.FLAG_PREFIX .. tostring(number)
end

-- The update with the highest number, or nil when there are none.
function UpdateRules.latest(config: Types.UpdatesConfig): UpdateDef?
	local best: UpdateDef? = nil
	for _, def in config.list do
		if best == nil or def.number > best.number then
			best = def
		end
	end
	return best
end

function UpdateRules.hasSeen(flags: { [string]: boolean }, number: number): boolean
	return flags[UpdateRules.flagKey(number)] == true
end

-- The join decision for update `latest` (nil: no updates). `firstSession`: the save is new (never saved before);
-- `tutorialRunning`: the player is (still) in the first-time tutorial.
function UpdateRules.onJoin(
	flags: { [string]: boolean },
	latest: number?,
	firstSession: boolean,
	tutorialRunning: boolean
): JoinDecision
	if latest == nil or UpdateRules.hasSeen(flags, latest) then
		return "none"
	end
	if firstSession or tutorialRunning then
		return "markSeen"
	end
	return "show"
end

-- Remembers update `number` as seen: sets news_<number> and clears every older news_ flag.
function UpdateRules.markSeen(flags: { [string]: boolean }, number: number)
	local prefix = UpdateRules.FLAG_PREFIX
	for key in table.clone(flags) do
		if string.sub(key, 1, #prefix) == prefix then
			flags[key] = nil
		end
	end
	flags[UpdateRules.flagKey(number)] = true
end

local function validDate(date: string): boolean
	local year, month, day = string.match(date, "^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
	if year == nil or month == nil or day == nil then
		return false
	end
	local m, d = tonumber(month) :: number, tonumber(day) :: number
	return tonumber(year) :: number >= 2024 and m >= 1 and m <= 12 and d >= 1 and d <= 31
end

local function line(text: string, maxLength: number): boolean
	local length = utf8.len(text)
	return length ~= nil and length >= 1 and length <= maxLength and string.find(text, "[%c<>]") == nil
end

-- True when `text` starts with an emoji (anything outside ASCII, like TextFit counts them).
local function startsWithEmoji(text: string): boolean
	local ok, first = pcall(utf8.codepoint, text, 1)
	return ok and type(first) == "number" and first > 127
end

-- Problems with Config/Updates (an empty list means valid): whole positive numbers, newest first and never repeated,
-- real dates, a short title and 3 to 5 short highlight lines, each starting with an emoji.
function UpdateRules.validate(config: Types.UpdatesConfig): { string }
	local problems: { string } = {}
	local previous: number? = nil
	for index, def in config.list do
		local name = `update {index} (#{def.number})`
		if not (def.number >= 1 and def.number % 1 == 0 and def.number < 1e6) then
			table.insert(problems, `{name} needs a whole number of 1 or more`)
		elseif previous ~= nil and def.number >= previous then
			table.insert(
				problems,
				`{name} must come after a higher number: the newest goes first, numbers never repeat`
			)
		end
		previous = def.number
		if not validDate(def.date) then
			table.insert(problems, `{name} date {def.date} must be YYYY-MM-DD`)
		end
		if not line(def.title, UpdateRules.TITLE_LENGTH) then
			table.insert(problems, `{name} needs a title of 1 to {UpdateRules.TITLE_LENGTH} characters, one line`)
		end
		local count = #def.highlights
		if count < UpdateRules.MIN_HIGHLIGHTS or count > UpdateRules.MAX_HIGHLIGHTS then
			table.insert(
				problems,
				`{name} needs {UpdateRules.MIN_HIGHLIGHTS} to {UpdateRules.MAX_HIGHLIGHTS} highlights`
			)
		end
		for i, text in def.highlights do
			if not line(text, UpdateRules.HIGHLIGHT_LENGTH) then
				table.insert(
					problems,
					`{name} highlight {i} must be one line of 1 to {UpdateRules.HIGHLIGHT_LENGTH} characters`
				)
			elseif not startsWithEmoji(text) then
				table.insert(problems, `{name} highlight {i} should start with an emoji`)
			end
		end
	end
	return problems
end

return UpdateRules
