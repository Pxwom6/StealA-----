--!strict
--[[
	Thin wrapper over AnalyticsService (Creator Hub → Analytics → Funnels / Economy / Custom).

	Onboarding funnel (each step logged once per player, tracked in the save so rejoining doesn't re-log). Steps 2-5
	follow the first-time tutorial (Config/Tutorial: buy, collect, lock, steal):
	  1 Joined  2 FirstBeltPurchase  3 FirstCollect  4 TutorialLock (the lock step ended: locked, or it moved on by
	  itself)  5 TutorialComplete (completed and rewarded; a skip never logs it)  6 FirstSteal  7 FirstRebirth
	Roblox counts a logged step as completing every earlier one, so a funnel step must be one every player passes in
	order: skipping the tutorial is the custom event `tutorial_skipped` instead, and exact completion / skip rates come
	from `tutorial_step` and `tutorial_skipped` (a player who skipped and later steals shows steps 4-5 as completed in
	the funnel view). Steps are matched by number: never renumber a step once the game is live (DECISIONS.md #21).
	Store funnel (recurring, one funnel session per store visit):
	  1 StoreOpened  2 ProductPrompted  3 ProductPurchased
	Economy events: cash sources and sinks (collect events are aggregated per minute to stay within limits).
	Custom events and funnel steps can carry up to three breakdown fields. AnalyticsService only accepts the keys
	CustomField01..03 (any other key is silently dropped), so callers pass the values IN ORDER as a list (`Fields`)
	and they are mapped to those keys here. What each position means, per event:
	  store funnel ProductPurchased        01 kind ("pass" | "product")  02 item key
	  store funnel ProductPrompted         01 item key
	  pass_purchased / product_purchased   01 item key
	  steal                                01 creature id  02 mutation id ("" when plain)
	  mutation_bought                      01 mutation id  02 creature id  (value = mutation order)
	  tutorial_step                        01 step id  02 outcome ("done" | "early" | "unavailable" | "timeout")
	                                       (value = whole seconds spent on the step)
	  tutorial_skipped                     01 step id the player skipped at  (value = that step's number)

	Every call is pcall'd: analytics must never break gameplay (and is a no-op in some Studio configurations).
]]

local AnalyticsService = game:GetService("AnalyticsService")
local HttpService = game:GetService("HttpService")

local Sessions = require(script.Parent.Sessions)

type Session = Sessions.Session

-- Breakdown values in order: [1] -> CustomField01, [2] -> CustomField02, [3] -> CustomField03.
export type Fields = { string }

local Analytics = {}

local FIELD_KEYS: { string } = {
	Enum.AnalyticsCustomFieldKeys.CustomField01.Name,
	Enum.AnalyticsCustomFieldKeys.CustomField02.Name,
	Enum.AnalyticsCustomFieldKeys.CustomField03.Name,
}

-- The only custom-field shape AnalyticsService accepts. More than three values is a programming error: the extra
-- ones are dropped with a warning instead of failing the event.
local function customFields(fields: Fields?): { [string]: string }?
	if fields == nil then
		return nil
	end
	local result: { [string]: string } = {}
	for index, value in fields do
		local key = FIELD_KEYS[index]
		if key == nil then
			warn(`[Analytics] only {#FIELD_KEYS} custom fields are allowed; dropped the rest`)
			break
		end
		result[key] = value
	end
	return result
end

local ONBOARDING_STEPS: { [string]: number } = {
	Joined = 1,
	FirstBeltPurchase = 2,
	FirstCollect = 3,
	TutorialLock = 4,
	TutorialComplete = 5,
	FirstSteal = 6,
	FirstRebirth = 7,
}

local STORE_STEPS: { [string]: number } = {
	StoreOpened = 1,
	ProductPrompted = 2,
	ProductPurchased = 3,
}

local CURRENCY = "Cash"

local storeFunnels: { [number]: string } = {}
local pendingCollect: { [Player]: number } = {}

local function safe(fn: () -> ())
	local ok, err = pcall(fn :: () -> ...any)
	if not ok then
		warn(`[Analytics] {err}`)
	end
end

function Analytics.start()
	task.spawn(function()
		while true do
			task.wait(60)
			for player, amount in pendingCollect do
				local session = Sessions.get(player)
				if session and amount > 0 then
					Analytics.economySource(session, amount, "Gameplay", "Collect")
				end
			end
			table.clear(pendingCollect)
		end
	end)
end

-- Logs an onboarding milestone once per player (ever). Returns true the first time.
function Analytics.milestone(session: Session, name: string): boolean
	local step = ONBOARDING_STEPS[name]
	if step == nil then
		return false
	end
	local flag = "ob_" .. name
	if session.data.flags[flag] then
		return false
	end
	session.data.flags[flag] = true
	safe(function()
		AnalyticsService:LogOnboardingFunnelStepEvent(session.player, step, name)
	end)
	return true
end

function Analytics.storeStep(session: Session, name: string, fields: Fields?)
	local step = STORE_STEPS[name]
	if step == nil then
		return
	end
	if step == 1 or storeFunnels[session.userId] == nil then
		storeFunnels[session.userId] = HttpService:GenerateGUID(false)
	end
	local funnelId = storeFunnels[session.userId]
	safe(function()
		AnalyticsService:LogFunnelStepEvent(session.player, "Store", funnelId, step, name, customFields(fields))
	end)
end

function Analytics.economySource(session: Session, amount: number, transactionType: string, sku: string?)
	if amount < 1 then
		return
	end
	safe(function()
		AnalyticsService:LogEconomyEvent(
			session.player,
			Enum.AnalyticsEconomyFlowType.Source,
			CURRENCY,
			math.floor(amount),
			math.floor(session.data.cash),
			transactionType,
			sku
		)
	end)
end

function Analytics.economySink(session: Session, amount: number, transactionType: string, sku: string?)
	if amount < 1 then
		return
	end
	safe(function()
		AnalyticsService:LogEconomyEvent(
			session.player,
			Enum.AnalyticsEconomyFlowType.Sink,
			CURRENCY,
			math.floor(amount),
			math.floor(session.data.cash),
			transactionType,
			sku
		)
	end)
end

-- Collects happen every few seconds; they are summed and logged once a minute.
function Analytics.collect(session: Session, amount: number)
	pendingCollect[session.player] = (pendingCollect[session.player] or 0) + amount
end

function Analytics.custom(session: Session, name: string, value: number?, fields: Fields?)
	safe(function()
		AnalyticsService:LogCustomEvent(session.player, name, value, customFields(fields))
	end)
end

-- A mutated creature was bought off the belt.
function Analytics.mutationBought(session: Session, mutationId: string, mutationOrder: number, creatureId: string)
	Analytics.custom(session, "mutation_bought", mutationOrder, { mutationId, creatureId })
end

-- A tutorial step ended (`outcome`: TutorialRules.StepOutcome) after `seconds` on it.
function Analytics.tutorialStep(session: Session, stepId: string, outcome: string, seconds: number)
	Analytics.custom(session, "tutorial_step", math.max(0, math.floor(seconds)), { stepId, outcome })
end

-- The player pressed Skip on step number `stepIndex` (`stepId`).
function Analytics.tutorialSkipped(session: Session, stepId: string, stepIndex: number)
	Analytics.custom(session, "tutorial_skipped", stepIndex, { stepId })
end

function Analytics.forget(session: Session)
	storeFunnels[session.userId] = nil
	pendingCollect[session.player] = nil
end

return Analytics
