--!strict
--[[
	Self-test section Remotes: every remote Shared/Net lists is a RemoteEvent in ReplicatedStorage.Remotes (the
	Studio-only DevGrantProduct too, since this is Studio) and nothing else is there; and Roblox's online services
	degrade the way the code expects in Studio:
	  * PolicyService: each player's answer was published (the attribute PaidRandomItemsAllowed) and agrees with what
	    PolicyService says now (asked in a pcall; a failed lookup counts as restricted, Logic/PaidRandomItems);
	  * MessagingService: CrossServer neither publishes nor listens in Studio (with API access on, a test session would
	    reach live servers). MessagingService itself is never called.
]]

local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage.Shared.Net)
local PaidRandomItems = require(ReplicatedStorage.Shared.Logic.PaidRandomItems)
local CrossServer = require(script.Parent.Parent.Services.CrossServer)
local Kit = require(script.Parent.Kit)

-- A player who has just joined may still be waiting for their first policy lookup (it retries once after 1 s).
local POLICY_WAIT_SECONDS = 5

local Section: Kit.Section = {
	name = "Remotes",
	run = function(ctx: Kit.Context): string
		local folder = ReplicatedStorage:FindFirstChild("Remotes")
		if folder == nil then
			ctx.problem("ReplicatedStorage.Remotes is missing: Net.createAll never ran")
			return "no remotes"
		end
		local listed: { [string]: boolean } = {}
		local names: { string } = {}
		local function list(name: string)
			listed[name] = true
			table.insert(names, name)
		end
		for _, name in Net.clientToServer do
			list(name)
		end
		for _, name in Net.serverToClient do
			list(name)
		end
		table.sort(names)
		local missing: { string } = {}
		for _, name in names do
			local remote = folder:FindFirstChild(name)
			if remote == nil then
				table.insert(missing, name)
			elseif not remote:IsA("RemoteEvent") then
				ctx.problem(`Remotes.{name} is a {remote.ClassName}, not a RemoteEvent`)
			end
		end
		if #missing > 0 then
			ctx.problem(`{#missing} remotes are missing: {Kit.list(missing, 4)}`)
		end
		for _, child in folder:GetChildren() do
			if not listed[child.Name] then
				ctx.warning(`ReplicatedStorage.Remotes has {child.Name}, which Shared/Net doesn't list`)
			end
		end

		local answered, failed = 0, 0
		for _, player in Players:GetPlayers() do
			local deadline = os.clock() + POLICY_WAIT_SECONDS
			while player:GetAttribute(PaidRandomItems.ATTRIBUTE) == nil and os.clock() < deadline do
				task.wait(0.1)
			end
			local published = player:GetAttribute(PaidRandomItems.ATTRIBUTE)
			if type(published) ~= "boolean" then
				ctx.problem(`{player.Name}: no policy answer was published ({PaidRandomItems.ATTRIBUTE} is nil)`)
				continue
			end
			local ok, info = pcall(function(): any
				return PolicyService:GetPolicyInfoForPlayerAsync(player)
			end)
			local allowed = PaidRandomItems.allowedByPolicy(ok, info)
			if ok then
				answered += 1
			else
				failed += 1
				ctx.note(`PolicyService failed for {player.Name} (counts as restricted): {Kit.short(tostring(info))}`)
			end
			if published ~= allowed then
				if ok and published == false then
					ctx.warning(
						`{player.Name}: PolicyService answers now, but the join lookup failed (a retry publishes it)`
					)
				else
					ctx.problem(
						`{player.Name}: {PaidRandomItems.ATTRIBUTE} is {published}, PolicyService says {allowed}`
					)
				end
			end
		end

		if RunService:IsStudio() then
			if CrossServer.enabled() then
				ctx.problem("CrossServer is on in Studio: admin actions would reach live servers")
			end
			if CrossServer.subscribed("host") or CrossServer.subscribed("shout") then
				ctx.problem("CrossServer listens to MessagingService in Studio")
			end
		end
		local policy = if answered + failed == 0
			then "no player for PolicyService"
			elseif failed == 0 then `PolicyService answered for {answered}`
			else `PolicyService failed for {failed} (restricted, as expected)`
		return `{#names - #missing} remotes, {policy}, MessagingService off in Studio`
	end,
}

return Section
