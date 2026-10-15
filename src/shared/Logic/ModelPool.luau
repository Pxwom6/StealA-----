--!strict
--[[
	A bounded pool of things to reuse, keyed by what they look like: BeltController parks a belt Snackling's model under
	"creature|mutation" when it leaves the belt and takes it back for the next item that looks the same (DECISIONS.md
	#47). Pure bookkeeping: the caller builds what take() can't give and destroys what park() hands back.

	At most `perKey` are parked under one key and `total` in all. Parking past either cap gives back the one to destroy:
	the newcomer when its key is full, else the least recently parked. So a session never keeps more than `total`
	spare models, however many creature and mutation pairs it has seen (the old pool kept one of every pair forever:
	about 450 models after 10 hours).
]]

local ModelPool = {}

type Entry<T> = { key: string, item: T }

export type Pool<T> = {
	perKey: number,
	total: number,
	entries: { Entry<T> }, -- parked, least recently parked first
	perKeyCount: { [string]: number },
}

function ModelPool.new<T>(perKey: number, total: number): Pool<T>
	return {
		perKey = math.max(0, math.floor(perKey)),
		total = math.max(0, math.floor(total)),
		entries = {},
		perKeyCount = {},
	}
end

-- A parked item for `key` (the most recently parked one), taken out of the pool; nil when there is none.
function ModelPool.take<T>(pool: Pool<T>, key: string): T?
	for index = #pool.entries, 1, -1 do
		local entry = pool.entries[index]
		if entry.key == key then
			table.remove(pool.entries, index)
			pool.perKeyCount[key] -= 1
			return entry.item
		end
	end
	return nil
end

-- Parks `item` under `key`. Returns what to destroy (empty when everything fits).
function ModelPool.park<T>(pool: Pool<T>, key: string, item: T): { T }
	if (pool.perKeyCount[key] or 0) >= pool.perKey then
		return { item } -- one like it is already waiting
	end
	table.insert(pool.entries, { key = key, item = item })
	pool.perKeyCount[key] = (pool.perKeyCount[key] or 0) + 1
	local evicted: { T } = {}
	while #pool.entries > pool.total do
		local oldest = table.remove(pool.entries, 1) :: Entry<T>
		pool.perKeyCount[oldest.key] -= 1
		table.insert(evicted, oldest.item)
	end
	return evicted
end

-- How many items are parked.
function ModelPool.size<T>(pool: Pool<T>): number
	return #pool.entries
end

-- Every parked item (least recently parked first), e.g. to update them all.
function ModelPool.items<T>(pool: Pool<T>): { T }
	local list: { T } = {}
	for _, entry in pool.entries do
		table.insert(list, entry.item)
	end
	return list
end

return ModelPool
