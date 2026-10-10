--!strict
local T = require("./TestKit")
local SettingsRules = require("../src/shared/Logic/SettingsRules")
local ScreenLayout = require("../src/shared/Logic/ScreenLayout")
local DataSchema = require("../src/shared/Logic/DataSchema")
local Sounds = require("../src/shared/Config/Sounds")
local Seasons = require("../src/shared/Config/Seasons")
local Rarities = require("../src/shared/Config/Rarities")
local Theme = require("../src/shared/Config/Theme")
local Types = require("../src/shared/Types")

T.describe("SettingsRules", function()
	T.it("reads every setting from the flags, defaulting to off", function()
		T.expect(SettingsRules.fromFlags({})).toEqual({ musicOff = false, sfxOff = false, reduceEffects = false })
		local view = SettingsRules.fromFlags({ settings_musicOff = true, settings_reduceEffects = true, other = true })
		T.expect(view).toEqual({ musicOff = true, sfxOff = false, reduceEffects = true })
	end)
	T.it("stores a setting as a flag and removes it when switched back off", function()
		local flags: { [string]: boolean } = {}
		T.expect(SettingsRules.apply(flags, "sfxOff", true)).toBe(true)
		T.expect(flags.settings_sfxOff).toBe(true)
		T.expect(SettingsRules.apply(flags, "sfxOff", true)).toBe(false) -- no change
		T.expect(SettingsRules.apply(flags, "sfxOff", false)).toBe(true)
		T.expect(flags.settings_sfxOff).toBeNil()
	end)
	T.it("only accepts known keys", function()
		local flags: { [string]: boolean } = {}
		T.expect(SettingsRules.key("musicOff")).toBe("musicOff")
		T.expect(SettingsRules.key("tutorial_done")).toBeNil()
		T.expect(SettingsRules.key(42)).toBeNil()
		T.expect(SettingsRules.key(nil)).toBeNil()
		T.expect(SettingsRules.apply(flags, "tutorial_done", true)).toBe(false)
		T.expect((next(flags))).toBeNil()
	end)
	T.it("survives a save round trip without a schema change", function()
		local rules: DataSchema.SanitiseRules = {
			isValidCreature = function(_id: string): boolean
				return true
			end,
			maxPodiums = 20,
			maxPodiumUpgrades = 8,
			startingPodiums = 8,
			maxRebirths = 30,
			maxReceipts = 3,
			maxHistory = 2,
		}
		local data = DataSchema.template(0)
		SettingsRules.apply(data.flags, "musicOff", true)
		SettingsRules.apply(data.flags, "reduceEffects", true)
		local clean = DataSchema.sanitise(data :: any, 0, rules)
		T.expect(SettingsRules.fromFlags(clean.flags))
			.toEqual({ musicOff = true, sfxOff = false, reduceEffects = true })
	end)
	T.it("gets and changes one setting of a view", function()
		local view: Types.SettingsView = { musicOff = false, sfxOff = true, reduceEffects = false }
		T.expect(SettingsRules.get(view, "sfxOff")).toBe(true)
		T.expect(SettingsRules.get(view, "nope")).toBe(false)
		T.expect(SettingsRules.with(view, "musicOff", true))
			.toEqual({ musicOff = true, sfxOff = true, reduceEffects = false })
		T.expect(SettingsRules.with(view, "nope", true)).toEqual(view)
	end)
	T.it("has a label for every setting", function()
		local text = (Theme.text :: any) :: { [string]: string }
		T.expect(text.settingsMusic ~= nil and text.settingsSfx ~= nil and text.settingsReduceFx ~= nil).toBe(true)
		T.expect(#SettingsRules.KEYS).toBe(3)
	end)
end)

T.describe("ScreenLayout", function()
	T.it("reserves no corner on phones or when the player list is off", function()
		T.expect(ScreenLayout.playerListWidth(true, true, 667, 375, 2)).toBe(0) -- iPhone SE landscape
		T.expect(ScreenLayout.playerListWidth(false, false, 1920, 1080, 2)).toBe(0)
	end)
	T.it("reserves the player list's width on computers, wider with more leaderstats", function()
		local two = ScreenLayout.playerListWidth(true, false, 1920, 1080, 2)
		local four = ScreenLayout.playerListWidth(true, false, 1920, 1080, 4)
		T.expect(two).toBeGreaterThan(300)
		T.expect(four).toBeGreaterThan(two)
		T.expect(ScreenLayout.playerListWidth(true, false, 1920, 1080, 50)).toBeAtMost(500)
		-- tablets keep the reserve (touch, but a big screen)
		T.expect(ScreenLayout.playerListWidth(true, true, 1024, 768, 2)).toBe(two)
	end)
	T.it("puts the gear in the corner, or left of the player list when there is room", function()
		T.expect(ScreenLayout.gearX(785, 0, 44, 8, 125)).toBe(733)
		-- 1280 px wide at UI scale 1.33: 962 units, player list about 255 units
		local x = ScreenLayout.gearX(962, 255, 44, 8, 125)
		T.expect(x + 44).toBeAtMost(962 - 255)
		T.expect(x).toBeGreaterThan(962 / 2 + 125)
		-- too narrow to fit beside it without covering the cash: back in the corner
		T.expect(ScreenLayout.gearX(593, 245, 44, 8, 125)).toBe(593 - 8 - 44)
	end)
	T.it("keeps the tutorial banner left of the player list and hides the list when even that cannot work", function()
		-- 1100 px Studio window at scale 1.35: 815 units wide, player list 252 units
		T.expect(ScreenLayout.bannerRightLimit(700, 815, 252)).toBe(563)
		T.expect(ScreenLayout.bannerRightLimit(611, 785, 0)).toBe(611)
		T.expect(ScreenLayout.bannerNeedsPlayerListHidden(400, 300, 815, 252, 6)).toBe(false)
		T.expect(ScreenLayout.bannerNeedsPlayerListHidden(407.5, 300, 815, 252, 6)).toBe(true) -- 0.5 too far
		T.expect(ScreenLayout.bannerNeedsPlayerListHidden(296, 300, 593, 245, 6)).toBe(true)
		T.expect(ScreenLayout.bannerNeedsPlayerListHidden(296, 300, 593, 0, 6)).toBe(false)
	end)
end)

T.describe("Config/Sounds", function()
	local function check(slot: Types.SoundSlot, where: string)
		local id = if type(slot) == "string" then slot else slot.id
		local ok = id == ""
			or string.match(id, "^rbxassetid://%d+$") ~= nil
			or string.match(id, "^rbxasset://sounds/[%w_%. ]+%.%a+$") ~= nil
		if not ok then
			error(`{where}: "{id}" is not an asset id or a built-in rbxasset://sounds/ file`)
		end
		if type(slot) == "table" then
			local volume = slot.volume or 0.5
			local pitch = slot.pitch or 1
			if not (volume >= 0 and volume <= 1) then
				error(`{where}: volume must be 0..1`)
			end
			if not (pitch >= 0.5 and pitch <= 2) then
				error(`{where}: pitch must be 0.5..2`)
			end
		end
	end
	T.it("every sound is silent, an uploaded asset or a built-in file, with sane volume and pitch", function()
		for name, slot in Sounds.ui do
			check(slot, `ui.{name}`)
		end
		for name, slot in Sounds.world do
			check(slot, `world.{name}`)
		end
		for name, slot in Sounds.rarity do
			check(slot, `rarity.{name}`)
		end
		for name, track in Sounds.music do
			check({ id = track.id, volume = track.volume }, `music.{name}`)
		end
		T.expect(Sounds.musicFadeSeconds).toBeGreaterThan(0)
	end)
	T.it("has the slots the game plays", function()
		for _, name in { "click", "toggle", "open", "purchase", "error", "claim" } do
			T.expect(Sounds.ui[name] ~= nil).toBe(true)
		end
		for _, name in { "buy", "collect", "sell", "lock", "stealStart", "stealSuccess", "tagged", "alarm" } do
			T.expect(Sounds.world[name] ~= nil).toBe(true)
		end
		for _, rarity in Rarities do
			T.expect(Sounds.rarity[rarity.id] ~= nil).toBe(true)
		end
		T.expect(Sounds.music.lobby ~= nil).toBe(true)
	end)
	T.it("music slots other than lobby are seasonal theme ids", function()
		for name in Sounds.music do
			T.expect(name == "lobby" or Seasons.themes[name] ~= nil).toBe(true)
		end
	end)
end)

return nil
