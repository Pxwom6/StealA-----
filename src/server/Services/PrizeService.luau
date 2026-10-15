--!strict
--[[
	Prizes from gifts, the Lucky Spin and supply crates (Types.PrizeReward), paid the same way everywhere:

	  cash      sized from the player's steady income like a cash pack (EconomyMath.cashPackAmount)
	  spin      banked for the Lucky Spin (SpinRules.bank); spins beyond Config/Spin.maxBanked are paid as cash
	  creature  a Snackling rolled at `luck` x the server's luck, a bought Server Luck boost left out (its store card
	            only shows belt odds); mutation rolled as usual, or always `mutation`; on the lowest free podium. With a
	            full base it is sold for its usual refund instead, and so it is when the player is carrying a stolen
	            Snackling home with one free podium left (that podium is for the delivery)

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
local SpinRules = require(ReplicatedStorage.Shared.Logic.SpinRules)
local BeltService = require(script.Parent.BeltService)
local EconomyService = require(script.Parent.EconomyService)
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

-- Puts `def` (with `variant`) on a free podium, or pays its sell value when the base is full. A thief carrying a
-- Snackling home keeps their last free podium for it: the prize is sold instead (Inventory.prizeMayTakePodium).
-- Returns whether it was given and the cash paid instead (0 when given).
function PrizeService.giveOrSell(
	session: Session,
	def: Types.CreatureDef,
	variant: string?,
	sku: string
): (boolean, number)
	local mayTake = Inventory.prizeMayTakePodium(session.data.creatures, session.capacity, session.carry ~= nil)
	if mayTake and EconomyService.giveCreature(session, def.id, variant) then
		return true, 0
	end
	local value = EconomyMath.sellValue(GameData.price(def, variant), Economy.sellRefund)
	EconomyService.addCash(session, value, "Gameplay", sku)
	return false, value
end

-- Pays `reward` to `session`. `sku` names the source for analytics ("Gift", "Spin"...).
function PrizeService.pay(session: Session, reward: Types.PrizeReward, sku: string): Result
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
		local def, variant = PrizeService.rollCreature(reward.luck, 1, reward.mutation)
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
