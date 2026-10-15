--!strict
--[[
	How big a line of text comes out in a box: a pure model of Roblox's TextScaled (+ TextWrapped) with the real
	metrics of the game's display font, FredokaOne (advance widths read from FredokaOne-Regular.ttf, 1000 units per
	em; ascent 974 + descent 236 = 1.21 em per line). Used by tests and tools/layoutCheck.luau to prove HUD labels stay
	readable on phones (DECISIONS.md #44), and by the client to pick a toast's height.

	Sizes are em sizes in UI units (a phone at UI scale 0.85 shows 12 UI as about 10 px). Emoji come from Roblox's
	emoji font and are counted as 1.2 em (measured against the reviewer's numbers), anything else unknown as an
	average letter. Wrapping is greedy at spaces, like Roblox's; a word wider than the box does not fit.
]]

local TextFit = {}

TextFit.LINE_HEIGHT = 1.21 -- em per line
TextFit.MAX_SIZE = 100 -- Roblox's TextScaled maximum

local EMOJI = 1200 -- per mille of an em
local UNKNOWN = 573 -- an average lowercase letter

-- Advance widths (per mille of an em) of the printable ASCII range, code points 32 (space) to 126 (~).
-- stylua: ignore
local ASCII: { number } = {
	253, 267, 429, 749, 475, 838, 748, 208, 384, 384, 503, 527, 238, 433, 237, 526, -- space ! " # $ % & ' ( ) * + , - . /
	608, 407, 609, 608, 592, 530, 560, 561, 582, 560, -- 0-9
	238, 237, 627, 478, 627, 512, 908, -- : ; < = > ? @
	765, 646, 679, 704, 638, 637, 714, 699, 257, 549, 639, 587, 870, -- A-M
	720, 775, 632, 830, 631, 583, 731, 726, 783, 999, 741, 686, 643, -- N-Z
	348, 528, 348, 526, 826, 482, -- [ \ ] ^ _ `
	596, 592, 517, 598, 573, 450, 585, 605, 255, 252, 536, 327, 851, -- a-m
	606, 600, 582, 582, 457, 489, 449, 606, 638, 793, 567, 604, 586, -- n-z
	381, 217, 381, 651, -- { | } ~
}

-- Other characters the game's text uses.
local EXTRA: { [number]: number } = {
	[0x00B7] = 237, -- ·
	[0x00D7] = 521, -- ×
	[0x00E9] = 573, -- é
	[0x00B0] = 407, -- °
	[0x2013] = 561, -- –
	[0x2014] = 693, -- —
	[0x2018] = 237, -- ‘
	[0x2019] = 237, -- ’
	[0x201C] = 482, -- “
	[0x201D] = 482, -- ”
	[0x2026] = 911, -- …
}

-- Code points that take no room of their own (emoji variation selectors, joiners, skin tones).
local function zeroWidth(code: number): boolean
	return code == 0xFE0F or code == 0xFE0E or code == 0x200D or (code >= 0x1F3FB and code <= 0x1F3FF)
end

local function advance(code: number): number
	if code >= 32 and code <= 126 then
		return ASCII[code - 31]
	end
	local extra = EXTRA[code]
	if extra then
		return extra
	elseif zeroWidth(code) then
		return 0
	elseif code >= 0x2190 then
		return EMOJI -- arrows, symbols, dingbats (✓ ✨ ⚡) and pictographs
	end
	return UNKNOWN
end

-- Width of `text` at em size `size` (UI units). Invalid UTF-8 counts byte by byte as unknown letters.
function TextFit.width(text: string, size: number): number
	local total = 0
	local ok = pcall(function()
		for _, code in utf8.codes(text) do
			total += advance(code)
		end
	end)
	if not ok then
		total = #text * UNKNOWN
	end
	return total / 1000 * size
end

-- Greedy word wrap at em size `size` into lines no wider than `boxWidth`; nil when a single word is wider.
function TextFit.wrap(text: string, size: number, boxWidth: number): { string }?
	local lines: { string } = {}
	local spaceWidth = TextFit.width(" ", size)
	for paragraph in string.gmatch(text .. "\n", "([^\n]*)\n") do
		local line = ""
		local lineWidth = 0
		for word in string.gmatch(paragraph, "%S+") do
			local wordWidth = TextFit.width(word, size)
			if wordWidth > boxWidth then
				return nil
			end
			if line == "" then
				line, lineWidth = word, wordWidth
			elseif lineWidth + spaceWidth + wordWidth <= boxWidth then
				line ..= " " .. word
				lineWidth += spaceWidth + wordWidth
			else
				table.insert(lines, line)
				line, lineWidth = word, wordWidth
			end
		end
		table.insert(lines, line)
	end
	return lines
end

-- True when `text` fits a `boxWidth` x `boxHeight` box at em size `size`: on one line, or wrapped.
function TextFit.fits(text: string, size: number, boxWidth: number, boxHeight: number, wrapped: boolean): boolean
	if size <= 0 or boxWidth <= 0 or boxHeight <= 0 then
		return false
	end
	if not wrapped then
		return TextFit.width(text, size) <= boxWidth and size * TextFit.LINE_HEIGHT <= boxHeight
	end
	local lines = TextFit.wrap(text, size, boxWidth)
	return lines ~= nil and #lines * size * TextFit.LINE_HEIGHT <= boxHeight
end

-- The size TextScaled picks: the largest whole size (at most `maxSize`, default 100) that fits; 0 when even 1 does
-- not.
function TextFit.fit(text: string, boxWidth: number, boxHeight: number, wrapped: boolean, maxSize: number?): number
	local high = math.floor(math.min(maxSize or TextFit.MAX_SIZE, TextFit.MAX_SIZE))
	-- Fitting is monotonic in the size, so search.
	local low = 0
	while low < high do
		local mid = math.ceil((low + high) / 2)
		if TextFit.fits(text, mid, boxWidth, boxHeight, wrapped) then
			low = mid
		else
			high = mid - 1
		end
	end
	return low
end

-- Lines `text` takes when wrapped at `size` in `boxWidth` (math.huge when a word does not fit).
function TextFit.lineCount(text: string, size: number, boxWidth: number): number
	local lines = TextFit.wrap(text, size, boxWidth)
	return if lines then #lines else math.huge
end

return TextFit
