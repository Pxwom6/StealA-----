--!strict
local T = require("./TestKit")
local BountyRules = require("../src/shared/Logic/BountyRules")
local Bounty = require("../src/shared/Config/Bounty")
local Modifiers = require("../src/shared/Config/Modifiers")
local Theme = require("../src/shared/Config/Theme")
local Types = require("../src/shared/Types")

local function candidate(userId: number, income: number, joinedAt: number?, eligible: boolean?): BountyRules.Candidate
	return {
		userId = userId,
		income = income,
		joinedAt = joinedAt or 0,
		eligible = if eligible == nil then true else eligible,
	}
end

-- A hunt with the bounty on `target`.
local function huntOn(target: number): BountyRules.Hunt
	local hunt = BountyRules.newHunt()
	hunt.targetUserId = target
	return hunt
end

local function claimBy(claimer: number, victim: number, now: number, friends: boolean?): BountyRules.ClaimContext
	return { claimerUserId = claimer, victimUserId = victim, friends = friends == true, now = now }
end

T.describe("BountyRules: the real config", function()
	T.it("is valid", function()
		local problems = BountyRules.validate(Bounty)
		if #problems > 0 then
			print(table.concat(problems, "\n"))
		end
		T.expect(#problems).toBe(0)
	end)

	T.it("is what Bounty Hunt runs", function()
		local def = Modifiers.modifiers.bountyHunt
		T.expect(def.bounty).toBe(true)
		T.expect(def.hostable).toBeNil() -- it pays cash: never for a private server's owner to start
	end)

	T.it("rests long enough for the target to get away, a few times in a hunt", function()
		local duration = Modifiers.schedule.durationSeconds
		T.expect(Bounty.restSeconds).toBeAtLeast(20)
		T.expect(duration / Bounty.restSeconds).toBeAtLeast(5)
	end)

	T.it("has every refusal it explains in Theme.text", function()
		local text = (Theme.text :: any) :: { [string]: string }
		for _, reason in BountyRules.REASONS do
			local key = BountyRules.messageKey(reason)
			if key then
				T.expect(type(text[key])).toBe("string")
			end
		end
		T.expect(BountyRules.messageKey("notTarget")).toBeNil() -- an ordinary tag says nothing about bounties
		T.expect(BountyRules.messageKey("self")).toBeNil()
	end)
end)

T.describe("BountyRules.pickTarget", function()
	T.it("puts the bounty on the top earner", function()
		T.expect(BountyRules.pickTarget({ candidate(1, 50), candidate(2, 900), candidate(3, 400) })).toBe(2)
	end)

	T.it("breaks a tie by who joined first, then by UserId", function()
		T.expect(BountyRules.pickTarget({ candidate(1, 500, 30), candidate(2, 500, 10) })).toBe(2)
		T.expect(BountyRules.pickTarget({ candidate(7, 500, 10), candidate(4, 500, 10) })).toBe(4)
	end)

	T.it("skips players without a base or in the tutorial, and anyone earning nothing", function()
		T.expect(BountyRules.pickTarget({ candidate(1, 9999, 0, false), candidate(2, 10) })).toBe(2)
		T.expect(BountyRules.pickTarget({ candidate(1, 0), candidate(2, 0.5) })).toBeNil()
		T.expect(BountyRules.pickTarget({ candidate(1, 0 / 0), candidate(2, math.huge) })).toBeNil()
		T.expect(BountyRules.pickTarget({})).toBeNil()
	end)
end)

T.describe("BountyRules claims", function()
	T.it("pays a hunter who tags or robs the target", function()
		T.expect((BountyRules.canClaim(Bounty, huntOn(1), claimBy(2, 1, 100)))).toBe(true)
	end)

	T.it("says nothing about players who are not the target, or with no hunt", function()
		local ok, reason = BountyRules.canClaim(Bounty, huntOn(1), claimBy(2, 3, 100))
		T.expect(ok).toBe(false)
		T.expect(reason).toBe("notTarget")
		T.expect(select(2, BountyRules.canClaim(Bounty, nil, claimBy(2, 1, 100)))).toBe("notTarget")
		T.expect(select(2, BountyRules.canClaim(Bounty, BountyRules.newHunt(), claimBy(2, 1, 100)))).toBe("notTarget")
	end)

	T.it("never pays the target, nor their friends (no trading tags for payouts)", function()
		T.expect(select(2, BountyRules.canClaim(Bounty, huntOn(1), claimBy(1, 1, 100)))).toBe("self")
		T.expect(select(2, BountyRules.canClaim(Bounty, huntOn(1), claimBy(2, 1, 100, true)))).toBe("friend")
	end)

	T.it("pays each hunter once a hunt, and rests between claims", function()
		local hunt = huntOn(1)
		BountyRules.claim(Bounty, hunt, 2, 100)
		T.expect(hunt.claimed).toBe(1)
		T.expect(BountyRules.isResting(hunt, 100 + Bounty.restSeconds - 0.01)).toBe(true)
		T.expect(BountyRules.isResting(hunt, 100 + Bounty.restSeconds)).toBe(false)
		-- the same hunter, even after the rest
		T.expect(select(2, BountyRules.canClaim(Bounty, hunt, claimBy(2, 1, 100 + Bounty.restSeconds + 60))))
			.toBe("claimed")
		-- another one during the rest, then after it
		T.expect(select(2, BountyRules.canClaim(Bounty, hunt, claimBy(3, 1, 105)))).toBe("resting")
		T.expect((BountyRules.canClaim(Bounty, hunt, claimBy(3, 1, 100 + Bounty.restSeconds)))).toBe(true)
	end)

	T.it("keeps a hunter's claim when the bounty moves to someone else", function()
		local hunt = huntOn(1)
		BountyRules.claim(Bounty, hunt, 2, 100)
		hunt.targetUserId = 5 -- the first target left
		T.expect(select(2, BountyRules.canClaim(Bounty, hunt, claimBy(2, 5, 1000)))).toBe("claimed")
		T.expect((BountyRules.canClaim(Bounty, hunt, claimBy(3, 5, 1000)))).toBe(true)
	end)

	T.it("checks friends before the claim limit and the rest, so a friend always hears why", function()
		local hunt = huntOn(1)
		BountyRules.claim(Bounty, hunt, 2, 100)
		T.expect(select(2, BountyRules.canClaim(Bounty, hunt, claimBy(2, 1, 101, true)))).toBe("friend")
	end)
end)

T.describe("BountyRules.payout", function()
	T.it("pays from the claimer's own income, never less than the minimum", function()
		T.expect(BountyRules.payout(Bounty, "tag", 0)).toBe(Bounty.tag.minimum)
		T.expect(BountyRules.payout(Bounty, "steal", 0)).toBe(Bounty.steal.minimum)
		T.expect(BountyRules.payout(Bounty, "tag", 1000)).toBe(1000 * Bounty.tag.incomeSeconds)
		T.expect(BountyRules.payout(Bounty, "steal", 1000)).toBe(1000 * Bounty.steal.incomeSeconds)
	end)

	T.it("pays more for robbing the base than for a tag", function()
		for _, income in { 0, 10, 1000, 1e6 } do
			T.expect(BountyRules.payout(Bounty, "steal", income))
				.toBeGreaterThan(BountyRules.payout(Bounty, "tag", income))
		end
	end)
end)

T.describe("BountyRules.validate", function()
	T.it("refuses broken numbers", function()
		local broken: Types.BountyConfig = {
			tag = { incomeSeconds = -1, minimum = 0 },
			steal = { incomeSeconds = 90, minimum = -5 },
			claimsPerHunter = 0,
			restSeconds = 2,
			checkSeconds = 60,
		}
		T.expect(#BountyRules.validate(broken)).toBe(5)
	end)
end)

return nil
