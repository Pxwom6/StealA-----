--!strict
-- What's New (Logic/UpdateRules, Config/Updates): the newest update, who sees its card, remembering it, validation.
local T = require("./TestKit")
local UpdateRules = require("../src/shared/Logic/UpdateRules")
local Updates = require("../src/shared/Config/Updates")
local Types = require("../src/shared/Types")

local function update(number: number): Types.UpdateDef
	return {
		number = number,
		date = "2026-10-15",
		title = "Update!",
		highlights = { "🗺️ More maps", "⛈️ More twists", "🎨 Titles and base skins" },
	}
end

T.describe("UpdateRules: the real config", function()
	T.it("is valid", function()
		T.expect(table.concat(UpdateRules.validate(Updates), "; ")).toBe("")
	end)

	T.it("lists the newest first, and that is the one shown", function()
		local latest = UpdateRules.latest(Updates) :: Types.UpdateDef
		T.expect(latest ~= nil).toBe(true)
		T.expect(latest).toBe(Updates.list[1])
	end)
end)

T.describe("UpdateRules", function()
	T.it("picks the highest number, or nothing", function()
		T.expect(UpdateRules.latest({ list = {} })).toBeNil()
		local newest = update(3)
		T.expect(UpdateRules.latest({ list = { update(1), newest, update(2) } })).toBe(newest)
	end)

	T.it("shows the card to a returning player who hasn't seen it", function()
		T.expect(UpdateRules.onJoin({}, 2, false, false)).toBe("show")
		T.expect(UpdateRules.onJoin({ news_1 = true }, 2, false, false)).toBe("show") -- an older one doesn't count
	end)

	T.it("never shows it twice", function()
		T.expect(UpdateRules.onJoin({ news_2 = true }, 2, false, false)).toBe("none")
	end)

	T.it("gives new players the tutorial instead: what they started in counts as seen", function()
		T.expect(UpdateRules.onJoin({}, 2, true, true)).toBe("markSeen")
		T.expect(UpdateRules.onJoin({}, 2, true, false)).toBe("markSeen")
		T.expect(UpdateRules.onJoin({}, 2, false, true)).toBe("markSeen") -- still in the tutorial
		T.expect(UpdateRules.onJoin({}, nil, false, false)).toBe("none") -- no updates at all
	end)

	T.it("remembers only the newest one it was shown", function()
		local flags: { [string]: boolean } = { news_1 = true, news_7 = true, settings_sfxOff = true, map_meadow = true }
		UpdateRules.markSeen(flags, 2)
		T.expect(flags).toEqual({ news_2 = true, settings_sfxOff = true, map_meadow = true })
		T.expect(UpdateRules.hasSeen(flags, 2)).toBe(true)
		T.expect(UpdateRules.hasSeen(flags, 1)).toBe(false)
		T.expect(UpdateRules.flagKey(12)).toBe("news_12")
	end)
end)

T.describe("UpdateRules validation", function()
	local function problems(edit: (Types.UpdateDef) -> ()): number
		local def = update(1)
		edit(def)
		return #UpdateRules.validate({ list = { def } })
	end

	T.it("catches a bad update", function()
		T.expect(problems(function() end)).toBe(0)
		local cases: { [string]: (Types.UpdateDef) -> () } = {
			zero = function(def)
				def.number = 0
			end,
			fraction = function(def)
				def.number = 1.5
			end,
			date = function(def)
				def.date = "15/10/2026"
			end,
			month = function(def)
				def.date = "2026-13-01"
			end,
			title = function(def)
				def.title = string.rep("A", UpdateRules.TITLE_LENGTH + 1)
			end,
			emptyTitle = function(def)
				def.title = ""
			end,
			tooFew = function(def)
				def.highlights = { "🗺️ One", "⛈️ Two" }
			end,
			tooMany = function(def)
				def.highlights = { "🗺️ 1", "🗺️ 2", "🗺️ 3", "🗺️ 4", "🗺️ 5", "🗺️ 6" }
			end,
			long = function(def)
				def.highlights[1] = "🗺️ " .. string.rep("a", UpdateRules.HIGHLIGHT_LENGTH)
			end,
			noEmoji = function(def)
				def.highlights[2] = "More twists"
			end,
			twoLines = function(def)
				def.highlights[3] = "🎨 Titles\nand skins"
			end,
		}
		for name, edit in cases do
			if problems(edit) == 0 then
				error(`an update with a bad {name} passed`)
			end
		end
	end)

	T.it("wants the newest first, and never a number twice", function()
		T.expect(#UpdateRules.validate({ list = { update(2), update(1) } })).toBe(0)
		T.expect(#UpdateRules.validate({ list = { update(1), update(2) } })).toBe(1)
		T.expect(#UpdateRules.validate({ list = { update(2), update(2) } })).toBe(1)
	end)
end)

return nil
