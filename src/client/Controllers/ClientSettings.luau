--!strict
--[[
	The local player's settings, readable by any client code:

	  ClientSettings.reduceEffects()  -- true: skip particles, idle animations and other flair (low-end phones)
	  ClientSettings.sfxOn() / ClientSettings.musicOn()
	  ClientSettings.onChanged(function(settings: Types.SettingsView) ... end)

	The LocalPlayer also carries the attribute "ReduceEffects" (boolean) for shared modules that can't require client
	code (e.g. `Players.LocalPlayer:GetAttribute("ReduceEffects") == true`).

	A change applies at once and goes to the server as the SetSetting intent (quick taps on the same setting are
	coalesced into one message); the saved values come back with the first StateUpdate after joining.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Types = require(ReplicatedStorage.Shared.Types)
local SettingsRules = require(ReplicatedStorage.Shared.Logic.SettingsRules)
local StateStore = require(script.Parent.StateStore)

local ClientSettings = {}

ClientSettings.REDUCE_EFFECTS_ATTRIBUTE = "ReduceEffects"

local SEND_DELAY = 0.75 -- seconds a change waits for more changes before it is sent

local current: Types.SettingsView = { musicOff = false, sfxOff = false, reduceEffects = false }
local listeners: { (Types.SettingsView) -> () } = {}
local adopted = false -- the saved settings arrived, or the player changed one first (theirs wins)
local pending: { [string]: boolean } = {}
local sendScheduled = false

local function notify()
	Players.LocalPlayer:SetAttribute(ClientSettings.REDUCE_EFFECTS_ATTRIBUTE, current.reduceEffects)
	for _, listener in listeners do
		task.spawn(listener, current)
	end
end

function ClientSettings.get(): Types.SettingsView
	return current
end

function ClientSettings.musicOn(): boolean
	return not current.musicOff
end

function ClientSettings.sfxOn(): boolean
	return not current.sfxOff
end

function ClientSettings.reduceEffects(): boolean
	return current.reduceEffects
end

-- Calls `listener` whenever a setting changes (not right away).
function ClientSettings.onChanged(listener: (Types.SettingsView) -> ())
	table.insert(listeners, listener)
end

local function flush()
	sendScheduled = false
	for key, value in pending do
		Net.get("SetSetting"):FireServer(key, value)
	end
	table.clear(pending)
end

function ClientSettings.set(key: string, on: boolean)
	if SettingsRules.key(key) == nil or SettingsRules.get(current, key) == on then
		return
	end
	current = SettingsRules.with(current, key, on)
	adopted = true
	pending[key] = on
	if not sendScheduled then
		sendScheduled = true
		task.delay(SEND_DELAY, flush)
	end
	notify()
end

function ClientSettings.start()
	Players.LocalPlayer:SetAttribute(ClientSettings.REDUCE_EFFECTS_ATTRIBUTE, false)
	StateStore.onChange(function(state)
		local saved = state.settings
		if adopted or saved == nil then
			return
		end
		adopted = true
		if
			saved.musicOff ~= current.musicOff
			or saved.sfxOff ~= current.sfxOff
			or saved.reduceEffects ~= current.reduceEffects
		then
			current = table.clone(saved)
			notify()
		end
	end)
end

return ClientSettings
