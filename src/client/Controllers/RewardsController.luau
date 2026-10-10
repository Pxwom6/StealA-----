--!strict
--[[
	Retention UI:
	  * "Welcome back — you earned X" popup after offline earnings
	  * Rewards panel (side button with a badge) with two tabs:
	      Daily   the login streak: a 7-day track and one-tap claim; the panel opens itself on this tab once per
	              session when a reward is waiting (after the welcome popup, never during the first-time tutorial)
	      Quests  today's three quests (QuestService → StateUpdate `quests`): progress bars, rewards, Claim buttons, the
	              all-done bonus and when new quests arrive
	    Each tab has its own red dot when something is claimable; the side button shows one when either does. The open
	    panel updates live (progress, countdowns) without being rebuilt.
	  * HUD pills for live events (banner + "Halloween ends in 3d 4h", in the event's theme colour) and server luck
	    (multiplier + time until it next changes), from LiveOpsService's workspace attributes
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Quests = require(ReplicatedStorage.Shared.Config.Quests)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local GameData = require(ReplicatedStorage.Shared.GameData)
local Net = require(ReplicatedStorage.Shared.Net)
local Types = require(ReplicatedStorage.Shared.Types)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local DailyStreak = require(ReplicatedStorage.Shared.Logic.DailyStreak)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local QuestRules = require(ReplicatedStorage.Shared.Logic.QuestRules)
local Modal = require(script.Parent.Parent.UI.Modal)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local HudController = require(script.Parent.HudController)
local NotificationController = require(script.Parent.NotificationController)
local SoundPlayer = require(script.Parent.SoundPlayer)
local StateStore = require(script.Parent.StateStore)

export type Tab = "daily" | "quests"

type TabButton = { button: TextButton, badge: Frame }
type TabDef = { id: string, text: string }

type Panel = {
	modal: Modal.ModalHandle,
	tab: string, -- a Tab
	tabs: { [string]: TabButton },
	content: Frame,
	refresh: ((state: Types.ClientState) -> ())?,
}

local RewardsController = {}

-- Reference px. Height stays within Modal's 340 so the panel fits a landscape phone.
local PANEL_SIZE = Vector2.new(620, 336)
local TAB_BAR_HEIGHT = 40
local TAB_WIDTH = 170
local CONTENT_TOP = 48
local QUEST_ROW_HEIGHT = 56
local QUEST_ROW_GAP = 6
local CLAIM_WIDTH = 140
local SECONDS_PER_DAY = 86400

local TABS: { TabDef } = {
	{ id = "daily", text = Theme.text.rewardsTabDaily },
	{ id = "quests", text = Theme.text.rewardsTabQuests },
}

local questDefs = QuestRules.index(Quests.pool)

local rewardsButton: HudController.SideButton
local panel: Panel? = nil
local pillStack: Frame
local luckPill: Frame
local luckLabel: TextLabel
local eventPill: Frame
local eventLabel: TextLabel
local eventCountdown: TextLabel
local autoOpenedDaily = false
local welcomeOpen = false

-- Seconds until the next UTC midnight (a new daily reward, new quests), on the server's clock.
local function secondsToMidnight(): number
	local now = workspace:GetServerTimeNow()
	return (math.floor(now / SECONDS_PER_DAY) + 1) * SECONDS_PER_DAY - now
end

local function setStroke(frame: GuiObject, color: Color3)
	local stroke = frame:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = color
	end
end

local function badgeDot(parent: GuiObject): Frame
	local badge = UiKit.new("Frame", {
		Name = "Badge",
		Size = UDim2.fromOffset(18, 18),
		Position = UDim2.new(1, -10, 0, -7),
		BackgroundColor3 = UiTheme.palette("danger"),
		Visible = false,
		ZIndex = 3,
		Parent = parent,
	}) :: Frame
	UiKit.corner(9).Parent = badge
	UiKit.stroke(2).Parent = badge
	return badge
end

-- Daily tab ---------------------------------------------------------------------------------------------------------

local function buildDaily(content: Frame): (state: Types.ClientState) -> ()
	local cycle = #Economy.daily
	local track = UiKit.new("Frame", {
		Name = "Track",
		Size = UDim2.new(1, 0, 0, 112),
		BackgroundTransparency = 1,
		Parent = content,
	}) :: Frame
	UiKit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
		Parent = track,
	})
	type Cell = { frame: Frame, icon: TextLabel, reward: TextLabel }
	local cells: { Cell } = {}
	for slot = 1, cycle do
		local cell = UiKit.panel({
			LayoutOrder = slot,
			Size = UDim2.new(1 / cycle, -6, 1, 0),
			BackgroundColor3 = UiTheme.palette("panelLight"),
			Parent = track,
		})
		UiKit.label({
			Text = Format.template(Theme.text.dailyDay, { day = slot }),
			Size = UDim2.fromScale(1, 0.3),
			Parent = cell,
		})
		local icon = UiKit.label({
			Text = "🎁",
			Size = UDim2.fromScale(1, 0.4),
			Position = UDim2.fromScale(0, 0.3),
			Parent = cell,
		})
		local reward = UiKit.label({
			Text = "",
			Size = UDim2.new(1, -6, 0.28, 0),
			Position = UDim2.new(0, 3, 0.7, 0),
			Visible = false,
			Parent = cell,
		})
		table.insert(cells, { frame = cell, icon = icon, reward = reward })
	end
	local body = UiKit.label({
		Name = "Streak",
		Text = "",
		Size = UDim2.new(1, 0, 0, 26),
		Position = UDim2.fromOffset(0, 118),
		TextColor3 = UiTheme.palette("textDim"),
		Parent = content,
	})
	local claim = UiKit.button({
		Name = "ClaimDaily",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromOffset(260, 56),
		BackgroundColor3 = UiTheme.palette("panelLight"),
		Text = "",
		Parent = content,
	}, function()
		local latest = StateStore.get()
		if latest and latest.daily.canClaim then
			Net.get("ClaimDaily"):FireServer()
			SoundPlayer.ui("claim")
		end
	end)

	return function(state: Types.ClientState)
		local daily = state.daily
		local currentSlot = DailyStreak.slot(daily.nextStreak, cycle)
		for slot, cell in cells do
			local isNext = slot == currentSlot -- claimable now, or tomorrow once today's is claimed
			local claimedThisCycle = slot < currentSlot
			cell.frame.BackgroundColor3 = if isNext
				then UiTheme.palette("gold")
				elseif claimedThisCycle then UiTheme.palette("success")
				else UiTheme.palette("panelLight")
			cell.icon.Text = if claimedThisCycle then "✓" else "🎁"
			cell.reward.Visible = isNext
			cell.reward.Text = UiTheme.cash(daily.reward)
		end
		body.Text = Format.template(Theme.text.dailyBody, { day = daily.streak })
		claim.BackgroundColor3 = if daily.canClaim then UiTheme.palette("success") else UiTheme.palette("panelLight")
		UiKit.setButtonText(
			claim,
			if daily.canClaim
				then `{Theme.text.claim} {UiTheme.cash(daily.reward)}`
				else Format.clock(secondsToMidnight())
		)
	end
end

-- Quests tab --------------------------------------------------------------------------------------------------------

-- The quest's line, e.g. "Collect $2.5K from your pads".
local function questText(def: Types.QuestDef?, slot: Types.QuestSlotView): string
	if def == nil then
		return Theme.text.questUnknown
	end
	local rarity = if def.minRarity then GameData.catalog.rarities[def.minRarity] else nil
	return UiTheme.text(def.textKey, {
		count = slot.target,
		amount = UiTheme.cash(slot.target),
		rarity = if rarity then rarity.displayName else "",
	})
end

local function buildQuests(content: Frame): (state: Types.ClientState) -> ()
	type Row = {
		frame: Frame,
		text: TextLabel,
		fill: Frame,
		progress: TextLabel,
		tag: Frame,
		tagLabel: TextLabel,
		claim: TextButton,
	}
	local rows: { Row } = {}
	for index = 1, #Quests.slots do
		local frame = UiKit.panel({
			Name = `Quest{index}`,
			Size = UDim2.new(1, 0, 0, QUEST_ROW_HEIGHT),
			Position = UDim2.fromOffset(0, (index - 1) * (QUEST_ROW_HEIGHT + QUEST_ROW_GAP)),
			BackgroundColor3 = UiTheme.palette("panelLight"),
			Parent = content,
		})
		local text = UiKit.label({
			Name = "Text",
			Text = "",
			Position = UDim2.fromOffset(12, 4),
			Size = UDim2.new(1, -(CLAIM_WIDTH + 24), 0, 24),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = frame,
		})
		UiKit.new("UITextSizeConstraint", { MaxTextSize = 22, Parent = text })
		-- Progress bar, with the difficulty tag at its right end.
		local bar = UiKit.new("Frame", {
			Name = "Bar",
			Position = UDim2.fromOffset(12, 32),
			Size = UDim2.new(1, -(CLAIM_WIDTH + 24 + 60), 0, 16),
			BackgroundColor3 = UiTheme.palette("stroke"),
			ClipsDescendants = true,
			Parent = frame,
		}) :: Frame
		UiKit.corner(8).Parent = bar
		local fill = UiKit.new("Frame", {
			Name = "Fill",
			Size = UDim2.fromScale(0, 1),
			BackgroundColor3 = UiTheme.palette("success"),
			Parent = bar,
		}) :: Frame
		UiKit.corner(8).Parent = fill
		local progress = UiKit.label({
			Name = "Progress",
			Text = "",
			Size = UDim2.fromScale(1, 1),
			FontFace = UiTheme.bodyFont,
			ZIndex = 2,
			Parent = bar,
		})
		local tag = UiKit.new("Frame", {
			Name = "Difficulty",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -(CLAIM_WIDTH + 14), 0, 30),
			Size = UDim2.fromOffset(52, 20),
			BackgroundColor3 = UiTheme.palette("success"),
			Parent = frame,
		}) :: Frame
		UiKit.corner(10).Parent = tag
		local tagLabel = UiKit.label({
			Text = "",
			Size = UDim2.new(1, -8, 1, -4),
			Position = UDim2.fromOffset(4, 2),
			Parent = tag,
		})
		local claim = UiKit.button({
			Name = "Claim",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -6, 0.5, 0),
			Size = UDim2.fromOffset(CLAIM_WIDTH, 44),
			BackgroundColor3 = UiTheme.palette("panel"),
			Text = "",
			Parent = frame,
		}, function()
			local latest = StateStore.get()
			local slot = latest and latest.quests.list[index]
			if slot and not slot.claimed and slot.progress >= slot.target then
				Net.get("ClaimQuest"):FireServer(index)
				SoundPlayer.ui("claim")
			end
		end)
		table.insert(rows, {
			frame = frame,
			text = text,
			fill = fill,
			progress = progress,
			tag = tag,
			tagLabel = tagLabel,
			claim = claim,
		})
	end
	local footerTop = #Quests.slots * (QUEST_ROW_HEIGHT + QUEST_ROW_GAP)
	local bonus = UiKit.label({
		Name = "Bonus",
		Text = "",
		Position = UDim2.fromOffset(4, footerTop),
		Size = UDim2.new(0.62, -4, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = UiTheme.palette("gold"),
		Parent = content,
	})
	local reset = UiKit.label({
		Name = "Reset",
		Text = "",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -4, 0, footerTop),
		Size = UDim2.new(0.38, -4, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = UiTheme.palette("textDim"),
		FontFace = UiTheme.bodyFont,
		Parent = content,
	})

	return function(state: Types.ClientState)
		local view = state.quests
		local claimed = 0
		for index, row in rows do
			local slot = view.list[index]
			row.frame.Visible = slot ~= nil
			if slot == nil then
				continue
			end
			local def = questDefs[slot.id]
			local hard = def ~= nil and def.difficulty == "hard"
			local done = slot.progress >= slot.target
			local claimable = done and not slot.claimed and def ~= nil
			if slot.claimed then
				claimed += 1
			end
			row.text.Text = questText(def, slot)
			row.fill.Size = UDim2.fromScale(math.clamp(slot.progress / math.max(1, slot.target), 0, 1), 1)
			row.fill.BackgroundColor3 = if hard then UiTheme.palette("gold") else UiTheme.palette("success")
			row.progress.Text = if def and def.kind == "collect"
				then `{UiTheme.cash(slot.progress)} / {UiTheme.cash(slot.target)}`
				else `{Format.number(slot.progress)} / {Format.number(slot.target)}`
			row.tag.BackgroundColor3 = if hard then UiTheme.palette("primary") else UiTheme.palette("success")
			row.tagLabel.Text = if hard then Theme.text.questHard else Theme.text.questEasy
			row.claim.BackgroundColor3 = if claimable
				then UiTheme.palette("success")
				elseif slot.claimed then UiTheme.palette("panelLight")
				else UiTheme.palette("panel")
			UiKit.setButtonText(
				row.claim,
				if slot.claimed
					then `✓ {Theme.text.questClaimed}`
					elseif claimable then `{Theme.text.claim} {UiTheme.cash(slot.reward)}`
					else UiTheme.cash(slot.reward)
			)
			setStroke(row.frame, if claimable then UiTheme.palette("gold") else UiTheme.palette("stroke"))
		end
		bonus.Text = if view.bonusClaimed
			then Theme.text.questBonusClaimed
			else Format.template(
				Theme.text.questBonus,
				{ amount = UiTheme.cash(view.bonus), done = claimed, count = #view.list }
			)
		reset.Text = Format.template(
			Theme.text.questResetsIn,
			{ time = Format.duration(view.resetsAt - workspace:GetServerTimeNow()) }
		)
	end
end

-- Panel ---------------------------------------------------------------------------------------------------------------

local function updateBadges(state: Types.ClientState)
	local dailyReady = state.daily.canClaim
	local questsReady = state.quests.claimable > 0
	rewardsButton.badge.Visible = dailyReady or questsReady
	local current = panel
	if current then
		current.tabs.daily.badge.Visible = dailyReady
		current.tabs.quests.badge.Visible = questsReady
	end
end

local function selectTab(tab: string)
	local current = panel
	if current == nil then
		return
	end
	current.tab = tab
	for id, entry in current.tabs do
		entry.button.BackgroundColor3 = if id == tab then UiTheme.palette("gold") else UiTheme.palette("panelLight")
	end
	current.content:ClearAllChildren()
	current.refresh = if tab == "daily" then buildDaily(current.content) else buildQuests(current.content)
	local state = StateStore.get()
	if state and current.refresh then
		current.refresh(state)
	end
end

-- Opens the Rewards panel on `tab`; without one, on Daily when its reward is waiting, else on Quests.
function RewardsController.open(tab: Tab?)
	local state = StateStore.get()
	if state == nil then
		return
	end
	local modal = Modal.open(Theme.text.rewardsTitle, PANEL_SIZE, function()
		panel = nil
	end)
	local tabBar = UiKit.new("Frame", {
		Name = "Tabs",
		Size = UDim2.new(1, 0, 0, TAB_BAR_HEIGHT),
		BackgroundTransparency = 1,
		Parent = modal.body,
	}) :: Frame
	UiKit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 10),
		Parent = tabBar,
	})
	local content = UiKit.new("Frame", {
		Name = "Content",
		Position = UDim2.fromOffset(0, CONTENT_TOP),
		Size = UDim2.new(1, 0, 1, -CONTENT_TOP),
		BackgroundTransparency = 1,
		Parent = modal.body,
	}) :: Frame
	local tabs: { [string]: TabButton } = {}
	for order, entry in TABS do
		local id = entry.id
		local button = UiKit.button({
			Name = entry.id,
			LayoutOrder = order,
			Size = UDim2.fromOffset(TAB_WIDTH, TAB_BAR_HEIGHT),
			BackgroundColor3 = UiTheme.palette("panelLight"),
			Text = entry.text,
		}, function()
			local current = panel
			if current and current.tab ~= id then
				SoundPlayer.ui("click")
				selectTab(id)
			end
		end)
		tabs[entry.id] = { button = button, badge = badgeDot(button) }
		button.Parent = tabBar
	end
	panel = { modal = modal, tab = "daily", tabs = tabs, content = content, refresh = nil }
	local defaultTab: Tab = if state.daily.canClaim or #state.quests.list == 0 then "daily" else "quests"
	selectTab(tab or defaultTab)
	updateBadges(state)
	-- Countdowns tick while the panel is open.
	task.spawn(function()
		while modal.isOpen() do
			task.wait(1)
			local current = panel
			local latest = StateStore.get()
			if current and current.modal == modal and current.refresh and latest then
				current.refresh(latest)
			end
		end
	end)
