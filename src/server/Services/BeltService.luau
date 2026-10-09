--!strict
--[[
	The conveyor. Every `belt.spawnInterval` seconds a creature is rolled (weighted rarity × server luck, event
	creatures only during their event) and broadcast to clients as {id, creatureId, spawnAt}. Items are not
	physics objects: position is a pure function of spawn time (Logic/BeltMath), clients render pooled models,
	and the server validates every purchase against where the item really is.

	BuyBeltItem(itemId) checks: item exists and is on the belt, buyer is in range of it, buyer has a free podium
	and enough cash at the SERVER's price. Then the creature "teleports" to the buyer's base.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Gameplay = require(ReplicatedStorage.Shared.Config.Gameplay)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local GameData = require(ReplicatedStorage.Shared.GameData)
local BeltMath = require(ReplicatedStorage.Shared.Logic.BeltMath)
local Guard = require(ReplicatedStorage.Shared.Logic.Guard)
local RarityRoll = require(ReplicatedStorage.Shared.Logic.RarityRoll)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local Analytics = require(script.Parent.Analytics)
local Announcer = require(script.Parent.Announcer)
local EconomyService = require(script.Parent.EconomyService)
local LiveOpsService = require(script.Parent.LiveOpsService)
local PlotService = require(script.Parent.PlotService)
local Remotes = require(script.Parent.Remotes)
local Sessions = require(script.Parent.Sessions)

type Session = Sessions.Session

local Types = require(ReplicatedStorage.Shared.Types)

export type BeltItem = Types.BeltItem

local BeltService = {}

local belt: BeltMath.Belt
local items: { [number]: BeltItem } = {}
local nextId = 1
local rng = Random.new()

local function now(): number
	return workspace:GetServerTimeNow()
end

local function itemList(): { BeltItem }
	local list: { BeltItem } = {}
	for _, item in items do
		table.insert(list, item)
	end
	return list
end

local function prune(t: number)
	for id, item in items do
		if BeltMath.isExpired(belt, item.spawnAt, t) then
			items[id] = nil
		end
	end
end

local function spawnOne(forcedId: string?)
	local t = now()
	prune(t)
	local count = 0
	for _ in items do
		count += 1
	end
	if count >= Gameplay.belt.maxItems and forcedId == nil then
		return
	end
	local catalog = GameData.catalog
	local creatureId = forcedId
		or RarityRoll.roll(
			catalog.rarityList,
			catalog.creatureList,
			LiveOpsService.luckMultiplier(),
			LiveOpsService.activeEventIds(),
			function(): number
				return rng:NextNumber()
			end
		)
	if creatureId == nil or catalog.creatures[creatureId] == nil then
		return
	end
	local item: BeltItem = { id = nextId, creatureId = creatureId, spawnAt = t }
	nextId += 1
	items[item.id] = item
	Remotes.fireAll("BeltSpawn", item)

	local def = catalog.creatures[creatureId]
	local rarity = catalog.rarities[def.rarity]
	if rarity.announceOnSpawn then
		Announcer.broadcast({
			text = Format.template(
				Theme.text.announceSpawn,
				{ rarity = rarity.displayName, creature = def.displayName }
			),
			rarity = rarity.id,
			kind = "spawn",
		})
	end
end

local function onBuy(player: Player, idArg: unknown)
	local id = Guard.integer(idArg, 1, 2 ^ 40)
	local session = Sessions.get(player)
	if id == nil or session == nil or session.plot == 0 then
		return
	end
	local item = items[id]
	local t = now()
	if item == nil or BeltMath.isExpired(belt, item.spawnAt, t) then
		return -- sold or gone; the client will catch up from BeltRemove / expiry
	end
	if session.carry ~= nil then
		Remotes.notify(player, Theme.text.alreadyCarrying, "error")
		return
	end
	local root = Sessions.rootPart(session)
	if root == nil then
		return
	end
	local cfg = Gameplay.belt
	local distance = BeltMath.distanceTo(belt, item.spawnAt, t, root.Position.X, root.Position.Z, cfg.latencyTolerance)
	if distance > cfg.buyRange then
		Remotes.notify(player, Theme.text.tooFar, "error")
		return
	end
	if EconomyService.freePodium(session) == nil then
		Remotes.notify(player, Theme.text.baseFull, "error")
		return
	end
	local def = GameData.catalog.creatures[item.creatureId]
	if not EconomyService.trySpend(session, def.price, "Shop", def.id) then
		Remotes.notify(player, Theme.text.notEnoughCash, "error")
		return
	end

	items[id] = nil
	local record = EconomyService.giveCreature(session, def.id)
	if record == nil then
		-- Cannot happen (free podium checked above, no yield in between), but never take cash for nothing.
		EconomyService.addCash(session, def.price)
		return
	end
	session.data.stats.beltPurchases += 1
	Analytics.milestone(session, "FirstBeltPurchase")

	local podium = PlotService.podium(session.plot, record.podium)
	Remotes.fireAll("BeltRemove", {
		id = id,
		buyerUserId = session.userId,
		target = if podium then podium.standCFrame.Position else nil,
	})
	Remotes.notify(player, Format.template(Theme.text.boughtCreature, { creature = def.displayName }), "success")

	local rarity = GameData.catalog.rarities[def.rarity]
	if rarity.announceOnBuy then
		Announcer.broadcast({
			text = Format.template(Theme.text.announceBuy, {
				player = player.DisplayName,
				rarity = rarity.displayName,
				creature = def.displayName,
			}),
			rarity = rarity.id,
			kind = "buy",
		})
	end
end

-- Sent to a client once it is ready (late joiners see what is already on the belt).
function BeltService.sendSnapshot(player: Player)
	prune(now())
	Remotes.fire(player, "BeltSnapshot", itemList())
end

-- Puts a specific creature on the belt now (Studio dev command / future events).
function BeltService.spawnCreature(creatureId: string)
	spawnOne(creatureId)
end

function BeltService.belt(): BeltMath.Belt
	return belt
end

function BeltService.start(beltDef: BeltMath.Belt)
	belt = beltDef
	Remotes.onIntent("BuyBeltItem", onBuy)
	task.spawn(function()
		while true do
			spawnOne()
			task.wait(Gameplay.belt.spawnInterval)
		end
	end)
end

return BeltService
