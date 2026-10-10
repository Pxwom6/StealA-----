--!strict
local T = require("./TestKit")
local IdleMotion = require("../src/shared/Logic/IdleMotion")

T.describe("IdleMotion", function()
	T.it("podium: a small bob, squash, sway and turn, scaled to the model", function()
		local cfg = IdleMotion.PODIUM
		for _, height in { 1, 3, 7, 40 } do
			local maxLift = math.min(cfg.lift * height, cfg.maxLift)
			for i = 0, 400 do
				local pose = IdleMotion.podium(i * 0.037, (i % 7) / 7, height)
				T.expect(pose.lift).toBeAtLeast(0)
				T.expect(pose.lift).toBeAtMost(maxLift + 1e-9)
				T.expect(math.abs(pose.squash)).toBeAtMost(cfg.squash + 1e-9)
				T.expect(math.abs(pose.roll)).toBeAtMost(cfg.roll + 1e-9)
				T.expect(math.abs(pose.yaw)).toBeAtMost(cfg.yaw + 1e-9)
			end
		end
	end)

	T.it("podium: squashed at the bottom of the bob, stretched at the top", function()
		local height = 4
		local lowest, highest = math.huge, -math.huge
		local squashLow, squashHigh = 0, 0
		for i = 0, 1000 do
			local pose = IdleMotion.podium(i * 0.01, 0.3, height)
			if pose.lift < lowest then
				lowest, squashLow = pose.lift, pose.squash
			end
			if pose.lift > highest then
				highest, squashHigh = pose.lift, pose.squash
			end
		end
		T.expect(squashLow).toBeLessThan(-0.03)
		T.expect(squashHigh).toBeGreaterThan(0.03)
	end)

	T.it("podium: moves smoothly (no jumps between frames)", function()
		local previous = IdleMotion.podium(0, 0.5, 5)
		for i = 1, 600 do
			local pose = IdleMotion.podium(i / 60, 0.5, 5)
			T.expect(math.abs(pose.lift - previous.lift)).toBeLessThan(0.02)
			T.expect(math.abs(pose.squash - previous.squash)).toBeLessThan(0.01)
			T.expect(math.abs(pose.roll - previous.roll)).toBeLessThan(0.01)
			previous = pose
		end
	end)

	T.it("podium: different phases are out of step", function()
		local a = IdleMotion.podium(10, 0.1, 3)
		local b = IdleMotion.podium(10, 0.6, 3)
		T.expect(math.abs(a.lift - b.lift) + math.abs(a.squash - b.squash)).toBeGreaterThan(0.001)
	end)

	T.it("belt: hops, squashes when it lands, stretches in the air, waddles side to side", function()
		local cfg = IdleMotion.BELT
		local period = 1 / cfg.hopsPerSecond
		for i = 0, 300 do
			local pose = IdleMotion.belt(i * 0.013, 0.25)
			T.expect(pose.lift).toBeAtLeast(0)
			T.expect(pose.lift).toBeAtMost(cfg.height + 1e-9)
			T.expect(math.abs(pose.roll)).toBeAtMost(cfg.roll + 1e-9)
		end
		local landing = IdleMotion.belt(period * 3 + 0.001, 0)
		T.expect(landing.lift).toBeLessThan(0.01)
		T.expect(landing.squash).toBeLessThan(-0.05)
		local top = IdleMotion.belt(period * 3.5, 0)
		T.expect(top.lift).toBeNear(cfg.height, 1e-6)
		T.expect(top.squash).toBeGreaterThan(0)
		local nextTop = IdleMotion.belt(period * 4.5, 0)
		T.expect(top.roll * nextTop.roll).toBeLessThan(0)
	end)

	T.it("turns any number into a phase between 0 and 1", function()
		for _, n in { 0, 1, 2, 17, 12345, -3 } do
			local phase = IdleMotion.phaseOf(n)
			T.expect(phase).toBeAtLeast(0)
			T.expect(phase).toBeLessThan(1)
		end
		T.expect(IdleMotion.phaseOf(5) ~= IdleMotion.phaseOf(6)).toBe(true)
	end)
end)

return nil
