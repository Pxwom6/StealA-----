--!strict
--[[
	Drops on the walkways while a drop modifier runs (Config/Modifiers `drops`; what they hold: Config/Drops).

	  * Supply crates parachute down onto a random spot on one of the walkways (announced), land after fallSeconds
	    and wait there for lifetimeSeconds. The first player to hold one open gets a Snackling rolled with extra luck
	    and mutation chance in their base (its sell value when the base is full) plus cash, and everyone hears what
	    it was. Opening is two intents, like a steal: CrateBegin when the hold starts and CrateOpen when it completes.
	    The server checks that the crate has landed and is still closed, that the player is within reach both times at
	    a position trusted as for a steal (no teleport in the last 10 s), and that the hold lasted long enough
	    (DropRules.holdLongEnough).
	  * Coins: a scatter over both walkways every so often. The server itself picks a coin up for whoever walks
	    through it (a quick distance check against trusted positions, not client touch events), paying a few seconds
	    of that player's income.
	  * Runaways (Great Escape): a Snackling rolled with extra luck appears on a walkway, as far from everyone as it
	    can (announced, rarity and all), and runs along it in short legs, each planned away from the players near it
	    (DropRules.runawayTarget). The leg is published as one attribute and the client draws the Snackling on it, so
	    nothing is sent while it runs; the server checks catches against the same position (DropRules.legPosition) and
	    player positions trusted as for a steal, like crates. The first player to reach it gets it (its sell value with a full base);
	    uncaught, it gets away after its lifetime.

	The schedule follows server time from the moment the modifier starts (DropRules.times). Crates and coins live in
	workspace.Drops, tagged for the client (DropController adds the prompt, the marker, the spin and the effects).
	They go when their own lifetime ends, not when the modifier does, so a crate someone is opening never vanishes
	under their hands.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local CreatureVisuals = require(ReplicatedStorage.Shared.CreatureVisuals)
local Drops = require(ReplicatedStorage.Shared.Config.Drops)
local Gameplay = require(ReplicatedStorage.Shared.Config.Gameplay)
local Modifiers = require(ReplicatedStorage.Shared.Config.Modifiers)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local GameData = require(ReplicatedStorage.Shared.GameData)
local Types = require(ReplicatedStorage.Shared.Types)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local DropRules = require(ReplicatedStorage.Shared.Logic.DropRules)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local Guard = require(ReplicatedStorage.Shared.Logic.Guard)
local Announcer = require(script.Parent.Announcer)
local EconomyService = require(script.Parent.EconomyService)
local GameEvents = require(script.Parent.GameEvents)
local ModifierService = require(script.Parent.ModifierService)
local PositionTracker = require(script.Parent.PositionTracker)
local PrizeService = require(script.Parent.PrizeService)
local Remotes = require(script.Parent.Remotes)
local Sessions = require(script.Parent.Sessions)

type Session = Sessions.Session

local DropService = {}

DropService.CRATE_TAG = "SupplyCrate"
DropService.COIN_TAG = "DropCoin"
DropService.RUNAWAY_TAG = "Runaway"

local CRATE_SIZE = 4
local CRATE_COLOR = "#B07443"
local BAND_COLOR = "#FFD23F"
local CANOPY_COLOR = "#FF5C5C"
local COIN_COLOR = "#FFD23F"
local STEP_SECONDS = 0.25
local PICKUP_SECONDS = 0.1
-- The server allows this much more than the client prompt's reach (a player stepping back as the hold completes).
local REACH_SLACK = 2
-- A new runaway stands still this long before it runs, so everyone sees where it popped out.
local RUNAWAY_APPEAR_SECONDS = 1.2

type Crate = {
	id: number,
	model: Model,
	box: BasePart,
	canopy: BasePart?,
	landsAt: number,
	expiresAt: number,
	landed: boolean,
	opened: boolean,
	holds: { [Player]: number }, -- when each player's hold began
}

type Coin = { part: BasePart, expiresAt: number }

type Runaway = {
	id: number,
	model: Model,
	def: Types.CreatureDef,
	variant: string?,
	leg: DropRules.Leg,
	expiresAt: number,
}

local folder: Folder
local walkwayY = 0.2
local crates: { [number]: Crate } = {}
local coins: { Coin } = {}
local runaways: { [number]: Runaway } = {}
local nextRunawayId = 1
local nextCrateId = 1
local random = Random.new()
local runningId: string? = nil
local pending: { number } = {} -- server times of the running modifier's drops still to come

local function now(): number
	return workspace:GetServerTimeNow()
end

local function nextRandom(): number
	return random:NextNumber()
end

local function newPart(props: { [string]: any }): BasePart
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(part :: any)[key] = value
	end
	return part
end

-- The welded extras of a crate follow its box down as the box tweens.
local function weld(part: BasePart, to: BasePart)
	part.Anchored = false
	part.Massless = true
	local constraint = Instance.new("WeldConstraint")
	constraint.Part0 = to
	constraint.Part1 = part
	constraint.Parent = part
end

-- Crates -------------------------------------------------------------------------------------------------------------

local function spawnCrate(t: number)
	local x, z = DropRules.position(Drops.area, nextRandom)
	local id = nextCrateId
	nextCrateId += 1
	local landing = CFrame.new(x, walkwayY + CRATE_SIZE / 2, z) * CFrame.Angles(0, nextRandom() * math.pi * 2, 0)
	local model = Instance.new("Model")
	model.Name = `SupplyCrate{id}`
	local box = newPart({
		Name = "Crate",
		Size = Vector3.one * CRATE_SIZE,
		CFrame = landing + Vector3.new(0, Drops.crate.dropHeight, 0),
		Color = UiTheme.color(CRATE_COLOR),
		Material = Enum.Material.WoodPlanks,
		Parent = model,
	})
	model.PrimaryPart = box
	local band = newPart({
		Name = "Band",
		Size = Vector3.new(CRATE_SIZE + 0.1, 0.8, CRATE_SIZE + 0.1),
		CFrame = box.CFrame,
		Color = UiTheme.color(BAND_COLOR),
		Material = Enum.Material.Metal,
		Parent = model,
	})
	weld(band, box)
	local canopy = newPart({
		Name = "Parachute",
		Size = Vector3.new(10, 4.5, 10),
		CFrame = box.CFrame * CFrame.new(0, 8, 0),
		Color = UiTheme.color(CANOPY_COLOR),
		Material = Enum.Material.Fabric,
		Parent = model,
	})
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = canopy
	weld(canopy, box)

	local landsAt = t + Drops.crate.fallSeconds
	model:SetAttribute("CrateId", id)
	model:SetAttribute("LandsAt", landsAt)
	model:SetAttribute("Landed", false)
	CollectionService:AddTag(model, DropService.CRATE_TAG)
	model.Parent = folder
	TweenService:Create(box, TweenInfo.new(Drops.crate.fallSeconds, Enum.EasingStyle.Linear), { CFrame = landing })
		:Play()
	crates[id] = {
		id = id,
		model = model,
		box = box,
		canopy = canopy,
		landsAt = landsAt,
		expiresAt = landsAt + Drops.crate.lifetimeSeconds,
		landed = false,
		opened = false,
		holds = {},
	}
	Announcer.broadcast({ text = Theme.text.crateFalling, color = CRATE_COLOR, kind = "drop" })
end

local function land(crate: Crate)
	crate.landed = true
	local canopy = crate.canopy
	if canopy then
		canopy:Destroy()
		crate.canopy = nil
	end
	crate.model:SetAttribute("Landed", true)
end

local function removeCrate(crate: Crate)
	crates[crate.id] = nil
	crate.model:Destroy()
end

-- Whether `session` stands within reach of `crate`, at a position the server trusts as much as for a steal: a crate's
-- landing spot is known for the seconds it falls, so the 2 s a teleport costs elsewhere would let a teleporter win
-- it; a steal's 10 s does not (PositionTracker.isTrustedForSteal).
local function inReach(session: Session, crate: Crate): boolean
	local root = Sessions.rootPart(session)
	if root == nil then
		return false
	end
	local offset = root.Position - crate.box.Position
	local horizontal = Vector3.new(offset.X, 0, offset.Z).Magnitude
	return horizontal <= Drops.crate.openRange + REACH_SLACK
		and math.abs(offset.Y) <= 10
		and PositionTracker.isTrustedForSteal(session, root.Position)
end

local function crateFor(idArg: unknown): Crate?
	local id = Guard.integer(idArg, 1, 2 ^ 31)
	return if id then crates[id] else nil
end

-- What is inside: a Snackling rolled with the crate's extra luck and mutation chance, and some cash.
local function open(session: Session, crate: Crate)
	local def, variant = PrizeService.rollCreature(Drops.crate.luck, Drops.crate.mutationChance, nil)
	local cash = DropRules.amount(Drops.crate.cash, session.packIncome)
	local player = session.player
	if def then
		local name = GameData.displayName(def, variant)
		local rarity = GameData.catalog.rarities[def.rarity]
		-- A full base: the Snackling is sold for its usual refund instead.
		local given, refund = PrizeService.giveOrSell(session, def, variant, "SupplyCrate")
		if given then
			Remotes.notify(
				player,
				Format.template(Theme.text.crateReward, { creature = name, cash = UiTheme.cash(cash) }),
				"success"
			)
		else
			Remotes.notify(
				player,
				Format.template(Theme.text.crateRewardFull, { creature = name, cash = UiTheme.cash(cash + refund) }),
				"success"
			)
		end
		Announcer.broadcast({
			text = Format.template(
				Theme.text.crateOpened,
				{ player = player.DisplayName, rarity = rarity.displayName, creature = name }
			),
			rarity = def.rarity,
			kind = "drop",
		})
		Remotes.fire(player, "Effect", { kind = "crate", position = crate.box.Position, rarity = def.rarity })
	end
	EconomyService.addCash(session, cash, "Gameplay", "SupplyCrate")
	removeCrate(crate)
	GameEvents.emit(session, { kind = "milestone", milestone = "crate" }) -- achievements
end

local function onBegin(player: Player, idArg: unknown)
	local session = Sessions.get(player)
	local crate = crateFor(idArg)
	if session == nil or crate == nil or not crate.landed or crate.opened then
		return
	end
	if inReach(session, crate) then
		crate.holds[player] = now()
	end
end

local function onOpen(player: Player, idArg: unknown)
	local session = Sessions.get(player)
	local crate = crateFor(idArg)
	if session == nil then
		return
	end
	if crate == nil or crate.opened then
		Remotes.notify(player, Theme.text.crateTaken, "error")
		return
	end
	if not crate.landed or not inReach(session, crate) then
		return
	end
	if not DropRules.holdLongEnough(Drops, crate.holds[player], now()) then
		return
	end
	crate.opened = true
	open(session, crate)
end

-- Coins --------------------------------------------------------------------------------------------------------------

local function spawnCoins(t: number)
	local color = UiTheme.color(COIN_COLOR)
	for _ = 1, Drops.coins.perWave do
		local x, z = DropRules.position(Drops.area, nextRandom)
		local coin = newPart({
			Name = "Coin",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.35, 2.2, 2.2),
			-- A cylinder runs along X: this stands the coin on its edge, facing a random way.
			CFrame = CFrame.new(x, walkwayY + Drops.coins.height, z) * CFrame.Angles(0, nextRandom() * math.pi, 0),
			Color = color,
			Material = Enum.Material.Neon,
			CastShadow = false,
			Parent = folder,
		})
		CollectionService:AddTag(coin, DropService.COIN_TAG)
		table.insert(coins, { part = coin, expiresAt = t + Drops.coins.lifetimeSeconds })
	end
end

local function pickUp()
	if #coins == 0 then
		return
	end
	for _, player in Players:GetPlayers() do
		local session = Sessions.get(player)
		local root = if session then Sessions.rootPart(session) else nil
		if session == nil or root == nil then
			continue
		end
		local position = root.Position
		for index = #coins, 1, -1 do
			local coin = coins[index]
			local offset = position - coin.part.Position
			local horizontal = Vector3.new(offset.X, 0, offset.Z).Magnitude
			if
				DropRules.inPickupRange(Drops, horizontal, offset.Y) and PositionTracker.isTrusted(session, position)
			then
				table.remove(coins, index)
				local amount = DropRules.amount(Drops.coins.value, session.packIncome)
				EconomyService.addCash(session, amount, "Gameplay", "Coin")
				Remotes.fire(player, "Effect", { kind = "collect", amount = amount, position = coin.part.Position })
				coin.part:Destroy()
			end
		end
	end
end

-- Runaways -----------------------------------------------------------------------------------------------------------

-- Where every player stands (horizontally), for a runaway to keep away from.
local function playerPoints(): { DropRules.Point }
	local list: { DropRules.Point } = {}
	for _, player in Players:GetPlayers() do
		local session = Sessions.get(player)
		local root = if session then Sessions.rootPart(session) else nil
		if root then
			table.insert(list, { x = root.Position.X, z = root.Position.Z })
		end
	end
	return list
end

local function setLeg(runaway: Runaway, leg: DropRules.Leg)
	runaway.leg = leg
	runaway.model:SetAttribute("Leg", DropRules.encodeLeg(leg))
end

local function removeRunaway(runaway: Runaway)
	runaways[runaway.id] = nil
	runaway.model:Destroy()
end

-- A Snackling escapes: far from everyone, or right at `at` (the Studio command and the server test). nil when no
-- Snackling can roll.
local function spawnRunaway(t: number, at: Vector3?): Runaway?
	local cfg = Drops.runaway
	local def, variant = PrizeService.rollCreature(cfg.luck, cfg.mutationChance, nil)
	if def == nil then
		return nil
	end
	local x, z
	if at then
		x, z = at.X, at.Z
	else
		x, z = DropRules.runawayStart(Drops, playerPoints(), nextRandom)
	end
	local rarity = GameData.catalog.rarities[def.rarity]
	local model =
		CreatureVisuals.build(def, rarity, { anchored = true, mutation = GameData.mutation(variant), idle = false })
	local id = nextRunawayId
	nextRunawayId += 1
	model.Name = `Runaway{id}`
	model:PivotTo(CFrame.new(x, walkwayY, z) * CFrame.Angles(0, nextRandom() * math.pi * 2, 0))
	model:SetAttribute("RunawayId", id)
	model:SetAttribute("Rarity", def.rarity)
	local runaway: Runaway = {
		id = id,
		model = model,
		def = def,
		variant = variant,
		leg = { fromX = x, fromZ = z, toX = x, toZ = z, startsAt = t, endsAt = t + RUNAWAY_APPEAR_SECONDS },
		expiresAt = t + cfg.lifetimeSeconds,
	}
	setLeg(runaway, runaway.leg)
	CollectionService:AddTag(model, DropService.RUNAWAY_TAG)
	model.Parent = folder
	runaways[id] = runaway
	Announcer.broadcast({
		text = Format.template(
			Theme.text.runawayEscaped,
			{ rarity = rarity.displayName, creature = GameData.displayName(def, variant) }
		),
		rarity = def.rarity,
		kind = "drop",
	})
	return runaway
end

-- Where a runaway is now (on the walkway, at its feet).
local function runawayPosition(runaway: Runaway, t: number): Vector3
	local x, z = DropRules.legPosition(runaway.leg, t)
	return Vector3.new(x, walkwayY, z)
end

local function catch(session: Session, runaway: Runaway, position: Vector3)
	removeRunaway(runaway)
	local player = session.player
	local def, variant = runaway.def, runaway.variant
	local name = GameData.displayName(def, variant)
	local rarity = GameData.catalog.rarities[def.rarity]
	local given, refund = PrizeService.giveOrSell(session, def, variant, "Runaway")
	if given then
		Remotes.notify(player, Format.template(Theme.text.runawayReward, { creature = name }), "success")
	else
		Remotes.notify(
			player,
			Format.template(Theme.text.runawayRewardFull, { creature = name, cash = UiTheme.cash(refund) }),
			"success"
		)
	end
	Announcer.broadcast({
		text = Format.template(
			Theme.text.runawayCaught,
			{ player = player.DisplayName, rarity = rarity.displayName, creature = name }
		),
		rarity = def.rarity,
		kind = "drop",
	})
	Remotes.fireAll("Effect", { kind = "runaway", position = position, rarity = def.rarity })
	GameEvents.emit(session, { kind = "milestone", milestone = "runaway" }) -- achievements
end

-- Plans each runaway's next leg as the last one ends (sprinting while someone is near), and lets uncaught ones get
-- away.
local function runRunaways(t: number)
	local points: { DropRules.Point }? = nil
	for _, runaway in runaways do
		if t >= runaway.expiresAt then
			removeRunaway(runaway)
		elseif t >= runaway.leg.endsAt then
			local players = points or playerPoints()
			points = players
			local leg = runaway.leg
			local toX, toZ = DropRules.runawayTarget(Drops, leg.toX, leg.toZ, players, nextRandom)
			local fleeing = DropRules.isFleeing(Drops, leg.toX, leg.toZ, players)
			setLeg(runaway, DropRules.runawayLeg(Drops, leg.toX, leg.toZ, toX, toZ, t, fleeing))
		end
	end
end

-- Moves the runaways on, then whoever reaches one first catches it (positions trusted as for a steal, like crates: a
-- teleport next to one only pays off after the 10 s a steal would wait). Coins keep the lighter check: each is worth
-- a few seconds of income, and a hop to one still costs its 2 s.
local function stepRunaways()
	if next(runaways) == nil then
		return
	end
	local t = now()
	runRunaways(t)
	for _, runaway in runaways do
		local position = runawayPosition(runaway, t)
		for _, player in Players:GetPlayers() do
			local session = Sessions.get(player)
			local root = if session then Sessions.rootPart(session) else nil
			if session == nil or root == nil then
				continue
			end
			local offset = root.Position - position
			local horizontal = Vector3.new(offset.X, 0, offset.Z).Magnitude
			if
				DropRules.catches(Drops, horizontal, offset.Y, REACH_SLACK)
				and PositionTracker.isTrustedForSteal(session, root.Position)
			then
				catch(session, runaway, position)
				break
			end
		end
	end
end

-- The schedule -------------------------------------------------------------------------------------------------------

local function step()
	local t = now()
	local id = ModifierService.current()
	local def = if id then Modifiers.modifiers[id] else nil
	local drops = if def then def.drops else nil
	if id ~= runningId then
		runningId = id
		pending = {}
		if drops then
			for _, offset in DropRules.times(drops, math.max(0, ModifierService.endsAt() - t)) do
				table.insert(pending, t + offset)
			end
		end
	end
	while drops and #pending > 0 and t >= pending[1] do
		table.remove(pending, 1)
		if drops.kind == "crate" then
			spawnCrate(t)
		elseif drops.kind == "runaway" then
			spawnRunaway(t)
		elseif drops.kind == "coins" then
			spawnCoins(t)
		end -- "boss": BossService
	end
	for _, crate in crates do
		if not crate.landed and t >= crate.landsAt then
			land(crate)
		end
		if t >= crate.expiresAt then
			removeCrate(crate)
		end
	end
	for index = #coins, 1, -1 do
		local coin = coins[index]
		if t >= coin.expiresAt then
			table.remove(coins, index)
			coin.part:Destroy()
		end
	end
end

-- How many crates, coins and runaways are out right now (tests).
function DropService.counts(): (number, number, number)
	local crateCount, runawayCount = 0, 0
	for _ in crates do
		crateCount += 1
	end
	for _ in runaways do
		runawayCount += 1
	end
	return crateCount, #coins, runawayCount
end

-- A Snackling escapes now (Studio /runaway; the server test): far from everyone, or at `at`. Returns its model.
function DropService.releaseRunaway(at: Vector3?): Model?
	local runaway = spawnRunaway(now(), at)
	return if runaway then runaway.model else nil
end

-- Where runaway `model` is now, as the server sees it (tests).
function DropService.runawayPosition(model: Model): Vector3?
	local id = model:GetAttribute("RunawayId")
	local runaway = if type(id) == "number" then runaways[id] else nil
	return if runaway then runawayPosition(runaway, now()) else nil
end

-- The crate models out right now, by id (tests).
function DropService.crateModels(): { [number]: Model }
	local models: { [number]: Model } = {}
	for id, crate in crates do
		models[id] = crate.model
	end
	return models
end

function DropService.start(walkwayTop: number)
	walkwayY = walkwayTop
	for _, problem in
		DropRules.validate(Drops, {
			maxX = Gameplay.belt.length / 2,
			maxZ = Gameplay.map.walkwayWidth,
			beltHalfWidth = Gameplay.belt.width / 2,
		})
	do
		warn(`[Drops] config problem: {problem}`)
	end
	folder = Instance.new("Folder")
	folder.Name = "Drops"
	folder.Parent = workspace
	Remotes.onIntent("CrateBegin", onBegin)
	Remotes.onIntent("CrateOpen", onOpen)
	task.spawn(function()
		while true do
			task.wait(STEP_SECONDS)
			local ok, err = pcall(step :: () -> ...any)
			if not ok then
				warn(`[Drops] {err}`)
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(PICKUP_SECONDS)
			local ok, err = pcall(pickUp :: () -> ...any)
			if not ok then
				warn(`[Drops] {err}`)
			end
			ok, err = pcall(stepRunaways :: () -> ...any)
			if not ok then
				warn(`[Drops] {err}`)
			end
		end
	end)
end

return DropService
