--!strict
-- Titles and base skins (Logic/StyleRules, Config/Titles, Config/Skins): unlocking, wearing one at a time, the view,
-- the trims beside VIP's gold, and validation.
local T = require("./TestKit")
local Achievements = require("../src/shared/Config/Achievements")
local AchievementRules = require("../src/shared/Logic/AchievementRules")
local Catalog = require("../src/shared/Logic/Catalog")
local Creatures = require("../src/shared/Config/Creatures")
local DataSchema = require("../src/shared/Logic/DataSchema")
local Economy = require("../src/shared/Config/Economy")
local Mutations = require("../src/shared/Config/Mutations")
local Rarities = require("../src/shared/Config/Rarities")
local Skins = require("../src/shared/Config/Skins")
local StyleRules = require("../src/shared/Logic/StyleRules")
local Theme = require("../src/shared/Config/Theme")
local Titles = require("../src/shared/Config/Titles")
local Types = require("../src/shared/Types")

local catalog = Catalog.build(Creatures, Rarities, Mutations)
local achievements = StyleRules.achievementsById(Achievements)
local tierCount = 0
for _ in catalog.rarities do
	tierCount += 1
end
local limits: StyleRules.UnlockLimits =
	{ achievements = achievements, maxRebirths = Economy.rebirth.maxRebirths, tiers = tierCount }
local PAD = Theme.world.collectPad
local TITLES = StyleRules.titleEntries(Titles)
local SKINS = StyleRules.skinEntries(Skins)

-- Every title and skin id that has shipped (worn as the flags title_<id> and skin_<id>). APPEND-ONLY: a renamed id
-- leaves whoever wore it wearing nothing.
local RELEASED_TITLE_IDS = {
	"stickyFingers",
	"snackShopper",
	"collector",
	"insider",
	"masterThief",
	"millionaire",
	"bornAgain",
	"giantSlayer",
	"mutationHunter",
	"explorer",
	"snackScholar",
	"legendaryBandit",
	"fiveLives",
	"globetrotter",
	"completionist",
	"secretKeeper",
	"billionaire",
	"mvp",
	"snackdexMaster",
	"phantomThief",
	"sevenLives",
	"veteran",
}
local RELEASED_SKIN_IDS = {
	"classic",
	"sprinklePink",
	"mintChip",
	"blueberry",
	"goldenCrust",
	"licoriceNight",
	"rainbowSwirl",
	"diamond",
}

local function save(): Types.PlayerData
	return DataSchema.template(100)
end

local function unlocks(data: Types.PlayerData, all: boolean?): StyleRules.Unlocks
	return {
		ctx = AchievementRules.context(data, catalog.creatures, catalog.rarities),
		flags = data.flags,
		achievements = achievements,
		rarities = catalog.rarities,
		all = all,
	}
end

local function title(id: string): Types.TitleDef
	local def = StyleRules.titleById(Titles, id)
	assert(def, `no title {id}`)
	return def
end

local function count(set: { [string]: boolean }): number
	local n = 0
	for _ in set do
		n += 1
	end
	return n
end

