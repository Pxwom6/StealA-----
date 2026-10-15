--!strict
--[[
	Lights and particles on far-away Snacklings (DECISIONS.md #47): a full server has about 190 PointLights and 200
	ParticleEmitters on podium Snacklings, the biggest rendering cost on low-end phones, and most of them are too far
	away to see. IdleController switches them off beyond `offBeyond` studs from the camera and back on within
	`onWithin`; the gap between the two keeps them from flickering at the edge. Checked every `checkSeconds`.
]]

local Types = require("../Types")

local FxCulling = {}

export type Config = Types.PodiumFxConfig

-- Whether a Snackling's lights and particles show at `distance` studs from the camera, given whether they showed.
function FxCulling.shown(wasShown: boolean, distance: number, cfg: Config): boolean
	if distance ~= distance then
		return wasShown -- NaN: no camera yet
	end
	if wasShown then
		return distance <= cfg.offBeyond
	end
	return distance <= cfg.onWithin
end

-- Problems with the config (empty when valid). Checked by CI.
function FxCulling.validate(cfg: Config): { string }
	local problems: { string } = {}
	if not (cfg.onWithin > 0) then
		table.insert(problems, "podiumFx.onWithin must be above 0")
	end
	if not (cfg.offBeyond > cfg.onWithin) then
		table.insert(problems, "podiumFx.offBeyond must be beyond onWithin (no flicker at the edge)")
	end
	if not (cfg.checkSeconds > 0 and cfg.checkSeconds <= 5) then
		table.insert(problems, "podiumFx.checkSeconds must be in (0, 5]")
	end
	return problems
end

return FxCulling
