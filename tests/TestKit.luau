--!strict
--[[
	A tiny test framework for Lune (no dependencies, so the tests also type-check as plain Luau).

	local T = require("./TestKit")
	T.describe("Format", function()
		T.it("abbreviates", function()
			T.expect(Format.number(1500)).toBe("1.5K")
		end)
	end)
]]

export type Expectation = {
	toBe: (expected: any) -> (),
	toEqual: (expected: any) -> (),
	toBeNear: (expected: number, epsilon: number?) -> (),
	toBeTruthy: () -> (),
	toBeFalsy: () -> (),
	toBeNil: () -> (),
	toBeGreaterThan: (expected: number) -> (),
	toBeLessThan: (expected: number) -> (),
	toBeAtLeast: (expected: number) -> (),
	toBeAtMost: (expected: number) -> (),
}

local TestKit = {}

local stack: { string } = {}
local passed = 0
local failures: { { name: string, message: string } } = {}

local function render(value: any): string
	if type(value) == "string" then
		return string.format("%q", value)
	elseif type(value) == "table" then
		local parts = {}
		for k, v in value do
			table.insert(parts, `{tostring(k)}={render(v)}`)
		end
		table.sort(parts)
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	return tostring(value)
end

local function deepEqual(a: any, b: any): boolean
	if type(a) ~= type(b) then
		return false
	end
	if type(a) ~= "table" then
		return a == b
	end
	for k, v in a do
		if not deepEqual(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

function TestKit.describe(name: string, body: () -> ())
	table.insert(stack, name)
	body()
	table.remove(stack)
end

function TestKit.it(name: string, body: () -> ())
	local fullName = table.concat(stack, " > ") .. " > " .. name
	local ok, err = pcall(body :: () -> ...any)
	if ok then
		passed += 1
	else
		table.insert(failures, { name = fullName, message = tostring(err) })
	end
end

function TestKit.expect(actual: any): Expectation
	local function fail(message: string)
		error(message, 3)
	end
	return {
		toBe = function(expected: any)
			if actual ~= expected then
				fail(`expected {render(expected)}, got {render(actual)}`)
			end
		end,
		toEqual = function(expected: any)
			if not deepEqual(actual, expected) then
				fail(`expected {render(expected)}, got {render(actual)}`)
			end
		end,
		toBeNear = function(expected: number, epsilon: number?)
			local eps = epsilon or 1e-9
			if type(actual) ~= "number" or math.abs(actual - expected) > eps then
				fail(`expected {expected} (+-{eps}), got {render(actual)}`)
			end
		end,
		toBeTruthy = function()
			if not actual then
				fail(`expected truthy, got {render(actual)}`)
			end
		end,
		toBeFalsy = function()
			if actual then
				fail(`expected falsy, got {render(actual)}`)
			end
		end,
		toBeNil = function()
			if actual ~= nil then
				fail(`expected nil, got {render(actual)}`)
			end
		end,
		toBeGreaterThan = function(expected: number)
			if type(actual) ~= "number" or not (actual > expected) then
				fail(`expected > {expected}, got {render(actual)}`)
			end
		end,
		toBeLessThan = function(expected: number)
			if type(actual) ~= "number" or not (actual < expected) then
				fail(`expected < {expected}, got {render(actual)}`)
			end
		end,
		toBeAtLeast = function(expected: number)
			if type(actual) ~= "number" or not (actual >= expected) then
				fail(`expected >= {expected}, got {render(actual)}`)
			end
		end,
		toBeAtMost = function(expected: number)
			if type(actual) ~= "number" or not (actual <= expected) then
				fail(`expected <= {expected}, got {render(actual)}`)
			end
		end,
	}
end

-- Deterministic RNG for tests (linear congruential), returns numbers in [0, 1).
function TestKit.seededRandom(seed: number): () -> number
	local state = seed % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	return function(): number
		state = (state * 48271) % 2147483647
		return (state - 1) / 2147483646
	end
end

-- Prints a summary and raises an error (non-zero exit code) if anything failed.
function TestKit.finish()
	for _, failure in failures do
		print(`FAIL  {failure.name}\n      {failure.message}`)
	end
	print(`\n{passed} passed, {#failures} failed`)
	if #failures > 0 then
		error(`{#failures} test(s) failed`, 0)
	end
end

return TestKit
