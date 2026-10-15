--!strict
-- The toast list's rules (Logic/ToastQueue, client NotificationController): nothing pushed out before 1.5 s, the
-- rest waiting in a short queue. Review 3: the tutorial's reward toast was thrown away unread on a phone.
local T = require("./TestKit")
local ToastQueue = require("../src/shared/Logic/ToastQueue")

local S = ToastQueue.SETTINGS

T.describe("ToastQueue.plan", function()
	T.it("shows a toast at once while there is room", function()
		T.expect(ToastQueue.plan({}, 3, 1, 10, S)).toEqual({ evict = 0, show = 1, retryIn = nil })
		T.expect(ToastQueue.plan({ 9, 9.5 }, 3, 2, 10, S)).toEqual({ evict = 0, show = 1, retryIn = 0.5 })
	end)

	T.it("never pushes out a toast that has shown for less than 1.5 s: the new one waits", function()
		local plan = ToastQueue.plan({ 9.2, 9.5, 9.9 }, 3, 1, 10, S)
		T.expect(plan.evict).toBe(0)
		T.expect(plan.show).toBe(0)
		T.expect(plan.retryIn).toBeNear(0.7, 1e-9) -- when the oldest has had its 1.5 s
	end)

	T.it("pushes out the oldest ones that have had their 1.5 s, one for each toast waiting", function()
		T.expect(ToastQueue.plan({ 8, 8.4, 9.9 }, 3, 1, 10, S)).toEqual({ evict = 1, show = 1, retryIn = nil })
		local two = ToastQueue.plan({ 8, 8.4, 9.9 }, 3, 3, 10, S)
		T.expect(two.evict).toBe(2)
		T.expect(two.show).toBe(2)
		T.expect(two.retryIn).toBeNear(1.4, 1e-9) -- the third waits for the newest
	end)

	T.it(
		"the tutorial's reward and four achievements on a three-toast phone: each is on screen 1.5 s or more",
		function()
			-- every toast arrives at t = 0, a 0.1 s pump loop runs them; record how long each one was on screen
			local queue: { ToastQueue.Item } = {}
			for index = 1, 5 do
				ToastQueue.enqueue(queue, { text = `toast {index}` }, S)
			end
			local screen: { { text: string, at: number } } = {}
			local onScreen: { [string]: number } = {}
			local t = 0
			while (#queue > 0 or #screen > 0) and t < 20 do
				-- a toast leaves by itself after 2.6 s
				for index = #screen, 1, -1 do
					if t - screen[index].at >= 2.6 then
						onScreen[screen[index].text] = t - screen[index].at
						table.remove(screen, index)
					end
				end
				local shownAt = {}
				for index, entry in screen do
					shownAt[index] = entry.at
				end
				local plan = ToastQueue.plan(shownAt, 3, #queue, t, S)
				for _ = 1, plan.evict do
					local gone = table.remove(screen, 1) :: { text: string, at: number }
					onScreen[gone.text] = t - gone.at
				end
				for _ = 1, plan.show do
					local item = table.remove(queue, 1) :: ToastQueue.Item
					table.insert(screen, { text = item.text, at = t })
				end
				t = math.floor((t + 0.1) * 10 + 0.5) / 10
			end
			for index = 1, 5 do
				T.expect(onScreen[`toast {index}`] or 0).toBeAtLeast(S.minSeconds)
			end
		end
	)

	T.it("a clock that went back counts as just shown; a screen with no room still shows one", function()
		T.expect(ToastQueue.plan({ 12 }, 1, 1, 10, S).evict).toBe(0)
		T.expect(ToastQueue.plan({}, 0, 2, 10, S).show).toBe(1)
	end)
end)

T.describe("ToastQueue.enqueue", function()
	T.it("waits oldest first, at most six, dropping the oldest waiting one", function()
		local queue: { ToastQueue.Item } = {}
		for index = 1, 8 do
			T.expect(ToastQueue.enqueue(queue, { text = `toast {index}`, kind = "info" }, S)).toBe(true)
		end
		T.expect(#queue).toBe(S.queueMax)
		T.expect(queue[1].text).toBe("toast 3")
		T.expect(queue[#queue].text).toBe("toast 8")
	end)

	T.it("doesn't queue the same text twice (a button tapped over and over)", function()
		local queue: { ToastQueue.Item } = {}
		T.expect(ToastQueue.enqueue(queue, { text = "Not enough cash!", kind = "error" }, S)).toBe(true)
		T.expect(ToastQueue.enqueue(queue, { text = "Not enough cash!", kind = "error" }, S)).toBe(false)
		T.expect(#queue).toBe(1)
	end)

	T.it("keeps the reviewer's numbers", function()
		T.expect(S.minSeconds).toBe(1.5)
		T.expect(S.queueMax).toBe(6)
	end)
end)

return nil
