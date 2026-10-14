--!strict
--[[
	A stand-in for ProfileStore in the offline server (tools/worldsim): the same calls DataService makes, with every
	profile kept in memory. A profile starts as a deep copy of the template (or of `MockProfileStore.saves[key]`, so a
	test can start a player from any save) and is written back there on Save / EndSession.
]]

local Sim = require("./Sim")

local MockProfileStore = {}

-- Saves by profile key, read when a session starts and written when it saves or ends.
MockProfileStore.saves = {} :: { [string]: any }
MockProfileStore.IsClosing = false
MockProfileStore.OnError = Sim.signal()

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, item in value do
		result[key] = deepCopy(item)
	end
	return result
end

function MockProfileStore.New(_name: string, template: any): any
	local store = {}
	function store.StartSessionAsync(_self: any, key: string, _params: any): any
		local active = true
		local profile: any = {
			Data = deepCopy(MockProfileStore.saves[key] or template),
			Key = key,
			OnSave = Sim.signal(),
			OnLastSave = Sim.signal(),
			OnAfterSave = Sim.signal(),
			OnSessionEnd = Sim.signal(),
		}
		profile.LastSavedData = profile.Data
		function profile.IsActive(_: any): boolean
			return active
		end
		function profile.Save(_: any)
			if not active then
				return
			end
			profile.OnSave:Fire()
			MockProfileStore.saves[key] = deepCopy(profile.Data)
			profile.OnAfterSave:Fire(profile.Data)
		end
		function profile.EndSession(_: any)
			if not active then
				return
			end
			profile.OnLastSave:Fire("Manual")
			MockProfileStore.saves[key] = deepCopy(profile.Data)
			active = false
			profile.OnSessionEnd:Fire()
		end
		function profile.AddUserId(_: any, _userId: number) end
		function profile.Reconcile(_: any)
			for field, value in template do
				if profile.Data[field] == nil then
					profile.Data[field] = deepCopy(value)
				end
			end
		end
		return profile
	end
	return store
end

return MockProfileStore
