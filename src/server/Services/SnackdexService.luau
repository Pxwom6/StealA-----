--!strict
--[[
	The Snackdex (collection book), server side. Rules: Logic/SnackdexRules; rewards: Config/Snackdex.

	* Discovery: every "acquired" GameEvent (a belt purchase through EconomyService.giveCreature, a delivered steal,
	  any future way a Snackling lands in a base) records the Snackling and its mutation in `data.snackdex`. Saves from
	  before the Snackdex were backfilled from what the player owned (DataSchema v3).
	* A new entry tells the owner's client (SnackdexSync with `discovered`: the "NEW!" toast and badge) and emits a
	  "discover" GameEvent (daily quests).
	* Tier completion is claimed automatically: when every regular Snackling of a tier has been owned, the tier's flag
	  is set and only then its one-time reward paid (steady income, like cash packs), with no yield in between, so it
	  pays once per account. The flag also adds the permanent collection bonus to the income multiplier
	  (EconomyService.multiplierInputs), so the economy is refreshed right after. Checked on every discovery and when
	  the client is ready (a backfilled save, or a config change that completed a tier).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Snackdex = require(ReplicatedStorage.Shared.Config.Snackdex)
local GameData = require(ReplicatedStorage.Shared.GameData)
local Types = require(ReplicatedStorage.Shared.Types)
local SnackdexRules = require(ReplicatedStorage.Shared.Logic.SnackdexRules)
local Analytics = require(script.Parent.Analytics)
local EconomyService = require(script.Parent.EconomyService)
local GameEvents = require(script.Parent.GameEvents)
local Remotes = require(script.Parent.Remotes)
local Sessions = require(script.Parent.Sessions)

type Session = Sessions.Session

local SnackdexService = {}

-- Sends the whole Snackdex to its owner, with what just happened. Deferred: the client hears about a discovery after
-- the purchase / steal toast of the same action. Nothing is sent before the client is ready (onReady sends it all).
local function sync(session: Session, discovered: Types.SnackdexDiscovery?, completed: { Types.SnackdexTierPaid }?)
	task.defer(function()
		if not session.ready or Sessions.get(session.player) ~= session then
			return
		end
		local payload: Types.SnackdexSync = {
			dex = SnackdexRules.view(session.data.snackdex, Snackdex),
			discovered = discovered,
			completed = if completed and #completed > 0 then completed else nil,
		}
		Remotes.fire(session.player, "SnackdexSync", payload)
	end)
end

-- Pays every complete tier whose reward hasn't been paid yet, in rarity order. Returns what was paid.
local function claimTiers(session: Session): { Types.SnackdexTierPaid }
	local catalog = GameData.catalog
	local dex = session.data.snackdex
	local paid: { Types.SnackdexTierPaid } = {}
	for _, rarityId in SnackdexRules.completedUnclaimed(dex, catalog.creatureList, catalog.rarityList) do
		-- Flag first, then pay, with no yield in between: a tier can only ever pay once per account.
		if SnackdexRules.claimTier(dex, rarityId) then
			local amount = SnackdexRules.tierReward(rarityId, session.packIncome, Snackdex)
			EconomyService.addCash(session, amount, "Gameplay", "SnackdexTier")
			table.insert(paid, { rarity = rarityId, amount = amount, bonus = Snackdex.incomeBonusPerTier })
			local rarity = catalog.rarities[rarityId]
			Analytics.snackdexTierCompleted(session, rarityId, if rarity then rarity.order else 0)
		end
	end
	if #paid > 0 then
		EconomyService.refresh(session) -- the collection bonus is part of the income multiplier
	end
	return paid
end

local function onAcquired(session: Session, creatureId: string, variant: string?)
	local newCreature, newVariant = SnackdexRules.discover(session.data.snackdex, creatureId, variant)
	if not newCreature and not newVariant then
		return
	end
	local completed = claimTiers(session)
	local discovery: Types.SnackdexDiscovery = {
		creatureId = creatureId,
		variant = if newVariant then variant else nil,
		newCreature = newCreature,
	}
	sync(session, discovery, completed)
	GameEvents.emit(session, { kind = "discover", creatureId = creatureId, variant = variant }) -- daily quests
end

-- PlayerLifecycle onReady hook: the whole Snackdex for the client, after paying any tier completed while away
-- (a save backfilled by the v3 migration, or a config change).
function SnackdexService.onReady(session: Session)
	sync(session, nil, claimTiers(session))
end

-- Studio /dex fill <rarity>: every regular Snackling of the tier (or every event one, "Event") discovered but one, and
-- the tier's reward flag cleared, so buying the last one tests completion. Returns the Snackling left out.
function SnackdexService.devFill(session: Session, sectionId: string): Types.CreatureDef?
	local owned: { [string]: boolean } = {}
	for _, list in { session.data.creatures, session.data.quarantine } do
		for _, record in list do
			owned[record.id] = true
		end
	end
	local leftOut = SnackdexRules.devFill(session.data.snackdex, GameData.catalog.creatureList, sectionId, owned)
	EconomyService.refresh(session) -- the tier's bonus is off until it is completed again
	sync(session, nil, nil)
	return leftOut
end

function SnackdexService.start()
	GameEvents.on("SnackdexService", function(session: Session, event: GameEvents.Event)
		if event.kind == "acquired" and event.creatureId ~= nil then
			onAcquired(session, event.creatureId, event.variant)
		end
	end)
end

return SnackdexService
