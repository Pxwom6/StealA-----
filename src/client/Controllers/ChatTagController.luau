--!strict
--[[
	Gold [VIP] chat tag for VIP pass owners (the server sets the player's "VIP" attribute after checking the pass).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Theme = require(ReplicatedStorage.Shared.Config.Theme)

local ChatTagController = {}

function ChatTagController.start()
	TextChatService.OnIncomingMessage = function(message: TextChatMessage): TextChatMessageProperties?
		local source = message.TextSource
		if not source then
			return nil
		end
		local player = Players:GetPlayerByUserId(source.UserId)
		if player == nil or player:GetAttribute("VIP") ~= true then
			return nil
		end
		local properties = Instance.new("TextChatMessageProperties")
		properties.PrefixText = `<font color="{Theme.palette.vip}">{Theme.vipChatTag}</font> {message.PrefixText}`
		return properties
	end
end

return ChatTagController
