--!strict
--[[
	Plays sound effects from Config/Sounds (ui / world / rarity slots). A slot is { id, volume?, pitch? } or a plain id
	string; an empty id is silent, so the game runs fine with no sound configured. Nothing plays while Sound effects
	are switched off (ClientSettings). The same sound asked for twice within a frame or two (a button's own click and
	its handler's click) plays once.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Sounds = require(ReplicatedStorage.Shared.Config.Sounds)
local Types = require(ReplicatedStorage.Shared.Types)
local ClientSettings = require(script.Parent.ClientSettings)

local SoundPlayer = {}

local DEFAULT_VOLUME = 0.5
local REPEAT_GUARD = 0.05 -- seconds

local cache: { [string]: Sound } = {}
local lastPlayed: { [string]: number } = {}
local effectsGroup: SoundGroup? = nil

local function group(): SoundGroup
	local existing = effectsGroup
	if existing then
		return existing
	end
	local newGroup = Instance.new("SoundGroup")
	newGroup.Name = "Effects"
	newGroup.Volume = 1
	newGroup.Parent = SoundService
	effectsGroup = newGroup
	return newGroup
end

local function play(id: string, volume: number, pitch: number)
	if id == "" or not ClientSettings.sfxOn() then
		return
	end
	local key = `{id}|{volume}|{pitch}`
	local now = os.clock()
	local last = lastPlayed[key]
	if last and now - last < REPEAT_GUARD then
		return
	end
	lastPlayed[key] = now
	local sound: Sound? = cache[key]
	if sound == nil then
		local newSound = Instance.new("Sound")
		newSound.Name = "Sfx"
		newSound.SoundId = id
		newSound.Volume = volume
		newSound.PlaybackSpeed = pitch
		newSound.SoundGroup = group()
		newSound.Parent = SoundService
		cache[key] = newSound
		sound = newSound
	end
	SoundService:PlayLocalSound(sound)
end

local function playSlot(slot: Types.SoundSlot?, volumeOverride: number?)
	if slot == nil then
		return
	end
	if type(slot) == "string" then
		play(slot, volumeOverride or DEFAULT_VOLUME, 1)
	else
		play(slot.id, volumeOverride or slot.volume or DEFAULT_VOLUME, slot.pitch or 1)
	end
end

-- Plays a slot ({ id, volume?, pitch? }) or a raw sound id; `volume` overrides the slot's.
function SoundPlayer.play(sound: Types.SoundSlot, volume: number?)
	playSlot(sound, volume)
end

function SoundPlayer.ui(name: string)
	playSlot(Sounds.ui[name])
end

function SoundPlayer.world(name: string)
	playSlot(Sounds.world[name])
end

function SoundPlayer.rarity(rarityId: string)
	playSlot(Sounds.rarity[rarityId])
end

return SoundPlayer
