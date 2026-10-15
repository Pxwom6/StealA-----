--!strict
--[[
	The Starter Pack (a developer product, Config/Monetization.starterPack): fixed contents, nothing random, once per
	account.

	  contents   cash sized from the buyer's steady income like a cash pack (at least a generous floor), one set
	             Snackling with one set mutation from the permanent roster, and unlocks for the first gadgets; a gadget
	             the buyer already owns pays its cash price instead, so the pack is never worth less to them
	  once       the save flag OWNED_FLAG, set in the same step as the grant. The server refuses a second purchase before
	             the prompt; a receipt that still arrives (a second prompt opened earlier) pays the whole pack's value
	             in cash (cashValue), so nothing paid for is lost
	  the offer  a gentle card, once per account (OFFER_FLAG once shown), after the first rebirth or the playtime in
	             `offer`, whichever comes first; never during the tutorial, over a dialog or while carrying, and not
	             once bought

	Gadgets can be bought with cash anyway (Config/Gadgets), so the pack speeds a player up and locks nobody out.
	Pure: no Roblox APIs; the caller passes prices and ownership.
]]

local EconomyMath = require("./EconomyMath")
local Types = require("../Types")

type StarterPackConfig = Types.StarterPackConfig

local StarterPackRules = {}

-- Save flags: bought (once per account), and the one-time offer card shown.
StarterPackRules.OWNED_FLAG = "starter_pack"
StarterPackRules.OFFER_FLAG = "starter_offer"

export type Contents = {
	cash: number, -- the income-sized cash
	creatureId: string,
	variant: string?,
	gadgets: { string }, -- gadgets it unlocks (not owned yet), in config order
	gadgetCash: number, -- the cash prices of the gadgets the buyer already owns, paid instead
}

function StarterPackRules.owns(flags: { [string]: boolean }): boolean
	return flags[StarterPackRules.OWNED_FLAG] == true
end

-- The income-sized cash part for a player with `packIncome` steady income (EconomyMath.packIncome).
function StarterPackRules.cash(config: StarterPackConfig, packIncome: number): number
	return EconomyMath.cashPackAmount(packIncome, config.cash)
end

-- What the pack gives a buyer: `cash` (StarterPackRules.cash, quoted when the receipt is first seen), the Snackling,
-- and each gadget the buyer doesn't own (`ownsGadget`) or else its cash price (`gadgetPrice`).
function StarterPackRules.contents(
	config: StarterPackConfig,
	cash: number,
	ownsGadget: (id: string) -> boolean,
	gadgetPrice: (id: string) -> number
): Contents
	local gadgets: { string } = {}
	local gadgetCash = 0
	for _, id in config.gadgets do
		if ownsGadget(id) then
			gadgetCash += math.max(0, gadgetPrice(id))
		else
			table.insert(gadgets, id)
		end
	end
	return {
		cash = math.max(0, cash),
		creatureId = config.creatureId,
		variant = config.variant,
		gadgets = gadgets,
		gadgetCash = gadgetCash,
	}
end

-- The whole pack's worth in cash (a second receipt pays this): its cash, the Snackling's belt price, and every gadget
-- in it at its price (unlocked or already paid as cash).
function StarterPackRules.cashValue(
	contents: Contents,
	creaturePrice: number,
	gadgetPrice: (id: string) -> number
): number
	local value = contents.cash + contents.gadgetCash + math.max(0, creaturePrice)
	for _, id in contents.gadgets do
		value += math.max(0, gadgetPrice(id))
	end
	return value
end

