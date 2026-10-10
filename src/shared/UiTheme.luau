--!strict
--[[
	Roblox-side access to Config/Theme: hex colours → Color3 (cached), fonts, and text templates.
]]

local Theme = require("./Config/Theme")
local Seasons = require("./Config/Seasons")
local Format = require("./Logic/Format")
local SeasonRules = require("./Logic/SeasonRules")
local GameData = require("./GameData")
local Types = require("./Types")

local UiTheme = {}

local colorCache: { [string]: Color3 } = {}

function UiTheme.color(hex: string): Color3
	local cached = colorCache[hex]
	if cached then
		return cached
	end
	local ok, color = pcall(Color3.fromHex, hex)
	local result = if ok then color else Color3.new(1, 0, 1)
	colorCache[hex] = result
	return result
end

function UiTheme.palette(key: string): Color3
	local hex = ((Theme.palette :: any) :: { [string]: string })[key]
	return UiTheme.color(hex or "#FF00FF")
end

function UiTheme.world(key: string): Color3
	local hex = ((Theme.world :: any) :: { [string]: string })[key]
	return UiTheme.color(hex or "#FF00FF")
end

function UiTheme.rarityColor(rarityId: string): Color3
	local rarity = GameData.catalog.rarities[rarityId]
	return UiTheme.color(if rarity then rarity.color else "#FFFFFF")
end

-- Colour of a LiveOps event in the UI (event pill, "EVENT" tag): its seasonal theme's accent (Config/Seasons), or the
-- palette's event colour.
function UiTheme.eventColor(eventId: string?): Color3
	local theme = SeasonRules.themeForEvent(Seasons, eventId)
	return if theme then UiTheme.color(theme.accentColor) else UiTheme.palette("event")
end

function UiTheme.plotColor(plotIndex: number): Color3
	local colors = Theme.plotColors
	return UiTheme.color(colors[((plotIndex - 1) % #colors) + 1])
end

local function fontFromName(name: string, fallback: Enum.Font): Font
	local ok, enumItem = pcall(function(): Enum.Font
		return (Enum.Font :: any)[name]
	end)
	return Font.fromEnum(if ok and enumItem then enumItem else fallback)
end

UiTheme.displayFont = fontFromName(Theme.fonts.display, Enum.Font.FredokaOne)
UiTheme.bodyFont = fontFromName(Theme.fonts.body, Enum.Font.GothamBold)

-- Looks up a Theme.text entry by key and fills its {placeholders}. Unknown keys return the key itself so a
-- missing string is visible in playtests instead of crashing.
function UiTheme.text(key: string, vars: { [string]: any }?): string
	local template = ((Theme.text :: any) :: { [string]: string })[key]
	if template == nil then
		return key
	end
	return Format.template(template, vars)
end

-- Escapes text for a RichText label.
function UiTheme.escapeRich(text: string): string
	local escaped = string.gsub(text, "[&<>\"']", {
		["&"] = "&amp;",
		["<"] = "&lt;",
		[">"] = "&gt;",
		['"'] = "&quot;",
		["'"] = "&apos;",
	})
	return escaped
end

local function richColor(text: string, hex: string): string
	return `<font color="{hex}">{UiTheme.escapeRich(text)}</font>`
end

-- A creature's name for a RichText label: the creature in its rarity colour, a mutation ("Golden") in the mutation's
-- colour, in the order of Theme.text.mutatedName.
function UiTheme.creatureNameRich(def: Types.CreatureDef, variant: string?): string
	local rarity = GameData.catalog.rarities[def.rarity]
	local creature = richColor(def.displayName, if rarity then rarity.color else "#FFFFFF")
	local mutation = GameData.mutation(variant)
	if mutation == nil then
		return creature
	end
	return Format.template(
		Theme.text.mutatedName,
		{ mutation = richColor(mutation.displayName, mutation.color), creature = creature }
	)
end

function UiTheme.cash(amount: number): string
	return Format.cash(amount, Theme.currencySymbol)
end

function UiTheme.perSecond(amount: number): string
	return UiTheme.text("perSecond", { amount = UiTheme.cash(amount) })
end

return UiTheme
