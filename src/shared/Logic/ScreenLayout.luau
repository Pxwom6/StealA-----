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

-- The HUD's top-right row, in UI units: the settings gear (SettingsController) and, left of it, the Friends button
-- (SocialController). Both are square full touch targets just under Roblox's top bar.
ScreenLayout.CORNER = table.freeze({
	size = 44, -- gear and Friends button, like the tutorial's Skip
	margin = 8, -- from the screen edge, from the player list, and between the two buttons
	top = 4, -- the HUD screen already starts below Roblox's top bar
	stackHalfWidth = 125, -- the cash pill in the centre of the top stack is 250 wide: the row stays clear of it
})

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

-- Left edge of a button of `width` just left of the gear (at `gearX`, from gearX above), or nil when there is no room
-- there: it would reach the cash pill in the centre, or the gear sits in the corner under the player list (a narrow
-- window) so the button would too. The caller then puts it somewhere else (the Friends button: back in the top stack).
function ScreenLayout.besideGearX(
	screenWidth: number,
	playerList: number,
	gearX: number,
	width: number,
	margin: number,
	stackHalfWidth: number
): number?
	local x = gearX - margin - width
	if x < screenWidth / 2 + stackHalfWidth + margin then
		return nil
	end
	if playerList > 0 and x + width > screenWidth - playerList then
		return nil
	end
	return x
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
