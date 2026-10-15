--!strict
--[[
	Titles and base skins (Config/Titles, Config/Skins; rules in Logic/StyleRules), picked in Settings ▸ Style.

	* Unlocking reads the save (achievements' ach_<id> flags and goals, rebirths, Snackdex tiers): nothing is bought and
	  nothing new is saved for it. After every achievement check (AchievementService.onChecked: within a second of
	  anything a goal counts, and every 10 s for everyone; after the achievement's own toast) whatever was newly
	  unlocked gets a toast, "New title unlocked: Master Thief — equip it in Settings ▸ Style". What a player had
	  unlocked when they joined is the starting point: no toasts for it.
	* Wearing is a flag, title_<id> and skin_<id>, one of each at most. On join the flags are repaired (extras, unknown
	  ids and locked ones cleared, StyleRules.normalize); EquipStyle(kind, id) wears another after checking the kind,
	  that the id is a config key (or "" for none) and that the player has it unlocked. Nothing yields in between.
	* What is worn shows at once: the title as the player attribute "Title" (the chat tag reads it) and the nametag over
	  their head (Nametags, also after a respawn), the skin on their plot (PlotService.setSkin) from the moment it is
	  theirs; PlotService.release puts the Classic look back when they leave.
	* GetStyle → StyleSync: what the Style dialog shows (what is worn, what is unlocked, progress); an equip answers with
	  a new StyleSync.
	* Analytics: style_equipped (01 = "title" | "skin", 02 = the id, "" for none). Ids are config keys: bounded.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Achievements = require(ReplicatedStorage.Shared.Config.Achievements)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Skins = require(ReplicatedStorage.Shared.Config.Skins)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local Titles = require(ReplicatedStorage.Shared.Config.Titles)
local GameData = require(ReplicatedStorage.Shared.GameData)
local AchievementRules = require(ReplicatedStorage.Shared.Logic.AchievementRules)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local Guard = require(ReplicatedStorage.Shared.Logic.Guard)
local StyleRules = require(ReplicatedStorage.Shared.Logic.StyleRules)
local Analytics = require(script.Parent.Analytics)
local Nametags = require(script.Parent.Nametags)
local PlotService = require(script.Parent.PlotService)
local Remotes = require(script.Parent.Remotes)
local Sessions = require(script.Parent.Sessions)
local TutorialService = require(script.Parent.TutorialService)

type Session = Sessions.Session

local StyleService = {}

local catalog = GameData.catalog
local achievements = StyleRules.achievementsById(Achievements)
local TITLES = StyleRules.titleEntries(Titles)
local SKINS = StyleRules.skinEntries(Skins)
local KINDS = { "title", "skin" }

-- Per session, runtime only: what was unlocked at the last check ("title:<id>", "skin:<id>"), and Studio's /style all.
type State = { known: { [string]: boolean }, all: boolean }
local states: { [Session]: State } = setmetatable({}, { __mode = "k" }) :: any

local function unlocks(session: Session): StyleRules.Unlocks
	local state = states[session]
	return {
		ctx = AchievementRules.context(session.data, catalog.creatures, catalog.rarities),
		flags = session.data.flags,
		achievements = achievements,
		rarities = catalog.rarities,
		all = state ~= nil and state.all,
	}
end

local function unlockedNow(session: Session): ({ [string]: boolean }, { [string]: boolean })
	local u = unlocks(session)
	return StyleRules.unlocked(TITLES, u), StyleRules.unlocked(SKINS, u)
end

-- Puts on what the save says: the title (attribute and nametag) and the skin (plot).
local function apply(session: Session)
	local flags = session.data.flags
	session.player:SetAttribute(Nametags.ATTRIBUTE, StyleRules.wornTitle(flags, Titles))
	Nametags.refresh(session)
	if session.plot ~= 0 then
		PlotService.setSkin(session.plot, StyleRules.wornSkin(flags, Skins))
	end
end

-- Repairs the worn flags against what is unlocked now (one of each, known ids, unlocked) and puts them on.
local function normalizeAndApply(session: Session)
	local titles, skins = unlockedNow(session)
	local flags = session.data.flags
	StyleRules.normalize(flags, StyleRules.TITLE_PREFIX, TITLES, titles)
	StyleRules.normalize(flags, StyleRules.SKIN_PREFIX, SKINS, skins, Skins.default)
	apply(session)
end

local function sync(session: Session)
	Remotes.fire(session.player, "StyleSync", StyleRules.view(Titles, Skins, unlocks(session)))
end

-- Join hook (after the plot is assigned): repairs the worn flags, remembers what is already unlocked (no toasts for
-- that) and puts the title and skin on.
function StyleService.onJoined(session: Session)
	local titles, skins = unlockedNow(session)
	local known: { [string]: boolean } = {}
	for id in titles do
		known["title:" .. id] = true
	end
	for id in skins do
		known["skin:" .. id] = true
	end
	states[session] = { known = known, all = false }
	normalizeAndApply(session)
end

-- A new character (the first one, or a respawn): its nametag, once its head is there.
function StyleService.onCharacter(session: Session, character: Model)
	character:WaitForChild("Head", 10)
	if session.player.Character == character then
		Nametags.refresh(session)
	end
end

-- After an achievement check (AchievementService.onChecked): a toast for every title or skin unlocked since the last
-- (held during the first-time tutorial and a few seconds after it, like the achievements': TutorialService).
function StyleService.check(session: Session)
	local state = states[session]
	if state == nil or not session.ready then
		return
	end
	local titles, skins = unlockedNow(session)
	for _, def in Titles.list do
		local key = "title:" .. def.id
		if titles[def.id] and not state.known[key] then
			state.known[key] = true
			TutorialService.notifyWhenQuiet(
				session,
				Format.template(Theme.text.titleUnlocked, { icon = def.icon, title = def.text }),
				"success"
			)
		end
	end
	for _, def in Skins.list do
		local key = "skin:" .. def.id
		if skins[def.id] and not state.known[key] then
			state.known[key] = true
			TutorialService.notifyWhenQuiet(
				session,
				Format.template(Theme.text.skinUnlocked, { icon = def.icon, skin = def.name }),
				"success"
			)
		end
	end
end

local function onGet(player: Player)
	local session = Sessions.get(player)
	if session and session.ready then
		sync(session)
	end
end

-- EquipStyle(kind, id): wear title / skin `id` ("" = no title, or the default skin).
local function onEquip(player: Player, rawKind: unknown, rawId: unknown)
	local session = Sessions.get(player)
	if session == nil or not session.ready then
		return
	end
	local kind = Guard.oneOf(rawKind, KINDS)
	if kind == nil or type(rawId) ~= "string" or #rawId > StyleRules.ID_LENGTH then
		return
	end
	local id = rawId :: string
	local titles, skins = unlockedNow(session)
	local styleKind: StyleRules.Kind = if kind == "title" then "title" else "skin"
	if not StyleRules.canEquip(styleKind, id, Titles, Skins, if kind == "title" then titles else skins) then
		sync(session) -- the dialog shows the truth again
		return
	end
	local flags = session.data.flags
	if kind == "title" then
		StyleRules.equip(flags, StyleRules.TITLE_PREFIX, id)
	else
		StyleRules.equip(flags, StyleRules.SKIN_PREFIX, if id == Skins.default then "" else id)
	end
	apply(session)
	sync(session)
	Analytics.custom(session, "style_equipped", nil, { kind, id })
end

-- Studio /style all | off: everything counts as unlocked for this player this session (not saved), or not any more
-- (what they then wear but haven't unlocked comes off).
function StyleService.setUnlockAll(session: Session, all: boolean)
	local state = states[session]
	if state == nil then
		return
	end
	state.all = all
	local titles, skins = unlockedNow(session)
	for id in titles do
		state.known["title:" .. id] = true
	end
	for id in skins do
		state.known["skin:" .. id] = true
	end
	normalizeAndApply(session)
	sync(session)
end

function StyleService.start()
	local limits: StyleRules.UnlockLimits = {
		achievements = achievements,
		maxRebirths = Economy.rebirth.maxRebirths,
		tiers = #catalog.rarityList,
	}
	for _, problem in StyleRules.validateTitles(Titles, limits) do
		warn(`[Style] config problem: {problem}`)
	end
	for _, problem in StyleRules.validateSkins(Skins, limits, Theme.world.collectPad) do
		warn(`[Style] config problem: {problem}`)
	end
	Remotes.onIntent("GetStyle", onGet)
	Remotes.onIntent("EquipStyle", onEquip)
end

return StyleService
