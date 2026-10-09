--!strict
--[[
	Rebirth: spend everything (cash + Snacklings) for a permanent earnings multiplier and a longer base lock.
	Podium upgrades, game passes and stats are kept (Config/Economy.rebirth). Any steal involving the player is
	resolved first so no creature is ever lost "in transit".
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local RebirthMath = require(ReplicatedStorage.Shared.Logic.RebirthMath)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local Analytics = require(script.Parent.Analytics)
local Announcer = require(script.Parent.Announcer)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local LockService = require(script.Parent.LockService)
local PlotService = require(script.Parent.PlotService)
local Remotes = require(script.Parent.Remotes)
local Sessions = require(script.Parent.Sessions)
local StealService = require(script.Parent.StealService)

type Session = Sessions.Session

local CFG = Economy.rebirth

local RebirthService = {}

function RebirthService.rebirth(session: Session): boolean
	local data = session.data
	local ok, reason = RebirthMath.canRebirth(data.cash, data.rebirths, CFG)
	if not ok then
		if reason == "max" then
			Remotes.notify(session.player, Theme.text.rebirthMax, "error")
		else
			local cost = RebirthMath.cost(data.rebirths, CFG) or 0
			Remotes.notify(
				session.player,
				Format.template(Theme.text.rebirthNeed, { amount = UiTheme.cash(cost) }),
				"error"
			)
		end
		return false
	end

	StealService.releaseAll(session, "rebirth")

	data.cash = CFG.cashAfterRebirth
	table.clear(data.creatures)
	table.clear(data.quarantine) -- quarantined Snacklings are part of what a rebirth spends
	if not CFG.keepPodiumUpgrades then
		data.podiumUpgrades = 0
	end
	data.rebirths += 1
	data.rebirthMultiplier = math.max(data.rebirthMultiplier, RebirthMath.multiplierFor(data.rebirths, CFG))

	EconomyService.refresh(session)
	LockService.refresh(session)
	DataService.saveSoon(session.profile)

	if Analytics.milestone(session, "FirstRebirth") then
		Analytics.custom(session, "first_rebirth_playtime", math.floor(data.stats.playTime))
	end
	Analytics.custom(session, "rebirth", data.rebirths)
	Announcer.broadcast({
		text = Format.template(Theme.text.announceRebirth, {
			player = session.player.DisplayName,
			rebirths = data.rebirths,
		}),
		kind = "rebirth",
	})
	if session.plot ~= 0 then
		Remotes.fire(session.player, "Effect", {
			kind = "rebirth",
			position = PlotService.refs(session.plot).spawnCFrame.Position,
		})
	end
	return true
end

function RebirthService.start()
	Remotes.onIntent("Rebirth", function(player: Player)
		local session = Sessions.get(player)
		if session then
			RebirthService.rebirth(session)
		end
	end)
end

return RebirthService
