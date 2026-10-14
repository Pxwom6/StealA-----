--!strict
--[[
	Redeem codes (the list: server/Codes.luau, server-only; the rules: Logic/CodeRules). The RedeemCode intent carries
	what the player typed. The server tidies it up (any case, spaces around it), checks the code exists, has not
	expired and was not used on this account, then pays: cash sized from the player's steady income like a cash pack,
	or a Snackling on a free podium (a full base leaves the code unused and says so). The flag `code_<CODE>` is set
	before paying, so a code can never pay twice. Every answer is a toast; analytics logs "code_redeemed".
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local GameData = require(ReplicatedStorage.Shared.GameData)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)
local CodeRules = require(ReplicatedStorage.Shared.Logic.CodeRules)
local EconomyMath = require(ReplicatedStorage.Shared.Logic.EconomyMath)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local Types = require(ReplicatedStorage.Shared.Types)
local Codes = require(script.Parent.Parent.Codes) :: Types.CodesConfig
local Analytics = require(script.Parent.Analytics)
local EconomyService = require(script.Parent.EconomyService)
local Remotes = require(script.Parent.Remotes)
local Sessions = require(script.Parent.Sessions)

local CodeService = {}

-- The toast for each refusal (Theme.text keys).
local REFUSALS: { [string]: string } = {
	invalid = "codeInvalid",
	unknown = "codeUnknown",
	expired = "codeExpired",
	used = "codeUsed",
}

local function refuse(player: Player, key: string)
	Remotes.notify(player, (Theme.text :: any)[key] or Theme.text.codeUnknown, "error")
end

local function onRedeem(player: Player, typed: unknown)
	local session = Sessions.get(player)
	if session == nil then
		return
	end
	local def, code, refusal = CodeRules.check(Codes, typed, session.data.flags, os.time())
	if def == nil or code == nil then
		refuse(player, REFUSALS[refusal or "invalid"])
		return
	end
	local reward = def.reward
	if reward.kind == "creature" then
		local creature = GameData.catalog.creatures[reward.creatureId]
		if creature == nil then
			refuse(player, "codeUnknown")
			return
		end
		if EconomyService.freePodium(session) == nil then
			refuse(player, "codeBaseFull")
			return
		end
		session.data.flags[CodeRules.flagKey(code)] = true
		EconomyService.giveCreature(session, creature.id, reward.variant)
		Remotes.notify(
			player,
			Format.template(
				Theme.text.codeRedeemedCreature,
				{ creature = GameData.displayName(creature, reward.variant) }
			),
			"success"
		)
	else
		session.data.flags[CodeRules.flagKey(code)] = true
		local amount = EconomyMath.cashPackAmount(
			session.packIncome,
			{ incomeSeconds = reward.incomeSeconds, minimum = reward.minimum }
		)
		EconomyService.addCash(session, amount, "Gameplay", "Code")
		Remotes.notify(
			player,
			Format.template(Theme.text.codeRedeemedCash, { amount = UiTheme.cash(amount) }),
			"success"
		)
	end
	Analytics.custom(session, "code_redeemed", nil, { code })
	print(`[Codes] {player.Name} redeemed {code}`)
end

function CodeService.start()
	for _, problem in CodeRules.validate(Codes, GameData.catalog.creatures, GameData.catalog.mutations) do
		warn(`[Codes] config problem: {problem}`)
	end
	Remotes.onIntent("RedeemCode", onRedeem)
end

return CodeService
