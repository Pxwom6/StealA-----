--!strict
--[[
	What's New: the update notes. A returning player sees the newest one once, as a card when they join (never in their
	first session or during the tutorial, never over another dialog or while carrying; the flag news_<number>), and the
	board on the spawn plaza always shows it. Plain data only (Logic/UpdateRules checks it).

	Before each publish: add a new entry at the TOP with the next number, today's date and 3 to 5 short lines, each
	starting with an emoji (at most 64 characters: CI checks they fit the card). Only the newest entry is shown;
	keep the old ones below it as a history. Never reuse a number: players who saw it would not see the new one.
]]

local Types = require("../Types")

local Updates: Types.UpdatesConfig = {
	list = {
		{
			number = 1,
			date = "2026-10-15",
			title = "The Big Snack Update!",
			highlights = {
				"🗺️ 27 maps! Vote for the next one every 20 minutes",
				"⛈️ 20 server twists: storms, coin rain, runaways, Snack Attack",
				"✨ New mutations, gadgets, free gifts and the Lucky Spin",
				"🏆 50+ trophies, plus titles and base skins to earn",
				"🎉 Admin drops, and Valentine's and Easter events on the way!",
			},
		},
	},
}

return Updates
