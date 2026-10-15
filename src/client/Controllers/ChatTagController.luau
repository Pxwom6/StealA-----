--!strict
--[[
	Chat tags before a player's name: a gold [VIP] for VIP pass owners (the server sets the player's "VIP" attribute
	after checking the pass), then the title they wear in its own colour (the "Title" attribute, written by StyleService;
	Config/Titles, off with Titles.chatTag = false): "[VIP] [🦹 Master Thief] Bob: hi". Titles come from config, never
	from players, so they need no filtering; they are escaped for rich text all the same.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local Titles = require(ReplicatedStorage.Shared.Config.Titles)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local StyleRules = require(ReplicatedStorage.Shared.Logic.StyleRules)

local ChatTagController = {}

-- The tags `player` shows in chat, or "" for none.
local function tags(player: Player): string
	local parts: { string } = {}
	if player:GetAttribute("VIP") == true then
		table.insert(parts, `<font color="{Theme.palette.vip}">{Theme.vipChatTag}</font>`)
	end
	local id = player:GetAttribute("Title")
	local def = if Titles.chatTag and type(id) == "string" and id ~= "" then StyleRules.titleById(Titles, id) else nil
	if def then
		table.insert(parts, `<font color="{def.color}">[{UiTheme.escapeRich(`{def.icon} {def.text}`)}]</font>`)
	end
	return table.concat(parts, " ")
end

function ChatTagController.start()
	TextChatService.OnIncomingMessage = function(message: TextChatMessage): TextChatMessageProperties?
		local source = message.TextSource
		if not source then
			return nil
		end
		local player = Players:GetPlayerByUserId(source.UserId)
		local prefix = if player then tags(player) else ""
		if prefix == "" then
			return nil
		end
		local properties = Instance.new("TextChatMessageProperties")
		properties.PrefixText = `{prefix} {message.PrefixText}`
		return properties
	end
end

return ChatTagController
