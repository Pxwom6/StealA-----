--!strict
--[[
	Store rules shared by the server and the client (Config/Monetization).

	Unconfigured items: every pass and product starts with id 0 until Leo creates it on the Creator Hub and pastes its
	id into Config/Monetization. Outside Studio such an item is HIDDEN everywhere it would be sold (the Shop's cards and
	headers, the "Need $X more?" offer, the Spin tab's pack buttons), never shown as unavailable; in Studio it stays, so
	the "(Studio) Grant" button can test it through the real receipt path (DevGrantProduct).

	Checked before prompting: Lucky Spin packs and the Starter Pack can't always be bought, so their buy buttons ask the
	server first (the RequestPurchase intent, StoreService) and the client checks the same rule before asking, for an
	instant answer. The receipt path checks again (MonetizationService): a client can always prompt by itself.
	  Spins         paid random items: only where the player's Roblox policy allows them (PlayerPolicy), and not while
	                the spin bank already holds Config/Spin.paidBankFull spins or more (a receipt still banks every
	                spin it paid for, past any cap)
	  StarterPack   once per account, and only with a free podium for its Snackling

	Pure: no Roblox APIs (the caller passes RunService:IsStudio() and the player's state).
]]

local StoreRules = {}

-- Product kinds (Config/Monetization) whose purchase is checked on the server before Roblox's prompt opens.
StoreRules.CHECKED_KINDS = table.freeze({ Spins = true, StarterPack = true } :: { [string]: boolean })

-- Product kinds with a random effect: Roblox's Paid Random Items policy covers them (Logic/PaidRandomItems).
StoreRules.PAID_RANDOM_KINDS = table.freeze({ ServerLuck = true, Spins = true } :: { [string]: boolean })

-- Where a store item can be seen or bought, for analytics (a closed list, so breakdown fields stay bounded).
StoreRules.SURFACES = table.freeze({ "store", "spin", "offer" })

-- What a purchase check looks at (the server fills it from its own state, the client from its StateUpdate).
export type PurchaseContext = {
	visible: boolean, -- StoreRules.visible for the product's id
	paidRandomAllowed: boolean, -- PlayerPolicy (the client: the player attribute in Logic/PaidRandomItems)
	spins: number, -- spins banked now
	spinBankFull: number, -- Config/Spin.paidBankFull
	starterOwned: boolean, -- the Starter Pack was bought (Logic/StarterPackRules)
	podiumFree: boolean, -- the Starter Pack's Snackling may take a podium now
}

-- Why a product of `kind` can't be bought now, or nil when it can. Reasons, in this order: "unknown" (not a checked
-- kind) | "unavailable" (not created on the Creator Hub, outside Studio) | "restricted" (paid random items, not
-- allowed by the player's policy) | "bankFull" | "owned" | "baseFull".
function StoreRules.purchaseRefusal(kind: string, ctx: PurchaseContext): string?
	if not StoreRules.CHECKED_KINDS[kind] then
		return "unknown"
	elseif not ctx.visible then
		return "unavailable"
	elseif StoreRules.PAID_RANDOM_KINDS[kind] and not ctx.paidRandomAllowed then
		return "restricted"
	elseif kind == "Spins" and not (ctx.spins < ctx.spinBankFull) then
		return "bankFull"
	elseif kind == "StarterPack" and ctx.starterOwned then
		return "owned"
	elseif kind == "StarterPack" and not ctx.podiumFree then
		return "baseFull"
	end
	return nil
end

-- Config/Theme.text key telling the player why a purchase was refused (nil: say nothing, e.g. a made-up key).
function StoreRules.messageKey(reason: string): string?
	local map: { [string]: string } = {
		unavailable = "storeNotYet",
		restricted = "storeRandomRestricted",
		bankFull = "spinPackBankFull",
		owned = "starterOwned",
		baseFull = "starterBaseFull",
	}
	return map[reason]
end

-- Every refusal reason (checks over all of them).
StoreRules.REASONS = table.freeze({ "unknown", "unavailable", "restricted", "bankFull", "owned", "baseFull" })

-- Whether a store item with this Creator Hub id is shown: a configured id anywhere, an unconfigured one (0) only in
-- Studio.
function StoreRules.visible(id: number, isStudio: boolean): boolean
	return id ~= 0 or isStudio
end

-- The keys of `order` whose items are shown (StoreRules.visible), in order. `items` maps keys to anything with a
-- numeric `id` (Monetization.passes, Monetization.products); keys missing from it are left out.
function StoreRules.visibleKeys(order: { string }, items: { [string]: any }, isStudio: boolean): { string }
	local keys: { string } = {}
	for _, key in order do
		local item = items[key]
		local id = if type(item) == "table" then item.id else nil
		if type(id) == "number" and StoreRules.visible(id, isStudio) then
			table.insert(keys, key)
		end
	end
	return keys
end

return StoreRules
