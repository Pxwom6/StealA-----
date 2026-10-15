--!strict
--[[
	Settings: a small gear button at the right end of the HUD's top-right row, in Roblox's top bar strip (under Roblox's
	top-left buttons when its player list fills the corner on computers; Logic/ScreenLayout) opens a dialog with three
	switches: Music, Sound effects and Reduce
	effects. A change applies at once and is saved per player (ClientSettings → SetSetting intent → `settings_<key>`
	flags in the save). A last row opens the Redeem Code dialog (CodesController); for players who may host (an admin,
	or this private server's owner: StateUpdate `host`) it shares that row with "🛠️ Host panel" (HostPanelController),
	so the dialog keeps its height.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local Types = require(ReplicatedStorage.Shared.Types)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local ScreenLayout = require(ReplicatedStorage.Shared.Logic.ScreenLayout)
local SettingsRules = require(ReplicatedStorage.Shared.Logic.SettingsRules)
local Modal = require(script.Parent.Parent.UI.Modal)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local ClientSettings = require(script.Parent.ClientSettings)
local CodesController = require(script.Parent.CodesController)
local HostPanelController = require(script.Parent.HostPanelController)
local HudController = require(script.Parent.HudController)
local SoundPlayer = require(script.Parent.SoundPlayer)

local SettingsController = {}

type Row = {
	key: string,
	label: string, -- Theme.text key
	hint: string?, -- Theme.text key of a second, smaller line
	onMeans: boolean, -- the switch shows ON when the setting has this value (music is ON when musicOff is false)
}

local ROWS: { Row } = {
	{ key = "musicOff", label = "settingsMusic", onMeans = false },
	{ key = "sfxOff", label = "settingsSfx", onMeans = false },
	{ key = "reduceEffects", label = "settingsReduceFx", hint = "settingsReduceFxHint", onMeans = true },
}

local GEAR_SIZE = ScreenLayout.SIZE.corner.button
local TRACK_SIZE = Vector2.new(84, 40)
local KNOB_SIZE = 32

local gear: TextButton

-- One settings line: its label (and hint) on the left, an ON / OFF switch on the right; the whole row is the target.
local function buildRow(row: Row, order: number, parent: Instance): (Types.SettingsView) -> ()
	local height = if row.hint then 78 else 54
	local button = UiKit.new("TextButton", {
		Name = row.key,
		LayoutOrder = order,
		AutoButtonColor = false,
		Text = "",
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = UiTheme.palette("panelLight"),
		Parent = parent,
	}) :: TextButton
	UiKit.corner(UiKit.RADIUS.medium).Parent = button
	UiKit.stroke(UiKit.STROKE.normal).Parent = button
	UiKit.addPressFeedback(button)
	UiKit.label({
		Name = "Label",
		Text = UiTheme.text(row.label),
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(16, 7),
		Size = UDim2.new(1, -TRACK_SIZE.X - 40, 0, 40),
		Parent = button,
	})
	if row.hint then
		UiKit.label({
			Name = "Hint",
			Text = UiTheme.text(row.hint),
			FontFace = UiTheme.bodyFont,
			TextColor3 = UiTheme.palette("textDim"),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
			Position = UDim2.fromOffset(16, 48),
			Size = UDim2.new(1, -TRACK_SIZE.X - 40, 0, 24),
			Parent = button,
		})
	end

	local track = UiKit.new("Frame", {
		Name = "Switch",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.fromOffset(TRACK_SIZE.X, TRACK_SIZE.Y),
		BackgroundColor3 = UiTheme.palette("panel"),
		Parent = button,
	}) :: Frame
	UiKit.corner(TRACK_SIZE.Y // 2).Parent = track
	UiKit.stroke(UiKit.STROKE.thin).Parent = track
	local stateLabel = UiKit.label({
		Name = "State",
		Text = "",
		FontFace = UiTheme.bodyFont,
		Size = UDim2.new(1, -KNOB_SIZE - 10, 1, -14),
		Position = UDim2.fromOffset(6, 7),
		Parent = track,
	})
	local knob = UiKit.new("Frame", {
		Name = "Knob",
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.fromOffset(KNOB_SIZE, KNOB_SIZE),
		BackgroundColor3 = UiTheme.palette("text"),
		Parent = track,
	}) :: Frame
	UiKit.corner(KNOB_SIZE // 2).Parent = knob
	UiKit.stroke(UiKit.STROKE.thin).Parent = knob

	local shownOn: boolean? = nil
	local function show(settings: Types.SettingsView)
		local on = SettingsRules.get(settings, row.key) == row.onMeans
		if on == shownOn then
			return
		end
		local animate = shownOn ~= nil
		shownOn = on
		local knobPosition = if on then UDim2.new(1, -KNOB_SIZE - 4, 0.5, 0) else UDim2.new(0, 4, 0.5, 0)
		local trackColor = if on then UiTheme.palette("success") else UiTheme.palette("panel")
		stateLabel.Text = if on then Theme.text.settingsOn else Theme.text.settingsOff
		stateLabel.Position = if on then UDim2.fromOffset(6, 7) else UDim2.fromOffset(KNOB_SIZE + 4, 7)
		if animate then
			local info = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			TweenService:Create(knob, info, { Position = knobPosition }):Play()
			TweenService:Create(track, info, { BackgroundColor3 = trackColor }):Play()
		else
			knob.Position = knobPosition
			track.BackgroundColor3 = trackColor
		end
	end
	button.Activated:Connect(function()
		local value = SettingsRules.get(ClientSettings.get(), row.key)
		ClientSettings.set(row.key, not value)
		SoundPlayer.ui("toggle") -- after the change, so turning sound effects back on is audible
	end)
	show(ClientSettings.get())
	return show
end

-- A row button that opens another dialog in place of this one. With a `hint`, the label is on the left and the hint
-- on the right; without, the label fills it.
local function buildLinkButton(
	name: string,
	text: string,
	hint: string?,
	size: UDim2,
	position: UDim2,
	parent: Instance,
	open: () -> ()
)
	local button = UiKit.new("TextButton", {
		Name = name,
		AutoButtonColor = false,
		Text = "",
		Size = size,
		Position = position,
		BackgroundColor3 = UiTheme.palette("panelLight"),
		Parent = parent,
	}) :: TextButton
	UiKit.corner(UiKit.RADIUS.medium).Parent = button
	UiKit.stroke(UiKit.STROKE.normal).Parent = button
	UiKit.addPressFeedback(button)
	UiKit.label({
		Name = "Label",
		Text = text,
		TextXAlignment = if hint then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(16, 7),
		Size = if hint then UDim2.new(0.45, 0, 0, 40) else UDim2.new(1, -32, 0, 40),
		Parent = button,
	})
	if hint then
		UiKit.label({
			Name = "Hint",
			Text = hint,
			FontFace = UiTheme.bodyFont,
			TextColor3 = UiTheme.palette("textDim"),
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -16, 0.5, 0),
			Size = UDim2.new(0.5, 0, 0, 24),
			Parent = button,
		})
	end
	button.Activated:Connect(function()
		SoundPlayer.ui("click")
		open()
	end)
end

-- The last row: the Redeem Code dialog, and beside it the host panel for players who may host.
local function buildLastRow(order: number, parent: Instance)
	local row = UiKit.new("Frame", {
		Name = "LastRow",
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 54),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	if not HostPanelController.mayHost() then
		buildLinkButton(
			"Codes",
			Theme.text.settingsCodes,
			Theme.text.settingsCodesHint,
			UDim2.fromScale(1, 1),
			UDim2.new(),
			row,
			CodesController.open
		)
		return
	end
	local half = UDim2.new(0.5, -4, 1, 0)
	buildLinkButton("Codes", Theme.text.settingsCodes, nil, half, UDim2.new(), row, CodesController.open)
	buildLinkButton("Host", Theme.text.settingsHost, nil, half, UDim2.new(0.5, 4, 0, 0), row, HostPanelController.open)
end

function SettingsController.open()
	local stopListening: (() -> ())? = nil
	local modal = Modal.open(Theme.text.settingsTitle, Vector2.new(460, 336), function()
		if stopListening then
			stopListening()
		end
	end)
	UiKit.new("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
		Parent = modal.body,
	})
	local updaters: { (Types.SettingsView) -> () } = {}
	for order, row in ROWS do
		table.insert(updaters, buildRow(row, order, modal.body))
	end
	buildLastRow(#ROWS + 1, modal.body)
	stopListening = ClientSettings.onChanged(function(settings)
		for _, update in updaters do
			update(settings)
		end
	end)
end

function SettingsController.start()
	gear = UiKit.button({
		Name = "SettingsButton",
		Size = UDim2.fromOffset(GEAR_SIZE, GEAR_SIZE),
		BackgroundColor3 = UiTheme.palette("panel"),
		Text = "⚙",
	}, SettingsController.open)
	HudController.place("gear", gear)
end

return SettingsController
