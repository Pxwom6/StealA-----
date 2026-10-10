--!strict
--[[
	Unit test entry point: `lune run tests/run.luau`.
	Each spec registers its tests when required. Add new spec files to this list.
]]

local T = require("./TestKit")

require("./Format.spec")
require("./Guard.spec")
require("./RateLimiter.spec")
require("./Config.spec")
require("./RarityRoll.spec")
require("./EconomyMath.spec")
require("./RebirthMath.spec")
require("./OfflineEarnings.spec")
require("./ReceiptLedger.spec")
require("./LockRules.spec")
require("./StealRules.spec")
require("./DailyStreak.spec")
require("./DataSchema.spec")
require("./BeltMath.spec")
require("./LiveOpsRules.spec")
require("./Inventory.spec")
require("./MutationRules.spec")

T.finish()
