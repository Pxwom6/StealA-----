--!strict
-- Type stubs for Lune's built-in @lune/process (only what tools use); see fs.luau.
local process = {}

process.args = {} :: { string }

function process.exit(_code: number?): never
	error("stub")
end

return process
