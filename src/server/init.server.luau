--!strict
--[[
	Server entry point. Services are started explicitly, in dependency order; PlayerLifecycle goes last so
	every system is ready before the first player is processed. Cross-service join/leave steps are wired here
	through PlayerLifecycle hooks, which keeps the services free of circular requires.
]]

local Services = script.Services

local Analytics = require(Services.Analytics)
local BeltService = require(Services.BeltService)
local DataService = require(Services.DataService)
local EconomyService = require(Services.EconomyService)
local LiveOpsService = require(Services.LiveOpsService)
local LockService = require(Services.LockService)
local MapBuilder = require(Services.MapBuilder)
local MonetizationService = require(Services.MonetizationService)
local PlayerLifecycle = require(Services.PlayerLifecycle)
local PlotService = require(Services.PlotService)
local RebirthService = require(Services.RebirthService)
local Remotes = require(Services.Remotes)
local Replication = require(Services.Replication)
local StealService = require(Services.StealService)

Remotes.start()
DataService.start()

local world = MapBuilder.build()
PlotService.start(world)

Analytics.start()
LiveOpsService.start()
Replication.start()
EconomyService.start()
BeltService.start(world.belt)
LockService.start()
StealService.start()
RebirthService.start()
MonetizationService.start()

local hooks = PlayerLifecycle.hooks()
hooks.checkPasses = MonetizationService.checkPasses
table.insert(hooks.onJoined, LockService.refresh)
table.insert(hooks.onLeaving, function(session)
	StealService.releaseAll(session, "left")
end)

PlayerLifecycle.start()
