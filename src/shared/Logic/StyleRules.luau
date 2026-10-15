--!strict
--[[
	Titles and base skins (Config/Titles, Config/Skins): what a player has unlocked, what they wear, the Style dialog's
	view, how a skin's trims share a base with VIP's gold, and validation. Pure: no Roblox APIs; configs and texts are
	passed in.

	Unlocking reads what the save already keeps (AchievementRules.context for rebirths and Snackdex tiers, the ach_<id>
	flags for achievements), so nothing new is saved for it and existing players have their titles the first time they
	join. An achievement's title stays unlocked once its flag is set, even if its goal later grows (Globetrotter asks
	for every map, and maps are added).

	Wearing is a flag: title_<id> and skin_<id>, at most one of each. `equip` clears the others; `normalize` repairs a
	save holding more than one, an id the config no longer has, or one that is no longer unlocked. No title flag means
	no title; no skin flag means the default skin (Classic), which is never stored as a flag.
]]

local Types = require("../Types")
local AchievementRules = require("./AchievementRules")
local Format = require("./Format")

type TitleDef = Types.TitleDef
type SkinDef = Types.SkinDef
type StyleUnlock = Types.StyleUnlock

local StyleRules = {}

StyleRules.TITLE_PREFIX = "title_"
StyleRules.SKIN_PREFIX = "skin_"
StyleRules.ID_LENGTH = 32
StyleRules.TITLE_LENGTH = 16 -- characters of a title's text: it must fit a nametag on a phone
StyleRules.NAME_LENGTH = 16 -- characters of a skin's name
-- A title's colour against its dark outline: relative luminance 0.3 is a contrast ratio of about 6:1 or better.
StyleRules.MIN_TITLE_LUMINANCE = 0.3
-- Every floor colour of a skin stays at least this far (redmean colour distance, 0-765) from the collect pads' green,
-- which sit on the floor: the Classic floors, blended with each plot's colour, are 164 or more.
StyleRules.MIN_PAD_CONTRAST = 150
StyleRules.MAX_TILE_COLORS = 8

