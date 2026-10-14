--!strict
--[[
	The Rewards panel's Gifts tab (playtime gifts; server: GiftService, config: Config/Gifts): six gift boxes that
	unlock with time played today. Each shows when it unlocks ("12 min"), what it holds and a countdown, then a Claim
	button, then a tick. The time counts on here from the last StateUpdate (GiftsTab.played), so the countdowns tick
	without any traffic; the server re-checks every claim.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Gifts = require(ReplicatedStorage.Shared.Config.Gifts)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local Net = require(ReplicatedStorage.Shared.Net)
local Types = require(ReplicatedStorage.Shared.Types)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local GiftRules = require(ReplicatedStorage.Shared.Logic.GiftRules)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local SoundPlayer = require(script.Parent.SoundPlayer)
local StateStore = require(script.Parent.StateStore)

local GiftsTab = {}

local CELL_GAP = 8
local CELL_HEIGHT = 150

-- Seconds played today as of now: what the server last sent plus the time since.
function GiftsTab.played(view: Types.GiftsView): number
	return view.seconds + math.max(0, workspace:GetServerTimeNow() - view.syncedAt)
end

-- Gifts unlocked and not claimed, counting the time since the last update.
function GiftsTab.claimable(view: Types.GiftsView): number
	local played = GiftsTab.played(view)
	local count = 0
	for index in Gifts.ladder do
		if played >= Gifts.ladder[index].minutes * 60 and table.find(view.claimed, index) == nil then
			count += 1
		end
	end
	return count
end

-- What a gift holds, in a few words.
local function rewardText(reward: Types.PrizeReward, cash: number): string
	if reward.kind == "cash" then
		return "+" .. UiTheme.cash(cash)
	elseif reward.kind == "spin" then
		return if reward.count == 1
			then Theme.text.giftSpin
			else Format.template(Theme.text.giftSpins, { count = reward.count })
	end
	return if reward.luck > 1
		then Format.template(Theme.text.giftCreatureLucky, { luck = Format.number(reward.luck) })
		else Theme.text.giftCreature
end

-- Builds the tab into `content`; returns its refresh.
function GiftsTab.build(content: Frame): (state: Types.ClientState) -> ()
	UiKit.label({
		Name = "Title",
		Text = Theme.text.giftsTitle,
		Size = UDim2.new(1, 0, 0, 24),
		TextColor3 = UiTheme.palette("gold"),
		Parent = content,
	})
	local row = UiKit.new("Frame", {
		Name = "Gifts",
		Position = UDim2.fromOffset(0, 30),
		Size = UDim2.new(1, 0, 0, CELL_HEIGHT),
		BackgroundTransparency = 1,
		Parent = content,
	}) :: Frame
	UiKit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, CELL_GAP),
		Parent = row,
	})
	type Cell = { frame: Frame, reward: TextLabel, button: TextButton }
	local cells: { Cell } = {}
	local count = #Gifts.ladder
	for index, def in Gifts.ladder do
		local frame = UiKit.panel({
			Name = `Gift{index}`,
			LayoutOrder = index,
			Size = UDim2.new(1 / count, -CELL_GAP, 1, 0),
			BackgroundColor3 = UiTheme.palette("panelLight"),
			Parent = row,
		})
		UiKit.label({
			Name = "When",
			Text = Format.template(Theme.text.minutesShort, { minutes = def.minutes }),
			FontFace = UiTheme.bodyFont,
			Size = UDim2.new(1, -8, 0, 20),
			Position = UDim2.fromOffset(4, 4),
			TextColor3 = UiTheme.palette("textDim"),
			Parent = frame,
		})
		UiKit.label({
			Name = "Icon",
			Text = def.icon,
			Size = UDim2.new(1, 0, 0, 40),
			Position = UDim2.fromOffset(0, 26),
			Parent = frame,
		})
		local reward = UiKit.label({
			Name = "Reward",
			Text = "",
			TextWrapped = true,
			Size = UDim2.new(1, -8, 0, 32),
			Position = UDim2.fromOffset(4, 68),
			Parent = frame,
		})
		local button = UiKit.button({
			Name = "Claim",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -6),
			Size = UDim2.new(1, -10, 0, 38),
			BackgroundColor3 = UiTheme.palette("panel"),
			Text = "",
			Parent = frame,
		}, function()
			local latest = StateStore.get()
			if latest == nil then
				return
			end
			local view = latest.gifts
			if GiftRules.isUnlocked(Gifts, index, GiftsTab.played(view)) and table.find(view.claimed, index) == nil then
				Net.get("ClaimGift"):FireServer(index)
				SoundPlayer.ui("claim")
			end
		end)
		table.insert(cells, { frame = frame, reward = reward, button = button })
	end
	local footer = UiKit.label({
		Name = "Resets",
		Text = "",
		FontFace = UiTheme.bodyFont,
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.fromOffset(0, 30 + CELL_HEIGHT + 8),
		TextColor3 = UiTheme.palette("textDim"),
		Parent = content,
	})

	return function(state: Types.ClientState)
		local view = state.gifts
		local played = GiftsTab.played(view)
		for index, cell in cells do
			local def = Gifts.ladder[index]
			cell.reward.Text = rewardText(def.reward, view.rewards[index] or 0)
			local claimed = table.find(view.claimed, index) ~= nil
			local unlocked = GiftRules.isUnlocked(Gifts, index, played)
			cell.frame.BackgroundColor3 = if claimed
				then UiTheme.palette("success")
				elseif unlocked then UiTheme.palette("gold")
				else UiTheme.palette("panelLight")
			cell.button.BackgroundColor3 = if unlocked and not claimed
				then UiTheme.palette("success")
				else UiTheme.palette("panel")
			UiKit.setButtonText(
				cell.button,
				if claimed
					then Theme.text.giftClaimed
					elseif unlocked then Theme.text.giftReady
					else Format.clock(GiftRules.secondsUntil(Gifts, index, played))
			)
		end
		footer.Text = Format.template(
			Theme.text.giftsResetIn,
			{ time = Format.duration(math.max(0, view.resetsAt - workspace:GetServerTimeNow())) }
		)
	end
end

return GiftsTab