local function flagsWith(prefix: string, flags: { [string]: boolean }): { string }
	local list: { string } = {}
	for key in flags do
		if string.sub(key, 1, #prefix) == prefix then
			table.insert(list, key)
		end
	end
	table.sort(list)
	return list
end

T.describe("StyleRules: the real config", function()
	T.it("has valid titles and skins", function()
		local problems = StyleRules.validateTitles(Titles, limits)
		for _, problem in StyleRules.validateSkins(Skins, limits, PAD) do
			table.insert(problems, problem)
		end
		T.expect(table.concat(problems, "; ")).toBe("")
	end)

	T.it("keeps every shipped title and skin id, and lists every new one", function()
		for _, pair in
			{
				{ list = Titles.list, released = RELEASED_TITLE_IDS },
				{ list = Skins.list, released = RELEASED_SKIN_IDS },
			} :: { any }
		do
			local ids: { [string]: boolean } = {}
			for _, def in pair.list do
				ids[def.id] = true
				if table.find(pair.released, def.id) == nil then
					error(`append "{def.id}" to the released ids in tests/StyleRules.spec.luau so it is protected`)
				end
			end
			for _, id in pair.released do
				if not ids[id] then
					error(`{id} shipped and must stay (whoever wears it would wear nothing)`)
				end
			end
		end
	end)

	T.it("comes from achievements, rebirths and the Snackdex, and never from Robux", function()
		local kinds: { [string]: number } = {}
		for _, def in Titles.list do
			kinds[def.unlock.kind] = (kinds[def.unlock.kind] or 0) + 1
		end
		T.expect((kinds.achievement or 0) > 0 and (kinds.rebirths or 0) > 0 and (kinds.tiers or 0) > 0).toBe(true)
		T.expect(kinds.free).toBeNil()
		local skinKinds: { [string]: number } = {}
		for _, def in Skins.list do
			skinKinds[def.unlock.kind] = (skinKinds[def.unlock.kind] or 0) + 1
		end
		T.expect(skinKinds.free).toBe(1) -- Classic
		T.expect((skinKinds.rebirths or 0) > 0 and (skinKinds.tiers or 0) > 0 and (skinKinds.achievement or 0) > 0)
			.toBe(true)
		T.expect(#Skins.list).toBe(8)
		-- the brief's examples
		for _, id in { "masterThief", "legendaryBandit", "globetrotter", "completionist", "millionaire" } do
			local def = title(id)
			T.expect(def.unlock.kind == "achievement" and (def.unlock :: any).id == id).toBe(true)
		end
		T.expect((title("bornAgain").unlock :: any).count).toBe(1)
		T.expect((title("fiveLives").unlock :: any).count).toBe(5)
	end)

	T.it("asks for no more rebirths or tiers than there can be", function()
		for _, entries in { TITLES, SKINS } do
			for _, entry in entries do
				local unlock = entry.unlock :: any
				if unlock.kind == "rebirths" then
					T.expect(unlock.count).toBeAtMost(Economy.rebirth.maxRebirths)
				elseif unlock.kind == "tiers" then
					T.expect(unlock.count).toBeAtMost(tierCount)
				end
			end
		end
	end)

	T.it("only lets the rainbow skin animate, and keeps Classic the plot's own look", function()
		for _, def in Skins.list do
			local look = def.look
			T.expect(look ~= nil and look.rainbow == true).toBe(def.id == "rainbowSwirl")
		end
		T.expect(Skins.default).toBe("classic")
		T.expect((StyleRules.skinById(Skins, "classic") :: Types.SkinDef).look).toBeNil()
	end)
end)

T.describe("StyleRules unlocking", function()
	T.it("starts a new save with only the free skin", function()
		local u = unlocks(save())
		T.expect(count(StyleRules.unlocked(TITLES, u))).toBe(0)
		local skins = StyleRules.unlocked(SKINS, u)
		T.expect(count(skins)).toBe(1)
		T.expect(skins.classic).toBe(true)
	end)

	T.it("unlocks an achievement's title once its flag is set, or once its goal is reached", function()
		local data = save()
		local masterThief = title("masterThief").unlock
		T.expect(StyleRules.isUnlocked(masterThief, unlocks(data))).toBe(false)
		data.stats.steals = 24
		local progress, target = StyleRules.progress(masterThief, unlocks(data))
		T.expect(progress).toBe(24)
		T.expect(target).toBe(25)
		data.stats.steals = 25 -- reached; AchievementService flags it within a second
		T.expect(StyleRules.isUnlocked(masterThief, unlocks(data))).toBe(true)
		local fresh = save()
		fresh.flags[AchievementRules.flagKey("masterThief")] = true -- paid earlier
		T.expect(StyleRules.isUnlocked(masterThief, unlocks(fresh))).toBe(true)
		progress, target = StyleRules.progress(masterThief, unlocks(fresh))
		T.expect(progress).toBe(target)
	end)

	T.it("keeps a title whose goal grew after it was earned (Globetrotter and new maps)", function()
		local data = save()
		data.flags[AchievementRules.flagKey("globetrotter")] = true -- every map, back when there were fewer
		data.flags.map_meadow = true
		T.expect(StyleRules.isUnlocked(title("globetrotter").unlock, unlocks(data))).toBe(true)
	end)

	T.it("counts rebirths and Snackdex tiers from the save", function()
		local data = save()
		data.rebirths = 4
		local five = title("fiveLives").unlock
		T.expect(StyleRules.isUnlocked(five, unlocks(data))).toBe(false)
		local progress, target = StyleRules.progress(five, unlocks(data))
		T.expect(progress).toBe(4)
		T.expect(target).toBe(5)
		data.rebirths = 6
		T.expect(StyleRules.isUnlocked(five, unlocks(data))).toBe(true)
		progress = StyleRules.progress(five, unlocks(data))
		T.expect(progress).toBe(5) -- never past the target
		local scholar = title("snackScholar").unlock
		data.snackdex.tiers = { Common = true, Uncommon = true }
		T.expect(StyleRules.isUnlocked(scholar, unlocks(data))).toBe(false)
		data.snackdex.tiers.Rare = true
		T.expect(StyleRules.isUnlocked(scholar, unlocks(data))).toBe(true)
	end)

	T.it("never unlocks an unknown achievement (unless its flag is there), and unlocks all in Studio", function()
		local unknown: Types.StyleUnlock = { kind = "achievement", id = "noSuchThing" }
		local data = save()
		T.expect(StyleRules.isUnlocked(unknown, unlocks(data))).toBe(false)
		data.flags.ach_noSuchThing = true
		T.expect(StyleRules.isUnlocked(unknown, unlocks(data))).toBe(true)
		local everything = unlocks(save(), true)
		T.expect(count(StyleRules.unlocked(TITLES, everything))).toBe(#Titles.list)
		T.expect(count(StyleRules.unlocked(SKINS, everything))).toBe(#Skins.list)
	end)
end)

T.describe("StyleRules wearing", function()
	local P = StyleRules.TITLE_PREFIX

	T.it("wears one title at a time", function()
		local flags: { [string]: boolean } = { settings_musicOff = true }
		StyleRules.equip(flags, P, "masterThief")
		T.expect(flagsWith(P, flags)).toEqual({ "title_masterThief" })
		StyleRules.equip(flags, P, "mvp")
		T.expect(flagsWith(P, flags)).toEqual({ "title_mvp" })
		T.expect(StyleRules.worn(flags, P, TITLES)).toBe("mvp")
		StyleRules.equip(flags, P, "")
		T.expect(#flagsWith(P, flags)).toBe(0)
		T.expect(StyleRules.worn(flags, P, TITLES)).toBe("")
		T.expect(flags.settings_musicOff).toBe(true) -- other flags stay
	end)

	T.it("repairs a save with extras, unknown ids or locked ones", function()
		local flags: { [string]: boolean } =
			{ title_mvp = true, title_masterThief = true, title_gone = true, ach_mvp = true }
		local unlocked = { mvp = true, masterThief = true }
		local kept, changed = StyleRules.normalize(flags, P, TITLES, unlocked)
		T.expect(kept).toBe("masterThief") -- the first in the list's order
		T.expect(changed).toBe(true)
		T.expect(flagsWith(P, flags)).toEqual({ "title_masterThief" })
		T.expect(flags.ach_mvp).toBe(true)
		kept, changed = StyleRules.normalize(flags, P, TITLES, unlocked)
		T.expect(kept).toBe("masterThief")
		T.expect(changed).toBe(false) -- already fine
		kept, changed = StyleRules.normalize(flags, P, TITLES, { mvp = true }) -- no longer unlocked
		T.expect(kept).toBe("")
		T.expect(changed).toBe(true)
		T.expect(#flagsWith(P, flags)).toBe(0)
	end)

	T.it("never stores the default skin, and wears it when no skin flag is set", function()
		local S = StyleRules.SKIN_PREFIX
		local flags: { [string]: boolean } = { skin_classic = true }
		local kept, changed = StyleRules.normalize(flags, S, SKINS, { classic = true }, Skins.default)
		T.expect(kept).toBe("")
		T.expect(changed).toBe(true)
		T.expect(StyleRules.wornSkin(flags, Skins)).toBe("classic")
		StyleRules.equip(flags, S, "diamond")
		T.expect(StyleRules.wornSkin(flags, Skins)).toBe("diamond")
	end)

	T.it("lets a player wear only what they unlocked", function()
		local unlocked = { masterThief = true, classic = true, mintChip = true }
		T.expect(StyleRules.canEquip("title", "masterThief", Titles, Skins, unlocked)).toBe(true)
		T.expect(StyleRules.canEquip("title", "mvp", Titles, Skins, unlocked)).toBe(false)
		T.expect(StyleRules.canEquip("title", "noSuchTitle", Titles, Skins, { noSuchTitle = true })).toBe(false)
		T.expect(StyleRules.canEquip("title", "", Titles, Skins, {})).toBe(true) -- no title
		T.expect(StyleRules.canEquip("skin", "mintChip", Titles, Skins, unlocked)).toBe(true)
		T.expect(StyleRules.canEquip("skin", "diamond", Titles, Skins, unlocked)).toBe(false)
		T.expect(StyleRules.canEquip("skin", "masterThief", Titles, Skins, unlocked)).toBe(false) -- a title, not a skin
	end)

	T.it("shows what is worn and how far each one is", function()
		local data = save()
		data.stats.steals = 3
		data.rebirths = 1
		StyleRules.equip(data.flags, P, "stickyFingers")
		local view = StyleRules.view(Titles, Skins, unlocks(data))
		T.expect(view.title).toBe("stickyFingers")
		T.expect(view.skin).toBe("classic")
		T.expect(#view.titles).toBe(#Titles.list)
		T.expect(#view.skins).toBe(#Skins.list)
		local byId: { [string]: Types.StyleItemView } = {}
		for _, item in view.titles do
			byId[item.id] = item
		end
		T.expect(byId.stickyFingers.unlocked).toBe(true)
		T.expect(byId.bornAgain.unlocked).toBe(true)
		T.expect(byId.masterThief.unlocked).toBe(false)
		T.expect(byId.masterThief.progress).toBe(3)
		T.expect(byId.masterThief.target).toBe(25)
	end)
end)

T.describe("StyleRules texts", function()
	local text = Theme.text :: any
	T.it("says how to earn each one", function()
		T.expect(StyleRules.hint(title("masterThief").unlock, achievements, tierCount, text))
			.toBe("Steal 25 Snacklings")
		T.expect(StyleRules.hint({ kind = "rebirths", count = 1 }, achievements, tierCount, text)).toBe("Rebirth once")
		T.expect(StyleRules.hint({ kind = "rebirths", count = 5 }, achievements, tierCount, text))
			.toBe("Rebirth 5 times")
		T.expect(StyleRules.hint({ kind = "tiers", count = 1 }, achievements, tierCount, text))
			.toBe(Theme.text.styleEarnTierOnce)
		T.expect(StyleRules.hint({ kind = "tiers", count = 3 }, achievements, tierCount, text))
			.toBe("Complete 3 Snackdex tiers")
		T.expect(StyleRules.hint({ kind = "tiers", count = tierCount }, achievements, tierCount, text))
			.toBe(Theme.text.styleEarnTiersAll)
		T.expect(StyleRules.hint({ kind = "free" }, achievements, tierCount, text)).toBe(Theme.text.styleEarnFree)
	end)

	T.it("shows progress like the Trophies tab: cash, hours or a count", function()
		local function shown(id: string, progress: number, target: number): string
			return StyleRules.progressText(title(id).unlock, progress, target, achievements, text, "$")
		end
		T.expect(shown("masterThief", 12, 25)).toBe("🔒 12 / 25")
		T.expect(shown("billionaire", 1.25e6, 1e9)).toBe("🔒 $1.25M / $1B")
		T.expect(shown("veteran", 3.45, 50)).toBe("🔒 3.4 / 50 h")
		T.expect(StyleRules.progressText({ kind = "rebirths", count = 5 }, 2, 5, achievements, text, "$"))
			.toBe("🔒 2 / 5")
	end)
end)

T.describe("StyleRules trims and tiles", function()
	T.it("keeps VIP's gold on a Classic base, and its corner caps under any other skin", function()
		local look = (StyleRules.skinById(Skins, "mintChip") :: Types.SkinDef).look
		local walls, caps = StyleRules.trimSources(nil, false)
		T.expect(walls == "wall" and caps == "wall").toBe(true)
		walls, caps = StyleRules.trimSources(nil, true)
		T.expect(walls == "vip" and caps == "vip").toBe(true)
		walls, caps = StyleRules.trimSources(look, false)
		T.expect(walls == "skin" and caps == "skin").toBe(true)
		walls, caps = StyleRules.trimSources(look, true)
		T.expect(walls == "skin" and caps == "vip").toBe(true)
	end)

	T.it("alternates two colours into the Classic checker, and more into stripes", function()
		for side = 1, 2 do
			for row = 0, 3 do
				-- MapBuilder's Classic floor: light where (row + side) is even
				local light = (row + side) % 2 == 0
				T.expect(StyleRules.tileIndex(row, side, 2)).toBe(if light then 1 else 2)
			end
		end
		local seen: { [number]: boolean } = {}
		for side = 1, 2 do
			for row = 0, 3 do
				seen[StyleRules.tileIndex(row, side, 6)] = true
			end
		end
		T.expect(count(seen :: any)).toBe(5) -- 8 tiles show 5 of 6 colours
	end)

	T.it("measures colours", function()
		T.expect(StyleRules.luminance("#FFFFFF")).toBeNear(1, 1e-9)
		T.expect(StyleRules.luminance("#000000")).toBe(0)
		T.expect(StyleRules.luminance("#FFF")).toBe(-1)
		T.expect(StyleRules.distance("#3DDC84", "#3DDC84")).toBe(0)
		T.expect(StyleRules.distance("#000000", "#FFFFFF")).toBeNear(StyleRules.distance("#FFFFFF", "#000000"), 1e-9)
		T.expect(StyleRules.distance("#000000", "#FFFFFF")).toBeGreaterThan(700)
		T.expect(StyleRules.distance("nope", "#FFFFFF")).toBe(-1)
		-- the Classic floors' greenest tile (plot 6) is still this far from the pads
		T.expect(StyleRules.distance("#95D4BB", Theme.world.collectPad)).toBeGreaterThan(StyleRules.MIN_PAD_CONTRAST)
	end)
end)

T.describe("StyleRules validation", function()
	local function titleProblems(edit: (Types.TitleDef) -> ()): { string }
		local def = table.clone(title("masterThief"))
		edit(def)
		local config = table.clone(Titles)
		config.list = { def }
		return StyleRules.validateTitles(config, limits)
	end

	T.it("catches a bad title", function()
		T.expect(#titleProblems(function() end)).toBe(0)
		local cases: { [string]: (Types.TitleDef) -> () } = {
			id = function(def)
				def.id = "master thief"
			end,
			text = function(def)
				def.text = "The Greatest Snack Thief Ever"
			end,
			newline = function(def)
				def.text = "Master\nThief"
			end,
			rich = function(def)
				def.text = "<b>Thief</b>"
			end,
			icon = function(def)
				def.icon = ""
			end,
			hex = function(def)
				def.color = "red"
			end,
			dark = function(def)
				def.color = "#3A4AA8"
			end,
			free = function(def)
				def.unlock = { kind = "free" }
			end,
			achievement = function(def)
				def.unlock = { kind = "achievement", id = "noSuchThing" }
			end,
			rebirths = function(def)
				def.unlock = { kind = "rebirths", count = Economy.rebirth.maxRebirths + 1 }
			end,
			tiers = function(def)
				def.unlock = { kind = "tiers", count = 0 }
			end,
			fraction = function(def)
				def.unlock = { kind = "rebirths", count = 1.5 }
			end,
		}
		for name, edit in cases do
			if #titleProblems(edit) == 0 then
				error(`a title with a bad {name} passed`)
			end
		end
	end)

	T.it("catches duplicate titles and a nametag out of range", function()
		local config = table.clone(Titles)
		config.list = { title("mvp"), title("mvp") }
		T.expect(#StyleRules.validateTitles(config, limits)).toBe(1)
		config = table.clone(Titles)
		config.nametag = table.clone(Titles.nametag)
		config.nametag.maxDistance = 1000
		T.expect(#StyleRules.validateTitles(config, limits)).toBe(1)
	end)

	local function skinProblems(id: string, edit: (Types.SkinDef, Types.SkinLook?) -> ()): { string }
		local list: { Types.SkinDef } = {}
		for _, def in Skins.list do
			local copy = table.clone(def)
			if copy.look then
				copy.look = table.clone(copy.look)
				copy.look.tiles = table.clone(copy.look.tiles)
			end
			if copy.id == id then
				edit(copy, copy.look)
			end
			table.insert(list, copy)
		end
		return StyleRules.validateSkins({ list = list, default = Skins.default }, limits, PAD)
	end

	T.it("catches a bad skin", function()
		T.expect(#skinProblems("mintChip", function() end)).toBe(0)
		local cases: { [string]: (Types.SkinDef, Types.SkinLook?) -> () } = {
			free = function(def)
				def.unlock = { kind = "free" }
			end,
			noLook = function(def)
				def.look = nil
			end,
			oneTile = function(_, look)
				(look :: Types.SkinLook).tiles = { "#D2F7EA" }
			end,
			padGreen = function(_, look)
				(look :: Types.SkinLook).tiles[1] = "#4FDC8A" -- would hide the collect pads
			end,
			badHex = function(_, look)
				(look :: Types.SkinLook).rug = "brown"
			end,
			glowingFloor = function(_, look)
				(look :: Types.SkinLook).tileMaterial = "Neon"
			end,
			glassRug = function(_, look)
				(look :: Types.SkinLook).rugMaterial = "Glass"
			end,
			icyTrim = function(_, look)
				(look :: Types.SkinLook).trimMaterial = "Ice" -- the wall tops are solid: no slipping
			end,
			name = function(def)
				def.name = "Mint Chocolate Chip Swirl"
			end,
			unknownAchievement = function(def)
				def.unlock = { kind = "achievement", id = "nope" }
			end,
		}
		for name, edit in cases do
			if #skinProblems("mintChip", edit) == 0 then
				error(`a skin with a bad {name} passed`)
			end
		end
	end)

	T.it("needs a free default skin with the plot's own look", function()
		T.expect(#skinProblems("classic", function(def)
			def.unlock = { kind = "tiers", count = 1 }
		end)).toBeGreaterThan(0)
		local list = table.clone(Skins.list)
		T.expect(#StyleRules.validateSkins({ list = list, default = "nope" }, limits, PAD)).toBeGreaterThan(0)
	end)
end)

return nil
