--!strict
--[[
	The host panel (Config/Host; rules: Logic/HostRules), checked here. Admins and a private server's owner open it
	from Settings; the client only sends intents.

	One intent, HostAction(kind, scope, args): `kind` one of HostRules.ACTIONS, `scope` "server" or "all", `args` a
	table of fields (id, mutation, minutes, multiplier, on, text). It is rate-limited (Config/Gameplay.rateLimits),
	refused silently for anyone who may host nothing, and otherwise:
	  1. HostRules.command checks every argument (known ids, finite numbers clamped to the /mod, /luck and /event
	     limits, short clean text) and HostRules.check the role: admins anything, owners only the map, rotation and
	     hostable modifiers in their own server, nobody else nothing.
	  2. A broadcast is filtered by Roblox first (the only step that yields, before any check that it could undo).
	  3. The cooldown (owners: map 60 s, modifier 10 min; admins: gifts 30 s) and, for "All servers", this server's
	     send cap are checked and taken; then the action runs here at once through the services that own it
	     (MapThemeService, ModifierService, BeltService, LiveOpsService, EconomyService, Announcer) and is logged as
	     the analytics custom event host_action (01 the action, 02 "admin" | "admin_all" | "owner", 03 the map,
	     modifier, Snackling or event id, or ""; value: its minutes or multiplier).
	  4. "All servers": CrossServer publishes it; every other server validates it again (HostRules.command, and the
	     sender must be an admin) and runs it once. If publishing fails it has still run here, and the admin is told
	     so. In Studio it never leaves the session (and says so).

	The admin chat commands are thin parsers onto the same path, for every server as they always were: /luck
	<multiplier> <minutes>, /event <id> [minutes], /event off [id], /announce <text>. (/map and /mod stay in their
	services, this server only.)

	Cooldowns are kept per UserId for the server's life, so leaving and rejoining doesn't reset them. Each player's
	role and cooldowns reach their client in StateUpdate `host` (session.host), which shows or hides the Settings row.
	In Studio everyone is an admin; `/hostas owner|none|admin` (DevCommands) tries the panel as another role.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local Host = require(ReplicatedStorage.Shared.Config.Host)
local LiveOps = require(ReplicatedStorage.Shared.Config.LiveOps)
local MapThemes = require(ReplicatedStorage.Shared.Config.MapThemes)
local Modifiers = require(ReplicatedStorage.Shared.Config.Modifiers)
local Mutations = require(ReplicatedStorage.Shared.Config.Mutations)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local GameData = require(ReplicatedStorage.Shared.GameData)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local HostRules = require(ReplicatedStorage.Shared.Logic.HostRules)
local Analytics = require(script.Parent.Analytics)
local BeltService = require(script.Parent.BeltService)
local CrossServer = require(script.Parent.CrossServer)
local EconomyService = require(script.Parent.EconomyService)
local LiveOpsService = require(script.Parent.LiveOpsService)
local MapThemeService = require(script.Parent.MapThemeService)
local ModifierService = require(script.Parent.ModifierService)
local Remotes = require(script.Parent.Remotes)
local Replication = require(script.Parent.Replication)
local Sessions = require(script.Parent.Sessions)

type Session = Sessions.Session
type Command = HostRules.Command

local HostService = {}

local cooldowns: { [number]: HostRules.Cooldowns } = {} -- by UserId, for the server's life
local devRoles: { [number]: HostRules.Role } = {} -- Studio only: /hostas

local function now(): number
	return workspace:GetServerTimeNow()
end

local function isStudio(): boolean
	return RunService:IsStudio()
end

-- What `userId` may host in this server.
function HostService.role(userId: number): HostRules.Role
	local devRole = devRoles[userId]
	if isStudio() and devRole ~= nil then
		return devRole :: HostRules.Role
	end
	return HostRules.role({
		userId = userId,
		studio = isStudio(),
		admins = LiveOps.adminUserIds,
		privateServerId = game.PrivateServerId,
		privateServerOwnerId = game.PrivateServerOwnerId,
	})
end

local function cooldownsOf(userId: number): HostRules.Cooldowns
	local list = cooldowns[userId]
	if list == nil then
		list = {}
		cooldowns[userId] = list
	end
	return list
end

-- Tells `session`'s client what it may host (StateUpdate `host`). Runs on join and whenever a cooldown starts.
function HostService.refresh(session: Session)
	local view = HostRules.view(HostService.role(session.userId), isStudio(), cooldowns[session.userId] or {})
	session.host = if view.role == "" then nil else view
	Replication.markDirty(session)
end

-- Studio only: try the panel as `role` (nil: back to the real one, an admin in Studio).
function HostService.devSetRole(session: Session, role: HostRules.Role?)
	if not isStudio() then
		return
	end
	if role then
		devRoles[session.userId] = role
	else
		devRoles[session.userId] = nil
	end
	HostService.refresh(session)
end

-- The ids a command may name right now.
local function known(): HostRules.Known
	return {
		maps = MapThemes.themes,
		modifiers = Modifiers.modifiers,
		creatures = GameData.catalog.creatures,
		mutations = GameData.catalog.mutations,
		events = LiveOpsService.configuredEventIds(),
	}
end

local function notify(session: Session?, text: string, kind: string?)
	if session and Sessions.get(session.player) == session then
		Remotes.notify(session.player, text, kind or "info")
	end
end

-- Every player gets `minutes` of their own steady income (HostRules.giftAmount). Returns how many were paid.
local function giftEveryone(minutes: number): number
	local count = 0
	for _, session in Sessions.all() do
		local amount = HostRules.giftAmount(session.packIncome, minutes, Host)
		EconomyService.addCash(session, amount, "Gameplay", "HostGift")
		Remotes.notify(
			session.player,
			Format.template(Theme.text.hostGiftReceived, { amount = UiTheme.cash(amount) }),
			"success"
		)
		count += 1
	end
	return count
end

-- Runs a checked command in this server, through the services that own each thing. `actor` (nil for a message from
-- another server) hears how it went when there is nothing else to see; `role` is who sent it.
local function apply(command: Command, actor: Session?, role: HostRules.Role)
	local kind = command.kind
	if kind == "mapSwitch" and command.id then
		MapThemeService.switchTo(command.id, true)
	elseif kind == "mapVote" then
		MapThemeService.openVote(nil)
		notify(actor, Theme.text.hostVoteStarted)
	elseif kind == "mapRotation" then
		MapThemeService.setRotation(command.on == true)
		notify(
			actor,
			if command.on
				then Format.template(Theme.text.hostRotationNowOn, { minutes = MapThemes.rotation.mapSeconds // 60 })
				else Theme.text.hostRotationNowOff
		)
	elseif kind == "modStart" and command.id and command.minutes then
		-- an owner's is theirs to stop or change (HostRules.check)
		ModifierService.startModifier(
			command.id,
			command.minutes * 60,
			true,
			if role == "owner" then "owner" else "admin"
		)
	elseif kind == "modStop" then
		if ModifierService.current() == nil then
			notify(actor, Theme.text.hostModNoneRunning)
		else
			ModifierService.stopModifier()
			notify(actor, Theme.text.hostModStopped)
		end
	elseif kind == "beltDrop" and command.id then
		BeltService.adminDrop(command.id, command.mutation)
	elseif kind == "luck" and command.multiplier and command.minutes then
		LiveOpsService.startLuck(command.multiplier, command.minutes)
	elseif kind == "eventStart" and command.id then
		-- a seasonal event ends any other seasonal one (one at a time, LiveOpsService)
		local started, ended = LiveOpsService.startEvent(command.id, command.minutes)
		if started then
			notify(
				actor,
				if #ended > 0
					then Format.template(
						Theme.text.hostEventReplaced,
						{ event = command.id, ended = table.concat(ended, ", ") }
					)
					else Format.template(Theme.text.hostEventStarted, { event = command.id }),
				"success"
			)
		end
	elseif kind == "eventStop" then
		local ended = LiveOpsService.endEvents(command.id)
		notify(actor, Format.template(Theme.text.hostEventsEnded, { count = ended }))
	elseif kind == "gift" and command.minutes then
		local count = giftEveryone(command.minutes)
		notify(actor, Format.template(Theme.text.hostGiftSent, { count = count }))
	elseif kind == "broadcast" and command.text then
		LiveOpsService.announce(command.text)
		notify(actor, Theme.text.hostBroadcastSent)
	end
end

local function log(session: Session, role: HostRules.Role, command: Command, scope: HostRules.Scope)
	local who = if role == "owner" then "owner" elseif scope == "all" then "admin_all" else "admin"
	Analytics.custom(
		session,
		"host_action",
		command.minutes or command.multiplier,
		{ command.kind, who, command.id or "" }
	)
end

-- Runs `command` for `session`'s player as `role`, in `scope`: checks it, starts its cooldown, runs it here and, for
-- "All servers", sends it to every other server. A broadcast is filtered first (that yields); from the cooldown check
-- on nothing yields until it has run here.
function HostService.run(session: Session, role: HostRules.Role, command: Command, requested: HostRules.Scope)
	local refusal = HostRules.check(
		role,
		command,
		requested,
		Modifiers.modifiers,
		ModifierService.current(),
		ModifierService.startedBy() == "owner"
	)
	if refusal then
		local key = "hostRefused" .. string.upper(string.sub(refusal, 1, 1)) .. string.sub(refusal, 2)
		notify(session, UiTheme.text(key), "error")
		return
	end
	local scope: HostRules.Scope = HostRules.effectiveScope(command, requested)
	if command.kind == "broadcast" and command.text then
		-- Text everyone reads goes through Roblox's filter, even from admins.
		local filtered = LiveOpsService.filterForBroadcast(command.text, session.userId)
		if Sessions.get(session.player) ~= session then
			return -- left while it was filtered
		end
		if filtered == nil then
			notify(session, Theme.text.hostFilterFailed, "error")
			return
		end
		command.text = filtered
	end

	local t = now()
	local list = cooldownsOf(session.userId)
	local group, seconds = HostRules.cooldown(role, command.kind, Host)
	if group then
		local wait = HostRules.waitSeconds(list, group, t)
		if wait > 0 then
			notify(session, Format.template(Theme.text.hostWait, { time = Format.duration(math.ceil(wait)) }), "error")
			return
		end
	end
	local global = scope == "all" and CrossServer.enabled()
	if global and not CrossServer.trySend() then
		notify(session, Theme.text.hostAllBusy, "error")
		return
	end
	if group then
		HostRules.startCooldown(list, group, seconds, t)
		HostService.refresh(session)
	end
	apply(command, session, role)
	log(session, role, command, scope :: HostRules.Scope)

	if scope == "all" and not global then
		notify(session, Theme.text.hostStudioLocal)
	elseif global then
		local id = CrossServer.publish(
			"host",
			command.kind,
			HostRules.args(command),
			session.userId,
			function(ok: boolean)
				notify(
					session,
					if ok then Theme.text.hostSentAll else Theme.text.hostAllFailed,
					if ok then "success" else "error"
				)
			end
		)
		if id == nil then
			notify(session, Theme.text.hostAllFailed, "error")
		end
	end
end

local function onHostAction(player: Player, kindArg: unknown, scopeArg: unknown, argsArg: unknown)
	local session = Sessions.get(player)
	if session == nil then
		return
	end
	local role = HostService.role(session.userId)
	if role == "none" then
		return -- nobody else has the panel: nothing to say to whoever sent this
	end
	local scope = HostRules.scope(scopeArg)
	local command = if scope then HostRules.command(kindArg, argsArg, known(), Host) else nil
	if scope == nil or command == nil then
		notify(session, Theme.text.hostInvalid, "error")
		return
	end
	HostService.run(session, role :: HostRules.Role, command, scope :: HostRules.Scope)
end

-- An admin action from another server: only an admin can have sent it, and it is checked again here.
local function onRemote(message: CrossServer.Message)
	if table.find(LiveOps.adminUserIds, message.from) == nil then
		return
	end
	local command = HostRules.command(message.kind, message.args, known(), Host)
	if command == nil or HostRules.effectiveScope(command, "all") ~= "all" then
		return
	end
	apply(command, nil, "admin")
end

-- Chat commands (admins; every server, as they always were) ---------------------------------------------------------

-- The first `count` characters of `text` (never half a character), or nil when it isn't valid UTF-8.
local function firstCharacters(text: string, count: number): string?
	local length = utf8.len(text)
	if length == nil then
		return nil
	end
	if length <= count then
		return text
	end
	local cut = utf8.offset(text, count + 1)
	return if cut then string.sub(text, 1, cut - 1) else text
end

local function addCommand(alias: string, parse: (args: { string }, rawArgs: string) -> Command?)
	local command = Instance.new("TextChatCommand")
	command.Name = "LiveOps" .. alias
	command.PrimaryAlias = "/" .. alias
	command.AutocompleteVisible = false
	command.Parent = TextChatService
	command.Triggered:Connect(function(source: TextSource, text: string)
		local player = Players:GetPlayerByUserId(source.UserId)
		local session = if player then Sessions.get(player) else nil
		if session == nil or HostService.role(source.UserId) ~= "admin" then
			return
		end
		local rawArgs = string.match(text, "^%S+%s*(.*)$") or ""
		local args: { string } = {}
		for word in string.gmatch(rawArgs, "%S+") do
			table.insert(args, word)
		end
		local parsed = parse(args, rawArgs)
		if parsed == nil then
			notify(session, Theme.text.hostInvalid, "error")
			return
		end
		HostService.run(session, "admin", parsed, "all")
	end)
end

local function addCommands()
	-- /luck <multiplier> <minutes>   (2x for 15 minutes when left out)
	addCommand("luck", function(args: { string }): Command?
		return HostRules.command("luck", { multiplier = tonumber(args[1]), minutes = tonumber(args[2]) }, known(), Host)
	end)
	-- /event <eventId> [minutes]   start a configured event now (for its durationSeconds, or `minutes`)
	-- /event off [eventId]         end the events started this way (all of them, or just that one)
	addCommand("event", function(args: { string }): Command?
		local first = args[1]
		if first == nil then
			return nil
		elseif string.lower(first) == "off" then
			return HostRules.command("eventStop", { id = args[2] }, known(), Host)
		end
		return HostRules.command("eventStart", { id = first, minutes = tonumber(args[2]) }, known(), Host)
	end)
	-- /announce <text>   (filtered, at most Config/Host.limits.broadcastLength characters)
	addCommand("announce", function(_args: { string }, rawArgs: string): Command?
		local text = firstCharacters(rawArgs, Host.limits.broadcastLength)
		return if text then HostRules.command("broadcast", { text = text }, known(), Host) else nil
	end)
end

function HostService.start()
	local unlocks: { [string]: boolean } = {}
	for _, mutation in Mutations do
		if mutation.modifierId then
			unlocks[mutation.modifierId] = true
		end
	end
	for _, problem in HostRules.validate(Host, LiveOps.limits.maxLuckMultiplier) do
		warn(`[Host] config problem: {problem}`)
	end
	for _, problem in HostRules.hostableProblems(Modifiers, unlocks) do
		warn(`[Host] config problem: {problem}`)
	end
	Remotes.onIntent("HostAction", onHostAction)
	CrossServer.on("host", onRemote)
	addCommands()
end

return HostService
