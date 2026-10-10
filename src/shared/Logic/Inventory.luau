--!strict
--[[
	Podium slot operations on the saved creature list. Every creature has a stable per-player `uid` and exactly
	one podium; at most one creature per podium. Pure: no Roblox APIs.
]]

local Types = require("../Types")

export type CreatureRecord = Types.CreatureRecord
export type Owner = { creatures: { CreatureRecord }, nextUid: number }

local Inventory = {}

function Inventory.findFreePodium(creatures: { CreatureRecord }, capacity: number): number?
	local used: { [number]: boolean } = {}
	for _, record in creatures do
		used[record.podium] = true
	end
	for podium = 1, capacity do
		if not used[podium] then
			return podium
		end
	end
	return nil
end

function Inventory.findByPodium(creatures: { CreatureRecord }, podium: number): (CreatureRecord?, number?)
	for index, record in creatures do
		if record.podium == podium then
			return record, index
		end
	end
	return nil, nil
end

function Inventory.findByUid(creatures: { CreatureRecord }, uid: string): (CreatureRecord?, number?)
	for index, record in creatures do
		if record.uid == uid then
			return record, index
		end
	end
	return nil, nil
end

-- Places a new creature on `podium` (caller has checked it is free), with its mutation id (`variant`, nil for a
-- plain one). Returns the new record.
function Inventory.add(owner: Owner, creatureId: string, podium: number, now: number, variant: string?): CreatureRecord
	local record: CreatureRecord = {
		uid = tostring(owner.nextUid),
		id = creatureId,
		podium = podium,
		acquiredAt = now,
		stored = 0,
		variant = variant,
	}
	owner.nextUid += 1
	table.insert(owner.creatures, record)
	return record
end

function Inventory.removeByUid(creatures: { CreatureRecord }, uid: string): CreatureRecord?
	local record, index = Inventory.findByUid(creatures, uid)
	if record ~= nil and index ~= nil then
		table.remove(creatures, index)
	end
	return record
end

-- Moves a creature from one owner to another (a completed steal; later: trades). The receiver gets a fresh uid
-- and the creature lands on `podium` with its mutation (variant). Returns the new record, or nil if the uid was not
-- found.
function Inventory.transfer(from: Owner, to: Owner, uid: string, podium: number, now: number): CreatureRecord?
	local record = Inventory.removeByUid(from.creatures, uid)
	if record == nil then
		return nil
	end
	return Inventory.add(to, record.id, podium, now, record.variant)
end

return Inventory