end

local function showWelcome(payload: { amount: number, seconds: number })
	welcomeOpen = true
	local modal = Modal.open(Theme.text.welcomeBackTitle, Vector2.new(480, 260), function()
		welcomeOpen = false
		local state = StateStore.get()
		if state and state.daily.canClaim and not autoOpenedDaily and state.tutorial.step == "" then
			autoOpenedDaily = true
			RewardsController.open("daily")
		end
	end)
	UiKit.label({
		Text = Format.template(Theme.text.welcomeBackBody, {
			amount = UiTheme.cash(payload.amount),
			duration = Format.duration(payload.seconds),
		}),
		FontFace = UiTheme.bodyFont,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 90),
		Parent = modal.body,
	})
	UiKit.label({
		Text = "+" .. UiTheme.cash(payload.amount),
		TextColor3 = UiTheme.palette("cash"),
		Size = UDim2.new(1, 0, 0, 40),
		Position = UDim2.fromOffset(0, 86),
		Parent = modal.body,
	})
	UiKit.button({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromOffset(220, 56),
		BackgroundColor3 = UiTheme.palette("success"),
		Text = Theme.text.ok,
		Parent = modal.body,
	}, modal.close)
	SoundPlayer.ui("claim")
end

-- "12:34" under an hour, "1d 6h" / "2h 15m" for long events.
local function countdown(seconds: number): string
	return if seconds < 3600 then Format.clock(seconds) else Format.duration(seconds)
