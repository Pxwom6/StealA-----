--!strict
--[[
	What's New (Config/Updates; rules in Logic/UpdateRules).

	* The card: on join (after TutorialService has decided whether the tutorial runs), a returning player who hasn't
	  seen the newest update is sent WhatsNew once their client is ready. The client opens the card only when nothing
	  is in the way (no other dialog, not carrying, no tutorial: WhatsNewController) and then answers SeenNews(number),
	  which sets the flag news_<number> (older news_ flags go). A card that never got shown (the player left first)
	  comes again next time. A first session (a save that was never saved before) or a player still in the tutorial
	  counts the update as seen without a card: new players get the tutorial instead.
	* The board on the spawn plaza (MapBuilder builds it outside the Scenery folder): the newest update's title and
	  highlights, written once at start (Logic/NewsLayout places them).
	* Analytics: news_seen (value = the update's number).

	In Studio without API access every session is a first one (nothing is saved), so the card never comes by itself
	there: /news shows it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local Updates = require(ReplicatedStorage.Shared.Config.Updates)
local Types = require(ReplicatedStorage.Shared.Types)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local Guard = require(ReplicatedStorage.Shared.Logic.Guard)
local NewsLayout = require(ReplicatedStorage.Shared.Logic.NewsLayout)
local UpdateRules = require(ReplicatedStorage.Shared.Logic.UpdateRules)
local Analytics = require(script.Parent.Analytics)
local MapBuilder = require(script.Parent.MapBuilder)
local Remotes = require(script.Parent.Remotes)
local Sessions = require(script.Parent.Sessions)

type Session = Sessions.Session

local NewsService = {}

-- The update number each session's card is waiting to be seen for (runtime only).
local pending: { [Session]: number } = setmetatable({}, { __mode = "k" }) :: any

-- Join hook, after TutorialService.onJoined: show the card, count the update as seen, or nothing.
function NewsService.onJoined(session: Session)
	local latest = UpdateRules.latest(Updates)
	if latest == nil then
		return
	end
	local firstSession = session.lastSeenAtJoin <= 0
	local decision = UpdateRules.onJoin(session.data.flags, latest.number, firstSession, session.tutorial ~= nil)
	if decision == "markSeen" then
		UpdateRules.markSeen(session.data.flags, latest.number)
	elseif decision == "show" then
		pending[session] = latest.number
	end
end

-- Ready hook: the client is listening now.
function NewsService.onReady(session: Session)
	local number = pending[session]
	if number then
		Remotes.fire(session.player, "WhatsNew", { number = number })
	end
end

-- SeenNews(number): the card for update `number` was shown. Only the one this session is waiting for counts.
local function onSeen(player: Player, rawNumber: unknown)
	local session = Sessions.get(player)
	local number = Guard.integer(rawNumber, 1, 999999)
	if session == nil or number == nil or pending[session] ~= number then
		return
	end
	pending[session] = nil
	UpdateRules.markSeen(session.data.flags, number)
	Analytics.custom(session, "news_seen", number)
end

-- Studio /news: the newest update's card again, as if it had never been seen.
function NewsService.showAgain(session: Session)
	local latest = UpdateRules.latest(Updates)
	if latest == nil then
		return
	end
	session.data.flags[UpdateRules.flagKey(latest.number)] = nil
	pending[session] = latest.number
	Remotes.fire(session.player, "WhatsNew", { number = latest.number })
end

local function label(props: { [string]: any }, parent: Instance): TextLabel
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.FontFace = UiTheme.displayFont
	text.TextScaled = true
	text.TextColor3 = UiTheme.palette("text")
	for key, value in props do
		(text :: any)[key] = value
	end
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = UiTheme.palette("stroke")
	stroke.Parent = text
	text.Parent = parent
	return text
end

local function place(r: NewsLayout.Rect): (UDim2, UDim2)
	return UDim2.fromOffset(r.x, r.y), UDim2.fromOffset(r.w, r.h)
end

-- Writes `update` on the board's front: a header band, the title, a line per highlight, the number and date.
local function writeBoard(panel: BasePart, update: Types.UpdateDef)
	local B = NewsLayout.BOARD
	local gui = Instance.new("SurfaceGui")
	gui.Name = "WhatsNew"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = B.pixelsPerStud
	gui.LightInfluence = 0
	gui.Parent = panel
	local boxes = NewsLayout.boardBoxes(#update.highlights)
	local band = Instance.new("Frame")
	band.Name = "Header"
	band.Position, band.Size = place(boxes.header)
	band.BackgroundColor3 = UiTheme.palette("secondary")
	band.BorderSizePixel = 0
	band.Parent = gui
	label({ Name = "Label", Size = UDim2.fromScale(1, 1), Text = Theme.text.newsBoardHeader }, band)
	local position, size = place(boxes.title)
	label(
		{ Name = "Title", Position = position, Size = size, Text = update.title, TextColor3 = UiTheme.palette("gold") },
		gui
	)
	for i, line in update.highlights do
		position, size = place(boxes[`line{i}`])
		label({
			Name = `Line{i}`,
			Position = position,
			Size = size,
			Text = line,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, gui)
	end
	position, size = place(boxes.meta)
	label({
		Name = "Meta",
		Position = position,
		Size = size,
		Text = Format.template(Theme.text.whatsNewMeta, { number = update.number, date = update.date }),
		TextColor3 = UiTheme.palette("textDim"),
		FontFace = UiTheme.bodyFont,
	}, gui)
end

function NewsService.start(world: MapBuilder.World)
	for _, problem in UpdateRules.validate(Updates) do
		warn(`[News] config problem: {problem}`)
	end
	local latest = UpdateRules.latest(Updates)
	if latest then
		writeBoard(world.newsBoard, latest)
	end
	Remotes.onIntent("SeenNews", onSeen)
end

return NewsService
