--!strict
--[[
	The gadget buttons (Config/Gadgets): one round button per owned gadget beside the TAG button, where
	Logic/ScreenLayout.gadgetSlots puts them (HudController places them; tools/layoutCheck.luau checks them on every
	checked screen). None until the player owns a gadget, none during the first-time tutorial. A screen with room for
	fewer (three on a 320 px tall phone) shows the first gadgets owned; a button with no slot stays hidden.

	  * slot 1 is the first gadget owned in Config/Gadgets order, slot 2 the next...; each shows its icon in its colour
	  * recharging: a dark disc shrinks away as the gadget recharges, with the seconds left on it
	  * running (the soda's speed, the shield, a peel lying in your base): a bright pulsing ring
	  * keys 1-4 on a keyboard use the gadgets in Config/Gadgets order (each button shows its key)
	  * with the Auto Collect pass, the Snack Magnet shows "AUTO": the pass already does its job every few seconds, so
	    a tap only says so (GadgetRules.coveredByAutoCollect; the server refuses it too)

	Using one only sends the UseGadget intent; the server checks everything and answers with a toast when it says no.
	A tap while the button still shows its cooldown says so here instead, without asking the server.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Gadgets = require(ReplicatedStorage.Shared.Config.Gadgets)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local Net = require(ReplicatedStorage.Shared.Net)
local Types = require(ReplicatedStorage.Shared.Types)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local GadgetRules = require(ReplicatedStorage.Shared.Logic.GadgetRules)
local ScreenLayout = require(ReplicatedStorage.Shared.Logic.ScreenLayout)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local HudController = require(script.Parent.HudController)
local NotificationController = require(script.Parent.NotificationController)
local StateStore = require(script.Parent.StateStore)

local GadgetController = {}

local SLOTS = math.min(#Gadgets.order, ScreenLayout.SIZE.gadget.slots)
local PRESS_DEBOUNCE = 0.6 -- seconds: one tap is one use, even before the server's answer comes back
local KEYS: { [Enum.KeyCode]: number } = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Five] = 5,
	[Enum.KeyCode.Six] = 6,
	[Enum.KeyCode.Seven] = 7,
	[Enum.KeyCode.Eight] = 8,
	[Enum.KeyCode.Nine] = 9,
	[Enum.KeyCode.KeypadOne] = 1,
	[Enum.KeyCode.KeypadTwo] = 2,
	[Enum.KeyCode.KeypadThree] = 3,
	[Enum.KeyCode.KeypadFour] = 4,
}

type Slot = {
	button: TextButton,
	icon: TextLabel,
	disc: Frame, -- the cooldown: shrinks from the whole button to nothing
	time: TextLabel,
	key: TextLabel,
	auto: TextLabel, -- "AUTO" over a Snack Magnet while the player owns the Auto Collect pass
	stroke: UIStroke,
	id: string?, -- the gadget it shows now
	pressedAt: number,
	cooling: boolean,
}

local slots: { Slot } = {}
local view: Types.GadgetsView = { owned = {}, readyAt = {}, activeUntil = {} }
local inTutorial = true -- until the first state says otherwise (no flash of buttons for a new player)
local autoCollect = false -- the player owns the Auto Collect pass
local room = SLOTS -- buttons this screen has a slot for (ScreenLayout.gadgetSlots)
local roomFor = "" -- the screen that was measured on

-- Whether the number of slots this screen has room for changed (worked out again only when the screen did).
local function measureRoom(): boolean
	local device = HudController.device()
	local key = table.concat({
		device.widthPx,
		device.heightPx,
		device.left,
		device.insetRightPx,
		device.insetBottomPx,
		device.topBar,
		device.topBarLeft,
		device.topBarRight,
		device.playerList,
	}, ":")
	if key == roomFor then
		return false
	end
	roomFor = key
	local count = #ScreenLayout.gadgetSlots(device, SLOTS)
	local changed = count ~= room
	room = count
	return changed
end

-- The Auto Collect pass already does what gadget `id` does (the Snack Magnet): its button shows AUTO.
local function covered(id: string): boolean
	return GadgetRules.coveredByAutoCollect(Gadgets.gadgets[id], autoCollect)
end

local function now(): number
	return workspace:GetServerTimeNow()
end

local function nameOf(id: string): string
	return UiTheme.text(Gadgets.gadgets[id].nameKey)
end

-- Uses the gadget in `slot` (a tap or its key).
local function press(slot: Slot)
	local id = slot.id
	if id == nil or inTutorial or not slot.button.Visible then
		return
	end
	local t = os.clock()
	if t - slot.pressedAt < PRESS_DEBOUNCE then
		return
	end
	slot.pressedAt = t
	if covered(id) then
		NotificationController.toast(Theme.text.magnetAuto, "info")
		return
	end
	local readyAt = view.readyAt[id]
	if readyAt and readyAt > now() then
		NotificationController.toast(
			UiTheme.text("gadgetRecharging", { name = nameOf(id), time = Format.clock(readyAt - now()) }),
			"error"
		)
		return
	end
	Net.get("UseGadget"):FireServer(id)
end

local function buildSlot(index: number): Slot
	local slot: Slot
	local button = UiKit.button({
		Name = `Gadget{index}`,
		Size = UDim2.fromOffset(ScreenLayout.SIZE.gadget.size, ScreenLayout.SIZE.gadget.size),
		BackgroundColor3 = UiTheme.palette("panel"),
		Text = "",
		Visible = false,
	}, function()
		press(slot)
	end)
	-- An icon button: round, no text padding, the emoji in the middle.
	local corner = button:FindFirstChildOfClass("UICorner")
	if corner then
		corner.CornerRadius = UDim.new(0.5, 0)
	end
	local padding = button:FindFirstChildOfClass("UIPadding")
	if padding then
		padding:Destroy()
	end
	local icon = button:FindFirstChild("Label") :: TextLabel
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromScale(0.68, 0.68)
	local disc = UiKit.new("Frame", {
		Name = "Cooldown",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = UiTheme.palette("stroke"),
		BackgroundTransparency = 0.3,
		Visible = false,
		ZIndex = 2,
		Parent = button,
	}) :: Frame
	UiKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = disc })
	local time = UiKit.label({
		Name = "Time",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.6, 0.5),
		Visible = false,
		ZIndex = 3,
		Parent = button,
	})
	-- The key on a keyboard, in the top-left corner (inside the button, so it never spills onto a neighbour).
	local key = UiKit.label({
		Name = "Key",
		Position = UDim2.fromScale(0.02, 0.02),
		Size = UDim2.fromScale(0.34, 0.34),
		TextColor3 = UiTheme.palette("gold"),
		Visible = false,
		ZIndex = 4,
		Parent = button,
	})
	-- "AUTO" across the bottom of a Snack Magnet the Auto Collect pass makes unneeded.
	local auto = UiKit.label({
		Name = "Auto",
		Text = Theme.text.gadgetAutoBadge,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1.02),
		Size = UDim2.fromScale(0.9, 0.36),
		TextColor3 = UiTheme.palette("gold"),
		Visible = false,
		ZIndex = 4,
		Parent = button,
	})
	slot = {
		button = button,
		icon = icon,
		disc = disc,
		time = time,
		key = key,
		auto = auto,
		stroke = button:FindFirstChildOfClass("UIStroke") :: UIStroke,
		id = nil,
		pressedAt = -math.huge,
		cooling = false,
	}
	HudController.place(`gadget{index}`, button)
	return slot
