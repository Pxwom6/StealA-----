--!strict
--[[
	The Lucky Spin (Config/Spin; rules: Logic/SpinRules). Spin uses the free spin when it is ready (its 12-hour timer
	starts again), else a banked one; the server picks the prize by weight, pays it at once (PrizeService) and tells
	the client which segment won (SpinResult { index, text }) so its reel can stop there and then show the toast. One
	spin at a time per player (the reel takes a few seconds). A jackpot or a Diamond Snackling is announced to the
	server. Snackling prizes roll with fixed odds (PrizeService.rollFixed): banked spins may have been bought (Lucky
	Spin packs, paid random items), and every outcome's chance is listed in the Spin tab (Logic/SpinOdds).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Spin = require(ReplicatedStorage.Shared.Config.Spin)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local GameData = require(ReplicatedStorage.Shared.GameData)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local SpinRules = require(ReplicatedStorage.Shared.Logic.SpinRules)
local Analytics = require(script.Parent.Analytics)
local Announcer = require(script.Parent.Announcer)
local PrizeService = require(script.Parent.PrizeService)
local Remotes = require(script.Parent.Remotes)
local Replication = require(script.Parent.Replication)
local Sessions = require(script.Parent.Sessions)

local SpinService = {}

-- How long the client's reel runs (SpinTab); a new spin before it stops is ignored.
SpinService.REEL_SECONDS = 4
-- Segments announced to the whole server when won.
local ANNOUNCED: { [string]: boolean } = { jackpot = true, diamond = true }

local random = Random.new()
local busyUntil: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any

local function onSpin(player: Player)
	local session = Sessions.get(player)
	if session == nil or (busyUntil[player] or 0) > os.clock() then
		return
	end
	local state = session.data.spin
	local now = os.time()
	local source: SpinRules.Source? = SpinRules.source(state, now)
	if source == nil then
		Remotes.notify(player, Theme.text.spinNotReady, "error")
		return
	end
	SpinRules.consume(state, source, now, Spin)
	local index = SpinRules.pick(Spin.segments, function(): number
		return random:NextNumber()
	end)
	local segment = Spin.segments[index]
	busyUntil[player] = os.clock() + SpinService.REEL_SECONDS
	-- fixed odds: exactly what the Odds view's Details list shows (Logic/SpinOdds), whatever luck or event is live
	local result = PrizeService.pay(session, segment.reward, "Spin", true)
	Remotes.fire(player, "SpinResult", { index = index, text = result.text })
	Analytics.custom(session, "lucky_spin", nil, { segment.id, source })
	if ANNOUNCED[segment.id] then
		local creature = if result.creatureId then GameData.catalog.creatures[result.creatureId] else nil
		Announcer.broadcast({
			text = Format.template(Theme.text.spinAnnounce, {
				player = player.DisplayName,
				prize = if creature then GameData.displayName(creature, result.variant) else segment.label,
			}),
			color = segment.color,
			kind = "spin",
		})
	end
	Replication.markDirty(session)
end

function SpinService.start()
	for _, problem in SpinRules.validate(Spin, GameData.catalog.mutations) do
		warn(`[Spin] config problem: {problem}`)
	end
	Remotes.onIntent("Spin", onSpin)
end

return SpinService
