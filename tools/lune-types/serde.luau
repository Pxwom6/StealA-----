--!strict
-- Type stubs for Lune's built-in @lune/serde (only what tools use); see fs.luau.
local serde = {}

function serde.decode(_format: "json" | "toml" | "yaml", _encoded: string): any
	error("stub")
end

return serde
