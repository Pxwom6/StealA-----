--!strict
--[[
	Roblox's Paid Random Items policy: a paid item with a random effect may only be offered to a player whose
	PolicyService policy allows it (ArePaidRandomItemsRestricted is false). Server Luck (a paid boost to luck) is one;
	paid Lucky Spin packs would be another.

	The server looks the policy up when a player joins (Services/PlayerPolicy, in a pcall: a failed lookup counts as
	restricted) and publishes the answer as the player attribute ATTRIBUTE. The store reads that attribute and shows
	such an item as blocked unless it is true (so also while the lookup is still running), and the receipt handler
	refuses to grant one to a player who isn't allowed.

	Pure: no Roblox APIs.
]]

local PaidRandomItems = {}

-- Player attribute: true once the lookup said paid random items are allowed; false when restricted or the lookup
-- failed; nil while it runs.
PaidRandomItems.ATTRIBUTE = "PaidRandomItemsAllowed"

-- What a GetPolicyInfoForPlayerAsync call returned (`ok` = it didn't throw, `info` = its result) means for paid
-- random items. Anything but a clear "not restricted" counts as restricted.
function PaidRandomItems.allowedByPolicy(ok: boolean, info: unknown): boolean
	if not ok or type(info) ~= "table" then
		return false
	end
	return (info :: { [string]: unknown }).ArePaidRandomItemsRestricted == false
end

-- Whether the published attribute value lets the store offer a paid random item (only an explicit true does).
function PaidRandomItems.allowedByAttribute(value: unknown): boolean
	return value == true
end

return PaidRandomItems
