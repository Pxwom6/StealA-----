--!strict
-- Type stubs for Lune's built-in @lune/serde (only what tools use); see fs.luau.
local serde = {}

function serde.decode(_format: "json" | "toml" | "yaml", _encoded: string): any
	error("stub")
end

function serde.encode(_format: "json" | "toml" | "yaml", _value: any, _pretty: boolean?): string
	error("stub")
end

return serde
