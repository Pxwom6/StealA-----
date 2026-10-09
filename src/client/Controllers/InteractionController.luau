--!strict
--[[
	World interactions as local ProximityPrompts (native tap / hold on mobile, E on keyboard). Each prompt only
	sends an intent; the server decides. Prompts are created per podium and re-labelled as ownership changes:
	  own podium with a creature    → "Sell"  (short hold so it can't happen by accident)
	  own upgrade pad               → "Add Podium"
	Other players' podiums (Steal) and the lock button are added by StealController / LockController.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local GameData = require(ReplicatedStorage.Shared.GameData)
local Net = require(ReplicatedStorage.Shared.Net)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local EconomyMath = require(ReplicatedStorage.Shared.Logic.EconomyMath)
local UiKit = require(script.Parent.Parent.UI.UiKit)

local InteractionController = {}

local localPlayer = Players.LocalPlayer

export type PodiumPromptHook = (podium: Model, plot: Model, prompt: ProximityPrompt) -> boolean

-- Other controllers can claim a podium prompt for non-owners (e.g. Steal). Return true if handled.
local foreignHooks: { PodiumPromptHook } = {}

function InteractionController.addForeignPodiumHook(hook: PodiumPromptHook)
	table.insert(foreignHooks, hook)
end

local refreshers: { () -> () } = {}

function InteractionController.refreshAll()
	for _, refresh in refreshers do
		refresh()
	end
end

local function isMine(plot: Model): boolean
	return plot:GetAttribute("OwnerUserId") == localPlayer.UserId
end

local function setupPodium(podium: Model, plot: Model)
	local base = podium:WaitForChild("Base") :: BasePart
	local prompt = UiKit.new("ProximityPrompt", {
		Name = "PodiumPrompt",
		RequiresLineOfSight = false,
		MaxActivationDistance = 10,
		KeyboardKeyCode = Enum.KeyCode.E,
		Enabled = false,
		Parent = base,
	}) :: ProximityPrompt
	prompt:SetAttribute("Role", "")

	local function refresh()
		local creatureId = podium:GetAttribute("CreatureId")
		local def = if type(creatureId) == "string" then GameData.catalog.creatures[creatureId] else nil
		if def == nil or podium:GetAttribute("BeingStolen") == true then
			prompt.Enabled = false
			return
		end
		if isMine(plot) then
			prompt:SetAttribute("Role", "Sell")
			prompt.ActionText =
				`{Theme.text.sellAction} {UiTheme.cash(EconomyMath.sellValue(def.price, Economy.sellRefund))}`
			prompt.ObjectText = def.displayName
			prompt.HoldDuration = 0.8
			prompt.Enabled = true
			return
		end
		for _, hook in foreignHooks do
			if hook(podium, plot, prompt) then
				return
			end
		end
		prompt.Enabled = false
	end

	prompt.Triggered:Connect(function()
		if prompt:GetAttribute("Role") == "Sell" and isMine(plot) then
			local index = podium:GetAttribute("PodiumIndex")
			Net.get("SellCreature"):FireServer(index)
		end
	end)
	for _, attribute in { "CreatureId", "BeingStolen" } do
		podium:GetAttributeChangedSignal(attribute):Connect(refresh)
	end
	plot:GetAttributeChangedSignal("OwnerUserId"):Connect(refresh)
	table.insert(refreshers, refresh)
	refresh()
end

local function setupUpgradePad(plot: Model)
	local pad = plot:WaitForChild("UpgradePad") :: BasePart
	local prompt = UiKit.new("ProximityPrompt", {
		Name = "UpgradePrompt",
		ActionText = Theme.text.upgradeAction,
		RequiresLineOfSight = false,
		MaxActivationDistance = 10,
		HoldDuration = 0,
		KeyboardKeyCode = Enum.KeyCode.E,
		Enabled = false,
		Parent = pad,
	}) :: ProximityPrompt
	local function refresh()
		local cost = plot:GetAttribute("NextPodiumCost")
		local available = type(cost) == "number" and cost >= 0
		prompt.Enabled = isMine(plot) and available
		if type(cost) == "number" and cost >= 0 then
			prompt.ObjectText = UiTheme.cash(cost)
		end
	end
	prompt.Triggered:Connect(function()
		Net.get("BuyPodium"):FireServer()
	end)
	plot:GetAttributeChangedSignal("OwnerUserId"):Connect(refresh)
	plot:GetAttributeChangedSignal("NextPodiumCost"):Connect(refresh)
	table.insert(refreshers, refresh)
	refresh()
end

function InteractionController.start()
	local plotsFolder = workspace:WaitForChild("Map"):WaitForChild("Plots")
	for _, plot in plotsFolder:GetChildren() do
		if not plot:IsA("Model") then
			continue
		end
		task.spawn(setupUpgradePad, plot)
		local podiums = plot:WaitForChild("Podiums")
		for _, podium in podiums:GetChildren() do
			if podium:IsA("Model") then
				task.spawn(setupPodium, podium, plot)
			end
		end
	end
end

return InteractionController
