--!strict
--[[
	Studio-only Snackling gallery (DevCommands: `/gallery [mutationId]`, `/gallery off`): every Snackling on labelled
	terraces, one row per rarity (Common nearest, the Halloween event Snacklings last), so all of them can be checked
	and screenshotted at once. Optionally every one gets the same mutation (e.g. `/gallery rainbow`).

	It stands on the open grass behind the north row of bases (outside every plot, away from the belt and the lobby):
	rows climb a little so the back ones are visible over the front ones. The models are real CreatureVisuals models,
	so they idle on clients like Snacklings on podiums.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Gameplay = require(ReplicatedStorage.Shared.Config.Gameplay)
local CreatureVisuals = require(ReplicatedStorage.Shared.CreatureVisuals)
local GameData = require(ReplicatedStorage.Shared.GameData)
local Types = require(ReplicatedStorage.Shared.Types)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)

local DevGallery = {}

local FOLDER_NAME = "SnacklingGallery"
local SPACING = 8 -- studs between Snacklings in a row
local ROW_GAP = 16 -- studs between rows
local STEP_UP = 1.5 -- each row stands this much higher than the one in front
local BASE_HEIGHT = 0.4
local CLEARANCE = 26 -- studs between the back walls of the north bases and the first row

local MAP = Gameplay.map

local function anchoredPart(props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = true
	part.CanTouch = false
	part.CanQuery = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		(part :: any)[key] = value
	end
	return part
end

local function label(parent: Instance, text: string, color: Color3, top: number, height: number)
	local textLabel = Instance.new("TextLabel")
	textLabel.BackgroundTransparency = 1
	textLabel.Position = UDim2.fromScale(0, top)
	textLabel.Size = UDim2.fromScale(1, height)
	textLabel.FontFace = UiTheme.displayFont
	textLabel.TextScaled = true
	textLabel.Text = text
	textLabel.TextColor3 = color
	textLabel.Parent = parent
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = UiTheme.palette("stroke")
	stroke.Parent = textLabel
end

local function billboard(adornee: BasePart, size: UDim2, offset: number): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Size = size
	gui.StudsOffsetWorldSpace = Vector3.new(0, offset, 0)
	gui.MaxDistance = 260
	gui.LightInfluence = 0
	gui.Adornee = adornee
	gui.Parent = adornee
	return gui
end

-- The rows: one per rarity (regular Snacklings, cheapest first), then the event Snacklings.
type Row = { title: string, color: Color3, creatures: { Types.CreatureDef } }

local function rows(): { Row }
	local list: { Row } = {}
	local events: { Types.CreatureDef } = {}
	for _, rarity in GameData.catalog.rarityList do
		local regular: { Types.CreatureDef } = {}
		for _, def in GameData.catalog.byRarity[rarity.id] do
			if def.eventId then
				table.insert(events, def)
			else
				table.insert(regular, def)
			end
		end
		table.sort(regular, function(a: Types.CreatureDef, b: Types.CreatureDef): boolean
			return a.price < b.price
		end)
		table.insert(list, {
			title = `{string.upper(rarity.displayName)} ({#regular})`,
			color = UiTheme.color(rarity.color),
			creatures = regular,
		})
	end
	if #events > 0 then
		table.insert(list, { title = `EVENT ({#events})`, color = UiTheme.palette("event"), creatures = events })
	end
	return list
end

function DevGallery.clear()
	local existing = workspace:FindFirstChild(FOLDER_NAME)
	if existing then
		existing:Destroy()
	end
end

-- Builds the gallery (replacing an old one) and returns where to stand to see it all, and how many Snacklings it has.
function DevGallery.build(mutation: Types.MutationDef?): (CFrame, number)
	DevGallery.clear()
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME

	local firstZ = MAP.walkwayWidth + MAP.plotDepth + CLEARANCE
	local count = 0
	for index, row in rows() do
		local k = index - 1
		local z = firstZ + k * ROW_GAP
		local top = BASE_HEIGHT + k * STEP_UP
		local width = math.max(#row.creatures, 1) * SPACING + SPACING
		anchoredPart({
			Name = "Terrace",
			Size = Vector3.new(width + SPACING, top, ROW_GAP),
			CFrame = CFrame.new(0, top / 2, z),
			Color = row.color:Lerp(Color3.new(1, 1, 1), 0.72),
			Parent = folder,
		})
		local sign = anchoredPart({
			Name = "RowTitle",
			Size = Vector3.new(1, 1, 1),
			CFrame = CFrame.new(-width / 2, top + 5, z),
			Transparency = 1,
			CanCollide = false,
			Parent = folder,
		})
		label(billboard(sign, UDim2.fromOffset(220, 46), 0), row.title, row.color, 0, 1)

		for i, def in row.creatures do
			local rarity = GameData.catalog.rarities[def.rarity]
			local model = CreatureVisuals.build(def, rarity, { anchored = true, mutation = mutation })
			local x = (i - (#row.creatures + 1) / 2) * SPACING
			model:PivotTo(CFrame.new(x, top + 0.1, z))
			local root = model.PrimaryPart :: BasePart
			local gui = billboard(root, UDim2.fromOffset(170, 50), CreatureVisuals.height(model) + 1.6)
			label(gui, GameData.displayName(def, if mutation then mutation.id else nil), Color3.new(1, 1, 1), 0, 0.58)
			label(gui, string.upper(rarity.displayName), UiTheme.color(rarity.color), 0.58, 0.42)
			model.Parent = folder
			count += 1
		end
	end
	folder.Parent = workspace

	local eye = Vector3.new(0, 6, firstZ - 22)
	return CFrame.lookAt(eye, Vector3.new(0, 4, firstZ + 2 * ROW_GAP)), count
end

return DevGallery
