--!strict
--[[
	Plot (base) assignment: one plot per player, released on leave. `owners[plotIndex] = userId`.
	Pure: no requires, no Roblox APIs.
]]

export type Owners = { [number]: number }

local PlotAssignment = {}

function PlotAssignment.plotOf(owners: Owners, userId: number): number?
	for plot, owner in owners do
		if owner == userId then
			return plot
		end
	end
	return nil
end

-- Returns the player's plot (existing or newly claimed, lowest free index first), or nil if the server is full.
function PlotAssignment.claim(owners: Owners, plotCount: number, userId: number): number?
	local existing = PlotAssignment.plotOf(owners, userId)
	if existing ~= nil then
		return existing
	end
	for plot = 1, plotCount do
		if owners[plot] == nil then
			owners[plot] = userId
			return plot
		end
	end
	return nil
end

function PlotAssignment.release(owners: Owners, userId: number): number?
	local plot = PlotAssignment.plotOf(owners, userId)
	if plot ~= nil then
		owners[plot] = nil
	end
	return plot
end

return PlotAssignment
