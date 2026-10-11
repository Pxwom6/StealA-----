--!strict
--[[
	Player settings (music, sound effects, reduce effects). They are saved in the save's existing `flags` map as
	`settings_<key> = true` (a missing flag means false), so there is no save-format change: DataSchema.sanitise
	already keeps every `true` flag, and a code rollback keeps them too. Pure: no Roblox APIs.

	The client applies a change at once and sends the SetSetting intent; the server checks the key against KEYS and the
	value is a boolean, then updates the flag (SettingsService).
]]

local Types = require("../Types")

local SettingsRules = {}

-- Every setting, in the order the settings panel lists them. Never rename one: they are in players' saves.
SettingsRules.KEYS = { "musicOff", "sfxOff", "reduceEffects" } :: { string }

SettingsRules.FLAG_PREFIX = "settings_"

function SettingsRules.flagName(key: string): string
	return SettingsRules.FLAG_PREFIX .. key
end

-- `value` if it is a known setting key, else nil (for remote arguments).
function SettingsRules.key(value: unknown): string?
	if type(value) ~= "string" then
		return nil
	end
	for _, key in SettingsRules.KEYS do
		if key == value then
			return key
		end
	end
	return nil
end

function SettingsRules.fromFlags(flags: { [string]: boolean }): Types.SettingsView
	return {
		musicOff = flags[SettingsRules.flagName("musicOff")] == true,
		sfxOff = flags[SettingsRules.flagName("sfxOff")] == true,
		reduceEffects = flags[SettingsRules.flagName("reduceEffects")] == true,
	}
end

-- Sets a setting in `flags` (true = flag set, false = flag removed). Returns whether anything changed.
function SettingsRules.apply(flags: { [string]: boolean }, key: string, on: boolean): boolean
	if SettingsRules.key(key) == nil then
		return false
	end
	local name = SettingsRules.flagName(key)
	local was = flags[name] == true
	if was == on then
		return false
	end
	if on then
		flags[name] = true
	else
		flags[name] = nil
	end
	return true
end

-- The value of one setting in a view (false for an unknown key).
function SettingsRules.get(view: Types.SettingsView, key: string): boolean
	if key == "musicOff" then
		return view.musicOff
	elseif key == "sfxOff" then
		return view.sfxOff
	elseif key == "reduceEffects" then
		return view.reduceEffects
	end
	return false
end

-- A copy of `view` with one setting changed (unknown keys change nothing).
function SettingsRules.with(view: Types.SettingsView, key: string, on: boolean): Types.SettingsView
	return {
		musicOff = if key == "musicOff" then on else view.musicOff,
		sfxOff = if key == "sfxOff" then on else view.sfxOff,
		reduceEffects = if key == "reduceEffects" then on else view.reduceEffects,
	}
end

return SettingsRules
