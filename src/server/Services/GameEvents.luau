--!strict
--[[
	Gameplay events the server saw, for the systems that react to what players do: the first-time tutorial, daily
	quests and the Snackdex. The service that applied an action emits it right after applying it, so listeners only
	ever see real, validated gameplay (no client message can emit one).

	  beltPurchase  a Snackling was bought from the belt (creatureId, variant)       BeltService
	  acquired      a Snackling landed in the player's base: bought, stolen or        EconomyService.giveCreature,
	                any other way (creatureId, variant)                               StealService (delivery)
	  collect       cash collected from a pad, not from selling (amount)             EconomyService (pad check)
	  sell          a Snackling was sold (creatureId, variant)                        EconomyService
	  lock          the base was locked (Instant Lock included)                       LockService
	  steal         a steal was delivered (creatureId, variant)                       StealService
	  discover      a new Snackdex entry: a new Snackling, or a new mutation of one   SnackdexService
	                (creatureId, variant)

	Listeners run at once, in the order they subscribed (the bootstrap starts TutorialService first), each in its own
	pcall: a listener's bug can only ever cost that listener, never the gameplay code that emitted the event or the
	other listeners. A listener may emit further events (the Snackdex emits "discover" while handling "acquired").
]]

local Sessions = require(script.Parent.Sessions)

type Session = Sessions.Session

export type Kind = "beltPurchase" | "acquired" | "collect" | "sell" | "lock" | "steal" | "discover"

export type Event = {
	kind: Kind,
	creatureId: string?,
	variant: string?, -- mutation id, nil for a plain Snackling
	amount: number?, -- cash, for "collect"
}

export type Listener = (session: Session, event: Event) -> ()

local GameEvents = {}

local listeners: { { name: string, listener: Listener } } = {}

-- Subscribes `listener` to every event; `name` labels its warnings.
function GameEvents.on(name: string, listener: Listener)
	table.insert(listeners, { name = name, listener = listener })
end

-- Tells every listener that `session`'s player just did something. Never throws.
function GameEvents.emit(session: Session, event: Event)
	for _, entry in listeners do
		local ok, err = pcall(entry.listener :: (Session, Event) -> ...any, session, event)
		if not ok then
			warn(`[GameEvents] {entry.name} failed on {event.kind} for {session.player.Name}: {err}`)
		end
	end
end

return GameEvents
