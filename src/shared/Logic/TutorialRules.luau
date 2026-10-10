--!strict
--[[
	First-time player tutorial rules (Config/Tutorial).

	Progress is saved in the existing `data.flags` map (no save-format change): one flag per finished step
	(`tutorial_buy`, ...) and `tutorial_done` once the tutorial is over (completed, skipped, or the player already had
	progress when it shipped). The current step is the first configured step whose flag is not set, so a step whose
	action was done early (e.g. locking during the collect step) is skipped when it comes up, and a rejoin resumes
	where the player left off. The reward is paid only by `finish` with "completed", and only the first time the done
	flag is set (the flag is set before the amount is returned, so the caller pays with no yield in between).

	Pure: no Roblox APIs. Times are server timestamps in seconds.
]]

local Types = require("../Types")

export type Flags = { [string]: boolean }
export type StepDef = Types.TutorialStepDef
export type Config = Types.TutorialConfig

-- "new": start from the first step. "resume": a tutorial in progress. "done": already over. "returning": an existing
-- player from before the tutorial (treat as done, no reward). "off": the tutorial is disabled.
export type JoinStatus = "new" | "resume" | "done" | "returning" | "off"

-- How a step ended: its action ("done"), its action done before the step came up ("early"), its action unavailable
-- for too long ("unavailable"), or its time ran out ("timeout").
export type StepOutcome = "done" | "early" | "unavailable" | "timeout"

-- How the tutorial ended. Only "completed" pays the reward.
export type FinishReason = "completed" | "skipped" | "returning"

-- A belt item the "buy" guide could point at: its price at the server's rules, ground position and time left.
export type BeltCandidate = { id: number, price: number, x: number, z: number, secondsLeft: number }

-- One of the player's podiums for the "collect" guide.
export type PodiumCandidate = { index: number, occupied: boolean, stored: number }

local TutorialRules = {}

TutorialRules.DONE_FLAG = "tutorial_done"

-- Banner text (Theme.text key) per step. Every configured step id must have one (CI).
TutorialRules.TEXT_KEYS = {
	buy = "tutorialBuy",
	collect = "tutorialCollect",
	lock = "tutorialLock",
	steal = "tutorialSteal",
} :: { [string]: string }

function TutorialRules.stepFlag(stepId: string): string
	return "tutorial_" .. stepId
end

function TutorialRules.isDone(flags: Flags): boolean
	return flags[TutorialRules.DONE_FLAG] == true
end

-- True when the save shows the player already played before the tutorial existed (or found their own way around
-- the loop before ever starting it): anything owned, bought, stolen or rebirthed.
function TutorialRules.hasProgress(data: Types.PlayerData): boolean
	return #data.creatures > 0
		or #data.quarantine > 0
		or data.rebirths > 0
		or data.stats.beltPurchases > 0
		or data.stats.steals > 0
end

function TutorialRules.joinStatus(data: Types.PlayerData, cfg: Config): JoinStatus
	local flags = data.flags
	if TutorialRules.isDone(flags) then
		return "done"
	elseif not cfg.enabled then
		return "off"
	end
	for _, step in cfg.steps do
		if flags[TutorialRules.stepFlag(step.id)] then
			return "resume" -- step flags only exist for players who started the tutorial
		end
	end
	return if TutorialRules.hasProgress(data) then "returning" else "new"
end

-- The step the player is on and its 1-based index, or nil (and 0) when the tutorial is over or every step is done.
function TutorialRules.currentStep(flags: Flags, cfg: Config): (StepDef?, number)
	if TutorialRules.isDone(flags) then
		return nil, 0
	end
	for index, step in cfg.steps do
		if not flags[TutorialRules.stepFlag(step.id)] then
			return step, index
		end
	end
	return nil, 0
end

function TutorialRules.stepIndex(stepId: string, cfg: Config): number
	for index, step in cfg.steps do
		if step.id == stepId then
			return index
		end
	end
	return 0
end

-- Records that the player did `action` (a step id) while the tutorial runs. Returns true when that step was not
-- finished yet (and now is); false for unknown actions, finished steps or a tutorial that is over.
function TutorialRules.markStep(flags: Flags, action: string, cfg: Config): boolean
	if TutorialRules.isDone(flags) or TutorialRules.stepIndex(action, cfg) == 0 then
		return false
	end
	local flag = TutorialRules.stepFlag(action)
	if flags[flag] then
		return false
	end
	flags[flag] = true
	return true
end

-- Since when the current step's action has been unavailable without a break (nil while it is available).
function TutorialRules.trackUnavailable(since: number?, available: boolean, now: number): number?
	if available then
		return nil
	end
	return since or now
end

-- Whether the current step should finish on its own now (see Types.TutorialStepDef), and how.
function TutorialRules.autoOutcome(
	step: StepDef,
	startedAt: number,
	unavailableSince: number?,
	now: number
): StepOutcome?
	local unavailableSeconds = step.unavailableSeconds
	if unavailableSeconds and unavailableSince and now - unavailableSince >= unavailableSeconds then
		return "unavailable"
	end
	local timeout = step.timeoutSeconds
	if timeout and now - startedAt >= timeout then
		return "timeout"
	end
	return nil
