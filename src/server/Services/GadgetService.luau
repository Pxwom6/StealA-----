--!strict
--[[
	Gadgets (Config/Gadgets): gear bought once with in-game cash and used whenever the player likes.

	  BuyGadget(id)  the gadget exists, isn't owned yet and the player has the cash (the server's price): the cash is
	                 spent and the save flag gadget_<id> set, kept forever (rebirths too; no save-format change). A
	                 shortfall only says "Not enough cash!": gadgets never lead to a Robux offer.
	  UseGadget(id)  owned, not during the first-time tutorial, alive and recharged (server time, this session), then
	                 the gadget's own checks; nothing yields between the checks and the effect:
	    speed   the player walks (and carries) faster for a few seconds (Movement; the movement checks follow)
	    peel    a banana peel on the floor at their feet, only inside their own base, at the position the server sees
	            and trusts (the client sends no position). One per player: a new one replaces the old. The first other
	            player whose trusted position steps on it slips (Logic/GadgetRules.stepsOnPeel, checked on a short
	            timer like coin pickups, no client touch events): frozen for a moment, and a Snackling of the owner's
	            they carry runs home exactly as after a tag (StealService.slipped). It goes after its lifetime.
	    shield  StealService refuses tags on the player for a few seconds and tells the tagger "Shielded!" (locks,
	            peels and everything else still work)
	    magnet  every active pad of their base is collected through the pad path (EconomyService.collectPad: same
	            floating "+$X", same collect event, same analytics); refused when there is nothing to collect. The
	            Auto Collect pass does this every few seconds, so for its owners the magnet is neither used nor sold
	            ("auto": its button shows AUTO, GadgetRules.coveredByAutoCollect)

	Gadget Frenzy (a server modifier, Config/Modifiers `gadgetCooldown`): a gadget used while it runs recharges in half
	the time, and one already recharging when it starts finishes the rest at that pace, never under the fairness floors
	(Logic/GadgetRules.cooldownSeconds: a soda runs at most a third of the time, a shield a fifth). When it ends,
	recharges keep whatever they had left. Speeds, the movement caps and every other rule are untouched.

	What players see: the Player attributes GadgetSpeedUntil and SlippedUntil (server time) drive the soda fizz and the
	dizzy stars on every client (GadgetFxController); a shielded player wears a translucent bubble the server makes
	(welded to them, massless, never collides, touches or blocks a ray; ShieldUntil says until when); peels are
	anchored, non-colliding models in workspace.Gadgets; Effect "gadget" (to the user), "slip" (to everyone) and
	"shieldBlock" (to the tagger) cue sounds and bursts.

	Finding them: the first time a gadget the player doesn't own becomes affordable with cash, one toast says so
	("🥤 You can buy a Fizzy Soda with cash! Shop ▸ Gadgets"), once per account (the flag tip_gadgets), never during
	the first-time tutorial or just after it (GadgetRules.affordableTip, checked once a second).

	Analytics: gadget_bought (value = price, 01 = gadget id), gadget_used (01 = gadget id), gadget_effect (01 = gadget
	id, 02 = "peelDrop" | "peelSlip" | "shieldBlock"; the shield one is logged by StealService).
	Studio: /gadgets [all|off] grants or removes every gadget and recharges them (DevCommands).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Gadgets = require(ReplicatedStorage.Shared.Config.Gadgets)
local Gameplay = require(ReplicatedStorage.Shared.Config.Gameplay)
local Modifiers = require(ReplicatedStorage.Shared.Config.Modifiers)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local Types = require(ReplicatedStorage.Shared.Types)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local GadgetRules = require(ReplicatedStorage.Shared.Logic.GadgetRules)
local Guard = require(ReplicatedStorage.Shared.Logic.Guard)
local ModifierRules = require(ReplicatedStorage.Shared.Logic.ModifierRules)
local Analytics = require(script.Parent.Analytics)
local EconomyService = require(script.Parent.EconomyService)
local ModifierService = require(script.Parent.ModifierService)
local Movement = require(script.Parent.Movement)
local PlotService = require(script.Parent.PlotService)
local PositionTracker = require(script.Parent.PositionTracker)
local Remotes = require(script.Parent.Remotes)
local Replication = require(script.Parent.Replication)
local Sessions = require(script.Parent.Sessions)
local StealService = require(script.Parent.StealService)
local TutorialService = require(script.Parent.TutorialService)

type Session = Sessions.Session
type GadgetDef = Types.GadgetDef

type Peel = {
	ownerUserId: number,
	gadgetId: string,
	def: GadgetDef,
	position: Vector3, -- its middle, on the owner's floor
	expiresAt: number,
	model: Model,
}

local GadgetService = {}

local folder: Folder
local random = Random.new()
local peels: { [number]: Peel } = {} -- by owner UserId: one each
local bubbles: { [Session]: { part: BasePart, untilT: number } } = {} -- Bubble Shields up right now
-- Players with a speed gadget or a slip running, and the speed state last given to their Humanoid: when either ends,
-- Movement gives them their normal speed back (server time, so it ends when the effect does).
local watching: { [Session]: string } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function nameOf(def: GadgetDef): string
	return UiTheme.text(def.nameKey)
end

-- What the Humanoid's speed depends on from gadgets right now (a change means it needs applying again).
local function speedPhase(session: Session, t: number): string
	return `{GadgetRules.isFrozen(session.gadgets, t)}|{GadgetRules.speedMultiplier(session.gadgets, t)}`
end

-- Gives `session` its speed now and keeps watching it until its gadget effects are over.
local function applySpeed(session: Session)
	Movement.apply(session)
	watching[session] = speedPhase(session, now())
end

local function stepSpeeds(t: number)
	for session, phase in watching do
		if Sessions.get(session.player) ~= session then
			watching[session] = nil
			continue
		end
		local current = speedPhase(session, t)
		if current ~= phase then
			Movement.apply(session)
			watching[session] = current
		end
		if not GadgetRules.isFrozen(session.gadgets, t) and GadgetRules.speedMultiplier(session.gadgets, t) == 1 then
			watching[session] = nil
		end
	end
end

-- Bubble Shields ------------------------------------------------------------------------------------------------------

local BUBBLE_SIZE = 7.5

local function removeBubble(session: Session)
	local bubble = bubbles[session]
	if bubble then
		bubbles[session] = nil
		bubble.part:Destroy()
	end
end

-- A translucent bubble around `session`'s character until `untilT`, for everyone to see who can't be tagged.
local function addBubble(session: Session, def: GadgetDef, untilT: number)
	removeBubble(session)
	local root = Sessions.rootPart(session)
	local character = session.player.Character
	if root == nil or character == nil then
		return
	end
	local part = Instance.new("Part")
	part.Name = "GadgetShield"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.one * BUBBLE_SIZE
	part.Material = Enum.Material.ForceField
	part.Color = UiTheme.color(def.color)
	part.Transparency = 0.2
	part.CastShadow = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.Anchored = false
	part.CFrame = root.CFrame
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = part
	weld.Parent = part
	part.Parent = character
	bubbles[session] = { part = part, untilT = untilT }
end

local function stepBubbles(t: number)
	for session, bubble in bubbles do
		if t >= bubble.untilT or bubble.part.Parent == nil or Sessions.get(session.player) ~= session then
			removeBubble(session)
		end
	end
end

-- Peels ---------------------------------------------------------------------------------------------------------------

local function peelPart(props: { [string]: any }): BasePart
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		(part :: any)[key] = value
	end
	return part
end

-- A banana peel lying on the floor at `spot` (its middle, on the floor): a squashed yellow dome, four curled flaps
-- with brown tips, a little stem. About 3 studs across; anchored, never collides, touched or ray cast.
local function buildPeel(spot: Vector3, color: Color3): Model
	local model = Instance.new("Model")
	model.Name = "BananaPeel"
	local tip = UiTheme.world("bananaPeelTip")
	local base = CFrame.new(spot) * CFrame.Angles(0, random:NextNumber() * math.pi * 2, 0)
	local middle = peelPart({
		Name = "Peel",
		Size = Vector3.new(1.3, 0.55, 1.3),
		CFrame = base * CFrame.new(0, 0.2, 0),
		Color = color,
		Parent = model,
	})
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = middle
	model.PrimaryPart = middle
	for index = 0, 3 do
		local around = base * CFrame.Angles(0, index * math.pi / 2 + math.pi / 4, 0)
		-- each flap lies outward from the middle, its far end curling up a little
		local flap = around * CFrame.new(0, 0.12, -0.95) * CFrame.Angles(math.rad(-12), 0, 0)
		peelPart({ Name = "Flap", Size = Vector3.new(0.75, 0.16, 1.5), CFrame = flap, Color = color, Parent = model })
		peelPart({
			Name = "Tip",
			Size = Vector3.new(0.5, 0.17, 0.3),
			CFrame = flap * CFrame.new(0, 0.01, -0.72),
			Color = tip,
			Parent = model,
		})
	end
	peelPart({
		Name = "Stem",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.45, 0.22, 0.22),
		CFrame = base * CFrame.new(0, 0.52, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = tip,
		Parent = model,
	})
	return model
end

-- Takes `ownerUserId`'s peel away (gone, stepped on, replaced, or its owner left), and its "running" ring off their
-- button. `replacedBy`: the gadget whose new peel takes its place; when that is the same gadget, the ring
-- GadgetRules.use just started is the new peel's and stays.
local function removePeel(ownerUserId: number, replacedBy: string?)
	local peel = peels[ownerUserId]
	if peel == nil then
		return
	end
	peels[ownerUserId] = nil
	peel.model:Destroy()
	local owner = Sessions.getByUserId(ownerUserId)
	if owner and peel.gadgetId ~= replacedBy then
		owner.gadgets.activeUntil[peel.gadgetId] = nil
		Replication.markDirty(owner)
	end
end

local function placePeel(session: Session, id: string, def: GadgetDef, at: Vector3, t: number)
	removePeel(session.userId, id) -- one each: a new peel replaces the old one
	local spot = Vector3.new(at.X, PlotService.refs(session.plot).floorY, at.Z)
	local expiresAt = t + (def.durationSeconds or 0)
	local model = buildPeel(spot, UiTheme.color(def.color))
	model:SetAttribute("OwnerUserId", session.userId)
	model:SetAttribute("ExpiresAt", expiresAt)
	model.Parent = folder
	peels[session.userId] = {
		ownerUserId = session.userId,
		gadgetId = id,
		def = def,
		position = spot,
		expiresAt = expiresAt,
		model = model,
	}
	Remotes.notify(session.player, Theme.text.peelPlaced, "success")
end

-- `victim` stepped on `peel`: they slip (frozen), and a Snackling of the peel owner's they carry runs home.
local function slip(peel: Peel, victim: Session, t: number)
	removePeel(peel.ownerUserId)
	GadgetRules.freeze(victim.gadgets, t, peel.def.slipSeconds or 0)
	victim.player:SetAttribute("SlippedUntil", victim.gadgets.frozenUntil)
	local owner = Sessions.getByUserId(peel.ownerUserId)
	-- Like a tag: the carry is cancelled, the Snackling runs home, the thief waits before stealing again, and both
	-- hear about it from StealService (its toasts name the peel).
	local dropped = owner ~= nil and StealService.slipped(victim, owner)
	applySpeed(victim) -- frozen (after the carry's own speed reset)
	if owner and not dropped then
		Remotes.notify(
			victim.player,
			Format.template(Theme.text.peelSlipped, { owner = owner.player.DisplayName }),
			"warning"
		)
		Remotes.notify(
			owner.player,
			Format.template(Theme.text.peelSlippedOwner, { player = victim.player.DisplayName }),
			"success"
		)
	end
	Remotes.fireAll("Effect", {
		kind = "slip",
		position = peel.position,
		userId = victim.userId,
		ownerUserId = peel.ownerUserId,
	})
	if owner then
		Analytics.custom(owner, "gadget_effect", nil, { peel.gadgetId, if dropped then "peelDrop" else "peelSlip" })
	end
end

local function stepPeels(t: number)
	if next(peels) == nil then
		return
	end
	local height = Gadgets.peel.triggerHeight
	for ownerUserId, peel in peels do
		if t >= peel.expiresAt then
			removePeel(ownerUserId)
			continue
		end
		local radius = peel.def.triggerRadius or 0
		for _, session in Sessions.all() do
			if session.userId == ownerUserId then
				continue -- the owner never slips on their own peel
			end
			local root = Sessions.rootPart(session)
			if root == nil then
				continue
			end
			local offset = root.Position - peel.position
			if
				GadgetRules.stepsOnPeel(offset.X, offset.Z, offset.Y, radius, height)
				and PositionTracker.isTrusted(session, root.Position)
			then
				slip(peel, session, t)
				break
			end
		end
	end
end

-- Buying ------------------------------------------------------------------------------------------------------------

local function onBuy(player: Player, idArg: unknown)
	local session = Sessions.get(player)
	if session == nil then
		return
	end
	local id = Guard.keyOf(idArg, Gadgets.gadgets)
	local def = if id then Gadgets.gadgets[id] else nil
	local ok, reason = GadgetRules.canBuy({
		exists = def ~= nil,
		owned = id ~= nil and GadgetRules.owns(session.data.flags, id),
		cash = session.data.cash,
		price = if def then def.price else math.huge,
		covered = def ~= nil and GadgetRules.coveredByAutoCollect(def, session.passes.AutoCollect),
	})
	if not ok or id == nil or def == nil then
		local key = if reason then GadgetRules.messageKey(reason) else nil
		if key then
			Remotes.notify(player, UiTheme.text(key), "error")
		end
		return
	end
	if not EconomyService.trySpend(session, def.price, "Shop", `Gadget_{id}`) then
		Remotes.notify(player, Theme.text.notEnoughCash, "error")
		return
	end
	session.data.flags[GadgetRules.flag(id)] = true
	Replication.markDirty(session)
	Remotes.notify(player, Format.template(Theme.text.gadgetBought, { icon = def.icon, name = nameOf(def) }), "success")
	Remotes.fire(player, "Effect", { kind = "gadgetBought", gadget = id })
	Analytics.custom(session, "gadget_bought", def.price, { id })
end

-- Using -------------------------------------------------------------------------------------------------------------

local function refuse(session: Session, def: GadgetDef, id: string, reason: string?, t: number)
	local key = if reason then GadgetRules.messageKey(reason) else nil
	if key == nil then
		return
	end
	local remaining = GadgetRules.remaining(session.gadgets, id, t)
	Remotes.notify(session.player, UiTheme.text(key, { name = nameOf(def), time = Format.clock(remaining) }), "error")
end

local function useMagnet(session: Session)
	local total = 0
	for _, podium in PlotService.refs(session.plot).podiums do
		if podium.index > session.capacity then
			break
		end
		total += EconomyService.collectPad(session, podium)
	end
	if total > 0 then
		Remotes.notify(
			session.player,
			Format.template(Theme.text.magnetCollected, { amount = UiTheme.cash(total) }),
			"success"
		)
	end
end

local function onUse(player: Player, idArg: unknown)
	local session = Sessions.get(player)
	local id = Guard.keyOf(idArg, Gadgets.gadgets)
	if session == nil or id == nil then
		return
	end
	local def = Gadgets.gadgets[id]
	local t = now()
	local root = Sessions.rootPart(session)
	local ok, reason = GadgetRules.canUse({
		owned = GadgetRules.owns(session.data.flags, id),
		inTutorial = session.tutorial ~= nil,
		alive = root ~= nil,
		now = t,
		readyAt = session.gadgets.readyAt[id],
		covered = GadgetRules.coveredByAutoCollect(def, session.passes.AutoCollect), -- a magnet: "AUTO"
	})
	-- The gadget's own checks, on the server's view of the player (no client position is ever trusted).
	if ok and root then
		if def.kind == "peel" then
			local plot = session.plot
			ok, reason = GadgetRules.canPlacePeel({
				x = root.Position.X,
				z = root.Position.Z,
				rect = if plot ~= 0 then PlotService.rect(plot) else nil,
				heightAboveFloor = if plot ~= 0 then root.Position.Y - PlotService.refs(plot).floorY else 0,
				wallHeight = Gameplay.map.wallHeight,
				trusted = PositionTracker.isTrusted(session, root.Position),
			})
		elseif def.kind == "magnet" then
			if session.plot == 0 or EconomyService.collectable(session) < 1 then
				ok, reason = false, "empty"
			end
		end
	end
	if not ok or root == nil then
		refuse(session, def, id, reason, t)
		return
	end

	-- the cooldown starts here (shorter while Gadget Frenzy runs)
	GadgetRules.use(session.gadgets, id, def, t, Gadgets, ModifierService.effects().gadgetCooldown)
	if def.kind == "speed" then
		applySpeed(session)
		player:SetAttribute("GadgetSpeedUntil", session.gadgets.speedUntil)
	elseif def.kind == "shield" then
		player:SetAttribute("ShieldUntil", session.gadgets.shieldUntil)
		addBubble(session, def, session.gadgets.shieldUntil)
	elseif def.kind == "peel" then
		placePeel(session, id, def, root.Position, t)
	elseif def.kind == "magnet" then
		useMagnet(session)
	end
	Replication.markDirty(session)
	Remotes.fire(player, "Effect", { kind = "gadget", gadget = id, position = root.Position })
	Analytics.custom(session, "gadget_used", nil, { id })
end

-- Studio (DevCommands /gadgets): every gadget owned (`own`) or none, and all of them recharged.
function GadgetService.devSet(session: Session, own: boolean)
	for _, id in Gadgets.order do
		if own then
			session.data.flags[GadgetRules.flag(id)] = true
		else
			session.data.flags[GadgetRules.flag(id)] = nil
		end
	end
	table.clear(session.gadgets.readyAt)
	table.clear(session.gadgets.usedAt)
	Replication.markDirty(session)
end

-- The peels lying around right now, by owner UserId (tests).
function GadgetService.peelModels(): { [number]: Model }
	local models: { [number]: Model } = {}
	for ownerUserId, peel in peels do
		models[ownerUserId] = peel.model
	end
	return models
end

-- A player is leaving: their peel goes with them.
function GadgetService.onLeaving(session: Session)
	removePeel(session.userId)
	removeBubble(session)
	watching[session] = nil
end

-- The one-time hint that gadgets exist, when the first one becomes affordable (GadgetRules.affordableTip).
local function stepTips()
	for _, session in Sessions.all() do
		if not session.ready then
			continue
		end
		local flags = session.data.flags
		local id = GadgetRules.affordableTip(
			Gadgets,
			flags,
			session.data.cash,
			TutorialService.quiet(session),
			session.passes.AutoCollect
		)
		local def = if id then Gadgets.gadgets[id] else nil
		if def then
			flags[GadgetRules.TIP_FLAG] = true
			Remotes.notify(
				session.player,
				Format.template(Theme.text.gadgetTip, { icon = def.icon, name = nameOf(def) }),
				"info"
			)
		end
	end
end

function GadgetService.start()
	for _, problem in
		GadgetRules.validate(
			Gadgets,
			(Theme.text :: any) :: { [string]: string },
			ModifierRules.maxWalkSpeed(Modifiers)
		)
	do
		warn(`[Gadgets] config problem: {problem}`)
	end
	folder = Instance.new("Folder")
	folder.Name = "Gadgets"
	folder.Parent = workspace
	-- Gadget Frenzy starting: everything still recharging catches up at once (GadgetRules.rechargeChanged).
	local recharge = ModifierService.effects().gadgetCooldown
	ModifierService.onChanged(function()
		local before, after = recharge, ModifierService.effects().gadgetCooldown
		recharge = after
		local t = now()
		for _, session in Sessions.all() do
			if GadgetRules.rechargeChanged(session.gadgets, Gadgets, t, before, after) then
				Replication.markDirty(session)
			end
		end
	end)
	Remotes.onIntent("BuyGadget", onBuy)
	Remotes.onIntent("UseGadget", onUse)
	task.spawn(function()
		while true do
			task.wait(1)
			local ok, err = pcall(stepTips :: () -> ...any)
			if not ok then
				warn(`[Gadgets] tips: {err}`)
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(Gadgets.peel.checkSeconds)
			local t = now()
			local ok, err = pcall(stepPeels :: (number) -> ...any, t)
			if not ok then
				warn(`[Gadgets] {err}`)
			end
			ok, err = pcall(stepSpeeds :: (number) -> ...any, t)
			if not ok then
				warn(`[Gadgets] {err}`)
			end
			ok, err = pcall(stepBubbles :: (number) -> ...any, t)
			if not ok then
				warn(`[Gadgets] {err}`)
			end
		end
	end)
end

return GadgetService
