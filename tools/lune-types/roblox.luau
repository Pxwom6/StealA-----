--!strict
-- Type stubs for Lune's built-in @lune/roblox (only what tools use); see fs.luau. Instances and datatypes are `any`
-- here: the tools that use them (tools/worldsim) treat them dynamically.
local roblox = {}

roblox.Instance = (nil :: any) :: { new: (className: string) -> any }
roblox.Vector3 = nil :: any
roblox.Vector2 = nil :: any
roblox.CFrame = nil :: any
roblox.Color3 = nil :: any
roblox.BrickColor = nil :: any
roblox.UDim = nil :: any
roblox.UDim2 = nil :: any
roblox.Rect = nil :: any
roblox.Ray = nil :: any
roblox.Enum = nil :: any
roblox.Font = nil :: any
roblox.NumberRange = nil :: any
roblox.NumberSequence = nil :: any
roblox.NumberSequenceKeypoint = nil :: any
roblox.ColorSequence = nil :: any
roblox.ColorSequenceKeypoint = nil :: any
roblox.PhysicalProperties = nil :: any

function roblox.implementMethod(_className: string, _name: string, _callback: (...any) -> ...any)
	error("stub")
end

function roblox.implementProperty(
	_className: string,
	_name: string,
	_getter: (instance: any) -> any,
	_setter: ((instance: any, value: any) -> ())?
)
	error("stub")
end

return roblox
