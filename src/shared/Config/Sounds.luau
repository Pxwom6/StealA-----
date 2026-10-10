--!strict
--[[
	Sound effects and music. Plain data only.

	Each effect is { id, volume?, pitch? }: `id` is an audio asset ("rbxassetid://123456"); volume 0..1 (default 0.5);
	pitch = playback speed (default 1, 0.5..2). An empty id (or a plain "" instead of the table) is silent.

	Every id below is a public Roblox-library asset that was checked to load in Studio (Oct 2026):
	  * Roblox's own UI sound set ("Roblox_UI_*", uploaded by Roblox),
	  * Roblox's licensed music library (APMOfficial) and sound-effects library (ProSoundEffects).
	They work in any experience. To swap one, paste another audio asset id; README.md lists what each slot is for.
]]

local Types = require("../Types")

type SoundSlot = Types.SoundSlot

-- Roblox UI sound set (creator: Roblox)
local CLICK = "rbxassetid://15675032796" -- Roblox_UI_Small_Click
local BRIGHT_CLICK = "rbxassetid://15675059323" -- Roblox_UI_Bright_Click
local POP = "rbxassetid://15675055424" -- Roblox_UI_Cute_Pop
local DELETE = "rbxassetid://15675075163" -- Roblox_UI_Delete
local PAPER = "rbxassetid://15675037413" -- Roblox_UI_Paper_Swipe
local INDICATOR = "rbxassetid://15675085146" -- Roblox_UI_Indicator
local STINGER = "rbxassetid://15675043410" -- Roblox_UI_Tonal_Stinger
local SWEEP = "rbxassetid://15675046931" -- Roblox_UI_Sweep
local WHOOSH = "rbxassetid://15675024286" -- Roblox_UI_Whoosh_01
local WHOOSH_SHORT = "rbxassetid://15675012262" -- Roblox_UI_Whoosh_04
local WHISTLE_LOW = "rbxassetid://15675062723" -- Roblox_UI_Whistle_Low
local PIANO_HELLO = "rbxassetid://15675016548" -- Roblox_UI_Piano_Hello
local COINS = "rbxassetid://127645268874265" -- CoinTransfer_01 (creator: Roblox)
-- ProSoundEffects (Roblox's licensed SFX library)
local POLICE_WHISTLE = "rbxassetid://9125775930" -- Police Whistle Long Short Various Versions 2
-- APMOfficial (Roblox's licensed music library): short stings
local TOY_RACE_STING = "rbxassetid://1842030434" -- The Big Toy Race (sting d)
local FUNFAIR_STING = "rbxassetid://9038314266" -- Funfair Fun (sting)
local EARLY_BIRD = "rbxassetid://9040476631" -- Early Bird - Mnemonic2

local Sounds = {
	ui = {
		click = { id = CLICK, volume = 0.45 }, -- every button (UiKit)
		toggle = { id = BRIGHT_CLICK, volume = 0.45 }, -- settings switches
		open = { id = PAPER, volume = 0.3, pitch = 1.15 }, -- a dialog opens
		purchase = { id = COINS, volume = 0.5, pitch = 1.1 }, -- success toasts
		error = { id = DELETE, volume = 0.35, pitch = 0.9 }, -- "Not enough cash!" and other refusals
		claim = { id = EARLY_BIRD, volume = 0.45 },
	} :: { [string]: SoundSlot },
	world = {
		buy = { id = POP, volume = 0.45 }, -- a Snackling flies off the belt to its buyer's base
		collect = { id = COINS, volume = 0.4, pitch = 1.2 }, -- cash collected from a pad
		sell = { id = PAPER, volume = 0.45, pitch = 0.9 },
		lock = { id = INDICATOR, volume = 0.45, pitch = 0.9 },
		unlock = { id = SWEEP, volume = 0.45 },
		stealStart = { id = WHOOSH, volume = 0.6, pitch = 0.9 },
		stealSuccess = { id = STINGER, volume = 0.55, pitch = 1.1 },
		tagged = { id = WHISTLE_LOW, volume = 0.6 },
		alarm = { id = POLICE_WHISTLE, volume = 0.6 }, -- plays for the owner while someone carries their Snackling
		rebirth = { id = TOY_RACE_STING, volume = 0.55 },
		announce = { id = WHOOSH_SHORT, volume = 0.4, pitch = 1.2 }, -- a server-wide banner slides in
		luck = { id = FUNFAIR_STING, volume = 0.45 },
		mutation = { id = PIANO_HELLO, volume = 0.45, pitch = 1.2 }, -- a mutated Snackling (Golden, Diamond...) appears on the belt
	} :: { [string]: SoundSlot },
	-- Played when a creature of this rarity appears on the belt near you / lands in your base.
	rarity = {
		Common = { id = POP, volume = 0.3, pitch = 1.1 },
		Uncommon = { id = POP, volume = 0.35, pitch = 1.3 },
		Rare = { id = BRIGHT_CLICK, volume = 0.4 },
		Epic = { id = STINGER, volume = 0.4, pitch = 1.1 },
		Legendary = { id = PIANO_HELLO, volume = 0.45 },
		Mythic = { id = FUNFAIR_STING, volume = 0.5 },
		Secret = { id = TOY_RACE_STING, volume = 0.55, pitch = 0.95 },
	} :: { [string]: SoundSlot },
	-- Looping music (APMOfficial). `lobby` plays by default; a key matching a seasonal theme id plays while that
	-- theme is on.
	music = {
		lobby = { id = "rbxassetid://1842203609", volume = 0.25 }, -- Laugh To Learn (59 s loop)
		halloween = { id = "rbxassetid://1848232312", volume = 0.3 }, -- Hear, The Wind Blows (49 s)
	} :: { [string]: Types.MusicTrack },
	musicFadeSeconds = 2.5, -- crossfade between tracks, and fade in / out when Music is switched on / off
}

return Sounds
