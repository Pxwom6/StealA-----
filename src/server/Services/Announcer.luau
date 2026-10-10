--!strict
--[[
	Server-wide announcements: a big banner on every screen plus a system chat line. Used for Mythic/Secret
	spawns and purchases, announced mutations (Rainbow), big steals, rebirths, luck boosts and admin messages — the
	loud social moments.
]]

local Remotes = require(script.Parent.Remotes)

export type Announcement = {
	text: string,
	rarity: string?, -- colours the banner
	color: string?, -- "#RRGGBB": colours the banner instead of the rarity (a mutation's own announcement)
	kind: string?, -- "spawn" | "buy" | "steal" | "rebirth" | "luck" | "admin"
}

local Announcer = {}

function Announcer.broadcast(announcement: Announcement)
	Remotes.fireAll("Announce", announcement)
end

return Announcer
