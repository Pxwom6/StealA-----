--!strict
--[[
	Gadgets: gear for stealing and defending, bought once with in-game cash (never Robux) in the Shop's Gadgets tab and
	kept forever (rebirths too; saved as the flags `gadget_<id>`). Each owned gadget gets a round button by the TAG
	button (keys 1, 2, 3, 4 in `order`), and the player uses it whenever they like; then it recharges. Plain data only.

	  Fizzy Soda    walk faster for a few seconds, carrying too (the carry slowdown still applies on top)
	  Banana Peel   drop a peel at your feet inside your own base: the first visitor to step on it slips, and drops
	                your Snackling if they were carrying one (it runs home, like a tag)
	  Bubble Shield nobody can tag you for a moment (it never stops a lock, a peel or anything else)
	  Snack Magnet  collect the cash waiting on all your pads, from anywhere

	The server decides everything (GadgetService, Logic/GadgetRules): ownership, cash, cooldowns (server time, per
	session), where a peel may go and who steps on it. Names and descriptions are Config/Theme.text keys; CI checks
	every number below against the limits in Logic/GadgetRules.validate. BALANCE.md "Gadgets" has the prices against
	the income curve.
]]

local Types = require("../Types")

local Gadgets: Types.GadgetsConfig = {
	order = { "soda", "peel", "shield", "magnet" },
	gadgets = {
		soda = {
			kind = "speed",
			icon = "🥤",
			color = "#FF7AB6",
			nameKey = "gadgetSodaName",
			descriptionKey = "gadgetSodaInfo",
			price = 1500,
			cooldownSeconds = 35,
			durationSeconds = 6,
			speedMultiplier = 1.3,
		},
		peel = {
			kind = "peel",
			icon = "🍌",
			color = "#FFD23F",
			nameKey = "gadgetPeelName",
			descriptionKey = "gadgetPeelInfo",
			price = 15000,
			cooldownSeconds = 45,
			durationSeconds = 90,
			slipSeconds = 1.5,
			triggerRadius = 2.5,
		},
		shield = {
			kind = "shield",
			icon = "🫧",
			color = "#5CC8FF",
			nameKey = "gadgetShieldName",
			descriptionKey = "gadgetShieldInfo",
			price = 150000,
			cooldownSeconds = 40,
			durationSeconds = 3,
		},
		magnet = {
			kind = "magnet",
			icon = "🧲",
			color = "#B07CFF",
			nameKey = "gadgetMagnetName",
			descriptionKey = "gadgetMagnetInfo",
			price = 2500000,
			cooldownSeconds = 60,
		},
	},
	-- Sugar Rush (x1.25) with a Fizzy Soda (x1.3) would be x1.625: it is capped here, and so are the movement checks.
	maxSpeedMultiplier = 1.5,
	speedGraceSeconds = 4, -- like a speed modifier's (ModifierService): a client keeps the old speed for a round trip
	peel = {
		checkSeconds = 0.1, -- like coin pickups (DropService)
		-- A standing root is about 3 studs above the floor and a jump lifts it about 7 more: jumping over a peel works.
		triggerHeight = 5.5,
	},
}

return Gadgets
