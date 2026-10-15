--!strict
--[[
	Titles, base skins and What's New, offline (CI runs it after the other server tests):
	    lune run tools/worldsim/cosmetics.luau

	Boots the whole server like tools/worldsim/server.luau with the clock virtual (Sim.virtualClock) and random
	modifiers and the map rotation off, then plays the features through the real remotes and hooks (DECISIONS.md
	"Titles, base skins and What's New"):
	  * What's New: the board on the spawn plaza (and through a map change); the card for a returning player once, and
	    never for a new player, a player still in the tutorial, or one who saw it; SeenNews only for the update waited
	    for; /news.
	  * Titles: a locked or garbage equip changes nothing; a player earns titles (the toast after the achievement's,
	    once), wears one, and others see it (the "Title" attribute and the nametag on their head, hidden only from
	    them); one at a time; hidden while carrying, back after; on a new character; taken off; a save with extras,
	    unknown and locked ones repaired on join, with no toasts again.
	  * Base skins: a locked one refused; one earned, worn, painted on the plot (tiles, rug, trims), kept through a map
	    change, beside VIP's gold caps, the rainbow one tagged for the clients and untagged when it comes off, /style
	    all and off, and the plot back to Classic when its owner leaves, and the skin back on when they return.
	It fails on any error, any unexpected warning, or any check.

	Alice is brand new; Bob (VIP), Dan (never finished the tutorial) and Eve (saw the update) played before.
]]

local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")
local Sim = require("./Sim")
local MockProfileStore = require("./MockProfileStore")

local Vector3 = roblox.Vector3
local OCTOBER_15_2026 = 1792023721
local DAY = 86400

Sim.mock("ServerPackages/ProfileStore.lua", MockProfileStore)
Sim.virtualClock = true
Sim.now = OCTOBER_15_2026
Sim.shared("Config/Modifiers").schedule.enabled = false -- only /mod starts one
Sim.shared("Config/MapThemes").rotation.enabled = false

local ALICE, BOB, CAROL, DAN, EVE = 6001, 6002, 6003, 6004, 6005

local EXPECTED_WARNINGS = {
	"MessagingService.SubscribeAsync is not available offline",
}

local failures: { string } = {}
local function check(ok: boolean, message: string)
	if ok then
		print(`  ok   {message}`)
	else
		print(`  FAIL {message}`)
		table.insert(failures, message)
	end
end

local function finish()
	for _, message in Sim.warnings do
		local expected = false
		for _, pattern in EXPECTED_WARNINGS do
			if string.find(message, pattern, 1, true) then
				expected = true
			end
		end
		if not expected then
			table.insert(failures, `warning: {message}`)
			print(`  FAIL warning: {message}`)
		end
	end
	if #failures > 0 then
		print(`cosmetics test: {#failures} problem(s)`)
		process.exit(1)
	end
	print("cosmetics test: no problems")
	process.exit(0)
end

-- Players who played before the server started (their saves are in the mock store already).
local DataSchema = Sim.shared("Logic/DataSchema")
local Economy = Sim.shared("Config/Economy")
local Monetization = Sim.shared("Config/Monetization")
local function returning(flags: { [string]: boolean }): any
	local save = DataSchema.template(Economy.startingCash)
	save.firstJoin = OCTOBER_15_2026 - 10 * DAY
	save.lastSeen = OCTOBER_15_2026 - DAY
	for key, value in flags do
		save.flags[key] = value
	end
	return save
end
local bobSave = returning({ tutorial_done = true })
bobSave.stats.playTime = 5 * 3600 -- long past the new-player shield
MockProfileStore.saves[`Player_{BOB}`] = bobSave
MockProfileStore.saves[`Player_{DAN}`] = returning({}) -- joined once, never finished the tutorial
MockProfileStore.saves[`Player_{EVE}`] = returning({ tutorial_done = true, news_1 = true })
Sim.ownedPasses[BOB] = { [Monetization.passes.VIP.id] = true }

local booted, bootError = pcall(function()
	Sim.require("ServerScriptService", "Server")
end)
if not booted then
	print(`the server failed to boot: {bootError}`)
	process.exit(1)
end

