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

StateStore.start()
HudController.start()
NotificationController.start()
BeltController.start()
PlotController.start()
InteractionController.start()

Net.get("ClientReady"):FireServer()
