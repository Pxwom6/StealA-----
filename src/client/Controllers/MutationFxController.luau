--!strict
--[[
	Animates mutation looks on this client: every part tagged CreatureVisuals.RAINBOW_TAG (Rainbow Snacklings on
	the belt, on podiums and carried by thieves) cycles its hue. One loop at 10 Hz over the tagged parts; Rainbow is
	the rarest mutation, so there are only ever a handful. The colour change is local (it never replicates). Parts
	parked out of sight (BeltController's pooled models wait at y = -500) are skipped.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CreatureVisuals = require(ReplicatedStorage.Shared.CreatureVisuals)

local MutationFxController = {}

local STEP_SECONDS = 0.1
-- Below this height a part is parked, not shown (BeltController hides pooled belt models at y = -500).
local PARKED_BELOW_Y = -400

local function step()
	local t = os.clock()
	for _, instance in CollectionService:GetTagged(CreatureVisuals.RAINBOW_TAG) do
		if instance:IsA("BasePart") and instance.Position.Y > PARKED_BELOW_Y then
			local offset = instance:GetAttribute("HueOffset")
			instance.Color = CreatureVisuals.rainbowColor(if type(offset) == "number" then offset else 0, t)
		end
	end
end

function MutationFxController.start()
	task.spawn(function()
		while true do
			task.wait(STEP_SECONDS)
			step()
		end
	end)
end

return MutationFxController