end

-- Which gadget each slot shows, and which slots show at all.
local function bind()
	local keyboard = UserInputService.KeyboardEnabled
	for index, slot in slots do
		local id = view.owned[index]
		local show = id ~= nil and not inTutorial and index <= room
		if id ~= slot.id then
			slot.id = id
			if id then
				local def = Gadgets.gadgets[id]
				slot.button.BackgroundColor3 = UiTheme.color(def.color)
				slot.icon.Text = def.icon
				slot.key.Text = tostring(GadgetRules.slot(Gadgets, id) or index)
			end
		end
		slot.key.Visible = keyboard and show
		local isAuto = show and id ~= nil and covered(id)
		slot.auto.Visible = isAuto
		slot.icon.TextTransparency = if isAuto then 0.35 else 0
		if show ~= slot.button.Visible then
			slot.button.Visible = show
			if show then
				UiKit.popIn(slot.button)
			end
		end
	end
end

-- Cooldown discs, countdowns and the running ring, every frame while a button shows.
local function tick()
	local t = now()
	for _, slot in slots do
		local id = slot.id
		if id == nil or not slot.button.Visible then
			continue
		end
		local def = Gadgets.gadgets[id]
		local readyAt = view.readyAt[id]
		local remaining = if readyAt then math.max(0, readyAt - t) else 0
		local cooling = remaining > 0
		if cooling then
			local share = math.clamp(remaining / def.cooldownSeconds, 0, 1)
			slot.disc.Size = UDim2.fromScale(share, share)
			slot.time.Text = tostring(math.ceil(remaining))
		end
		if cooling ~= slot.cooling then
			slot.cooling = cooling
			slot.disc.Visible = cooling
			slot.time.Visible = cooling
			slot.icon.TextTransparency = if cooling or slot.auto.Visible then 0.35 else 0
			if not cooling then
				UiKit.popIn(slot.button) -- ready again
			end
		end
		local activeUntil = view.activeUntil[id]
		local active = activeUntil ~= nil and activeUntil > t
		if active then
			-- a ring that breathes while the effect runs (the soda, the shield, a peel lying in the base)
			slot.stroke.Color = UiTheme.palette("gold")
			slot.stroke.Thickness = 3 + 1.5 * (0.5 + 0.5 * math.sin(os.clock() * 8))
		elseif slot.stroke.Thickness ~= UiKit.STROKE.normal then
			slot.stroke.Color = UiTheme.palette("stroke")
			slot.stroke.Thickness = UiKit.STROKE.normal
		end
	end
end

function GadgetController.start()
	for index = 1, SLOTS do
		slots[index] = buildSlot(index)
	end
	measureRoom()
	-- the screen changed (turned, resized, Roblox's top bar grew): maybe more or fewer slots
	HudController.onLayout(function()
		if measureRoom() then
			bind()
		end
	end)
	StateStore.onChange(function(state)
		view = state.gadgets
		inTutorial = state.tutorial.step ~= ""
		autoCollect = state.passes.AutoCollect == true
		bind()
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return -- typing in chat or a text box
		end
		local index = KEYS[input.KeyCode]
		local id = if index then Gadgets.order[index] else nil
		if id == nil then
			return
		end
		for _, slot in slots do
			if slot.id == id then
				press(slot)
			end
		end
	end)
	-- A keyboard plugged in (or out) shows (or hides) the key hints.
	UserInputService:GetPropertyChangedSignal("KeyboardEnabled"):Connect(bind)
	RunService.RenderStepped:Connect(tick)
	Players.LocalPlayer.CharacterAdded:Connect(function()
		for _, slot in slots do
			slot.pressedAt = -math.huge
		end
	end)
end

return GadgetController
