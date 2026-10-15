--!strict
--[[
	Messages between servers (MessagingService; server/Services/CrossServer): admin actions sent to "All servers" and
	rare-pull shout-outs. Pure: no Roblox APIs; the clock is passed in.

	A message is one small versioned table, sent as JSON:
	  { v = 1, kind = "luck", args = { multiplier = 2, minutes = 15 }, from = 723735722, id = "<GUID>", at = 1.8e9 }
	(`from` is the sender's UserId, `at` the server time it was sent). `decode` accepts only that shape: the version
	must match and every field must have the right type and be small; args keep plain strings, numbers and booleans
	under short keys and nothing else. `accept` then drops a message older than maxAgeSeconds (or dated more than
	maxFutureSeconds ahead) and one whose id was seen before, and remembers the id (a bounded list). So every server
	acts on each message once, the sender's included: the sender remembers its own id before publishing and acts
	straight away, and its copy coming back is a duplicate.

	Shout-outs (Config/Host.shoutouts): `isShoutworthy` says which finds count, `due` is both rate limits (a server
	publishes at most one every publishEverySeconds and shows at most one every showEverySeconds), and a shout-out's
	args are only the finder's display name and the creature and mutation ids (each receiver builds the text from its
	own catalogue, so another server can never put words on the screen).
]]

local Types = require("../Types")

export type Args = { [string]: string | number | boolean }

export type Message = {
	v: number,
	kind: string,
	args: Args,
	from: number, -- the sender's UserId
	id: string, -- a GUID
	at: number, -- server time it was sent
}

-- Message ids seen recently: when, and in what order (oldest first).
export type Seen = { at: { [string]: number }, order: { string } }

-- A shout-out as it arrived: who found what.
export type Shout = { name: string, creatureId: string, variant: string? }

local CrossServerRules = {}

CrossServerRules.MAX_KIND = 32
CrossServerRules.MAX_ARGS = 8
CrossServerRules.MAX_KEY = 16
CrossServerRules.MAX_STRING = 500 -- bytes: a 120-character message of 4-byte characters fits
CrossServerRules.NAME_LENGTH = 20 -- Roblox display names have at most 20 characters
-- A shout-out shows at most this many characters of the name, so it reads at 12 UI or more in the narrowest banner
-- even for a name of 20 capital Ws (tests/HostPanelLayout.spec.luau).
CrossServerRules.SHOUT_NAME_LENGTH = 15
CrossServerRules.SHOUT_KIND = "shoutout"

local function finite(value: unknown): number?
	if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
		return value
	end
	return nil
end

function CrossServerRules.message(
	kind: string,
	args: Args,
	from: number,
	id: string,
	at: number,
	version: number
): Message
	return { v = version, kind = kind, args = args, from = from, id = id, at = at }
end

-- Only plain strings, numbers and booleans under short string keys, a few of them; anything else and the whole
-- message is refused.
local function cleanArgs(raw: unknown): Args?
	if raw == nil then
		return {}
	end
	if type(raw) ~= "table" then
		return nil
	end
	local args: Args = {}
	local count = 0
	for key, value in raw :: { [any]: any } do
		count += 1
		if count > CrossServerRules.MAX_ARGS then
			return nil
		end
		if type(key) ~= "string" or #key == 0 or #key > CrossServerRules.MAX_KEY then
			return nil
		end
		if type(value) == "string" then
			if #value > CrossServerRules.MAX_STRING then
				return nil
			end
			args[key] = value
		elseif type(value) == "number" then
			local n = finite(value)
			if n == nil then
				return nil
			end
			args[key] = n
		elseif type(value) == "boolean" then
			args[key] = value
		else
			return nil
		end
	end
	return args
end

-- The message in `raw` (a table decoded from JSON), or nil when it isn't one of ours in this version.
function CrossServerRules.decode(raw: unknown, version: number): Message?
	if type(raw) ~= "table" then
		return nil
	end
	local fields = raw :: { [any]: any }
	if fields.v ~= version then
		return nil
	end
	local kind = fields.kind
	if type(kind) ~= "string" or #kind == 0 or #kind > CrossServerRules.MAX_KIND then
		return nil
	end
	local from = finite(fields.from)
	if from == nil or from ~= math.floor(from) then
		return nil
	end
	local id = fields.id
	if type(id) ~= "string" or #id < 8 or #id > 64 then
		return nil
	end
	local at = finite(fields.at)
	if at == nil then
		return nil
	end
	local args = cleanArgs(fields.args)
	if args == nil then
		return nil
	end
	return { v = version, kind = kind, args = args, from = from, id = id, at = at }
end

-- Dedupe and expiry -----------------------------------------------------------------------------------------------

function CrossServerRules.newSeen(): Seen
	return { at = {}, order = {} }
end

