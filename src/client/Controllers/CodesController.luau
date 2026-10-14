--!strict
--[[
	The Redeem Code dialog (opened from Settings): a line of text, a box to type the code in and a Redeem button. Enter
	in the box redeems too. The server answers with a toast (CodeService), and a successful redeem clears the box.
	Codes are never on the client: what you type goes to the server as it is.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local Net = require(ReplicatedStorage.Shared.Net)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local CodeRules = require(ReplicatedStorage.Shared.Logic.CodeRules)
local Modal = require(script.Parent.Parent.UI.Modal)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local NotificationController = require(script.Parent.NotificationController)
local SoundPlayer = require(script.Parent.SoundPlayer)

local CodesController = {}

local DIALOG_SIZE = Vector2.new(440, 260)
-- A redeem a second ago is still on its way: a double tap must not send twice (the server rate-limits as well).
local RESEND_SECONDS = 1

local lastSent = 0

function CodesController.open()
	local modal = Modal.open(Theme.text.codesTitle, DIALOG_SIZE)
	UiKit.label({
		Name = "Body",
		Text = Theme.text.codesBody,
		FontFace = UiTheme.bodyFont,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 44),
		Parent = modal.body,
	})
	local box = UiKit.new("TextBox", {
		Name = "CodeBox",
		Position = UDim2.fromOffset(0, 56),
		Size = UDim2.new(1, 0, 0, 52),
		BackgroundColor3 = UiTheme.palette("panelLight"),
		TextColor3 = UiTheme.palette("text"),
		PlaceholderText = Theme.text.codesPlaceholder,
		PlaceholderColor3 = UiTheme.palette("textDim"),
		FontFace = UiTheme.displayFont,
		TextScaled = true,
		ClearTextOnFocus = false,
		Text = "",
		Parent = modal.body,
	}) :: TextBox
	UiKit.corner(UiKit.RADIUS.medium).Parent = box
	UiKit.stroke(UiKit.STROKE.normal).Parent = box
	UiKit.padding(10).Parent = box

	local function redeem()
		local typed = box.Text
		if CodeRules.normalize(typed) == nil then
			NotificationController.toast(Theme.text.codeInvalid, "error")
			return
		end
		local now = os.clock()
		if now - lastSent < RESEND_SECONDS then
			return
		end
		lastSent = now
		SoundPlayer.ui("click")
		Net.get("RedeemCode"):FireServer(typed)
	end
	UiKit.button({
		Name = "Redeem",
		Text = Theme.text.codesRedeem,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 120),
		Size = UDim2.fromOffset(200, 56),
		BackgroundColor3 = UiTheme.palette("success"),
		Parent = modal.body,
	}, redeem)
	box.FocusLost:Connect(function(enterPressed: boolean)
		if enterPressed then
			redeem()
		end
	end)
	-- A redeemed code clears the box, ready for the next one.
	local connection = Net.get("Notify").OnClientEvent:Connect(function(payload: { kind: string? })
		if payload.kind == "success" and box.Parent then
			box.Text = ""
		end
	end)
	task.spawn(function()
		while modal.isOpen() do
			task.wait(0.5)
		end
		connection:Disconnect()
	end)
end

return CodesController
