--!strict
--[[
	Global rare-pull shout-outs (Config/Host.shoutouts; rules: Logic/CrossServerRules). When someone here finds a
	Secret Snackling, or a Mythic-or-rarer Diamond or Rainbow one, every other server shows a banner:
	"🌍 Bob found a SECRET Gelato Griffin in another server!".

	* What counts: the GameEvents "found" event, so the belt, a Lucky Spin, a playtime gift, a supply crate, a
	  runaway, a Snack Attack prize, an achievement or a code (kept, or sold because the base was full). Never a
	  steal, and never an admin drop (the admin chose it; every server may have one).
	* Sending: at most one every publishEverySeconds from this server (more are dropped, not queued), on the "shout"
	  channel (CrossServer), carrying only the finder's display name and the creature and mutation ids.
	* Showing: a server checks the ids against its own catalogue, builds the text itself, and shows at most one every
	  showEverySeconds, through the usual announcement banner (Announce, kind "shoutout"), to every player but those
	  in the first-time tutorial. Its own shout-outs come back as duplicates and are not shown here.
	* Studio: off (CrossServer never sends or listens there).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Host = require(ReplicatedStorage.Shared.Config.Host)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local GameData = require(ReplicatedStorage.Shared.GameData)
local CrossServerRules = require(ReplicatedStorage.Shared.Logic.CrossServerRules)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local CrossServer = require(script.Parent.CrossServer)
local GameEvents = require(script.Parent.GameEvents)
local Remotes = require(script.Parent.Remotes)
local Sessions = require(script.Parent.Sessions)

type Session = Sessions.Session

local ShoutoutService = {}

local config = Host.shoutouts
local catalog = GameData.catalog
local lastPublishedAt = -math.huge
local lastShownAt = -math.huge

local function now(): number
	return workspace:GetServerTimeNow()
end

local function onEvent(session: Session, event: GameEvents.Event)
	if event.kind ~= "found" or event.source == "adminDrop" or not config.enabled or not CrossServer.enabled() then
		return
	end
	local def = if event.creatureId then catalog.creatures[event.creatureId] else nil
	if def == nil or not CrossServerRules.isShoutworthy(def.rarity, event.variant, catalog.rarities, config) then
		return
	end
	local name = CrossServerRules.cleanName(session.player.DisplayName)
		or CrossServerRules.cleanName(session.player.Name)
	local t = now()
	if name == nil or not CrossServerRules.due(lastPublishedAt, t, config.publishEverySeconds) then
		return
	end
	lastPublishedAt = t
	CrossServer.publish(
		"shout",
		CrossServerRules.SHOUT_KIND,
		CrossServerRules.shoutArgs(name, def.id, event.variant),
		session.userId
	)
end

local function onShout(message: CrossServer.Message)
	if message.kind ~= CrossServerRules.SHOUT_KIND then
		return
	end
	local shout =
		CrossServerRules.readShout(message.args, catalog.creatures, catalog.mutations, catalog.rarities, config)
	local t = now()
	if shout == nil or not CrossServerRules.due(lastShownAt, t, config.showEverySeconds) then
		return
	end
	lastShownAt = t
	local def = catalog.creatures[shout.creatureId]
	local rarity = catalog.rarities[def.rarity]
	local mutation = GameData.mutation(shout.variant)
	local banner = {
		text = Format.template(Theme.text.shoutout, {
			player = shout.name,
			rarity = string.upper(rarity.displayName),
			creature = GameData.displayName(def, shout.variant),
		}),
		rarity = rarity.id,
		color = if mutation then mutation.color else nil,
		kind = "shoutout",
	}
	for _, session in Sessions.all() do
		if session.ready and session.tutorial == nil then
			Remotes.fire(session.player, "Announce", banner)
		end
	end
end

function ShoutoutService.start()
	GameEvents.on("ShoutoutService", onEvent)
	CrossServer.on("shout", onShout)
end

return ShoutoutService
