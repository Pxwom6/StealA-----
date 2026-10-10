--!strict
--[[
	First-time player tutorial. Plain data only. Rules: Logic/TutorialRules; server: TutorialService; UI:
	TutorialController; banner text: Theme.text.tutorial*.

	A brand-new player is walked through the loop one short line at a time, with a glowing beam and a bouncing arrow
	pointing at what to do next. Every step is finished by the server seeing the real action (a belt purchase, a
	collect, a lock, a steal), never by a client message. Players who already had progress when the tutorial shipped
	never see it. Completing it pays `reward` once per account; skipping it pays nothing.
]]

local Types = require("../Types")

local Tutorial: Types.TutorialConfig = {
	enabled = true,

	-- About an Uncommon Snackling: a nice "you did it" moment, small next to the first hour's income (BALANCE.md).
	reward = 500,

	-- In order. A step whose action the player already did earlier in the tutorial is skipped when it comes up.
	steps = {
		{ id = "buy" }, -- "Buy a Snackling from the belt!"
		{ id = "collect" }, -- "Step on the glowing pad to collect your cash!"
		-- "Lock your base to keep thieves out!" Moves on by itself if the lock can't be used (recharging) for 20 s in
		-- a row, or after a minute, so the banner never nags.
		{ id = "lock", unavailableSeconds = 20, timeoutSeconds = 60 },
		-- "Sneak into another base and steal a Snackling!" Ends happily ("You're ready!") after 90 s without a steal:
		-- an empty server or bases that are all shielded must not block the reward.
		{ id = "steal", timeoutSeconds = 90 },
	},

	belt = {
		minSecondsLeft = 4, -- the belt moves ~8.7 studs/s: an item with less time left is gone before you get there
		switchMargin = 12,
	},
}

return Tutorial
