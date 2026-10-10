--!strict
--[[
	Sound effects and music. Plain data only.

	Each effect is { id, volume?, pitch? }: `id` is an uploaded asset ("rbxassetid://123456") or a file that ships
	inside the Roblox client ("rbxasset://sounds/<file>"); volume 0..1 (default 0.5); pitch = playback speed (default 1,
	0.5..2). An empty id (or a plain "" instead of the table) is silent. Every built-in file used here is listed in
	README.md ("Sounds") so it can be checked in Studio.

	TODO(owner): music. Roblox ships no music, so the tracks are empty: paste an audio asset id into `music.lobby`
	(plays everywhere) and optionally a seasonal track keyed by Config/Seasons theme id (e.g. `halloween`, played
	while that theme is on). The player loops it, crossfades when the track changes and respects the Music setting.
]]

local Types = require("../Types")

type SoundSlot = Types.SoundSlot

local BUTTON = "rbxasset://sounds/button.wav"
local PING = "rbxasset://sounds/electronicpingshort.wav"
local HIT = "rbxasset://sounds/hit.wav"
local VICTORY = "rbxasset://sounds/victory.wav"
local SNAP = "rbxasset://sounds/snap.wav"
local SWOOSH = "rbxasset://sounds/swoosh.wav"
local PAGE = "rbxasset://sounds/pageturn.wav"
local CLICK_FAST = "rbxasset://sounds/clickfast.wav"

local Sounds = {
	ui = {
		click = { id = BUTTON, volume = 0.4, pitch = 1.15 }, -- every button (UiKit)
		toggle = { id = CLICK_FAST, volume = 0.4, pitch = 1.1 }, -- settings switches
		open = { id = PAGE, volume = 0.35, pitch = 1.1 }, -- a dialog opens
		purchase = { id = PING, volume = 0.45, pitch = 1.25 }, -- success toasts
		error = { id = HIT, volume = 0.3, pitch = 0.75 }, -- "Not enough cash!" and other refusals
		claim = { id = VICTORY, volume = 0.45 },
	} :: { [string]: SoundSlot },
	world = {
		buy = { id = PING, volume = 0.3 }, -- a Snackling flies off the belt to its buyer's base
		collect = { id = SNAP, volume = 0.4, pitch = 1.5 }, -- cash collected from a pad
		sell = { id = SWOOSH, volume = 0.45, pitch = 1.2 },
		lock = { id = SNAP, volume = 0.6, pitch = 0.75 },
		unlock = { id = SNAP, volume = 0.5, pitch = 1.1 },
		stealStart = { id = SWOOSH, volume = 0.6, pitch = 0.85 },
		stealSuccess = { id = VICTORY, volume = 0.55, pitch = 1.1 },
		tagged = { id = HIT, volume = 0.55 },
		alarm = { id = PING, volume = 0.7, pitch = 0.7 }, -- plays for the owner while someone carries their Snackling
		rebirth = { id = VICTORY, volume = 0.6, pitch = 0.9 },
		announce = { id = SWOOSH, volume = 0.35, pitch = 1.3 }, -- a server-wide banner slides in
		luck = { id = VICTORY, volume = 0.45, pitch = 1.25 },
		mutation = { id = PING, volume = 0.45, pitch = 1.6 }, -- a mutated Snackling (Golden, Diamond...) appears on the belt
	} :: { [string]: SoundSlot },
	-- Played when a creature of this rarity appears on the belt near you / lands in your base.
	rarity = {
		Common = { id = SNAP, volume = 0.3, pitch = 1.2 },
		Uncommon = { id = SNAP, volume = 0.3, pitch = 1.4 },
		Rare = { id = PING, volume = 0.35 },
		Epic = { id = PING, volume = 0.4, pitch = 1.2 },
		Legendary = { id = VICTORY, volume = 0.45 },
		Mythic = { id = VICTORY, volume = 0.5, pitch = 1.15 },
		Secret = { id = VICTORY, volume = 0.55, pitch = 0.8 },
	} :: { [string]: SoundSlot },
	-- Looping music. `lobby` plays by default; a key matching a seasonal theme id plays while that theme is on.
	music = {
		lobby = { id = "", volume = 0.3 },
		halloween = { id = "", volume = 0.3 },
	} :: { [string]: Types.MusicTrack },
	musicFadeSeconds = 2.5, -- crossfade between tracks, and fade in / out when Music is switched on / off
}

return Sounds
