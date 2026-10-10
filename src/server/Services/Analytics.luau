--!strict
--[[
	Thin wrapper over AnalyticsService (Creator Hub → Analytics → Funnels / Economy / Custom).

	Onboarding funnel (each step logged once per player, tracked in the save so rejoining doesn't re-log):
	  1 Joined  2 FirstBeltPurchase  3 FirstCollect  4 FirstSteal  5 FirstRebirth
	Store funnel (recurring, one funnel session per store visit):
	  1 StoreOpened  2 ProductPrompted  3 ProductPurchased
	Economy events: cash sources and sinks (collect events are aggregated per minute to stay within limits).
	Custom events: e.g. "mutation_bought" (value = mutation order; CustomField01 = mutation id, 02 = creature id).

	Every call is pcall'd: analytics must never break gameplay (and is a no-op in some Studio configurations).
]]

local AnalyticsService = game:GetService("AnalyticsService")
local HttpService = game:GetService("HttpService")

local Sessions = require(script.Parent.Sessions)

type Session = Sessions.Session

local Analytics = {}

local ONBOARDING_STEPS: { [string]: number } = {
	Joined = 1,
	FirstBeltPurchase = 2,
	FirstCollect = 3,
	FirstSteal = 4,
	FirstRebirth = 5,
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

function Analytics.storeStep(session: Session, name: string, customFields: { [string]: any }?)
	local step = STORE_STEPS[name]
	if step == nil then
		return
	end
	if step == 1 or storeFunnels[session.userId] == nil then
		storeFunnels[session.userId] = HttpService:GenerateGUID(false)
	end
	local funnelId = storeFunnels[session.userId]
	safe(function()
		AnalyticsService:LogFunnelStepEvent(session.player, "Store", funnelId, step, name, customFields)
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

function Analytics.custom(session: Session, name: string, value: number?, customFields: { [string]: any }?)
	safe(function()
		AnalyticsService:LogCustomEvent(session.player, name, value, customFields)
	end)
end

-- A mutated creature was bought off the belt. Breakdowns use the Creator Hub's custom-field keys.
function Analytics.mutationBought(session: Session, mutationId: string, mutationOrder: number, creatureId: string)
	Analytics.custom(session, "mutation_bought", mutationOrder, {
		[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = mutationId,
		[Enum.AnalyticsCustomFieldKeys.CustomField02.Name] = creatureId,
	})
end

function Analytics.forget(session: Session)
	storeFunnels[session.userId] = nil
	pendingCollect[session.player] = nil
end

return Analytics
