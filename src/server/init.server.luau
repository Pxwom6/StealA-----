--!strict
--[[
	Server entry point. Services are started explicitly, in dependency order; PlayerLifecycle goes last so
	every system is ready before the first player is processed.
]]

local Services = script.Services

local Analytics = require(Services.Analytics)
local BeltService = require(Services.BeltService)
local DataService = require(Services.DataService)
local EconomyService = require(Services.EconomyService)
local LiveOpsService = require(Services.LiveOpsService)
local MapBuilder = require(Services.MapBuilder)
local PlayerLifecycle = require(Services.PlayerLifecycle)
local PlotService = require(Services.PlotService)
local Remotes = require(Services.Remotes)
local Replication = require(Services.Replication)

Remotes.start()
DataService.start()

local world = MapBuilder.build()
PlotService.start(world)

Analytics.start()
LiveOpsService.start()
Replication.start()
EconomyService.start()
BeltService.start(world.belt)

PlayerLifecycle.start()
