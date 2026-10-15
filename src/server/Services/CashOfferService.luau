--!strict
--[[
	"Need $X more?" offers. Called where a purchase fails for lack of cash (BeltService buying off the belt,
	EconomyService adding a podium): instead of only "Not enough cash!", the player may be offered the cheapest of the
	small cash packs that covers the gap (Logic/CashOfferRules), sized from their steady income exactly like the
	store card.

	The offer is a suggestion only: the client shows a small card with the pack's Robux price and a buy button that
	opens Roblox's own purchase prompt. The cash itself is granted by MonetizationService's receipt handler, quoted
	at purchase time like any other pack. Never during the first-time tutorial or a player's first
	Monetization.cashOffer.minPlaySeconds of play, at most one offer per cooldownSeconds, and never for a gap the
	player's income covers within smallGapSeconds: then the toast says how many seconds of income are missing.
	Otherwise (or when no small pack covers the gap) the usual toast is shown. CI checks the config
	(CashOfferRules.validate).

	No EconomyService dependency (EconomyService calls this), so the amounts come from the session's cached incomes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local CashOfferRules = require(ReplicatedStorage.Shared.Logic.CashOfferRules)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local Analytics = require(script.Parent.Analytics)
local Remotes = require(script.Parent.Remotes)
local Sessions = require(script.Parent.Sessions)

type Session = Sessions.Session

local CashOfferService = {}

-- A purchase costing `price` just failed because the player has less cash. Shows the offer when one is allowed and
-- a small pack covers the gap; otherwise the "Not enough cash!" toast, with the seconds of income missing when that
-- is only a few.
function CashOfferService.notEnoughCash(session: Session, price: number)
	local now = os.clock()
	local decision = CashOfferRules.decide({
		shortfall = price - session.data.cash,
		income = session.incomePerSecond,
		packIncome = session.packIncome,
		now = now,
		lastOfferAt = session.cashOfferAt,
		inTutorial = session.tutorial ~= nil,
		playSeconds = session.data.stats.playTime,
		allowUnconfigured = RunService:IsStudio(),
	}, Monetization.cashOffer, Monetization.products :: any, Economy.cashPacks :: any)
	local offer = decision.offer
	if offer == nil then
		local wait = decision.waitSeconds
		Remotes.notify(
			session.player,
			if wait then Format.template(Theme.text.notEnoughCashWait, { seconds = wait }) else Theme.text.notEnoughCash,
			"error"
		)
		return
	end
	session.cashOfferAt = now
	Remotes.fire(session.player, "CashOffer", { key = offer.key, amount = offer.amount, shortfall = offer.shortfall })
	Analytics.custom(session, "cash_offer_shown", offer.amount, { offer.key })
end

return CashOfferService