end

-- Ends the tutorial and returns the cash to pay: `cfg.reward` the first time it is completed, 0 otherwise (skipped,
-- an existing player, or already over). The done flag is set before returning, so a caller that pays straight away
-- (no yield) can never pay twice.
function TutorialRules.finish(flags: Flags, reason: FinishReason, cfg: Config): number
	if TutorialRules.isDone(flags) then
		return 0
	end
	flags[TutorialRules.DONE_FLAG] = true
	if reason ~= "completed" then
		return 0
	end
	local reward = cfg.reward
	return if reward == reward and reward > 0 and reward < math.huge then math.floor(reward) else 0
end

-- Clears every tutorial flag so it starts over (Studio test command only).
function TutorialRules.reset(flags: Flags, cfg: Config)
	flags[TutorialRules.DONE_FLAG] = nil
	for _, step in cfg.steps do
		flags[TutorialRules.stepFlag(step.id)] = nil
	end
end

-- The belt item the "buy" guide points at: the nearest one the player can afford that won't fall off the end before
-- they get there. The current target is kept unless another one is `switchMargin` studs closer, so the guide doesn't
-- flick between two items. nil when nothing qualifies.
function TutorialRules.pickBeltItem(
	items: { BeltCandidate },
	cash: number,
	px: number,
	pz: number,
	currentId: number?,
	cfg: Types.TutorialBeltConfig
): number?
	local bestId: number? = nil
	local bestDistance = math.huge
	local currentDistance: number? = nil
	for _, item in items do
		if item.price > cash or item.secondsLeft < cfg.minSecondsLeft then
			continue
		end
		local distance = math.sqrt((item.x - px) ^ 2 + (item.z - pz) ^ 2)
		if item.id == currentId then
			currentDistance = distance
		end
		if distance < bestDistance or (distance == bestDistance and bestId ~= nil and item.id < bestId) then
			bestId = item.id
			bestDistance = distance
		end
	end
	if currentDistance ~= nil and currentDistance <= bestDistance + cfg.switchMargin then
		return currentId
	end
	return bestId
end

-- The podium the "collect" guide points at: the occupied one with the most uncollected cash (lowest index on a tie),
-- or nil when no podium holds a Snackling.
function TutorialRules.pickCollectPodium(podiums: { PodiumCandidate }): number?
	local bestIndex: number? = nil
	local bestStored = -math.huge
	for _, podium in podiums do
		if not podium.occupied then
			continue
		end
		if
			podium.stored > bestStored
			or (podium.stored == bestStored and bestIndex ~= nil and podium.index < bestIndex)
		then
			bestIndex = podium.index
			bestStored = podium.stored
		end
	end
	return bestIndex
end

-- How much of the banner fits in `space` (UI units left for it, gap included): "full" (with the tip line, only when
-- `wantTip`), "compact" (one line) or "hidden" (it would overlap something below it).
export type BannerMode = "full" | "compact" | "hidden"

function TutorialRules.bannerMode(
	space: number,
	fullHeight: number,
	compactHeight: number,
	wantTip: boolean
): BannerMode
	if wantTip and space >= fullHeight then
		return "full"
	elseif space >= compactHeight then
		return "compact"
	end
	return "hidden" -- also for a NaN space
end

-- Width of the centred banner: `preferred`, narrowed so its right edge stays `gap` left of `rightLimit` (the TAG
-- button area), but never below `minWidth`. All in UI units.
function TutorialRules.bannerWidth(
	preferred: number,
	centerX: number,
	rightLimit: number,
	gap: number,
	minWidth: number
): number
	local fits = 2 * (rightLimit - gap - centerX)
	if fits ~= fits then
		return preferred -- NaN (no layout yet)
	end
	return math.max(minWidth, math.min(preferred, fits))
end

-- Problems with a tutorial config (empty when valid). Checked by CI so a typo can't ship.
function TutorialRules.validate(cfg: Config): { string }
	local problems: { string } = {}
	local function check(ok: boolean, message: string)
		if not ok then
			table.insert(problems, message)
		end
	end
	local function positive(value: number?): boolean
		return value == nil or (value == value and value > 0 and value < math.huge)
	end
	check(cfg.reward == cfg.reward and cfg.reward >= 0 and cfg.reward < math.huge, "reward")
	check(#cfg.steps > 0, "steps: at least one")
	local seen: { [string]: boolean } = {}
	for index, step in cfg.steps do
		check(TutorialRules.TEXT_KEYS[step.id] ~= nil, `steps[{index}]: unknown id {step.id}`)
		check(not seen[step.id], `steps[{index}]: duplicate id {step.id}`)
		seen[step.id] = true
		check(positive(step.timeoutSeconds), `steps[{index}].timeoutSeconds`)
		check(positive(step.unavailableSeconds), `steps[{index}].unavailableSeconds`)
	end
	check(cfg.belt.minSecondsLeft >= 0 and cfg.belt.switchMargin >= 0, "belt")
	return problems
end

return TutorialRules
