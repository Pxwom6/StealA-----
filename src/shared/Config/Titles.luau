--!strict
--[[
	Titles: a short line under a player's name over their head, and a tag beside their name in chat. Earned, never
	bought: each comes from an achievement (Config/Achievements), a number of rebirths or of Snackdex tiers completed
	(Logic/StyleRules). A player wears one, or none, picked in Settings ▸ Style ▸ Titles; locked ones say how to earn
	them. Plain data only.

	id       the equipped one is saved as the flag title_<id>: never rename or remove one that has shipped (CI keeps a
	         released list); a removed id only means its wearers wear nothing
	text     at most 16 characters, so it fits a nametag on a phone (CI measures it)
	icon     one emoji before the text
	color    #RRGGBB, light enough to read over the dark outline on every map (CI checks)
	unlock   { kind = "achievement", id = <achievement id> }, { kind = "rebirths", count = n } or
	         { kind = "tiers", count = n } (Snackdex tiers completed)

	The list is the Titles tab's order: easiest first.
]]

local Types = require("../Types")

local function achievement(id: string): Types.StyleUnlock
	return { kind = "achievement", id = id }
end

local Titles: Types.TitlesConfig = {
	list = {
		{
			id = "stickyFingers",
			text = "Sticky Fingers",
			icon = "🫳",
			color = "#9FE3FF",
			unlock = achievement("stickyFingers"),
		},
		{
			id = "snackShopper",
			text = "Snack Shopper",
			icon = "🛒",
			color = "#8CFF6B",
			unlock = achievement("snackShopper"),
		},
		{ id = "collector", text = "Collector", icon = "📖", color = "#C9B8FF", unlock = achievement("collector") },
		{ id = "insider", text = "Insider", icon = "🔑", color = "#FFE08A", unlock = achievement("insider") },
		{
			id = "masterThief",
			text = "Master Thief",
			icon = "🦹",
			color = "#FF7A7A",
			unlock = achievement("masterThief"),
		},
		{
			id = "millionaire",
			text = "Millionaire",
			icon = "💰",
			color = "#7CFF4D",
			unlock = achievement("millionaire"),
		},
		{
			id = "bornAgain",
			text = "Born Again",
			icon = "♻️",
			color = "#5CE6C4",
			unlock = { kind = "rebirths", count = 1 },
		},
		{
			id = "giantSlayer",
			text = "Giant Slayer",
			icon = "⚔️",
			color = "#FFA24D",
			unlock = achievement("giantSlayer"),
		},
		{
			id = "mutationHunter",
			text = "Mutation Hunter",
			icon = "🧪",
			color = "#D49CFF",
			unlock = achievement("mutationHunter"),
		},
		{ id = "explorer", text = "Explorer", icon = "🧭", color = "#5CD6FF", unlock = achievement("explorer") },
		{
			id = "snackScholar",
			text = "Snack Scholar",
			icon = "🎓",
			color = "#B8A6FF",
			unlock = { kind = "tiers", count = 3 },
		},
		{
			id = "legendaryBandit",
			text = "Legendary Bandit",
			icon = "👑",
			color = "#FFB21E",
			unlock = achievement("legendaryBandit"),
		},
		{
			id = "fiveLives",
			text = "Five Lives",
			icon = "🔁",
			color = "#3DDC84",
			unlock = { kind = "rebirths", count = 5 },
		},
		{
			id = "globetrotter",
			text = "Globetrotter",
			icon = "🌍",
			color = "#2EC4B6",
			unlock = achievement("globetrotter"),
		},
		{
			id = "completionist",
			text = "Completionist",
			icon = "💯",
			color = "#FF6F9A",
			unlock = achievement("completionist"),
		},
		{
			id = "secretKeeper",
			text = "Secret Keeper",
			icon = "🤫",
			color = "#1DFFE0",
			unlock = achievement("secretKeeper"),
		},
		{
			id = "billionaire",
			text = "Billionaire",
			icon = "🏦",
			color = "#FFD700",
			unlock = achievement("billionaire"),
		},
		{ id = "mvp", text = "MVP", icon = "🏆", color = "#FFE066", unlock = achievement("mvp") },
		{
			id = "snackdexMaster",
			text = "Snackdex Master",
			icon = "📚",
			color = "#B79CFF",
			unlock = { kind = "tiers", count = 7 },
		},
		{
			id = "phantomThief",
			text = "Phantom Thief",
			icon = "🥷",
			color = "#E3E0FF",
			unlock = achievement("phantomThief"),
		},
		{
			id = "sevenLives",
			text = "Seven Lives",
			icon = "🌀",
			color = "#FF5CD1",
			unlock = { kind = "rebirths", count = 7 },
		},
		{ id = "veteran", text = "Veteran", icon = "🎖️", color = "#FFB08A", unlock = achievement("veteran") },
	},

	-- One BillboardGui per character, on its Head, built by the server when the choice changes (server/Services/
	-- Nametags). Pixel-sized like Roblox's own names, hidden beyond maxDistance, hidden while carrying a Snackling (it
	-- would cover the loot on their head; the THIEF! marker shows instead) and from the wearer themself (Roblox hides
	-- your own name too: nothing over your character in the middle of your screen).
	nametag = {
		width = 220,
		height = 26,
		maxTextSize = 20,
		offset = 0.9,
		maxDistance = 70,
	},

	chatTag = true,
}

return Titles
