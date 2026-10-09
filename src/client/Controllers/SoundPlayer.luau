--!strict
--[[
	Plays UI / world sounds from Config/Sounds. Empty ids are skipped, so the game is silent until real sound
	assets are configured.
]]

local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sounds = require(ReplicatedStorage.Shared.Config.Sounds)

local SoundPlayer = {}

local cache: { [string]: Sound } = {}

function SoundPlayer.play(soundId: string, volume: number?)
	if soundId == "" then
		return
	end
	local cached: Sound? = cache[soundId]
	local sound: Sound
	if cached then
		sound = cached
	else
		sound = Instance.new("Sound")
		sound.SoundId = soundId
		sound.Parent = SoundService
		cache[soundId] = sound
	end
	sound.Volume = volume or 0.6
	SoundService:PlayLocalSound(sound)
end

function SoundPlayer.ui(name: string)
	SoundPlayer.play(((Sounds.ui :: any) :: { [string]: string })[name] or "")
end

function SoundPlayer.world(name: string)
	SoundPlayer.play(((Sounds.world :: any) :: { [string]: string })[name] or "")
end

function SoundPlayer.rarity(rarityId: string)
	SoundPlayer.play(Sounds.rarity[rarityId] or "")
end

return SoundPlayer
