--!strict
--[[
	Background music (Config/Sounds.music): the `lobby` track, or the track named after the seasonal theme that is on
	(workspace attribute SeasonTheme, e.g. "halloween"), looping. Changing track crossfades; switching Music off in
	Settings fades it out, and on again fades back in. A track with an empty id is silent, so nothing plays until the
	owner pastes an audio id into Config/Sounds. A track that fails to load (a removed or private audio) is skipped
	for the rest of the session: a seasonal one falls back to the lobby track.
]]

local ContentProvider = game:GetService("ContentProvider")
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
-- Audio ids that failed to load this session.
local broken: { [string]: boolean } = {}

local function usable(track: Types.MusicTrack?): boolean
	return track ~= nil and track.id ~= "" and not broken[track.id]
end

local function trackFor(theme: string): Types.MusicTrack?
	local seasonal = if theme ~= "" then Sounds.music[theme] else nil
	if usable(seasonal) then
		return seasonal
	end
	local lobby = Sounds.music.lobby
	if usable(lobby) then
		return lobby
	end
	return nil
end

-- Waits for `sound` to load; if it can't, skips its id from now on and picks the next track.
local function watchLoad(sound: Sound, id: string)
	task.spawn(function()
		local failed = false
		local ok = pcall(function()
			ContentProvider:PreloadAsync({ sound }, function(_, status: Enum.AssetFetchStatus)
				if status == Enum.AssetFetchStatus.Failure then
					failed = true
				end
			end)
		end)
		if (failed or not ok) and not broken[id] then
			warn(`[Music] {id} did not load; skipping it`)
			broken[id] = true
			local playing = current
			if playing and playing.sound == sound then
				MusicController.refresh()
			end
		end
	end)
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
	watchLoad(sound, track.id)
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
