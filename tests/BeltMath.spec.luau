--!strict
local T = require("./TestKit")
local BeltMath = require("../src/shared/Logic/BeltMath")

local belt: BeltMath.Belt = { startX = -100, startZ = 0, dirX = 1, dirZ = 0, length = 200, travelSeconds = 20 }

T.describe("BeltMath", function()
	T.it("moves items at length / travelSeconds", function()
		T.expect(BeltMath.speed(belt)).toBe(10)
		local x, z = BeltMath.position(belt, 0, 5)
		T.expect(x).toBe(-50)
		T.expect(z).toBe(0)
	end)
	T.it("clamps before spawn and after the end", function()
		T.expect(BeltMath.along(belt, 10, 5)).toBe(0)
		T.expect(BeltMath.along(belt, 0, 999)).toBe(200)
	end)
	T.it("expires items at the end of the belt", function()
		T.expect(BeltMath.isExpired(belt, 0, 19.9)).toBe(false)
		T.expect(BeltMath.isExpired(belt, 0, 20)).toBe(true)
	end)
	T.it("measures distance from the player to the item, forgiving latency", function()
		-- at t=5 the item is at x=-50; the player stands at x=-55, 3 studs off the belt
		T.expect(BeltMath.distanceTo(belt, 0, 5, -55, 3, 0)).toBeNear(math.sqrt(25 + 9))
		-- with 0.5s tolerance the item passed x=-55 recently, so the distance is just the 3 stud offset
		T.expect(BeltMath.distanceTo(belt, 0, 5, -55, 3, 0.5)).toBeNear(3)
		-- far away players stay far away
		T.expect(BeltMath.distanceTo(belt, 0, 5, 50, 0, 0.75)).toBeGreaterThan(90)
	end)
end)

return nil
