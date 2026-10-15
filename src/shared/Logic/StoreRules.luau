--!strict
--[[
	Store rules shared by the server and the client (Config/Monetization).

	Unconfigured items: every pass and product starts with id 0 until Leo creates it on the Creator Hub and pastes its
	id into Config/Monetization. Outside Studio such an item is HIDDEN everywhere it would be sold (the Shop's cards and
	headers, the "Need $X more?" offer), never shown as unavailable; in Studio it stays, so the "(Studio) Grant" button
	can test it through the real receipt path (DevGrantProduct).

	Pure: no Roblox APIs (the caller passes RunService:IsStudio()).
]]

local StoreRules = {}

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
