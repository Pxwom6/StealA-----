--!strict
--[[
	Persistence with ProfileStore (session-locked: a profile can only be active on one server at a time, so data
	cannot be duplicated by hopping servers).

	* load:        starts the session, reconciles with the template, migrates and sanitises the save in place
	* autosave:    ProfileStore saves every few minutes on its own
	* on leave:    PlayerLifecycle calls `release`, which ends the session (final save)
	* on shutdown: BindToClose ends every session and waits for the final saves
	* saveAndWait: used by receipts — request a save and yield until it lands (or the session ends / times out)

	In Studio without "Studio Access to API Services", ProfileStore automatically uses a mock store, so the game
	still runs (nothing persists between sessions).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataSchema = require(ReplicatedStorage.Shared.Logic.DataSchema)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Gameplay = require(ReplicatedStorage.Shared.Config.Gameplay)
local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)
local RebirthConfig = Economy.rebirth
local GameData = require(ReplicatedStorage.Shared.GameData)
local Sessions = require(script.Parent.Sessions)

type Profile = Sessions.Profile

-- Bump the suffix only for a deliberate wipe; schema changes go through DataSchema.migrate instead.
local STORE_NAME = "PlayerData_v1"

-- Give up loading after about this long (the player is then kicked with "please rejoin"). Passing `Cancel` turns off
-- ProfileStore's own 120 s timeout, so we need our own. It must outlast ProfileStore's session steal from a crashed
-- server, which lands 45-51 s in (5 s + 4 x 10 s of waits, plus six DataStore calls); 45 s would cancel just before
-- it and leave the player locked out until the dead session expires (~10 min).
local LOAD_TIMEOUT_SECONDS = 60

local DataService = {}

-- ProfileStore is installed by Wally (`wally install`) into ServerScriptService.ServerPackages.
local ProfileStoreModule: any = require(ServerScriptService.ServerPackages.ProfileStore)
local store: any = nil

local sanitiseRules: DataSchema.SanitiseRules = {
	isValidCreature = function(id: string): boolean
		return GameData.catalog.creatures[id] ~= nil
	end,
	maxPodiums = Gameplay.map.maxPodiums,
	maxPodiumUpgrades = Economy.podiumUpgrade.maxPurchased,
	maxRebirths = RebirthConfig.maxRebirths,
	maxReceipts = Monetization.purchaseIdCacheSize,
	maxHistory = Monetization.purchaseHistorySize,
}

local function profileKey(userId: number): string
	return `Player_{userId}`
end

function DataService.start()
	store = ProfileStoreModule.New(STORE_NAME, DataSchema.template(Economy.startingCash))
	ProfileStoreModule.OnError:Connect(function(message: string, storeName: string, key: string)
		warn(`[DataService] ProfileStore error ({storeName}/{key}): {message}`)
	end)

	game:BindToClose(function()
		-- End every session so the final save happens now; ProfileStore waits for in-flight saves.
		for _, session in Sessions.all() do
			session.data.lastSeen = os.time()
			if session.profile:IsActive() then
				session.profile:EndSession()
			end
		end
		local deadline = os.clock() + 25
		while os.clock() < deadline do
			local anyActive = false
			for _, session in Sessions.all() do
				if session.profile:IsActive() then
					anyActive = true
				end
			end
			if not anyActive then
				break
			end
			task.wait(0.25)
		end
	end)
end

-- Starts a session for `player`. Yields (about LOAD_TIMEOUT_SECONDS at most: Cancel is checked between DataStore
-- calls). Returns nil if the player left, the load timed out, or the store could not start a session.
function DataService.load(player: Player): Profile?
	local deadline = os.clock() + LOAD_TIMEOUT_SECONDS
	local profile: Profile? = store:StartSessionAsync(profileKey(player.UserId), {
		Cancel = function(): boolean
			return player.Parent ~= Players or os.clock() >= deadline
		end,
	})
	if profile == nil then
		return nil
	end
	profile:AddUserId(player.UserId) -- GDPR: associates the key with the user for erasure requests
	profile:Reconcile()

	local raw = (profile.Data :: any) :: { [string]: any }
	DataSchema.migrate(raw)
	local clean, fixes = DataSchema.sanitise(raw, Economy.startingCash, sanitiseRules)
	DataSchema.applyInPlace(raw, clean)
	if #fixes > 0 then
		warn(`[DataService] repaired save for {player.UserId}: {table.concat(fixes, ", ")}`)
	end

	-- Keep lastSeen fresh in every save (used for offline earnings).
	profile.OnSave:Connect(function()
		profile.Data.lastSeen = os.time()
	end)
	return profile
end

function DataService.release(profile: Profile)
	profile.Data.lastSeen = os.time()
	if profile:IsActive() then
		profile:EndSession()
	end
end

-- Requests a save and yields until a save completes, the session ends, or `timeout` seconds pass.
function DataService.saveAndWait(profile: Profile, timeout: number)
	if not profile:IsActive() then
		return
	end
	local saved = false
	local connection = profile.OnAfterSave:Connect(function()
		saved = true
	end)
	profile:Save()
	local deadline = os.clock() + timeout
	while not saved and profile:IsActive() and os.clock() < deadline do
		task.wait(0.1)
	end
	connection:Disconnect()
end

-- Fire-and-forget save after important changes (steals, rebirths, purchases).
function DataService.saveSoon(profile: Profile)
	if profile:IsActive() then
		profile:Save()
	end
end

return DataService
