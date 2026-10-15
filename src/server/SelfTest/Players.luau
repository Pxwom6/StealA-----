--!strict
--[[
	Self-test section Players (only when someone is in the session): each player has a session (their save loaded),
	owns a plot (PlotService and the plot's OwnerUserId attribute agree), walks at the speed Movement gives them, has
	leaderstats, and their state replicates: their client asked for it (ClientReady) and a change marked now is sent by
	the replication loop within a second or two.
]]

local Players = game:GetService("Players")

local Services = script.Parent.Parent.Services
local Movement = require(Services.Movement)
local PlotService = require(Services.PlotService)
local Replication = require(Services.Replication)
local Sessions = require(Services.Sessions)
local Kit = require(script.Parent.Kit)

local STATE_SECONDS = 2

local Section: Kit.Section = {
	name = "Players",
	run = function(ctx: Kit.Context): string
		local players = Players:GetPlayers()
		if #players == 0 then
			ctx.note("nobody is in this session: Players skipped")
			return "skipped: nobody is in this session"
		end
		local details: { string } = {}
		for _, player in players do
			local name = player.Name
			local session = Sessions.get(player)
			if session == nil then
				ctx.problem(`{name} has no session (their save didn't load?)`)
				continue
			end
			local plot = session.plot
			if plot == 0 then
				ctx.problem(`{name} has no plot`)
			else
				if PlotService.ownerOf(plot) ~= player.UserId then
					ctx.problem(`{name}'s plot {plot} belongs to {PlotService.ownerOf(plot)} in PlotService`)
				end
				local owner = PlotService.refs(plot).model:GetAttribute("OwnerUserId")
				if owner ~= player.UserId then
					ctx.problem(`{name}'s plot {plot} shows OwnerUserId {owner}`)
				end
			end
			local humanoid = Sessions.humanoid(session)
			local speed = Movement.walkSpeed(session)
			if humanoid == nil then
				ctx.warning(`{name} has no character right now: speed not checked`)
			elseif math.abs(humanoid.WalkSpeed - speed) > 0.01 then
				ctx.problem(`{name} walks at {humanoid.WalkSpeed}, Movement says {speed}`)
			end
			local stats = player:FindFirstChild("leaderstats")
			if stats == nil or stats:FindFirstChild("Cash") == nil or stats:FindFirstChild("Steals") == nil then
				ctx.problem(`{name} has no leaderstats with Cash and Steals`)
			end
			if not session.ready then
				ctx.problem(`{name}'s client never asked for its state (ClientReady)`)
			else
				Replication.markDirty(session)
				local sent = Kit.waitUntil(function(): boolean
					return not session.dirty
				end, ctx.now() + STATE_SECONDS)
				if not sent then
					ctx.problem(
						`{name}'s state was not sent within {STATE_SECONDS} s: is the replication loop running?`
					)
				end
			end
			table.insert(details, `{name} on plot {plot}, walking {speed}`)
		end
		return `{#players} player(s): {Kit.list(details, 2)}; state sent`
	end,
}

return Section
