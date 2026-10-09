--!strict
--[[
	Roblox-side access to Config/Theme: hex colours → Color3 (cached), fonts, and text templates.
]]

local Theme = require("./Config/Theme")
local Format = require("./Logic/Format")
local GameData = require("./GameData")

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

function UiTheme.cash(amount: number): string
	return Format.cash(amount, Theme.currencySymbol)
end

function UiTheme.perSecond(amount: number): string
	return UiTheme.text("perSecond", { amount = UiTheme.cash(amount) })
end

return UiTheme
