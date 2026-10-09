--!strict
--[[
	Timers, ranges, map geometry and anti-abuse limits. Plain data only.
	All distances are in studs, all times in seconds.
]]

export type RateLimit = { burst: number, perSecond: number }

local Gameplay = {
	walkSpeed = 16,

	-- Map geometry (used by MapBuilder). The belt runs along the X axis through the middle of the map; plots sit
	-- on both sides with their entrance facing the belt.
	map = {
		plotCount = 8,
		plotsPerSide = 4,
		plotWidth = 56, -- along X
		plotDepth = 78, -- along Z
		plotGap = 10,
		walkwayWidth = 22, -- distance from belt centre line to the plot entrance
		wallHeight = 7,
		entranceWidth = 18,
		podiumColumns = 2,
		podiumColumnOffset = 17, -- local X of each podium column
		podiumRowSpacing = 6.6,
		podiumFirstRowOffset = 11, -- distance from the entrance to the first podium row
		maxPodiums = 20,
	},

	belt = {
		spawnInterval = 2.5,
		length = 260,
		travelSeconds = 30,
		width = 9,
		surfaceY = 1.2, -- height of the belt surface items ride on
		buyRange = 16,
		latencyTolerance = 0.75, -- seconds of belt movement forgiven when checking buy range
		maxItems = 16,
	},

	collect = {
		-- How close (horizontally) the owner's root part must be to a collect pad's centre: roughly "standing on
		-- the 4.2-stud pad". Must stay below half of map.podiumRowSpacing so neighbouring pads never overlap.
		padRange = 3.2,
	},

	steal = {
		holdSeconds = 1.5, -- hold-to-grab duration (the server re-checks it)
		holdTolerance = 0.8, -- share of holdSeconds the server accepts (network jitter)
		grabRange = 12,
		-- A grab still counts this many studs above the walls (the root at a jump's apex is ~10 above the floor, ~11.6
		-- from a podium top). Delivery stays at floor level.
		grabJumpAllowance = 5,
		holdRangeSlack = 4, -- extra studs allowed when a hold starts (you may still be running in)
		carrySpeedMultiplier = 0.62,
		carryTimeoutSeconds = 75,
		tagRange = 13, -- horizontal studs between tagger and thief
		tagVerticalAllowance = 28, -- generous height difference still allowed for a tag (> maxCarryHeight)
		-- A carrying thief's root must stay between these heights above the ground: no flying away, no sinking under
		-- the map. 24 leaves room for a jump from the highest perch, the entrance sign (root apex about 22.8).
		minCarryHeight = 0,
		maxCarryHeight = 24,
		tagCooldownSeconds = 1,
		thiefCooldownAfterTagSeconds = 6,
		-- Carry movement budget (Logic/StealRules.stepCarryTrack): it refills at carry speed x speedCheckTolerance,
		-- holds at most speedBudgetSeconds of refill (so a lag spike's catch-up jump is paid for, but a sustained
		-- speed hack runs it dry), and the straight-line distance from the grab point is capped separately.
		speedCheckTolerance = 1.6,
		speedBudgetSeconds = 3,
		-- Starting budget (a jump right after the grab, while the client still walks at full speed for one round
		-- trip), and studs of slack on the straight-line cap.
		speedCheckLeeway = 12,
		deliveryCheckInterval = 0.2,
	},

	-- Server-side position sampling (every player, a few times per second) against a walking movement budget
	-- (Logic/StealRules.stepWalkTrack). Used to decide whether a client's reported position can be trusted, e.g. for
	-- tagging.
	tracking = {
		sampleInterval = 0.25,
		walkTolerance = 1.5, -- the budget refills at walk speed x this
		walkBudgetSeconds = 1.5, -- and holds at most this much refill (a stall/catch-up up to ~1.5 s is forgiven)
		walkLeeway = 12, -- starting budget after spawning or a server move (covers an immediate jump)
		-- A step the budget can't pay makes the position untrusted for teleportPenaltySeconds. A step more than
		-- teleportDeficit studs beyond the budget is a teleport: a tag is then refused for any carry that started
		-- less than teleportPenaltySeconds before it.
		teleportPenaltySeconds = 2,
		teleportDeficit = 24,
		stepSlack = 4, -- studs beyond walking speed allowed between the latest sample and a tag (jitter)
	},

	lock = {
		durationSeconds = 60,
		cooldownSeconds = 90, -- after a lock ends, free players wait this long before locking again
		-- Nobody (paid or not) can re-lock sooner than this after a lock ends, or half the lock's length if that is
		-- longer (Logic/LockRules.windows), so every base is open at least a third of the time.
		minVulnerableSeconds = 30,
		buttonRange = 12,
	},

	grace = {
		newPlayerSeconds = 240, -- total play time during which a new player's base cannot be stolen from
	},

	replicationHz = 5, -- player state is batched to clients this many times per second
	incomeTickSeconds = 1,
	leaderboardRefreshSeconds = 120,

	-- Token-bucket limits for every client → server remote. Anything over the limit is dropped.
	rateLimits = {
		ClientReady = { burst = 2, perSecond = 0.2 },
		BuyBeltItem = { burst = 4, perSecond = 2 },
		BuyPodium = { burst = 3, perSecond = 1 },
		SellCreature = { burst = 4, perSecond = 2 },
		StealBegin = { burst = 4, perSecond = 2 },
		StealConfirm = { burst = 4, perSecond = 2 },
		TagThief = { burst = 4, perSecond = 3 },
		LockBase = { burst = 2, perSecond = 0.5 },
		Rebirth = { burst = 2, perSecond = 0.2 },
		ClaimDaily = { burst = 2, perSecond = 0.2 },
		ClientEvent = { burst = 6, perSecond = 0.5 },
		DevGrantProduct = { burst = 3, perSecond = 1 },
	} :: { [string]: RateLimit },
}

return Gameplay
