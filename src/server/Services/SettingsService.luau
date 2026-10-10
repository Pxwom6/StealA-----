--!strict
--[[
	Player settings (Music, Sound effects, Reduce effects). The client applies a toggle at once and sends the
	SetSetting intent (rate-limited); this service checks the key is a known setting and the value a boolean, then saves
	it in the existing `flags` map as `settings_<key>` (Logic/SettingsRules; no save-format change). The value comes
	back to the owner in StateUpdate.settings, which is how the client restores it on the next join.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SettingsRules = require(ReplicatedStorage.Shared.Logic.SettingsRules)
local Remotes = require(script.Parent.Remotes)
local Replication = require(script.Parent.Replication)
local Sessions = require(script.Parent.Sessions)

local SettingsService = {}

local function onSetSetting(player: Player, rawKey: unknown, rawValue: unknown)
	local key = SettingsRules.key(rawKey)
	if key == nil or type(rawValue) ~= "boolean" then
		return
	end
	local session = Sessions.get(player)
	if session == nil then
		return
	end
	if SettingsRules.apply(session.data.flags, key, rawValue) then
		Replication.markDirty(session)
	end
end

function SettingsService.start()
	Remotes.onIntent("SetSetting", onSetSetting)
end

return SettingsService
