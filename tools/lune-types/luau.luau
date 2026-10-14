--!strict
-- Type stubs for Lune's built-in @lune/luau (only what tools use); see fs.luau.
local luau = {}

export type LoadOptions = { debugName: string?, environment: { [string]: any }?, injectGlobals: boolean? }

function luau.load(_source: string, _options: LoadOptions?): (...any) -> ...any
	error("stub")
end

return luau
