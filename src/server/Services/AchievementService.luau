--!strict
--[[
	Achievements (Config/Achievements; rules: Logic/AchievementRules). Each player's counts are checked every few
	seconds, and within a second of anything a goal counts (GameEvents: purchases, steals, new Snackdex entries...).
	An achievement reached for the first time sets its flag ach_<id> before paying, so it pays once per account; its
	prize goes through PrizeService, a toast says what it was, and its Roblox badge (if it has one) is awarded. A map
	a player has been on for Config/MapThemes.rotation.creditSeconds is recorded as the flag map_<id> for the map goals
	(MapThemeRules.creditDue: a quick switch through the maps counts for none), and each GameEvents "milestone" as the
	flag did_<milestone> for the milestone goals. The Trophies tab asks for the progress list (GetAchievements →
	AchievementSync).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Achievements = require(ReplicatedStorage.Shared.Config.Achievements)
local MapThemes = require(ReplicatedStorage.Shared.Config.MapThemes)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local GameData = require(ReplicatedStorage.Shared.GameData)
local AchievementRules = require(ReplicatedStorage.Shared.Logic.AchievementRules)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local GiftRules = require(ReplicatedStorage.Shared.Logic.GiftRules)
local MapThemeRules = require(ReplicatedStorage.Shared.Logic.MapThemeRules)
local Analytics = require(script.Parent.Analytics)
local GameEvents = require(script.Parent.GameEvents)
local MapThemeService = require(script.Parent.MapThemeService)
local PrizeService = require(script.Parent.PrizeService)
local Remotes = require(script.Parent.Remotes)
local Sessions = require(script.Parent.Sessions)

type Session = Sessions.Session

local AchievementService = {}

local FULL_CHECK_SECONDS = 10
local catalog = GameData.catalog
local pending: { [Session]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local checkedListeners: { (Session) -> () } = {}
-- The map each player was last seen on, and since when (server time; the first check on it).
local onMap: { [Session]: { id: string, since: number } } = setmetatable({}, { __mode = "k" }) :: any

-- Records the current map as played on (map_<id>) once `session`'s player has been on it long enough.
local function creditMap(session: Session)
	local id = MapThemeService.current()
	local t = workspace:GetServerTimeNow()
	local seen = onMap[session]
	if seen == nil or seen.id ~= id then
		seen = { id = id, since = t }
		onMap[session] = seen
	end
	if MapThemeRules.creditDue(seen.since, t, MapThemes.rotation) then
		session.data.flags[AchievementRules.mapFlagKey(id)] = true
	end
end

local function awardBadge(userId: number, badgeId: number)
	task.spawn(function()
		local ok, err = pcall(function()
			game:GetService("BadgeService"):AwardBadge(userId, badgeId)
		end)
		if not ok then
			warn(`[Achievements] badge {badgeId} for {userId}: {err}`)
		end
	end)
end

-- Records the current map (once played on long enough) and pays every achievement `session` has newly reached.
function AchievementService.check(session: Session)
	if not session.ready then
		return
	end
	local data = session.data
	creditMap(session)
	local ctx = AchievementRules.context(data, catalog.creatures, catalog.rarities)
	for _, def in AchievementRules.newlyDone(Achievements, ctx, data.flags, catalog.rarities) do
		data.flags[AchievementRules.flagKey(def.id)] = true
		local result = PrizeService.pay(session, def.reward, "Achievement")
		Remotes.notify(
			session.player,
			Format.template(Theme.text.achievementDone, { icon = def.icon, title = def.title, prize = result.text }),
			"success"
		)
		Analytics.custom(session, "achievement", nil, { def.id })
		if def.badgeId then
			awardBadge(session.userId, def.badgeId)
		end
	end
	for _, listener in checkedListeners do
		listener(session)
	end
end

-- Runs `listener` after every check of a player's achievements, once whatever it found is flagged and paid: titles and
-- base skins earned by achievements (StyleService) follow at once, with their toast after the achievement's.
function AchievementService.onChecked(listener: (Session) -> ())
	table.insert(checkedListeners, listener)
end

local function onGet(player: Player)
	local session = Sessions.get(player)
	if session == nil then
		return
	end
	local ctx = AchievementRules.context(session.data, catalog.creatures, catalog.rarities)
	Remotes.fire(
		player,
		"AchievementSync",
		AchievementRules.view(Achievements, ctx, session.data.flags, catalog.rarities)
	)
end

function AchievementService.start()
	for _, problem in
		AchievementRules.validate(Achievements, catalog.rarities, #MapThemes.order, function(reward, name)
			return GiftRules.rewardProblems(reward, name, catalog.mutations, true)
		end)
	do
		warn(`[Achievements] config problem: {problem}`)
	end
	GameEvents.on("AchievementService", function(session: Session, event: GameEvents.Event)
		local milestone = event.milestone
		if event.kind == "milestone" and milestone and AchievementRules.MILESTONES[milestone] then
			session.data.flags[AchievementRules.milestoneFlagKey(milestone)] = true
		end
		pending[session] = true
	end)
	Remotes.onIntent("GetAchievements", onGet)
	task.spawn(function()
		local sinceFull = 0
		while true do
			task.wait(1)
			sinceFull += 1
			local everyone = sinceFull >= FULL_CHECK_SECONDS
			if everyone then
				sinceFull = 0
			end
			for _, session in Sessions.all() do
				if everyone or pending[session] then
					pending[session] = nil
					local ok, err = pcall(AchievementService.check :: (Session) -> ...any, session)
					if not ok then
						warn(`[Achievements] {err}`)
					end
				end
			end
		end
	end)
end

return AchievementService