end

local function updateLiveOpsPills()
	local now = workspace:GetServerTimeNow()

	local multiplier = workspace:GetAttribute("LuckMultiplier")
	local luckEndsAt = workspace:GetAttribute("LuckEndsAt")
	local hasLuck = type(multiplier) == "number" and multiplier > 1
	luckPill.Visible = hasLuck
	if hasLuck then
		local remaining = if type(luckEndsAt) == "number" then math.max(0, luckEndsAt - now) else 0
		luckLabel.Text = Format.template(Theme.text.luckBanner, {
			multiplier = Format.number(multiplier :: number),
			time = countdown(remaining),
		})
	end

	local banner = workspace:GetAttribute("EventBanner")
	local hasBanner = type(banner) == "string" and banner ~= ""
	eventPill.Visible = hasBanner
	if hasBanner then
		local bannerId = workspace:GetAttribute("EventBannerId")
		local title = workspace:GetAttribute("EventTitle")
		local endsAt = workspace:GetAttribute("EventEndsAt")
		eventLabel.Text = banner :: string
		eventPill.BackgroundColor3 = UiTheme.eventColor(if type(bannerId) == "string" then bannerId else nil)
		local remaining = if type(endsAt) == "number" then math.max(0, endsAt - now) else 0
		eventCountdown.Text = Format.template(Theme.text.eventEndsIn, {
			event = if type(title) == "string" and title ~= "" then title else Theme.text.eventFallbackTitle,
			time = Format.duration(remaining),
		})
	end
	pillStack.Visible = hasLuck or hasBanner