-- Floor tiles and the rug are decoration (they never collide; players stand on the plot's invisible floor), so any
-- material that reads as a floor will do: no glowing, see-through or force-field ones.
StyleRules.FLOOR_MATERIALS = table.freeze({
	SmoothPlastic = true,
	Plastic = true,
	CeramicTiles = true,
	Marble = true,
	Granite = true,
	Slate = true,
	Concrete = true,
	Brick = true,
	Cobblestone = true,
	Pebble = true,
	Pavement = true,
	WoodPlanks = true,
	Wood = true,
	Fabric = true,
	Sand = true,
	Foil = true,
	Metal = true,
	DiamondPlate = true,
} :: { [string]: boolean })

-- The wall tops are solid (players can stand on them), so nothing slippery (Ice, Glacier) or see-through.
StyleRules.TRIM_MATERIALS = table.freeze({
	SmoothPlastic = true,
	Plastic = true,
	Neon = true,
	Foil = true,
	Metal = true,
	Marble = true,
	Granite = true,
	Slate = true,
	Concrete = true,
	Brick = true,
	WoodPlanks = true,
	Wood = true,
	Fabric = true,
	DiamondPlate = true,
} :: { [string]: boolean })

export type Kind = "title" | "skin"

-- What unlocking reads: the save's counts, its flags, the achievements and rarities by id.
export type Unlocks = {
	ctx: AchievementRules.Context,
	flags: { [string]: boolean },
	achievements: { [string]: Types.AchievementDef },
	rarities: { [string]: Types.RarityDef },
	all: boolean?, -- Studio's /style all: everything counts as unlocked
}

-- Where a base's trims get their look (MapBuilder.paintPlot): the skin's own trim, VIP's gold, or the plain wall trim.
export type TrimSource = "skin" | "vip" | "wall"

function StyleRules.flagKey(prefix: string, id: string): string
	return prefix .. id
end

-- Achievements by id, for Unlocks.achievements.
function StyleRules.achievementsById(config: Types.AchievementsConfig): { [string]: Types.AchievementDef }
	local byId: { [string]: Types.AchievementDef } = {}
	for _, def in config.list do
		byId[def.id] = def
	end
	return byId
end

-- How far a save is towards `unlock`: (progress, target). Progress never goes past the target.
function StyleRules.progress(unlock: StyleUnlock, u: Unlocks): (number, number)
	if unlock.kind == "free" then
		return 1, 1
	elseif unlock.kind == "achievement" then
		local def = u.achievements[unlock.id]
		local flagged = u.flags[AchievementRules.flagKey(unlock.id)] == true
		if def == nil then
			return if flagged then 1 else 0, 1
		end
		local progress, target = AchievementRules.progress(def, u.ctx, u.rarities)
		return if flagged then target else progress, target
	elseif unlock.kind == "rebirths" then
		return math.min(u.ctx.rebirths, unlock.count), unlock.count
	elseif unlock.kind == "tiers" then
		return math.min(u.ctx.tiers, unlock.count), unlock.count
	end
	return 0, 1
end

function StyleRules.isUnlocked(unlock: StyleUnlock, u: Unlocks): boolean
	if u.all then
		return true
	end
	local progress, target = StyleRules.progress(unlock, u)
	return progress >= target
end

-- A title or skin as unlocking and wearing see it: its id and how it is earned. Lists of these come from
-- StyleRules.titleEntries / skinEntries, in their config's order.
export type Entry = { id: string, unlock: StyleUnlock }

function StyleRules.titleEntries(titles: Types.TitlesConfig): { Entry }
	local entries: { Entry } = {}
	for _, def in titles.list do
		table.insert(entries, { id = def.id, unlock = def.unlock })
	end
	return entries
end

function StyleRules.skinEntries(skins: Types.SkinsConfig): { Entry }
	local entries: { Entry } = {}
	for _, def in skins.list do
		table.insert(entries, { id = def.id, unlock = def.unlock })
	end
	return entries
end

-- The ids of `entries` that `u` has unlocked.
function StyleRules.unlocked(entries: { Entry }, u: Unlocks): { [string]: boolean }
	local set: { [string]: boolean } = {}
	for _, entry in entries do
		if StyleRules.isUnlocked(entry.unlock, u) then
			set[entry.id] = true
		end
	end
	return set
end

-- The id worn (the first of `entries` with its flag set), or "" for none.
function StyleRules.worn(flags: { [string]: boolean }, prefix: string, entries: { Entry }): string
	for _, entry in entries do
		if flags[prefix .. entry.id] == true then
			return entry.id
		end
	end
	return ""
end

-- Wears `id` ("" = none): clears every other flag with `prefix`, then sets this one.
function StyleRules.equip(flags: { [string]: boolean }, prefix: string, id: string)
	for key in table.clone(flags) do
		if string.sub(key, 1, #prefix) == prefix then
			flags[key] = nil
		end
	end
	if id ~= "" then
		flags[prefix .. id] = true
	end
end

-- Makes `flags` hold at most one `prefix` flag, for one of `entries` that is unlocked and isn't `default` (worn
-- without a flag). Keeps the first such one in order and clears the rest (unknown ids too). Returns the id worn ("" for
-- none) and whether anything changed.
function StyleRules.normalize(
	flags: { [string]: boolean },
	prefix: string,
	entries: { Entry },
	unlocked: { [string]: boolean },
	default: string?
): (string, boolean)
	local keep = ""
	for _, entry in entries do
		if flags[prefix .. entry.id] == true and unlocked[entry.id] and entry.id ~= default then
			keep = entry.id
			break
		end
	end
	local changed = false
	for key in table.clone(flags) do
		if string.sub(key, 1, #prefix) == prefix and (keep == "" or key ~= prefix .. keep) then
			flags[key] = nil
			changed = true
		end
	end
	return keep, changed
end

-- The title worn, "" for none.
function StyleRules.wornTitle(flags: { [string]: boolean }, titles: Types.TitlesConfig): string
	return StyleRules.worn(flags, StyleRules.TITLE_PREFIX, StyleRules.titleEntries(titles))
end

-- The skin a base wears: the flag's, or the default.
function StyleRules.wornSkin(flags: { [string]: boolean }, skins: Types.SkinsConfig): string
	local id = StyleRules.worn(flags, StyleRules.SKIN_PREFIX, StyleRules.skinEntries(skins))
	return if id == "" then skins.default else id
end

function StyleRules.titleById(titles: Types.TitlesConfig, id: string): TitleDef?
	for _, def in titles.list do
		if def.id == id then
			return def
		end
	end
	return nil
end

function StyleRules.skinById(skins: Types.SkinsConfig, id: string): SkinDef?
	for _, def in skins.list do
		if def.id == id then
			return def
		end
	end
	return nil
end

-- Whether a player may wear `id` (a title, a skin, or "" = no title / the default skin) given what they unlocked.
function StyleRules.canEquip(
	kind: Kind,
	id: string,
	titles: Types.TitlesConfig,
	skins: Types.SkinsConfig,
	unlocked: { [string]: boolean }
): boolean
	if id == "" then
		return true
	end
	local known = if kind == "title"
		then StyleRules.titleById(titles, id) ~= nil
		else StyleRules.skinById(skins, id) ~= nil
	return known and unlocked[id] == true
end

local function items(entries: { Entry }, u: Unlocks): { Types.StyleItemView }
	local views: { Types.StyleItemView } = {}
	for _, entry in entries do
		local progress, target = StyleRules.progress(entry.unlock, u)
		table.insert(views, {
			id = entry.id,
			unlocked = u.all == true or progress >= target,
			progress = progress,
			target = target,
		})
	end
	return views
end

-- Everything the Style dialog shows (StyleSync).
function StyleRules.view(titles: Types.TitlesConfig, skins: Types.SkinsConfig, u: Unlocks): Types.StyleView
	return {
		title = StyleRules.wornTitle(u.flags, titles),
		skin = StyleRules.wornSkin(u.flags, skins),
		titles = items(StyleRules.titleEntries(titles), u),
		skins = items(StyleRules.skinEntries(skins), u),
	}
end

-- How to earn `unlock`, in a few words: an achievement's own description, or a line from `text` (Config/Theme.text:
-- styleEarnFree, styleEarnRebirthOnce, styleEarnRebirths, styleEarnTierOnce, styleEarnTiers, styleEarnTiersAll).
function StyleRules.hint(
	unlock: StyleUnlock,
	achievements: { [string]: Types.AchievementDef },
	tierCount: number,
	text: { [string]: string }
): string
	if unlock.kind == "achievement" then
		local def = achievements[unlock.id]
		return if def then def.description else ""
	elseif unlock.kind == "rebirths" then
		return if unlock.count == 1
			then text.styleEarnRebirthOnce
			else Format.template(text.styleEarnRebirths, { count = unlock.count })
	elseif unlock.kind == "tiers" then
		if unlock.count >= tierCount then
			return text.styleEarnTiersAll
		end
		return if unlock.count == 1
			then text.styleEarnTierOnce
			else Format.template(text.styleEarnTiers, { count = unlock.count })
	end
	return text.styleEarnFree
end

-- A locked card's progress, like the Trophies tab shows it: cash for the money goals, hours for time played, a count
-- otherwise ("🔒 12 / 25", "🔒 $1.2M / $1B", "🔒 3.4 / 10 h"). `text`: Config/Theme.text (styleLocked,
-- achievementHours); `currency`: Theme.currencySymbol.
function StyleRules.progressText(
	unlock: StyleUnlock,
	progress: number,
	target: number,
	achievements: { [string]: Types.AchievementDef },
	text: { [string]: string },
	currency: string
): string
	local def = if unlock.kind == "achievement" then achievements[unlock.id] else nil
	local goal = if def then def.goal else nil
	local shown: string
	if goal == "earned" or goal == "income" then
		shown = `{Format.cash(progress, currency)} / {Format.cash(target, currency)}`
	elseif goal == "playHours" then
		shown = Format.template(
			text.achievementHours,
			{ progress = Format.number(progress), target = Format.number(target) }
		)
	else
		shown = `{Format.number(progress)} / {Format.number(target)}`
	end
	return Format.template(text.styleLocked, { progress = shown })
end

-- Where a base's wall tops and corner caps get their look. Classic: the plain white trim, or VIP's gold all round.
-- Any other skin: its own trim, and a VIP keeps the gold corner caps (the golden base trim is a VIP perk).
function StyleRules.trimSources(look: Types.SkinLook?, vip: boolean): (TrimSource, TrimSource)
	if look == nil then
		local source: TrimSource = if vip then "vip" else "wall"
		return source, source
	end
	return "skin", if vip then "vip" else "skin"
end

-- The floor tile in `row` (0 = the entrance end) on `side` (1 or 2) takes this colour index of a skin's `tiles`
-- (1-based): colours alternate down the floor and across the aisle, so two colours make a checker.
function StyleRules.tileIndex(row: number, side: number, count: number): number
	return (row + side) % math.max(1, count) + 1
end

-- Colours -----------------------------------------------------------------------------------------------------------

-- The red, green and blue of a #RRGGBB colour (0-255), or three nils when it is malformed.
local function channels(hex: string): (number?, number?, number?)
	local r, g, b = string.match(hex, "^#(%x%x)(%x%x)(%x%x)$")
	if r == nil or g == nil or b == nil then
		return nil, nil, nil
	end
	return tonumber(r, 16), tonumber(g, 16), tonumber(b, 16)
end

function StyleRules.isHex(hex: string): boolean
	return channels(hex) ~= nil
end

-- Relative luminance (WCAG) of a #RRGGBB colour, 0 (black) to 1 (white); -1 for a malformed one.
function StyleRules.luminance(hex: string): number
	local r, g, b = channels(hex)
	if r == nil or g == nil or b == nil then
		return -1
	end
	local function linear(c: number): number
		local s = c / 255
		return if s <= 0.04045 then s / 12.92 else ((s + 0.055) / 1.055) ^ 2.4
	end
	return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
end

-- How different two #RRGGBB colours look ("redmean" weighted distance, 0 to about 765); -1 when one is malformed.
function StyleRules.distance(a: string, b: string): number
	local r1, g1, b1 = channels(a)
	local r2, g2, b2 = channels(b)
	if r1 == nil or g1 == nil or b1 == nil or r2 == nil or g2 == nil or b2 == nil then
		return -1
	end
	local mean = (r1 + r2) / 2
	local dr, dg, db = r1 - r2, g1 - g2, b1 - b2
	return math.sqrt((2 + mean / 256) * dr * dr + 4 * dg * dg + (2 + (255 - mean) / 256) * db * db)
end

-- Validation -------------------------------------------------------------------------------------------------------

-- The limits an unlock is checked against: achievements by id, the most rebirths there can be, the Snackdex tiers.
export type UnlockLimits = {
	achievements: { [string]: Types.AchievementDef },
	maxRebirths: number,
	tiers: number,
}

local function countProblems(count: number, most: number, what: string, problems: { string })
	if not (count >= 1 and count <= most and count % 1 == 0) then
		table.insert(problems, `{what} from 1 to {most}`)
	end
end

local function unlockProblems(unlock: StyleUnlock, name: string, limits: UnlockLimits, problems: { string })
	if unlock.kind == "achievement" then
		if limits.achievements[unlock.id] == nil then
			table.insert(problems, `{name} needs an achievement that exists ({unlock.id})`)
		end
	elseif unlock.kind == "rebirths" then
		countProblems(unlock.count, limits.maxRebirths, `{name} needs a whole number of rebirths`, problems)
	elseif unlock.kind == "tiers" then
		countProblems(unlock.count, limits.tiers, `{name} needs a whole number of Snackdex tiers`, problems)
	elseif unlock.kind ~= "free" then
		table.insert(problems, `{name} unlock kind {tostring((unlock :: any).kind)} is not one`)
	end
end

local function idProblems(id: string, index: number, what: string, seen: { [string]: boolean }, problems: { string })
	if string.match(id, "^%a%w*$") == nil or #id > StyleRules.ID_LENGTH or seen[id] then
		table.insert(
			problems,
			`{what} {index} needs a unique id of letters and digits (at most {StyleRules.ID_LENGTH})`
		)
	end
	seen[id] = true
end

-- A short line of plain text: no line breaks or rich-text brackets (titles go into chat as rich text).
local function plainText(text: string, maxLength: number): boolean
	local length = utf8.len(text)
	return length ~= nil and length >= 1 and length <= maxLength and string.find(text, "[%c<>]") == nil
end

local function iconOk(icon: string): boolean
	return #icon >= 1 and #icon <= 16 and string.find(icon, "[%s%c<>]") == nil
end

-- Problems with Config/Titles (an empty list means valid).
function StyleRules.validateTitles(config: Types.TitlesConfig, limits: UnlockLimits): { string }
	local problems: { string } = {}
	local seen: { [string]: boolean } = {}
	if #config.list == 0 then
		table.insert(problems, "there are no titles")
	end
	for index, def in config.list do
		idProblems(def.id, index, "title", seen, problems)
		local name = `title {def.id}`
		if not plainText(def.text, StyleRules.TITLE_LENGTH) then
			table.insert(problems, `{name} needs a text of 1 to {StyleRules.TITLE_LENGTH} characters, one line`)
		end
		if not iconOk(def.icon) then
			table.insert(problems, `{name} needs an icon`)
		end
		if not StyleRules.isHex(def.color) then
			table.insert(problems, `{name} color must be #RRGGBB`)
		elseif StyleRules.luminance(def.color) < StyleRules.MIN_TITLE_LUMINANCE then
			table.insert(problems, `{name} color is too dark to read over its outline`)
		end
		if def.unlock.kind == "free" then
			table.insert(problems, `{name} must be earned (titles are never free)`)
		end
		unlockProblems(def.unlock, name, limits, problems)
	end
	local tag = config.nametag
	local function range(value: number, low: number, high: number, what: string)
		if not (value >= low and value <= high) then
			table.insert(problems, `nametag.{what} must be between {low} and {high}`)
		end
	end
	range(tag.width, 100, 400, "width")
	range(tag.height, 16, 60, "height")
	range(tag.maxTextSize, 12, tag.height, "maxTextSize")
	range(tag.offset, 0, 4, "offset")
	range(tag.maxDistance, 20, 150, "maxDistance")
	return problems
end

-- Problems with Config/Skins (an empty list means valid). `padColor`: the collect pads' #RRGGBB (Theme.world).
function StyleRules.validateSkins(config: Types.SkinsConfig, limits: UnlockLimits, padColor: string): { string }
	local problems: { string } = {}
	local seen: { [string]: boolean } = {}
	local default = StyleRules.skinById(config, config.default)
	if default == nil then
		table.insert(problems, `the default skin {config.default} is not a skin`)
	elseif default.unlock.kind ~= "free" or default.look ~= nil then
		table.insert(problems, "the default skin must be free and keep the plot's own colours (no look)")
	end
	local function color(hex: string, what: string)
		if not StyleRules.isHex(hex) then
			table.insert(problems, `{what} must be #RRGGBB`)
		end
	end
	for index, def in config.list do
		idProblems(def.id, index, "skin", seen, problems)
		local name = `skin {def.id}`
		if not plainText(def.name, StyleRules.NAME_LENGTH) then
			table.insert(problems, `{name} needs a name of 1 to {StyleRules.NAME_LENGTH} characters, one line`)
		end
		if not iconOk(def.icon) then
			table.insert(problems, `{name} needs an icon`)
		end
		if def.id ~= config.default then
			if def.unlock.kind == "free" then
				table.insert(problems, `{name} must be earned (only the default skin is free)`)
			end
			if def.look == nil then
				table.insert(problems, `{name} needs a look (only the default keeps the plot's own colours)`)
			end
		end
		unlockProblems(def.unlock, name, limits, problems)
		local look = def.look
		if look then
			if #look.tiles < 2 or #look.tiles > StyleRules.MAX_TILE_COLORS then
				table.insert(problems, `{name} needs 2 to {StyleRules.MAX_TILE_COLORS} tile colours`)
			end
			for i, hex in look.tiles do
				color(hex, `{name} tiles[{i}]`)
				if StyleRules.isHex(hex) and StyleRules.distance(hex, padColor) < StyleRules.MIN_PAD_CONTRAST then
					table.insert(problems, `{name} tiles[{i}] is too close to the collect pads' colour`)
				end
			end
			color(look.rug, `{name} rug`)
			color(look.trim, `{name} trim`)
			if not StyleRules.FLOOR_MATERIALS[look.tileMaterial] then
				table.insert(problems, `{name} tileMaterial {look.tileMaterial} is not a floor material`)
			end
			if not StyleRules.FLOOR_MATERIALS[look.rugMaterial] then
				table.insert(problems, `{name} rugMaterial {look.rugMaterial} is not a floor material`)
			end
			if not StyleRules.TRIM_MATERIALS[look.trimMaterial] then
				table.insert(problems, `{name} trimMaterial {look.trimMaterial} is not a trim material`)
			end
		end
	end
	return problems
end

return StyleRules
