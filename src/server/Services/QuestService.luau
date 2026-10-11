--!strict
--[[
	Daily quests, server side. Rules: Logic/QuestRules; quests and rewards: Config/Quests.

	* Each player has three quests per UTC day in `data.quests`, rolled from their UserId and the day (DailyStreak's day
	  maths), so every server rolls the same ones and rejoining never re-rolls. They are rolled on join and, for players
	  online at UTC midnight, by a 10 s check (or the first event or claim after it).
	* Progress comes only from GameEvents (what the server saw happen, the same hook points as the tutorial): belt
	  purchases, pad collects, sells, locks, delivered steals and new Snackdex entries.
	* ClaimQuest(slot) (rate-limited) pays a finished quest: QuestRules.claim marks it claimed (and the all-done bonus,
	  with the last quest) before the cash is added, with no yield in between, so nothing can pay twice. Rewards are
	  sized from the steady income (session.packIncome: no LiveOps cash event, no friend & group bonus), like cash packs.
	* At the day change, quests that were finished but not claimed are paid automatically before the new ones roll.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Quests = require(ReplicatedStorage.Shared.Config.Quests)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local GameData = require(ReplicatedStorage.Shared.GameData)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local DailyStreak = require(ReplicatedStorage.Shared.Logic.DailyStreak)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local Guard = require(ReplicatedStorage.Shared.Logic.Guard)
local QuestRules = require(ReplicatedStorage.Shared.Logic.QuestRules)
local Analytics = require(script.Parent.Analytics)
local EconomyService = require(script.Parent.EconomyService)
local GameEvents = require(script.Parent.GameEvents)
local PlotService = require(script.Parent.PlotService)
local Remotes = require(script.Parent.Remotes)
local Replication = require(script.Parent.Replication)
local Sessions = require(script.Parent.Sessions)

type Session = Sessions.Session

local DAY_CHECK_SECONDS = 10
local MAX_SLOT = 8 -- DataSchema keeps at most 8 quests

local QuestService = {}

local questDefs = QuestRules.index(Quests.pool)
local rarityOrders: { [string]: number } = {}
for _, rarity in GameData.catalog.rarityList do
	rarityOrders[rarity.id] = rarity.order
end

local function today(): number
	return DailyStreak.dayIndex(os.time())
end

-- Pays one claimed quest (and the all-done bonus when this claim finished the day). `how`: "claim" or "auto".
-- Returns the amount paid.
local function pay(session: Session, def: QuestRules.QuestDef, allDone: boolean, how: string): number
	local amount = QuestRules.reward(def.difficulty, session.packIncome, Quests)
	EconomyService.addCash(session, amount, "TimedReward", "Quest")
	Analytics.questClaimed(session, def.id, def.difficulty, how)
	if allDone then
		local bonus = QuestRules.bonus(session.packIncome, Quests)
		EconomyService.addCash(session, bonus, "TimedReward", "QuestBonus")
		Analytics.questsAllDone(session, how)
		amount += bonus
	end
	return amount
end

-- Makes sure the saved quests are today's: pays what was finished but not claimed on an earlier day, then rolls
-- today's. Returns true when it rolled.
local function ensureToday(session: Session): boolean
	local quests = session.data.quests
	local day = today()
	if not QuestRules.isStale(quests, day) then
		return false
	end
	local autoPaid = 0
	for index in quests.list do
		local def, allDone = QuestRules.claim(quests, index, questDefs)
		if def then
			autoPaid += pay(session, def, allDone, "auto")
		end
	end
	QuestRules.roll(quests, session.userId, day, Quests, session.packIncome)
	Replication.markDirty(session)
	if autoPaid > 0 then
		Remotes.notify(
			session.player,
			Format.template(Theme.text.questAutoClaimed, { amount = UiTheme.cash(autoPaid) }),
			"success"
		)
	end
	return true
end

-- PlayerLifecycle onJoined hook (income is computed by then, so a "collect" target is sized from it). Never throws:
-- a quest bug must not stop the join.
function QuestService.onJoined(session: Session)
	local ok, err = pcall(ensureToday, session)
	if not ok then
		warn(`[QuestService] join failed for {session.player.Name}: {err}`)
	end
end

local function onEvent(session: Session, event: GameEvents.Event)
	if not QuestRules.KINDS[event.kind] then
		return
	end
	if ensureToday(session) and session.ready then
		Remotes.notify(session.player, Theme.text.questsNew, "info") -- this event already counts for the new day
	end
	local rarityOrder: number? = nil
	local def = if event.creatureId then GameData.catalog.creatures[event.creatureId] else nil
	if def then
		rarityOrder = rarityOrders[def.rarity]
	end
	local changed, finished = QuestRules.apply(
		session.data.quests,
		{ kind = event.kind, amount = event.amount, rarityOrder = rarityOrder },
		questDefs,
		rarityOrders
	)
	if not changed then
		return
	end
	Replication.markDirty(session)
	-- During the first-time tutorial the badge on Rewards is enough: a new player's first minute belongs to the loop.
	if session.tutorial == nil and #finished > 0 then
		local amounts: { number } = {}
		for _, index in finished do
			local quest = questDefs[session.data.quests.list[index].id]
			table.insert(amounts, QuestRules.reward(quest.difficulty, session.packIncome, Quests))
		end
		-- Deferred: after the toast of the action itself ("You stole ...!").
		task.defer(function()
			if session.player.Parent == nil then
				return
			end
			for _, amount in amounts do
				Remotes.notify(
					session.player,
					Format.template(Theme.text.questComplete, { amount = UiTheme.cash(amount) }),
					"success"
				)
			end
		end)
	end
end

local function onClaim(player: Player, slotArg: unknown)
	local slot = Guard.integer(slotArg, 1, MAX_SLOT)
	local session = Sessions.get(player)
	if slot == nil or session == nil then
		return
	end
	if ensureToday(session) then
		return -- the panel showed yesterday's quests: anything finished was just paid automatically
	end
	local quests = session.data.quests
	local def, allDone = QuestRules.claim(quests, slot, questDefs)
	if def == nil then
		return -- not finished, already claimed, or unknown: nothing to pay (a double tap lands here)
	end
	local amount = pay(session, def, allDone, "claim")
	Replication.markDirty(session)
	Remotes.notify(
		player,
		Format.template(
			if allDone then Theme.text.questAllDone else Theme.text.questReward,
			{ amount = UiTheme.cash(amount) }
		),
		"success"
	)
	if session.plot ~= 0 then
		Remotes.fire(player, "Effect", {
			kind = if allDone then "questsAllDone" else "quest",
			position = PlotService.refs(session.plot).spawnCFrame.Position,
		})
	end
end

-- Studio /quests reset: re-rolls today's quests with a random salt (progress, claims and the bonus start over).
function QuestService.devReset(session: Session)
	QuestRules.roll(session.data.quests, session.userId, today(), Quests, session.packIncome, math.random(1, 2 ^ 30))
	Replication.markDirty(session)
end

function QuestService.start()
	Remotes.onIntent("ClaimQuest", onClaim)
	GameEvents.on("QuestService", onEvent)
	task.spawn(function()
		while true do
			task.wait(DAY_CHECK_SECONDS)
			for _, session in Sessions.all() do
				local ok, rolled = pcall(ensureToday, session)
				if not ok then
					warn(`[QuestService] day check failed for {session.player.Name}: {rolled}`)
				elseif rolled and session.ready then
					Remotes.notify(session.player, Theme.text.questsNew, "info")
				end
			end
		end
	end)
end

return QuestService
