--!strict
--[[
	Steal a Snackling: the HUD half of the in-Studio self-test (README "Studio self-test"; the server half is
	studio/SelfTest.luau).

	  1. Press Play and wait for the HUD. (To try a phone: Test > Device, e.g. an iPhone in landscape, before Play.)
	  2. Put the Command Bar (View > Command Bar) on the client: until you pick a side it runs in Studio's edit view.
	     The Test tab's view button does it (Toggle Client View / Toggle Server View: its name flips each click).
	  3. Paste this whole file into the Command Bar and press Enter (the file itself: HttpService can't fetch on the
	     client). If it ran on the wrong side it says so in one line: click the view button and paste again.
	  4. A few seconds later, read the lines starting "SELFTEST client" at the end of the Output.

	It measures the real HUD as Roblox drew it: every frame HudController places (each carries its layout id as the
	attribute HudId) and the TAG button, by AbsolutePosition and AbsoluteSize, against where Logic/ScreenLayout puts
	them on this screen in this state (the device built the way HudController builds it). Then it runs ScreenLayout's
	own check on what it measured: overlaps between visible elements, anything off screen, a button in the play zone or
	under Roblox's buttons, touch targets under 44 px. Last, the text of every label in them: not clipped (TextFits, and
	TextBounds inside the label) and not tiny (12 UI or more, what Logic/TextFit promises the HUD keeps).

	It only requires pure shared modules (ScreenLayout, TextFit), which is fine from the Command Bar: they hold no state.
	It changes nothing but a hidden label it measures text with for a moment.
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local PREFIX = "SELFTEST client"
local OFF_PX = 2 -- px a measured edge may differ from the layout's (rounding)
local TEXT_SLACK_PX = 1.5 -- px text may overrun its label before it counts as clipped
local TINY_SLACK = 0.75 -- UI units under the minimum text size still allowed (measuring rounds)
local SETTLE_TRIES = 6 -- an element mid pop-in or pulse is measured again, 0.2 s apart

type Rect = { x: number, y: number, w: number, h: number }

-- "SELFTEST client <text>" (or "SELFTEST client: ..." when `text` starts with a colon), as a warning when it failed.
local function line(text: string, failed: boolean)
	local full = if string.sub(text, 1, 1) == ":" then PREFIX .. text else `{PREFIX} {text}`
	if failed then
		warn(full)
	else
		print(full)
	end
end

-- Whether `object` and every GuiObject above it in its ScreenGui shows.
local function visible(object: GuiObject): boolean
	local node: Instance? = object
	while node and not node:IsA("ScreenGui") do
		if node:IsA("GuiObject") and not node.Visible then
			return false
		end
		node = node.Parent
	end
	return node ~= nil and (node :: ScreenGui).Enabled
end

-- Whether an animation scale (a pop-in, a press, the cash pulse) on `object` is away from 1 right now.
local function animating(object: GuiObject): boolean
	for _, child in object:GetChildren() do
		if child:IsA("UIScale") and math.abs(child.Scale - 1) > 1e-3 then
			return true
		end
	end
	return false
end

local function main()
	if not RunService:IsRunning() then
		print(
			`{PREFIX}: this ran in Studio's edit view. Press Play, pick the client view (Test tab), then paste again.`
		)
		return
	end
	if not RunService:IsClient() then
		print(`{PREFIX}: this ran on the server view. Click Test > Toggle Client View, then paste again.`)
		return
	end
	local player = Players.LocalPlayer
	local playerGui = if player then player:FindFirstChildOfClass("PlayerGui") else nil
	local hudInstance = if playerGui then playerGui:FindFirstChild("Hud") else nil
	if hudInstance == nil or not hudInstance:IsA("ScreenGui") then
		print(`{PREFIX}: the HUD isn't up yet: wait for the game to load, then paste this again.`)
		return
	end
	local hud = hudInstance :: ScreenGui
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local logic = if shared then shared:FindFirstChild("Logic") else nil
	if logic == nil or logic:FindFirstChild("ScreenLayout") == nil or logic:FindFirstChild("TextFit") == nil then
		print(`{PREFIX}: no ReplicatedStorage.Shared.Logic.ScreenLayout here: sync the latest code first.`)
		return
	end
	local ScreenLayout = require(ReplicatedStorage.Shared.Logic.ScreenLayout)
	local TextFit = require(ReplicatedStorage.Shared.Logic.TextFit)

	local problems: { string } = {}
	local warnings: { string } = {}

	-- The screen as HudController sees it (HudController.device).
	local camera = workspace.CurrentCamera
	local viewport = camera.ViewportSize
	local position, size = hud.AbsolutePosition, hud.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		position, size = Vector2.zero, viewport
	end
	local free = GuiService.TopbarInset
	local hasFree = free.Width > 0
	local stats = player:FindFirstChild("leaderstats")
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local device = ScreenLayout.device({
		name = "this screen",
		widthPx = viewport.X,
		heightPx = viewport.Y,
		touch = UserInputService.TouchEnabled,
		insetLeftPx = math.max(0, position.X),
		insetRightPx = math.max(0, viewport.X - position.X - size.X),
		insetBottomPx = math.max(0, viewport.Y - size.Y),
		playerListPx = ScreenLayout.playerListWidth(
			StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.PlayerList),
			touchOnly,
			viewport.X,
			viewport.Y,
			if stats then #stats:GetChildren() else 0
		),
		topBarPx = GuiService:GetGuiInset().Y,
		topBarLeftPx = if hasFree then free.Min.X else nil,
		topBarRightPx = if hasFree then free.Max.X else nil,
	})
	line(
		string.format(
			": %.0fx%.0f px, UI scale %.2f, touch %s, player list %.0f px",
			viewport.X,
			viewport.Y,
			device.scale,
			if device.touch then "yes" else "no",
			device.playerList * device.scale
		),
		false
	)

	-- What HudController placed, by layout id; TAG sits in the action area.
	local placed: { [string]: GuiObject } = {}
	for _, descendant in hud:GetDescendants() do
		local id = descendant:GetAttribute("HudId")
		if type(id) == "string" and descendant:IsA("GuiObject") then
			placed[id] = descendant
		end
	end
	if next(placed) == nil then
		line("Placement: FAIL no HUD frame has a HudId: is this place's client code older than the self-test?", true)
		return
	end
	local actionArea = placed.actionArea
	local tag = if actionArea then actionArea:FindFirstChild("TagButton") else nil
	if tag and tag:IsA("GuiObject") then
		placed.tag = tag
	end

	-- The state, as HudController reads it (hudState), and the layout for it.
	local function shown(id: string): boolean
		local object: GuiObject? = placed[id]
		return object ~= nil and object.Visible and object.Parent ~= nil
	end
	local gadgets = 0
	while shown(`gadget{gadgets + 1}`) do
		gadgets += 1
	end
	local tutorial: GuiObject? = placed.tutorial
	local tagButton: GuiObject? = placed.tag
	local state: ScreenLayout.HudState = {
		tutorial = if tutorial and tutorial.Visible
			then (if tutorial:GetAttribute("Tip") == true then "full" else "compact")
			else nil,
		cashOffer = shown("cashOffer"),
		event = shown("event"),
		modifier = shown("modifier"),
		luck = shown("luck"),
		vote = shown("vote"),
		friends = shown("friends"),
		gadgets = gadgets,
		tag = tagButton ~= nil and visible(tagButton),
	}
	local layout = ScreenLayout.layout(device, state)
	local kinds: { [string]: string } = {}
	for _, element in layout.elements do
		kinds[element.id] = element.kind
	end

	local function modelRect(id: string): Rect?
		if id == "vote" then
			return if state.vote then ScreenLayout.voteStrip(device) else nil
		elseif id == "actionArea" then
			return ScreenLayout.actionArea(device)
		end
		return layout.byId[id]
	end

	-- Placement: every visible placed frame where the layout says (measured again while it animates).
	local measured: { ScreenLayout.Element } = {}
	local placedCount = 0
	local ids: { string } = {}
	for id in placed do
		table.insert(ids, id)
	end
	table.sort(ids)
	local placementProblems: { string } = {}
	for _, id in ids do
		local object = placed[id]
		if not visible(object) then
			continue
		end
		local tries = 0
		while animating(object) and tries < SETTLE_TRIES do
			tries += 1
			task.wait(0.2)
		end
		local p, s = object.AbsolutePosition, object.AbsoluteSize
		local rect: Rect = {
			x = (p.X - device.left) / device.scale,
			y = (p.Y - device.top) / device.scale,
			w = s.X / device.scale,
			h = s.Y / device.scale,
		}
		local wanted = modelRect(id)
		if wanted == nil then
			table.insert(placementProblems, `{id} shows, but ScreenLayout has no place for it in this state`)
		else
			local px = ScreenLayout.toPx(device, wanted)
			local off = math.max(
				math.abs(p.X - px.x),
				math.abs(p.Y - px.y),
				math.abs(p.X + s.X - px.x - px.w),
				math.abs(p.Y + s.Y - px.y - px.h)
			)
			if off > OFF_PX then
				table.insert(
					placementProblems,
					string.format(
						"%s is %.0f px off (at %.0f,%.0f %.0fx%.0f, layout %.0f,%.0f %.0fx%.0f)",
						id,
						off,
						p.X,
						p.Y,
						s.X,
						s.Y,
						px.x,
						px.y,
						px.w,
						px.h
					)
				)
			end
			placedCount += 1
		end
		if id ~= "actionArea" then
			local kind = if id == "vote" then "button" else kinds[id] or "info"
			table.insert(measured, { id = id, kind = kind, rect = rect })
		end
	end
	for _, problem in placementProblems do
		table.insert(problems, `Placement: {problem}`)
	end
	local placementLine = if #placementProblems == 0
		then `Placement: ok {placedCount} elements where ScreenLayout puts them`
		else `Placement: FAIL {placementProblems[1]}{if #placementProblems > 1
			then ` (+{#placementProblems - 1} more)`
			else ""}`
	line(placementLine, #placementProblems > 0)

	-- Layout: ScreenLayout's own check, on what Roblox drew (with Roblox's UI and the play zone from the model).
	for _, element in layout.elements do
		if element.kind == "core" or element.kind == "zone" then
			table.insert(measured, element)
		end
	end
	local layoutProblems = ScreenLayout.problems(device, measured)
	for _, problem in layoutProblems do
		table.insert(problems, `Layout: {problem}`)
	end
	line(
		if #layoutProblems == 0
			then "Layout: ok no overlaps, nothing off screen, in the play zone or under Roblox's buttons, touch targets OK"
			else `Layout: FAIL {layoutProblems[1]}{if #layoutProblems > 1
				then ` (+{#layoutProblems - 1} more)`
				else ""}`,
		#layoutProblems > 0
	)

	-- Text: TextBounds against each label's size. TextBounds may or may not include the screen's UIScale: a hidden
	-- probe label with a known text size says which.
	local font: Font? = nil
	for _, object in placed do
		for _, descendant in object:GetDescendants() do
			if font == nil and descendant:IsA("TextLabel") then
				font = descendant.FontFace
			end
		end
	end
	local boundsToPx = 1
	local probed, probeHeight = pcall(function(): number
		local probe = Instance.new("TextLabel")
		probe.Name = "SelfTestProbe"
		probe.BackgroundTransparency = 1
		probe.TextTransparency = 1
		probe.TextScaled = false
		probe.TextSize = 20
		probe.Text = "Hg"
		probe.Size = UDim2.fromOffset(200, 60)
		if font then
			probe.FontFace = font
		end
		probe.Parent = hud
		task.wait(0.1)
		local height = probe.TextBounds.Y
		probe:Destroy()
		return height
	end)
	if probed and probeHeight > 0 then
		local ratio = probeHeight / (20 * TextFit.LINE_HEIGHT)
		if math.abs(ratio - 1) < math.abs(ratio - device.scale) then
			boundsToPx = device.scale -- TextBounds is in UI units, before the screen's UIScale
		end
	end
	local textProblems: { string } = {}
	local labels, smallest = 0, math.huge
	for _, id in ids do
		local object = placed[id]
		if id == "actionArea" or not visible(object) then
			continue -- (the action area only holds TAG, which is checked as itself)
		end
		local candidates: { Instance } = { object }
		for _, descendant in object:GetDescendants() do
			table.insert(candidates, descendant)
		end
		for _, candidate in candidates do
			if not (candidate:IsA("TextLabel") or candidate:IsA("TextButton")) then
				continue
			end
			local label = candidate :: TextLabel
			local text = if label.RichText then string.gsub(label.Text, "<[^>]+>", "") else label.Text
			if string.match(text, "%S") == nil or not visible(label) then
				continue
			end
			labels += 1
			local box = label.AbsoluteSize
			local bounds = label.TextBounds * boundsToPx
			local name = `{id}: "{string.sub(text, 1, 24)}"`
			if not label.TextFits or bounds.X > box.X + TEXT_SLACK_PX or bounds.Y > box.Y + TEXT_SLACK_PX then
				table.insert(
					textProblems,
					string.format(
						"%s is clipped (text %.0fx%.0f px in %.0fx%.0f)",
						name,
						bounds.X,
						bounds.Y,
						box.X,
						box.Y
					)
				)
			end
			local lines = 1
			if label.TextWrapped then
				local w, h = box.X / device.scale, box.Y / device.scale
				local modelled = TextFit.fit(text, w, h, true)
				lines = math.clamp(TextFit.lineCount(text, math.max(modelled, 1), w), 1, 4)
			end
			local em = bounds.Y / lines / TextFit.LINE_HEIGHT / device.scale
			smallest = math.min(smallest, em)
			if em < ScreenLayout.TEXT.minSize - TINY_SLACK then
				table.insert(
					textProblems,
					string.format(
						"%s is tiny: %.1f UI (%.1f px), under %d UI",
						name,
						em,
						em * device.scale,
						ScreenLayout.TEXT.minSize
					)
				)
			end
		end
	end
	if not probed then
		table.insert(warnings, "Text: the probe label failed; TextBounds was taken as pixels")
	end
	for _, problem in textProblems do
		table.insert(problems, `Text: {problem}`)
	end
	local smallestText = if labels > 0 then string.format(", smallest %.1f UI", smallest) else ""
	line(
		if #textProblems == 0
			then `Text: ok {labels} labels, none clipped or tiny{smallestText}`
			else `Text: FAIL {textProblems[1]}{if #textProblems > 1 then ` (+{#textProblems - 1} more)` else ""}`,
		#textProblems > 0
	)

	line(`DONE: {#problems} problem(s), {#warnings} warning(s)`, #problems > 0)
	for index = 1, math.min(3, #problems) do
		line(`  {index}. {problems[index]}`, true)
	end
	for index = 1, math.min(2, #warnings) do
		line(`  warning: {warnings[index]}`, false)
	end
end

local ok, err = pcall(main :: () -> ...any)
if not ok then
	warn(`{PREFIX} DONE: the HUD check itself failed: {err}`)
end
