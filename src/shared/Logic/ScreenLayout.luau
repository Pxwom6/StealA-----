--!strict
--[[
	HUD layout around Roblox's own UI in the top-right corner. On computers (and tablets) Roblox shows its player list
	there, drawn above every game UI, so the settings gear and the tutorial banner's Skip button must stay left of it.
	On phones it starts hidden (it opens from the Roblox menu), so the corner is free. Pure: no Roblox APIs; the client
	passes in the device facts.

	Widths are in whatever unit the caller uses consistently (the client converts pixels to UI units).
]]

local ScreenLayout = {}

-- Estimated width of Roblox's player list in pixels: the names column plus one column per leaderstat, and the gap to
-- the screen edge. Roblox does not expose its real size, so this errs on the wide side.
ScreenLayout.PLAYER_LIST = { base = 190, perStat = 80, max = 480, margin = 8 }

-- Pixels the player list takes from the right edge of the screen: 0 when it is switched off or on a phone (a
-- touch-only device whose short side is under 500 px).
function ScreenLayout.playerListWidth(
	enabled: boolean,
	touchOnly: boolean,
	viewportX: number,
	viewportY: number,
	statCount: number
): number
	if not enabled then
		return 0
	end
	if touchOnly and math.min(viewportX, viewportY) < 500 then
		return 0
	end
	local list = ScreenLayout.PLAYER_LIST
	return math.min(list.max, list.base + list.perStat * math.max(0, statCount)) + list.margin
end

-- Left edge of the top-right gear button: in the corner, or just left of the player list when it shows. If that
-- would put it over the centred top stack (a narrow window), it stays in the corner.
function ScreenLayout.gearX(
	screenWidth: number,
	playerList: number,
	gearSize: number,
	margin: number,
	stackHalfWidth: number
): number
	local corner = screenWidth - margin - gearSize
	if playerList <= 0 then
		return corner
	end
	local beside = corner - playerList
	if beside >= screenWidth / 2 + stackHalfWidth + margin then
		return beside
	end
	return corner
end

-- The x the tutorial banner's right edge must stay left of: the TAG button area, or the player list's left edge.
function ScreenLayout.bannerRightLimit(actionAreaX: number, screenWidth: number, playerList: number): number
	return math.min(actionAreaX, screenWidth - playerList)
end

-- True when even the narrowest banner (centred on centerX) would run under the player list: the tutorial then hides
-- the player list while its banner shows, so Skip is always reachable.
function ScreenLayout.bannerNeedsPlayerListHidden(
	centerX: number,
	minWidth: number,
	screenWidth: number,
	playerList: number,
	gap: number
): boolean
	if playerList <= 0 then
		return false
	end
	return centerX + minWidth / 2 > screenWidth - playerList - gap
end

return ScreenLayout
