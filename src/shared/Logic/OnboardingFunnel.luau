--!strict
--[[
	Order of the onboarding funnel (Creator Hub → Analytics → Funnels → Onboarding).

	Roblox counts a logged funnel step as completing every earlier step, so steps must be logged in increasing order:
	a milestone reached out of order (e.g. the first steal during the tutorial's collect step) is remembered and logged
	once every earlier step has been logged. Tutorial-only steps (`tutorialOnly`) stop blocking once the tutorial is
	over without them (skipped, an existing player, or the tutorial switched off): they are then never logged, and the
	later steps go on. Roblox still shows them as completed for such a player (DECISIONS.md #21).

	Saved in `data.flags`: `ob_<name>` once logged (the flag the funnel always used), `obr_<name>` while reached but
	waiting for an earlier step. Pure: no Roblox APIs.
]]

export type Flags = { [string]: boolean }

export type Step = { name: string, tutorialOnly: boolean }

local OnboardingFunnel = {}

-- Step number = position. Never renumber once the game is live (Roblox matches steps by number).
OnboardingFunnel.STEPS = {
	{ name = "Joined", tutorialOnly = false },
	{ name = "FirstBeltPurchase", tutorialOnly = false },
	{ name = "FirstCollect", tutorialOnly = false },
	{ name = "TutorialLock", tutorialOnly = true }, -- the tutorial moved past its lock step
	{ name = "TutorialComplete", tutorialOnly = true }, -- completed (and rewarded); never on a skip
	{ name = "FirstSteal", tutorialOnly = false },
	{ name = "FirstRebirth", tutorialOnly = false },
} :: { Step }

local function loggedFlag(name: string): string
	return "ob_" .. name
end

local function reachedFlag(name: string): string
	return "obr_" .. name
end

-- The step's number, or 0 for a name that is not a step.
function OnboardingFunnel.stepNumber(name: string, steps: { Step }): number
	for index, step in steps do
		if step.name == name then
			return index
		end
	end
	return 0
end

function OnboardingFunnel.isLogged(flags: Flags, name: string): boolean
	return flags[loggedFlag(name)] == true
end

-- Records that the player reached milestone `name`. Returns true the first time (ever) it is reached.
function OnboardingFunnel.reach(flags: Flags, name: string, steps: { Step }): boolean
	if OnboardingFunnel.stepNumber(name, steps) == 0 or flags[loggedFlag(name)] or flags[reachedFlag(name)] then
		return false
	end
	flags[reachedFlag(name)] = true
	return true
end

-- The step numbers to log now, in increasing order, and marks them logged: every reached step whose earlier steps
-- are all logged (or are tutorial-only steps skipped because the tutorial is over).
function OnboardingFunnel.due(flags: Flags, steps: { Step }, tutorialOver: boolean): { number }
	local due: { number } = {}
	for index, step in steps do
		if flags[loggedFlag(step.name)] then
			continue
		elseif flags[reachedFlag(step.name)] then
			flags[reachedFlag(step.name)] = nil
			flags[loggedFlag(step.name)] = true
			table.insert(due, index)
		elseif step.tutorialOnly and tutorialOver then
			continue -- never reached and never will be: doesn't hold the later steps back
		else
			break -- not reached yet: every later step waits for it
		end
	end
	return due
end

return OnboardingFunnel
