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

local StealService = {}

local CFG = Gameplay.steal
local SPEED_WINDOW = 1

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
	clearCarry(thief)
	PlotService.setBusy(carry.plot, carry.podium, false)
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
	local podium = EconomyService.freePodium(thief)
	if podium == nil then
		StealService.cancel(thief, "full")
		return
	end
	-- Atomic (no yields): remove from victim, add to thief.
	local moved = Inventory.transfer(victim.data, thief.data, carry.uid, podium, os.time())
	clearCarry(thief)
	PlotService.setBusy(carry.plot, carry.podium, false)
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
	session.hold = { plot = plot, podium = podium, startedAt = now() }
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
	local holdStartedAt = if hold and hold.plot == plot and hold.podium == podium then hold.startedAt else nil

	local victim = Sessions.getByUserId(PlotService.ownerOf(plot))
	local root = Sessions.rootPart(thief)
	local podiumRefs = PlotService.podium(plot, podium)
	if victim == nil or root == nil or podiumRefs == nil then
		return
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
		thiefHasFreePodium = EconomyService.freePodium(thief) ~= nil,
		holdStartedAt = holdStartedAt,
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
	PlotService.setBusy(plot, podium, true)
	EconomyService.refresh(victim)

	local carry: Carry = {
		victimUserId = victim.userId,
		plot = plot,
		podium = podium,
		uid = record.uid,
		creatureId = record.id,
		startedAt = t,
		lastPosition = root.Position,
		lastCheckAt = os.clock(),
		model = nil,
		marker = nil,
	}
	thief.carry = carry
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

local function checkCarries()
	local t = now()
	local clockNow = os.clock()
	local maxSpeed = Gameplay.walkSpeed * CFG.carrySpeedMultiplier
	for _, thief in Sessions.all() do
		local carry = thief.carry
		if carry == nil then
			continue
		end
		if Sessions.getByUserId(carry.victimUserId) == nil then
			StealService.cancel(thief, "ownerLeft")
			continue
		end
		local root = Sessions.rootPart(thief)
		if root == nil then
			StealService.cancel(thief, "died")
			continue
		end
		if StealRules.isCarryExpired(carry.startedAt, t, CFG.carryTimeoutSeconds) then
			StealService.cancel(thief, "timeout")
			continue
		end
		-- Movement is checked on EVERY tick (so teleporting home right after a grab is caught before delivery),
		-- measured from the start of the current window; the window only restarts after SPEED_WINDOW seconds,
		-- so the per-window leeway can't be farmed by frequent checks.
		-- Upward movement counts too (falling doesn't), and the thief may not climb/fly above maxCarryHeight (or
		-- sink under the map).
		local heightAboveGround = root.Position.Y - PlotService.world().groundY
		if not StealRules.isCarryHeightAllowed(heightAboveGround, CFG.minCarryHeight, CFG.maxCarryHeight) then
			StealService.cancel(thief, "flying")
			continue
		end
		local dt = clockNow - carry.lastCheckAt
		local delta = root.Position - carry.lastPosition
		local moved = StealRules.movementDistance(delta.X, delta.Y, delta.Z)
		local tolerance, leeway = CFG.speedCheckTolerance, CFG.speedCheckLeeway
		if not StealRules.isMovementPlausible(moved, dt, maxSpeed, tolerance, leeway) then
			StealService.cancel(thief, "speed")
			continue
		end
		if dt >= SPEED_WINDOW then
			carry.lastPosition = root.Position
			carry.lastCheckAt = clockNow
		end
		if thief.plot ~= 0 then
			local refs = PlotService.refs(thief.plot)
			local inside = PlotService.isInside(thief.plot, root.Position)
			if StealRules.canDeliver(inside, root.Position.Y - refs.floorY, Gameplay.map.wallHeight) then
				deliver(thief)
			end
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
	task.spawn(function()
		while true do
			task.wait(CFG.deliveryCheckInterval)
			checkCarries()
		end
	end)
end

return StealService
