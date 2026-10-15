--!strict
--[[
	Bounty Hunt rules (Config/Bounty; the modifier is Config/Modifiers `bounty`): who wears the bounty, whether a tag or
	a steal claims it, what a claim pays, and validation. Pure: no Roblox APIs; times are server time.

	The target is the server's top earner: the most steady income (EconomyMath.packIncome: no temporary boost or friend
	bonus decides it) among the players who have a base and aren't in the first-time tutorial; ties go to whoever
	joined first. A claim pays the claimer (the tagger, or the thief who got the Snackling home) cash sized from their
	own steady income. Fair play:
	  * the target never claims their own bounty, and nor do their Roblox friends (no trading tags for payouts);
	  * each hunter claims it at most claimsPerHunter times in one hunt, whoever the target is by then;
	  * after any claim it rests for restSeconds, so nobody farms the target or camps by their base;
	  * only real gameplay counts: StealService decides every tag and every delivery exactly as always, and the
	    bounty only listens to what it decided (a tag needs the target carrying a Snackling, so nothing pays for
	    waiting by their spawn).
]]

local EconomyMath = require("./EconomyMath")
local Types = require("../Types")

type BountyConfig = Types.BountyConfig

-- A player the target could be: their steady income, when they joined (ties), and whether they may be the target
-- now (a base, no first-time tutorial).
export type Candidate = { userId: number, income: number, joinedAt: number, eligible: boolean }

-- One Bounty Hunt while it runs.
export type Hunt = {
	targetUserId: number?, -- nil: nobody earns anything yet
	claims: { [number]: number }, -- claimer UserId -> claims they made in this hunt
	restUntil: number, -- nobody can claim it before then (server time)
	claimed: number, -- claims in all
}

export type ClaimKind = "tag" | "steal"

export type ClaimContext = {
	claimerUserId: number,
	victimUserId: number, -- whose bounty would it be: the tagged thief, or the owner of the robbed base
	friends: boolean, -- the claimer and the target are Roblox friends
	now: number,
}

local BountyRules = {}

-- Why a claim was refused (BountyRules.canClaim), in the order they are checked.
BountyRules.REASONS = table.freeze({ "notTarget", "self", "friend", "claimed", "resting" })

function BountyRules.newHunt(): Hunt
	return { targetUserId = nil, claims = {}, restUntil = -math.huge, claimed = 0 }
end

-- The top earner among `candidates` (the eligible ones earning anything): highest income, then whoever joined first,
-- then the lowest UserId. nil when nobody qualifies.
function BountyRules.pickTarget(candidates: { Candidate }): number?
	local best: Candidate? = nil
	for _, candidate in candidates do
		if not candidate.eligible or not (candidate.income >= 1 and candidate.income < math.huge) then
			continue
		end
		local current = best
		if
			current == nil
			or candidate.income > current.income
			or (
				candidate.income == current.income
				and (
					candidate.joinedAt < current.joinedAt
					or (candidate.joinedAt == current.joinedAt and candidate.userId < current.userId)
				)
			)
		then
			best = candidate
		end
	end
	return if best then best.userId else nil
end

function BountyRules.isResting(hunt: Hunt, now: number): boolean
	return now < hunt.restUntil
end

-- Whether a tag or a steal by `ctx.claimerUserId` against `ctx.victimUserId` claims the bounty of `hunt`.
-- Reasons: "notTarget" (no hunt, or the victim isn't the target: nothing to say) | "self" | "friend" | "claimed"
-- (they already claimed claimsPerHunter times this hunt) | "resting".
function BountyRules.canClaim(config: BountyConfig, hunt: Hunt?, ctx: ClaimContext): (boolean, string?)
	if hunt == nil or hunt.targetUserId == nil or ctx.victimUserId ~= hunt.targetUserId then
		return false, "notTarget"
	elseif ctx.claimerUserId == hunt.targetUserId then
		return false, "self"
	elseif ctx.friends then
		return false, "friend"
	elseif (hunt.claims[ctx.claimerUserId] or 0) >= config.claimsPerHunter then
		return false, "claimed"
	elseif BountyRules.isResting(hunt, ctx.now) then
		return false, "resting"
	end
	return true, nil
end

-- Records a claim by `claimerUserId` at `now` (call only after canClaim said yes): it counts against their limit and
-- the bounty rests.
function BountyRules.claim(config: BountyConfig, hunt: Hunt, claimerUserId: number, now: number)
	hunt.claims[claimerUserId] = (hunt.claims[claimerUserId] or 0) + 1
	hunt.claimed += 1
	hunt.restUntil = now + config.restSeconds
end

-- What a claim of `kind` pays a claimer with this steady income per second (like a cash pack, at least the minimum).
function BountyRules.payout(config: BountyConfig, kind: ClaimKind, income: number): number
	local reward = if kind == "tag" then config.tag else config.steal
	return EconomyMath.cashPackAmount(income, { incomeSeconds = reward.incomeSeconds, minimum = reward.minimum })
end

-- Config/Theme.text key telling a would-be claimer why there was no bounty (nil: say nothing).
function BountyRules.messageKey(reason: string): string?
	local map: { [string]: string } = {
		friend = "bountyRefusedFriend",
		claimed = "bountyRefusedClaimed",
		resting = "bountyRefusedResting",
	}
	return map[reason]
end

-- Problems with Config/Bounty (an empty list means valid).
function BountyRules.validate(config: BountyConfig): { string }
	local problems: { string } = {}
	local function reward(value: Types.IncomeReward, what: string)
		if not (value.incomeSeconds >= 0 and value.incomeSeconds <= 600) then
			table.insert(problems, `{what}.incomeSeconds must be between 0 and 600`)
		end
		if not (value.minimum >= 0 and value.minimum < math.huge) then
			table.insert(problems, `{what}.minimum must be 0 or more`)
		end
	end
	reward(config.tag, "tag")
	reward(config.steal, "steal")
	if not (config.claimsPerHunter >= 1 and config.claimsPerHunter <= 3 and config.claimsPerHunter % 1 == 0) then
		table.insert(problems, "claimsPerHunter must be a whole number from 1 to 3")
	end
	-- long enough that the target gets away between claims, short enough that a 5-minute hunt keeps going
	if not (config.restSeconds >= 10 and config.restSeconds <= 120) then
		table.insert(problems, "restSeconds must be between 10 and 120")
	end
	if not (config.checkSeconds >= 0.5 and config.checkSeconds <= 10) then
		table.insert(problems, "checkSeconds must be between 0.5 and 10")
	end
	return problems
end

return BountyRules
