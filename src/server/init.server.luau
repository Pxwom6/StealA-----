--!strict
--[[
	Server entry point. Services are started explicitly, in dependency order; PlayerLifecycle goes last so
	every system is ready before the first player is processed. Cross-service join/leave steps are wired here
	through PlayerLifecycle hooks, which keeps the services free of circular requires.
]]

local Services = script.Services

local AchievementService = require(Services.AchievementService)
local Analytics = require(Services.Analytics)
local AutoCollectService = require(Services.AutoCollectService)
local BeltService = require(Services.BeltService)
local BossService = require(Services.BossService)
local BountyService = require(Services.BountyService)
local CodeService = require(Services.CodeService)
local CrossServer = require(Services.CrossServer)
local DataService = require(Services.DataService)
local DevCommands = require(Services.DevCommands)
local DropService = require(Services.DropService)
local EconomyService = require(Services.EconomyService)
local GadgetService = require(Services.GadgetService)
local GiftService = require(Services.GiftService)
local HostService = require(Services.HostService)
local LeaderboardService = require(Services.LeaderboardService)
local LiveOpsService = require(Services.LiveOpsService)
local LockService = require(Services.LockService)
local MapBuilder = require(Services.MapBuilder)
local MapThemeService = require(Services.MapThemeService)
local ModifierService = require(Services.ModifierService)
local MonetizationService = require(Services.MonetizationService)
local NewsService = require(Services.NewsService)
local PlayerLifecycle = require(Services.PlayerLifecycle)
local PlayerPolicy = require(Services.PlayerPolicy)
local PlotService = require(Services.PlotService)
local PositionTracker = require(Services.PositionTracker)
local QuestService = require(Services.QuestService)
local RebirthService = require(Services.RebirthService)
local Remotes = require(Services.Remotes)
local Replication = require(Services.Replication)
local RetentionService = require(Services.RetentionService)
local SeasonService = require(Services.SeasonService)
local SettingsService = require(Services.SettingsService)
local ShoutoutService = require(Services.ShoutoutService)
local SnackdexService = require(Services.SnackdexService)
local SocialService = require(Services.SocialService)
local SpinService = require(Services.SpinService)
local StealService = require(Services.StealService)
local StoreService = require(Services.StoreService)
local StyleService = require(Services.StyleService)
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
DropService.start(world.walkwayY) -- crates, coins, runaways and golden forks while a drop modifier runs
BossService.start(world.walkwayY) -- Snack Attack: giant Snacklings over the belt for everyone to tap together
LockService.start()
StealService.start()
GadgetService.start() -- cash-bought gear: speed, banana peels, shields, magnets (after steals: peels drop carries)
AutoCollectService.start() -- the Auto Collect pass: every pad's cash every few seconds, through the pad path
RebirthService.start()
PlayerPolicy.start() -- each player's PolicyService answer: paid random items (Server Luck, spin packs) only where allowed
MonetizationService.start()
StoreService.start() -- the store's analytics, and purchases checked before the prompt (spin packs, the Starter Pack)
RetentionService.start()
SocialService.start()
TutorialService.start(EconomyService.addCash) -- pays the one-time completion reward; first GameEvents listener
SnackdexService.start() -- after the tutorial: discoveries (and the quest event they emit) follow its steps
QuestService.start()
BountyService.start() -- Bounty Hunt: a bounty on the top earner, claimed by tags and steals (a GameEvents listener)
LeaderboardService.start(world)
SettingsService.start() -- music / sound effects / reduce effects, saved in flags
CodeService.start() -- redeem codes (server/Codes.luau), once per account, saved in flags
GiftService.start() -- playtime gifts: a daily ladder that unlocks with time in game
SpinService.start() -- the Lucky Spin: a free spin every 12 hours, plus spins from gifts
AchievementService.start() -- achievements paid once each, checked after every game event
StyleService.start() -- titles and base skins (Settings ▸ Style), unlocked by achievements, rebirths and the Snackdex
AchievementService.onChecked(StyleService.check) -- a toast for each title or skin unlocked, after the achievement's
NewsService.start(world) -- What's New: the card for returning players, the board on the spawn plaza
HostService.start() -- the host panel (admins, private-server owners) and the admin chat commands
ShoutoutService.start() -- rare pulls told to every other server
CrossServer.start() -- listens for other servers' admin actions and shout-outs (never in Studio)
DevCommands.start() -- Studio only

local hooks = PlayerLifecycle.hooks()
hooks.checkPasses = MonetizationService.checkPasses
table.insert(hooks.onJoined, LockService.refresh)
table.insert(hooks.onJoined, LockService.restore)
table.insert(hooks.onJoined, RetentionService.payOfflineEarnings)
table.insert(hooks.onJoined, SocialService.onJoined)
table.insert(hooks.onJoined, TutorialService.onJoined) -- after the lock timers are restored
table.insert(hooks.onJoined, NewsService.onJoined) -- after the tutorial: new players get it instead of What's New
table.insert(hooks.onJoined, QuestService.onJoined) -- after income is computed (collect targets, rewards)
table.insert(hooks.onJoined, HostService.refresh) -- shows the host panel row to admins and a private server's owner
table.insert(hooks.onJoined, StyleService.onJoined) -- the title over their head, their base's skin
table.insert(hooks.onCharacter, StyleService.onCharacter) -- the nametag on every new character
table.insert(hooks.onReady, RetentionService.sendWelcome)
table.insert(hooks.onReady, SnackdexService.onReady)
table.insert(hooks.onReady, NewsService.onReady) -- the What's New card, when the client shows it
table.insert(hooks.onLeaving, function(session)
	StealService.releaseAll(session, "left")
end)
table.insert(hooks.onLeaving, LockService.onLeaving)
table.insert(hooks.onLeaving, GadgetService.onLeaving)
table.insert(hooks.onLeaving, BountyService.onLeaving) -- the target leaving: the next top earner gets it
table.insert(hooks.onLeaving, SocialService.onLeaving)
table.insert(hooks.onLeaving, TutorialService.onLeaving)
table.insert(hooks.onLeaving, function(session)
	task.spawn(LeaderboardService.writePlayer, session)
end)

PlayerLifecycle.start()
