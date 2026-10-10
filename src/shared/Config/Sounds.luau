--!strict
--[[
	Sound asset IDs. Plain data only.

	TODO(owner): paste your uploaded sound IDs ("rbxassetid://123456"). An empty string means "silent" — the game
	runs fine without any of these, it just has no audio feedback yet.
]]

local Sounds = {
	ui = {
		click = "",
		purchase = "",
		error = "",
		claim = "",
	},
	world = {
		buy = "",
		collect = "",
		sell = "",
		lock = "",
		unlock = "",
		stealStart = "",
		stealSuccess = "",
		tagged = "",
		alarm = "", -- plays for the owner while someone carries their Snackling
		rebirth = "",
		announce = "",
		luck = "",
		mutation = "", -- a mutated Snackling (Golden, Diamond...) appears on the belt
	},
	-- Played when a creature of this rarity appears on the belt near you / lands in your base.
	rarity = {
		Common = "",
		Uncommon = "",
		Rare = "",
		Epic = "",
		Legendary = "",
		Mythic = "",
		Secret = "",
	} :: { [string]: string },
	music = {
		lobby = "",
	},
}

return Sounds
