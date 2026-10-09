--!strict
--[[
	Registry of per-player runtime state. One Session exists while a player is in the server and their save is
	loaded. Saved data lives in `session.data` (the live ProfileStore table); everything else is runtime only.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local LockRules = require(ReplicatedStorage.Shared.Logic.LockRules)
local StealRules = require(ReplicatedStorage.Shared.Logic.StealRules)

type Connection = { Disconnect: (self: any) -> () }
type Signal<T...> = { Connect: (self: any, listener: (T...) -> ()) -> Connection }

-- The subset of ProfileStore's Profile we use (the library's own generic type does not survive strict mode well).
export type Profile = {
	Data: Types.PlayerData,
	LastSavedData: Types.PlayerData,
	Key: string,
	IsActive: (self: Profile) -> boolean,
	Save: (self: Profile) -> (),
	EndSession: (self: Profile) -> (),
	AddUserId: (self: Profile, userId: number) -> (),
	Reconcile: (self: Profile) -> (),
	OnSave: Signal<>,
	OnLastSave: Signal<string>,
	OnAfterSave: Signal<any>,
	OnSessionEnd: Signal<>,
}

export type Passes = Types.Passes

export type Carry = {
	victimUserId: number,
	plot: number,
	podium: number,
	uid: string,
	creatureId: string,
	startedAt: number,
	track: StealRules.CarryTrack, -- movement budget, timed with os.clock()
	model: Model?,
	marker: BillboardGui?,
}

-- A Steal button press (StealBegin): when the server-timed hold started, or why it didn't (StealRules.canBeginHold).
export type Hold = { plot: number, podium: number, startedAt: number?, refusal: string? }

export type Session = {
	player: Player,
	userId: number,
	profile: Profile,
	data: Types.PlayerData,
	plot: number, -- 0 = none
	passes: Passes,
	lock: LockRules.LockState,
	graceUntil: number,
	carry: Carry?,
	hold: Hold?,
	stealCooldownUntil: number,
	tagCooldownUntil: number,
	walk: StealRules.WalkTrack?, -- server-observed movement (PositionTracker); nil until the first sample
	flaggedAt: number, -- server time of the last step the walk budget couldn't pay for (-inf: never)
	teleportedAt: number, -- server time of the last gross overrun, i.e. a teleport (-inf: never)
	joinedAt: number,
	lastSeenAtJoin: number, -- the save's lastSeen when it was loaded (offline earnings)
	playClock: number, -- os.clock() of the last play-time accrual
	ready: boolean, -- the client has finished loading and asked for state
	dirty: boolean, -- state changed since the last StateUpdate
	-- caches maintained by the services that own them
	incomePerSecond: number,
	packIncome: number, -- steady income cash packs are sized from (EconomyMath.packIncome)
	multiplier: number,
	capacity: number,
	lockDuration: number,
	pendingWelcome: { amount: number, seconds: number }?,
}

local Sessions = {}

local byPlayer: { [Player]: Session } = {}
local byUserId: { [number]: Session } = {}

function Sessions.add(session: Session)
	byPlayer[session.player] = session
	byUserId[session.userId] = session
end

function Sessions.remove(player: Player): Session?
	local session = byPlayer[player]
	if session then
		byPlayer[player] = nil
		byUserId[session.userId] = nil
	end
	return session
end

function Sessions.get(player: Player): Session?
	return byPlayer[player]
end

function Sessions.getByUserId(userId: number): Session?
	return byUserId[userId]
end

function Sessions.all(): { Session }
	local list: { Session } = {}
	for _, session in byPlayer do
		table.insert(list, session)
	end
	return list
end

-- Character root part, if the player is alive and spawned.
function Sessions.rootPart(session: Session): BasePart?
	local character = session.player.Character
	if character == nil then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or humanoid.Health <= 0 then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

function Sessions.humanoid(session: Session): Humanoid?
	local character = session.player.Character
	return if character then character:FindFirstChildOfClass("Humanoid") else nil
end

return Sessions