end

function RewardsController.start()
	rewardsButton = HudController.addSideButton(3, "🎁", Theme.text.rewardsButton, UiTheme.palette("gold"), function()
		SoundPlayer.ui("click")
		RewardsController.open()
	end)

	-- LiveOps pills share one slot in the HUD's top stack: the event banner with its countdown, then server luck.
	pillStack = UiKit.new("Frame", {
		Name = "LiveOpsPills",
		LayoutOrder = HudController.TOP_ORDER.liveOps,
		Size = UDim2.fromOffset(300, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Visible = false,
		Parent = HudController.topStack(),
	}) :: Frame
	UiKit.new("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 4),
		Parent = pillStack,
	})
	eventPill = UiKit.panel({
		Name = "EventPill",
		LayoutOrder = 1,
		Size = UDim2.fromOffset(290, 48),
		BackgroundColor3 = UiTheme.palette("event"),
		Visible = false,
		Parent = pillStack,
	})
	eventLabel = UiKit.label({
		Name = "Banner",
		Size = UDim2.new(1, -16, 0, 24),
		Position = UDim2.fromOffset(8, 3),
		Parent = eventPill,
	})
	eventCountdown = UiKit.label({
		Name = "Countdown",
		FontFace = UiTheme.bodyFont,
		Size = UDim2.new(1, -16, 0, 17),
		Position = UDim2.fromOffset(8, 27),
		Parent = eventPill,
	})
	luckPill = UiKit.panel({
		Name = "LuckPill",
		LayoutOrder = 2,
		Size = UDim2.fromOffset(230, 32),
		BackgroundColor3 = UiTheme.palette("luck"),
		Visible = false,
		Parent = pillStack,
	})
	luckLabel = UiKit.label({ Size = UDim2.new(1, -12, 1, -6), Position = UDim2.fromOffset(6, 3), Parent = luckPill })

	Net.get("WelcomeBack").OnClientEvent:Connect(showWelcome)
	StateStore.onChange(function(state)
		updateBadges(state)
		local current = panel
		if current and current.refresh then
			current.refresh(state)
		end
		-- Not during the first-time tutorial: a brand-new player's first seconds belong to the loop. The badge still
		-- shows, and the panel opens on the first update after the tutorial ends.
		if state.daily.canClaim and not autoOpenedDaily and not welcomeOpen and state.tutorial.step == "" then
			-- Give the welcome popup a moment to arrive first.
			task.delay(2.5, function()
				local latest = StateStore.get()
				if
					latest
					and latest.daily.canClaim
					and not autoOpenedDaily
					and not welcomeOpen
					and latest.tutorial.step == ""
				then
					autoOpenedDaily = true
					RewardsController.open("daily")
				end
			end)
		end
	end)
	Net.get("Effect").OnClientEvent:Connect(function(payload: { kind: string, position: Vector3? })
		local position = payload.position
		if position == nil then
			return
		end
		if payload.kind == "daily" or payload.kind == "questsAllDone" then
			NotificationController.sparkle(position, UiTheme.palette("gold"))
		elseif payload.kind == "quest" then
			NotificationController.sparkle(position, UiTheme.palette("success"))
		end
	end)
	task.spawn(function()
		while true do
			updateLiveOpsPills()
			task.wait(0.5)
		end
	end)
end

return RewardsController
