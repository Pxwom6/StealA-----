--!strict
-- Type stubs for Lune's built-in @lune/task (only what tools use); see fs.luau.
local task = {}

function task.wait(_seconds: number?): number
	error("stub")
end

function task.spawn(_callback: (...any) -> ...any): thread
	error("stub")
end

function task.defer(_callback: (...any) -> ...any): thread
	error("stub")
end

function task.delay(_seconds: number, _callback: (...any) -> ...any): thread
	error("stub")
end

function task.cancel(_thread: thread)
	error("stub")
end

return task
