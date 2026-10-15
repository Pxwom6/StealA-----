--!strict
--[[
	Snack Attack (a server modifier with `drops.kind = "boss"`; Config/Boss): a giant Snackling hovers over the middle
	of the belt and everyone taps it together.

	  * It appears on the modifier's drop schedule (DropRules.times), never while another one is still up: a regular
	    Snackling of one of the configured tiers, built at `scale` times its podium size, tagged for the client
	    (BossController draws its health bar, bob, turn and hit reactions) with attributes MaxHP, HP and EndsAt.
	  * Hits come from a ClickDetector (a mouse click, a tap, or a gamepad's R2 at the screen's centre dot). Roblox's
	    pointer hit-test is a spatial query, and creature models are built with CanQuery off, so the detector sits on
	    an invisible Hitbox part around the giant that queries can hit (it collides with and touches nothing). Each hit
	    counts only if the player is within reach of its middle at a position the server trusts (PositionTracker),
	    and only `hitsPerSecond` a second per player (RateLimiter, with a small burst): auto-clickers gain nothing.
	    The HP attribute is updated ten times a second.
	  * Taken down: everyone who landed `minHits` shares the reward (BossRules: cash from their own income, more for a
	    bigger share), the top hitter wins a Snackling rolled with extra luck, and everyone hears it. Not taken down by
	    EndsAt: it flies off, nothing is paid.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Boss = require(ReplicatedStorage.Shared.Config.Boss)
local Modifiers = require(ReplicatedStorage.Shared.Config.Modifiers)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local CreatureVisuals = require(ReplicatedStorage.Shared.CreatureVisuals)
local GameData = require(ReplicatedStorage.Shared.GameData)
local Types = require(ReplicatedStorage.Shared.Types)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local BossRules = require(ReplicatedStorage.Shared.Logic.BossRules)
local DropRules = require(ReplicatedStorage.Shared.Logic.DropRules)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local RateLimiter = require(ReplicatedStorage.Shared.Logic.RateLimiter)
local Announcer = require(script.Parent.Announcer)
local EconomyService = require(script.Parent.EconomyService)
local GameEvents = require(script.Parent.GameEvents)
local ModifierService = require(script.Parent.ModifierService)
local PositionTracker = require(script.Parent.PositionTracker)
local PrizeService = require(script.Parent.PrizeService)
local Remotes = require(script.Parent.Remotes)
local Sessions = require(script.Parent.Sessions)

local BossService = {}

BossService.TAG = "SnackBoss"
-- The giant's one hit-testable part, which holds its ClickDetector (BossController finds it by this name).
BossService.HITBOX = "Hitbox"

local STEP_SECONDS = 0.1
-- The server allows this much more than the ClickDetector's reach (a player stepping back as they tap).
local REACH_SLACK = 4

type Giant = {
	model: Model,
	def: Types.CreatureDef,
	centre: Vector3,
	hp: number,
	maxHp: number,
	endsAt: number,
	hits: { [string]: number },
	players: { [string]: Player },
	shownHp: number, -- the HP attribute as last set
}

local current: Giant? = nil
local walkwayY = 0.2
local random = Random.new()
local limiter = RateLimiter.new(Boss.burst, Boss.hitsPerSecond)
local runningId: string? = nil
local pending: { number } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

-- A regular Snackling of one of the configured tiers (the giant's looks; the prize is rolled separately).
local function pickCreature(): Types.CreatureDef?
	local pool: { Types.CreatureDef } = {}
	for _, rarityId in Boss.rarities do
		local tier = GameData.catalog.byRarity[rarityId]
		if tier then
			for _, creature in tier do
				if creature.eventId == nil then
					table.insert(pool, creature)
				end
			end
		end
	end
	if #pool == 0 then
		return nil
	end
	return pool[random:NextInteger(1, #pool)]
end

local function remove(giant: Giant)
	if current == giant then
		current = nil
	end
	giant.model:Destroy()
end

-- Taken down: pay everyone who helped, the top hitter's prize, and tell everyone.
local function defeat(giant: Giant)
	giant.model:SetAttribute("HP", 0)
	local position = giant.centre
	remove(giant)
	local creatureName = GameData.displayName(giant.def, nil)
	local shares = BossRules.shares(Boss, giant.hits)
	for _, share in shares do
		local player = giant.players[share.key]
		local session = if player then Sessions.get(player) else nil
		if session then
			local cash = BossRules.cash(Boss, share.share, session.packIncome)
			EconomyService.addCash(session, cash, "Gameplay", "SnackAttack")
			Remotes.notify(
				session.player,
				Format.template(Theme.text.bossReward, { cash = UiTheme.cash(cash) }),
				"success"
			)
			GameEvents.emit(session, { kind = "milestone", milestone = "snackAttack" }) -- achievements
		end
	end
	local top = shares[1]
	local winner = if top then giant.players[top.key] else nil
	local winnerSession = if winner then Sessions.get(winner) else nil
	local prizeDef, prizeVariant = nil, nil
	if winnerSession then
		prizeDef, prizeVariant = PrizeService.rollCreature(Boss.luck, Boss.mutationChance, nil)
	end
	if winnerSession then
		GameEvents.emit(winnerSession, { kind = "milestone", milestone = "snackAttackTop" }) -- achievements
	end
	if winnerSession and prizeDef then
		local name = GameData.displayName(prizeDef, prizeVariant)
		local given, refund = PrizeService.giveOrSell(winnerSession, prizeDef, prizeVariant, "SnackAttack")
		Remotes.notify(
			winnerSession.player,
			if given
				then Format.template(Theme.text.bossPrize, { creature = name })
				else Format.template(Theme.text.bossPrizeFull, { creature = name, cash = UiTheme.cash(refund) }),
			"success"
		)
		Announcer.broadcast({
			text = Format.template(Theme.text.bossDefeated, {
				creature = creatureName,
				player = winnerSession.player.DisplayName,
				rarity = GameData.catalog.rarities[prizeDef.rarity].displayName,
				prize = name,
			}),
			rarity = prizeDef.rarity,
			kind = "drop",
		})
	else
		Announcer.broadcast({
			text = Format.template(Theme.text.bossDown, { creature = creatureName }),
			rarity = giant.def.rarity,
			kind = "drop",
		})
	end
	Remotes.fireAll("Effect", { kind = "bossDown", position = position, rarity = giant.def.rarity })
end

local function onHit(player: Player)
	local giant = current
	local session = Sessions.get(player)
	if giant == nil or session == nil or giant.hp <= 0 then
		return
	end
	local root = Sessions.rootPart(session)
	if root == nil then
		return
	end
	local key = tostring(player.UserId)
	if not RateLimiter.allow(limiter, key, os.clock()) then
		return
	end
	if (root.Position - giant.centre).Magnitude > Boss.reach + REACH_SLACK then
		return
	end
	if not PositionTracker.isTrusted(session, root.Position) then
		return
	end
	giant.hits[key] = (giant.hits[key] or 0) + 1
	giant.players[key] = player
	giant.hp -= 1
	if giant.hp <= 0 then
		defeat(giant)
	end
end

-- The part the giant's ClickDetector answers for: an invisible box around it (its bounding box), welded to its root
-- so it bobs and turns with it on every client. It is the only part of the giant a pointer can hit (CanQuery), and it
-- never collides or touches; a box is also kinder to small fingers than the giant's outline.
local function addHitbox(model: Model, box: CFrame, size: Vector3): BasePart
	local hitbox = Instance.new("Part")
	hitbox.Name = BossService.HITBOX
	hitbox.Size = Vector3.new(math.max(size.X, 2), math.max(size.Y, 2), math.max(size.Z, 2))
	hitbox.CFrame = box
	hitbox.Transparency = 1
	hitbox.CastShadow = false
	hitbox.CanCollide = false
	hitbox.CanTouch = false
	hitbox.CanQuery = true
	hitbox.Massless = true
	hitbox.Anchored = false
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = model.PrimaryPart :: BasePart
	weld.Part1 = hitbox
	weld.Parent = hitbox
	hitbox.Parent = model
	return hitbox
end

-- A giant appears over the middle of the belt (or at `at`), with health for the players here (or `hp`: the Studio
-- command and the server test). nil when no Snackling can play it.
local function spawnGiant(t: number, at: Vector3?, hp: number?): Giant?
	local def = pickCreature()
	if def == nil then
		return nil
	end
	local rarity = GameData.catalog.rarities[def.rarity]
	local giantRarity = table.clone(rarity)
	giantRarity.modelScale = rarity.modelScale * Boss.scale
	local model = CreatureVisuals.build(def, giantRarity, { anchored = true, idle = false })
	model.Name = "SnackAttackGiant"
	local feet = at or Vector3.new(0, walkwayY + Boss.hoverHeight, 0)
	model:PivotTo(CFrame.new(feet) * CFrame.Angles(0, random:NextNumber(0, math.pi * 2), 0))
	local boxCentre, size = model:GetBoundingBox()
	local players = #Players:GetPlayers()
	local maxHp = hp or BossRules.maxHp(Boss, players)
	local giant: Giant = {
		model = model,
		def = def,
		centre = Vector3.new(feet.X, boxCentre.Position.Y, feet.Z),
		hp = maxHp,
		maxHp = maxHp,
		endsAt = t + Boss.lifetimeSeconds,
		hits = {},
		players = {},
		shownHp = maxHp,
	}
	model:SetAttribute("MaxHP", maxHp)
	model:SetAttribute("HP", maxHp)
	model:SetAttribute("EndsAt", giant.endsAt)
	model:SetAttribute("Height", size.Y)
	local clicker = Instance.new("ClickDetector")
	clicker.MaxActivationDistance = Boss.reach
	clicker.Parent = addHitbox(model, boxCentre, size)
	clicker.MouseClick:Connect(onHit)
	CollectionService:AddTag(model, BossService.TAG)
	model.Parent = workspace
	current = giant
	Announcer.broadcast({
		text = Format.template(Theme.text.bossAppeared, { creature = GameData.displayName(def, nil) }),
		rarity = def.rarity,
		kind = "drop",
	})
	return giant
end

local function step()
	local t = now()
	local id = ModifierService.current()
	local def = if id then Modifiers.modifiers[id] else nil
	local drops = if def and def.drops and def.drops.kind == "boss" then def.drops else nil
	if id ~= runningId then
		runningId = id
		pending = {}
		if drops then
			for _, offset in DropRules.times(drops, math.max(0, ModifierService.endsAt() - t)) do
				table.insert(pending, t + offset)
			end
		end
	end
	while #pending > 0 and t >= pending[1] do
		table.remove(pending, 1)
		if current == nil then
			spawnGiant(t)
		end
	end
	local giant = current
	if giant then
		if t >= giant.endsAt then
			remove(giant)
			Announcer.broadcast({
				text = Format.template(Theme.text.bossEscaped, { creature = GameData.displayName(giant.def, nil) }),
				kind = "drop",
			})
		elseif giant.hp ~= giant.shownHp then
			giant.shownHp = giant.hp
			giant.model:SetAttribute("HP", giant.hp)
		end
	end
end

-- The giant up now, if any (tests).
function BossService.current(): Model?
	return if current then current.model else nil
end

-- A giant appears now (Studio /boss; the server test), over the belt or at `at`, with `hp` health if given. Returns
-- its model (the one already up, if any).
function BossService.release(at: Vector3?, hp: number?): Model?
	if current then
		return current.model
	end
	local giant = spawnGiant(now(), at, hp)
	return if giant then giant.model else nil
end

-- Hits landed on the current giant by `player` (tests).
function BossService.hitsBy(player: Player): number
	return if current then current.hits[tostring(player.UserId)] or 0 else 0
end

function BossService.start(walkwayTop: number)
	walkwayY = walkwayTop
	local rarityIds: { [string]: boolean } = {}
	for id in GameData.catalog.rarities do
		rarityIds[id] = true
	end
	for _, problem in BossRules.validate(Boss, rarityIds) do
		warn(`[Boss] config problem: {problem}`)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		RateLimiter.forget(limiter, tostring(player.UserId))
	end)
	task.spawn(function()
		while true do
			task.wait(STEP_SECONDS)
			local ok, err = pcall(step :: () -> ...any)
			if not ok then
				warn(`[Boss] {err}`)
			end
		end
	end)
end

return BossService