local Sessions = Sim.server("Services/Sessions")
local PlotService = Sim.server("Services/PlotService")
local EconomyService = Sim.server("Services/EconomyService")
local AchievementService = Sim.server("Services/AchievementService")
local StealService = Sim.server("Services/StealService")
local Gameplay = Sim.shared("Config/Gameplay")
local Skins = Sim.shared("Config/Skins")
local Theme = Sim.shared("Config/Theme")
local Titles = Sim.shared("Config/Titles")
local Updates = Sim.shared("Config/Updates")
local Format = Sim.shared("Logic/Format")
local StyleRules = Sim.shared("Logic/StyleRules")
local UpdateRules = Sim.shared("Logic/UpdateRules")
local CreatureVisuals = Sim.shared("CreatureVisuals")
local UiTheme = Sim.shared("UiTheme")
local CollectionService = Sim.service("CollectionService")
local workspace = Sim.workspace()

local LATEST = UpdateRules.latest(Updates)

local function sessionOf(player: any): any
	return Sessions.get(player)
end

local function join(userId: number, name: string): any
	local player = Sim.addPlayer(userId, name)
	task.wait(0.2)
	local session = sessionOf(player)
	assert(session, `{name} has no session`)
	Sim.spawnCharacter(player, PlotService.refs(session.plot).spawnCFrame.Position)
	Sim.fireServer(player, "ClientReady")
	task.wait(0.2)
	return player
end

local function leave(player: any)
	Sim.removePlayer(player)
	task.wait(0.3)
end

local function chat(player: any, text: string)
	Sim.chat(player, text)
	task.wait(0.1)
end

-- An intent a second after the last one (rate limits refill), then a moment for the server to answer.
local function send(player: any, remote: string, ...: any)
	Sim.advance(1.1)
	Sim.fireServer(player, remote, ...)
	task.wait(0.1)
end

local function toasts(userId: number): { string }
	local list = {}
	for _, args in Sim.received(userId, "Notify") do
		table.insert(list, args[1].text)
	end
	return list
end

local function indexOf(list: { string }, text: string): number
	return table.find(list, text) or 0
end

local function count(list: { string }, text: string): number
	local n = 0
	for _, entry in list do
		if entry == text then
			n += 1
		end
	end
	return n
end

