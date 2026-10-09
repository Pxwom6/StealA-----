--!strict
--[[
	Rebirth formulas and the "what you lose / what you gain" preview shown before confirming.
	Pure: no requires, no Roblox APIs.
]]

export type RebirthConfig = {
	baseCost: number,
	costGrowth: number,
	multiplierPerRebirth: number,
	lockBonusPerRebirth: number,
	maxLockBonus: number,
	maxRebirths: number,
}

export type PreviewInput = {
	cash: number,
	rebirths: number,
	rebirthMultiplier: number,
	creatureCount: number,
	incomePerSecond: number,
	baseLockSeconds: number,
}

export type Preview = {
	canRebirth: boolean,
	reason: string?, -- "max" | "cash"
	cost: number?,
	loseCash: number,
	loseCreatures: number,
	loseIncomePerSecond: number,
	multiplierFrom: number,
	multiplierTo: number,
	lockFrom: number,
	lockTo: number,
}

local RebirthMath = {}

-- Cash needed for the next rebirth, or nil when the cap is reached.
function RebirthMath.cost(rebirths: number, cfg: RebirthConfig): number?
	if rebirths >= cfg.maxRebirths then
		return nil
	end
	return math.floor(cfg.baseCost * cfg.costGrowth ^ rebirths)
end

function RebirthMath.multiplierFor(rebirths: number, cfg: RebirthConfig): number
	return 1 + math.max(0, rebirths) * cfg.multiplierPerRebirth
end

function RebirthMath.lockBonusFor(rebirths: number, cfg: RebirthConfig): number
	return math.min(cfg.maxLockBonus, math.max(0, rebirths) * cfg.lockBonusPerRebirth)
end

function RebirthMath.canRebirth(cash: number, rebirths: number, cfg: RebirthConfig): (boolean, string?)
	local cost = RebirthMath.cost(rebirths, cfg)
	if cost == nil then
		return false, "max"
	end
	if cash < cost then
		return false, "cash"
	end
	return true, nil
end

function RebirthMath.preview(input: PreviewInput, cfg: RebirthConfig): Preview
	local ok, reason = RebirthMath.canRebirth(input.cash, input.rebirths, cfg)
	return {
		canRebirth = ok,
		reason = reason,
		cost = RebirthMath.cost(input.rebirths, cfg),
		loseCash = input.cash,
		loseCreatures = input.creatureCount,
		loseIncomePerSecond = input.incomePerSecond,
		multiplierFrom = input.rebirthMultiplier,
		multiplierTo = math.max(input.rebirthMultiplier, RebirthMath.multiplierFor(input.rebirths + 1, cfg)),
		lockFrom = input.baseLockSeconds + RebirthMath.lockBonusFor(input.rebirths, cfg),
		lockTo = input.baseLockSeconds + RebirthMath.lockBonusFor(input.rebirths + 1, cfg),
	}
end

return RebirthMath
