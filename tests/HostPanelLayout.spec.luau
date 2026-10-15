--!strict
-- The host panel's layout (Logic/HostPanelLayout), held to the HUD's rules (DECISIONS #47): it fits every checked
-- screen below Roblox's top bar, its buttons are full touch targets and its text reads at 12 UI or more.
local T = require("./TestKit")
local Catalog = require("../src/shared/Logic/Catalog")
local CrossServerRules = require("../src/shared/Logic/CrossServerRules")
local Format = require("../src/shared/Logic/Format")
local HostPanelLayout = require("../src/shared/Logic/HostPanelLayout")
local MutationRules = require("../src/shared/Logic/MutationRules")
local ScreenLayout = require("../src/shared/Logic/ScreenLayout")
local TextFit = require("../src/shared/Logic/TextFit")
local Creatures = require("../src/shared/Config/Creatures")
local Host = require("../src/shared/Config/Host")
local LiveOps = require("../src/shared/Config/LiveOps")
local MapThemes = require("../src/shared/Config/MapThemes")
local Modifiers = require("../src/shared/Config/Modifiers")
local Mutations = require("../src/shared/Config/Mutations")
local Rarities = require("../src/shared/Config/Rarities")
local Theme = require("../src/shared/Config/Theme")

type Rect = HostPanelLayout.Rect
type Box = HostPanelLayout.Box

local catalog = Catalog.build(Creatures, Rarities, Mutations)
local L = HostPanelLayout
local MIN = ScreenLayout.TEXT.minSize
local ROLES: { HostPanelLayout.Role } = { "admin", "owner" }

-- Every box `role` can see: the tab bar's and each of its tabs', by "tab.name".
local function allBoxes(role: HostPanelLayout.Role): { [string]: Box }
	local result: { [string]: Box } = {}
	for index, id in L.tabs(role) do
		result[`tabs.{id}`] = { rect = L.tabButton(index), kind = "button" }
	end
	if role == "admin" then
		result["tabs.scope"] = { rect = L.scopeButton(), kind = "button" }
	else
		result["tabs.owner"] = { rect = L.ownerNote(), kind = "label" }
	end
	for _, id in L.tabs(role) do
		for name, b in L.tab(id, role) do
			result[`{id}.{name}`] = b
		end
	end
	return result
end

local function overlaps(a: Rect, b: Rect): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

-- The size `text` comes out at in a button or value box `r` (padded like UiKit.button).
local function inButton(text: string, r: Rect, wrapped: boolean): number
	return TextFit.fit(text, r.w - 2 * L.PAD.x, r.h - 2 * L.PAD.y, wrapped)
end

T.describe("HostPanelLayout", function()
	T.it("fits every checked screen below Roblox's top bar, at the smallest scale", function()
		local problems: { string } = {}
		for _, spec in ScreenLayout.DEVICES do
			local device = ScreenLayout.device(spec)
			for _, problem in L.fitProblems(device.width, device.height, device.topBar, ScreenLayout.EDGE) do
				table.insert(problems, `{spec.name}: {problem}`)
			end
		end
		T.expect(table.concat(problems, "; ")).toBe("")
		-- and the body is the dialog less Modal's margins
		T.expect(L.BODY.w).toBe(L.DIALOG.w - 32)
		T.expect(L.BODY.h).toBe(L.DIALOG.h - 72)
		-- Modal's rule for landscape phones
		T.expect(L.DIALOG.h).toBeAtMost(340)
	end)

	T.it("gives admins five tabs and a scope switch, and owners Map and Modifiers", function()
		T.expect(L.tabs("admin")).toEqual({ "map", "modifiers", "belt", "boosts", "broadcast" })
		T.expect(L.tabs("owner")).toEqual({ "map", "modifiers" })
		T.expect(L.tab("map", "owner").vote).toBeNil()
		T.expect(L.tab("map", "admin").vote ~= nil).toBe(true)
	end)

	for _, each in ROLES do
		local role: HostPanelLayout.Role = each :: HostPanelLayout.Role
		T.it(`keeps every {role} box inside the body, apart from each other`, function()
			local problems: { string } = {}
			local boxes = allBoxes(role)
			for name, b in boxes do
				local r = b.rect
				if r.x < 0 or r.y < 0 or r.x + r.w > L.BODY.w + 1e-6 or r.y + r.h > L.BODY.h + 1e-6 then
					table.insert(problems, `{name} sticks out`)
				end
			end
			-- within a tab (and with the tab bar, which every tab shares)
			for nameA, a in boxes do
				for nameB, b in boxes do
					local tabA, tabB = string.match(nameA, "^(%w+)%."), string.match(nameB, "^(%w+)%.")
					local together = tabA == tabB or tabA == "tabs" or tabB == "tabs"
					if nameA < nameB and together and overlaps(a.rect, b.rect) then
						table.insert(problems, `{nameA} overlaps {nameB}`)
					end
				end
			end
			table.sort(problems)
			T.expect(table.concat(problems, "; ")).toBe("")
		end)

		T.it(`makes every {role} button and list cell a full touch target`, function()
			local small: { string } = {}
			for name, b in allBoxes(role) do
				if b.kind == "button" and (b.rect.w < L.BUTTON or b.rect.h < L.BUTTON) then
					table.insert(small, name)
				end
				local cell = b.cell
				if cell and (cell.w < L.BUTTON or cell.h < L.BUTTON) then
					table.insert(small, `{name} cells`)
				end
			end
			T.expect(table.concat(small, ", ")).toBe("")
			-- 52 UI is 44 px at the smallest scale
			T.expect(L.BUTTON * ScreenLayout.SCALE.min).toBeAtLeast(ScreenLayout.MIN_TOUCH)
		end)
	end

	T.it(
		"lays its lists out as the grids the controller builds (cells side by side, inset, beside the scroll bar)",
		function()
			for _, b in
				{ L.tab("map", "admin").list, L.tab("belt", "admin").creatures, L.tab("belt", "admin").mutations }
			do
				local cell = b.cell :: { w: number, h: number }
				local columns = b.columns :: number
				local inner = b.rect.w - 2 * L.LIST_INSET - L.SCROLLBAR
				T.expect(columns * cell.w + (columns - 1) * L.GAP).toBe(inner)
			end
		end
	)
end)

T.describe("HostPanelLayout text", function()
	local admin = function(id: string): { [string]: Box }
		return L.tab(id, "admin")
	end
	local small: { string } = {}
	local function check(what: string, size: number)
		if size < MIN then
			table.insert(small, `{what} ({math.floor(size * 10) / 10})`)
		end
	end

	T.it("fits the tab names, the scope switch and the owner's note", function()
		table.clear(small)
		local tabRect = L.tabButton(1)
		for _, key in { "hostTabMap", "hostTabModifiers", "hostTabBelt", "hostTabBoosts", "hostTabBroadcast" } do
			check(key, inButton((Theme.text :: any)[key], tabRect, false))
		end
		check("hostScopeServer", inButton(Theme.text.hostScopeServer, L.scopeButton(), false))
		check("hostScopeAll", inButton(Theme.text.hostScopeAll, L.scopeButton(), false))
		local note = L.ownerNote()
		check("hostOwnerNote", TextFit.fit(Theme.text.hostOwnerNote, note.w, note.h, false))
		T.expect(table.concat(small, ", ")).toBe("")
	end)

	T.it("fits every map and modifier in its list cell, and the line about the current one", function()
		table.clear(small)
		local map = admin("map")
		local cell = map.list.cell :: { w: number, h: number }
		local cellRect = { x = 0, y = 0, w = cell.w, h = cell.h }
		for _, id in MapThemes.order do
			local theme = MapThemes.themes[id]
			check(id, inButton(`{theme.icon} {theme.displayName}`, cellRect, true))
			local line = Format.template(Theme.text.hostMapNow, { icon = theme.icon, map = theme.displayName })
			check(`now {id}`, TextFit.fit(line, map.now.rect.w, map.now.rect.h, false))
		end
		local mods = admin("modifiers")
		for _, id in Modifiers.order do
			local def = Modifiers.modifiers[id]
			check(id, inButton(`{def.icon} {def.displayName}`, cellRect, true))
			local line =
				Format.template(Theme.text.hostModNow, { icon = def.icon, name = def.displayName, time = "59:59" })
			check(`now {id}`, TextFit.fit(line, mods.now.rect.w, mods.now.rect.h, false))
		end
		check("hostModNone", TextFit.fit(Theme.text.hostModNone, mods.now.rect.w, mods.now.rect.h, false))
		T.expect(table.concat(small, ", ")).toBe("")
	end)

	T.it("fits every Snackling and mutation in the Belt tab, and what will drop", function()
		table.clear(small)
		local belt = admin("belt")
		local creatureCell = belt.creatures.cell :: { w: number, h: number }
		local mutationCell = belt.mutations.cell :: { w: number, h: number }
		local summary = belt.summary.rect
		for _, def in catalog.creatureList do
			check(def.id, inButton(def.displayName, { x = 0, y = 0, w = creatureCell.w, h = creatureCell.h }, true))
			local rarity = string.upper(catalog.rarities[def.rarity].displayName)
			for index = 1, #catalog.mutationList + 1 do
				local variant = if index == 1 then nil else catalog.mutationList[index - 1].id
				local name = MutationRules.displayName(catalog.mutations, def, variant, Theme.text.mutatedName)
				local text = Format.template(Theme.text.hostBeltSummary, { rarity = rarity, creature = name })
				local size = TextFit.fit(text, summary.w, summary.h, true)
				if size < MIN then
					check(text, size)
				end
			end
		end
		local mutationRect = { x = 0, y = 0, w = mutationCell.w, h = mutationCell.h }
		check("hostBeltPlain", inButton(Theme.text.hostBeltPlain, mutationRect, true))
		for _, mutation in catalog.mutationList do
			check(mutation.id, inButton(mutation.displayName, mutationRect, true))
		end
		T.expect(table.concat(small, ", ")).toBe("")
	end)

	T.it("fits every value the steppers can show, and every button's words", function()
		table.clear(small)
		local P = Host.presets
		local mods, boosts, map = admin("modifiers"), admin("boosts"), admin("map")
		for _, minutes in P.modifierMinutes do
			check(
				`mod {minutes}`,
				inButton(Format.template(Theme.text.hostMinutes, { minutes = minutes }), mods.minutesValue.rect, true)
			)
		end
		for _, multiplier in P.luckMultiplier do
			check(
				`luck {multiplier}`,
				inButton(
					Format.template(Theme.text.hostLuckValue, { multiplier = multiplier }),
					boosts.luckValue.rect,
					true
				)
			)
		end
		for _, minutes in P.luckMinutes do
			check(
				`luck {minutes} min`,
				inButton(
					Format.template(Theme.text.hostMinutes, { minutes = minutes }),
					boosts.luckMinutesValue.rect,
					true
				)
			)
		end
		for _, event in LiveOps.events do
			local text = Format.template(Theme.text.hostEventValue, { event = event.title or event.id })
			check(event.id, inButton(text, boosts.eventValue.rect, true))
		end
		check("hostEventDefault", inButton(Theme.text.hostEventDefault, boosts.eventMinutesValue.rect, true))
		for _, minutes in P.eventMinutes do
			check(
				`event {minutes} min`,
				inButton(
					Format.template(Theme.text.hostMinutes, { minutes = minutes }),
					boosts.eventMinutesValue.rect,
					true
				)
			)
		end
		for _, minutes in P.giftMinutes do
			check(
				`gift {minutes}`,
				inButton(Format.template(Theme.text.hostGiftValue, { minutes = minutes }), boosts.giftValue.rect, true)
			)
		end
		local hint = boosts.giftHint.rect
		check("hostGiftHint", TextFit.fit(Theme.text.hostGiftHint, hint.w, hint.h, true))
		local ready = Format.template(Theme.text.hostReadyIn, { time = "9:59" })
		for _, entry in
			{
				{ "hostMapSwitch", map.switch.rect },
				{ "hostMapVote", (map.vote :: Box).rect },
				{ "hostRotationOn", map.rotation.rect },
				{ "hostRotationOff", map.rotation.rect },
				{ "ready", map.switch.rect },
				{ "hostModStart", mods.start.rect },
				{ "ready", mods.start.rect },
				{ "hostModStop", mods.stop.rect },
				{ "hostBeltDrop", admin("belt").drop.rect },
				{ "hostLuckStart", boosts.luckStart.rect },
				{ "hostEventStart", boosts.eventStart.rect },
				{ "hostEventStop", boosts.eventStop.rect },
				{ "hostGiftSend", boosts.giftSend.rect },
				{ "ready", boosts.giftSend.rect },
				{ "hostBroadcastSend", admin("broadcast").send.rect },
			} :: { { any } }
		do
			local key, r = entry[1] :: string, entry[2] :: Rect
			local text = if key == "ready" then ready else (Theme.text :: any)[key]
			check(key, inButton(text, r, false))
		end
		T.expect(table.concat(small, ", ")).toBe("")
	end)

	T.it("fits the Message tab's note and count, and the Settings row", function()
		table.clear(small)
		local broadcast = admin("broadcast")
		local note, count = broadcast.note.rect, broadcast.count.rect
		check("hostBroadcastNote", TextFit.fit(Theme.text.hostBroadcastNote, note.w, note.h, false))
		local counted = Format.template(
			Theme.text.hostBroadcastCount,
			{ count = Host.limits.broadcastLength, max = Host.limits.broadcastLength }
		)
		check("hostBroadcastCount", TextFit.fit(counted, count.w, count.h, false))
		-- Settings (460 wide): half of its last row, less the label's 16 a side
		local half = (460 - 32) / 2 - 4
		check("settingsHost", TextFit.fit(Theme.text.settingsHost, half - 32, 40, false))
		check("settingsCodes", TextFit.fit(Theme.text.settingsCodes, half - 32, 40, false))
		T.expect(table.concat(small, ", ")).toBe("")
	end)

	T.it("fits the host panel's banners in the narrowest announcement banner", function()
		table.clear(small)
		local narrowest = math.huge
		for _, spec in ScreenLayout.DEVICES do
			local layout = ScreenLayout.layout(ScreenLayout.device(spec), ScreenLayout.SCENARIOS[1].state)
			narrowest = math.min(narrowest, layout.byId.announcement.w)
		end
		local w = narrowest - 2 * ScreenLayout.TEXT.banner.padX
		local h = ScreenLayout.SIZE.banner.h - 2 * ScreenLayout.TEXT.banner.padY
		-- Shout-outs: every find worth one, with the widest names a player can have (shortened as ShoutoutService does).
		-- Admin drops: every Snackling with every mutation.
		local names: { string } = { string.rep("W", 20), string.rep("m", 20), "SuperCoolGamer123456" }
		for _, def in catalog.creatureList do
			local rarity = string.upper(catalog.rarities[def.rarity].displayName)
			for index = 1, #catalog.mutationList + 1 do
				local variant = if index == 1 then nil else catalog.mutationList[index - 1].id
				local name = MutationRules.displayName(catalog.mutations, def, variant, Theme.text.mutatedName)
				local texts: { string } = {
					Format.template(Theme.text.announceAdminDrop, { rarity = rarity, creature = name }),
				}
				if CrossServerRules.isShoutworthy(def.rarity, variant, catalog.rarities, Host.shoutouts) then
					for _, player in names do
						local shown = CrossServerRules.shortName(player, CrossServerRules.SHOUT_NAME_LENGTH)
						table.insert(
							texts,
							Format.template(Theme.text.shoutout, { player = shown, rarity = rarity, creature = name })
						)
					end
				end
				for _, text in texts do
					local size = TextFit.fit(text, w, h, true)
					if size < MIN then
						check(text, size)
					end
				end
			end
		end
		local luck = Format.template(Theme.text.adminLuck, { multiplier = 5.5, minutes = 1440 })
		check("adminLuck", TextFit.fit(luck, w, h, true))
		T.expect(table.concat(small, ", ")).toBe("")
	end)
end)

return nil
