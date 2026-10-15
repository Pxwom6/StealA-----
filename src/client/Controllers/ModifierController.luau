--!strict
--[[
	The running server modifier on the client (server: ModifierService):

	  * a button among the HUD's status pills, beside the event: "⚡ Rush Hour 4:12" in the modifier's colour (a full
	    44 px target above the play zone; Logic/ScreenLayout); tapping it repeats the description as a toast
	  * effects() / onChanged(): what the modifier changes, worked out from the published id exactly as the server does
	    (Logic/ModifierRules), so belt prices, the steal hold time and tag reach match what the server checks

	The id comes from workspace attributes Modifier and ModifierEndsAt.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modifiers = require(ReplicatedStorage.Shared.Config.Modifiers)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local ModifierRules = require(ReplicatedStorage.Shared.Logic.ModifierRules)
local ScreenLayout = require(ReplicatedStorage.Shared.Logic.ScreenLayout)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local HudController = require(script.Parent.HudController)
local NotificationController = require(script.Parent.NotificationController)

local ModifierController = {}

local current: string? = nil
local effects = ModifierRules.none()
local listeners: { () -> () } = {}
local chip: TextButton
local chipLabel: TextLabel

local function readId(): string?
	local id = workspace:GetAttribute("Modifier")
	if type(id) == "string" and Modifiers.modifiers[id] then
		return id
	end
	return nil
end

-- What the running modifier changes (every field 1 when none runs).
function ModifierController.effects(): ModifierRules.Effects
	return effects
end

-- Calls `listener` when a modifier starts or ends.
function ModifierController.onChanged(listener: () -> ())
	table.insert(listeners, listener)
end

local function updateChip()
	local id = current
	local def = if id then Modifiers.modifiers[id] else nil
	chip.Visible = def ~= nil
	if def == nil then
		return
	end
	local endsAt = workspace:GetAttribute("ModifierEndsAt")
	local remaining = if type(endsAt) == "number" then math.max(0, endsAt - workspace:GetServerTimeNow()) else 0
	chipLabel.Text = Format.template(
		Theme.text.modifierChip,
		{ icon = def.icon, name = def.displayName, time = Format.clock(remaining) }
	)
end

local function refresh()
	local id = readId()
	if id == current then
		return
	end
	current = id
	effects = ModifierRules.effects(Modifiers, id)
	local def = if id then Modifiers.modifiers[id] else nil
	if def then
		chip.BackgroundColor3 = UiTheme.color(def.color)
	end
	local wasVisible = chip.Visible
	updateChip()
	if chip.Visible and not wasVisible then
		UiKit.popIn(chip)
	end
	for _, listener in listeners do
		task.spawn(listener)
	end
end

function ModifierController.start()
	local size = ScreenLayout.SIZE.modifier
	chip = UiKit.button({
		Name = "ModifierChip",
		Size = UDim2.fromOffset(size.w, size.h),
		Visible = false,
	}, function()
		local id = current
		local def = if id then Modifiers.modifiers[id] else nil
		if def then
			NotificationController.toast(`{def.icon} {def.description}`, "info")
		end
	end)
	-- Wraps onto a second line for long names ("🌌 Northern Lights / 4:12").
	chipLabel = UiKit.label({ Name = "Text", Size = UDim2.fromScale(1, 1), TextWrapped = true, Parent = chip })
	HudController.place("modifier", chip)

	workspace:GetAttributeChangedSignal("Modifier"):Connect(refresh)
	refresh()
	task.spawn(function()
		while true do
			updateChip()
			task.wait(0.5)
		end
	end)
end

return ModifierController
