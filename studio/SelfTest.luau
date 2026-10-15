--!strict
--[[
	Steal a Snackling: the in-Studio self-test, in one paste (README "Studio self-test").

	  1. Sync the latest code into the place (studio/SyncFromGitHub.luau or Rojo) and leave Studio API access OFF
	     (Game Settings > Security), so nothing the test makes happen can reach a real save.
	  2. Press Play, then put the Command Bar (View > Command Bar) on the server: until you pick a side it runs in
	     Studio's edit view. Click Test > Toggle Server View (the button's name flips each click).
	  3. Paste this whole file into the Command Bar and press Enter. If it ran on the wrong side it says so in one line:
	     click the view button and paste again. Or, with Game Settings > Security > Allow HTTP Requests on (and while
	     the repo is public), paste this one line instead:
	         loadstring(game:GetService("HttpService"):GetAsync("https://raw.githubusercontent.com/Pxwom6/StealA-----/main/studio/SelfTest.luau", true))()
	  4. About two minutes later, read the end of the Output: one line per section, then a summary that ends with
	     "SELFTEST DONE: <n> problem(s), <m> warning(s)" and the first problems under it. The full report is the
	     StringValue ServerStorage.SelfTestReport: print(game.ServerStorage.SelfTestReport.Value) in the Command Bar.

	If it ran in the wrong place it says so in one line and does nothing else. The HUD check is the companion
	studio/SelfTestClient.luau, pasted on the client view (Test > Toggle Client View).

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
local START_SECONDS = 5 -- how long the Script may take to show it runs

local function start()
	if not RunService:IsStudio() then
		print("SELFTEST: this runs in Roblox Studio only.")
		return
	end
	if not RunService:IsRunning() then
		print(
			"SELFTEST: this ran in Studio's edit view. Press Play, click Test > Toggle Server View, then paste again."
		)
		return
	end
	if RunService:IsClient() then
		print("SELFTEST: this ran on the client view. Click Test > Toggle Server View, then paste again.")
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

	-- (The Command Bar may not set every property: any refusal is said, not thrown.)
	local runner: any = nil
	local made, err = pcall(function()
		local instance = Instance.new("Script")
		instance.Name = RUNNER_NAME
		runner = instance
		local holder: any = instance
		holder.Source = RUNNER_SOURCE
		if holder.Source ~= RUNNER_SOURCE then
			error("its Source could not be set")
		end
		instance.Parent = ServerScriptService
	end)
	if not made then
		if runner then
			runner:Destroy()
		end
		print(`SELFTEST: the Command Bar could not make the test's Script here ({err}).`)
		return
	end
	-- The Script marks itself Started as soon as it runs (or removes itself): say so if Studio never ran it.
	task.spawn(function()
		local deadline = os.clock() + START_SECONDS
		while os.clock() < deadline do
			if runner.Parent == nil or runner:GetAttribute("Started") == true then
				return
			end
			task.wait(0.1)
		end
		runner:Destroy()
		warn(`SELFTEST DONE: the test's Script didn't start within {START_SECONDS} s; nothing was changed.`)
	end)
end

start()