function CrossServerRules.hasSeen(seen: Seen, id: string): boolean
	return seen.at[id] ~= nil
end

-- Remembers `id` (seen at `now`), then forgets the oldest ids beyond `limit` and any older than `keepSeconds`.
function CrossServerRules.remember(seen: Seen, id: string, now: number, limit: number, keepSeconds: number)
	if seen.at[id] == nil then
		table.insert(seen.order, id)
	end
	seen.at[id] = now
	while #seen.order > 0 do
		local oldest = seen.order[1]
		local when = seen.at[oldest] or now
		if #seen.order <= limit and now - when <= keepSeconds then
			break
		end
		table.remove(seen.order, 1)
		seen.at[oldest] = nil
	end
end

-- How long an id is worth remembering: a copy can't be accepted once the message is too old anyway.
function CrossServerRules.keepSeconds(config: Types.HostMessaging): number
	return config.maxAgeSeconds + config.maxFutureSeconds + 5
end

-- Why `message` should be ignored now ("stale", "future", "duplicate"), or nil when it should be acted on; an
-- accepted message's id is remembered, so a copy of it is a duplicate.
function CrossServerRules.accept(seen: Seen, message: Message, now: number, config: Types.HostMessaging): string?
	local age = now - message.at
	if age > config.maxAgeSeconds then
		return "stale"
	elseif -age > config.maxFutureSeconds then
		return "future"
	elseif CrossServerRules.hasSeen(seen, message.id) then
		return "duplicate"
	end
	CrossServerRules.remember(seen, message.id, now, config.rememberIds, CrossServerRules.keepSeconds(config))
	return nil
end

-- Shout-outs ------------------------------------------------------------------------------------------------------

-- Whether finding a `rarityId` Snackling with mutation `variant` (nil = plain) is worth telling every server.
function CrossServerRules.isShoutworthy(
	rarityId: string,
	variant: string?,
	rarities: { [string]: Types.RarityDef },
	config: Types.HostShoutouts
): boolean
	local rarity = rarities[rarityId]
	if rarity == nil then
		return false
	end
	local top = rarities[config.rarity]
	if top ~= nil and rarity.order >= top.order then
		return true
	end
	local mutated = rarities[config.mutatedRarity]
	return variant ~= nil
		and mutated ~= nil
		and rarity.order >= mutated.order
		and table.find(config.mutations, variant) ~= nil
end

-- Whether a rate-limited thing last done at `lastAt` may happen again at `now`.
function CrossServerRules.due(lastAt: number, now: number, everySeconds: number): boolean
	return now - lastAt >= everySeconds
end

-- A display name to show: control characters removed, trimmed, at most NAME_LENGTH characters; nil if empty.
function CrossServerRules.cleanName(value: unknown): string?
	if type(value) ~= "string" or #value > CrossServerRules.NAME_LENGTH * 4 or utf8.len(value) == nil then
		return nil
	end
	local stripped = string.gsub(value, "%c", "")
	local name = string.match(stripped, "^%s*(.-)%s*$") or ""
	local length = utf8.len(name)
	if length == nil or length == 0 or length > CrossServerRules.NAME_LENGTH then
		return nil
	end
	return name
end

-- `name` cut to `maxLength` characters: a longer one keeps its first maxLength - 1 and ends in "…".
function CrossServerRules.shortName(name: string, maxLength: number): string
	local length = utf8.len(name)
	if length == nil or length <= maxLength then
		return name
	end
	local cut = utf8.offset(name, maxLength)
	return if cut then string.sub(name, 1, cut - 1) .. "…" else name
end

function CrossServerRules.shoutArgs(name: string, creatureId: string, variant: string?): Args
	local args: Args = { name = name, creature = creatureId }
	if variant then
		args.mutation = variant
	end
	return args
end

-- The shout-out in `args`, checked against this server's catalogue (a creature and mutation it knows, and still
-- worth a shout-out here), or nil.
function CrossServerRules.readShout(
	args: Args,
	creatures: { [string]: Types.CreatureDef },
	mutations: { [string]: Types.MutationDef },
	rarities: { [string]: Types.RarityDef },
	config: Types.HostShoutouts
): Shout?
	local name = CrossServerRules.cleanName(args.name)
	local creatureId = args.creature
	if name == nil or type(creatureId) ~= "string" or creatures[creatureId] == nil then
		return nil
	end
	local variant: string? = nil
	local mutation = args.mutation
	if mutation ~= nil then
		if type(mutation) ~= "string" or mutations[mutation] == nil then
			return nil
		end
		variant = mutation
	end
	if not CrossServerRules.isShoutworthy(creatures[creatureId].rarity, variant, rarities, config) then
		return nil
	end
	return { name = name, creatureId = creatureId, variant = variant }
end

return CrossServerRules
