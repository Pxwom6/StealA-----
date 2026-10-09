--!strict
--[[
	Validators for values arriving from the network. Every RemoteEvent argument is `unknown` until one of these
	accepts it: exploiters can send any type, NaN, infinities, huge strings or deeply nested tables.
	Pure: no requires, no Roblox APIs.
]]

local Guard = {}

function Guard.isFiniteNumber(value: unknown): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function Guard.isIntegerInRange(value: unknown, min: number, max: number): boolean
	if type(value) ~= "number" then
		return false
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return false
	end
	return value == math.floor(value) and value >= min and value <= max
end

-- Returns the value as an integer if valid, otherwise nil. Convenient in remote handlers.
function Guard.integer(value: unknown, min: number, max: number): number?
	if Guard.isIntegerInRange(value, min, max) then
		return value :: number
	end
	return nil
end

function Guard.shortString(value: unknown, maxLength: number): string?
	if type(value) == "string" and #value > 0 and #value <= maxLength then
		return value
	end
	return nil
end

-- Accepts only strings that are members of `allowed` (array of strings).
function Guard.oneOf(value: unknown, allowed: { string }): string?
	if type(value) ~= "string" then
		return nil
	end
	for _, option in allowed do
		if option == value then
			return value
		end
	end
	return nil
end

-- Accepts only strings that are keys of `map`.
function Guard.keyOf<T>(value: unknown, map: { [string]: T }): string?
	if type(value) ~= "string" or #value > 64 then
		return nil
	end
	if map[value] ~= nil then
		return value
	end
	return nil
end

return Guard
