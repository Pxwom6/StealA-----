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
local DevCommands = require(Services.DevCommands)
local EconomyService = require(Services.EconomyService)
local LeaderboardService = require(Services.LeaderboardService)
local LiveOpsService = require(Services.LiveOpsService)
local LockService = require(Services.LockService)
local MapBuilder = require(Services.MapBuilder)
local MonetizationService = require(Services.MonetizationService)
local PlayerLifecycle = require(Services.PlayerLifecycle)
local PlotService = require(Services.PlotService)
local PositionTracker = require(Services.PositionTracker)
local RebirthService = require(Services.RebirthService)
local Remotes = require(Services.Remotes)
local Replication = require(Services.Replication)
local RetentionService = require(Services.RetentionService)
local SeasonService = require(Services.SeasonService)
local SettingsService = require(Services.SettingsService)
local SocialService = require(Services.SocialService)
local StealService = require(Services.StealService)
local TutorialService = require(Services.TutorialService)

Remotes.start()
DataService.start()

local world = MapBuilder.build()
PlotService.start(world)

Analytics.start()
LiveOpsService.start()
SeasonService.start(world) -- seasonal decorations + lighting follow the active LiveOps events
Replication.start()
PositionTracker.start()
EconomyService.start()
BeltService.start(world.belt)
LockService.start()
StealService.start()
RebirthService.start()
MonetizationService.start()
RetentionService.start()
SocialService.start()
TutorialService.start(EconomyService.addCash) -- pays the one-time completion reward
LeaderboardService.start(world)
SettingsService.start() -- music / sound effects / reduce effects, saved in flags
DevCommands.start() -- Studio only

local hooks = PlayerLifecycle.hooks()
hooks.checkPasses = MonetizationService.checkPasses
table.insert(hooks.onJoined, LockService.refresh)
table.insert(hooks.onJoined, LockService.restore)
table.insert(hooks.onJoined, RetentionService.payOfflineEarnings)
table.insert(hooks.onJoined, SocialService.onJoined)
table.insert(hooks.onJoined, TutorialService.onJoined) -- after the lock timers are restored
table.insert(hooks.onReady, RetentionService.sendWelcome)
table.insert(hooks.onLeaving, function(session)
	StealService.releaseAll(session, "left")
end)
table.insert(hooks.onLeaving, LockService.onLeaving)
table.insert(hooks.onLeaving, SocialService.onLeaving)
table.insert(hooks.onLeaving, TutorialService.onLeaving)
table.insert(hooks.onLeaving, function(session)
	task.spawn(LeaderboardService.writePlayer, session)
end)

PlayerLifecycle.start()