local function lastSync(userId: number): any
	local list = Sim.received(userId, "StyleSync")
	local last = list[#list]
	return if last then last[1] else nil
end

local function flagsWith(flags: { [string]: boolean }, prefix: string): { string }
	local list = {}
	for key in flags do
		if string.sub(key, 1, #prefix) == prefix then
			table.insert(list, key)
		end
	end
	table.sort(list)
	return list
end

local function head(player: any): any
	return (player.Character :: any).Head
end

local function tags(player: any): { any }
	local list = {}
	for _, child in head(player):GetChildren() do
		if child.Name == "TitleTag" then
			table.insert(list, child)
		end
	end
	return list
end

local function title(id: string): any
	return StyleRules.titleById(Titles, id)
end

local function skinLook(id: string): any
	return (StyleRules.skinById(Skins, id) :: any).look
end

local function same(a: any, b: any): boolean
	return math.abs(a.R - b.R) < 1e-3 and math.abs(a.G - b.G) < 1e-3 and math.abs(a.B - b.B) < 1e-3
end

-- What a plot's cosmetic surfaces look like now, to compare later.
local function looks(plot: number): { string }
	local refs = PlotService.refs(plot)
	local list = {}
	local function add(part: any)
		local c = part.Color
		table.insert(list, string.format("%s %.3f %.3f %.3f %s", part.Name, c.R, c.G, c.B, part.Material.Name))
	end
	for _, tile in refs.tiles do
		add(tile.part)
	end
	add(refs.rug)
	for _, trim in refs.wallTrims do
		add(trim)
	end
	for _, cap in refs.caps do
		add(cap)
	end
	return list
end

local function equal(a: { string }, b: { string }): boolean
	return table.concat(a, "|") == table.concat(b, "|")
end

-- Moves a player somewhere, then lets enough server time pass for every movement check to trust them again.
local function teleport(player: any, position: any)
	Sim.moveCharacter(player, position)
	Sim.advance(1.5)
	task.wait(0.4)
	Sim.advance(11)
	task.wait(0.4)
end

-- `thief` grabs the Snackling on `victim`'s podium `podiumIndex` (standing next to it, trusted). Returns the carry.
local function grab(thief: any, victim: any, podiumIndex: number): any
	local thiefSession, victimSession = sessionOf(thief), sessionOf(victim)
	local podium = PlotService.podium(victimSession.plot, podiumIndex)
	teleport(thief, podium.base.Position + Vector3.new(4, 2, 0))
	Sim.fireServer(thief, "StealBegin", victimSession.plot, podiumIndex)
	task.wait(0.05)
	Sim.advance(Gameplay.steal.holdSeconds + 0.05)
	task.wait(0.05)
	Sim.fireServer(thief, "StealConfirm", victimSession.plot, podiumIndex)
	task.wait(0.1)
	return thiefSession.carry
end

local function scenario()
	print("cosmetics test:")

	-- What's New: the board -------------------------------------------------------------------------------------------
	local map = workspace.Map
	local board = map:FindFirstChild("NewsBoard")
	local surface = board and board:FindFirstChild("WhatsNew")
	check(board ~= nil and surface ~= nil, "the What's New board stands by the spawn plaza, its sign on it")
	check(map.Scenery:FindFirstChild("NewsBoard", true) == nil, "outside the Scenery folder a map change rebuilds")
	local boardParts = 0
	for _, child in map:GetChildren() do
		if string.sub(child.Name, 1, 9) == "NewsBoard" and child:IsA("BasePart") then
			boardParts += 1
		end
	end
	check(boardParts == 4, `a tiny board: panel, frame and two legs ({boardParts} parts)`)
	if surface then
		check(surface.Title.Text == LATEST.title, `it shows the newest update ({surface.Title.Text})`)
		check(surface.Line1.Text == LATEST.highlights[1], "and its highlights")
		check(surface:FindFirstChild(`Line{#LATEST.highlights}`) ~= nil, "every one of them")
	end

	-- What's New: who gets the card --------------------------------------------------------------------------------------
	local alice = join(ALICE, "Alice")
	local bob = join(BOB, "Bob")
	local dan = join(DAN, "Dan")
	local eve = join(EVE, "Eve")
	local a, b, d, e = sessionOf(alice), sessionOf(bob), sessionOf(dan), sessionOf(eve)
	local news = UpdateRules.flagKey(LATEST.number)
	check(#Sim.received(ALICE, "WhatsNew") == 0, "a brand-new player gets no What's New card (the tutorial instead)")
	check(a.data.flags[news] == true, "and the update she started in counts as seen")
	local bobCards = Sim.received(BOB, "WhatsNew")
	check(
		#bobCards == 1 and bobCards[1][1].number == LATEST.number,
		"a returning player who hasn't seen it is sent the card"
	)
	check(b.data.flags[news] == nil, "it isn't seen until his client shows it")
	check(#Sim.received(DAN, "WhatsNew") == 0 and d.tutorial ~= nil, "a player still in the tutorial gets none...")
	check(d.data.flags[news] == true, "...and it counts as seen")
	check(#Sim.received(EVE, "WhatsNew") == 0 and e.data.flags[news] == true, "one who saw it gets none")
	-- SeenNews allows two at once, then one every 5 s (Config/Gameplay.rateLimits): space them out.
	send(bob, "SeenNews", LATEST.number + 1)
	send(bob, "SeenNews", tostring(LATEST.number))
	Sim.advance(5)
	send(bob, "SeenNews", 0 / 0)
	check(b.data.flags[news] == nil, "SeenNews for another update, a string or NaN is ignored")
	Sim.advance(5)
	send(bob, "SeenNews", LATEST.number)
	check(b.data.flags[news] == true, "once his client shows it, it is seen (news_<number>)")
	local seen = 0
	for _, entry in Sim.analytics do
		if entry.method == "LogCustomEvent" and entry.args[2] == "news_seen" then
			seen += 1
		end
	end
	check(seen == 1, "and logged once")
	leave(bob)
	bob = join(BOB, "Bob")
	b = sessionOf(bob)
	check(#Sim.received(BOB, "WhatsNew") == 1, "rejoining, he doesn't get it again")
	leave(alice)
	alice = join(ALICE, "Alice")
	a = sessionOf(alice)
	check(#Sim.received(ALICE, "WhatsNew") == 0, "nor does Alice in her second session")
	chat(alice, "/news")
	local aliceCards = Sim.received(ALICE, "WhatsNew")
	check(#aliceCards == 1 and aliceCards[1][1].number == LATEST.number, "/news shows the card again (Studio)")
	local panelBefore = board
	chat(alice, "/map candy")
	check(map:FindFirstChild("NewsBoard") == panelBefore, "a map change leaves the board where it is")
	check(surface ~= nil and surface.Parent == panelBefore, "with its sign")

	for _, player in Sim.service("Players"):GetPlayers() do
		Sim.fireServer(player, "SkipTutorial")
	end
	task.wait(0.1)

	-- Titles ----------------------------------------------------------------------------------------------------------
	send(alice, "EquipStyle", "title", "masterThief")
	check(#flagsWith(a.data.flags, "title_") == 0, "a locked title can't be worn")
	check(alice:GetAttribute("Title") == "", "she wears none")
	local sync = lastSync(ALICE)
	check(sync ~= nil and sync.title == "", "the dialog is told the truth (StyleSync)")
	local garbage: { { any } } =
		{ { 123, "x" }, { "title", 5 }, { "hat", "masterThief" }, { "title", string.rep("a", 200) } }
	for _, args in garbage do
		send(alice, "EquipStyle", args[1], args[2])
	end
	check(#flagsWith(a.data.flags, "title_") == 0, "garbage arguments change nothing")

	a.data.stats.steals = 25 -- as if she had stolen 25 Snacklings
	AchievementService.check(a)
	local list = toasts(ALICE)
	local masterThief = title("masterThief")
	local unlocked = Format.template(Theme.text.titleUnlocked, { icon = masterThief.icon, title = masterThief.text })
	local achievementToast = 0
	for index, text in list do
		if string.find(text, "Master Thief", 1, true) and string.find(text, "Achievement", 1, true) then
			achievementToast = index
		end
	end
	check(a.data.flags.ach_masterThief == true, "25 steals earn Master Thief")
	check(indexOf(list, unlocked) > 0, `"{unlocked}" toasts`)
	check(achievementToast > 0 and achievementToast < indexOf(list, unlocked), "right after the achievement's toast")
	local sticky = title("stickyFingers")
	check(
		indexOf(list, Format.template(Theme.text.titleUnlocked, { icon = sticky.icon, title = sticky.text })) > 0,
		"Sticky Fingers too"
	)
	AchievementService.check(a)
	check(count(toasts(ALICE), unlocked) == 1, "an unlock toasts once")

	send(alice, "EquipStyle", "title", "masterThief")
	check(a.data.flags.title_masterThief == true, "she wears Master Thief (the flag title_masterThief)")
	check(alice:GetAttribute("Title") == "masterThief", "everyone can read it (the Title attribute; chat shows it)")
	local tag = tags(alice)[1]
	check(tag ~= nil and tag:IsA("BillboardGui"), "a nametag is on her head")
	if tag then
		check(tag.Title.Text == `{masterThief.icon} {masterThief.text}`, `it reads "{tag.Title.Text}"`)
		check(same(tag.Title.TextColor3, UiTheme.color(masterThief.color)), "in the title's colour")
		check(tag.PlayerToHideFrom == alice and tag.Enabled, "Bob sees it; only she doesn't (like Roblox's names)")
		check(tag.AlwaysOnTop and tag.MaxDistance == Titles.nametag.maxDistance, "readable, hidden far away")
	end
	sync = lastSync(ALICE)
	check(sync ~= nil and sync.title == "masterThief", "and her dialog shows it worn")

	send(alice, "EquipStyle", "title", "stickyFingers")
	check(
		table.concat(flagsWith(a.data.flags, "title_"), ",") == "title_stickyFingers",
		"another title replaces it: one at a time"
	)
	local now = tags(alice)
	check(#now == 1 and now[1].Title.Text == `{sticky.icon} {sticky.text}`, "one nametag, with the new title")

	-- Hidden while carrying (the loot on her head, THIEF! over it), back after
	chat(alice, "/noshield")
	EconomyService.giveCreature(b, "pizza_pup", nil)
	local carry = grab(alice, bob, b.data.creatures[1].podium)
	check(carry ~= nil, "Alice grabs Bob's Snackling")
	check(#tags(alice) == 1 and not tags(alice)[1].Enabled, "her title hides while she carries it")
	StealService.cancel(a, "timeout")
	task.wait(0.1)
	check(a.carry == nil and tags(alice)[1].Enabled, "and shows again when the carry ends")

	-- A new character gets it too
	Sim.spawnCharacter(alice, PlotService.refs(a.plot).spawnCFrame.Position)
	task.wait(0.3)
	check(#tags(alice) == 1, "her new character wears the title too")

	send(alice, "EquipStyle", "title", "")
	check(#flagsWith(a.data.flags, "title_") == 0 and alice:GetAttribute("Title") == "", "No title takes it off")
	check(#tags(alice) == 0, "and the nametag goes")

	-- A save with more than one title, an unknown one and a locked one is repaired on join, with no toasts again.
	send(alice, "EquipStyle", "title", "masterThief")
	leave(alice)
	local save = MockProfileStore.saves[`Player_{ALICE}`]
	save.flags.title_mvp = true -- locked
	save.flags.title_noSuchTitle = true
	save.flags.title_stickyFingers = true
	local before = #toasts(ALICE)
	alice = join(ALICE, "Alice")
	a = sessionOf(alice)
	check(
		table.concat(flagsWith(a.data.flags, "title_"), ",") == "title_stickyFingers",
		"a save wearing four titles keeps one: the first unlocked in the list"
	)
	check(alice:GetAttribute("Title") == "stickyFingers" and #tags(alice) == 1, "and wears it")
	AchievementService.check(a)
	local again = 0
	for index = before + 1, #toasts(ALICE) do
		if string.find(toasts(ALICE)[index], "New title unlocked", 1, true) then
			again += 1
		end
	end
	check(again == 0, "titles unlocked before don't toast again")

	-- Base skins --------------------------------------------------------------------------------------------------------
	local plot = a.plot
	local refs = PlotService.refs(plot)
	local classic = looks(plot)
	check(refs.model:GetAttribute("Skin") == Skins.default, "a base starts Classic")
	send(alice, "EquipStyle", "skin", "diamond")
	check(#flagsWith(a.data.flags, "skin_") == 0 and equal(looks(plot), classic), "a locked skin is refused")

	a.data.snackdex.tiers.Common = true -- a Snackdex tier completed
	AchievementService.check(a)
	local mint = StyleRules.skinById(Skins, "mintChip")
	local mintToast = Format.template(Theme.text.skinUnlocked, { icon = mint.icon, skin = mint.name })
	check(indexOf(toasts(ALICE), mintToast) > 0, `"{mintToast}" toasts`)
	send(alice, "EquipStyle", "skin", "mintChip")
	local look = skinLook("mintChip")
	check(a.data.flags.skin_mintChip == true, "she uses Mint Chip (the flag skin_mintChip)")
	check(refs.model:GetAttribute("Skin") == "mintChip", "her plot says so (the Skin attribute)")
	local tile = refs.tiles[1]
	local expected = look.tiles[StyleRules.tileIndex(tile.row, tile.side, #look.tiles)]
	check(same(tile.part.Color, UiTheme.color(expected)), "its floor tiles take the skin's colours")
	check(same(refs.rug.Color, UiTheme.color(look.rug)), "and the rug")
	check(
		same(refs.wallTrims[1].Color, UiTheme.color(look.trim)) and same(refs.caps[1].Color, UiTheme.color(look.trim)),
		"and the trims (she isn't VIP: the caps too)"
	)
	check(refs.walls[1].Color == refs.accent, "the walls keep the plot's colour")
	local podiumBefore = refs.podiums[1].base.Color
	check(refs.lockButton.Color == UiTheme.world("lockButton"), "the lock button keeps its colour")
	local painted = looks(plot)
	chat(alice, "/map volcano")
	check(equal(looks(plot), painted), "a map change doesn't repaint it")
	check(refs.podiums[1].base.Color == podiumBefore, "nor the podiums")

	-- VIP's gold trim: all round on Classic, the corner caps under a skin
	local bobRefs = PlotService.refs(b.plot)
	local gold = UiTheme.world("vipTrim")
	check(
		same(bobRefs.wallTrims[1].Color, gold) and same(bobRefs.caps[1].Color, gold),
		"Bob is VIP: his Classic base is trimmed in gold"
	)
	b.data.rebirths = 2
	AchievementService.check(b)
	send(bob, "EquipStyle", "skin", "licoriceNight")
	local licorice = skinLook("licoriceNight")
	check(b.data.flags.skin_licoriceNight == true, "two rebirths: he uses Licorice Night")
	check(
		same(bobRefs.wallTrims[1].Color, UiTheme.color(licorice.trim)) and same(bobRefs.caps[1].Color, gold),
		"its trim on his walls, and his VIP gold caps stay"
	)

	-- The rainbow one, tagged for every client to animate
	local carol = join(CAROL, "Carol")
	local c = sessionOf(carol)
	Sim.fireServer(carol, "SkipTutorial")
	chat(carol, "/style all")
	send(carol, "EquipStyle", "skin", "rainbowSwirl")
	local carolRefs = PlotService.refs(c.plot)
	local tagged, offsets = 0, {}
	for _, trim in carolRefs.wallTrims do
		if CollectionService:HasTag(trim, CreatureVisuals.RAINBOW_TAG) then
			tagged += 1
			offsets[trim:GetAttribute("HueOffset")] = true
		end
	end
	for _, cap in carolRefs.caps do
		if CollectionService:HasTag(cap, CreatureVisuals.RAINBOW_TAG) then
			tagged += 1
		end
	end
	local distinct = 0
	for _ in offsets do
		distinct += 1
	end
	check(c.data.flags.skin_rainbowSwirl == true, "/style all (Studio): Carol uses Rainbow Swirl")
	check(
		tagged == #carolRefs.wallTrims + #carolRefs.caps and distinct == #carolRefs.wallTrims,
		`its trims are tagged to cycle on clients, each a different hue ({tagged})`
	)
	send(carol, "EquipStyle", "skin", "classic")
	local stillTagged = 0
	for _, trim in carolRefs.wallTrims do
		if CollectionService:HasTag(trim, CreatureVisuals.RAINBOW_TAG) then
			stillTagged += 1
		end
	end
	local white = UiTheme.world("wall")
	check(stillTagged == 0, "back to Classic, the tags go")
	check(
		same(carolRefs.wallTrims[1].Color, white) and same(carolRefs.wallTrims[1]:GetAttribute("RestColor"), white),
		"and clients put the plain trim back (RestColor)"
	)
	check(#flagsWith(c.data.flags, "skin_") == 0, "Classic needs no flag")
	send(carol, "EquipStyle", "skin", "diamond")
	chat(carol, "/style off")
	check(
		#flagsWith(c.data.flags, "skin_") == 0 and carolRefs.model:GetAttribute("Skin") == Skins.default,
		"/style off: a skin she never earned comes off"
	)

	-- Leaving resets the plot; coming back puts the skin on again
	leave(alice)
	check(equal(looks(plot), classic), "when Alice leaves, her plot goes back to Classic")
	check(refs.model:GetAttribute("Skin") == Skins.default, "Skin attribute too")
	check(MockProfileStore.saves[`Player_{ALICE}`].flags.skin_mintChip == true, "her skin is in her save")
	alice = join(ALICE, "Alice")
	a = sessionOf(alice)
	check(
		PlotService.refs(a.plot).model:GetAttribute("Skin") == "mintChip"
			and same(PlotService.refs(a.plot).rug.Color, UiTheme.color(look.rug)),
		"and back again, so is Mint Chip"
	)
	leave(carol)
	leave(dan)
	leave(eve)
end

local passed, problem = pcall(scenario :: () -> ...any)
if not passed then
	print(`  FAIL the scenario stopped: {problem}`)
	table.insert(failures, tostring(problem))
end
finish()
