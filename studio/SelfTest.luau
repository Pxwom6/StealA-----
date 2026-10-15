--!strict
--[[
	Steal a Snackling: the in-Studio self-test, in one paste (README "Studio self-test").

	  1. Sync the latest code into the place (studio/SyncFromGitHub.luau or Rojo) and leave Studio API access OFF
	     (Game Settings > Security), so nothing the test makes happen can reach a real save.
	  2. Press Play. In View > Command Bar, check it says Server, paste this whole file and press Enter.
	  3. About two minutes later, read the end of the Output: one line per section, then a summary that ends with
	     "SELFTEST DONE: <n> problem(s), <m> warning(s)" and the first problems under it. The full report is the
	     StringValue ServerStorage.SelfTestReport (select it in the Explorer, or print it from the Command Bar:
	     print(game.ServerStorage.SelfTestReport.Value)).

	The HUD check is the companion studio/SelfTestClient.luau, pasted with the Command Bar switched to Client.

	Why this makes a Script: code run in the Command Bar gets its own copies of the modules it requires, not the ones
	the running game uses. A Script in ServerScriptService runs like the game's own scripts, so it starts
	ServerScriptService.Server.SelfTest (src/server/SelfTest), which drives the live services: it switches maps, runs
	modifiers and events, builds Snacklings and puts everything back afterwards. It never touches a DataStore or a
	save, never publishes or teleports, and won't run with Studio API access on. The Script removes itself at the end.
]]

local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local RUNNER_NAME = "SnacklingSelfTest"
local RUNNER_SOURCE = [[
local ok, err = pcall(function()
	require(game:GetService("ServerScriptService").Server.SelfTest).run(script)
end)
if not ok then
	warn("SELFTEST DONE: the self-test could not start: " .. tostring(err))
end
script:Destroy()
]]

local function start()
	if not RunService:IsStudio() then
		print("SELFTEST: this runs in Roblox Studio only.")
		return
	end
	if not RunService:IsRunning() then
		print("SELFTEST: press Play first, then paste this into the Command Bar with it set to Server.")
		return
	end
	if RunService:IsClient() then
		print(
			"SELFTEST: the Command Bar is on Client: switch it to Server (studio/SelfTestClient.luau is the Client one)."
		)
		return
	end
	local server = ServerScriptService:FindFirstChild("Server")
	local module = if server then server:FindFirstChild("SelfTest") else nil
	if module == nil or not module:IsA("ModuleScript") then
		print("SELFTEST: no ServerScriptService.Server.SelfTest here: sync the latest code, then Play and paste again.")
		return
	end
	if ServerScriptService:FindFirstChild(RUNNER_NAME) then
		print("SELFTEST: already running: wait for SELFTEST DONE in the Output.")
		return
	end
	local runner = Instance.new("Script")
	runner.Name = RUNNER_NAME;
	(runner :: any).Source = RUNNER_SOURCE
	runner.Parent = ServerScriptService
end

start()
