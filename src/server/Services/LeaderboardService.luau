--!strict
--[[
	Global leaderboards (OrderedDataStore): best cash/sec and total steals. Players' values are written every
	refresh (only when changed) and when they leave; the top 10 are drawn on the two boards flanking the archway onto
	the spawn plaza (rank badges, names, values).
	All DataStore calls are pcall'd: in Studio without API access the boards simply say so.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Gameplay = require(ReplicatedStorage.Shared.Config.Gameplay)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local MapBuilder = require(script.Parent.MapBuilder)
local Sessions = require(script.Parent.Sessions)

type Session = Sessions.Session

type Row = { frame: Frame, rank: TextLabel, name: TextLabel, value: TextLabel }

type Board = {
	name: string,
	store: OrderedDataStore?,
	value: (session: Session) -> number,
	format: (value: number) -> string,
	rows: { Row },
	status: TextLabel,
	lastWritten: { [number]: number },
}

local TOP_N = 10
local MAX_VALUE = 2 ^ 53

local LeaderboardService = {}

local boards: { Board } = {}
local nameCache: { [number]: string } = {}

local function getStore(name: string): OrderedDataStore?
	local ok, store = pcall(function(): OrderedDataStore
		return DataStoreService:GetOrderedDataStore(name)
	end)
	return if ok then store else nil
end

local function nameOf(userId: number): string
	local cached = nameCache[userId]
	if cached then
		return cached
	end
	local online = Players:GetPlayerByUserId(userId)
	if online then
		nameCache[userId] = online.DisplayName
		return online.DisplayName
	end
	local ok, name = pcall(function(): string
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local result = if ok then name else `#{userId}`
	nameCache[userId] = result
	return result
end

local MEDALS = { "#FFD23F", "#C8CAD8", "#E0955A" } -- gold, silver, bronze rank badges

local function boardLabel(props: { [string]: any }): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.FontFace = UiTheme.displayFont
	label.TextScaled = true
	label.TextColor3 = UiTheme.palette("text")
	for key, value in props do
		(label :: any)[key] = value
	end
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = UiTheme.palette("stroke")
	stroke.Parent = label
	return label
end

local function corner(parent: Instance, radius: UDim)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = parent
end

-- The board face: a title bar, a status line (no DataStore access / empty board) and ten rows with a rank badge, the
-- player's name and their value.
local function buildBoard(part: BasePart, title: string): ({ Row }, TextLabel)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Leaderboard"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0
	gui.Parent = part

	local titleBar = Instance.new("Frame")
	titleBar.Name = "TitleBar"
	titleBar.Size = UDim2.new(1, -24, 0, 86)
	titleBar.Position = UDim2.fromOffset(12, 12)
	titleBar.BackgroundColor3 = UiTheme.palette("primary")
	titleBar.Parent = gui
	corner(titleBar, UDim.new(0, 18))
	boardLabel({
		Name = "Title",
		Text = title,
		Size = UDim2.new(1, -24, 1, -16),
		Position = UDim2.fromOffset(12, 8),
		Parent = titleBar,
	})

	local status = boardLabel({
		Name = "Status",
		Text = "",
		TextColor3 = UiTheme.palette("textDim"),
		Size = UDim2.new(1, -40, 0, 32),
		Position = UDim2.fromOffset(20, 104),
		Parent = gui,
	})

	local list = Instance.new("Frame")
	list.Name = "Rows"
	list.BackgroundTransparency = 1
	list.Position = UDim2.fromOffset(16, 142)
	list.Size = UDim2.new(1, -32, 1, -154)
	list.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 5)
	layout.Parent = list

	local rows: { Row } = {}
	for i = 1, TOP_N do
		local frame = Instance.new("Frame")
		frame.Name = `Row{i}`
		frame.LayoutOrder = i
		frame.Size = UDim2.new(1, 0, 0.1, -5)
		frame.BackgroundColor3 = UiTheme.palette("panelLight")
		frame.BackgroundTransparency = if i % 2 == 0 then 0.55 else 0.2
		frame.Visible = false
		frame.Parent = list
		corner(frame, UDim.new(0, 12))
		local badge = Instance.new("Frame")
		badge.Name = "Badge"
		badge.AnchorPoint = Vector2.new(0, 0.5)
		badge.Position = UDim2.new(0, 6, 0.5, 0)
		badge.Size = UDim2.new(0, 40, 0.8, 0)
		badge.BackgroundColor3 = if MEDALS[i] then UiTheme.color(MEDALS[i]) else UiTheme.palette("panel")
		badge.Parent = frame
		corner(badge, UDim.new(0.5, 0))
		local rank = boardLabel({
			Name = "Rank",
			Text = tostring(i),
			Size = UDim2.fromScale(1, 0.8),
			Position = UDim2.fromScale(0, 0.1),
			Parent = badge,
		})
		local name = boardLabel({
			Name = "Name",
			Text = "",
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(0.58, -56, 0.72, 0),
			Position = UDim2.new(0, 54, 0.14, 0),
			Parent = frame,
		})
		local value = boardLabel({
			Name = "Value",
			Text = "",
			TextColor3 = UiTheme.palette("cash"),
			TextXAlignment = Enum.TextXAlignment.Right,
			Size = UDim2.new(0.42, -12, 0.72, 0),
			Position = UDim2.fromScale(0.58, 0.14),
			Parent = frame,
		})
		table.insert(rows, { frame = frame, rank = rank, name = name, value = value })
	end
	return rows, status
end

local function write(board: Board, session: Session)
	local store = board.store
	if store == nil then
		return
	end
	local value = math.clamp(math.floor(board.value(session)), 0, MAX_VALUE)
	if board.lastWritten[session.userId] == value or value <= 0 then
		return
	end
	local ok, err = pcall(function()
		store:SetAsync(tostring(session.userId), value)
	end)
	if ok then
		board.lastWritten[session.userId] = value
	else
		warn(`[Leaderboards] write failed ({board.name}): {err}`)
	end
end

local function refresh(board: Board)
	local store = board.store
	if store == nil then
		board.status.Text = Theme.text.leaderboardNoAccess
		return
	end
	local ok, pages = pcall(function(): DataStorePages
		return store:GetSortedAsync(false, TOP_N)
	end)
	if not ok then
		board.status.Text = Theme.text.leaderboardNoAccess
		return
	end
	local entries = pages:GetCurrentPage()
	board.status.Text = if #entries == 0 then Theme.text.leaderboardEmpty else ""
	for i = 1, TOP_N do
		local entry = entries[i]
		local row = board.rows[i]
		row.frame.Visible = entry ~= nil
		if entry then
			local userId = tonumber(entry.key) or 0
			row.name.Text = nameOf(userId)
			row.value.Text = board.format(entry.value)
		end
	end
end

function LeaderboardService.writePlayer(session: Session)
	for _, board in boards do
		write(board, session)
	end
end

function LeaderboardService.start(world: MapBuilder.World)
	local cashRows, cashStatus = buildBoard(world.leaderboards.cash, Theme.text.leaderboardCash)
	local stealRows, stealStatus = buildBoard(world.leaderboards.steals, Theme.text.leaderboardSteals)
	table.insert(boards, {
		name = "CashPerSecond",
		store = getStore("LB_CashPerSecond_v1"),
		value = function(session: Session): number
			return session.data.stats.bestCashPerSecond
		end,
		format = function(value: number): string
			return Format.cash(value, Theme.currencySymbol) .. "/s"
		end,
		rows = cashRows,
		status = cashStatus,
		lastWritten = {},
	})
	table.insert(boards, {
		name = "Steals",
		store = getStore("LB_Steals_v1"),
		value = function(session: Session): number
			return session.data.stats.steals
		end,
		format = function(value: number): string
			return Format.number(value)
		end,
		rows = stealRows,
		status = stealStatus,
		lastWritten = {},
	})

	task.spawn(function()
		while true do
			for _, session in Sessions.all() do
				LeaderboardService.writePlayer(session)
			end
			for _, board in boards do
				refresh(board)
			end
			task.wait(Gameplay.leaderboardRefreshSeconds)
		end
	end)
end

return LeaderboardService
