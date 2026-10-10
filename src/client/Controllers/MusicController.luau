--!strict
--[[
	Background music (Config/Sounds.music): the `lobby` track, or the track named after the seasonal theme that is on
	(workspace attribute SeasonTheme, e.g. "halloween"), looping. Changing track crossfades; switching Music off in
	Settings fades it out, and on again fades back in. A track with an empty id is silent, so nothing plays until the
	owner pastes an audio id into Config/Sounds.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Sounds = require(ReplicatedStorage.Shared.Config.Sounds)
local Types = require(ReplicatedStorage.Shared.Types)
local ClientSettings = require(script.Parent.ClientSettings)

local MusicController = {}

local DEFAULT_VOLUME = 0.3

type Playing = { sound: Sound, id: string }

local current: Playing? = nil
local musicGroup: SoundGroup

local function trackFor(theme: string): Types.MusicTrack?
	local seasonal = if theme ~= "" then Sounds.music[theme] else nil
	if seasonal and seasonal.id ~= "" then
		return seasonal
	end
	local lobby = Sounds.music.lobby
	if lobby and lobby.id ~= "" then
		return lobby
	end
	return nil
end

local function fadeInfo(): TweenInfo
	return TweenInfo.new(Sounds.musicFadeSeconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
end

local function fadeOut(playing: Playing)
	local tween = TweenService:Create(playing.sound, fadeInfo(), { Volume = 0 })
	tween.Completed:Connect(function()
		playing.sound:Stop()
		playing.sound:Destroy()
	end)
	tween:Play()
end

-- The current track (if any), crossfading from what played before.
function MusicController.refresh()
	local theme = workspace:GetAttribute("SeasonTheme")
	local track = if ClientSettings.musicOn() then trackFor(if type(theme) == "string" then theme else "") else nil
	local id = if track then track.id else ""
	local playing = current
	if playing and playing.id == id then
		return
	end
	if playing then
		fadeOut(playing)
		current = nil
	end
	if track == nil then
		return
	end
	local sound = Instance.new("Sound")
	sound.Name = "Music"
	sound.SoundId = track.id
	sound.Looped = true
	sound.Volume = 0
	sound.SoundGroup = musicGroup
	sound.Parent = SoundService
	sound:Play()
	TweenService:Create(sound, fadeInfo(), { Volume = track.volume or DEFAULT_VOLUME }):Play()
	current = { sound = sound, id = track.id }
end

function MusicController.start()
	musicGroup = Instance.new("SoundGroup")
	musicGroup.Name = "Music"
	musicGroup.Volume = 1
	musicGroup.Parent = SoundService
	workspace:GetAttributeChangedSignal("SeasonTheme"):Connect(MusicController.refresh)
	ClientSettings.onChanged(function()
		MusicController.refresh()
	end)
	MusicController.refresh()
end

return MusicController
