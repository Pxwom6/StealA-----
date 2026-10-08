--!strict
--[[
	Cash in, cash out.

	* Income tick (every Gameplay.incomeTickSeconds): each creature adds income × multiplier to its podium's
	  `stored` cash (saved, so it survives rejoining).
	* Collecting: 4×/s the server checks whether each owner's character stands on one of their collect pads and
	  moves that podium's stored cash into their wallet. Purely position-based: no client remote can collect.
	* Intents: BuyPodium, SellCreature.
	All cash changes go through addCash / trySpend so the HUD is marked dirty and analytics are logged.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Gameplay = require(ReplicatedStorage.Shared.Config.Gameplay)
local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local GameData = require(ReplicatedStorage.Shared.GameData)
local Types = require(ReplicatedStorage.Shared.Types)
local EconomyMath = require(ReplicatedStorage.Shared.Logic.EconomyMath)
local Inventory = require(ReplicatedStorage.Shared.Logic.Inventory)
local Guard = require(ReplicatedStorage.Shared.Logic.Guard)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local Analytics = require(script.Parent.Analytics)
local LiveOpsService = require(script.Parent.LiveOpsService)
local PlotService = require(script.Parent.PlotService)
local Remotes = require(script.Parent.Remotes)
local Replication = require(script.Parent.Replication)
local Sessions = require(script.Parent.Sessions)

type Session = Sessions.Session

local PAD_CHECK_INTERVAL = 0.25
local SELL_RANGE = 16
local UPGRADE_RANGE = 14

local EconomyService = {}

function EconomyService.multiplier(session: Session): number
	local perks = Monetization.perks
	return EconomyMath.incomeMultiplier({
		rebirthMultiplier = session.data.rebirthMultiplier,
		hasDoubleCash = session.passes.DoubleCash,
		doubleCashMultiplier = perks.doubleCashMultiplier,
		isVip = session.passes.VIP,
		vipIncomeBonus = perks.vipIncomeBonus,
		eventCashMultiplier = LiveOpsService.cashMultiplier(),
	})
end

function EconomyService.capacity(session: Session): number
	return EconomyMath.podiumCapacity(
		Economy.startingPodiums,
		session.data.podiumUpgrades,
		if session.passes.ExtraPodiums then Monetization.perks.extraPodiums else 0,
		Gameplay.map.maxPodiums
	)
end

-- Recomputes cached income / multiplier / capacity and pushes them to the world and the HUD.
function EconomyService.refresh(session: Session)
	session.multiplier = EconomyService.multiplier(session)
	session.capacity = EconomyService.capacity(session)
	local incomes: { number } = {}
	for _, record in session.data.creatures do
		local def = GameData.catalog.creatures[record.id]
		if def then
			table.insert(incomes, def.income)
		end
	end
	session.incomePerSecond = EconomyMath.totalIncome(incomes, session.multiplier)
	local stats = session.data.stats
	stats.bestCashPerSecond = math.max(stats.bestCashPerSecond, session.incomePerSecond)
	if session.plot ~= 0 then
		PlotService.syncPodiums(session)
		PlotService.setNextPodiumCost(
			session.plot,
			EconomyMath.podiumUpgradeCost(session.data.podiumUpgrades, Economy.podiumUpgrade)
		)
	end
	Replication.markDirty(session)
end

function EconomyService.addCash(session: Session, amount: number, transactionType: string?, sku: string?)
	if amount ~= amount or amount <= 0 or amount == math.huge then
		return
	end
	session.data.cash += amount
	session.data.stats.totalEarned += amount
	if transactionType then
		Analytics.economySource(session, amount, transactionType, sku)
	end
	Replication.markDirty(session)
end

function EconomyService.trySpend(session: Session, amount: number, transactionType: string, sku: string?): boolean
	if amount ~= amount or amount < 0 or session.data.cash < amount then
		return false
	end
	session.data.cash -= amount
	Analytics.economySink(session, amount, transactionType, sku)
	Replication.markDirty(session)
	return true
end

function EconomyService.freePodium(session: Session): number?
	return Inventory.findFreePodium(session.data.creatures, session.capacity)
end

-- Places a new creature on the lowest free podium. Returns the record, or nil if the base is full.
function EconomyService.giveCreature(session: Session, creatureId: string): Types.CreatureRecord?
	local podium = EconomyService.freePodium(session)
	if podium == nil or GameData.catalog.creatures[creatureId] == nil then
		return nil
	end
	local record = Inventory.add(session.data, creatureId, podium, os.time())
	EconomyService.refresh(session)
	return record
end

-- Moves a podium's stored cash into the owner's wallet. Returns the amount collected.
function EconomyService.collect(session: Session, podium: number): number
	local record = Inventory.findByPodium(session.data.creatures, podium)
	if record == nil or record.stored < 1 then
		return 0
	end
	local amount = math.floor(record.stored)
	record.stored -= amount
	EconomyService.addCash(session, amount)
	Analytics.collect(session, amount)
	if session.plot ~= 0 then
		PlotService.setStored(session.plot, podium, record.stored)
	end
	if Analytics.milestone(session, "FirstCollect") then
		Analytics.custom(session, "first_collect_amount", amount)
	end
	return amount
end

local function incomeTick(dt: number)
	for _, session in Sessions.all() do
		if session.plot == 0 then
			continue
		end
		local multiplier = session.multiplier
		for _, record in session.data.creatures do
			if PlotService.isBusy(session.plot, record.podium) then
				continue -- being carried away: earns nothing in transit
			end
			local def = GameData.catalog.creatures[record.id]
			if def then
				record.stored += EconomyMath.creatureIncome(def.income, multiplier) * dt
				PlotService.setStored(session.plot, record.podium, record.stored)
			end
		end
		-- play time (used for the new-player grace period)
		local nowClock = os.clock()
		session.data.stats.playTime += nowClock - session.playClock
		session.playClock = nowClock
	end
end

local function padCheck()
	local range = Gameplay.collect.padRange
	for _, session in Sessions.all() do
		if session.plot == 0 or session.carry ~= nil then
			continue
		end
		local root = Sessions.rootPart(session)
		if root == nil or not PlotService.isInside(session.plot, root.Position) then
			continue
		end
		local refs = PlotService.refs(session.plot)
		for _, podium in refs.podiums do
			if podium.index > session.capacity then
				break
			end
			local offset = root.Position - podium.padPosition
			if Vector3.new(offset.X, 0, offset.Z).Magnitude <= range and math.abs(offset.Y) < 8 then
				local amount = EconomyService.collect(session, podium.index)
				if amount > 0 then
					Remotes.fire(session.player, "Effect", {
						kind = "collect",
						amount = amount,
						position = podium.padPosition,
					})
				end
				break
			end
		end
	end
end

local function onBuyPodium(player: Player)
	local session = Sessions.get(player)
	if session == nil or session.plot == 0 then
		return
	end
	local root = Sessions.rootPart(session)
	local refs = PlotService.refs(session.plot)
	if root == nil or (root.Position - refs.upgradePad.Position).Magnitude > UPGRADE_RANGE then
		Remotes.notify(player, Theme.text.tooFar, "error")
		return
	end
	local cost = EconomyMath.podiumUpgradeCost(session.data.podiumUpgrades, Economy.podiumUpgrade)
	if cost == nil or EconomyService.capacity(session) >= Gameplay.map.maxPodiums then
		Remotes.notify(player, Theme.text.podiumMaxSign, "error")
		return
	end
	if not EconomyService.trySpend(session, cost, "Shop", "Podium") then
		Remotes.notify(player, Theme.text.notEnoughCash, "error")
		return
	end
	session.data.podiumUpgrades += 1
	EconomyService.refresh(session)
	Remotes.notify(player, Theme.text.podiumAdded, "success")
	Remotes.fire(player, "Effect", { kind = "podium", position = refs.upgradePad.Position })
end

local function onSellCreature(player: Player, podiumArg: unknown)
	local podium = Guard.integer(podiumArg, 1, Gameplay.map.maxPodiums)
	local session = Sessions.get(player)
	if podium == nil or session == nil or session.plot == 0 then
		return
	end
	if PlotService.isBusy(session.plot, podium) then
		return
	end
	local record = Inventory.findByPodium(session.data.creatures, podium)
	local podiumRefs = PlotService.podium(session.plot, podium)
	local root = Sessions.rootPart(session)
	if record == nil or podiumRefs == nil or root == nil then
		return
	end
	if (root.Position - podiumRefs.base.Position).Magnitude > SELL_RANGE then
		Remotes.notify(player, Theme.text.tooFar, "error")
		return
	end
	local def = GameData.catalog.creatures[record.id]
	EconomyService.collect(session, podium)
	Inventory.removeByUid(session.data.creatures, record.uid)
	local value = EconomyMath.sellValue(def.price, Economy.sellRefund)
	EconomyService.addCash(session, value, "Gameplay", "Sell")
	EconomyService.refresh(session)
	Remotes.notify(
		player,
		Format.template(Theme.text.soldCreature, { creature = def.displayName, amount = UiTheme.cash(value) }),
		"success"
	)
end

function EconomyService.start()
	Remotes.onIntent("BuyPodium", onBuyPodium)
	Remotes.onIntent("SellCreature", onSellCreature)

	LiveOpsService.onCashMultiplierChanged(function()
		for _, session in Sessions.all() do
			EconomyService.refresh(session)
		end
	end)

	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(Gameplay.incomeTickSeconds)
			local now = os.clock()
			incomeTick(now - last)
			last = now
		end
	end)

	task.spawn(function()
		while true do
			task.wait(PAD_CHECK_INTERVAL)
			padCheck()
		end
	end)
end

return EconomyService
