--!strict
--[[
	Renders the conveyor locally. The server only sends {id, creatureId, spawnAt, variant}; positions come from
	Logic/BeltMath and the shared server clock, so movement costs zero network traffic.

	Models are pooled per creature type and mutation (built once, reused forever) and each item gets a local "Buy"
	prompt that sends the BuyBeltItem intent — the server re-validates price, range and space. A mutated item shows
	the mutation's name in its colour, its mutated name ("Golden Pizza Pup") and its mutated price and income; a
	limited-time (event) Snackling has a small "EVENT" tag in its event's colour on top.

	Items hop along (Logic/IdleMotion.belt): the hop and a little waddle are part of the per-frame move; the squash
	and stretch of the body is only applied to items near the camera, about 30 times a second.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Gameplay = require(ReplicatedStorage.Shared.Config.Gameplay)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local GameData = require(ReplicatedStorage.Shared.GameData)
local Net = require(ReplicatedStorage.Shared.Net)
local Types = require(ReplicatedStorage.Shared.Types)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local CreatureVisuals = require(ReplicatedStorage.Shared.CreatureVisuals)
local BeltMath = require(ReplicatedStorage.Shared.Logic.BeltMath)
local IdleMotion = require(ReplicatedStorage.Shared.Logic.IdleMotion)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local ClientSettings = require(script.Parent.ClientSettings)
local NotificationController = require(script.Parent.NotificationController)
local SoundPlayer = require(script.Parent.SoundPlayer)
local StateStore = require(script.Parent.StateStore)

type Pooled = {
	key: string, -- poolKey(creatureId, variant)
	model: Model,
	prompt: ProximityPrompt,
	priceLabel: TextLabel,
	height: number,
	squash: { CreatureVisuals.SquashPart }, -- body parts the hop squashes
}

type Active = {
	item: Types.BeltItem,
	variant: string?,
	pooled: Pooled,
	connection: RBXScriptConnection,
	phase: number, -- idle animation phase (from the item id)
}

type Row = { text: string, color: Color3?, weight: number }

local BeltController = {}

local belt = BeltMath.centered(Gameplay.belt.length, Gameplay.belt.travelSeconds)
local surfaceY = Gameplay.belt.surfaceY
local active: { [number]: Active } = {}
local pools: { [string]: { Pooled } } = {}
local folder: Folder
local hidden = CFrame.new(0, -500, 0) -- parked pooled models (MutationFxController skips anything below y = -400)

-- Squash and stretch only items this close to the camera, at most this often.
local SQUASH_RANGE = 120
local SQUASH_STEP = 1 / 30
local lastSquash = 0

-- Studs between the top of an item's model and the centre of its name / price billboard.
local LABEL_GAP = 2.2

-- Share of the billboard height the rows of a plain item fill (the rest is breathing room).
local ROWS_FILL = 0.82

-- A mutation this client doesn't know (e.g. a newer server mid-update) is drawn and priced as plain, like the
-- server does for an unknown saved variant.
local function knownVariant(variant: string?): string?
	return if GameData.mutation(variant) ~= nil then variant else nil
end

local function poolKey(creatureId: string, variant: string?): string
	return creatureId .. "|" .. (variant or "")
end

local function makeBillboard(
	model: Model,
	def: Types.CreatureDef,
	rarity: Types.RarityDef,
	variant: string?,
	height: number
): TextLabel
	local root = model.PrimaryPart :: BasePart
	local big = rarity.order >= 6
	local mutation = GameData.mutation(variant)
	local rows: { Row } =
		{ { text = string.upper(rarity.displayName), color = UiTheme.color(rarity.color), weight = 0.26 } }
	if def.eventId then
		-- Limited-time Snackling: a small tag in its event's colour.
		table.insert(rows, 1, { text = Theme.text.eventTag, color = UiTheme.eventColor(def.eventId), weight = 0.2 })
	end
	if mutation then
		-- One more line, the mutation's name in its colour; the billboard grows so every line keeps its size.
		table.insert(
			rows,
			{ text = string.upper(mutation.displayName), color = UiTheme.color(mutation.color), weight = 0.26 }
		)
	end
	table.insert(rows, { text = GameData.displayName(def, variant), color = nil, weight = 0.3 })
	table.insert(rows, { text = "", color = UiTheme.palette("cash"), weight = 0.26 }) -- price, filled below
	local fill = 0
	for _, row in rows do
		fill += row.weight
	end
	local baseHeight = if big then 96 else 80
	local gui = UiKit.new("BillboardGui", {
		Name = "Info",
		Size = UDim2.fromOffset(if big then 230 else 190, math.floor(baseHeight * fill / ROWS_FILL + 0.5)),
		StudsOffsetWorldSpace = Vector3.new(0, height + LABEL_GAP, 0),
		MaxDistance = 90,
		LightInfluence = 0,
		Parent = root,
	}) :: BillboardGui
	UiKit.new("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Parent = gui,
	})
	local last: TextLabel? = nil
	for index, row in rows do
		local props: UiKit.Props = {
			LayoutOrder = index,
			Text = row.text,
			Size = UDim2.fromScale(1, row.weight * ROWS_FILL / fill),
			Parent = gui,
		}
		if row.color then
			props.TextColor3 = row.color
		end
		last = UiKit.label(props)
	end
	local price = last :: TextLabel
	price.Text = `{UiTheme.cash(GameData.price(def, variant))}  {UiTheme.perSecond(GameData.income(def, variant))}`
	return price
end

local function build(creatureId: string, variant: string?): Pooled
	local def = GameData.catalog.creatures[creatureId]
	local rarity = GameData.catalog.rarities[def.rarity]
	-- idle = false: the belt moves its own models (the hop is folded into step below)
	local model =
		CreatureVisuals.build(def, rarity, { anchored = true, mutation = GameData.mutation(variant), idle = false })
	local height = CreatureVisuals.height(model)
	local priceLabel = makeBillboard(model, def, rarity, variant, height)
	local prompt = UiKit.new("ProximityPrompt", {
		ActionText = Theme.text.buyAction,
		ObjectText = `{GameData.displayName(def, variant)} - {UiTheme.cash(GameData.price(def, variant))}`,
		HoldDuration = 0,
		MaxActivationDistance = Gameplay.belt.buyRange - 2,
		RequiresLineOfSight = false,
		KeyboardKeyCode = Enum.KeyCode.E,
		Parent = model.PrimaryPart,
	}) :: ProximityPrompt
	model.Parent = folder
	return {
		key = poolKey(creatureId, variant),
		model = model,
		prompt = prompt,
		priceLabel = priceLabel,
		height = height,
		squash = CreatureVisuals.squashParts(model),
	}
end

local function acquire(creatureId: string, variant: string?): Pooled
	local pool = pools[poolKey(creatureId, variant)]
	if pool and #pool > 0 then
		local pooled = table.remove(pool) :: Pooled
		pooled.prompt.Enabled = true
		return pooled
	end
	return build(creatureId, variant)
end

local function release(pooled: Pooled)
	pooled.prompt.Enabled = false
	CreatureVisuals.applySquash(pooled.squash, 0)
	pooled.model:PivotTo(hidden)
	local pool = pools[pooled.key]
	if pool == nil then
		pool = {}
		pools[pooled.key] = pool
	end
	table.insert(pool, pooled)
end

local function refreshAffordability(cash: number)
	for _, entry in active do
		local def = GameData.catalog.creatures[entry.item.creatureId]
		entry.pooled.priceLabel.TextColor3 = if cash >= GameData.price(def, entry.variant)
			then UiTheme.palette("cash")
			else UiTheme.palette("danger")
	end
end

local function add(item: Types.BeltItem)
	if active[item.id] or GameData.catalog.creatures[item.creatureId] == nil then
		return
	end
	local variant = knownVariant(item.variant)
	local pooled = acquire(item.creatureId, variant)
	local connection = pooled.prompt.Triggered:Connect(function()
		Net.get("BuyBeltItem"):FireServer(item.id)
	end)
	active[item.id] = {
		item = item,
		variant = variant,
		pooled = pooled,
		connection = connection,
		phase = IdleMotion.phaseOf(item.id),
	}
	local state = StateStore.get()
	if state then
		refreshAffordability(state.cash)
	end
	local def = GameData.catalog.creatures[item.creatureId]
	local rarity = GameData.catalog.rarities[def.rarity]
	if rarity.order >= 5 then
		SoundPlayer.rarity(rarity.id)
	elseif variant then
		SoundPlayer.world("mutation")
	end
end

local function remove(id: number): Active?
	local entry = active[id]
	if entry then
		active[id] = nil
		entry.connection:Disconnect()
		release(entry.pooled)
	end
	return entry
end

-- Flies a glowing orb from the belt to the buyer's podium: the "teleport home" moment.
local function flyHome(from: Vector3, to: Vector3, color: Color3)
	local orb = Instance.new("Part")
	orb.Shape = Enum.PartType.Ball
	orb.Size = Vector3.one * 1.6
	orb.Material = Enum.Material.Neon
	orb.Color = color
	orb.Anchored = true
	orb.CanCollide = false
	orb.CanQuery = false
	orb.CanTouch = false
	orb.Position = from
	orb.Parent = folder
	local mid = (from + to) / 2 + Vector3.new(0, 18, 0)
	local t0 = os.clock()
	local duration = 0.8
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local a = math.min(1, (os.clock() - t0) / duration)
		local p1 = from:Lerp(mid, a)
		local p2 = mid:Lerp(to, a)
		orb.Position = p1:Lerp(p2, a)
		if a >= 1 then
			connection:Disconnect()
			NotificationController.sparkle(to + Vector3.new(0, 2, 0), color)
			local tween = TweenService:Create(orb, TweenInfo.new(0.2), { Size = Vector3.zero })
			tween:Play()
			tween.Completed:Wait()
			orb:Destroy()
		end
	end)
