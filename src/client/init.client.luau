--!strict
--[[
	Client entry point. Waits for the initial replication (shared modules use relative string requires, which
	do not wait for instances), starts every controller, then tells the server it is ready for state.
]]

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

local Controllers = script.Controllers
local StateStore = require(Controllers.StateStore)
local HudController = require(Controllers.HudController)
local NotificationController = require(Controllers.NotificationController)
local BeltController = require(Controllers.BeltController)
local PlotController = require(Controllers.PlotController)
local InteractionController = require(Controllers.InteractionController)
local StealController = require(Controllers.StealController)
local LockController = require(Controllers.LockController)
local RebirthController = require(Controllers.RebirthController)
local StoreController = require(Controllers.StoreController)
local ChatTagController = require(Controllers.ChatTagController)
local RewardsController = require(Controllers.RewardsController)
local MutationFxController = require(Controllers.MutationFxController)
local SocialController = require(Controllers.SocialController)
local TutorialController = require(Controllers.TutorialController)
local ClientSettings = require(Controllers.ClientSettings)
local SettingsController = require(Controllers.SettingsController)
local MusicController = require(Controllers.MusicController)
local WorldFxController = require(Controllers.WorldFxController)

StateStore.start()
ClientSettings.start() -- saved settings (music, sound effects, reduce effects) arrive with the first state
HudController.start()
NotificationController.start()
BeltController.start()
PlotController.start()
InteractionController.start()
StealController.start()
LockController.start()
RebirthController.start()
StoreController.start()
ChatTagController.start()
RewardsController.start()
MutationFxController.start()
SocialController.start()
TutorialController.start()
SettingsController.start() -- the gear, top right
MusicController.start()
WorldFxController.start() -- belt chevrons, factory cog; Reduce effects

Net.get("ClientReady"):FireServer()
