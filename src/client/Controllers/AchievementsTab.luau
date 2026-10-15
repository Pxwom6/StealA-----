--!strict
--[[
	The Rewards panel's Trophies tab (achievements; server: AchievementService, config: Config/Achievements): how many
	are done, then a scrolling list with each one's icon, title, goal, progress bar and reward, ticked once done.
	Opening the tab (and every few seconds while it is open) asks the server for the progress (GetAchievements →
	AchievementSync). Achievements pay themselves the moment they are reached, with a toast, so nothing is claimed here.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Achievements = require(ReplicatedStorage.Shared.Config.Achievements)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local GameData = require(ReplicatedStorage.Shared.GameData)
local Net = require(ReplicatedStorage.Shared.Net)
local Types = require(ReplicatedStorage.Shared.Types)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local EconomyMath = require(ReplicatedStorage.Shared.Logic.EconomyMath)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local UiKit = require(script.Parent.Parent.UI.UiKit)

local AchievementsTab = {}

local ROW_HEIGHT = 58
local ROW_GAP = 6
local REFRESH_SECONDS = 5

type Row = { frame: Frame, fill: Frame, progress: TextLabel, reward: TextLabel }

type Built = {
	header: TextLabel,
	rows: { [string]: Row },
	lastAsked: number,
}

local built: Built? = nil
local latest: { Types.AchievementView } = {}
local defs: { [string]: Types.AchievementDef } = {}
for _, def in Achievements.list do
	defs[def.id] = def
end

-- What a prize gives, for the row's reward line.
local function rewardText(reward: Types.PrizeReward, income: number): string
	if reward.kind == "cash" then
		return "+"
			.. UiTheme.cash(
				EconomyMath.cashPackAmount(income, { incomeSeconds = reward.incomeSeconds, minimum = reward.minimum })
			)
	elseif reward.kind == "spin" then
		return if reward.count == 1
			then Theme.text.achievementRewardSpin
			else Format.template(Theme.text.achievementRewardSpins, { count = reward.count })
	end
	local mutation = if reward.mutation then GameData.mutation(reward.mutation) else nil
	if mutation then
		return Format.template(Theme.text.achievementRewardMutated, { mutation = mutation.displayName })
	end
	return Format.template(Theme.text.achievementRewardCreature, { luck = Format.number(reward.luck) })
end

-- The bar's text: cash for the money goals, hours (to a tenth) for time played, a count otherwise.
local function progressText(entry: Types.AchievementView): string
	local def = defs[entry.id]
	local goal = if def then def.goal else nil
	if goal == "earned" or goal == "income" then
		return `{UiTheme.cash(entry.progress)} / {UiTheme.cash(entry.target)}`
	elseif goal == "playHours" then
		return Format.template(
			Theme.text.achievementHours,
			{ progress = Format.number(entry.progress), target = Format.number(entry.target) }
		)
	end
	return `{Format.number(entry.progress)} / {Format.number(entry.target)}`
end

local function show(list: { Types.AchievementView })
	latest = list
	local current = built
	if current == nil then
		return
	end
	local done = 0
	for _, entry in list do
		local row = current.rows[entry.id]
		if entry.done then
			done += 1
		end
		if row then
			local share = if entry.target > 0 then math.clamp(entry.progress / entry.target, 0, 1) else 0
			row.fill.Size = UDim2.fromScale(if entry.done then 1 else share, 1)
			row.fill.BackgroundColor3 = if entry.done then UiTheme.palette("gold") else UiTheme.palette("success")
			row.progress.Text = if entry.done then "✓" else progressText(entry)
			row.frame.BackgroundColor3 = if entry.done then UiTheme.palette("panel") else UiTheme.palette("panelLight")
		end
	end
	current.header.Text = Format.template(Theme.text.achievementsCount, { done = done, total = #Achievements.list })
end

-- Builds the tab into `content`; returns its refresh (which also re-asks the server every few seconds).
function AchievementsTab.build(content: Frame): (state: Types.ClientState) -> ()
	local header = UiKit.label({
		Name = "Count",
		Text = Theme.text.achievementLoading,
		Size = UDim2.new(1, 0, 0, 24),
		TextColor3 = UiTheme.palette("gold"),
		Parent = content,
	})
	local scroll = UiKit.new("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromOffset(0, 30),
		Size = UDim2.new(1, 0, 1, -30),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = UiTheme.palette("textDim"),
		CanvasSize = UDim2.fromOffset(0, #Achievements.list * (ROW_HEIGHT + ROW_GAP)),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = content,
	}) :: ScrollingFrame
	UiKit.new("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, ROW_GAP),
		Parent = scroll,
	})
	local rows: { [string]: Row } = {}
	for order, def in Achievements.list do
		local frame = UiKit.panel({
			Name = def.id,
			LayoutOrder = order,
			Size = UDim2.new(1, -14, 0, ROW_HEIGHT),
			BackgroundColor3 = UiTheme.palette("panelLight"),
			Parent = scroll,
		})
		UiKit.label({
			Name = "Icon",
			Text = def.icon,
			Size = UDim2.fromOffset(44, 44),
			Position = UDim2.fromOffset(6, 7),
			Parent = frame,
		})
		UiKit.label({
			Name = "Title",
			Text = def.title,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(0.5, -60, 0, 24),
			Position = UDim2.fromOffset(56, 5),
			Parent = frame,
		})
		UiKit.label({
			Name = "Goal",
			Text = def.description,
			FontFace = UiTheme.bodyFont,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = UiTheme.palette("textDim"),
			Size = UDim2.new(0.5, -60, 0, 20),
			Position = UDim2.fromOffset(56, 31),
			Parent = frame,
		})
		local bar = UiKit.new("Frame", {
			Name = "Bar",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 8),
			Size = UDim2.new(0.45, 0, 0, 20),
			BackgroundColor3 = UiTheme.palette("stroke"),
			ClipsDescendants = true,
			Parent = frame,
		}) :: Frame
		UiKit.corner(10).Parent = bar
		local fill = UiKit.new("Frame", {
			Name = "Fill",
			Size = UDim2.fromScale(0, 1),
			BackgroundColor3 = UiTheme.palette("success"),
			Parent = bar,
		}) :: Frame
		UiKit.corner(10).Parent = fill
		local progress = UiKit.label({
			Name = "Progress",
			Text = "",
			FontFace = UiTheme.bodyFont,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 2,
			Parent = bar,
		})
		local reward = UiKit.label({
			Name = "Reward",
			Text = "",
			FontFace = UiTheme.bodyFont,
			TextColor3 = UiTheme.palette("cash"),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 32),
			Size = UDim2.new(0.45, 0, 0, 20),
			Parent = frame,
		})
		rows[def.id] = { frame = frame, fill = fill, progress = progress, reward = reward }
	end
	built = { header = header, rows = rows, lastAsked = 0 }
	if #latest > 0 then
		show(latest)
	end

	return function(state: Types.ClientState)
		local current = built
		if current == nil then
			return
		end
		for _, def in Achievements.list do
			local row = current.rows[def.id]
			if row then
				row.reward.Text =
					Format.template(Theme.text.achievementReward, { reward = rewardText(def.reward, state.packIncome) })
			end
		end
		local now = os.clock()
		if now - current.lastAsked >= REFRESH_SECONDS then
			current.lastAsked = now
			Net.get("GetAchievements"):FireServer()
		end
	end
end

-- Forgets the built tab (the panel closed or switched tabs).
function AchievementsTab.clear()
	built = nil
end

function AchievementsTab.start()
	Net.get("AchievementSync").OnClientEvent:Connect(show)
end

return AchievementsTab
