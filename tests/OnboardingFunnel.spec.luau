--!strict
local T = require("./TestKit")
local OnboardingFunnel = require("../src/shared/Logic/OnboardingFunnel")

local STEPS = OnboardingFunnel.STEPS

-- Reaches `name` and returns the step names logged as a result, in order.
local function reach(flags: OnboardingFunnel.Flags, name: string, tutorialOver: boolean): { string }
	OnboardingFunnel.reach(flags, name, STEPS)
	local names: { string } = {}
	for _, number in OnboardingFunnel.due(flags, STEPS, tutorialOver) do
		table.insert(names, STEPS[number].name)
	end
	return names
end

local function flush(flags: OnboardingFunnel.Flags, tutorialOver: boolean): { string }
	local names: { string } = {}
	for _, number in OnboardingFunnel.due(flags, STEPS, tutorialOver) do
		table.insert(names, STEPS[number].name)
	end
	return names
end

T.describe("OnboardingFunnel order", function()
	T.it("numbers the steps in tutorial order", function()
		local names: { string } = {}
		for _, step in STEPS do
			table.insert(names, step.name)
		end
		T.expect(names).toEqual({
			"Joined",
			"FirstBeltPurchase",
			"FirstCollect",
			"TutorialLock",
			"TutorialComplete",
			"FirstSteal",
			"FirstRebirth",
		})
		T.expect(OnboardingFunnel.stepNumber("TutorialComplete", STEPS)).toBe(5)
		T.expect(OnboardingFunnel.stepNumber("Nope", STEPS)).toBe(0)
	end)
	T.it("logs each step once, as it is reached in order", function()
		local flags: OnboardingFunnel.Flags = {}
		T.expect(reach(flags, "Joined", false)).toEqual({ "Joined" })
		T.expect(reach(flags, "Joined", false)).toEqual({})
		T.expect(OnboardingFunnel.reach(flags, "Joined", STEPS)).toBe(false) -- not the first time any more
		T.expect(reach(flags, "FirstBeltPurchase", false)).toEqual({ "FirstBeltPurchase" })
		T.expect(reach(flags, "FirstCollect", false)).toEqual({ "FirstCollect" })
		T.expect(reach(flags, "TutorialLock", false)).toEqual({ "TutorialLock" })
		T.expect(reach(flags, "TutorialComplete", true)).toEqual({ "TutorialComplete" })
		T.expect(reach(flags, "FirstSteal", true)).toEqual({ "FirstSteal" })
		T.expect(OnboardingFunnel.isLogged(flags, "FirstSteal")).toBe(true)
	end)
	T.it("holds a step reached early until every earlier step is logged", function()
		local flags: OnboardingFunnel.Flags = {}
		reach(flags, "Joined", false)
		reach(flags, "FirstBeltPurchase", false)
		-- locked and stole during the collect step
		T.expect(OnboardingFunnel.reach(flags, "TutorialLock", STEPS)).toBe(true) -- first time: custom events can fire
		T.expect(flush(flags, false)).toEqual({})
		T.expect(reach(flags, "FirstSteal", false)).toEqual({})
		T.expect(OnboardingFunnel.isLogged(flags, "FirstSteal")).toBe(false)
		T.expect(reach(flags, "FirstCollect", false)).toEqual({ "FirstCollect", "TutorialLock" })
		-- FirstSteal still waits for TutorialComplete while the tutorial runs
		T.expect(flush(flags, false)).toEqual({})
		T.expect(reach(flags, "TutorialComplete", true)).toEqual({ "TutorialComplete", "FirstSteal" })
	end)
	T.it("never logs FirstRebirth or FirstSteal ahead of a running tutorial", function()
		local flags: OnboardingFunnel.Flags = {}
		for _, name in { "Joined", "FirstBeltPurchase", "FirstCollect", "TutorialLock" } do
			reach(flags, name, false)
		end
		T.expect(reach(flags, "FirstRebirth", false)).toEqual({})
		T.expect(reach(flags, "FirstSteal", false)).toEqual({})
		T.expect(reach(flags, "TutorialComplete", true)).toEqual({ "TutorialComplete", "FirstSteal", "FirstRebirth" })
	end)
	T.it("lets later steps go once the tutorial is over without its steps (skipped / existing player)", function()
		local flags: OnboardingFunnel.Flags = {}
		for _, name in { "Joined", "FirstBeltPurchase", "FirstCollect" } do
			reach(flags, name, false)
		end
		T.expect(reach(flags, "FirstSteal", false)).toEqual({}) -- tutorial still running
		T.expect(flush(flags, true)).toEqual({ "FirstSteal" }) -- skipped: steps 4-5 are passed over, never logged
		T.expect(OnboardingFunnel.isLogged(flags, "TutorialLock")).toBe(false)
		T.expect(OnboardingFunnel.isLogged(flags, "TutorialComplete")).toBe(false)
	end)
	T.it("a regular step that isn't reached still holds the later ones back", function()
		local flags: OnboardingFunnel.Flags = {}
		reach(flags, "Joined", true)
		T.expect(reach(flags, "FirstSteal", true)).toEqual({}) -- stole before ever buying from the belt
		T.expect(reach(flags, "FirstBeltPurchase", true)).toEqual({ "FirstBeltPurchase" })
		T.expect(reach(flags, "FirstCollect", true)).toEqual({ "FirstCollect", "FirstSteal" })
	end)
	T.it("keeps steps logged before (ob_ flags) and ignores unknown names", function()
		local flags: OnboardingFunnel.Flags = { ob_Joined = true, ob_FirstBeltPurchase = true }
		T.expect(OnboardingFunnel.reach(flags, "FirstBeltPurchase", STEPS)).toBe(false)
		T.expect(reach(flags, "FirstCollect", false)).toEqual({ "FirstCollect" })
		T.expect(OnboardingFunnel.reach(flags, "Dance", STEPS)).toBe(false)
		T.expect(flags["obr_Dance"]).toBeNil()
		-- a reached step's waiting flag is cleared once it is logged
		T.expect(flags["obr_FirstCollect"]).toBeNil()
	end)
end)

return nil
