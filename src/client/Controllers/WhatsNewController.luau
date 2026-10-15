--!strict
--[[
	The What's New card (Config/Updates). NewsService sends WhatsNew to a returning player who hasn't seen the newest
	update; the card shows its title, number and date, a line per highlight and a big "Let's go!" button (laid out by
	Logic/NewsLayout). It waits until nothing is in the way, checking every second: the first state has arrived, no
	tutorial is running, the player isn't carrying a Snackling, no other dialog is open (Modal.isAnyOpen: the
	welcome-back popup and the daily reward come first) and a few seconds have passed since joining. Once it is shown
	the server is told (SeenNews), so it never comes again for that update. It closes with the button, the X or a tap
	outside it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local Updates = require(ReplicatedStorage.Shared.Config.Updates)
local Net = require(ReplicatedStorage.Shared.Net)
local Types = require(ReplicatedStorage.Shared.Types)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local NewsLayout = require(ReplicatedStorage.Shared.Logic.NewsLayout)
local Modal = require(script.Parent.Parent.UI.Modal)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local StateStore = require(script.Parent.StateStore)

local WhatsNewController = {}

local FIRST_WAIT_SECONDS = 6 -- after it arrives: the welcome-back popup and the daily reward open first
local CHECK_SECONDS = 1

local pending: number? = nil
local waiting = false

local function updateNumbered(number: number): Types.UpdateDef?
	for _, def in Updates.list do
		if def.number == number then
			return def
		end
	end
	return nil
end

local function canShow(): boolean
	local state = StateStore.get()
	return state ~= nil and state.tutorial.step == "" and state.carrying == "" and not Modal.isAnyOpen()
end

local function place(object: GuiObject, r: NewsLayout.Rect)
	object.Position = UDim2.fromOffset(r.x, r.y)
	object.Size = UDim2.fromOffset(r.w, r.h)
end

local function showCard(def: Types.UpdateDef)
	local modal = Modal.open(Theme.text.whatsNewTitle, Vector2.new(NewsLayout.CARD.w, NewsLayout.CARD.h))
	local boxes = NewsLayout.cardBoxes(#def.highlights)
	place(
		UiKit.label({ Name = "Title", Text = def.title, TextColor3 = UiTheme.palette("text"), Parent = modal.body }),
		boxes.title
	)
	place(
		UiKit.label({
			Name = "Meta",
			Text = Format.template(Theme.text.whatsNewMeta, { number = def.number, date = def.date }),
			FontFace = UiTheme.bodyFont,
			TextColor3 = UiTheme.palette("textDim"),
			Parent = modal.body,
		}),
		boxes.meta
	)
	for i, line in def.highlights do
		place(
			UiKit.label({
				Name = `Line{i}`,
				Text = line,
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = modal.body,
			}),
			boxes[`line{i}`]
		)
	end
	local button = UiKit.button({
		Name = "LetsGo",
		Text = Theme.text.whatsNewButton,
		BackgroundColor3 = UiTheme.palette("success"),
		Parent = modal.body,
	}, modal.close)
	place(button, boxes.button)
	Net.get("SeenNews"):FireServer(def.number)
end

-- Waits until the card can show without getting in the way, then shows it (once).
local function showWhenFree()
	if waiting then
		return
	end
	waiting = true
	task.spawn(function()
		task.wait(FIRST_WAIT_SECONDS)
		while pending ~= nil do
			if canShow() then
				local def = updateNumbered(pending :: number)
				pending = nil
				if def then
					showCard(def)
				end
				break
			end
			task.wait(CHECK_SECONDS)
		end
		waiting = false
	end)
end

function WhatsNewController.start()
	Net.get("WhatsNew").OnClientEvent:Connect(function(payload: { number: number? })
		if type(payload) == "table" and type(payload.number) == "number" then
			pending = payload.number
			showWhenFree()
		end
	end)
end

return WhatsNewController
