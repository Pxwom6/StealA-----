--!strict
--[[
	The toast list's rules (client NotificationController): which toasts on screen may be pushed out for a newer one,
	and which newer ones wait. Pure: no Roblox APIs; times are seconds on one clock (the client uses os.clock()).

	  * A toast on screen is never pushed out before it has shown for `minSeconds`: the tutorial's "You're ready!"
	    (or anything else worth saying) is read before a burst of others replaces it. It still leaves by itself after
	    its own time.
	  * While the list is full of toasts that haven't had that long, newer ones wait in a queue, oldest first, at
	    most `queueMax`; past that the oldest waiting one is dropped. A text already waiting isn't queued again (a
	    button tapped over and over).
]]

export type Item = { text: string, kind: string? }
export type Settings = { minSeconds: number, queueMax: number }

-- What to do now: push out the `evict` oldest toasts on screen, then show the `show` oldest waiting ones; `retryIn`:
-- seconds until another waiting toast may show (nil: none waits, or only a toast leaving by itself makes room).
export type Plan = { evict: number, show: number, retryIn: number? }

local ToastQueue = {}

ToastQueue.SETTINGS = table.freeze({ minSeconds = 1.5, queueMax = 6 }) :: Settings

-- Adds `item` to the waiting `queue` (in place). Returns false when it was left out (the same text already waits).
function ToastQueue.enqueue(queue: { Item }, item: Item, settings: Settings): boolean
	for _, waiting in queue do
		if waiting.text == item.text then
			return false
		end
	end
	table.insert(queue, item)
	while #queue > math.max(1, settings.queueMax) do
		table.remove(queue, 1)
	end
	return true
end

-- `shownAt`: when each toast on screen appeared, oldest first; `room`: how many fit on this screen (at least one);
-- `waiting`: how many are queued; `now`: the clock `shownAt` is on.
function ToastQueue.plan(shownAt: { number }, room: number, waiting: number, now: number, settings: Settings): Plan
	local free = math.max(0, math.max(1, room) - #shownAt)
	local show = math.min(free, waiting)
	local left = waiting - show
	local evict = 0
	while left > 0 and evict < #shownAt do
		local age = now - shownAt[evict + 1]
		if not (age >= settings.minSeconds) then -- (a clock that went back counts as just shown)
			break
		end
		evict += 1
		left -= 1
	end
	local retryIn: number? = nil
	if left > 0 and evict < #shownAt then
		local age = now - shownAt[evict + 1]
		retryIn = if age == age
			then math.clamp(settings.minSeconds - age, 0, settings.minSeconds)
			else settings.minSeconds
	end
	return { evict = evict, show = show + evict, retryIn = retryIn }
end

return ToastQueue