export type OfferContext = {
	owned: boolean, -- the pack was bought
	seen: boolean, -- the offer card was shown before (OFFER_FLAG)
	forSale: boolean, -- the pack exists on the Creator Hub (StoreRules.visible; Studio: always)
	inTutorial: boolean,
	rebirths: number,
	playSeconds: number, -- total play time (the save's stats.playTime)
}

-- The offer's context from a save, whether a tutorial runs and whether the pack is for sale.
function StarterPackRules.offerContext(data: Types.PlayerData, inTutorial: boolean, forSale: boolean): OfferContext
	return {
		owned = StarterPackRules.owns(data.flags),
		seen = data.flags[StarterPackRules.OFFER_FLAG] == true,
		forSale = forSale,
		inTutorial = inTutorial,
		rebirths = data.rebirths,
		playSeconds = data.stats.playTime,
	}
end

-- Whether the one-time offer card is due: for sale, not bought, not shown before, no tutorial running, and after the
-- first rebirth or the configured play time, whichever comes first.
function StarterPackRules.offerDue(ctx: OfferContext, config: StarterPackConfig): boolean
	if ctx.owned or ctx.seen or not ctx.forSale or ctx.inTutorial then
		return false
	end
	return ctx.rebirths >= config.offer.afterRebirths or ctx.playSeconds >= config.offer.afterPlaySeconds
end

export type MomentContext = {
	due: boolean, -- StarterPackRules.offerDue, from the server
	inTutorial: boolean,
	dialogOpen: boolean, -- any dialog (Modal.isAnyOpen)
	carrying: boolean, -- carrying a stolen Snackling home
	otherOffer: boolean, -- the "Need $X more?" strip is up (they share the strip's place)
	shownThisSession: boolean,
}

-- Whether the client may show the offer card right now: never during the tutorial, over a dialog, while carrying,
-- over another offer, or twice.
function StarterPackRules.canShowOffer(ctx: MomentContext): boolean
	return ctx.due
		and not ctx.inTutorial
		and not ctx.dialogOpen
		and not ctx.carrying
		and not ctx.otherOffer
		and not ctx.shownThisSession
end

-- Problems with Config/Monetization.starterPack (an empty list means valid). `creatures` / `mutations`: the catalogue
-- by id; `gadgetOrder`: Config/Gadgets.order.
function StarterPackRules.validate(
	config: StarterPackConfig,
	creatures: { [string]: Types.CreatureDef },
	mutations: { [string]: Types.MutationDef },
	gadgetOrder: { string }
): { string }
	local problems: { string } = {}
	local cash = config.cash
	if not (cash.incomeSeconds >= 60 and cash.incomeSeconds <= 4 * 3600) then
		table.insert(problems, "cash.incomeSeconds must be between a minute and 4 hours")
	end
	if not (cash.minimum >= 1000 and cash.minimum <= 1e7 and cash.minimum % 1 == 0) then
		table.insert(problems, "cash.minimum must be a whole amount from $1,000 to $10M")
	end
	local creature = creatures[config.creatureId]
	if creature == nil then
		table.insert(problems, `creatureId {config.creatureId} is not a Snackling`)
	elseif creature.eventId ~= nil then
		table.insert(problems, `{config.creatureId} is an event Snackling: pick one from the permanent roster`)
	end
	local variant = config.variant
	if variant ~= nil then
		local mutation = mutations[variant]
		if mutation == nil then
			table.insert(problems, `variant {variant} is not a mutation`)
		elseif mutation.eventId ~= nil or mutation.mapTheme ~= nil or mutation.modifierId ~= nil then
			table.insert(problems, `{variant} only rolls at certain times: pick a permanent mutation`)
		end
	end
	local seen: { [string]: boolean } = {}
	for _, id in config.gadgets do
		if table.find(gadgetOrder, id) == nil then
			table.insert(problems, `gadget {id} is not in Config/Gadgets`)
		elseif seen[id] then
			table.insert(problems, `gadget {id} is listed twice`)
		end
		seen[id] = true
	end
	local offer = config.offer
	if not (offer.afterRebirths >= 1 and offer.afterRebirths % 1 == 0) then
		table.insert(problems, "offer.afterRebirths must be a whole number from 1")
	end
	if not (offer.afterPlaySeconds >= 600 and offer.afterPlaySeconds <= 24 * 3600) then
		table.insert(problems, "offer.afterPlaySeconds must be between 10 minutes and a day")
	end
	if not (offer.showSeconds >= 5 and offer.showSeconds <= 30) then
		table.insert(problems, "offer.showSeconds must be between 5 and 30")
	end
	return problems
end

return StarterPackRules
