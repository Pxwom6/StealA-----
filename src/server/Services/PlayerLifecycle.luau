--!strict
--[[
	Join / leave orchestration. Order matters, so it lives in one place:

	join:  load save (session-locked) → check game passes → create session → claim a plot → grace period →
	       income/podiums → offline earnings → leaderstats → spawn at base → (client ready) send state
	leave: cancel steals involving the player → release plot → end the save session (final save)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Gameplay = require(ReplicatedStorage.Shared.Config.Gameplay)
local LockRules = require(ReplicatedStorage.Shared.Logic.LockRules)
local StealRules = require(ReplicatedStorage.Shared.Logic.StealRules)
local Analytics = require(script.Parent.Analytics)
local BeltService = require(script.Parent.BeltService)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local PlotService = require(script.Parent.PlotService)
local PositionTracker = require(script.Parent.PositionTracker)
local Remotes = require(script.Parent.Remotes)
local Replication = require(script.Parent.Replication)
local Sessions = require(script.Parent.Sessions)

type Session = Sessions.Session

export type Hooks = {
	-- Called after the session exists and has a plot, before the client is told anything. May yield.
	onJoined: { (session: Session) -> () },
	-- Called when the client reports ready (after state + belt snapshot were sent).
	onReady: { (session: Session) -> () },
	-- Called first thing on leave, while the session and plot still exist.
	onLeaving: { (session: Session) -> () },
	-- Fills session.passes before anything else uses them. May yield.
	checkPasses: ((player: Player) -> Sessions.Passes)?,
}

local PlayerLifecycle = {}

local hooks: Hooks = { onJoined = {}, onReady = {}, onLeaving = {}, checkPasses = nil }
local pendingReady: { [Player]: boolean } = {}

function PlayerLifecycle.hooks(): Hooks
	return hooks
end

local function createLeaderstats(player: Player)
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	local cash = Instance.new("StringValue")
	cash.Name = "Cash"
	cash.Parent = folder
	local steals = Instance.new("IntValue")
	steals.Name = "Steals"
	steals.Parent = folder
	folder.Parent = player
end

local function placeAtBase(session: Session, character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if root == nil or session.plot == 0 or character.Parent == nil then
		return
	end
	local spawnCFrame = PlotService.refs(session.plot).spawnCFrame
	character:PivotTo(spawnCFrame)
	PositionTracker.reset(session, spawnCFrame.Position) -- a server move, not a teleport exploit
end

local function onCharacterAdded(session: Session, character: Model)
	PositionTracker.reset(session, nil)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.WalkSpeed = Gameplay.walkSpeed
	end
	task.defer(placeAtBase, session, character)
end

local function markReady(session: Session)
	session.ready = true
	Replication.flush(session)
	BeltService.sendSnapshot(session.player)
	for _, hook in hooks.onReady do
		task.spawn(hook, session)
	end
end

local function onPlayerAdded(player: Player)
	local profile, failure = DataService.load(player)
	if profile == nil then
		-- A load cut short by a shutdown is not a data problem: no misleading kick (the server is closing anyway).
		if player.Parent == Players and not DataService.isClosing() then
			player:Kick(
				if failure == "newerSave"
					then "This server is updating — please rejoin!"
					else "Could not load your data. Please rejoin in a moment!"
			)
		end
		return
	end
	if player.Parent ~= Players then
		DataService.release(profile)
		return
	end
	local lastSeenAtJoin = profile.Data.lastSeen

	local passes: Sessions.Passes = if hooks.checkPasses
		then hooks.checkPasses(player)
		else { DoubleCash = false, VIP = false, ExtraPodiums = false, LongerLock = false }
	if player.Parent ~= Players then
		DataService.release(profile)
		return
	end

	local now = workspace:GetServerTimeNow()
	local session: Session = {
		player = player,
		userId = player.UserId,
		profile = profile,
		data = profile.Data,
		plot = 0,
		passes = passes,
		lock = LockRules.newState(),
		graceUntil = 0,
		carry = nil,
		hold = nil,
		stealCooldownUntil = 0,
		tagCooldownUntil = 0,
		walk = nil,
		flaggedAt = -math.huge,
		teleportedAt = -math.huge,
		joinedAt = now,
		lastSeenAtJoin = lastSeenAtJoin,
		playClock = os.clock(),
		ready = false,
		dirty = true,
		incomePerSecond = 0,
		packIncome = 0,
		multiplier = 1,
		capacity = 0,
		lockDuration = Gameplay.lock.durationSeconds,
		pendingWelcome = nil,
	}
	Sessions.add(session)

	profile.OnSessionEnd:Connect(function()
		-- Another server took the session (or it ended unexpectedly): never keep playing on stale data. During a
		-- shutdown every session ends on purpose and players are disconnected when the server closes, so no
		-- misleading kick then (steals refuse to move creatures between ended sessions, see StealService).
		if DataService.isClosing() then
			return
		end
		if player.Parent == Players and Sessions.get(player) == session then
			player:Kick("Your data was opened in another server. Please rejoin.")
		end
	end)

	if session.data.firstJoin == 0 then
		session.data.firstJoin = os.time()
	end
	Analytics.milestone(session, "Joined")

	if PlotService.assign(session) == nil then
		player:Kick("This server is full. Please join another server!")
		return
	end
	session.graceUntil = StealRules.graceUntil(now, session.data.stats.playTime, Gameplay.grace.newPlayerSeconds)
	PlotService.setShieldTimes(session.plot, 0, session.graceUntil)

	EconomyService.refresh(session)
	for _, hook in hooks.onJoined do
		hook(session)
	end

	createLeaderstats(player)
	Replication.flush(session)

	player.CharacterAdded:Connect(function(character: Model)
		onCharacterAdded(session, character)
	end)
	if player.Character then
		onCharacterAdded(session, player.Character)
	end

	if pendingReady[player] then
		pendingReady[player] = nil
		markReady(session)
	end
end

local function onPlayerRemoving(player: Player)
	pendingReady[player] = nil
	Remotes.forget(player)
	local session = Sessions.get(player)
	if session == nil then
		return
	end
	for _, hook in hooks.onLeaving do
		local ok, err = pcall(hook :: (Session) -> ...any, session)
		if not ok then
			warn(`[PlayerLifecycle] leave hook failed: {err}`)
		end
	end
	Analytics.forget(session)
	PlotService.release(session)
	Sessions.remove(player)
	DataService.release(session.profile)
end

local function onClientReady(player: Player)
	local session = Sessions.get(player)
	if session == nil then
		pendingReady[player] = true -- data still loading; finish when the session exists
		return
	end
	if not session.ready then
		markReady(session)
	end
end

function PlayerLifecycle.start()
	Remotes.onIntent("ClientReady", onClientReady)
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return PlayerLifecycle
