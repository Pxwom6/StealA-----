--!strict
--[[
	Friend & group rewards UI (server: SocialService, rules: Logic/SocialRules).

	  * A tappable pill in the HUD's top stack, under the lock pill, shows the current bonus ("Friends +20%  ·  Group
	    +10%"), or suggests playing with friends / joining the group while there is none. It is not a fourth round
	    side button on purpose: three 74px side buttons already fill the left edge between the top bar and the
	    movement thumbstick on a landscape phone.
	  * Tapping it opens the Friends & Group panel with big buttons: Invite friends (Roblox's own invite prompt,
	    hidden when this player can't send invites) and, when Config/Social.group.groupId is set and the player is not
	    a member yet, Join group (GroupService:PromptJoinAsync), after which the server is asked to check again.
	Nothing is ever rewarded for sending invites: only friends actually playing in the server count.
]]

local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local Social = require(ReplicatedStorage.Shared.Config.Social)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local Net = require(ReplicatedStorage.Shared.Net)
local Types = require(ReplicatedStorage.Shared.Types)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local SocialRules = require(ReplicatedStorage.Shared.Logic.SocialRules)
local Modal = require(script.Parent.Parent.UI.Modal)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local HudController = require(script.Parent.HudController)
local NotificationController = require(script.Parent.NotificationController)
local SoundPlayer = require(script.Parent.SoundPlayer)
local StateStore = require(script.Parent.StateStore)

local SocialController = {}

local localPlayer = Players.LocalPlayer
local groupEnabled = SocialRules.groupEnabled(Social.group)

local pill: TextButton
local canInvite = false
local groupName: string? = nil
local joinPromptOpen = false
local refreshPanel: (() -> ())? = nil -- set while the panel is open

local function percent(bonus: number): number
	return SocialRules.percent(bonus)
end

local function displayGroupName(): string
	return groupName or Theme.text.socialGroupFallbackName
end

local function pillText(view: Types.SocialView): string
	local parts: { string } = {}
	if view.friendBonus > 0 then
		table.insert(parts, Format.template(Theme.text.socialPillFriends, { percent = percent(view.friendBonus) }))
	end
	if view.groupBonus > 0 then
		table.insert(parts, Format.template(Theme.text.socialPillGroup, { percent = percent(view.groupBonus) }))
	end
	if #parts > 0 then
		return table.concat(parts, "  ·  ")
	elseif canInvite or not groupEnabled then
		return Format.template(
			Theme.text.socialPillPlayTogether,
			{ percent = percent(Social.friends.incomeBonusPerFriend) }
		)
	end
	return Format.template(Theme.text.socialPillJoinGroup, { percent = percent(Social.group.incomeBonus) })
end

local function updatePill(state: Types.ClientState)
	local view = state.social
	local canJoinGroup = groupEnabled and not view.groupMember
	-- Only shown when it has something to say or offer (so in Studio, with no group set and no invites, it hides).
	pill.Visible = view.bonus > 0 or canInvite or canJoinGroup
	UiKit.setButtonText(pill, "👥 " .. pillText(view))
end

local function redraw()
	local state = StateStore.get()
	if state then
		updatePill(state)
	end
	if refreshPanel then
		refreshPanel()
	end
end

-- Asks Roblox whether this player may send invites right now (yields, so in its own thread).
local function refreshCanInvite()
	task.spawn(function()
		local ok, result = pcall(function(): boolean
			return SocialService:CanSendGameInviteAsync(localPlayer)
		end)
		local allowed = ok and result == true
		if allowed ~= canInvite then
			canInvite = allowed
			redraw()
		end
	end)
end

local function onInvite()
	SoundPlayer.ui("click")
	local options = Instance.new("ExperienceInviteOptions")
	options.PromptMessage = Theme.text.socialInviteMessage
	local ok = pcall(function()
		SocialService:PromptGameInvite(localPlayer, options)
	end)
	if ok then
		Net.get("InvitePrompted"):FireServer() -- analytics only: nothing is rewarded for inviting
	else
		NotificationController.toast(Theme.text.socialInviteUnavailable, "error")
		refreshCanInvite()
	end
end

local function onJoinGroup()
	if joinPromptOpen then
		return
	end
	joinPromptOpen = true
	SoundPlayer.ui("click")
	task.spawn(function()
		local ok, status = pcall(function()
			return GroupService:PromptJoinAsync(Social.group.groupId)
		end)
		joinPromptOpen = false
		if not ok then
			NotificationController.toast(
				Format.template(Theme.text.socialGroupPromptFailed, { group = displayGroupName() }),
				"error"
			)
		elseif status == Enum.GroupMembershipStatus.Joined or status == Enum.GroupMembershipStatus.AlreadyMember then
			Net.get("CheckGroup"):FireServer() -- the server decides; it answers with a toast
		elseif status == Enum.GroupMembershipStatus.JoinRequestPending then
			NotificationController.toast(Theme.text.socialGroupPending, "info")
		end
	end)
end

function SocialController.open()
	if StateStore.get() == nil then
		return
	end
	SoundPlayer.ui("click")
	refreshCanInvite()

	local fill: () -> ()
	local modal = Modal.open(Theme.text.socialTitle, Vector2.new(560, 320), function()
		if refreshPanel == fill then
			refreshPanel = nil
		end
	end)
	local lines = UiKit.new("Frame", {
		Size = UDim2.new(1, 0, 1, -66),
		BackgroundTransparency = 1,
		Parent = modal.body,
	}) :: Frame
	UiKit.new("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 6),
		Parent = lines,
	})
	local friendsLine = UiKit.label({ LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 34), Parent = lines })
	local friendsHint = UiKit.label({
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 40),
		TextWrapped = true,
		FontFace = UiTheme.bodyFont,
		TextColor3 = UiTheme.palette("textDim"),
		Parent = lines,
	})
	local groupLine = UiKit.label({
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, 56),
		TextWrapped = true,
		Visible = groupEnabled,
		Parent = lines,
	})

	local buttons = UiKit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, 0, 0, 58),
		BackgroundTransparency = 1,
		Parent = modal.body,
	}) :: Frame
	UiKit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 12),
		Parent = buttons,
	})
	local inviteButton = UiKit.button({
		LayoutOrder = 1,
		Size = UDim2.fromOffset(230, 56),
		BackgroundColor3 = UiTheme.palette("social"),
		Text = Theme.text.socialInvite,
		Parent = buttons,
	}, onInvite)
	local joinButton = UiKit.button({
		LayoutOrder = 2,
		Size = UDim2.fromOffset(230, 56),
		BackgroundColor3 = UiTheme.palette("success"),
		Text = Theme.text.socialGroupJoin,
		Parent = buttons,
	}, onJoinGroup)

	fill = function()
		local state = StateStore.get()
		if state == nil or not modal.isOpen() then
			return
		end
		local view = state.social
		friendsLine.Text =
			Format.template(Theme.text.socialFriendsLine, { count = view.friends, percent = percent(view.friendBonus) })
		friendsHint.Text = Format.template(Theme.text.socialFriendsHint, {
			per = percent(Social.friends.incomeBonusPerFriend),
			max = percent(SocialRules.friendBonus(Social.friends.maxFriends, Social.friends)),
		})
		if groupEnabled then
			local groupPercent = percent(SocialRules.groupBonus(true, Social.group))
			if view.groupMember then
				groupLine.Text = Format.template(
					Theme.text.socialGroupMember,
					{ group = displayGroupName(), percent = groupPercent }
				)
				groupLine.TextColor3 = UiTheme.palette("success")
			elseif not view.groupRewardClaimed and Social.group.welcomeReward ~= nil then
				groupLine.Text = Format.template(Theme.text.socialGroupPitchGift, {
					group = displayGroupName(),
					percent = groupPercent,
					amount = UiTheme.cash(SocialRules.groupWelcomeAmount(state.packIncome, Social.group)),
				})
				groupLine.TextColor3 = UiTheme.palette("gold")
			else
				groupLine.Text =
					Format.template(Theme.text.socialGroupPitch, { group = displayGroupName(), percent = groupPercent })
				groupLine.TextColor3 = UiTheme.palette("gold")
			end
		end
		inviteButton.Visible = canInvite
		joinButton.Visible = groupEnabled and not view.groupMember
	end
	refreshPanel = fill
	fill()
end

function SocialController.start()
	pill = UiKit.button({
		Name = "SocialPill",
		LayoutOrder = 5,
		Size = UDim2.fromOffset(260, 34),
		BackgroundColor3 = UiTheme.palette("social"),
		Visible = false,
		Parent = HudController.topStack(),
	}, SocialController.open)

	StateStore.onChange(function()
		redraw()
	end)
	refreshCanInvite()
	if groupEnabled then
		task.spawn(function()
			local ok, info = pcall(function()
				return GroupService:GetGroupInfoAsync(Social.group.groupId)
			end)
			if ok and type(info) == "table" and type(info.Name) == "string" then
				groupName = info.Name
				redraw()
			end
		end)
	end
end

return SocialController
