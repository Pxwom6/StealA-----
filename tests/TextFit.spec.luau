--!strict
local T = require("./TestKit")
local TextFit = require("../src/shared/Logic/TextFit")

T.describe("TextFit", function()
	T.it("measures FredokaOne's advance widths", function()
		-- "Hi" = H 699 + i 255 per mille of an em
		T.expect(TextFit.width("Hi", 10)).toBeNear(9.54, 1e-9)
		T.expect(TextFit.width("", 10)).toBe(0)
		T.expect(TextFit.width(" ", 1000)).toBe(253)
		-- emoji and symbols are wide; variation selectors take no room
		T.expect(TextFit.width("✨", 10)).toBeNear(12, 1e-9)
		T.expect(TextFit.width("☄️", 10)).toBeNear(12, 1e-9)
		T.expect(TextFit.width("·", 1000)).toBe(237)
	end)
	T.it("wraps greedily at spaces and refuses a word wider than the box", function()
		-- "aa" is 11.92 wide at size 10, a space 2.53
		T.expect(TextFit.wrap("aa aa aa", 10, 27)).toEqual({ "aa aa", "aa" })
		T.expect(TextFit.wrap("aa aa aa", 10, 13)).toEqual({ "aa", "aa", "aa" })
		T.expect(TextFit.wrap("one", 10, 5)).toBeNil()
		T.expect(TextFit.wrap("a\nb", 10, 100)).toEqual({ "a", "b" })
		T.expect(TextFit.lineCount("aa aa aa", 10, 27)).toBe(2)
		T.expect(TextFit.lineCount("one", 10, 5)).toBe(math.huge)
	end)
	T.it("picks the size TextScaled would: the largest whole size that fits", function()
		local w = TextFit.width("Hello", 1)
		T.expect(TextFit.fit("Hello", w * 20, 100, false)).toBe(20)
		T.expect(TextFit.fit("Hello", w * 20 - 0.01, 100, false)).toBe(19)
		-- limited by the height: one line is 1.21 em tall
		T.expect(TextFit.fit("Hello", 1000, 24.3, false)).toBe(20)
		T.expect(TextFit.fit("Hello", 1000, 1000, false, 28)).toBe(28)
		T.expect(TextFit.fit("Hello", 0, 10, false)).toBe(0)
		-- wrapping lets a long line grow into two
		local one = TextFit.fit("Cherry Blossom Garden", 100, 40, false)
		local two = TextFit.fit("Cherry Blossom Garden", 100, 40, true)
		T.expect(two).toBeGreaterThan(one)
		T.expect(TextFit.fits("Cherry Blossom Garden", two, 100, 40, true)).toBe(true)
		T.expect(TextFit.fits("Cherry Blossom Garden", two + 1, 100, 40, true)).toBe(false)
	end)
	T.it("agrees with the UI reviewer's measurements of the old HUD", function()
		-- the old vote card gave a map name one 77 x 16 line; the reviewer measured 5.7 px at UI scale 0.85
		T.expect(TextFit.fit("Cherry Blossom Garden", 76.7, 16, false) * 0.85).toBeLessThan(7)
		-- an old one-line toast (324 x 32): "No spins yet: ..." 9.5 px
		local spin = TextFit.fit("No spins yet: one is free every 12 hours, and gifts give more.", 324, 32, false)
		T.expect(spin * 0.85).toBeLessThan(10)
	end)
end)

return nil
