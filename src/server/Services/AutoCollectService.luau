--!strict
--[[
	Auto Collect (the game pass Config/Monetization.passes.AutoCollect): every `perks.autoCollectSeconds` the cash
	waiting on an owner's active pads is collected for them, wherever they are, carrying a Snackling or not.

	It is the pad path (EconomyService.collectPad), pad by pad, like the Snack Magnet: the same "+$X" over each pad,
	the same "collect" gameplay event (quests, the tutorial's collect step) and the same analytics. The feedback is
	toned down because it runs every few seconds: the Effects are quiet (the client plays no sound and floats the
	"+$X" only over pads near its camera) and nothing toasts.

	Ownership is the session's, checked live like every pass (never saved, DECISIONS.md #11). One timer for everyone,
	checked twice a second (Logic/AutoCollectRules.due per player, so a collect lands within half a second of being
	due): no per-frame loop. A Snack Magnet owned by a pass holder shows "AUTO" and stays unused
	(GadgetRules.coveredByAutoCollect).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)
local AutoCollectRules = require(ReplicatedStorage.Shared.Logic.AutoCollectRules)
local EconomyService = require(script.Parent.EconomyService)
local PlotService = require(script.Parent.PlotService)
local Sessions = require(script.Parent.Sessions)

type Session = Sessions.Session

local CHECK_SECONDS = 0.5

local AutoCollectService = {}

-- When each pass holder's pads were last collected (os.clock()); nil until the first collect after the pass is on.
local lastAt: { [Session]: number } = setmetatable({}, { __mode = "k" }) :: any

-- Collects every active pad of `session`'s base through the pad path, quietly. Returns the cash collected.
function AutoCollectService.collect(session: Session): number
	if session.plot == 0 then
		return 0
	end
	local total = 0
	for _, podium in PlotService.refs(session.plot).podiums do
		if podium.index > session.capacity then
			break
		end
		total += EconomyService.collectPad(session, podium, true)
	end
	return total
end

local function step(now: number)
	local interval = Monetization.perks.autoCollectSeconds
	for _, session in Sessions.all() do
		if not session.passes.AutoCollect or session.plot == 0 then
			lastAt[session] = nil -- the first collect comes as soon as the pass is on
			continue
		end
		if AutoCollectRules.due(lastAt[session], now, interval) then
			lastAt[session] = now
			AutoCollectService.collect(session)
		end
	end
end

function AutoCollectService.start()
	for _, problem in AutoCollectRules.validate(Monetization.perks.autoCollectSeconds) do
		warn(`[AutoCollect] config problem: {problem}`)
	end
	-- One error must not stop collecting for good: the body runs protected.
	task.spawn(function()
		while true do
			task.wait(CHECK_SECONDS)
			local ok, err = pcall(step :: (number) -> ...any, os.clock())
			if not ok then
				warn(`[AutoCollect] {err}`)
			end
		end
	end)
end

return AutoCollectService
