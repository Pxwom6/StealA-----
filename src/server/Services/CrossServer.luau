--!strict
--[[
	Messages between servers over MessagingService (Config/Host.messaging; rules: Logic/CrossServerRules). Two
	channels, each on its own topic: "host" (admin actions sent to All servers, HostService) and "shout" (rare-pull
	shout-outs, ShoutoutService), so a busy evening of shout-outs can never crowd out an admin's message.

	  publish  wraps the args in one versioned message (kind, args, the sender's UserId, a GUID, the server time),
	           remembers its id first (MessagingService delivers the sender's own copy too, and the caller has
	           already acted on it here, so that copy is a duplicate), then sends it as JSON in the background;
	           `onDone(ok)` says whether it went out.
	  receive  decodes the JSON, keeps only messages of this version and shape, at most receiveBurst /
	           receivePerMinute per channel, none older than maxAgeSeconds and none seen before, then calls the
	           channel's handler. Handlers validate the args again (HostRules.command, CrossServerRules.readShout).

	Every MessagingService call is pcall'd. Subscribing retries quietly in the background (5 s, 10 s, ... up to
	60 s) and warns once. Studio never subscribes or publishes: with Studio API access on, a test session would
	otherwise reach every live server (DECISIONS #15). HostService runs "All servers" there in this server only and
	says so.
]]

local HttpService = game:GetService("HttpService")
local MessagingService = game:GetService("MessagingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Host = require(ReplicatedStorage.Shared.Config.Host)
local CrossServerRules = require(ReplicatedStorage.Shared.Logic.CrossServerRules)
local RateLimiter = require(ReplicatedStorage.Shared.Logic.RateLimiter)

export type Channel = "host" | "shout"
export type Message = CrossServerRules.Message
export type Handler = (message: Message) -> ()

local CrossServer = {}

local config = Host.messaging
local TOPICS: { [string]: string } = { host = config.hostTopic, shout = config.shoutTopic }
local CHANNELS: { string } = { "host", "shout" }

local handlers: { [string]: Handler } = {}
local subscribed: { [string]: boolean } = {}
local seen = CrossServerRules.newSeen()
-- Timed on the server clock (both caps are per minute; a stalled server never gets a burst for it).
local sendLimiter = RateLimiter.new(config.sendBurst, config.sendPerMinute / 60)
local receiveLimiter = RateLimiter.new(config.receiveBurst, config.receivePerMinute / 60)

local function now(): number
	return workspace:GetServerTimeNow()
end

-- Whether messages can leave or reach this server at all (never in Studio).
function CrossServer.enabled(): boolean
	return not RunService:IsStudio()
end

-- Whether this server is listening on `channel` yet.
function CrossServer.subscribed(channel: Channel): boolean
	return subscribed[channel] == true
end

-- `handler` gets every accepted message on `channel` (one handler per channel).
function CrossServer.on(channel: Channel, handler: Handler)
	handlers[channel] = handler
end

-- Takes one of this server's sends for an admin action (Config/Host.messaging send caps); false when none is left
-- right now.
function CrossServer.trySend(): boolean
	return RateLimiter.allow(sendLimiter, "host", now())
end

-- Sends `kind` with `args` to every server. This server's own copy is ignored: the caller acts here itself. Returns
-- the message id, or nil when nothing was sent (Studio, or a message too big to send). `onDone(ok)` runs once it went
-- out or failed.
function CrossServer.publish(
	channel: Channel,
	kind: string,
	args: CrossServerRules.Args,
	from: number,
	onDone: ((ok: boolean) -> ())?
): string?
	if not CrossServer.enabled() then
		return nil
	end
	local t = now()
	local id = HttpService:GenerateGUID(false)
	local message = CrossServerRules.message(kind, args, from, id, t, config.version)
	local encodedOk, encoded = pcall(function(): string
		return HttpService:JSONEncode(message)
	end)
	if not encodedOk or #encoded > config.maxBytes then
		warn(`[CrossServer] {kind} not sent: it doesn't fit in one message`)
		return nil
	end
	CrossServerRules.remember(seen, id, t, config.rememberIds, CrossServerRules.keepSeconds(config))
	task.spawn(function()
		local ok, err = pcall(function()
			MessagingService:PublishAsync(TOPICS[channel], encoded)
		end)
		if not ok then
			warn(`[CrossServer] could not send {kind} to the other servers: {err}`)
		end
		if onDone then
			onDone(ok)
		end
	end)
	return id
end

-- A message as it arrived on `channel`'s topic (MessagingService's { Data, Sent }).
local function receive(channel: string, packet: unknown)
	local data: unknown = if type(packet) == "table" then (packet :: any).Data else nil
	local raw: unknown = data
	if type(data) == "string" then
		local ok, decoded = pcall(function(): any
			return HttpService:JSONDecode(data)
		end)
		if not ok then
			return
		end
		raw = decoded
	end
	local message = CrossServerRules.decode(raw, config.version)
	-- This server's own copies are dropped before they can use up the receive cap.
	if message == nil or CrossServerRules.hasSeen(seen, message.id) then
		return
	end
	local t = now()
	if
		not RateLimiter.allow(receiveLimiter, channel, t)
		or CrossServerRules.accept(seen, message, t, config) ~= nil
	then
		return
	end
	local handler = handlers[channel]
	if handler then
		local ok, err = pcall(handler :: (Message) -> ...any, message)
		if not ok then
			warn(`[CrossServer] {channel} handler failed on {message.kind}: {err}`)
		end
	end
end

local function subscribe(channel: string)
	local attempt = 0
	while true do
		attempt += 1
		local ok, err = pcall(function()
			MessagingService:SubscribeAsync(TOPICS[channel], function(packet: any)
				receive(channel, packet)
			end)
		end)
		if ok then
			subscribed[channel] = true
			if attempt > 1 then
				print(`[CrossServer] listening for {channel} messages after {attempt} attempts`)
			end
			return
		end
		if attempt == 1 then
			warn(`[CrossServer] could not listen for {channel} messages, retrying quietly in the background: {err}`)
		end
		task.wait(math.min(60, 5 * 2 ^ (attempt - 1)))
	end
end

function CrossServer.start()
	if not CrossServer.enabled() then
		return
	end
	for _, channel in CHANNELS do
		task.spawn(subscribe, channel)
	end
end

return CrossServer
