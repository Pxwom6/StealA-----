--!strict
--[[
	Stealing and defending.

	Grab:     StealBegin(plot, podium) starts a server-side hold timer; StealConfirm(plot, podium) asks
	          Logic/StealRules.canGrab (ownership, lock, new-player shield, range, hold time, space at home...).
	Carry:    the creature rides above the thief's head with a THIEF! marker everyone can see; the thief is slowed.
	          Ownership does NOT change yet — the creature is "in transit" and still in the victim's save.
	Deliver:  when the thief's character is inside their own plot the creature moves to their save (one atomic,
	          non-yielding transfer) and both profiles are asked to save.
	Fail:     tagged by anyone, timeout, death, leaving, the victim locking while the thief is still inside, or an
	          implausible movement speed (speed exploits) → the creature runs home.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Gameplay = require(ReplicatedStorage.Shared.Config.Gameplay)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local GameData = require(ReplicatedStorage.Shared.GameData)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local CreatureVisuals = require(ReplicatedStorage.Shared.CreatureVisuals)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local Guard = require(ReplicatedStorage.Shared.Logic.Guard)
local Inventory = require(ReplicatedStorage.Shared.Logic.Inventory)
local LockRules = require(ReplicatedStorage.Shared.Logic.LockRules)
local StealRules = require(ReplicatedStorage.Shared.Logic.StealRules)
local Analytics = require(script.Parent.Analytics)
local Announcer = require(script.Parent.Announcer)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local LockService = require(script.Parent.LockService)
local PlotService = require(script.Parent.PlotService)
local PositionTracker = require(script.Parent.PositionTracker)
local Remotes = require(script.Parent.Remotes)
local Replication = require(script.Parent.Replication)
local Sessions = require(script.Parent.Sessions)

type Session = Sessions.Session
type Carry = Sessions.Carry

export type CancelReason =
	"tagged"
	| "timeout"
	| "died"
	| "left"
	| "ownerLeft"
	| "locked"
	| "speed"
	| "flying"
	| "full"
	| "rebirth"
	| "error"

local StealService = {}

local CFG = Gameplay.steal

local CARRY_LIMITS: StealRules.CarryLimits = {
	maxSpeed = Gameplay.walkSpeed * CFG.carrySpeedMultiplier,
	tolerance = CFG.speedCheckTolerance,
	budgetSeconds = CFG.speedBudgetSeconds,
	leeway = CFG.speedCheckLeeway,
}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function setWalkSpeed(session: Session, speed: number)
	local humanoid = Sessions.humanoid(session)
	if humanoid then
		humanoid.WalkSpeed = speed
	end
end

local function attachCarryVisuals(session: Session, carry: Carry)
	local character = session.player.Character
	local head = character and character:FindFirstChild("Head")
	if character == nil or head == nil or not head:IsA("BasePart") then
		return
	end
	local def = GameData.catalog.creatures[carry.creatureId]
	local rarity = GameData.catalog.rarities[def.rarity]
	local model = CreatureVisuals.build(def, rarity, { anchored = false })
	model:PivotTo(head.CFrame * CFrame.new(0, head.Size.Y / 2 + 0.4, 0))
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = head
	weld.Part1 = assert(model.PrimaryPart, "creature models always have a Root")
	weld.Parent = model
	model.Name = "CarriedCreature"
	model.Parent = character
	carry.model = model

	local marker = Instance.new("BillboardGui")
	marker.Name = "ThiefMarker"
	marker.Size = UDim2.fromOffset(150, 44)
	marker.StudsOffsetWorldSpace = Vector3.new(0, CreatureVisuals.height(model) + 3.5, 0)
	marker.AlwaysOnTop = true
	marker.MaxDistance = 250
	marker.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.FontFace = UiTheme.displayFont
	label.TextScaled = true
	label.Text = Theme.text.carryMarker
	label.TextColor3 = UiTheme.palette("danger")
	label.Parent = marker
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = UiTheme.palette("stroke")
	stroke.Parent = label
	marker.Parent = head
	carry.marker = marker
end

local function clearCarry(session: Session)
	local carry = session.carry
	if carry == nil then
		return
	end
	session.carry = nil
	if carry.model then
		carry.model:Destroy()
	end
	if carry.marker then
		carry.marker:Destroy()
	end
	session.player:SetAttribute("Carrying", nil)
	setWalkSpeed(session, Gameplay.walkSpeed)
	Replication.markDirty(session)
end

-- Ends a carry without a transfer: the creature runs back to its podium.
function StealService.cancel(thief: Session, reason: CancelReason, taggerName: string?)
	local carry = thief.carry
	if carry == nil then
		return
	end
	PlotService.setBusy(carry.plot, carry.podium, false) -- first, so nothing below can leave the podium stuck
	clearCarry(thief)
	local victim = Sessions.getByUserId(carry.victimUserId)
	if victim then
		EconomyService.refresh(victim)
	end

	local def = GameData.catalog.creatures[carry.creatureId]
	local creatureName = def.displayName
	if reason == "tagged" then
		thief.stealCooldownUntil = now() + CFG.thiefCooldownAfterTagSeconds
		Remotes.notify(thief.player, Format.template(Theme.text.gotTagged, { creature = creatureName }), "error")
		Remotes.fire(thief.player, "Effect", { kind = "tagged" })
	elseif reason == "timeout" or reason == "speed" or reason == "flying" then
		Remotes.notify(
			thief.player,
			Format.template(Theme.text.stealFailedTimeout, { creature = creatureName }),
			"error"
		)
	elseif reason == "full" then
		Remotes.notify(thief.player, Theme.text.baseFull, "error")
	elseif reason == "locked" or reason == "rebirth" then
		Remotes.notify(thief.player, Format.template(Theme.text.creatureReturned, { creature = creatureName }), "error")
	elseif reason == "ownerLeft" then
		Remotes.notify(
			thief.player,
			Format.template(Theme.text.ownerLeftDuringSteal, { creature = creatureName }),
			"info"
		)
	end
	if victim and reason ~= "ownerLeft" and reason ~= "rebirth" then
		local text = Format.template(Theme.text.creatureReturned, { creature = creatureName })
		if taggerName then
			text = `{taggerName}: {text}`
		end
		Remotes.notify(victim.player, text, "success")
	end
	if reason == "speed" then
		warn(`[StealService] dropped carry for {thief.player.Name}: implausible movement speed`)
	end
end

local function deliver(thief: Session)
	local carry = thief.carry
	if carry == nil then
		return
	end
	local victim = Sessions.getByUserId(carry.victimUserId)
	if victim == nil then
		StealService.cancel(thief, "ownerLeft")
		return
	end
	-- A transfer changes two saves. If either session has ended (e.g. the server is shutting down and their final
	-- save may already be written), moving the creature could duplicate or lose it: send it home instead.
	if not thief.profile:IsActive() or not victim.profile:IsActive() then
		StealService.cancel(thief, "left")
		return
	end
	local podium = EconomyService.freePodium(thief)
	if podium == nil then
		StealService.cancel(thief, "full")
		return
	end
	-- Atomic (no yields): remove from victim, add to thief.
	local moved = Inventory.transfer(victim.data, thief.data, carry.uid, podium, os.time())
	PlotService.setBusy(carry.plot, carry.podium, false)
	clearCarry(thief)
	if moved == nil then
		EconomyService.refresh(victim)
		return
	end
	thief.data.stats.steals += 1
	victim.data.stats.timesStolenFrom += 1
	EconomyService.refresh(victim)
	EconomyService.refresh(thief)
	DataService.saveSoon(thief.profile)
	DataService.saveSoon(victim.profile)

	local def = GameData.catalog.creatures[moved.id]
	local rarity = GameData.catalog.rarities[def.rarity]
	Remotes.notify(thief.player, Format.template(Theme.text.stealSuccess, { creature = def.displayName }), "success")
	Remotes.notify(
		victim.player,
		Format.template(Theme.text.stolenFromYou, { thief = thief.player.DisplayName, creature = def.displayName }),
		"error"
	)
	local podiumRefs = PlotService.podium(thief.plot, podium)
	if podiumRefs then
		Remotes.fire(thief.player, "Effect", { kind = "stolen", position = podiumRefs.standCFrame.Position })
	end
	if Analytics.milestone(thief, "FirstSteal") then
		Analytics.custom(thief, "first_steal_rarity", rarity.order)
	end
	Analytics.custom(thief, "steal", rarity.order, { creature = def.id })
	if rarity.announceOnSteal then
		Announcer.broadcast({
			text = Format.template(Theme.text.announceSteal, {
				thief = thief.player.DisplayName,
				owner = victim.player.DisplayName,
				rarity = rarity.displayName,
				creature = def.displayName,
			}),
			rarity = rarity.id,
			kind = "steal",
		})
	end
end

local function onStealBegin(player: Player, plotArg: unknown, podiumArg: unknown)
	local plot = Guard.integer(plotArg, 1, Gameplay.map.plotCount)
	local podium = Guard.integer(podiumArg, 1, Gameplay.map.maxPodiums)
	local session = Sessions.get(player)
	if plot == nil or podium == nil or session == nil then
		return
	end
	session.hold = nil
	local root = Sessions.rootPart(session)
	local podiumRefs = PlotService.podium(plot, podium)
	if root == nil or podiumRefs == nil then
		return
	end
	-- The server-timed hold only starts at the podium (no starting it from across the map or right after a teleport).
	-- If it doesn't, the reason is kept so the grab can explain it (e.g. a connection hiccup).
	local ok, refusal = StealRules.canBeginHold({
		distance = (root.Position - podiumRefs.base.Position).Magnitude,
		grabRange = CFG.grabRange,
		rangeSlack = CFG.holdRangeSlack,
		thiefInsideBase = PlotService.isInside(plot, root.Position),
		thiefTrusted = PositionTracker.isTrustedForSteal(session, root.Position),
	})
	session.hold = { plot = plot, podium = podium, startedAt = if ok then now() else nil, refusal = refusal }
end

local function onStealConfirm(player: Player, plotArg: unknown, podiumArg: unknown)
	local plot = Guard.integer(plotArg, 1, Gameplay.map.plotCount)
	local podium = Guard.integer(podiumArg, 1, Gameplay.map.maxPodiums)
	local thief = Sessions.get(player)
	if plot == nil or podium == nil or thief == nil or thief.plot == 0 then
		return
	end
	local hold = thief.hold
	thief.hold = nil
	local sameHold = if hold and hold.plot == plot and hold.podium == podium then hold else nil

	local victim = Sessions.getByUserId(PlotService.ownerOf(plot))
	local root = Sessions.rootPart(thief)
	local podiumRefs = PlotService.podium(plot, podium)
	if victim == nil or root == nil or podiumRefs == nil then
		return
	end
	if not thief.profile:IsActive() or not victim.profile:IsActive() then
		return -- a session has ended (shutting down): no new steals
	end
	local t = now()
	local record = Inventory.findByPodium(victim.data.creatures, podium)
	local ok, reason = StealRules.canGrab({
		now = t,
		thiefUserId = thief.userId,
		ownerUserId = victim.userId,
		thiefCarrying = thief.carry ~= nil,
		thiefCooldownUntil = thief.stealCooldownUntil,
		baseLocked = LockRules.isLocked(victim.lock, t),
		ownerGraceUntil = victim.graceUntil,
		creaturePresent = record ~= nil,
		creatureBusy = PlotService.isBusy(plot, podium),
		distance = (root.Position - podiumRefs.base.Position).Magnitude,
		grabRange = CFG.grabRange,
		thiefInsideBase = PlotService.isInside(plot, root.Position),
		thiefHeightAboveFloor = root.Position.Y - PlotService.refs(plot).floorY,
		wallHeight = Gameplay.map.wallHeight,
		grabJumpAllowance = CFG.grabJumpAllowance,
		thiefHasFreePodium = EconomyService.freePodium(thief) ~= nil,
		-- teleported in to confirm, or a lag spike just now: refused with a "connection hiccup" message
		thiefTrusted = PositionTracker.isTrustedForSteal(thief, root.Position),
		holdStartedAt = if sameHold then sameHold.startedAt else nil,
		holdRefusal = if sameHold then sameHold.refusal else nil,
		holdSeconds = CFG.holdSeconds,
		holdTolerance = CFG.holdTolerance,
	})
	if not ok or record == nil then
		local key = StealRules.messageKey(reason or "")
		if key then
			Remotes.notify(player, UiTheme.text(key, { time = Format.clock(thief.stealCooldownUntil - t) }), "error")
		end
		return
	end

	-- The victim keeps the cash that was sitting on the podium.
	EconomyService.collect(victim, podium)

	-- The carry exists before the podium is marked busy, and everything after that runs protected: if any of it
	-- throws, cancelling the carry frees the podium again (a busy podium with no carry would hide the creature
	-- forever).
	local carry: Carry = {
		victimUserId = victim.userId,
		plot = plot,
		podium = podium,
		uid = record.uid,
		creatureId = record.id,
		startedAt = t,
		track = StealRules.newCarryTrack(root.Position.X, root.Position.Y, root.Position.Z, os.clock(), CARRY_LIMITS),
		model = nil,
		marker = nil,
	}
	thief.carry = carry
	PlotService.setBusy(plot, podium, true)
	local started, err = pcall(function()
		EconomyService.refresh(victim)
		LockService.endGrace(thief) -- stealing forfeits your own new-player protection
		attachCarryVisuals(thief, carry)
		player:SetAttribute("Carrying", record.id)
		setWalkSpeed(thief, Gameplay.walkSpeed * CFG.carrySpeedMultiplier)
		Replication.markDirty(thief)

		local def = GameData.catalog.creatures[record.id]
		Remotes.notify(player, Theme.text.stealStarted, "warning")
		Remotes.fire(victim.player, "StealAlert", {
			thiefUserId = thief.userId,
			thiefName = player.DisplayName,
			creatureId = record.id,
			text = Format.template(Theme.text.beingStolen, { thief = player.DisplayName, creature = def.displayName }),
		})
		Analytics.custom(thief, "steal_started", GameData.catalog.rarities[def.rarity].order)
	end)
	if not started then
		warn(`[StealService] starting a carry failed, sending the creature home: {err}`)
		StealService.cancel(thief, "error")
	end
end

local function onTag(player: Player, targetArg: unknown)
	local targetId = Guard.integer(targetArg, 1, 2 ^ 53)
	local tagger = Sessions.get(player)
	if targetId == nil or tagger == nil then
		return
	end
	local thief = Sessions.getByUserId(targetId)
	if thief == nil then
		return
	end
	local taggerRoot = Sessions.rootPart(tagger)
	local thiefRoot = Sessions.rootPart(thief)
	if taggerRoot == nil or thiefRoot == nil then
		return
	end
	local t = now()
	local ok = StealRules.canTag({
		now = t,
		taggerUserId = tagger.userId,
		thiefUserId = thief.userId,
		thiefCarrying = thief.carry ~= nil,
		horizontalDistance = Vector3.new(
			thiefRoot.Position.X - taggerRoot.Position.X,
			0,
			thiefRoot.Position.Z - taggerRoot.Position.Z
		).Magnitude,
		verticalDistance = thiefRoot.Position.Y - taggerRoot.Position.Y,
		tagRange = CFG.tagRange,
		tagVerticalAllowance = CFG.tagVerticalAllowance,
		taggerCooldownUntil = tagger.tagCooldownUntil,
		taggerTrusted = PositionTracker.isTrusted(
			tagger,
			taggerRoot.Position,
			if thief.carry then thief.carry.startedAt else t
		),
	})
	if not ok then
		return
	end
	tagger.tagCooldownUntil = t + CFG.tagCooldownSeconds
	local carry = thief.carry :: Carry
	local def = GameData.catalog.creatures[carry.creatureId]
	StealService.cancel(thief, "tagged", player.DisplayName)
	Remotes.notify(
		player,
		Format.template(Theme.text.taggedThief, { thief = thief.player.DisplayName, creature = def.displayName }),
		"success"
	)
	Remotes.fire(player, "Effect", { kind = "tag", position = thiefRoot.Position })
	Analytics.custom(tagger, "tag")
end

-- One check of one carry: owner still here, thief alive, not timed out, height, movement budget, then delivery.
-- `allowDeliver` is false when LockService runs it just before ejecting the thief from someone else's base.
local function checkCarry(thief: Session, allowDeliver: boolean)
	local carry = thief.carry
	if carry == nil then
		return
	end
	if Sessions.getByUserId(carry.victimUserId) == nil then
		StealService.cancel(thief, "ownerLeft")
		return
	end
	local root = Sessions.rootPart(thief)
	if root == nil then
		StealService.cancel(thief, "died")
		return
	end
	if StealRules.isCarryExpired(carry.startedAt, now(), CFG.carryTimeoutSeconds) then
		StealService.cancel(thief, "timeout")
		return
	end
	-- The thief may not climb/fly above maxCarryHeight (or sink under the map). Movement is checked on EVERY tick (so
	-- teleporting home right after a grab is caught before delivery) against a distance budget: it refills with time
	-- and pays for distance moved (climbing once, not every jump; falling is free), so lag spikes are forgiven but
	-- speed hacks are not.
	local position = root.Position
	local heightAboveGround = position.Y - PlotService.world().groundY
	if not StealRules.isCarryHeightAllowed(heightAboveGround, CFG.minCarryHeight, CFG.maxCarryHeight) then
		StealService.cancel(thief, "flying")
		return
	end
	if not StealRules.stepCarryTrack(carry.track, position.X, position.Y, position.Z, os.clock(), CARRY_LIMITS) then
		StealService.cancel(thief, "speed")
		return
	end
	if allowDeliver and thief.plot ~= 0 then
		local refs = PlotService.refs(thief.plot)
		local inside = PlotService.isInside(thief.plot, position)
		if StealRules.canDeliver(inside, position.Y - refs.floorY, Gameplay.map.wallHeight) then
			deliver(thief)
		end
	end
end

local function checkCarries()
	for _, thief in Sessions.all() do
		-- One failing carry must not stop the loop (every later carry would hang with its podium busy).
		local ok, err = pcall(checkCarry :: (Session, boolean) -> ...any, thief, true)
		if not ok then
			warn(`[StealService] carry check failed for {thief.player.Name}, sending the creature home: {err}`)
			pcall(function()
				StealService.cancel(thief, "error")
			end)
		end
	end
end

-- Cancels every carry involving `session` (as thief or as victim). Used on leave and rebirth.
function StealService.releaseAll(session: Session, reason: CancelReason)
	if session.carry then
		StealService.cancel(session, if reason == "rebirth" then "rebirth" else "left")
	end
	for _, other in Sessions.all() do
		if other.carry and other.carry.victimUserId == session.userId then
			StealService.cancel(other, if reason == "rebirth" then "rebirth" else "ownerLeft")
		end
	end
end

-- Called by LockService before ejecting: a thief still inside the base they are robbing drops the creature.
function StealService.onBaseLocked(owner: Session)
	for _, other in Sessions.all() do
		local carry = other.carry
		if carry and carry.victimUserId == owner.userId then
			local root = Sessions.rootPart(other)
			if root and PlotService.isInside(owner.plot, root.Position) then
				StealService.cancel(other, "locked")
			end
		end
	end
end

function StealService.start()
	Remotes.onIntent("StealBegin", onStealBegin)
	Remotes.onIntent("StealConfirm", onStealConfirm)
	Remotes.onIntent("TagThief", onTag)
	LockService.setLockListener(StealService.onBaseLocked)
	-- Before a carrying visitor is moved out of a locked base, judge how they got in (a teleport is still caught).
	LockService.setBeforeEject(function(visitor: Session)
		local ok, err = pcall(checkCarry :: (Session, boolean) -> ...any, visitor, false)
		if not ok then
			warn(`[StealService] carry check before eject failed for {visitor.player.Name}: {err}`)
			pcall(function()
				StealService.cancel(visitor, "error")
			end)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(CFG.deliveryCheckInterval)
			checkCarries()
		end
	end)
end

return StealService
