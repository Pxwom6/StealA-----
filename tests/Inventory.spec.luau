--!strict
local T = require("./TestKit")
local Inventory = require("../src/shared/Logic/Inventory")
local PlotAssignment = require("../src/shared/Logic/PlotAssignment")
local Catalog = require("../src/shared/Logic/Catalog")
local F = require("./Fixtures")

T.describe("Inventory", function()
	T.it("finds the lowest free podium within capacity", function()
		local owner: Inventory.Owner = { creatures = {}, nextUid = 1 }
		T.expect(Inventory.findFreePodium(owner.creatures, 3)).toBe(1)
		Inventory.add(owner, "a", 1, 0)
		Inventory.add(owner, "b", 3, 0)
		T.expect(Inventory.findFreePodium(owner.creatures, 3)).toBe(2)
		Inventory.add(owner, "c", 2, 0)
		T.expect(Inventory.findFreePodium(owner.creatures, 3)).toBeNil()
		T.expect(Inventory.findFreePodium(owner.creatures, 4)).toBe(4)
	end)
	T.it("assigns increasing uids and finds by podium / uid", function()
		local owner: Inventory.Owner = { creatures = {}, nextUid = 7 }
		local record = Inventory.add(owner, "a", 2, 123)
		T.expect(record.uid).toBe("7")
		T.expect(owner.nextUid).toBe(8)
		T.expect((Inventory.findByPodium(owner.creatures, 2) :: Inventory.CreatureRecord).id).toBe("a")
		T.expect((Inventory.findByPodium(owner.creatures, 1))).toBeNil()
		T.expect((Inventory.findByUid(owner.creatures, "7") :: Inventory.CreatureRecord).podium).toBe(2)
	end)
	T.it("transfers between owners exactly once", function()
		local victim: Inventory.Owner = { creatures = {}, nextUid = 1 }
		local thief: Inventory.Owner = { creatures = {}, nextUid = 50 }
		local record = Inventory.add(victim, "donut", 1, 0)
		local moved = Inventory.transfer(victim, thief, record.uid, 4, 99) :: Inventory.CreatureRecord
		T.expect(#victim.creatures).toBe(0)
		T.expect(#thief.creatures).toBe(1)
		T.expect(moved.id).toBe("donut")
		T.expect(moved.podium).toBe(4)
		T.expect(moved.uid).toBe("50")
		T.expect(Inventory.transfer(victim, thief, record.uid, 5, 99)).toBeNil()
		T.expect(#thief.creatures).toBe(1)
	end)
	T.it("stores the mutation variant and keeps it across a transfer", function()
		local victim: Inventory.Owner = { creatures = {}, nextUid = 1 }
		local thief: Inventory.Owner = { creatures = {}, nextUid = 1 }
		local plain = Inventory.add(victim, "pup", 1, 0)
		local golden = Inventory.add(victim, "pup", 2, 0, "golden")
		local unknown = Inventory.add(victim, "pup", 3, 0, "not_in_config")
		T.expect(plain.variant).toBeNil()
		T.expect(golden.variant).toBe("golden")
		local moved = Inventory.transfer(victim, thief, golden.uid, 1, 5) :: Inventory.CreatureRecord
		T.expect(moved.variant).toBe("golden")
		local movedUnknown = Inventory.transfer(victim, thief, unknown.uid, 2, 5) :: Inventory.CreatureRecord
		T.expect(movedUnknown.variant).toBe("not_in_config")
		local movedPlain = Inventory.transfer(victim, thief, plain.uid, 3, 5) :: Inventory.CreatureRecord
		T.expect(movedPlain.variant).toBeNil()
		T.expect(#victim.creatures).toBe(0)
	end)
end)

T.describe("PlotAssignment", function()
	T.it("claims the lowest free plot, is idempotent, and releases", function()
		local owners: PlotAssignment.Owners = {}
		T.expect(PlotAssignment.claim(owners, 2, 111)).toBe(1)
		T.expect(PlotAssignment.claim(owners, 2, 111)).toBe(1)
		T.expect(PlotAssignment.claim(owners, 2, 222)).toBe(2)
		T.expect(PlotAssignment.claim(owners, 2, 333)).toBeNil()
		T.expect(PlotAssignment.release(owners, 111)).toBe(1)
		T.expect(PlotAssignment.claim(owners, 2, 333)).toBe(1)
		T.expect(PlotAssignment.release(owners, 999)).toBeNil()
	end)
end)

T.describe("Catalog", function()
	local rarities = { F.rarity("B", 2, 1, true), F.rarity("A", 1, 10, false) }
	local x = F.creature("x", "A", 1)
	local y = F.creature("y", "B", 1)
	y.price = 2
	local creatures = { x, y }
	T.it("indexes and sorts", function()
		local catalog = Catalog.build(creatures, rarities)
		T.expect(catalog.rarityList[1].id).toBe("A")
		T.expect(catalog.creatures.y.price).toBe(2)
		T.expect(#catalog.byRarity.B).toBe(1)
		T.expect((Catalog.rarityOf(catalog, "y") :: Catalog.RarityInfo).id).toBe("B")
		T.expect(Catalog.rarityOf(catalog, "nope")).toBeNil()
	end)
	T.it("reports config problems", function()
		local bad1 = F.creature("x", "Nope", 1)
		bad1.price = 1.5
		bad1.income = 0
		local bad2 = F.creature("x", "A", 1)
		local bad = { bad1, bad2 }
		local problems = Catalog.validate(bad, rarities)
		T.expect(#problems).toBeAtLeast(5)
	end)
end)

return nil
