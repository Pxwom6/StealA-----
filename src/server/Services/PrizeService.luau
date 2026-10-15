--!strict
--[[
	Prizes from gifts, the Lucky Spin and supply crates (Types.PrizeReward), paid the same way everywhere:

	  cash      sized from the player's steady income like a cash pack (EconomyMath.cashPackAmount)
	  spin      banked for the Lucky Spin (SpinRules.bank); spins beyond the bank's size (Config/Spin.maxBanked, bought
	            spins in it or not) are paid as cash
	  creature  a Snackling rolled at `luck` x the server's luck, a bought Server Luck boost left out (its store card
	            only shows belt odds); mutation rolled as usual, or always `mutation`; on the lowest free podium. With a
	            full base it is sold for its usual refund instead, and so it is when the player is carrying a stolen
	            Snackling home with one free podium left (that podium is for the delivery). The Lucky Spin pays with
	            fixed odds instead (`fixedOdds`, rollFixed): a permanent Snackling at exactly `luck`, plain or always
	            `mutation`, nothing live involved, so a spin pays exactly the odds its Details list shows
	            (Logic/SpinOdds; paid Lucky Spin packs are paid random items)

	`pay` returns what happened, with a line for the toast; the caller decides when to show it (the Lucky Spin shows it
	after its reel stops).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Spin = require(ReplicatedStorage.Shared.Config.Spin)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local GameData = require(ReplicatedStorage.Shared.GameData)
local Types = require(ReplicatedStorage.Shared.Types)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local EconomyMath = require(ReplicatedStorage.Shared.Logic.EconomyMath)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local Inventory = require(ReplicatedStorage.Shared.Logic.Inventory)
local MutationRules = require(ReplicatedStorage.Shared.Logic.MutationRules)
local RarityRoll = require(ReplicatedStorage.Shared.Logic.RarityRoll)
local SpinOdds = require(ReplicatedStorage.Shared.Logic.SpinOdds)
local SpinRules = require(ReplicatedStorage.Shared.Logic.SpinRules)
local BeltService = require(script.Parent.BeltService)
local EconomyService = require(script.Parent.EconomyService)
local GameEvents = require(script.Parent.GameEvents)
local LiveOpsService = require(script.Parent.LiveOpsService)
local ModifierService = require(script.Parent.ModifierService)
local Replication = require(script.Parent.Replication)
local Sessions = require(script.Parent.Sessions)

type Session = Sessions.Session

export type Result = {
	text: string, -- for the toast
	cash: number, -- cash paid (including a full base's refund)
	spins: number, -- spins banked
	creatureId: string?, -- the Snackling won (given or sold)
	variant: string?,
	rarity: string?,
	given: boolean, -- the Snackling went to the base (false: sold, or no Snackling)
}

local PrizeService = {}

local random = Random.new()

local function nextRandom(): number
	return random:NextNumber()
end

-- Rolls a Snackling at `luck` x the server's luck (without a bought Server Luck boost, see
-- LiveOpsService.prizeLuckMultiplier), its mutation as the belt would (times `mutationChance`) unless `forcedVariant`
-- is given. nil only when nothing can roll.
function PrizeService.rollCreature(
	luck: number,
	mutationChance: number,
	forcedVariant: string?
): (Types.CreatureDef?, string?)
	local catalog = GameData.catalog
	local creatureId = RarityRoll.roll(
		catalog.rarityList,
		catalog.creatureList,
		LiveOpsService.prizeLuckMultiplier() * luck,
		LiveOpsService.activeEventIds(),
		nextRandom
	)
	local def = if creatureId then catalog.creatures[creatureId] else nil
	if def == nil then
		return nil, nil
	end
	if forcedVariant ~= nil and catalog.mutations[forcedVariant] ~= nil then
		return def, forcedVariant
	end
	local variant = MutationRules.roll(
		catalog.mutationList,
		BeltService.mutationConditions(),
		nextRandom,
		ModifierService.effects().mutationChance * mutationChance
	)
	return def, variant
end

