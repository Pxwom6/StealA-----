--!strict
--[[
	Every Lucky Spin prize with its exact chance, as a grid of coloured cells (Logic/StoreLayout.oddsCells): the Spin
	tab's Odds view and each Lucky Spin pack's Shop card, so the odds are on screen before any purchase. The chances
	are Config/Spin's weights through SpinRules.chances, the numbers the server rolls with.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Spin = require(ReplicatedStorage.Shared.Config.Spin)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local SpinRules = require(ReplicatedStorage.Shared.Logic.SpinRules)
local StoreLayout = require(ReplicatedStorage.Shared.Logic.StoreLayout)
local UiKit = require(script.Parent.UiKit)

local OddsGrid = {}

-- Builds the grid over `area` of `parent` (UI units in `parent`'s coordinates), its cells at `zIndex`. Returns the
-- frame holding it (destroy it to rebuild at another size).
function OddsGrid.build(parent: GuiObject, area: StoreLayout.Rect, zIndex: number): Frame
	local holder = UiKit.new("Frame", {
		Name = "OddsCells",
		Position = UDim2.fromOffset(area.x, area.y),
		Size = UDim2.fromOffset(area.w, area.h),
		BackgroundTransparency = 1,
		ZIndex = zIndex,
		Parent = parent,
	}) :: Frame
	local cells = StoreLayout.oddsCells({ x = 0, y = 0, w = area.w, h = area.h }, #Spin.segments)
	for index, chance in SpinRules.chances(Spin.segments) do
		local segment = Spin.segments[index]
		local cellRect = cells[index]
		local cell = UiKit.new("Frame", {
			Name = segment.id,
			Position = UDim2.fromOffset(cellRect.x, cellRect.y),
			Size = UDim2.fromOffset(cellRect.w, cellRect.h),
			BackgroundColor3 = UiTheme.color(segment.color),
			ZIndex = zIndex,
			Parent = holder,
		}) :: Frame
		UiKit.corner(UiKit.RADIUS.small).Parent = cell
		local prizeRect, chanceRect = StoreLayout.oddsText(cellRect)
		UiKit.label({
			Name = "Prize",
			Text = `{segment.icon} {segment.label}`,
			Position = UDim2.fromOffset(prizeRect.x - cellRect.x, prizeRect.y - cellRect.y),
			Size = UDim2.fromOffset(prizeRect.w, prizeRect.h),
			ZIndex = zIndex + 1,
			Parent = cell,
		})
		UiKit.label({
			Name = "Chance",
			Text = Format.percent(chance),
			Position = UDim2.fromOffset(chanceRect.x - cellRect.x, chanceRect.y - cellRect.y),
			Size = UDim2.fromOffset(chanceRect.w, chanceRect.h),
			ZIndex = zIndex + 1,
			Parent = cell,
		})
	end
	return holder
end

return OddsGrid
