--!strict
--[[
	Redeem code rules: what a typed code means, whether a player may still redeem it, and config validation. The codes
	themselves live in server/Codes.luau (server-only), so a client never sees one it was not told about.

	Each code works once per account: redeeming sets the flag `code_<CODE>` in the save (flags need no schema change).
	Pure: no Roblox APIs.
]]

local Types = require("../Types")

type CodesConfig = Types.CodesConfig
type CodeDef = Types.CodeDef

local CodeRules = {}

CodeRules.MAX_LENGTH = 24

-- Why a code can't be redeemed (a Theme.text key each: code<Reason>).
export type Refusal = "invalid" | "unknown" | "expired" | "used"

-- The code as stored: letters and digits only, upper case; nil for anything else (empty, too long, symbols, spaces
-- inside). Spaces around it are forgiven.
function CodeRules.normalize(text: unknown): string?
	if type(text) ~= "string" then
		return nil
	end
	local trimmed = string.match(text, "^%s*(.-)%s*$") or ""
	if trimmed == "" or #trimmed > CodeRules.MAX_LENGTH or string.match(trimmed, "^%w+$") == nil then
		return nil
	end
	return string.upper(trimmed)
end

-- The save flag that marks `code` (normalized) as redeemed.
function CodeRules.flagKey(code: string): string
	return `code_{code}`
end

-- The code's definition if this player may redeem it now, or nil and why not. `code` is what the player typed.
function CodeRules.check(
	config: CodesConfig,
	typed: unknown,
	flags: { [string]: boolean },
	now: number
): (CodeDef?, string?, Refusal?)
	local code = CodeRules.normalize(typed)
	if code == nil then
		return nil, nil, "invalid"
	end
	local def = config[code]
	if def == nil then
		return nil, code, "unknown"
	end
	if def.expiresAt ~= nil and now >= def.expiresAt then
		return nil, code, "expired"
	end
	if flags[CodeRules.flagKey(code)] == true then
		return nil, code, "used"
	end
	return def, code, nil
end

-- Problems with the codes config (an empty list means valid). `creatures` / `mutations` are the known ids.
function CodeRules.validate(config: CodesConfig, creatures: { [string]: any }, mutations: { [string]: any }): { string }
	local problems: { string } = {}
	local function problem(message: string)
		table.insert(problems, message)
	end
	for code, def in config do
		local name = `code {code}`
		if CodeRules.normalize(code) ~= code then
			problem(`{name} must be upper-case letters and digits, at most {CodeRules.MAX_LENGTH}`)
		end
		local reward = def.reward :: any
		if reward.kind == "cash" then
			if
				not (
					type(reward.incomeSeconds) == "number"
					and reward.incomeSeconds > 0
					and reward.incomeSeconds <= 3600
				)
			then
				problem(`{name} incomeSeconds must be between 0 and 3600`)
			end
			if not (type(reward.minimum) == "number" and reward.minimum >= 0 and reward.minimum < math.huge) then
				problem(`{name} minimum must be 0 or more`)
			end
		elseif reward.kind == "creature" then
			if creatures[reward.creatureId] == nil then
				problem(`{name} gives unknown Snackling {tostring(reward.creatureId)}`)
			end
			if reward.variant ~= nil and mutations[reward.variant] == nil then
				problem(`{name} gives unknown mutation {tostring(reward.variant)}`)
			end
		else
			problem(`{name} reward kind must be cash or creature`)
		end
		if def.expiresAt ~= nil and not (def.expiresAt > 1600000000) then
			problem(`{name} expiresAt must be a unix time in seconds`)
		end
	end
	return problems
end

return CodeRules