end

local function onRemove(payload: { id: number, buyerUserId: number?, target: Vector3? })
	local entry = active[payload.id]
	local position: Vector3? = nil
	if entry then
		position = entry.pooled.model:GetPivot().Position
	end
	local removed = remove(payload.id)
	if removed and position and payload.target then
		local def = GameData.catalog.creatures[removed.item.creatureId]
		local mutation = GameData.mutation(removed.variant)
		local color = if mutation then UiTheme.color(mutation.color) else UiTheme.rarityColor(def.rarity)
		flyHome(position, payload.target, color)
		SoundPlayer.world("buy")
	end
end

local STILL: IdleMotion.Pose = { lift = 0, squash = 0, roll = 0, yaw = 0 }

local function step()
	local reduced = ClientSettings.reduceEffects()
	local now = workspace:GetServerTimeNow()
	local clock = os.clock()
	local squashNow = clock - lastSquash >= SQUASH_STEP
	if squashNow then
		lastSquash = clock
	end
	local camera = workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else Vector3.zero
	for id, entry in active do
		local item = entry.item
		if BeltMath.isExpired(belt, item.spawnAt, now) then
			remove(id)
			continue
		end
		local x, z = BeltMath.position(belt, item.spawnAt, now)
		-- Settings > Reduce effects: items glide instead of hopping (no squash either).
		local pose = if reduced then STILL else IdleMotion.belt(now - item.spawnAt, entry.phase)
		local position = Vector3.new(x, surfaceY + pose.lift, z)
		local facing = CFrame.lookAt(position, position + Vector3.new(belt.dirX, 0, belt.dirZ))
		entry.pooled.model:PivotTo(facing * CFrame.Angles(0, pose.yaw, pose.roll))
		if squashNow and (position - eye).Magnitude <= SQUASH_RANGE then
			CreatureVisuals.applySquash(entry.pooled.squash, pose.squash)
		end
	end
end

-- What is on the belt right now (for the tutorial guide): each item, its mutation as drawn (nil = plain), its model
-- and how far above the model's pivot its name / price billboard is centred.
export type ItemView = { item: Types.BeltItem, variant: string?, model: Model, labelHeight: number }

function BeltController.items(): { ItemView }
	local list: { ItemView } = {}
	for _, entry in active do
		table.insert(list, {
			item = entry.item,
			variant = entry.variant,
			model = entry.pooled.model,
			labelHeight = entry.pooled.height + LABEL_GAP,
		})
	end
	return list
end

function BeltController.start()
	folder = Instance.new("Folder")
	folder.Name = "BeltItems"
	folder.Parent = workspace

	Net.get("BeltSnapshot").OnClientEvent:Connect(function(items: { Types.BeltItem })
		for id in active do
			remove(id)
		end
		for _, item in items do
			add(item)
		end
	end)
	Net.get("BeltSpawn").OnClientEvent:Connect(add)
	Net.get("BeltRemove").OnClientEvent:Connect(onRemove)
	StateStore.onChange(function(state)
		refreshAffordability(state.cash)
	end)
	RunService.RenderStepped:Connect(step)
end

return BeltController
