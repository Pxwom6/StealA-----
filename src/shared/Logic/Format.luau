--!strict
--[[
	Number and time formatting for a phone-sized UI. Pure: no requires, no Roblox APIs.

	Format.number(1234567)      --> "1.23M"
	Format.cash(1500, "$")       --> "$1.5K"
	Format.clock(75)             --> "1:15"
	Format.duration(3725)        --> "1h 2m"
	Format.percent(0.0123)       --> "1.23%"
	Format.template("Hi {name}", { name = "Ana" }) --> "Hi Ana"
]]

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

local function stripZeros(text: string): string
	if string.find(text, ".", 1, true) == nil then
		return text
	end
	text = string.gsub(text, "0+$", "")
	text = string.gsub(text, "%.$", "")
	return text
end

-- Abbreviates a number with K/M/B/... suffixes and at most 3 significant digits. Always rounds DOWN so a
-- player is never shown more money than they have.
function Format.number(value: number): string
	if value ~= value then
		return "0"
	end
	if value == math.huge then
		return "inf"
	end
	if value == -math.huge then
		return "-inf"
	end
	local sign = if value < 0 then "-" else ""
	local n = math.abs(value)
	if n < 1000 then
		if n == math.floor(n) then
			return sign .. string.format("%d", n)
		end
		return sign .. stripZeros(string.format("%.1f", math.floor(n * 10) / 10))
	end

	local tier = math.floor(math.log10(n) / 3)
	local scaled = n / 10 ^ (tier * 3)
	-- Guard against floating point error at exact powers of 1000.
	if scaled >= 1000 then
		tier += 1
		scaled /= 1000
	elseif scaled < 1 then
		tier -= 1
		scaled *= 1000
	end
	if tier + 1 > #SUFFIXES then
		return sign .. string.format("%.2e", n)
	end

	local text
	if scaled >= 100 then
		text = string.format("%d", math.floor(scaled))
	elseif scaled >= 10 then
		text = stripZeros(string.format("%.1f", math.floor(scaled * 10 + 1e-9) / 10))
	else
		text = stripZeros(string.format("%.2f", math.floor(scaled * 100 + 1e-9) / 100))
	end
	return sign .. text .. SUFFIXES[tier + 1]
end

function Format.cash(value: number, symbol: string?): string
	local prefix = symbol or "$"
	if value < 0 then
		return "-" .. prefix .. Format.number(-value)
	end
	return prefix .. Format.number(value)
end

-- "m:ss" below an hour, "h:mm:ss" above. Negative or NaN input shows "0:00".
function Format.clock(seconds: number): string
	if seconds ~= seconds or seconds < 0 then
		seconds = 0
	end
	local total = math.ceil(seconds)
	local h = total // 3600
	local m = (total % 3600) // 60
	local s = total % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s)
	end
	return string.format("%d:%02d", m, s)
end

-- Human duration with the two largest units: "45s", "5m 3s", "2h 15m", "3d 4h".
function Format.duration(seconds: number): string
	if seconds ~= seconds or seconds < 0 then
		seconds = 0
	end
	local total = math.floor(seconds)
	local d = total // 86400
	local h = (total % 86400) // 3600
	local m = (total % 3600) // 60
	local s = total % 60
	if d > 0 then
		return string.format("%dd %dh", d, h)
	elseif h > 0 then
		return string.format("%dh %dm", h, m)
	elseif m > 0 then
		return string.format("%dm %ds", m, s)
	end
	return string.format("%ds", s)
end

-- Probability (0..1) as a percentage with enough decimals to stay meaningful for tiny odds.
function Format.percent(probability: number): string
	local p = probability * 100
	if p ~= p or p <= 0 then
		return "0%"
	end
	local text
	if p >= 10 then
		text = string.format("%.1f", p)
	elseif p >= 1 then
		text = string.format("%.2f", p)
	elseif p >= 0.01 then
		text = string.format("%.3f", p)
	else
		text = string.format("%.4f", p)
	end
	return stripZeros(text) .. "%"
end

-- Replaces {key} with vars[key]. Unknown keys are left as-is so missing data is visible in testing.
function Format.template(text: string, vars: { [string]: any }?): string
	if vars == nil then
		return text
	end
	local result = string.gsub(text, "{(%w+)}", function(key: string): string
		local value = vars[key]
		if value == nil then
			return "{" .. key .. "}"
		end
		return tostring(value)
	end)
	return result
end

return Format
