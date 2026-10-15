--!strict
--[[
	The host panel's rules (Config/Host): who may host, which actions exist, what their arguments may be, and the
	cooldowns. Pure: no Roblox APIs and no clock; the config, the known ids and the time are passed in.

	Roles (HostRules.role):
	  "admin"  in Config/LiveOps.adminUserIds, or anyone in Studio
	  "owner"  the private server's owner: PrivateServerId ~= "" and PrivateServerOwnerId == their UserId
	           (PrivateServerOwnerId is 0 in reserved servers, which have no owner)
	  "none"   everyone else: every action is refused

	Actions (HostRules.ACTIONS; any other kind is refused):
	  mapSwitch    { id = map }                 admin; owner (cooldown "map", as long as the rotation's turn)
	  mapVote      {}                           admin
	  mapRotation  { on = boolean }             admin; owner. Always this server only.
	  modStart     { id = modifier, minutes? }  admin; owner if the modifier is hostable and nothing runs but the
	                                            owner's own (cooldown "modifier")
	  modStop      {}                           admin; owner if the owner started the running modifier
	  beltDrop     { id = creature, mutation? } admin: an admin drop on the belt, announced
	  luck         { multiplier?, minutes? }    admin
	  eventStart   { id = event, minutes? }     admin (no minutes: the event's own durationSeconds)
	  eventStop    { id? }                      admin (no id: every event started this way)
	  gift         { minutes? }                 admin (cooldown "gift"): everyone gets minutes of their own income
	  broadcast    { text }                     admin (Roblox filters it before anyone sees it)
	Owners never act on "All servers".

	`command` turns what arrived (an intent's arguments, or a message from another server) into a Command with every
	field checked: ids must be known, numbers finite and clamped to Config/Host.limits (the /mod, /luck and /event
	limits), text trimmed, without control characters and short. The same function runs on both, so a message from
	another server is validated again when it arrives.
]]

local EconomyMath = require("./EconomyMath")
local Types = require("../Types")

export type Role = "admin" | "owner" | "none"
export type Scope = "server" | "all"

export type Command = {
	kind: string, -- a key of HostRules.ACTIONS
	id: string?, -- the map, modifier, creature or event
	mutation: string?, -- beltDrop: the mutation (nil = plain)
	minutes: number?,
	multiplier: number?,
	on: boolean?, -- mapRotation
	text: string?, -- broadcast
}

-- The ids a command may name.
export type Known = {
	maps: { [string]: Types.MapThemeDef },
	modifiers: { [string]: Types.ModifierDef },
	creatures: { [string]: Types.CreatureDef },
	mutations: { [string]: Types.MutationDef },
	events: { [string]: boolean }, -- configured LiveOps event ids
}

export type ActionDef = {
	owner: boolean, -- a private server's owner may use it (in their own server)
	localOnly: boolean, -- always this server, whatever scope was asked for
}

-- Cooldown group -> server time it is ready again.
export type Cooldowns = { [string]: number }

export type RoleInput = {
	userId: number,
	studio: boolean,
	admins: { number },
	privateServerId: string,
	privateServerOwnerId: number,
}

local HostRules = {}

HostRules.ACTIONS = {
	mapSwitch = { owner = true, localOnly = false },
	mapVote = { owner = false, localOnly = false },
	mapRotation = { owner = true, localOnly = true },
	modStart = { owner = true, localOnly = false },
	modStop = { owner = true, localOnly = false },
	beltDrop = { owner = false, localOnly = false },
	luck = { owner = false, localOnly = false },
	eventStart = { owner = false, localOnly = false },
	eventStop = { owner = false, localOnly = false },
	gift = { owner = false, localOnly = false },
	broadcast = { owner = false, localOnly = false },
} :: { [string]: ActionDef }

-- Every action, in the order the panel shows them.
HostRules.ORDER = {
	"mapSwitch",
	"mapVote",
	"mapRotation",
	"modStart",
	"modStop",
	"beltDrop",
	"luck",
	"eventStart",
	"eventStop",
	"gift",
	"broadcast",
} :: { string }

-- Refusals `check` can give (each has a Theme.text line: "hostRefused" .. the key with its first letter upper case).
HostRules.REFUSALS = { "notAllowed", "adminOnly", "notHostable", "notYours" } :: { string }

function HostRules.role(input: RoleInput): Role
	if input.studio or table.find(input.admins, input.userId) ~= nil then
		return "admin"
	end
	if
		input.privateServerId ~= ""
		and input.privateServerOwnerId ~= 0
		and input.privateServerOwnerId == input.userId
	then
		return "owner"
	end
	return "none"
end

function HostRules.scope(value: unknown): Scope?
	if value == "server" then
		return "server"
	elseif value == "all" then
		return "all"
	end
	return nil
end

-- Argument checks ---------------------------------------------------------------------------------------------------

local function finite(value: unknown): number?
	if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
		return value
	end
	return nil
end

-- A number argument. Missing: the range's default (nil when it has none). Present: finite, clamped into the range
-- and rounded to 1 / perUnit (4 = quarter minutes, 10 = tenths, 1 = whole); anything else is invalid (ok = false).
local function ranged(value: unknown, range: Types.HostRange, perUnit: number): (number?, boolean)
	if value == nil then
		return range.default, true
	end
	local n = finite(value)
	if n == nil then
		return nil, false
	end
	local rounded = math.floor(math.clamp(n, range.min, range.max) * perUnit + 0.5) / perUnit
	return math.clamp(rounded, range.min, range.max), true
end

local function knownId(value: unknown, known: { [string]: any }): string?
	if type(value) == "string" and #value > 0 and #value <= 64 and known[value] ~= nil then
		return value
	end
	return nil
end

-- Text for everyone to read: valid UTF-8, control characters (new lines...) turned into spaces, trimmed, 1 to
-- `maxLength` characters.
function HostRules.cleanText(value: unknown, maxLength: number): string?
	if type(value) ~= "string" or #value > maxLength * 4 or utf8.len(value) == nil then
		return nil
	end
	local spaced = string.gsub(value, "%c", " ")
	local text = string.match(spaced, "^%s*(.-)%s*$") or ""
	local length = utf8.len(text)
	if length == nil or length == 0 or length > maxLength then
		return nil
	end
	return text
end

-- The command `kindArg` with `argsArg` (a table of fields, or nil), checked and normalised; nil when the kind is not
-- an action or any argument is missing, unknown or the wrong type.
function HostRules.command(kindArg: unknown, argsArg: unknown, known: Known, config: Types.HostConfig): Command?
	if type(kindArg) ~= "string" or HostRules.ACTIONS[kindArg] == nil then
		return nil
	end
	if argsArg ~= nil and type(argsArg) ~= "table" then
		return nil
	end
	-- `kind` goes into the command; `is` is what the branches compare (a comparison narrows its variable to one
	-- literal, which a Command's `kind: string` would not accept).
	local kind: string = kindArg
	local is: string = kindArg
	local args: { [any]: any } = if type(argsArg) == "table" then argsArg :: any else {}
	local limits = config.limits

	if is == "mapSwitch" then
		local id = knownId(args.id, known.maps)
		return if id then { kind = kind, id = id } else nil
	elseif is == "mapVote" or is == "modStop" then
		return { kind = kind }
	elseif is == "mapRotation" then
		local on = args.on
		return if type(on) == "boolean" then { kind = kind, on = on } else nil
	elseif is == "modStart" then
		local id = knownId(args.id, known.modifiers)
		local minutes, ok = ranged(args.minutes, limits.modifierMinutes, 4)
		return if id and ok and minutes then { kind = kind, id = id, minutes = minutes } else nil
	elseif is == "beltDrop" then
		local id = knownId(args.id, known.creatures)
		local mutation: string? = nil
		if args.mutation ~= nil and args.mutation ~= "" then
			mutation = knownId(args.mutation, known.mutations)
			if mutation == nil then
				return nil
			end
		end
		return if id then { kind = kind, id = id, mutation = mutation } else nil
	elseif is == "luck" then
		local multiplier, multiplierOk = ranged(args.multiplier, limits.luckMultiplier, 10)
		local minutes, minutesOk = ranged(args.minutes, limits.luckMinutes, 1)
		if multiplier and minutes and multiplierOk and minutesOk then
			return { kind = kind, multiplier = multiplier, minutes = minutes }
		end
		return nil
	elseif is == "eventStart" then
		local id = knownId(args.id, known.events)
		local minutes, ok = ranged(args.minutes, limits.eventMinutes, 1)
		return if id and ok then { kind = kind, id = id, minutes = minutes } else nil
	elseif is == "eventStop" then
		if args.id == nil or args.id == "" then
			return { kind = kind }
		end
		local id = knownId(args.id, known.events)
		return if id then { kind = kind, id = id } else nil
	elseif is == "gift" then
		local minutes, ok = ranged(args.minutes, limits.giftMinutes, 1)
		return if ok and minutes then { kind = kind, minutes = minutes } else nil
	elseif is == "broadcast" then
		local text = HostRules.cleanText(args.text, limits.broadcastLength)
		return if text then { kind = kind, text = text } else nil
	end
	return nil
end

-- The fields of `command` sent to other servers (its kind travels beside them).
function HostRules.args(command: Command): { [string]: string | number | boolean }
	local args: { [string]: string | number | boolean } = {}
	if command.id then
		args.id = command.id
	end
	if command.mutation then
		args.mutation = command.mutation
	end
	if command.minutes then
		args.minutes = command.minutes
	end
	if command.multiplier then
		args.multiplier = command.multiplier
	end
	if command.on ~= nil then
		args.on = command.on
	end
	if command.text then
		args.text = command.text
	end
	return args
end

-- Permissions -----------------------------------------------------------------------------------------------------

local function hostable(modifiers: { [string]: Types.ModifierDef }, id: string?): boolean
	local def = if id then modifiers[id] else nil
	return def ~= nil and def.hostable == true
end

-- Why `role` may not run `command` for `scope` (a HostRules.REFUSALS key), or nil when it may. `running` is the
-- modifier running now, `runningIsOwners` whether this server's owner started it. An owner may start a hostable
-- modifier when none runs or over their own, and stop only their own: the random schedule's (and an admin's) run to
-- their end, so an owner can't cut them short to roll the next one sooner.
function HostRules.check(
	role: Role,
	command: Command,
	scope: Scope,
	modifiers: { [string]: Types.ModifierDef },
	running: string?,
	runningIsOwners: boolean?
): string?
	if role == "admin" then
		return nil
	elseif role ~= "owner" then
		return "notAllowed"
	end
	local def = HostRules.ACTIONS[command.kind]
	if def == nil or not def.owner or scope == "all" then
		return "adminOnly"
	end
	local someoneElses = running ~= nil and runningIsOwners ~= true
	if command.kind == "modStart" then
		if not hostable(modifiers, command.id) then
			return "notHostable"
		elseif someoneElses then
			return "notYours"
		end
	elseif command.kind == "modStop" and someoneElses then
		return "notYours"
	end
	return nil
end

-- Where `command` applies: `scope`, except that per-server actions (rotation) always stay in this server.
function HostRules.effectiveScope(command: Command, scope: Scope): Scope
	local def = HostRules.ACTIONS[command.kind]
	return if def and def.localOnly then "server" else scope
end

-- Cooldowns -------------------------------------------------------------------------------------------------------

-- The cooldown `kind` starts for `role`: its group and length in seconds, or nil.
function HostRules.cooldown(role: Role, kind: string, config: Types.HostConfig): (string?, number)
	if role == "owner" then
		if kind == "mapSwitch" then
			return "map", config.owner.mapCooldownSeconds
		elseif kind == "modStart" then
			return "modifier", config.owner.modifierCooldownSeconds
		end
	elseif role == "admin" and kind == "gift" then
		return "gift", config.admin.giftCooldownSeconds
	end
	return nil, 0
end

-- Seconds left before `group` is ready again (0 = ready).
function HostRules.waitSeconds(cooldowns: Cooldowns, group: string, now: number): number
	return math.max(0, (cooldowns[group] or 0) - now)
end

function HostRules.startCooldown(cooldowns: Cooldowns, group: string, seconds: number, now: number)
	cooldowns[group] = now + seconds
end

-- What a player's client is told (StateUpdate `host`).
function HostRules.view(role: Role, studio: boolean, cooldowns: Cooldowns): Types.HostView
	return {
		role = if role == "none" then "" else role,
		studio = studio,
		mapReadyAt = cooldowns.map or 0,
		modifierReadyAt = cooldowns.modifier or 0,
		giftReadyAt = cooldowns.gift or 0,
	}
end

-- What "Gift everyone" pays a player: `minutes` of their steady income, like a cash pack (never below
-- minutes x gift.minimumPerMinute).
function HostRules.giftAmount(packIncome: number, minutes: number, config: Types.HostConfig): number
	return EconomyMath.cashPackAmount(
		packIncome,
		{ incomeSeconds = minutes * 60, minimum = minutes * config.gift.minimumPerMinute }
	)
end

-- Config checks -----------------------------------------------------------------------------------------------------

-- Problems with the modifiers marked hostable: a private server's owner may only start ones that leave the economy
-- alone. `unlocks` are the modifiers some mutation only rolls during (Config/Mutations modifierId: the weathers).
function HostRules.hostableProblems(config: Types.ModifiersConfig, unlocks: { [string]: boolean }): { string }
	local problems: { string } = {}
	local count = 0
	for _, id in config.order do
		local def = config.modifiers[id]
		if def == nil or def.hostable ~= true then
			continue
		end
		count += 1
		local effects = def.effects
		local name = `hostable modifier {id}`
		if (effects.luck or 1) > 1 then
			table.insert(problems, `{name} raises luck`)
		end
		if (effects.mutationChance or 1) > 1 then
			table.insert(problems, `{name} raises mutation chances`)
		end
		if (effects.income or 1) > 1 then
			table.insert(problems, `{name} raises income`)
		end
		if (effects.beltPrice or 1) < 1 then
			table.insert(problems, `{name} cuts belt prices`)
		end
		if (effects.spawnInterval or 1) < 1 then
			table.insert(problems, `{name} speeds up the belt (more rare spawns an hour)`)
		end
		if def.drops ~= nil then
			table.insert(problems, `{name} drops things`)
		end
		if unlocks[id] then
			table.insert(problems, `{name} unlocks a mutation`)
		end
	end
	if count == 0 then
		table.insert(problems, "no modifier is hostable: private-server owners would have none to start")
	end
	return problems
end

local function rangeProblems(name: string, range: Types.HostRange, presets: { number }?, problems: { string })
	if not (range.min > 0 and range.min <= range.max) then
		table.insert(problems, `limits.{name} needs 0 < min <= max`)
	end
	local default = range.default
	if default ~= nil and not (default >= range.min and default <= range.max) then
		table.insert(problems, `limits.{name} default must be inside min..max`)
	end
	if presets then
		if #presets == 0 then
			table.insert(problems, `presets.{name} is empty`)
		end
		for index, value in presets do
			if not (value >= range.min and value <= range.max) then
				table.insert(problems, `presets.{name} {value} is outside limits.{name}`)
			end
			if index > 1 and not (value > presets[index - 1]) then
				table.insert(problems, `presets.{name} must go up`)
			end
		end
	end
end

-- Problems with Config/Host (CI and the server's start both run it). `maxLuckMultiplier` is LiveOps' luck cap.
function HostRules.validate(config: Types.HostConfig, maxLuckMultiplier: number): { string }
	local problems: { string } = {}
	local limits, presets = config.limits, config.presets
	rangeProblems("modifierMinutes", limits.modifierMinutes, presets.modifierMinutes, problems)
	rangeProblems("luckMultiplier", limits.luckMultiplier, presets.luckMultiplier, problems)
	rangeProblems("luckMinutes", limits.luckMinutes, presets.luckMinutes, problems)
	rangeProblems("eventMinutes", limits.eventMinutes, presets.eventMinutes, problems)
	rangeProblems("giftMinutes", limits.giftMinutes, presets.giftMinutes, problems)
	if limits.luckMultiplier.min < 1 or limits.luckMultiplier.max > maxLuckMultiplier then
		table.insert(problems, `limits.luckMultiplier must stay within 1..{maxLuckMultiplier} (LiveOps luck cap)`)
	end
	if limits.modifierMinutes.default == nil or limits.giftMinutes.default == nil then
		table.insert(problems, "limits.modifierMinutes and limits.giftMinutes need a default")
	end
	if limits.luckMultiplier.default == nil or limits.luckMinutes.default == nil then
		table.insert(problems, "limits.luckMultiplier and limits.luckMinutes need a default (/luck with no numbers)")
	end
	if not (limits.broadcastLength >= 1 and limits.broadcastLength <= 200) then
		table.insert(problems, "limits.broadcastLength must be 1..200")
	end
	if not (config.owner.mapCooldownSeconds > 0 and config.owner.modifierCooldownSeconds > 0) then
		table.insert(problems, "owner cooldowns must be above 0")
	end
	if not (config.admin.giftCooldownSeconds >= 0) then
		table.insert(problems, "admin.giftCooldownSeconds must be 0 or more")
	end
	if not (config.gift.minimumPerMinute >= 0) then
		table.insert(problems, "gift.minimumPerMinute must be 0 or more")
	end

	local m = config.messaging
	if m.hostTopic == "" or m.shoutTopic == "" or m.hostTopic == m.shoutTopic or #m.hostTopic > 80 then
		table.insert(problems, "messaging topics must be two different non-empty names")
	end
	if not (m.version >= 1 and m.version == math.floor(m.version)) then
		table.insert(problems, "messaging.version must be a whole number from 1")
	end
	if not (m.maxAgeSeconds > 0 and m.maxFutureSeconds >= 0) then
		table.insert(problems, "messaging.maxAgeSeconds must be above 0 (and maxFutureSeconds 0 or more)")
	end
	if not (m.rememberIds >= 16) then
		table.insert(problems, "messaging.rememberIds must be at least 16")
	end
	if not (m.maxBytes >= 200 and m.maxBytes <= 1000) then
		table.insert(problems, "messaging.maxBytes must be 200..1000 (Roblox allows 1 KB a message)")
	end
	if not (m.sendBurst >= 1 and m.sendPerMinute > 0 and m.receiveBurst >= 1 and m.receivePerMinute > 0) then
		table.insert(problems, "messaging send / receive caps must allow at least one message")
	end

	local s = config.shoutouts
	if not (s.publishEverySeconds >= 1 and s.showEverySeconds >= 1) then
		table.insert(problems, "shoutouts publish / show intervals must be at least 1 s")
	end
	if #s.mutations == 0 then
		table.insert(problems, "shoutouts.mutations is empty")
	end
	return problems
end

return HostRules
