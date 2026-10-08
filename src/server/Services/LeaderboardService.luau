--!strict
--[[
	Global leaderboards (OrderedDataStore): best cash/sec and total steals. Players' values are written every
	refresh (only when changed) and when they leave; the top 10 are drawn on the two boards next to the belt.
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

type Board = {
	name: string,
	store: OrderedDataStore?,
	value: (session: Session) -> number,
	format: (value: number) -> string,
	rows: { TextLabel },
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

local function buildBoard(part: BasePart, title: string): ({ TextLabel }, TextLabel)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0
	gui.Parent = part
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = gui
	local function label(order: number, text: string, color: Color3, height: number): TextLabel
		local l = Instance.new("TextLabel")
		l.LayoutOrder = order
		l.Size = UDim2.fromScale(0.94, height)
		l.BackgroundTransparency = 1
		l.FontFace = UiTheme.displayFont
		l.TextScaled = true
		l.TextColor3 = color
		l.Text = text
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.Parent = gui
		return l
	end
	local titleLabel = label(0, title, UiTheme.palette("gold"), 0.12)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Center
	local status = label(1, "", UiTheme.palette("textDim"), 0.05)
	status.TextXAlignment = Enum.TextXAlignment.Center
	local rows: { TextLabel } = {}
	for i = 1, TOP_N do
		table.insert(rows, label(1 + i, "", UiTheme.palette("text"), 0.08))
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
		board.status.Text = "Leaderboards need DataStore access"
		return
	end
	local ok, pages = pcall(function(): DataStorePages
		return store:GetSortedAsync(false, TOP_N)
	end)
	if not ok then
		board.status.Text = "Leaderboards need DataStore access"
		return
	end
	board.status.Text = ""
	local entries = pages:GetCurrentPage()
	for i = 1, TOP_N do
		local entry = entries[i]
		local row = board.rows[i]
		if entry then
			local userId = tonumber(entry.key) or 0
			row.Text = `{i}. {nameOf(userId)}   {board.format(entry.value)}`
		else
			row.Text = ""
		end
	end
end

function LeaderboardService.writePlayer(session: Session)
	for _, board in boards do
		write(board, session)
	end
end

function LeaderboardService.start(world: MapBuilder.World)
	local cashRows, cashStatus = buildBoard(world.leaderboards.cash, "Top Cash/sec")
	local stealRows, stealStatus = buildBoard(world.leaderboards.steals, "Top Thieves")
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
