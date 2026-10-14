--!strict
-- Type stubs for Lune's built-in @lune/fs (only what tools use), so luau-lsp can check the tools. Lune itself always
-- loads its real built-in; the .luaurc "lune" alias points the type checker here.
local fs = {}

function fs.readFile(_path: string): string
	error("stub")
end

function fs.writeFile(_path: string, _contents: string)
	error("stub")
end

function fs.readDir(_path: string): { string }
	error("stub")
end

return fs
