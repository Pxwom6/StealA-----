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
		padRange = 7, -- how close the owner's root part must be to a collect pad
	},

	steal = {
		holdSeconds = 1.5, -- hold-to-grab duration (the server re-checks it)
		holdTolerance = 0.8, -- share of holdSeconds the server accepts (network jitter)
		grabRange = 12,
		carrySpeedMultiplier = 0.62,
		carryTimeoutSeconds = 75,
		tagRange = 13,
		tagCooldownSeconds = 1,
		thiefCooldownAfterTagSeconds = 6,
		speedCheckTolerance = 1.6, -- multiplier on the allowed carry speed before we drop the creature
		speedCheckLeeway = 6, -- extra studs forgiven per check (jumps, lag)
		deliveryCheckInterval = 0.2,
	},

	lock = {
		durationSeconds = 60,
		cooldownSeconds = 90, -- after a lock ends, free players wait this long before locking again
		minVulnerableSeconds = 30, -- nobody (paid or not) can re-lock sooner than this after a lock ends
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
