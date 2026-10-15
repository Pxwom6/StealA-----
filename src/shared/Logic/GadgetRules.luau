--!strict
--[[
	Gadget rules (Config/Gadgets): who owns which gadget (the save's `gadget_<id>` flags), whether one can be bought or
	used right now, what using one does to the player's gadget state (cooldowns, effects), the walking speed a speed
	gadget gives and the movement checks allow (capped together with a speed modifier), where a banana peel may go and
	who steps on it, what the client is told, and validation. Pure: no Roblox APIs; times come in as server time.
]]

local StealRules = require("./StealRules")
local Types = require("../Types")

type GadgetsConfig = Types.GadgetsConfig
type GadgetDef = Types.GadgetDef

-- A player's gadgets this session (Sessions.Session.gadgets). Never saved: cooldowns start over in a new server.
export type State = {
	readyAt: { [string]: number }, -- gadget id -> when it can be used again
	activeUntil: { [string]: number }, -- gadget id -> when its effect ends (a peel: when the peel goes)
	speedUntil: number, -- a speed gadget runs until then (0: never)
	speedMultiplier: number, -- at this multiplier
	-- A speed the movement checks still allow after a newer speed gadget replaced it (like ModifierService's grace).
	previousSpeed: number,
	previousSpeedUntil: number,
	shieldUntil: number, -- nobody can tag this player until then
	shieldId: string?, -- the gadget shielding them (analytics)
	frozenUntil: number, -- slipped on a banana peel: can't move until then
}

export type BuyContext = {
	exists: boolean, -- a gadget with that id is configured
	owned: boolean,
	cash: number,
	price: number, -- the server's price (Config/Gadgets), never the client's
	covered: boolean?, -- the player's Auto Collect pass already does what it does (GadgetRules.coveredByAutoCollect)
}

export type UseContext = {
	owned: boolean,
	inTutorial: boolean, -- the first-time tutorial is running (gadget buttons are hidden then)
	alive: boolean, -- the character exists and isn't dead
	now: number,
	readyAt: number?, -- State.readyAt[id]
	covered: boolean?, -- the player's Auto Collect pass already does what it does
}

-- Where the player wants to drop a peel: at their own feet (the server's view of their root).
export type PeelPlaceContext = {
	x: number,
	z: number,
	rect: StealRules.Rect?, -- the player's own plot, the bounds the steal code uses (nil: no plot)
	heightAboveFloor: number, -- the root above that plot's floor
	wallHeight: number,
	trusted: boolean, -- the root fits what the server observed (PositionTracker), not a teleport
}

local GadgetRules = {}

GadgetRules.FLAG_PREFIX = "gadget_"

GadgetRules.KINDS = table.freeze({ speed = true, peel = true, shield = true, magnet = true } :: { [string]: boolean })

-- The save flag that records owning gadget `id`.
function GadgetRules.flag(id: string): string
	return GadgetRules.FLAG_PREFIX .. id
end

function GadgetRules.owns(flags: { [string]: boolean }, id: string): boolean
	return flags[GadgetRules.flag(id)] == true
end

-- The gadgets the player owns, in config order (ids the config no longer has are left out, their flags stay).
function GadgetRules.owned(flags: { [string]: boolean }, config: GadgetsConfig): { string }
	local list: { string } = {}
	for _, id in config.order do
		if config.gadgets[id] and GadgetRules.owns(flags, id) then
			table.insert(list, id)
		end
	end
	return list
end

-- Gadget `id`'s place in config order: its button slot and its key (1, 2, 3...). nil for an unknown id.
function GadgetRules.slot(config: GadgetsConfig, id: string): number?
	return table.find(config.order, id)
end

function GadgetRules.newState(): State
	return {
		readyAt = {},
		activeUntil = {},
		speedUntil = 0,
		speedMultiplier = 1,
		previousSpeed = 1,
		previousSpeedUntil = 0,
		shieldUntil = 0,
		shieldId = nil,
		frozenUntil = 0,
	}
end

-- The Auto Collect pass collects every pad every few seconds, which is all the Snack Magnet does. For its owners the
-- magnet's button shows "AUTO" and stays harmless: it is never used (its cooldown never starts) and never sold to them
-- for cash it would waste; both say why. Every other gadget is untouched.
function GadgetRules.coveredByAutoCollect(def: GadgetDef, hasAutoCollect: boolean): boolean
	return hasAutoCollect and def.kind == "magnet"
end

-- Whether a gadget can be bought. Reasons: "unknown" | "owned" | "auto" | "cash".
function GadgetRules.canBuy(ctx: BuyContext): (boolean, string?)
	if not ctx.exists then
		return false, "unknown"
	elseif ctx.owned then
		return false, "owned"
	elseif ctx.covered then
		return false, "auto"
	elseif not (ctx.price >= 0 and ctx.cash >= ctx.price) then
		return false, "cash"
	end
	return true, nil
end

-- Whether a gadget can be used now (the kind's own checks come after: GadgetRules.canPlacePeel...).
-- Reasons, in this order: "notOwned" | "auto" | "tutorial" | "dead" | "cooldown".
function GadgetRules.canUse(ctx: UseContext): (boolean, string?)
	if not ctx.owned then
		return false, "notOwned"
	elseif ctx.covered then
		return false, "auto"
	elseif ctx.inTutorial then
		return false, "tutorial"
	elseif not ctx.alive then
		return false, "dead"
	elseif ctx.readyAt ~= nil and not (ctx.now >= ctx.readyAt) then
		return false, "cooldown"
	end
	return true, nil
end

-- Seconds until gadget `id` can be used again (0 when ready).
function GadgetRules.remaining(state: State, id: string, t: number): number
	local readyAt = state.readyAt[id]
	return if readyAt then math.max(0, readyAt - t) else 0
end

-- The speed gadget's multiplier at time `t` (1 when none runs).
function GadgetRules.speedMultiplier(state: State, t: number): number
	return if t < state.speedUntil then state.speedMultiplier else 1
end

-- What the movement checks allow for speed gadgets at `t`: the running one's multiplier, kept for `grace` seconds after
-- it ends (the client may still run at it for a round trip), and one it replaced while that still counted.
function GadgetRules.speedAllowance(state: State, t: number, grace: number): number
	local allowance = 1
	if t < state.speedUntil + grace then
		allowance = state.speedMultiplier
	end
	if t < state.previousSpeedUntil then
		allowance = math.max(allowance, state.previousSpeed)
	end
	return allowance
end

-- A speed modifier's walking multiplier times a speed gadget's, never above `cap`. The humanoid gets this; the
-- movement checks get the same with each side's allowance (never less than the speed itself), so nobody is flagged for
-- a speed the server gave them, and nothing ever walks (or is allowed) past the cap.
function GadgetRules.combinedSpeed(modifier: number, gadget: number, cap: number): number
	return math.min(cap, modifier * gadget)
end

function GadgetRules.isShielded(state: State, t: number): boolean
	return t < state.shieldUntil
end

function GadgetRules.isFrozen(state: State, t: number): boolean
	return t < state.frozenUntil
end

-- Slipped on a peel at `t`: can't move for `seconds` (a second slip meanwhile can only make it longer).
function GadgetRules.freeze(state: State, t: number, seconds: number)
	state.frozenUntil = math.max(state.frozenUntil, t + math.max(0, seconds))
end

-- Uses gadget `id` (its `def`) at `t`: the cooldown starts, and a speed or shield effect runs (a peel's life is
-- recorded too; GadgetService puts the peel down). Call only after canUse and the kind's own checks said yes.
function GadgetRules.use(state: State, id: string, def: GadgetDef, t: number, config: GadgetsConfig)
	state.readyAt[id] = t + def.cooldownSeconds
	local duration = def.durationSeconds or 0
	if def.kind == "speed" then
		-- A speed that still counts (running, or in its grace) stays allowed as long as it would have been.
		local carried, carriedUntil = 1, 0
		local grace = config.speedGraceSeconds
		if t < state.speedUntil + grace then
			carried, carriedUntil = state.speedMultiplier, state.speedUntil + grace
		end
		if t < state.previousSpeedUntil then
			carried = math.max(carried, state.previousSpeed)
			carriedUntil = math.max(carriedUntil, state.previousSpeedUntil)
		end
		state.previousSpeed, state.previousSpeedUntil = carried, carriedUntil
		state.speedUntil = t + duration
		state.speedMultiplier = def.speedMultiplier or 1
		state.activeUntil[id] = state.speedUntil
	elseif def.kind == "shield" then
		state.shieldUntil = math.max(state.shieldUntil, t + duration)
		state.shieldId = id
		state.activeUntil[id] = state.shieldUntil
	elseif def.kind == "peel" then
		state.activeUntil[id] = t + duration
	end
end

-- Whether a peel can go down at the player's feet. Reasons: "outside" (not inside their own base) | "height" (not on
-- its floor, e.g. on top of a wall) | "untrusted" (the position doesn't fit what the server saw).
function GadgetRules.canPlacePeel(ctx: PeelPlaceContext): (boolean, string?)
	local rect = ctx.rect
	if rect == nil or not StealRules.isInsideRect(ctx.x, ctx.z, rect) then
		return false, "outside"
	elseif not StealRules.isAtFloorLevel(ctx.heightAboveFloor, ctx.wallHeight) then
		return false, "height"
	elseif not ctx.trusted then
		return false, "untrusted"
	end
	return true, nil
end

-- True when a root (dx, dz) from a peel's middle, `heightAboveFloor` above the floor it lies on, is stepping on it:
-- within `radius` horizontally and low enough to be walking (jumping over it is fine). False for NaN.
function GadgetRules.stepsOnPeel(
	dx: number,
	dz: number,
	heightAboveFloor: number,
	radius: number,
	triggerHeight: number
): boolean
	return dx * dx + dz * dz <= radius * radius and heightAboveFloor >= -2 and heightAboveFloor <= triggerHeight
end

-- Config/Theme.text key telling the player why a buy or a use was refused (nil: say nothing).
function GadgetRules.messageKey(reason: string): string?
	local map: { [string]: string } = {
		owned = "gadgetAlreadyOwned",
		cash = "notEnoughCash",
		notOwned = "gadgetNotOwned",
		tutorial = "gadgetTutorial",
		cooldown = "gadgetRecharging",
		outside = "peelOutsideBase",
		height = "peelOnFloor",
		untrusted = "stealConnectionHiccup",
		empty = "magnetEmpty",
		auto = "magnetAuto",
	}
	return map[reason]
end

-- Every refusal reason (checks over all of them).
GadgetRules.REASONS = table.freeze({
	"unknown",
	"owned",
	"auto",
	"cash",
	"notOwned",
	"tutorial",
	"dead",
	"cooldown",
	"outside",
	"height",
	"untrusted",
	"empty",
})

-- What fills a gadget's description template: {percent} faster, lasts {seconds}, slip {slip}, recharges {cooldown}.
function GadgetRules.describe(def: GadgetDef): { [string]: any }
	return {
		percent = math.floor(((def.speedMultiplier or 1) - 1) * 100 + 0.5),
		seconds = def.durationSeconds or 0,
		slip = def.slipSeconds or 0,
		cooldown = def.cooldownSeconds,
	}
end

-- What the owning client is told (StateUpdate `gadgets`).
function GadgetRules.view(flags: { [string]: boolean }, state: State, config: GadgetsConfig): Types.GadgetsView
	local owned = GadgetRules.owned(flags, config)
	local readyAt: { [string]: number } = {}
	local activeUntil: { [string]: number } = {}
	for _, id in owned do
		readyAt[id] = state.readyAt[id]
		activeUntil[id] = state.activeUntil[id]
	end
	return { owned = owned, readyAt = readyAt, activeUntil = activeUntil }
end

-- The fastest anyone can walk with `maxModifierSpeed` (the strongest speed modifier) and every speed gadget.
function GadgetRules.fastestSpeed(config: GadgetsConfig, maxModifierSpeed: number): number
	local best = 1
	for _, def in config.gadgets do
		if def.kind == "speed" then
			best = math.max(best, def.speedMultiplier or 1)
		end
	end
	return GadgetRules.combinedSpeed(maxModifierSpeed, best, config.maxSpeedMultiplier)
end

local HEX_PATTERN = "^#%x%x%x%x%x%x$"

-- Problems with Config/Gadgets (an empty list means valid). `text`: Config/Theme.text (names and descriptions must be
-- there, with every placeholder filled). `maxModifierSpeed`: the fastest walking speed a modifier can set
-- (ModifierRules.maxWalkSpeed); the cap must never slow a modifier down on its own.
function GadgetRules.validate(config: GadgetsConfig, text: { [string]: string }, maxModifierSpeed: number): { string }
	local problems: { string } = {}
	local function problem(message: string)
		table.insert(problems, message)
	end
	local function range(value: number?, low: number, high: number, what: string)
		if value == nil or not (value >= low and value <= high) then
			problem(`{what} must be between {low} and {high}`)
		end
	end

	local seen: { [string]: boolean } = {}
	for _, id in config.order do
		if config.gadgets[id] == nil then
			problem(`order lists unknown gadget {id}`)
		elseif seen[id] then
			problem(`order lists {id} twice`)
		end
		seen[id] = true
	end
	if #config.order == 0 or #config.order > 9 then
		problem("order needs 1 to 9 gadgets (keys 1-9)")
	end
	local lastPrice = 0
	for _, id in config.order do
		local def = config.gadgets[id]
		if def then
			if def.price < lastPrice then
				problem(`gadget {id} is cheaper than the one before it in order (the shop lists them by price)`)
			end
			lastPrice = def.price
		end
	end

	for id, def in config.gadgets do
		local name = `gadget {id}`
		if not seen[id] then
			problem(`{name} is missing from order`)
		end
		if string.match(id, "^%a%w*$") == nil or #id > 20 then
			problem(`{name}: ids are letters and digits (it is saved in the flag {GadgetRules.flag(id)})`)
		end
		if not GadgetRules.KINDS[def.kind] then
			problem(`{name} has an unknown kind {def.kind}`)
		end
		if def.icon == "" then
			problem(`{name} needs an icon`)
		end
		if string.match(def.color, HEX_PATTERN) == nil then
			problem(`{name} color must be #RRGGBB`)
		end
		local nameText = text[def.nameKey]
		if nameText == nil or nameText == "" or #nameText > 20 then
			problem(`{name} needs Theme.text.{def.nameKey}, at most 20 characters`)
		end
		local description = text[def.descriptionKey]
		if description == nil or description == "" then
			problem(`{name} needs Theme.text.{def.descriptionKey}`)
		else
			local filled = string.gsub(description, "{(%w+)}", function(key: string): string
				return if GadgetRules.describe(def)[key] ~= nil then "" else "{" .. key .. "}"
			end)
			if string.find(filled, "{", 1, true) then
				problem(`{name} description has a placeholder GadgetRules.describe doesn't fill`)
			end
		end
		if not (def.price == math.floor(def.price)) then
			problem(`{name} price must be whole cash`)
		end
		range(def.price, 100, 1e12, `{name} price`)
		range(def.cooldownSeconds, 5, 600, `{name} cooldownSeconds`)
		if def.kind == "speed" then
			range(def.durationSeconds, 1, 30, `{name} durationSeconds`)
			range(def.speedMultiplier, 1.05, 1.5, `{name} speedMultiplier`)
			local duration = def.durationSeconds or 0
			-- the speed comes and goes: never more than a third of the time
			if not (def.cooldownSeconds >= 3 * duration) then
				problem(`{name} cooldownSeconds must be at least 3x its durationSeconds`)
			end
		elseif def.kind == "shield" then
			-- Fairness: nobody is un-taggable for long, or often.
			range(def.durationSeconds, 1, 5, `{name} durationSeconds`)
			local duration = def.durationSeconds or 0
			if not (def.cooldownSeconds >= 5 * duration) then
				problem(`{name} cooldownSeconds must be at least 5x its durationSeconds`)
			end
		elseif def.kind == "peel" then
			range(def.durationSeconds, 10, 300, `{name} durationSeconds`)
			range(def.slipSeconds, 0.5, 3, `{name} slipSeconds`)
			range(def.triggerRadius, 1, 5, `{name} triggerRadius`)
		end
	end

	-- The widest any movement check gets is 1.5x walking speed, and a speed modifier alone is never capped.
	range(config.maxSpeedMultiplier, 1, 1.5, "maxSpeedMultiplier")
	if not (config.maxSpeedMultiplier >= maxModifierSpeed) then
		problem(`maxSpeedMultiplier must be at least the fastest speed modifier ({maxModifierSpeed})`)
	end
	range(config.speedGraceSeconds, 1, 10, "speedGraceSeconds")
	range(config.peel.checkSeconds, 0.05, 0.5, "peel.checkSeconds")
	range(config.peel.triggerHeight, 3.5, 8, "peel.triggerHeight")
	return problems
end

return GadgetRules
