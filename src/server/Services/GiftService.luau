--!strict
--[[
	Playtime gifts (Config/Gifts; rules: Logic/GiftRules). Time counts while a player is in game (every few seconds,
	on server time, capped per step so a stall never grants a burst); `data.gifts` holds today's seconds and claims.
	ClaimGift(index) pays an unlocked gift once per day (GiftRules.claim marks it before PrizeService pays, with no
	yield in between). At UTC midnight, gifts that were unlocked but not claimed are paid automatically and the ladder
	starts again. The client shows the ladder from StateUpdate `gifts` and counts the time on itself.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Gifts = require(ReplicatedStorage.Shared.Config.Gifts)
local GameData = require(ReplicatedStorage.Shared.GameData)
local DailyStreak = require(ReplicatedStorage.Shared.Logic.DailyStreak)
local GiftRules = require(ReplicatedStorage.Shared.Logic.GiftRules)
local Guard = require(ReplicatedStorage.Shared.Logic.Guard)
local Analytics = require(script.Parent.Analytics)
local PrizeService = require(script.Parent.PrizeService)
local Remotes = require(script.Parent.Remotes)
local Replication = require(script.Parent.Replication)
local Sessions = require(script.Parent.Sessions)

type Session = Sessions.Session

local GiftService = {}

local TICK_SECONDS = 5
local MAX_STEP_SECONDS = 15

local lastTick: { [Session]: number } = setmetatable({}, { __mode = "k" }) :: any

local function now(): number
	return workspace:GetServerTimeNow()
end

-- Makes sure the saved gifts are today's: pays what was unlocked but not claimed on the earlier day, then starts
-- today's ladder. Returns true when it started a new day.
local function ensureToday(session: Session): boolean
	local gifts = session.data.gifts
	local day = DailyStreak.dayIndex(os.time())
	if not GiftRules.isStale(gifts, day) then
		return false
	end
	if gifts.day >= 0 then
		for index in Gifts.ladder do
			local def = GiftRules.claim(gifts, Gifts, index)
			if def then
				PrizeService.pay(session, def.reward, "GiftAuto")
			end
		end
	end
	GiftRules.reset(gifts, day)
	Replication.markDirty(session)
	return true
end

-- Adds playtime to today's gifts (Studio /playtime, and the tick).
function GiftService.addPlaytime(session: Session, seconds: number)
	ensureToday(session)
	local gifts = session.data.gifts
	local before = GiftRules.claimable(gifts, Gifts)
	GiftRules.addTime(gifts, seconds)
	if GiftRules.claimable(gifts, Gifts) ~= before then
		Replication.markDirty(session) -- a gift just unlocked
	end
end

local function tick()
	local t = now()
	for _, session in Sessions.all() do
		if not session.ready then
			lastTick[session] = nil
			continue
		end
		local last = lastTick[session]
		lastTick[session] = t
		if last then
			GiftService.addPlaytime(session, math.clamp(t - last, 0, MAX_STEP_SECONDS))
		else
			ensureToday(session)
		end
	end
end

local function onClaim(player: Player, indexArg: unknown)
	local session = Sessions.get(player)
	local index = Guard.integer(indexArg, 1, 32)
	if session == nil or index == nil then
		return
	end
	ensureToday(session)
	local def = GiftRules.claim(session.data.gifts, Gifts, index)
	if def == nil then
		return
	end
	local result = PrizeService.pay(session, def.reward, "Gift")
	Remotes.notify(player, result.text, "success")
	Analytics.custom(session, "gift_claimed", index)
	Replication.markDirty(session)
end

function GiftService.start()
	for _, problem in GiftRules.validate(Gifts, GameData.catalog.mutations) do
		warn(`[Gifts] config problem: {problem}`)
	end
	Remotes.onIntent("ClaimGift", onClaim)
	task.spawn(function()
		while true do
			task.wait(TICK_SECONDS)
			local ok, err = pcall(tick :: () -> ...any)
			if not ok then
				warn(`[Gifts] {err}`)
			end
		end
	end)
end

return GiftService
