--!strict
local T = require("./TestKit")
local GadgetRules = require("../src/shared/Logic/GadgetRules")
local ModifierRules = require("../src/shared/Logic/ModifierRules")
local StealRules = require("../src/shared/Logic/StealRules")
local Format = require("../src/shared/Logic/Format")
local Gadgets = require("../src/shared/Config/Gadgets")
local Gameplay = require("../src/shared/Config/Gameplay")
local Modifiers = require("../src/shared/Config/Modifiers")
local Theme = require("../src/shared/Config/Theme")
local Types = require("../src/shared/Types")

type UseContext = GadgetRules.UseContext

local TEXT = (Theme.text :: any) :: { [string]: string }
local MAX_MODIFIER_SPEED = ModifierRules.maxWalkSpeed(Modifiers)

local function copy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, item in value do
		result[key] = copy(item)
	end
	return result
end

local function def(id: string): Types.GadgetDef
	return Gadgets.gadgets[id]
end

-- The first gadget of `kind` in the real config.
local function ofKind(kind: string): (string, Types.GadgetDef)
	for _, id in Gadgets.order do
		if Gadgets.gadgets[id].kind == kind then
			return id, Gadgets.gadgets[id]
		end
	end
	error(`no {kind} gadget`)
end

T.describe("GadgetRules: the real config", function()
	T.it("is valid", function()
		local problems = GadgetRules.validate(Gadgets, TEXT, MAX_MODIFIER_SPEED)
		if #problems > 0 then
			print(table.concat(problems, "\n"))
		end
		T.expect(#problems).toBe(0)
	end)

	T.it("has the four gadgets of the brief, one of each kind, cheapest first", function()
		T.expect(#Gadgets.order).toBe(4)
		local kinds: { [string]: boolean } = {}
		local last = 0
		for _, id in Gadgets.order do
			local gadget = def(id)
			kinds[gadget.kind] = true
			T.expect(gadget.price).toBeGreaterThan(last)
			last = gadget.price
		end
		T.expect(kinds.speed and kinds.peel and kinds.shield and kinds.magnet).toBe(true)
	end)

	T.it("prices are early-to-mid-game goals: the first in minutes, the last before the first rebirth", function()
		-- BALANCE.md "Gadgets": a free player can save for the first after ~3 minutes and the last within the hour.
		T.expect(def(Gadgets.order[1]).price).toBeAtMost(5000) -- a few minutes of a new player's income
		T.expect(def(Gadgets.order[#Gadgets.order]).price).toBeLessThan(25e6) -- the first rebirth costs $25M
		for _, id in Gadgets.order do
			T.expect(def(id).price % 100).toBe(0) -- round numbers on the shop card
		end
	end)

	T.it("uses the brief's numbers", function()
		local _, soda = ofKind("speed")
		T.expect(soda.speedMultiplier).toBe(1.3)
		T.expect(soda.durationSeconds).toBe(6)
		T.expect(soda.cooldownSeconds).toBe(35)
		local _, peel = ofKind("peel")
		T.expect(peel.durationSeconds).toBe(90)
		T.expect(peel.slipSeconds).toBe(1.5)
		T.expect(peel.cooldownSeconds).toBe(45)
		local _, shield = ofKind("shield")
		T.expect(shield.durationSeconds).toBe(3)
		T.expect(shield.cooldownSeconds).toBe(40)
		local _, magnet = ofKind("magnet")
		T.expect(magnet.cooldownSeconds).toBe(60)
	end)

	T.it("fills every description and names every gadget", function()
		for _, id in Gadgets.order do
			local gadget = def(id)
			local name = TEXT[gadget.nameKey]
			T.expect(type(name) == "string" and #name > 0).toBe(true)
			local text = Format.template(TEXT[gadget.descriptionKey], GadgetRules.describe(gadget))
			T.expect((string.find(text, "{", 1, true))).toBeNil()
		end
		local _, soda = ofKind("speed")
		T.expect(GadgetRules.describe(soda).percent).toBe(30)
	end)

	T.it("has text for every refusal that is reported", function()
		for _, reason in GadgetRules.REASONS do
			local key = GadgetRules.messageKey(reason)
			if key then
				T.expect(type(TEXT[key]) == "string").toBe(true)
			end
		end
		-- these are silent on purpose: garbage ids and a dead player's button mash
		T.expect(GadgetRules.messageKey("unknown")).toBeNil()
		T.expect(GadgetRules.messageKey("dead")).toBeNil()
	end)
end)

T.describe("GadgetRules ownership", function()
	T.it("is a flag per gadget, so it survives rebirths with no save-format change", function()
		T.expect(GadgetRules.flag("soda")).toBe("gadget_soda")
		local flags: { [string]: boolean } = { gadget_shield = true, gadget_soda = true, gadget_gone = true }
		T.expect(GadgetRules.owns(flags, "soda")).toBe(true)
		T.expect(GadgetRules.owns(flags, "peel")).toBe(false)
		-- config order, and a flag the config no longer knows is ignored (and kept in the save)
		T.expect(GadgetRules.owned(flags, Gadgets)).toEqual({ "soda", "shield" })
	end)

	T.it("gives every gadget its config slot (button and key)", function()
		for index, id in Gadgets.order do
			T.expect(GadgetRules.slot(Gadgets, id)).toBe(index)
		end
		T.expect(GadgetRules.slot(Gadgets, "nope")).toBeNil()
	end)
end)

T.describe("GadgetRules.affordableTip (finding gadgets)", function()
	local soda, peel = Gadgets.gadgets.soda.price, Gadgets.gadgets.peel.price
	T.it("names the cheapest gadget not owned once it is affordable with cash", function()
		T.expect(GadgetRules.affordableTip(Gadgets, {}, soda - 1, false, false)).toBeNil()
		T.expect(GadgetRules.affordableTip(Gadgets, {}, soda, false, false)).toBe("soda")
		T.expect(GadgetRules.affordableTip(Gadgets, {}, 1e12, false, false)).toBe("soda") -- the cheapest of all
		T.expect(GadgetRules.affordableTip(Gadgets, { gadget_soda = true }, peel, false, false)).toBe("peel")
		T.expect(GadgetRules.affordableTip(Gadgets, { gadget_soda = true }, peel - 1, false, false)).toBeNil()
	end)
	T.it("once per account, and never while the tutorial needs the screen", function()
		T.expect(GadgetRules.affordableTip(Gadgets, { [GadgetRules.TIP_FLAG] = true }, 1e12, false, false)).toBeNil()
		T.expect(GadgetRules.affordableTip(Gadgets, {}, 1e12, true, false)).toBeNil()
	end)
	T.it("never points an Auto Collect owner at the magnet", function()
		local flags = { gadget_soda = true, gadget_peel = true, gadget_shield = true }
		T.expect(GadgetRules.affordableTip(Gadgets, flags, 1e12, false, false)).toBe("magnet")
		T.expect(GadgetRules.affordableTip(Gadgets, flags, 1e12, false, true)).toBeNil()
	end)
	T.it("the hint's text names the gadget and where to buy it", function()
		local text = Format.template(TEXT.gadgetTip, { icon = "🥤", name = TEXT.gadgetSodaName })
		T.expect(text).toBe("🥤 You can buy a Fizzy Soda with cash! Shop ▸ " .. TEXT.storeTabGadgets)
	end)
end)

T.describe("GadgetRules buying", function()
	T.it("refuses unknown gadgets, ones you own and ones you can't afford", function()
		local function buy(exists: boolean, owned: boolean, cash: number): string?
			local _, reason = GadgetRules.canBuy({ exists = exists, owned = owned, cash = cash, price = 1500 })
			return reason
		end
		T.expect(buy(false, false, 1e9)).toBe("unknown")
		T.expect(buy(true, true, 1e9)).toBe("owned")
		T.expect(buy(true, false, 1499)).toBe("cash")
		T.expect(buy(true, false, 0 / 0)).toBe("cash")
		T.expect((GadgetRules.canBuy({ exists = true, owned = false, cash = 1500, price = 1500 }))).toBe(true)
	end)
end)

T.describe("GadgetRules cooldowns", function()
	local function useContext(state: GadgetRules.State, id: string, t: number): UseContext
		return { owned = true, inTutorial = false, alive = true, now = t, readyAt = state.readyAt[id] }
	end

	T.it("starts when used and holds for the gadget's cooldown (server time)", function()
		for _, id in Gadgets.order do
			local gadget = def(id)
			local state = GadgetRules.newState()
			T.expect((GadgetRules.canUse(useContext(state, id, 100)))).toBe(true)
			GadgetRules.use(state, id, gadget, 100, Gadgets)
			T.expect(state.readyAt[id]).toBe(100 + gadget.cooldownSeconds)
			local ok, reason = GadgetRules.canUse(useContext(state, id, 100 + gadget.cooldownSeconds - 0.01))
			T.expect(ok).toBe(false)
			T.expect(reason).toBe("cooldown")
			T.expect(GadgetRules.remaining(state, id, 100 + gadget.cooldownSeconds - 10)).toBeNear(10, 1e-9)
			T.expect((GadgetRules.canUse(useContext(state, id, 100 + gadget.cooldownSeconds)))).toBe(true)
			T.expect(GadgetRules.remaining(state, id, 1e6)).toBe(0)
		end
	end)

	T.it("each gadget has its own cooldown", function()
		local state = GadgetRules.newState()
		GadgetRules.use(state, "soda", def("soda"), 0, Gadgets)
		T.expect((GadgetRules.canUse(useContext(state, "shield", 1)))).toBe(true)
	end)

	T.it("refuses in this order: not owned, during the tutorial, dead, recharging", function()
		local function reason(owned: boolean, tutorial: boolean, alive: boolean, readyAt: number?): string?
			local _, why =
				GadgetRules.canUse({ owned = owned, inTutorial = tutorial, alive = alive, now = 10, readyAt = readyAt })
			return why
		end
		T.expect(reason(false, true, false, 99)).toBe("notOwned")
		T.expect(reason(true, true, false, 99)).toBe("tutorial")
		T.expect(reason(true, false, false, 99)).toBe("dead")
		T.expect(reason(true, false, true, 99)).toBe("cooldown")
		T.expect(reason(true, false, true, 0 / 0)).toBe("cooldown") -- a broken time never lets it through
		T.expect(reason(true, false, true, nil)).toBeNil()
	end)
end)

T.describe("GadgetRules speed", function()
	local id, soda = ofKind("speed")
	local grace = Gadgets.speedGraceSeconds

	T.it("runs for its duration, and the movement checks keep allowing it for the grace after", function()
		local state = GadgetRules.newState()
		T.expect(GadgetRules.speedMultiplier(state, 0)).toBe(1)
		T.expect(GadgetRules.speedAllowance(state, 0, grace)).toBe(1)
		GadgetRules.use(state, id, soda, 50, Gadgets)
		local duration = soda.durationSeconds :: number
		T.expect(GadgetRules.speedMultiplier(state, 50)).toBe(1.3)
		T.expect(GadgetRules.speedMultiplier(state, 50 + duration - 0.01)).toBe(1.3)
		T.expect(GadgetRules.speedMultiplier(state, 50 + duration)).toBe(1)
		T.expect(GadgetRules.speedAllowance(state, 50 + duration + grace - 0.01, grace)).toBe(1.3)
		T.expect(GadgetRules.speedAllowance(state, 50 + duration + grace, grace)).toBe(1)
		T.expect(state.activeUntil[id]).toBe(50 + duration)
	end)

	T.it("a faster speed replaced by a slower one stays allowed as long as it would have", function()
		local fast = copy(soda)
		fast.speedMultiplier = 1.45
		local state = GadgetRules.newState()
		GadgetRules.use(state, "fast", fast, 0, Gadgets)
		GadgetRules.use(state, id, soda, 2, Gadgets) -- replaces it two seconds in
		T.expect(GadgetRules.speedMultiplier(state, 3)).toBe(1.3)
		T.expect(GadgetRules.speedAllowance(state, 3, grace)).toBe(1.45)
		T.expect(GadgetRules.speedAllowance(state, (fast.durationSeconds :: number) + grace - 0.01, grace)).toBe(1.45)
		T.expect(GadgetRules.speedAllowance(state, (fast.durationSeconds :: number) + grace, grace)).toBe(1.3)
	end)

	T.it("caps a modifier and a gadget together at 1.5x", function()
		T.expect(Gadgets.maxSpeedMultiplier).toBeAtMost(1.5)
		-- Sugar Rush (x1.25) with the soda (x1.3) would be 1.625
		T.expect(GadgetRules.combinedSpeed(1.25, 1.3, Gadgets.maxSpeedMultiplier)).toBe(1.5)
		T.expect(GadgetRules.combinedSpeed(1, 1.3, Gadgets.maxSpeedMultiplier)).toBe(1.3)
		T.expect(GadgetRules.combinedSpeed(0.8, 1.3, Gadgets.maxSpeedMultiplier)).toBeNear(1.04, 1e-9)
		T.expect(GadgetRules.combinedSpeed(1.25, 1, Gadgets.maxSpeedMultiplier)).toBe(1.25) -- a modifier alone: as is
		T.expect(GadgetRules.fastestSpeed(Gadgets, MAX_MODIFIER_SPEED)).toBeAtMost(1.5)
	end)

	T.it("never lets anyone walk faster than the movement checks allow", function()
		-- Sweep a soda and a speed modifier starting and ending in every order: the speed the humanoid gets is
		-- never above what PositionTracker and the carry budget allow at that moment (and both stay at 1.5x or less).
		local walkLimit = Modifiers.limits.walkSpeed
		for _, modifierSpeed in { walkLimit.min, 1, 1.25, walkLimit.max } do
			for _, sodaAt in { 0, 3, 7, 12 } do
				local state = GadgetRules.newState()
				GadgetRules.use(state, id, soda, sodaAt, Gadgets)
				for step = 0, 200 do
					local t = step * 0.1
					-- the modifier runs from 5 s to 10 s; ModifierService keeps its allowance for 4 s after a change
					local modifierNow = if t >= 5 and t < 10 then modifierSpeed else 1
					local modifierAllowance = math.max(modifierNow, if t >= 10 and t < 14 then modifierSpeed else 1)
					local speed = GadgetRules.combinedSpeed(
						modifierNow,
						GadgetRules.speedMultiplier(state, t),
						Gadgets.maxSpeedMultiplier
					)
					local allowed = GadgetRules.combinedSpeed(
						modifierAllowance,
						GadgetRules.speedAllowance(state, t, grace),
						Gadgets.maxSpeedMultiplier
					)
					T.expect(speed).toBeAtMost(allowed)
					T.expect(allowed).toBeAtMost(1.5)
				end
			end
		end
	end)

	T.it("keeps a carrying thief on soda slower than anyone walking, and catchable", function()
		local carrying = Gameplay.walkSpeed * Gameplay.steal.carrySpeedMultiplier * 1.3
		T.expect(carrying).toBeLessThan(Gameplay.walkSpeed) -- a tagger on foot still catches up
		local cappedCarry = Gameplay.walkSpeed * Gameplay.steal.carrySpeedMultiplier * Gadgets.maxSpeedMultiplier
		T.expect(cappedCarry).toBeLessThan(Gameplay.walkSpeed)
	end)
end)

T.describe("GadgetRules shield", function()
	local id, shield = ofKind("shield")

	T.it("stops tags for its few seconds, then ends", function()
		local state = GadgetRules.newState()
		T.expect(GadgetRules.isShielded(state, 0)).toBe(false)
		GadgetRules.use(state, id, shield, 10, Gadgets)
		T.expect(GadgetRules.isShielded(state, 10)).toBe(true)
		T.expect(GadgetRules.isShielded(state, 10 + (shield.durationSeconds :: number) - 0.01)).toBe(true)
		T.expect(GadgetRules.isShielded(state, 10 + (shield.durationSeconds :: number))).toBe(false)
		T.expect(state.shieldId).toBe(id)
	end)

	T.it("is fair: never long, and off most of the time even used on every recharge", function()
		local duration = shield.durationSeconds :: number
		T.expect(duration).toBeAtMost(5)
		T.expect(duration / shield.cooldownSeconds).toBeLessThan(0.2)
	end)

	T.it("is the last tag check, so only a tag that would have landed says Shielded!", function()
		local function tag(shielded: boolean, distance: number, cooldownUntil: number): (boolean, string?)
			return StealRules.canTag({
				now = 10,
				taggerUserId = 1,
				thiefUserId = 2,
				thiefCarrying = true,
				horizontalDistance = distance,
				verticalDistance = 0,
				tagRange = 13,
				tagVerticalAllowance = 28,
				taggerCooldownUntil = cooldownUntil,
				taggerTrusted = true,
				thiefShielded = shielded,
			})
		end
		T.expect((tag(false, 5, 0))).toBe(true)
		T.expect(select(2, tag(true, 5, 0))).toBe("shielded")
		T.expect(select(2, tag(true, 50, 0))).toBe("far")
		T.expect(select(2, tag(true, 5, 20))).toBe("cooldown")
	end)
end)

T.describe("GadgetRules banana peel", function()
	local id, peel = ofKind("peel")
	-- A plot the size of the real ones (Config/Gameplay.map), the way MapBuilder lays them out.
	local map = Gameplay.map
	local rect: StealRules.Rect =
		{ minX = 100 - map.plotWidth / 2, maxX = 100 + map.plotWidth / 2, minZ = 30, maxZ = 30 + map.plotDepth }

	local function place(x: number, z: number, height: number, trusted: boolean?, noPlot: boolean?): (boolean, string?)
		return GadgetRules.canPlacePeel({
			x = x,
			z = z,
			rect = if noPlot then nil else rect,
			heightAboveFloor = height,
			wallHeight = map.wallHeight,
			trusted = trusted ~= false,
		})
	end

	T.it("goes down only inside your own base, on its floor", function()
		T.expect((place(100, 60, 3))).toBe(true)
		T.expect((place(rect.minX, rect.minZ, 3))).toBe(true) -- the edge still counts, as for steals
		T.expect(select(2, place(rect.minX - 0.1, 60, 3))).toBe("outside")
		T.expect(select(2, place(100, rect.maxZ + 0.1, 3))).toBe("outside")
		T.expect(select(2, place(100, 60, 3, true, true))).toBe("outside") -- no base at all
		T.expect(select(2, place(0 / 0, 60, 3))).toBe("outside")
		T.expect(select(2, place(100, 60, map.wallHeight + 3))).toBe("height") -- standing on a wall
		T.expect(select(2, place(100, 60, 0 / 0))).toBe("height")
		T.expect(select(2, place(100, 60, 3, false))).toBe("untrusted")
	end)

	T.it("trips whoever walks within its radius, but not someone jumping over it", function()
		local radius = peel.triggerRadius :: number
		local height = Gadgets.peel.triggerHeight
		T.expect(GadgetRules.stepsOnPeel(0, 0, 3, radius, height)).toBe(true)
		T.expect(GadgetRules.stepsOnPeel(radius * 0.7, radius * 0.7, 3, radius, height)).toBe(true)
		T.expect(GadgetRules.stepsOnPeel(radius + 0.01, 0, 3, radius, height)).toBe(false)
		T.expect(GadgetRules.stepsOnPeel(0, 0, 3 + 7, radius, height)).toBe(false) -- a jump clears it
		T.expect(GadgetRules.stepsOnPeel(0, 0, -5, radius, height)).toBe(false)
		T.expect(GadgetRules.stepsOnPeel(0 / 0, 0, 3, radius, height)).toBe(false)
		-- a standing root (about 3 studs up) counts; so does a tall avatar's
		T.expect(height).toBeGreaterThan(4.5)
		-- walking through it takes several server checks even at the fastest carrying speed
		local fastest = Gameplay.walkSpeed * Gadgets.maxSpeedMultiplier
		T.expect(2 * radius / fastest).toBeGreaterThan(2 * Gadgets.peel.checkSeconds)
	end)

	T.it("records how long the peel stays, and freezes for the slip", function()
		local state = GadgetRules.newState()
		GadgetRules.use(state, id, peel, 0, Gadgets)
		T.expect(state.activeUntil[id]).toBe(peel.durationSeconds)
		T.expect(state.readyAt[id]).toBe(peel.cooldownSeconds)
		-- one peel at a time, and the next one can be put down before the first has gone (it replaces it)
		T.expect(peel.cooldownSeconds).toBeLessThan(peel.durationSeconds :: number)
		local victim = GadgetRules.newState()
		GadgetRules.freeze(victim, 5, peel.slipSeconds :: number)
		T.expect(GadgetRules.isFrozen(victim, 5)).toBe(true)
		T.expect(GadgetRules.isFrozen(victim, 5 + (peel.slipSeconds :: number))).toBe(false)
		GadgetRules.freeze(victim, 4, 0.5) -- an earlier, shorter slip never shortens it
		T.expect(victim.frozenUntil).toBe(5 + (peel.slipSeconds :: number))
	end)
end)

T.describe("GadgetRules view", function()
	T.it("tells the client what it owns, when each is ready and what is running", function()
		local state = GadgetRules.newState()
		GadgetRules.use(state, "soda", def("soda"), 100, Gadgets)
		GadgetRules.use(state, "magnet", def("magnet"), 100, Gadgets) -- not owned: left out of the view
		local view = GadgetRules.view({ gadget_soda = true, gadget_peel = true }, state, Gadgets)
		T.expect(view.owned).toEqual({ "soda", "peel" })
		T.expect(view.readyAt.soda).toBe(100 + def("soda").cooldownSeconds)
		T.expect(view.readyAt.peel).toBeNil()
		T.expect(view.readyAt.magnet).toBeNil()
		T.expect(view.activeUntil.soda).toBe(100 + (def("soda").durationSeconds :: number))
		T.expect(view.usedAt.soda).toBe(100) -- the button's disc runs over readyAt - usedAt
		T.expect(view.usedAt.magnet).toBeNil()
	end)
end)

T.describe("GadgetRules Gadget Frenzy (faster recharges)", function()
	local FRENZY = ModifierRules.effects(Modifiers, "gadgetFrenzy").gadgetCooldown
	local STRONGEST = Modifiers.limits.gadgetCooldown.min

	T.it("halves every recharge", function()
		T.expect(FRENZY).toBe(0.5)
		T.expect(GadgetRules.cooldownSeconds(def("peel"), FRENZY)).toBe(def("peel").cooldownSeconds / 2)
		T.expect(GadgetRules.cooldownSeconds(def("shield"), FRENZY)).toBe(def("shield").cooldownSeconds / 2)
		T.expect(GadgetRules.cooldownSeconds(def("magnet"), FRENZY)).toBe(def("magnet").cooldownSeconds / 2)
	end)

	T.it("never below a gadget's fairness floor: a soda runs at most a third of the time", function()
		local soda = def("soda")
		local duration = soda.durationSeconds :: number
		T.expect(GadgetRules.cooldownSeconds(soda, FRENZY)).toBe(math.max(3 * duration, soda.cooldownSeconds / 2))
		T.expect(GadgetRules.cooldownSeconds(soda, FRENZY)).toBe(18) -- not 17.5
	end)

	T.it("keeps every gadget fair even at the strongest recharge any modifier may set", function()
		for _, id in Gadgets.order do
			local gadget = def(id)
			local cooldown = GadgetRules.cooldownSeconds(gadget, STRONGEST)
			local duration = gadget.durationSeconds or 0
			T.expect(cooldown).toBeAtLeast(GadgetRules.MIN_COOLDOWN)
			if gadget.kind == "speed" then
				T.expect(cooldown).toBeAtLeast(3 * duration)
			elseif gadget.kind == "shield" then
				T.expect(cooldown).toBeAtLeast(5 * duration)
			end
		end
	end)

	T.it("changes nothing without it, and ignores a nonsense multiplier", function()
		for _, id in Gadgets.order do
			local gadget = def(id)
			T.expect(GadgetRules.cooldownSeconds(gadget, nil)).toBe(gadget.cooldownSeconds)
			T.expect(GadgetRules.cooldownSeconds(gadget, 1)).toBe(gadget.cooldownSeconds)
			T.expect(GadgetRules.cooldownSeconds(gadget, 0 / 0)).toBe(gadget.cooldownSeconds)
			T.expect(GadgetRules.cooldownSeconds(gadget, -1)).toBe(gadget.cooldownSeconds)
		end
	end)

	T.it("starts the shorter recharge for a gadget used while it runs", function()
		local state = GadgetRules.newState()
		GadgetRules.use(state, "shield", def("shield"), 100, Gadgets, FRENZY)
		T.expect(state.usedAt.shield).toBe(100)
		T.expect(state.readyAt.shield).toBe(100 + def("shield").cooldownSeconds / 2)
		-- the effect itself is untouched
		T.expect(state.shieldUntil).toBe(100 + (def("shield").durationSeconds :: number))
	end)

	T.it("lets a gadget already recharging finish the rest at the new pace when it starts", function()
		local state = GadgetRules.newState()
		GadgetRules.use(state, "magnet", def("magnet"), 100, Gadgets) -- ready at 160
		T.expect(GadgetRules.rechargeChanged(state, Gadgets, 120, 1, FRENZY)).toBe(true)
		T.expect(state.readyAt.magnet).toBe(140) -- 40 s left, now 20
	end)

	T.it("never sooner than the floor after it was used", function()
		local state = GadgetRules.newState()
		GadgetRules.use(state, "soda", def("soda"), 100, Gadgets) -- ready at 135
		GadgetRules.rechargeChanged(state, Gadgets, 100, 1, FRENZY) -- at once: 117.5 would be under the floor
		T.expect(state.readyAt.soda).toBe(100 + 3 * (def("soda").durationSeconds :: number))
	end)

	T.it("leaves recharges as they are when it ends, and ignores gadgets already ready", function()
		local state = GadgetRules.newState()
		GadgetRules.use(state, "peel", def("peel"), 100, Gadgets, FRENZY)
		local readyAt = state.readyAt.peel
		T.expect(GadgetRules.rechargeChanged(state, Gadgets, 105, FRENZY, 1)).toBe(false)
		T.expect(state.readyAt.peel).toBe(readyAt)
		T.expect(GadgetRules.rechargeChanged(state, Gadgets, readyAt + 1, 1, FRENZY)).toBe(false)
		T.expect(state.readyAt.peel).toBe(readyAt)
	end)
end)

T.describe("GadgetRules validation", function()
	local function problemsWith(edit: (config: any) -> ()): number
		local config = copy(Gadgets)
		edit(config)
		return #GadgetRules.validate(config, TEXT, MAX_MODIFIER_SPEED)
	end

	T.it("refuses a broken config", function()
		T.expect(problemsWith(function(c)
			c.maxSpeedMultiplier = 1.6 -- wider than the anti-cheat may ever get
		end)).toBeGreaterThan(0)
		T.expect(problemsWith(function(c)
			c.maxSpeedMultiplier = 1.2 -- would slow down Sugar Rush on its own
		end)).toBeGreaterThan(0)
		T.expect(problemsWith(function(c)
			c.gadgets.shield.durationSeconds = 8 -- un-taggable for too long
		end)).toBeGreaterThan(0)
		T.expect(problemsWith(function(c)
			c.gadgets.shield.cooldownSeconds = 10 -- un-taggable too often
		end)).toBeGreaterThan(0)
		T.expect(problemsWith(function(c)
			c.gadgets.soda.speedMultiplier = 2
		end)).toBeGreaterThan(0)
		T.expect(problemsWith(function(c)
			c.gadgets.soda.kind = "teleport"
		end)).toBeGreaterThan(0)
		T.expect(problemsWith(function(c)
			c.gadgets.peel.triggerRadius = nil
		end)).toBeGreaterThan(0)
		T.expect(problemsWith(function(c)
			c.gadgets.magnet.price = 10 -- cheaper than the shield before it
		end)).toBeGreaterThan(0)
		T.expect(problemsWith(function(c)
			c.gadgets.peel.nameKey = "noSuchText"
		end)).toBeGreaterThan(0)
		T.expect(problemsWith(function(c)
			table.insert(c.order, "soda")
		end)).toBeGreaterThan(0)
		T.expect(problemsWith(function(c)
			c.gadgets.extra = copy(c.gadgets.soda) -- not in order
		end)).toBeGreaterThan(0)
		T.expect(problemsWith(function(c)
			c.gadgets["bad id"] = copy(c.gadgets.soda)
			table.insert(c.order, "bad id")
		end)).toBeGreaterThan(0)
	end)
end)

return nil