-- A Lucky Spin's Snackling, with odds that never change (Logic/SpinOdds): a permanent Snackling rolled at exactly
-- `luck` (no server, event, admin or modifier luck), and exactly `variant` (nil: plain, no mutation roll). The odds the
-- Spin tab and the pack cards list are these very weights (RarityRoll.creatureOdds on the same arguments). nil only
-- when nothing can roll.
function PrizeService.rollFixed(luck: number, variant: string?): (Types.CreatureDef?, string?)
	local catalog = GameData.catalog
	local creatureId = RarityRoll.roll(catalog.rarityList, catalog.creatureList, luck, SpinOdds.NO_EVENTS, nextRandom)
	local def = if creatureId then catalog.creatures[creatureId] else nil
	if def == nil then
		return nil, nil
	end
	return def, if variant ~= nil and catalog.mutations[variant] ~= nil then variant else nil
end

-- Puts `def` (with `variant`) on a free podium, or pays its sell value when the base is full. A thief carrying a
-- Snackling home keeps their last free podium for it: the prize is sold instead (Inventory.prizeMayTakePodium).
-- Returns whether it was given and the cash paid instead (0 when given). Either way it was found (GameEvents "found",
-- source `sku`).
function PrizeService.giveOrSell(
	session: Session,
	def: Types.CreatureDef,
	variant: string?,
	sku: string
): (boolean, number)
	local mayTake = Inventory.prizeMayTakePodium(session.data.creatures, session.capacity, session.carry ~= nil)
	local given = mayTake and EconomyService.giveCreature(session, def.id, variant) ~= nil
	local value = 0
	if not given then
		value = EconomyMath.sellValue(GameData.price(def, variant), Economy.sellRefund)
		EconomyService.addCash(session, value, "Gameplay", sku)
	end
	GameEvents.emit(session, { kind = "found", creatureId = def.id, variant = variant, source = sku }) -- shout-outs
	return given, value
end

-- Pays `reward` to `session`. `sku` names the source for analytics ("Gift", "Spin"...). `fixedOdds`: a Snackling is
-- rolled with PrizeService.rollFixed (the Lucky Spin), not at the server's luck with a mutation roll.
function PrizeService.pay(session: Session, reward: Types.PrizeReward, sku: string, fixedOdds: boolean?): Result
	local result: Result = { text = "", cash = 0, spins = 0, given = false }
	if reward.kind == "cash" then
		local amount = EconomyMath.cashPackAmount(
			session.packIncome,
			{ incomeSeconds = reward.incomeSeconds, minimum = reward.minimum }
		)
		EconomyService.addCash(session, amount, "Gameplay", sku)
		result.cash = amount
		result.text = Format.template(Theme.text.prizeCash, { amount = UiTheme.cash(amount) })
	elseif reward.kind == "spin" then
		local overflow = SpinRules.bank(session.data.spin, reward.count, Spin)
		result.spins = reward.count - overflow
		result.text = Format.template(
			if reward.count == 1 then Theme.text.prizeSpin else Theme.text.prizeSpins,
			{ count = reward.count }
		)
		if overflow > 0 then
			local amount = overflow
				* EconomyMath.cashPackAmount(
					session.packIncome,
					{ incomeSeconds = Spin.bankedOverflow.incomeSeconds, minimum = Spin.bankedOverflow.minimum }
				)
			EconomyService.addCash(session, amount, "Gameplay", sku)
			result.cash = amount
			result.text = Format.template(Theme.text.prizeSpinsFull, { amount = UiTheme.cash(amount) })
		end
		Replication.markDirty(session)
	else
		local def, variant
		if fixedOdds then
			def, variant = PrizeService.rollFixed(reward.luck, reward.mutation)
		else
			def, variant = PrizeService.rollCreature(reward.luck, 1, reward.mutation)
		end
		if def then
			local name = GameData.displayName(def, variant)
			local given, value = PrizeService.giveOrSell(session, def, variant, sku)
			result.creatureId = def.id
			result.variant = variant
			result.rarity = def.rarity
			result.given = given
			result.cash = value
			local rarity = GameData.catalog.rarities[def.rarity]
			result.text = if given
				then Format.template(Theme.text.prizeCreature, { rarity = rarity.displayName, creature = name })
				else Format.template(
					Theme.text.prizeCreatureSold,
					{ creature = name, amount = UiTheme.cash(value) }
				)
		end
	end
	return result
end

return PrizeService
