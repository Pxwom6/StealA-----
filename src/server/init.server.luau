--!strict
--[[
	Server entry point. Services are started explicitly, in dependency order; PlayerLifecycle goes last so
	every system is ready before the first player is processed. Cross-service join/leave steps are wired here
	through PlayerLifecycle hooks, which keeps the services free of circular requires.
]]

local Services = script.Services

local AchievementService = require(Services.AchievementService)
local Analytics = require(Services.Analytics)
local BeltService = require(Services.BeltService)
local BossService = require(Services.BossService)
local CodeService = require(Services.CodeService)
local DataService = require(Services.DataService)
local DevCommands = require(Services.DevCommands)
local DropService = require(Services.DropService)
local EconomyService = require(Services.EconomyService)
local GiftService = require(Services.GiftService)
local LeaderboardService = require(Services.LeaderboardService)
local LiveOpsService = require(Services.LiveOpsService)
local LockService = require(Services.LockService)
local MapBuilder = require(Services.MapBuilder)
local MapThemeService = require(Services.MapThemeService)
local ModifierService = require(Services.ModifierService)
local MonetizationService = require(Services.MonetizationService)
local PlayerLifecycle = require(Services.PlayerLifecycle)
local PlotService = require(Services.PlotService)
local PositionTracker = require(Services.PositionTracker)
local QuestService = require(Services.QuestService)
local RebirthService = require(Services.RebirthService)
local Remotes = require(Services.Remotes)
local Replication = require(Services.Replication)
local RetentionService = require(Services.RetentionService)
local SeasonService = require(Services.SeasonService)
local SettingsService = require(Services.SettingsService)
local SnackdexService = require(Services.SnackdexService)
local SocialService = require(Services.SocialService)
local SpinService = require(Services.SpinService)
local StealService = require(Services.StealService)
local TutorialService = require(Services.TutorialService)

Remotes.start()
DataService.start()

local firstMap = MapThemeService.firstMap() -- a random map theme (Config/MapThemes); the map is built dressed as it
local world = MapBuilder.build(firstMap)
PlotService.start(world)

Analytics.start()
LiveOpsService.start()
SeasonService.start(world) -- seasonal decorations + lighting follow the active LiveOps events
MapThemeService.start(firstMap) -- the map changes every so often, after a vote
ModifierService.start() -- random server twists every few minutes (systems read its effects; after LiveOps: luck)
Replication.start()
PositionTracker.start()
EconomyService.start()
BeltService.start(world.belt)
DropService.start(world.walkwayY) -- crates, coins and runaways on the walkways while a drop modifier runs
BossService.start(world.walkwayY) -- Snack Attack: giant Snacklings over the belt for everyone to tap together
LockService.start()
StealService.start()
RebirthService.start()
MonetizationService.start()
RetentionService.start()
SocialService.start()
TutorialService.start(EconomyService.addCash) -- pays the one-time completion reward; first GameEvents listener
SnackdexService.start() -- after the tutorial: discoveries (and the quest event they emit) follow its steps
QuestService.start()
LeaderboardService.start(world)
SettingsService.start() -- music / sound effects / reduce effects, saved in flags
CodeService.start() -- redeem codes (server/Codes.luau), once per account, saved in flags
GiftService.start() -- playtime gifts: a daily ladder that unlocks with time in game
SpinService.start() -- the Lucky Spin: a free spin every 12 hours, plus spins from gifts
AchievementService.start() -- achievements paid once each, checked after every game event
DevCommands.start() -- Studio only

local hooks = PlayerLifecycle.hooks()
hooks.checkPasses = MonetizationService.checkPasses
table.insert(hooks.onJoined, LockService.refresh)
table.insert(hooks.onJoined, LockService.restore)
table.insert(hooks.onJoined, RetentionService.payOfflineEarnings)
table.insert(hooks.onJoined, SocialService.onJoined)
table.insert(hooks.onJoined, TutorialService.onJoined) -- after the lock timers are restored
table.insert(hooks.onJoined, QuestService.onJoined) -- after income is computed (collect targets, rewards)
table.insert(hooks.onReady, RetentionService.sendWelcome)
table.insert(hooks.onReady, SnackdexService.onReady)
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
